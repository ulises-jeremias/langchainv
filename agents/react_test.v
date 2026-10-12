module agents

import context
import json2
import ulises_jeremias.langchainv.chains
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.memory
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.tools

struct ReactEchoTool {}

fn (_tool ReactEchoTool) spec() tools.ToolSpec {
	return tools.ToolSpec{
		name:        'echo'
		description: 'Returns the input unchanged'
		parameters:  json2.Any(map[string]json2.Any{})
	}
}

fn (_tool ReactEchoTool) call(mut _ctx context.Context, input string) !string {
	return input
}

struct ReactFixtureModel {
	state &ReactFixtureModelState
}

struct ReactFixtureModelState {
mut:
	outputs []string
	prompts []string
	options []llms.CallOptions
}

fn (model ReactFixtureModel) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	options.validate()!
	mut state := model.state
	if state.prompts.len >= state.outputs.len {
		return error('unexpected ReAct model call')
	}
	state.prompts << prompt
	state.options << options
	return state.outputs[state.prompts.len - 1]
}

fn test_react_agent_parses_tool_action_and_final_answer() {
	mut state := &ReactFixtureModelState{
		outputs: [
			'Thought: use echo\nAction: echo\nAction Input: hello',
			'Thought: done\nFinal Answer: hello back',
		]
	}
	agent := new_react_agent(ReactFixtureModel{
		state: state
	}, [ReactEchoTool{}], ReactOptions{}) or { panic(err) }
	mut ctx := context.background()
	first := agent.plan(mut ctx, [], {
		'input': 'say hello'
	}, llms.CallOptions{}) or { panic(err) }
	assert first.actions.len == 1
	assert first.actions[0].tool == 'echo'
	assert first.actions[0].tool_input == 'hello'
	assert first.actions[0].log.contains('Thought: use echo')
	assert state.options[0].stop_words == ['\nObservation:', '\n\tObservation:']
	second := agent.plan(mut ctx, [schema.AgentStep{
		action:      schema.AgentAction{
			tool:       'echo'
			tool_input: 'hello'
			log:        'Thought: use echo\nAction: echo\nAction Input: hello'
		}
		observation: 'hello'
	}], {
		'input': 'say hello'
	}, llms.CallOptions{}) or { panic(err) }
	if finish := second.finish {
		answer := finish.return_values['output'] or { panic('missing ReAct final answer') }
		assert answer == json2.Any('hello back')
	} else {
		assert false, 'expected ReAct agent to finish'
	}
	assert state.prompts[1].contains('Observation: hello')
}

fn test_react_agent_supports_case_insensitive_output_labels_and_custom_options() {
	mut state := &ReactFixtureModelState{
		outputs: ['The answer is: 42']
	}
	agent := new_react_agent(ReactFixtureModel{
		state: state
	}, [ReactEchoTool{}], ReactOptions{
		input_keys:   ['question']
		output_key:   'result'
		call_options: llms.CallOptions{
			max_tokens: 32
			model:      'offline-model'
		}
	}) or { panic(err) }
	mut ctx := context.background()
	result := agent.plan(mut ctx, [], {
		'question': 'life?'
	}, llms.CallOptions{}) or { panic(err) }
	if finish := result.finish {
		answer := finish.return_values['result'] or { panic('missing custom output') }
		assert answer == json2.Any('42')
	} else {
		assert false, 'expected ReAct answer finish'
	}
	assert agent.input_keys() == ['question']
	assert agent.output_keys() == ['result']
	assert state.options[0].max_tokens == 32
	assert state.options[0].model == 'offline-model'
}

fn test_react_agent_runs_through_the_executor_with_tool_observation() {
	mut state := &ReactFixtureModelState{
		outputs: [
			'Thought: call echo\nAction: echo\nAction Input: hello',
			'Thought: the echo tool returned the answer\nFinal Answer: hello',
		]
	}
	agent := new_react_agent(ReactFixtureModel{
		state: state
	}, [ReactEchoTool{}], ReactOptions{}) or { panic(err) }
	mut executor := new_default_executor(agent) or { panic(err) }
	mut ctx := context.background()
	outputs := executor.call(mut ctx, {
		'input': json2.Any('say hello')
	}) or { panic(err) }
	answer := outputs['output'] or { panic('missing ReAct executor answer') }
	assert answer == json2.Any('hello')
	assert state.prompts.len == 2
	assert state.prompts[1].contains('Observation: hello')
}

fn test_conversational_react_agent_loads_and_saves_history_through_chain_memory() {
	mut state := &ReactFixtureModelState{
		outputs: [
			'Final Answer: I will remember your name.',
			'Final Answer: Your name is Ada.',
		]
	}
	agent := new_conversational_react_agent(ReactFixtureModel{
		state: state
	}, [ReactEchoTool{}], ReactOptions{}) or { panic(err) }
	assert agent.input_keys() == ['input', 'history']
	executor := new_executor(agent, ExecutorOptions{
		memory: memory.new_conversation_buffer('history', 'input', 'output') or { panic(err) }
	}) or { panic(err) }
	mut ctx := context.background()
	first := chains.call(mut ctx, executor, {
		'input': json2.Any('My name is Ada.')
	}) or { panic(err) }
	assert (first['output'] or { panic('missing first answer') }).str() == 'I will remember your name.'
	second := chains.call(mut ctx, executor, {
		'input': json2.Any('What is my name?')
	}) or { panic(err) }
	assert (second['output'] or { panic('missing second answer') }).str() == 'Your name is Ada.'
	assert state.prompts[0].contains('Conversation history:\n')
	assert state.prompts[0].contains('Current request:\ninput: My name is Ada.')
	assert state.prompts[1].contains('Human: My name is Ada.\nAI: I will remember your name.')
	assert state.prompts[1].contains('Current request:\ninput: What is my name?')
}

