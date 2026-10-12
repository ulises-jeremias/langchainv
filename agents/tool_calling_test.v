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

fn test_openai_functions_agent_uses_default_keys_and_custom_messages() {
	mut state := &FixtureModelState{
		responses: [llms.Response{
			choices: [llms.Choice{
				content: 'final answer'
			}]
		}]
	}
	agent := new_openai_functions_agent(FixtureModel{
		state: state
	}, [ToolCallingEchoTool{}], OpenAIFunctionsAgentOptions{
		system_prompt:  'Use the available functions when needed.'
		extra_messages: [schema.text_message(.ai, 'Earlier assistant guidance.')]
		call_options:   llms.CallOptions{
			max_tokens: 32
		}
	}) or { panic(err) }
	assert agent.input_keys() == ['input']
	assert agent.output_keys() == ['output']
	assert agent.get_tools().len == 1
	mut ctx := context.background()
	result := agent.plan(mut ctx, [], {
		'input': 'say hello'
	}, llms.CallOptions{}) or { panic(err) }
	assert state.messages[0].len == 3
	assert state.messages[0][0].text().contains('Use the available functions')
	assert state.messages[0][1].text() == 'Earlier assistant guidance.'
	assert state.messages[0][2].text() == 'input: say hello'
	assert state.options[0].tools.len == 1
	assert state.options[0].max_tokens == 32
	if finish := result.finish {
		assert (finish.return_values['output'] or { panic('missing output') }) == json2.Any('final answer')
	} else {
		assert false, 'expected a final answer'
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

fn test_tool_calling_agent_replays_parallel_calls_as_one_assistant_message() {
	mut state := &FixtureModelState{
		responses: [
			llms.Response{
				choices: [llms.Choice{
					tool_calls: [
						schema.ToolCall{
							id:            'tool-call-a'
							call_type:     'function'
							function_call: schema.FunctionCall{
								name:      'echo'
								arguments: 'first'
							}
						}
						schema.ToolCall{
							id:            'tool-call-b'
							call_type:     'function'
							function_call: schema.FunctionCall{
								name:      'echo'
								arguments: 'second'
							}
						},
					]
				}]
			}
			llms.Response{
				choices: [llms.Choice{
					content: 'done'
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
	executor.call(mut ctx, {
		'question': json2.Any('run both')
	}) or { panic(err) }

	replayed := state.messages[1]
	assert replayed.len == 5
	assert replayed[2].role == .ai
	assert replayed[2].parts.len == 2
	assert replayed[3].role == .tool
	assert replayed[4].role == .tool
	first_result := replayed[3].parts[0]
	match first_result {
		schema.ToolResult {
			assert first_result.call_id == 'tool-call-a'
			assert first_result.content == 'echo:first'
		}
		else {
			assert false, 'expected the first tool result after the assistant batch'
		}
	}
	second_result := replayed[4].parts[0]
	match second_result {
		schema.ToolResult {
			assert second_result.call_id == 'tool-call-b'
			assert second_result.content == 'echo:second'
		}
		else {
			assert false, 'expected the second tool result after the assistant batch'
		}
	}
	first_call := replayed[2].parts[0]
	match first_call {
		schema.ToolCall {
			assert first_call.id == 'tool-call-a'
		}
		else {
			assert false, 'expected the first assistant tool call'
		}
	}
	second_call := replayed[2].parts[1]
	match second_call {
		schema.ToolCall {
			assert second_call.id == 'tool-call-b'
		}
		else {
			assert false, 'expected the second assistant tool call'
		}
	}
}

fn test_tool_calling_agent_normalizes_legacy_single_argument_function_input() {
	mut state := &FixtureModelState{
		responses: [
			llms.Response{
				choices: [llms.Choice{
					function_call: schema.FunctionCall{
						name:      'echo'
						arguments: '{"__arg1":"hello"}'
					}
				}]
			}
			llms.Response{
				choices: [llms.Choice{
					content: 'done'
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
		'question': json2.Any('echo hello')
	}) or { panic(err) }
	assert (result['output'] or { panic('missing output') }) == json2.Any('done')
	assert state.messages[1].len == 4
	legacy_call := state.messages[1][2].parts[0]
	match legacy_call {
		schema.ToolCall {
			assert legacy_call.id == 'agent-step-0'
		}
		else {
			assert false, 'expected the legacy call to be replayed as a tool call'
		}
	}
	legacy_result := state.messages[1][3].parts[0]
	match legacy_result {
		schema.ToolResult {
			assert legacy_result.call_id == 'agent-step-0'
			assert legacy_result.content == 'echo:hello'
		}
		else {
			assert false, 'expected the matching result for the legacy call'
		}
	}
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
