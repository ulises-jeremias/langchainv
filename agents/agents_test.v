module agents

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.tools

struct SequenceAgent {
	state &SequenceAgentState
}

struct SequenceAgentState {
mut:
	plans       []PlanResult
	calls       int
	step_counts []int
}

fn (agent SequenceAgent) plan(mut _ctx context.Context, steps []schema.AgentStep, _inputs map[string]string, _options llms.CallOptions) !PlanResult {
	mut state := agent.state
	state.calls++
	state.step_counts << steps.len
	if state.calls > state.plans.len {
		return error('unexpected plan call')
	}
	return state.plans[state.calls - 1]
}

fn (_agent SequenceAgent) input_keys() []string {
	return ['question']
}

fn (_agent SequenceAgent) output_keys() []string {
	return ['output']
}

fn (_agent SequenceAgent) get_tools() []tools.Tool {
	return [EchoTool{}]
}

struct EchoTool {}

fn (_tool EchoTool) spec() tools.ToolSpec {
	return tools.ToolSpec{
		name:        'echo'
		description: 'Returns the provided text'
		parameters:  json2.Any(map[string]json2.Any{})
	}
}

fn (_tool EchoTool) call(mut _ctx context.Context, input string) !string {
	return 'echo:${input}'
}

fn test_executor_runs_tool_then_finishes_with_intermediate_steps() {
	mut state := &SequenceAgentState{
		plans: [
			PlanResult{
				actions: [schema.AgentAction{
					tool:       'ECHO'
					tool_input: 'hello\nObservation:'
					tool_id:    'call-1'
				}]
			},
			PlanResult{
				finish: schema.AgentFinish{
					return_values: {
						'output': json2.Any('done')
					}
				}
			},
		]
	}
	agent := SequenceAgent{
		state: state
	}
	executor := new_executor(agent, ExecutorOptions{
		max_iterations:            2
		return_intermediate_steps: true
	}) or { panic(err) }
	mut ctx := context.background()
	result := executor.call(mut ctx, {
		'question': json2.Any('say hello')
	}) or { panic(err) }
	assert (result['output'] or { panic('missing output') }) == json2.Any('done')
	steps := result['intermediate_steps'] or { panic('missing intermediate steps') }
	assert steps is []json2.Any
	if steps is []json2.Any {
		assert steps.len == 1
	} else {
		assert false, 'intermediate steps should be a JSON array'
	}
	assert state.calls == 2
	assert state.step_counts == [0, 1]
}

fn test_executor_reports_unknown_tool_as_an_observation() {
	mut state := &SequenceAgentState{
		plans: [
			PlanResult{
				actions: [schema.AgentAction{
					tool:       'missing'
					tool_input: '{}'
				}]
			},
			PlanResult{
				finish: schema.AgentFinish{
					return_values: {
						'output': json2.Any('recovered')
					}
				}
			},
		]
	}
	executor := new_default_executor(SequenceAgent{
		state: state
	}) or { panic(err) }
	mut ctx := context.background()
	result := executor.call(mut ctx, {
		'question': json2.Any('try missing')
	}) or { panic(err) }
	assert (result['output'] or { panic('missing output') }) == json2.Any('recovered')
}

fn test_executor_rejects_non_string_inputs_before_planning() {
	mut state := &SequenceAgentState{}
	executor := new_default_executor(SequenceAgent{
		state: state
	}) or { panic(err) }
	mut ctx := context.background()
	executor.call(mut ctx, {
		'question': json2.Any(42)
	}) or {
		assert err.msg().contains('must be a string')
		assert state.calls == 0
		return
	}
	assert false, 'expected a type error'
}

fn test_executor_rejects_missing_declared_inputs() {
	mut state := &SequenceAgentState{}
	executor := new_default_executor(SequenceAgent{
		state: state
	}) or { panic(err) }
	mut ctx := context.background()
	executor.call(mut ctx, map[string]json2.Any{}) or {
		assert err.msg().contains('missing required agent input')
		assert state.calls == 0
		return
	}
	assert false, 'expected a missing input error'
}

fn test_executor_enforces_iteration_limit_and_bound() {
	new_executor(SequenceAgent{
		state: &SequenceAgentState{}
	}, ExecutorOptions{
		max_iterations: hard_max_iterations + 1
	}) or {
		assert err.msg().contains('max_iterations')
		return
	}
	assert false, 'expected an oversized iteration limit to fail'
}

fn test_executor_stops_when_iteration_limit_is_reached() {
	mut state := &SequenceAgentState{
		plans: [PlanResult{
			actions: [schema.AgentAction{
				tool:       'echo'
				tool_input: 'again'
			}]
		}]
	}
	executor := new_executor(SequenceAgent{
		state: state
	}, ExecutorOptions{
		max_iterations: 1
	}) or { panic(err) }
	mut ctx := context.background()
	executor.call(mut ctx, {
		'question': json2.Any('never finish')
	}) or {
		assert err.msg().contains('did not finish')
		return
	}
	assert false, 'expected iteration limit error'
}

fn test_strip_observation_suffix_removes_only_the_exact_suffix() {
	assert strip_observation_suffix('hello\nObservation:') == 'hello'
	assert strip_observation_suffix('addition') == 'addition'
	assert strip_observation_suffix('hello\nObservation: extra') == 'hello\nObservation: extra'
}
