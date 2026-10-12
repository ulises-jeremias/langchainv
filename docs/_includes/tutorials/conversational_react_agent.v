module main

import context
import json2
import ulises_jeremias.langchainv.agents
import ulises_jeremias.langchainv.chains
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.memory
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.tools

struct ConversationDemoModel {}

fn (_ ConversationDemoModel) complete(mut _ctx context.Context, prompt string, _options llms.CallOptions) !string {
	if prompt.contains('Human: My name is Ada.') {
		return 'Final Answer: Your name is Ada.'
	}
	return 'Final Answer: I will remember your name.'
}

struct ConversationDemoTool {}

fn (_ ConversationDemoTool) spec() tools.ToolSpec {
	return tools.ToolSpec{
		name:        'echo'
		description: 'Returns its input unchanged'
		parameters:  json2.Any(map[string]json2.Any{})
	}
}

fn (_ ConversationDemoTool) call(mut _ctx context.Context, input string) !string {
	return input
}

fn main() {
	agent := agents.new_conversational_react_agent(ConversationDemoModel{}, [ConversationDemoTool{}],
		agents.ReactOptions{}) or { panic(err) }
	chat_memory := memory.new_conversation_buffer('history', 'input', 'output') or { panic(err) }
	executor := agents.new_executor(agent, agents.ExecutorOptions{
		memory: chat_memory
	}) or { panic(err) }
	mut ctx := context.background()
	first := chains.call(mut ctx, executor, {
		'input': json2.Any('My name is Ada.')
	}) or { panic(err) }
	println((first['output'] or { panic('missing first answer') }).str())
	second := chains.call(mut ctx, executor, {
		'input': json2.Any('What is my name?')
	}) or { panic(err) }
	println((second['output'] or { panic('missing second answer') }).str())
}
