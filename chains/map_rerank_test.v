module chains

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema

@[heap]
struct MapRerankFixtureState {
mut:
	prompts []string
}

struct MapRerankFixtureModel {
	state &MapRerankFixtureState
}

fn (model MapRerankFixtureModel) complete(mut _ctx context.Context, prompt string, _options llms.CallOptions) !string {
	mut state := model.state
	state.prompts << prompt
	if prompt.contains('invalid') {
		return 'answer\nScore: high'
	}
	if prompt.contains('low') {
		return 'low answer\nScore: 2'
	}
	if prompt.contains('tie') {
		return 'tie answer\nScore: 9'
	}
	return 'best answer\nScore: 9'
}

struct MapRerankFixture {
	chain MapRerankDocumentsChain
	state &MapRerankFixtureState
}

fn map_rerank_fixture(options MapRerankDocumentsOptions) !MapRerankFixture {
	mut state := &MapRerankFixtureState{}
	llm_chain := new_llm_chain(MapRerankFixtureModel{
		state: state
	}, prompts.StringTemplate{
		template: 'Question: {question}\nPassage: {context}'
	}, 'result')!
	chain := new_map_rerank_documents_chain(llm_chain, options)!
	return MapRerankFixture{
		chain: chain
		state: state
	}
}

fn test_map_rerank_selects_highest_score_and_returns_sorted_steps() {
	fixture := map_rerank_fixture(MapRerankDocumentsOptions{
		return_intermediate_steps: true
	}) or { panic(err) }
	mut ctx := context.background()
	outputs := call(mut ctx, fixture.chain, {
		'input_documents': documents_value([
			schema.new_document('low')
			schema.new_document('best')
			schema.new_document('tie'),
		])
		'question':        json2.Any('which?')
	}) or { panic(err) }
	assert (outputs['result'] or { panic('missing result') }).str() == 'best answer'
	assert fixture.state.prompts == [
		'Question: which?\nPassage: low',
		'Question: which?\nPassage: best',
		'Question: which?\nPassage: tie',
	]
	assert fixture.chain.input_keys() == ['input_documents', 'question']
	assert fixture.chain.output_keys() == ['result', 'intermediate_steps']
	steps_value := outputs['intermediate_steps'] or { panic('missing steps') }
	assert steps_value is []json2.Any
	steps := steps_value as []json2.Any
	assert steps.len == 3
	if item := steps[0] {
		assert item is map[string]json2.Any
		step := item as map[string]json2.Any
		assert (step['answer'] or { panic('missing top answer') }).str() == 'best answer'
		assert (step['score'] or { panic('missing top score') }).str() == '9'
	}
	if item := steps[1] {
		assert item is map[string]json2.Any
		step := item as map[string]json2.Any
		assert (step['answer'] or { panic('missing tied answer') }).str() == 'tie answer'
	} else {
		assert false, 'missing tied result'
	}
}

fn test_map_rerank_rejects_empty_input_without_mapping() {
	fixture := map_rerank_fixture(MapRerankDocumentsOptions{}) or { panic(err) }
	mut ctx := context.background()
	call(mut ctx, fixture.chain, {
		'input_documents': documents_value([]schema.Document{})
		'question':        json2.Any('which?')
	}) or {
		assert err.msg().contains('at least one document')
		assert fixture.state.prompts.len == 0
		return
	}
	assert false, 'expected empty map-rerank input to fail'
}

fn test_map_rerank_rejects_bad_scores() {
	mut state := &MapRerankFixtureState{}
	llm_chain := new_llm_chain(MapRerankFixtureModel{
		state: state
	}, prompts.StringTemplate{
		template: '{context}'
	}, 'result') or { panic(err) }
	chain := new_map_rerank_documents_chain(llm_chain, MapRerankDocumentsOptions{}) or {
		panic(err)
	}
	mut ctx := context.background()
	call(mut ctx, chain, {
		'input_documents': documents_value([schema.new_document('invalid')])
	}) or {
		assert err.msg().contains('score must be an integer')
		return
	}
	assert false, 'expected malformed score to fail'
}

fn test_map_rerank_enforces_document_count_before_mapping() {
	fixture := map_rerank_fixture(MapRerankDocumentsOptions{
		max_documents: 1
	}) or { panic(err) }
	mut ctx := context.background()
	call(mut ctx, fixture.chain, {
		'input_documents': documents_value([schema.new_document('low'), schema.new_document('best')])
		'question':        json2.Any('which?')
	}) or {
		assert err.msg().contains('document count')
		assert fixture.state.prompts.len == 0
		return
	}
	assert false, 'expected document count limit to fail'
}