fn test_conversational_react_agent_preserves_custom_inputs_and_adds_history() {
	mut state := &ReactFixtureModelState{
		outputs: ['Final Answer: done']
	}
	agent := new_conversational_react_agent(ReactFixtureModel{
		state: state
	}, [ReactEchoTool{}], ReactOptions{
		input_keys: ['question']
	}) or { panic(err) }
	assert agent.input_keys() == ['question', 'history']
	mut ctx := context.background()
	agent.plan(mut ctx, [], {
		'history':  'Earlier conversation.'
		'question': 'Continue.'
	}, llms.CallOptions{}) or { panic(err) }
	assert state.prompts[0].contains('question: Continue.')
	assert state.prompts[0].contains('Conversation history:\nEarlier conversation.')
}

fn test_react_agent_rejects_missing_action_input() {
	parse_react_output('Thought: act\nAction: echo', 'output') or {
		assert err.msg().contains('Action Input')
		return
	}
	assert false, 'expected malformed ReAct output to fail'
}

fn test_react_agent_rejects_second_action_before_input() {
	parse_react_output('Action: echo\nAction: echo\nAction Input: value', 'output') or {
		assert err.msg().contains('Action Input')
		return
	}
	assert false, 'expected a second action header to invalidate the first action'
}

fn test_react_agent_preserves_control_text_inside_tool_input() {
	parsed_action := parse_react_output("Action: echo\nAction Input: SELECT 'Final Answer: done'",
		'output') or { panic(err) }
	assert parsed_action.actions.len == 1
	assert parsed_action.actions[0].tool_input == "SELECT 'Final Answer: done'"
}

fn test_react_agent_rejects_empty_final_answer() {
	parse_react_output('Final Answer:', 'output') or {
		assert err.msg().contains('empty Final Answer')
		return
	}
	assert false, 'expected an empty final answer to fail'
}

fn test_react_agent_parses_final_answer_after_unicode_text() {
	parsed_unicode_answer := parse_react_output('café\nFinal Answer: listo', 'output') or {
		panic(err)
	}
	if finish := parsed_unicode_answer.finish {
		answer := finish.return_values['output'] or { panic('missing unicode-prefixed answer') }
		assert answer == json2.Any('listo')
	} else {
		assert false, 'expected unicode-prefixed answer finish'
	}
}

fn test_react_agent_recovers_inline_case_insensitive_action_headers() {
	parsed := parse_react_output('I will use a tool. action: echo ACTION INPUT: hello world',
		'output') or { panic(err) }
	assert parsed.actions.len == 1
	assert parsed.actions[0].tool == 'echo'
	assert parsed.actions[0].tool_input == 'hello world'
}

fn test_react_agent_recovers_inline_final_answer_after_prose() {
	parsed := parse_react_output('The result is ready. THE ANSWER IS: 42', 'output') or {
		panic(err)
	}
	if finish := parsed.finish {
		assert (finish.return_values['output'] or { panic('missing recovered answer') }) == json2.Any('42')
	} else {
		assert false, 'expected inline final answer'
	}
}

fn test_react_agent_does_not_parse_control_labels_inside_tool_input() {
	parsed := parse_react_output('Action: echo\nAction Input: Final Answer: done\nAction: keep as data',
		'output') or { panic(err) }
	assert parsed.actions.len == 1
	assert parsed.actions[0].tool_input == 'Final Answer: done\nAction: keep as data'
}

fn test_react_agent_rejects_prompt_bound_below_minimum() {
	mut state := &ReactFixtureModelState{
		outputs: ['Final Answer: done']
	}
	new_react_agent(ReactFixtureModel{
		state: state
	}, [ReactEchoTool{}], ReactOptions{
		max_prompt_bytes: 128
	}) or {
		assert err.msg().contains('prompt byte limit')
		return
	}
	assert false, 'expected undersized ReAct prompt bound to fail'
}

fn test_react_agent_rejects_oversized_input_before_model_call() {
	mut state := &ReactFixtureModelState{
		outputs: ['Final Answer: done']
	}
	bounded_agent := new_react_agent(ReactFixtureModel{
		state: state
	}, [ReactEchoTool{}], ReactOptions{}) or { panic(err) }
	mut ctx := context.background()
	bounded_agent.plan(mut ctx, [], {
		'input': 'x'.repeat(70000)
	}, llms.CallOptions{}) or {
		assert err.msg().contains('byte limit')
		assert state.prompts.len == 0
		return
	}
	assert false, 'expected oversized input to be rejected before calling the model'
}
