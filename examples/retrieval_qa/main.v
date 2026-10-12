module main

import context
import json2
import ulises_jeremias.langchainv.chains
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.vectorstores

struct DemoEmbedder {}

fn (_ DemoEmbedder) embed_documents(mut _ctx context.Context, texts []string) ![][]f32 {
	return texts.map(embed_text(it))
}

fn (_ DemoEmbedder) embed_query(mut _ctx context.Context, text string) ![]f32 {
	return embed_text(text)
}

struct DemoCompletionModel {}

fn (_ DemoCompletionModel) complete(mut _ctx context.Context, prompt string, _options llms.CallOptions) !string {
	if prompt.contains('within 30 days') {
		return 'Returns are accepted within 30 days of delivery.'
	}
	return 'I do not know based on the retrieved documents.'
}

fn embed_text(text string) []f32 {
	lower := text.to_lower()
	return [f32(if lower.contains('return') { 1 } else { 0 }), f32(if lower.contains('ship') {
		1
	} else {
		0
	}), f32(if lower.contains('warranty') { 1 } else { 0 })]
}

fn main() {
	mut ctx := context.background()
	mut store := vectorstores.new_in_memory_vector_store(DemoEmbedder{}, 8) or { panic(err) }
	documents := [
		schema.new_document('Returns are accepted within 30 days of delivery.'),
		schema.new_document('Standard shipping takes three to five business days.'),
		schema.new_document('Electronic products include a one-year warranty.'),
	]
	store.add_documents(mut ctx, documents, vectorstores.StoreOptions{}) or { panic(err) }
	retriever := vectorstores.to_retriever(store, 1, vectorstores.SearchOptions{}) or { panic(err) }
	chain := chains.new_retrieval_qa_chain(retriever, DemoCompletionModel{}, prompts.StringTemplate{
		template: 'Answer only from this context:\n{context}\n\nQuestion: {question}'
	}, chains.RetrievalQAOptions{
		retrieval: schema.RetrievalOptions{
			k: 1
		}
	}) or { panic(err) }
	outputs := chains.call(mut ctx, chain, {
		'question': json2.Any('Can I return an order?')
	}) or { panic(err) }
	println((outputs['answer'] or { panic('missing answer') }).str())
}
