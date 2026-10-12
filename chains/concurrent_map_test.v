module chains

import context
import json2
import sync
import time
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema

enum ConcurrentMapOutput {
	uppercase
	expanded
	ranked
	invalid_score
	failure
	cancellation
}

@[heap]
struct ConcurrentMapState {
mut:
	mutex      sync.Mutex
	active     int
	max_active int
	calls      int
}

struct ConcurrentMapModel {
	state    &ConcurrentMapState
	output   ConcurrentMapOutput
	delay_ms int
}

fn (model ConcurrentMapModel) complete(mut ctx context.Context, prompt string, _options llms.CallOptions) !string {
	mut state := model.state
	state.mutex.lock()
	state.active++
	state.calls++
	if state.active > state.max_active {
		state.max_active = state.active
	}
	state.mutex.unlock()

	time.sleep(time.Duration(model.delay_ms) * time.millisecond)
	if model.output == .failure && prompt.contains('first') {
		time.sleep(40 * time.millisecond)
	}

	state.mutex.lock()
	state.active--
	state.mutex.unlock()

	if model.output == .failure {
		if prompt.contains('first') {
			return error('first document failure')
		}
		return error('later document failure')
	}
	if model.output == .cancellation {
		ctx_error := ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
	}
	if model.output == .ranked {
		if prompt.contains('best') {
			return 'best answer\nScore: 9'
		}
		if prompt.contains('tie-first') {
			return 'first tied answer\nScore: 9'
		}
		if prompt.contains('tie-second') {
			return 'second tied answer\nScore: 9'
		}
		if prompt.contains('middle') {
			return 'middle answer\nScore: 5'
		}
		return 'low answer\nScore: 1'
	}
	if model.output == .invalid_score {
		return 'invalid answer\nScore: nope'
	}
	if model.output == .expanded {
		return 'expanded: ${prompt}'
	}
	return prompt.to_upper()
}

fn test_map_reduce_uses_bounded_concurrency_and_preserves_input_order() {
	mut state := &ConcurrentMapState{}
	map_chain := new_llm_chain(ConcurrentMapModel{
		state:    state
		output:   .uppercase
		delay_ms: 35
	}, prompts.StringTemplate{
		template: '{context}'
	}, 'mapped') or { panic(err) }
	mut reducer_state := &MapReduceCaptureState{}
	chain := new_map_reduce_documents_chain(map_chain, MapReduceCaptureReducer{
		state: reducer_state
	}, MapReduceDocumentsOptions{
		max_concurrency: 3
	}) or { panic(err) }
	mut ctx := context.background()
	call(mut ctx, chain, {
		'input_documents': documents_value([
			schema.new_document('first')
			schema.new_document('second')
			schema.new_document('third'),
		])
	}) or { panic(err) }

	assert state.max_active > 1
	assert state.max_active <= 3
	assert state.active == 0
	assert reducer_state.documents.len == 3
	assert mapped_content(reducer_state.documents, 0) == 'FIRST'
	assert mapped_content(reducer_state.documents, 1) == 'SECOND'
	assert mapped_content(reducer_state.documents, 2) == 'THIRD'
}

fn test_map_rerank_maps_concurrently_and_keeps_ties_stable() {
	mut state := &ConcurrentMapState{}
	llm_chain := new_llm_chain(ConcurrentMapModel{
		state:    state
		output:   .ranked
		delay_ms: 35
	}, prompts.StringTemplate{
		template: '{context}'
	}, 'result') or { panic(err) }
	chain := new_map_rerank_documents_chain(llm_chain, MapRerankDocumentsOptions{
		max_concurrency:           3
		return_intermediate_steps: true
	}) or { panic(err) }
	mut ctx := context.background()
	outputs := call(mut ctx, chain, {
		'input_documents': documents_value([
			schema.new_document('low')
			schema.new_document('best')
			schema.new_document('tie-first')
			schema.new_document('tie-second'),
		])
	}) or { panic(err) }

	assert state.max_active > 1
	assert state.max_active <= 3
	assert state.active == 0
	assert (outputs['result'] or { panic('missing result') }).str() == 'best answer'
	steps_value := outputs['intermediate_steps'] or { panic('missing steps') }
	assert steps_value is []json2.Any
	steps := steps_value as []json2.Any
	assert ranked_answer(steps, 0) == 'best answer'
	assert ranked_answer(steps, 1) == 'first tied answer'
	assert ranked_answer(steps, 2) == 'second tied answer'
	assert ranked_answer(steps, 3) == 'low answer'
}

fn test_map_documents_reports_the_first_input_error_after_parallel_work() {
	mut state := &ConcurrentMapState{}
	map_chain := new_llm_chain(ConcurrentMapModel{
		state:  state
		output: .failure
	}, prompts.StringTemplate{
		template: '{context}'
	}, 'mapped') or { panic(err) }
	chain := new_map_reduce_documents_chain(map_chain, MapReduceCaptureReducer{
		state: &MapReduceCaptureState{}
	}, MapReduceDocumentsOptions{
		max_concurrency: 2
	}) or { panic(err) }
	mut ctx := context.background()
	call(mut ctx, chain, {
		'input_documents': documents_value([
			schema.new_document('first')
			schema.new_document('second'),
		])
	}) or {
		assert err.msg().contains('first document failure')
		return
	}
	assert false, 'expected a map model error'
}

