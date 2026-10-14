module mistral

import context
import net.http
import ulises_jeremias.langchainv.httputil

struct FakeHTTPClient {
	state &FakeHTTPState
}

struct FakeHTTPState {
mut:
	requests []httputil.Request
	response httputil.Response
}

fn (client FakeHTTPClient) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	return state.response
}

fn new_fixture_client(body string, status int) (Client, &FakeHTTPState) {
	mut state := &FakeHTTPState{
		response: httputil.Response{
			status_code: status
			headers:     http.Header{}
			body:        body
		}
	}
	client := new_client('test-secret', FakeHTTPClient{
		state: state
	}) or { panic(err) }
	return client, state
}

fn test_embeddings_request_auth_model_and_input_order() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"data":[{"index":1,"embedding":[0.0,1.0]},{"index":0,"embedding":[1.0,0.0]}]}', 200)
	vectors := client.create_embedding(mut ctx, ['first text', 'second text']) or { panic(err) }
	assert vectors == [[f32(1), 0], [0, f32(1)]]
	assert state.requests.len == 1
	request := state.requests[0]
	assert request.method == .post
	assert request.url == 'https://api.mistral.ai/v1/embeddings'
	assert (request.headers['Authorization'] or { '' }) == 'Bearer test-secret'
	assert request.body.contains('"model":"mistral-embed"')
	assert request.body.contains('"encoding_format":"float"')
	assert request.body.contains('"input":["first text","second text"]')
}

fn test_custom_endpoint_model_and_output_dimension() {
	mut ctx := context.background()
	mut state := &FakeHTTPState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"data":[{"index":0,"embedding":[0.5,0.25]}]}'
		}
	}
	client := new_client_with_options('test-secret', FakeHTTPClient{
		state: state
	}, Options{
		base_url:         'https://proxy.example/v1/'
		model:            'mistral-embed'
		output_dimension: 2
	}) or { panic(err) }
	client.create_embedding(mut ctx, ['text']) or { panic(err) }
	assert state.requests[0].url == 'https://proxy.example/v1/embeddings'
	assert state.requests[0].body.contains('"output_dimension":2')
}

fn test_empty_input_does_not_make_http_request() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"data":[]}', 200)
	vectors := client.create_embedding(mut ctx, []) or { panic(err) }
	assert vectors.len == 0
	assert state.requests.len == 0
}

fn test_embeddings_reject_invalid_response_indices_and_dimensions() {
	mut ctx := context.background()
	for body, expected_error in {
		'{"data":[{"index":0,"embedding":[1.0]},{"index":0,"embedding":[2.0]}]}':     'duplicate input index'
		'{"data":[{"index":0,"embedding":[1.0]},{"index":1,"embedding":[2.0,3.0]}]}': 'different dimensions'
		'{"data":[{"index":2,"embedding":[1.0]},{"index":1,"embedding":[2.0]}]}':     'out-of-range'
		'{"data":[{"index":0,"embedding":[1.0]}]}':                                   'returned 1 vectors for 2 texts'
	} {
		client, _ := new_fixture_client(body, 200)
		client.create_embedding(mut ctx, ['one', 'two']) or {
			assert err.msg().contains(expected_error)
			continue
		}
		assert false, 'expected malformed response to fail'
	}
}

fn test_embeddings_reject_input_and_http_errors_before_returning_vectors() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"data":[]}', 200)
	client.create_embedding(mut ctx, ['']) or {
		assert err.msg().contains('empty text')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected empty text to fail'

	http_client, _ := new_fixture_client('private provider response', 429)
	http_client.create_embedding(mut ctx, ['text']) or {
		assert err.msg() == 'Mistral embeddings request returned HTTP 429'
		return
	}
	assert false, 'expected HTTP error'
}

fn test_client_rejects_invalid_configuration() {
	for options in [
		Options{
			output_dimension: 0
		},
		Options{
			base_url: 'http://mistral.test/v1'
		},
	] {
		new_client_with_options('test-secret', FakeHTTPClient{
			state: &FakeHTTPState{}
		}, options) or {
			assert err.msg() != ''
			continue
		}
		assert false, 'expected invalid configuration to fail'
	}
}
