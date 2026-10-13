module jina

import context
import net.http
import ulises_jeremias.langchainv.httputil

@[heap]
struct OptionsFakeState {
mut:
	requests []httputil.Request
	response httputil.Response
}

struct OptionsFakeClient {
	state &OptionsFakeState
}

fn (client OptionsFakeClient) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	return state.response
}

fn test_create_embedding_sends_task_dimension_and_late_chunking() {
	mut state := &OptionsFakeState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"data":[{"index":0,"embedding":[0.1,0.2]}]}'
		}
	}
	client := new_client_with_options('test-secret', OptionsFakeClient{
		state: state
	}, Options{
		base_url:      'https://jina.test/v1'
		model:         'jina-test'
		task:          'retrieval.query'
		dimensions:    512
		late_chunking: true
	}) or { panic(err) }
	mut ctx := context.background()
	vectors := client.create_embedding(mut ctx, ['hello']) or { panic(err) }
	assert vectors.len == 1
	assert state.requests[0].body.contains('"task":"retrieval.query"')
	assert state.requests[0].body.contains('"dimensions":512')
	assert state.requests[0].body.contains('"late_chunking":true')
}

fn test_new_client_rejects_unknown_task_and_invalid_dimensions() {
	mut state := &OptionsFakeState{}
	new_client_with_options('test-secret', OptionsFakeClient{
		state: state
	}, Options{
		task: 'unknown-task'
	}) or {
		assert err.msg().contains('task')
		return
	}
	assert false, 'expected an unknown task to fail'
}

fn test_create_embedding_omits_unset_options() {
	mut state := &OptionsFakeState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"data":[{"index":0,"embedding":[0.1]}]}'
		}
	}
	client := new_client_with_options('test-secret', OptionsFakeClient{
		state: state
	}, Options{
		base_url: 'https://jina.test/v1'
		model:    'jina-test'
	}) or { panic(err) }
	mut ctx := context.background()
	client.create_embedding(mut ctx, ['hello']) or { panic(err) }
	assert !state.requests[0].body.contains('"task"')
	assert !state.requests[0].body.contains('late_chunking')
}
