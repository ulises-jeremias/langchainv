module main

import context
import ulises_jeremias.langchainv.chains
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema

struct EchoCompletionModel {}

fn (_ EchoCompletionModel) complete(mut _ctx context.Context, prompt string, _options llms.CallOptions) !string {
	return prompt
}

fn main() {
	model := EchoCompletionModel{}
	map_chain := chains.new_llm_chain(model, prompts.StringTemplate{
		template: 'Map: {context}'
	}, 'mapped') or { panic(err) }
	reduce_llm_chain := chains.new_llm_chain(model, prompts.StringTemplate{
		template: '{context}'
	}, 'answer') or { panic(err) }
	reduce_chain := chains.new_stuff_documents_chain(reduce_llm_chain,
		chains.StuffDocumentsOptions{}) or { panic(err) }
	chain := chains.new_map_reduce_documents_chain(map_chain, reduce_chain,
		chains.MapReduceDocumentsOptions{
			max_concurrency: 3
		}) or { panic(err) }
	mut ctx := context.background()
	outputs := chains.call(mut ctx, chain, {
		'input_documents': chains.documents_value([
			schema.new_document('First note.')
			schema.new_document('Second note.'),
		])
	}) or { panic(err) }
	println((outputs['answer'] or { panic('missing answer') }).str())
}
