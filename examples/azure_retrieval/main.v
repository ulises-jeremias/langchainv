module main

import context
import json2
import os
import ulises_jeremias.langchainv.chains
import ulises_jeremias.langchainv.embeddings.openai as openai_embeddings
import ulises_jeremias.langchainv.llms.openai as openai_llms
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.vectorstores
import ulises_jeremias.langchainv.vectorstores.azureaisearch as azure_search

fn main() {
	if os.getenv('LANGCHAINV_ALLOW_LIVE_EXAMPLES') != '1' {
		println('Live retrieval is disabled. Read examples/README.md before opting in.')
		return
	}
	openai_api_key := os.getenv('OPENAI_API_KEY').trim_space()
	azure_service := os.getenv('AZURE_SEARCH_SERVICE').trim_space()
	azure_admin_key := os.getenv('AZURE_SEARCH_ADMIN_KEY').trim_space()
	if openai_api_key == '' || azure_service == '' || azure_admin_key == '' {
		eprintln('Set OPENAI_API_KEY, AZURE_SEARCH_SERVICE, and AZURE_SEARCH_ADMIN_KEY.')
		exit(2)
	}
	mut ctx := context.background()
	embedding_client := openai_embeddings.new_default_client(openai_api_key) or { panic(err) }
	embedder := embedding_client.default_embedder() or { panic(err) }
	store := azure_search.new_store(embedder, azure_search.Options{
		endpoint:   'https://${azure_service}.search.windows.net'
		index_name: 'knowledge'
		api_key:    azure_admin_key
	}) or { panic(err) }
	documents := [
		schema.new_document('Returns are accepted within 30 days of delivery.'),
		schema.new_document('Standard shipping takes three to five business days.'),
		schema.new_document('Electronic products include a one-year warranty.'),
	]
	ids := store.add_documents(mut ctx, documents, vectorstores.StoreOptions{
		namespace: 'langchainv-live-example'
	}) or { panic(err) }
	defer {
		store.delete(mut ctx, ids, vectorstores.StoreOptions{}) or {
			eprintln('Could not remove the temporary Azure AI Search example documents.')
		}
	}
	retriever := vectorstores.to_retriever(store, 2, vectorstores.SearchOptions{
		namespace: 'langchainv-live-example'
	}) or { panic(err) }
	answer_model := openai_llms.new_default_client(openai_api_key) or { panic(err) }
	chain := chains.new_retrieval_qa_chain(retriever, answer_model, prompts.StringTemplate{
		template: 'Answer only from the retrieved context. If it does not contain the answer, say you do not know.\n\nContext:\n{context}\n\nQuestion: {question}'
	}, chains.RetrievalQAOptions{
		retrieval: schema.RetrievalOptions{
			k: 2
		}
	}) or { panic(err) }
	outputs := chains.call(mut ctx, chain, {
		'question': json2.Any('How long do I have to return a purchase?')
	}) or { panic(err) }
	println((outputs['answer'] or { panic('missing answer') }).str())
}
