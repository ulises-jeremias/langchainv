module chains

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema

struct RetrievalFixtureState {
mut:
	documents []schema.Document
	queries   []string
	options   []schema.RetrievalOptions
}

struct RetrievalFixture {
	state &RetrievalFixtureState
}

fn (retriever RetrievalFixture) get_relevant_documents(mut _ctx context.Context, query string, options schema.RetrievalOptions) ![]schema.Document {
	mut state := retriever.state
	state.queries << query
	state.options << options
	return state.documents.clone()
}

struct RetrievalCompletionState {
mut:
	prompts []string
}

struct RetrievalCompletionFixture {
	state &RetrievalCompletionState
}

fn (model RetrievalCompletionFixture) complete(mut _ctx context.Context, prompt string, _options llms.CallOptions) !string {
	mut state := model.state
	state.prompts << prompt
	return 'grounded answer'
}

fn test_retrieval_qa_formats_bounded_context_and_returns_answer() {
	mut retriever_state := &RetrievalFixtureState{
		documents: [
			schema.new_document('first source')
			schema.new_document('second source'),
		]
	}
	mut model_state := &RetrievalCompletionState{}
	chain := new_retrieval_qa_chain(RetrievalFixture{
		state: retriever_state
	}, RetrievalCompletionFixture{
		state: model_state
	}, prompts.StringTemplate{
		template: 'Context:\n{context}\nQuestion: {question}'
	}, RetrievalQAOptions{
		retrieval: schema.RetrievalOptions{
			k: 2
		}
	}) or { panic(err) }
	mut ctx := context.background()
	outputs := call(mut ctx, chain, {
		'question': json2.Any('what happened?')
	}) or { panic(err) }
	assert (outputs['answer'] or { panic('missing answer') }).str() == 'grounded answer'
	assert chain.input_keys() == ['question']
	assert chain.output_keys() == ['answer']
	assert retriever_state.queries == ['what happened?']
	assert retriever_state.options[0].k == 2
	assert model_state.prompts == ['Context:\nfirst source\n\nsecond source\nQuestion: what happened?']
}

fn test_retrieval_qa_rejects_oversized_context_before_model_call() {
	mut retriever_state := &RetrievalFixtureState{
		documents: [schema.new_document('content that exceeds the limit')]
	}
	mut model_state := &RetrievalCompletionState{}
	chain := new_retrieval_qa_chain(RetrievalFixture{
		state: retriever_state
	}, RetrievalCompletionFixture{
		state: model_state
	}, prompts.StringTemplate{
		template: '{context} {question}'
	}, RetrievalQAOptions{
		max_context_bytes: 8
	}) or { panic(err) }
	mut ctx := context.background()
	call(mut ctx, chain, {
		'question': json2.Any('q')
	}) or {
		assert err.msg().contains('byte limit')
		assert model_state.prompts.len == 0
		return
	}
	assert false, 'expected retrieved context to exceed its configured limit'
}

fn test_retrieval_qa_rejects_too_many_documents() {
	mut retriever_state := &RetrievalFixtureState{
		documents: [
			schema.new_document('one')
			schema.new_document('two'),
		]
	}
	chain := new_retrieval_qa_chain(RetrievalFixture{
		state: retriever_state
	}, RetrievalCompletionFixture{
		state: &RetrievalCompletionState{}
	}, prompts.StringTemplate{
		template: '{context} {question}'
	}, RetrievalQAOptions{
		max_documents: 1
	}) or { panic(err) }
	mut ctx := context.background()
	call(mut ctx, chain, {
		'question': json2.Any('q')
	}) or {
		assert err.msg().contains('more documents')
		return
	}
	assert false, 'expected too many retrieved documents to fail'
}

fn test_retrieval_qa_can_return_source_documents() {
	mut retriever_state := &RetrievalFixtureState{
		documents: [schema.new_document('source')]
	}
	chain := new_retrieval_qa_chain(RetrievalFixture{
		state: retriever_state
	}, RetrievalCompletionFixture{
		state: &RetrievalCompletionState{}
	}, prompts.StringTemplate{
		template: '{context} {question}'
	}, RetrievalQAOptions{
		return_source_documents: true
	}) or { panic(err) }
	mut ctx := context.background()
	outputs := call(mut ctx, chain, {
		'question': json2.Any('q')
	}) or { panic(err) }
	assert chain.output_keys() == ['answer', 'source_documents']
	returned_documents := (outputs['source_documents'] or { panic('missing source documents') }).as_array()
	assert returned_documents.len == 1
	returned_document := returned_documents[0].as_map()
	page_content := returned_document['page_content'] or { panic('missing page content') }
	assert page_content.str() == 'source'
}
