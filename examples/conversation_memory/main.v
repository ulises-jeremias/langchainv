module main

import context
import json2
import ulises_jeremias.langchainv.chains
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.memory
import ulises_jeremias.langchainv.schema

struct DemoModel {}

fn (_ DemoModel) complete(mut _ctx context.Context, prompt string, _options llms.CallOptions) !string {
	if prompt.contains('Human: My name is Ada.') && prompt.ends_with('Human: What is my name?\nAI:') {
		return 'Your name is Ada.'
	}
	return 'Nice to meet you.'
}

fn main() {
	conversation := memory.new_conversation_buffer('history', 'input', 'output') or { panic(err) }
	chain := chains.new_conversation_chain(DemoModel{}, schema.Memory(conversation)) or { panic(err) }
	mut ctx := context.background()
	first := chains.call(mut ctx, chain, {
		'input': json2.Any('My name is Ada.')
	}) or { panic(err) }
	println((first['output'] or { panic('missing first answer') }).str())
	second := chains.call(mut ctx, chain, {
		'input': json2.Any('What is my name?')
	}) or { panic(err) }
	println((second['output'] or { panic('missing second answer') }).str())
}
