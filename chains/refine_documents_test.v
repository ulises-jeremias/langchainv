module chains

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema

@[heap]
struct RefineFixtureState {
mut:
	prompts []string
}

struct RefineFixtureModel {
	state  &RefineFixtureState
	prefix string
}

fn (model RefineFixtureModel) complete(mut _ctx context.Context, prompt string, _options llms.CallOptions) !string {
	mut state := model.state
	state.prompts << prompt
	return '${model.prefix}: ${prompt}'
}

struct RefineFixture {
	chain          RefineDocumentsChain
	initial_state  &RefineFixtureState
	refine_state   &RefineFixtureState
}

fn refine_fixture(options RefineDocumentsOptions) !RefineFixture {
	mut initial_state := &RefineFixtureState{}
	mut refine_state := &RefineFixtureState{}
	initial_chain := new_llm_chain(RefineFixtureModel{
		state:  initial_state
		prefix: 'initial'
	}, prompts.StringTemplate{
		template: '{context} || {question}'
	}, 'initial')!
	refine_chain := new_llm_chain(RefineFixtureModel{
		state:  refine_state
		prefix: 'refined'
	}, prompts.StringTemplate{
		template: '{existing_answer} + {context} || {question}'
	}, 'refined')!
	chain := new_refine_documents_chain(initial_chain, refine_chain, options)!
	return RefineFixture{
		chain:         chain
		initial_state: initial_state
		refine_state:  refine_state
	}
}

fn refine_test_document(content string, source string) schema.Document {
	mut metadata := map[string]json2.Any{}
	metadata['source'] = json2.Any(source)
	return schema.Document{
		page_content: content
		metadata:     metadata
	}
}

fn test_refine_documents_formats_metadata_and_updates_answer_in_order() {
	fixture := refine_fixture(RefineDocumentsOptions{
		document_prompt: prompts.StringTemplate{
			template: '{source}: {page_content}'
		}
	}) or { panic(err) }
	mut ctx := context.background()
	outputs := call(mut ctx, fixture.chain, {
		'input_documents': documents_value([
			refine_test_document('first', 'one.txt')
			refine_test_document('second', 'two.txt'),
		])
		'question':        json2.Any('why?')
	}) or { panic(err) }
	assert (outputs['output'] or { panic('missing output') }).str() == 'refined: initial: one.txt: first || why? + two.txt: second || why?'
	assert fixture.initial_state.prompts == ['one.txt: first || why?']
	assert fixture.refine_state.prompts == ['initial: one.txt: first || why? + two.txt: second || why?']
	assert fixture.chain.input_keys() == ['input_documents', 'question']
	assert fixture.chain.output_keys() == ['output']
}

fn test_refine_documents_rejects_missing_document_metadata_before_model_calls() {
	fixture := refine_fixture(RefineDocumentsOptions{
		document_prompt: prompts.StringTemplate{
			template: '{source}: {page_content}'
		}
	}) or { panic(err) }
	mut ctx := context.background()
	call(mut ctx, fixture.chain, {
		'input_documents': documents_value([schema.new_document('no source')])
		'question':        json2.Any('why?')
	}) or {
		assert err.msg().contains('source')
		assert fixture.initial_state.prompts.len == 0
		return
	}
	assert false, 'expected missing metadata to fail'
}

fn test_refine_documents_rejects_empty_documents_before_model_calls() {
	fixture := refine_fixture(RefineDocumentsOptions{}) or { panic(err) }
	mut ctx := context.background()
	call(mut ctx, fixture.chain, {
		'input_documents': documents_value([]schema.Document{})
		'question':        json2.Any('why?')
	}) or {
		assert err.msg().contains('at least one document')
		assert fixture.initial_state.prompts.len == 0
		return
	}
	assert false, 'expected empty document list to fail'
}

fn test_refine_documents_enforces_count_limit_before_model_calls() {
	fixture := refine_fixture(RefineDocumentsOptions{
		max_documents: 1
	}) or { panic(err) }
	mut ctx := context.background()
	call(mut ctx, fixture.chain, {
		'input_documents': documents_value([
			schema.new_document('one')
			schema.new_document('two'),
		])
		'question':        json2.Any('why?')
	}) or {
		assert err.msg().contains('document count')
		assert fixture.initial_state.prompts.len == 0
		return
	}
	assert false, 'expected document count limit to fail'
}
