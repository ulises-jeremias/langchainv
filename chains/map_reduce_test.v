module chains

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema

@[heap]
struct MapReduceFixtureState {
mut:
	prompts []string
}

struct MapReduceFixtureModel {
	state &MapReduceFixtureState
}

fn (model MapReduceFixtureModel) complete(mut _ctx context.Context, prompt string, _options llms.CallOptions) !string {
	mut state := model.state
	state.prompts << prompt
	return prompt.to_upper()
}

@[heap]
struct MapReduceCaptureState {
mut:
	documents []json2.Any
}

struct MapReduceCaptureReducer {
	state &MapReduceCaptureState
}

fn (chain MapReduceCaptureReducer) call(mut _ctx context.Context, inputs map[string]json2.Any) !map[string]json2.Any {
	value := inputs['input_documents'] or { return error('missing mapped documents') }
	if value !is []json2.Any {
		return error('expected mapped documents array')
	}
	mut state := chain.state
	state.documents = (value as []json2.Any).clone()
	return {
		'answer': json2.Any('reduced')
	}
}

fn (_ MapReduceCaptureReducer) memory() ?schema.Memory {
	return none
}

fn (_ MapReduceCaptureReducer) input_keys() []string {
	return ['input_documents']
}

fn (_ MapReduceCaptureReducer) output_keys() []string {
	return ['answer']
}

struct MapReduceFixture {
	chain        MapReduceDocumentsChain
	map_state    &MapReduceFixtureState
	reduce_state &MapReduceFixtureState
}

fn map_reduce_fixture() !MapReduceFixture {
	mut map_state := &MapReduceFixtureState{}
	mut reduce_state := &MapReduceFixtureState{}
	map_chain := new_llm_chain(MapReduceFixtureModel{
		state: map_state
	}, prompts.StringTemplate{
		template: 'Map {context} for {question}'
	}, 'map_result')!
	reduce_llm_chain := new_llm_chain(MapReduceFixtureModel{
		state: reduce_state
	}, prompts.StringTemplate{
		template: 'Reduce {context} for {question}'
	}, 'answer')!
	reduce_chain := new_stuff_documents_chain(reduce_llm_chain, StuffDocumentsOptions{})!
	chain := new_map_reduce_documents_chain(map_chain, reduce_chain, MapReduceDocumentsOptions{
		return_intermediate_steps: true
	})!
	return MapReduceFixture{
		chain:        chain
		map_state:    map_state
		reduce_state: reduce_state
	}
}

fn test_map_reduce_maps_in_order_then_reduces_bounded_documents() {
	fixture := map_reduce_fixture() or { panic(err) }
	mut ctx := context.background()
	outputs := call(mut ctx, fixture.chain, {
		'input_documents': documents_value([
			schema.new_document('first')
			schema.new_document('second'),
		])
		'question':        json2.Any('why?')
	}) or { panic(err) }
	assert (outputs['answer'] or { panic('missing answer') }).str() == 'reduced'
	assert fixture.map_state.prompts == ['Map first for why?', 'Map second for why?']
	assert fixture.reduce_state.prompts == ['Reduce MAP FIRST FOR WHY?\n\nMAP SECOND FOR WHY? for why?']
	assert fixture.chain.input_keys() == ['input_documents', 'question']
	assert fixture.chain.output_keys() == ['answer', 'intermediate_steps']
	steps := outputs['intermediate_steps'] or { panic('missing map steps') }
	assert steps is []json2.Any
	assert (steps as []json2.Any).len == 2
}

fn test_map_reduce_preserves_document_metadata() {
	mut map_state := &MapReduceFixtureState{}
	mut reduce_state := &MapReduceCaptureState{}
	map_chain := new_llm_chain(MapReduceFixtureModel{
		state: map_state
	}, prompts.StringTemplate{
		template: '{context}'
	}, 'mapped') or { panic(err) }
	chain := new_map_reduce_documents_chain(map_chain, MapReduceCaptureReducer{
		state: reduce_state
	}, MapReduceDocumentsOptions{}) or { panic(err) }
	mut metadata := map[string]json2.Any{}
	metadata['source'] = json2.Any('fixture.txt')
	mut ctx := context.background()
	call(mut ctx, chain, {
		'input_documents': documents_value([schema.Document{
			page_content: 'source text'
			metadata:     metadata
		}])
	}) or { panic(err) }
	assert reduce_state.documents.len == 1
	if item := reduce_state.documents[0] {
		assert item is map[string]json2.Any
		document := item as map[string]json2.Any
		assert (document['page_content'] or { panic('missing page_content') }).str() == 'SOURCE TEXT'
		metadata_value := document['metadata'] or { panic('missing metadata') }
		assert metadata_value is map[string]json2.Any
		assert ((metadata_value as map[string]json2.Any)['source'] or { panic('missing source') }).str() == 'fixture.txt'
	} else {
		assert false, 'missing mapped document'
	}
}

fn test_map_reduce_rejects_document_count_limit_before_mapping() {
	fixture := map_reduce_fixture() or { panic(err) }
	mut too_many_documents := []schema.Document{cap: 17}
	for _ in 0 .. 17 {
		too_many_documents << schema.new_document('one')
	}
	mut ctx := context.background()
	call(mut ctx, fixture.chain, {
		'input_documents': documents_value(too_many_documents)
		'question':        json2.Any('q')
	}) or {
		assert err.msg().contains('document count')
		assert fixture.map_state.prompts.len == 0
		return
	}
	assert false, 'expected document count limit to reject input'
}

fn test_map_reduce_rejects_input_key_collisions() {
	map_state := &MapReduceFixtureState{}
	map_chain := new_llm_chain(MapReduceFixtureModel{
		state: map_state
	}, prompts.StringTemplate{
		template: '{context}'
	}, 'mapped') or { panic(err) }
	reducer := MapReduceCaptureReducer{
		state: &MapReduceCaptureState{}
	}
	new_map_reduce_documents_chain(map_chain, reducer, MapReduceDocumentsOptions{
		input_key: 'context'
	}) or {
		assert err.msg().contains('conflicts')
		return
	}
	assert false, 'expected colliding input key to fail'
}

fn test_map_reduce_rejects_oversized_source_documents() {
	mut map_state := &MapReduceFixtureState{}
	map_chain := new_llm_chain(MapReduceFixtureModel{
		state: map_state
	}, prompts.StringTemplate{
		template: '{context}'
	}, 'mapped') or { panic(err) }
	chain := new_map_reduce_documents_chain(map_chain, MapReduceCaptureReducer{
		state: &MapReduceCaptureState{}
	}, MapReduceDocumentsOptions{
		max_document_bytes: 4
	}) or { panic(err) }
	mut ctx := context.background()
	call(mut ctx, chain, {
		'input_documents': documents_value([schema.new_document('source')])
	}) or {
		assert err.msg().contains('byte limit')
		assert map_state.prompts.len == 0
		return
	}
	assert false, 'expected oversized source document to fail'
}
