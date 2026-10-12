module main

import context
import json2
import ulises_jeremias.langchainv.agents
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.tools

@[heap]
struct DemoModelState {
mut:
	calls int
}

struct DemoModel {
	state &DemoModelState
}

fn (model DemoModel) generate_content(mut _ctx context.Context, messages []schema.Message, _options llms.CallOptions) !llms.Response {
	mut state := model.state
	state.calls++
	if state.calls == 1 {
		return llms.Response{
			choices: [llms.Choice{
				tool_calls: [schema.ToolCall{
					id:            'call-1'
					call_type:     'function'
					function_call: schema.FunctionCall{
						name:      'calculator'
						arguments: '{"expression":"6 * 7"}'
					}
				}]
			}]
		}
	}
	if messages.len > 0 && messages[messages.len - 1].parts.len > 0 {
		last_part := messages[messages.len - 1].parts[0]
		match last_part {
			schema.ToolResult {
				if last_part.content == '42' {
					return llms.Response{
						choices: [llms.Choice{
							content: '6 times 7 is 42.'
						}]
					}
				}
			}
			else {}
		}
	}
	return error('expected the calculator result 42')
}

fn main() {
	model := DemoModel{
		state: &DemoModelState{}
	}
	agent := agents.new_openai_functions_agent(model, [tools.new_calculator()], agents.OpenAIFunctionsAgentOptions{
		input_keys:    ['question']
		system_prompt: 'Use the calculator when a question needs arithmetic.'
	}) or { panic(err) }
	executor := agents.new_executor(agent, agents.ExecutorOptions{
		max_iterations:            3
		return_intermediate_steps: true
	}) or { panic(err) }
	mut ctx := context.background()
	result := executor.call(mut ctx, {
		'question': json2.Any('What is 6 times 7?')
	}) or { panic(err) }
	println((result['output'] or { panic('missing answer') }).str())
}
