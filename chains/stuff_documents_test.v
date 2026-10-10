module chains

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema

@[heap]
struct StuffCompletionState {
mut:
	prompts []string
}

struct StuffCompletionFixture {
	state &StuffCompletionState
}

fn (model StuffCompletionFixture) complete(mut _ctx context.Context, prompt string, _options llms.CallOptions) !string {
	mut state := model.state
	state.prompts << prompt
	return 'combined answer'
}

fn new_stuff_fixture(state &StuffCompletionState) !StuffDocumentsChain {
	inner := new_llm_chain(StuffCompletionFixture{
		state: state
	}, prompts.StringTemplate{
		template: 'Context: {context}\nQuestion: {question}'
	}, 'answer')!
	return new_stuff_documents_chain(inner, StuffDocumentsOptions{})
}

fn test_stuff_documents_joins_and_passes_through_prompt_inputs() {
	mut model_state := &StuffCompletionState{}
	chain := new_stuff_fixture(model_state) or { panic(err) }
	mut ctx := context.background()
	inputs := {
		'input_documents': documents_value([
			schema.new_document('first')
			schema.new_document('second'),
		])
		'question':        json2.Any('what?')
	}
	outputs := call(mut ctx, chain, inputs) or { panic(err) }
	assert (outputs['answer'] or { panic('missing output') }).str() == 'combined answer'
	assert chain.input_keys() == ['input_documents', 'question']
	assert chain.output_keys() == ['answer']
	assert model_state.prompts == ['Context: first\n\nsecond\nQuestion: what?']
}

fn test_stuff_documents_supports_custom_keys_separator_and_limits() {
	mut model_state := &StuffCompletionState{}
	inner := new_llm_chain(StuffCompletionFixture{
		state: model_state
	}, prompts.StringTemplate{
		template: '{evidence} {query}'
	}, 'result') or { panic(err) }
	chain := new_stuff_documents_chain(inner, StuffDocumentsOptions{
		input_key:          'sources'
		document_variable:  'evidence'
		separator:          ' | '
		max_documents:      2
		max_document_bytes: 16
	}) or { panic(err) }
	mut ctx := context.background()
	call(mut ctx, chain, {
		'sources': documents_value([schema.new_document('one'), schema.new_document('two')])
		'query':   json2.Any('q')
	}) or { panic(err) }
	assert model_state.prompts == ['one | two q']
}

fn test_stuff_documents_rejects_invalid_document_items_before_model_call() {
	mut model_state := &StuffCompletionState{}
	chain := new_stuff_fixture(model_state) or { panic(err) }
	mut ctx := context.background()
	call(mut ctx, chain, {
		'input_documents': json2.Any([json2.Any({
			'content': json2.Any('missing page_content')
		})])
		'question':        json2.Any('q')
	}) or {
		assert err.msg().contains('page_content')
		assert model_state.prompts.len == 0
		return
	}
	assert false, 'expected malformed document to fail'
}

fn test_stuff_documents_enforces_document_count_and_context_bytes() {
	mut state := &StuffCompletionState{}
	chain := new_stuff_documents_chain(new_llm_chain(StuffCompletionFixture{
		state: state
	}, prompts.StringTemplate{
		template: '{context}'
	}, 'answer') or { panic(err) }, StuffDocumentsOptions{
		max_documents:      1
		max_document_bytes: 4
	}) or { panic(err) }
	mut ctx := context.background()
	call(mut ctx, chain, {
		'input_documents': documents_value([schema.new_document('one'), schema.new_document('two')])
	}) or {
		assert err.msg().contains('document count')
		return
	}
	assert false, 'expected too many documents to fail'
}

fn test_stuff_documents_rejects_oversized_combined_content() {
	mut state := &StuffCompletionState{}
	chain := new_stuff_documents_chain(new_llm_chain(StuffCompletionFixture{
		state: state
	}, prompts.StringTemplate{
		template: '{context}'
	}, 'answer') or { panic(err) }, StuffDocumentsOptions{
		max_document_bytes: 4
	}) or { panic(err) }
	mut ctx := context.background()
	call(mut ctx, chain, {
		'input_documents': documents_value([schema.new_document('hello')])
	}) or {
		assert err.msg().contains('byte limit')
		assert state.prompts.len == 0
		return
	}
	assert false, 'expected combined content to exceed configured byte limit'
}
