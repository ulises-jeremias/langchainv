module agents

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.tools

struct FlakyAgent {
	state &FlakyAgentState
}

struct FlakyAgentState {
mut:
	calls       int
	failures    int
	steps_seen  []schema.AgentStep
	finish_text string
}

fn (agent FlakyAgent) plan(mut _ctx context.Context, steps []schema.AgentStep, _inputs map[string]string, _options llms.CallOptions) !PlanResult {
	mut state := agent.state
	state.calls++
	if state.calls <= state.failures {
		return error('model returned neither an action nor a final answer')
	}
	state.steps_seen = steps.clone()
	return PlanResult{
		finish: schema.AgentFinish{
			return_values: {
				'output': json2.Any(state.finish_text)
			}
		}
	}
}

fn (_agent FlakyAgent) input_keys() []string {
	return ['question']
}

fn (_agent FlakyAgent) output_keys() []string {
	return ['output']
}

fn (_agent FlakyAgent) get_tools() []tools.Tool {
	return [ParsingEchoTool{}]
}

struct ParsingEchoTool {}

fn (_tool ParsingEchoTool) spec() tools.ToolSpec {
	return tools.ToolSpec{
		name:        'echo'
		description: 'Returns the provided text'
		parameters:  json2.Any(map[string]json2.Any{})
	}
}

fn (_tool ParsingEchoTool) call(mut _ctx context.Context, input string) !string {
	return 'echo:${input}'
}

fn test_executor_recovers_from_plan_error_when_enabled() {
	mut state := &FlakyAgentState{
		failures:    1
		finish_text: 'recovered'
	}
	executor := new_executor(FlakyAgent{
		state: state
	}, ExecutorOptions{
		max_iterations:        3
		handle_parsing_errors: true
	}) or { panic(err) }
	mut ctx := context.background()
	result := executor.call(mut ctx, {
		'question': json2.Any('hello')
	}) or { panic(err) }
	assert (result['output'] or { panic('missing output') }) == json2.Any('recovered')
	assert state.calls == 2
	assert state.steps_seen.len == 1
	assert state.steps_seen[0].action.tool == '_invalid_output'
	assert state.steps_seen[0].observation.contains('Invalid or incomplete response')
}

fn test_executor_fails_fast_on_plan_error_by_default() {
	mut state := &FlakyAgentState{
		failures:    1
		finish_text: 'unused'
	}
	executor := new_executor(FlakyAgent{
		state: state
	}, ExecutorOptions{
		max_iterations: 3
	}) or { panic(err) }
	mut ctx := context.background()
	executor.call(mut ctx, {
		'question': json2.Any('hello')
	}) or {
		assert err.msg().contains('agent planning failed')
		assert state.calls == 1
		return
	}
	assert false, 'expected the plan error to fail the call'
}

fn test_executor_spends_iterations_on_repeated_plan_errors() {
	mut state := &FlakyAgentState{
		failures:    10
		finish_text: 'unused'
	}
	executor := new_executor(FlakyAgent{
		state: state
	}, ExecutorOptions{
		max_iterations:        2
		handle_parsing_errors: true
	}) or { panic(err) }
	mut ctx := context.background()
	executor.call(mut ctx, {
		'question': json2.Any('hello')
	}) or {
		assert err.msg().contains('did not finish within 2 iterations')
		assert state.calls == 2
		return
	}
	assert false, 'expected repeated plan errors to exhaust iterations'
}
