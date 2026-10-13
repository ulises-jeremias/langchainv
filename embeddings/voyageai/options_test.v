module voyageai

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

fn test_create_embedding_sends_dimension_and_truncation_options() {
	mut state := &OptionsFakeState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"data":[{"embedding":[0.1,0.2]}]}'
		}
	}
	client := new_client_with_options('test-secret', OptionsFakeClient{
		state: state
	}, Options{
		base_url:   'https://voyage.test/v1'
		model:      'voyage-test'
		dimensions: 256
		truncation: false
	}) or { panic(err) }
	mut ctx := context.background()
	vectors := client.create_embedding(mut ctx, ['hello']) or { panic(err) }
	assert vectors.len == 1
	assert state.requests.len == 1
	assert state.requests[0].body.contains('"output_dimension":256')
	assert state.requests[0].body.contains('"truncation":false')
}

fn test_new_client_rejects_invalid_dimensions() {
	mut state := &OptionsFakeState{}
	new_client_with_options('test-secret', OptionsFakeClient{
		state: state
	}, Options{
		dimensions: -1
	}) or {
		assert err.msg().contains('dimensions')
		return
	}
	assert false, 'expected invalid dimensions to fail'
}

fn test_create_embedding_omits_unset_options() {
	mut state := &OptionsFakeState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"data":[{"embedding":[0.1]}]}'
		}
	}
	client := new_client_with_options('test-secret', OptionsFakeClient{
		state: state
	}, Options{
		base_url: 'https://voyage.test/v1'
		model:    'voyage-test'
	}) or { panic(err) }
	mut ctx := context.background()
	client.create_embedding(mut ctx, ['hello']) or { panic(err) }
	assert !state.requests[0].body.contains('output_dimension')
	assert !state.requests[0].body.contains('truncation')
}