fn test_map_reduce_does_not_start_another_batch_after_output_limit_error() {
	mut state := &ConcurrentMapState{}
	map_chain := new_llm_chain(ConcurrentMapModel{
		state:    state
		output:   .expanded
		delay_ms: 10
	}, prompts.StringTemplate{
		template: '{context}'
	}, 'mapped') or { panic(err) }
	chain := new_map_reduce_documents_chain(map_chain, MapReduceCaptureReducer{
		state: &MapReduceCaptureState{}
	}, MapReduceDocumentsOptions{
		max_concurrency:    2
		max_document_bytes: 10
	}) or { panic(err) }
	mut ctx := context.background()
	call(mut ctx, chain, {
		'input_documents': documents_value([
			schema.new_document('a')
			schema.new_document('b')
			schema.new_document('c'),
		])
	}) or {
		assert err.msg().contains('byte limit')
		assert concurrent_map_call_count(state) == 2
		return
	}
	assert false, 'expected the combined mapped output limit to fail'
}

fn test_map_rerank_does_not_start_another_batch_after_invalid_score() {
	mut state := &ConcurrentMapState{}
	llm_chain := new_llm_chain(ConcurrentMapModel{
		state:    state
		output:   .invalid_score
		delay_ms: 10
	}, prompts.StringTemplate{
		template: '{context}'
	}, 'result') or { panic(err) }
	chain := new_map_rerank_documents_chain(llm_chain, MapRerankDocumentsOptions{
		max_concurrency: 2
	}) or { panic(err) }
	mut ctx := context.background()
	call(mut ctx, chain, {
		'input_documents': documents_value([
			schema.new_document('first')
			schema.new_document('second')
			schema.new_document('third'),
		])
	}) or {
		assert err.msg().contains('integer')
		assert concurrent_map_call_count(state) == 2
		return
	}
	assert false, 'expected the invalid score to fail'
}

fn test_parallel_mapping_observes_parent_context_deadline() {
	mut state := &ConcurrentMapState{}
	map_chain := new_llm_chain(ConcurrentMapModel{
		state:    state
		output:   .cancellation
		delay_ms: 25
	}, prompts.StringTemplate{
		template: '{context}'
	}, 'mapped') or { panic(err) }
	chain := new_map_reduce_documents_chain(map_chain, MapReduceCaptureReducer{
		state: &MapReduceCaptureState{}
	}, MapReduceDocumentsOptions{
		max_concurrency: 2
	}) or { panic(err) }
	mut parent := context.background()
	mut ctx, cancel := context.with_timeout(mut parent, 10 * time.millisecond)
	call(mut ctx, chain, {
		'input_documents': documents_value([
			schema.new_document('first')
			schema.new_document('second'),
		])
	}) or {
		assert err.msg().contains('deadline exceeded')
		cancel()
		return
	}
	cancel()
	assert false, 'expected the parent deadline to cancel mapping'
}

fn test_document_map_concurrency_is_bounded_by_options() {
	mut state := &ConcurrentMapState{}
	map_chain := new_llm_chain(ConcurrentMapModel{
		state: state
	}, prompts.StringTemplate{
		template: '{context}'
	}, 'mapped') or { panic(err) }
	reducer := MapReduceCaptureReducer{
		state: &MapReduceCaptureState{}
	}
	new_map_reduce_documents_chain(map_chain, reducer, MapReduceDocumentsOptions{
		max_concurrency: 6
	}) or {
		assert err.msg().contains('max_concurrency')
		return
	}
	assert false, 'expected map-reduce concurrency above five to fail'
}

fn test_map_rerank_rejects_concurrency_above_five() {
	llm_chain := new_llm_chain(ConcurrentMapModel{
		state: &ConcurrentMapState{}
	}, prompts.StringTemplate{
		template: '{context}'
	}, 'result') or { panic(err) }
	new_map_rerank_documents_chain(llm_chain, MapRerankDocumentsOptions{
		max_concurrency: 6
	}) or {
		assert err.msg().contains('max_concurrency')
		return
	}
	assert false, 'expected map-rerank concurrency above five to fail'
}

fn mapped_content(documents []json2.Any, index int) string {
	value := documents[index] or { panic('missing mapped document') }
	assert value is map[string]json2.Any
	document := value as map[string]json2.Any
	return (document['page_content'] or { panic('missing page content') }).str()
}

fn ranked_answer(steps []json2.Any, index int) string {
	value := steps[index] or { panic('missing ranked step') }
	assert value is map[string]json2.Any
	return ((value as map[string]json2.Any)['answer'] or { panic('missing answer') }).str()
}

fn concurrent_map_call_count(state &ConcurrentMapState) int {
	mut mutable_state := state
	mutable_state.mutex.lock()
	defer {
		mutable_state.mutex.unlock()
	}
	return mutable_state.calls
}
