module agents

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.tools

struct ToolCallingEchoTool {}

fn (_tool ToolCallingEchoTool) spec() tools.ToolSpec {
	return tools.ToolSpec{
		name:        'echo'
		description: 'Returns the provided text'
		parameters:  json2.Any(map[string]json2.Any{})
	}
}

fn (_tool ToolCallingEchoTool) call(mut _ctx context.Context, input string) !string {
	return 'echo:${input}'
}

struct FixtureModel {
	state &FixtureModelState
}

struct FixtureModelState {
mut:
	responses []llms.Response
	messages  [][]schema.Message
	options   []llms.CallOptions
}

fn (model FixtureModel) generate_content(mut _ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	mut state := model.state
	if state.messages.len >= state.responses.len {
		return error('unexpected model call')
	}
	state.messages << messages.clone()
	state.options << options
	return state.responses[state.messages.len - 1]
}

fn fixture_tool_response() llms.Response {
	return llms.Response{
		choices: [llms.Choice{
			tool_calls: [schema.ToolCall{
				id:            'tool-call-1'
				call_type:     'function'
				function_call: schema.FunctionCall{
					name:      'echo'
					arguments: '{"text":"hello"}'
				}
			}]
		}]
	}
}

fn test_tool_calling_agent_maps_model_tool_requests_to_actions() {
	mut state := &FixtureModelState{
		responses: [fixture_tool_response()]
	}
	agent := new_tool_calling_agent(FixtureModel{
		state: state
	}, [ToolCallingEchoTool{}], ToolCallingAgentOptions{
		input_keys:    ['question']
		system_prompt: 'Use tools when useful.'
		call_options:  llms.CallOptions{
			max_tokens: 64
		}
	}) or { panic(err) }
	mut ctx := context.background()
	result := agent.plan(mut ctx, [], {
		'question': 'say hello'
	}, llms.CallOptions{}) or { panic(err) }
	assert result.actions.len == 1
	assert result.actions[0].tool == 'echo'
	assert result.actions[0].tool_id == 'tool-call-1'
	assert result.actions[0].tool_input == '{"text":"hello"}'
	assert state.options[0].tools.len == 1
	assert state.options[0].tools[0].name == 'echo'
	assert state.options[0].max_tokens == 64
	assert state.messages[0][0].text().contains('Use tools when useful.')
	assert state.messages[0][1].text() == 'question: say hello'
}

fn test_tool_calling_agent_maps_text_to_finish() {
	mut state := &FixtureModelState{
		responses: [llms.Response{
			choices: [llms.Choice{
				content: 'final answer'
			}]
		}]
	}
	agent := new_tool_calling_agent(FixtureModel{
		state: state
	}, [ToolCallingEchoTool{}], ToolCallingAgentOptions{
		input_keys: ['question']
	}) or { panic(err) }
	mut ctx := context.background()
	result := agent.plan(mut ctx, [], {
		'question': 'answer me'
	}, llms.CallOptions{}) or { panic(err) }
	assert result.actions.len == 0
	if finish := result.finish {
		assert (finish.return_values['output'] or { panic('missing output') }) == json2.Any('final answer')
	} else {
		assert false, 'expected a terminal finish'
	}
}

fn test_tool_calling_agent_replays_tool_history_through_executor() {
	mut state := &FixtureModelState{
		responses: [
			fixture_tool_response(),
			llms.Response{
				choices: [llms.Choice{
					content: 'echo:hello'
				}]
			},
		]
	}
	agent := new_tool_calling_agent(FixtureModel{
		state: state
	}, [ToolCallingEchoTool{}], ToolCallingAgentOptions{
		input_keys: ['question']
	}) or { panic(err) }
	executor := new_executor(agent, ExecutorOptions{
		max_iterations: 2
	}) or { panic(err) }
	mut ctx := context.background()
	result := executor.call(mut ctx, {
		'question': json2.Any('say hello')
	}) or { panic(err) }
	assert (result['output'] or { panic('missing output') }) == json2.Any('echo:hello')
	assert state.messages.len == 2
	assert state.messages[1].len == 4
	assert state.messages[1][2].role == .ai
	assert state.messages[1][3].role == .tool
}

fn test_tool_calling_agent_rejects_duplicate_tools() {
	mut state := &FixtureModelState{}
	new_tool_calling_agent(FixtureModel{
		state: state
	}, [ToolCallingEchoTool{}, ToolCallingEchoTool{}], ToolCallingAgentOptions{
		input_keys: ['question']
	}) or {
		assert err.msg().contains('unique')
		return
	}
	assert false, 'expected duplicate tool names to fail'
}

fn test_tool_calling_agent_executor_rejects_missing_inputs_without_model_call() {
	mut state := &FixtureModelState{}
	agent := new_tool_calling_agent(FixtureModel{
		state: state
	}, [ToolCallingEchoTool{}], ToolCallingAgentOptions{
		input_keys: ['question']
	}) or { panic(err) }
	executor := new_default_executor(agent) or { panic(err) }
	mut ctx := context.background()
	executor.call(mut ctx, map[string]json2.Any{}) or {
		assert err.msg().contains('missing required agent input')
		assert state.messages.len == 0
		return
	}
	assert false, 'expected missing input validation to fail'
}
