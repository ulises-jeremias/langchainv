module openai

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

fn fake_client(body string) (Client, &FakeHTTPState) {
	mut state := &FakeHTTPState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        body
		}
	}
	client := new_client('test-secret', FakeHTTPClient{
		state: state
	}) or { panic(err) }
	return client, state
}

fn test_embeddings_request_auth_and_reorders_provider_results() {
	mut ctx := context.background()
	client, state := fake_client('{"data":[{"index":1,"embedding":[0.0,1.0]},{"index":0,"embedding":[1.0,0.0]}]}')
	vectors := client.create_embedding(mut ctx, ['first text', 'second text']) or { panic(err) }
	assert vectors == [[f32(1), 0], [0, f32(1)]]
	assert state.requests.len == 1
	request := state.requests[0]
	assert request.method == .post
	assert request.url == 'https://api.openai.com/v1/embeddings'
	assert (request.headers['Authorization'] or { '' }) == 'Bearer test-secret'
	assert request.body.contains('"model":"text-embedding-3-small"')
	assert request.body.contains('"encoding_format":"float"')
	assert request.body.contains('"first text"')
}

fn test_embeddings_rejects_bad_status_without_returning_body() {
	mut ctx := context.background()
	mut state := &FakeHTTPState{
		response: httputil.Response{
			status_code: 429
			body:        'provider error that may include sensitive details'
		}
	}
	client := new_client('test-secret', FakeHTTPClient{
		state: state
	}) or { panic(err) }
	client.create_embedding(mut ctx, ['text']) or {
		assert err.msg() == 'OpenAI embeddings request returned HTTP 429'
		return
	}
	assert false, 'expected HTTP error'
}

fn test_embeddings_rejects_invalid_or_duplicate_indices() {
	mut ctx := context.background()
	client, _ := fake_client('{"data":[{"index":0,"embedding":[1.0]},{"index":0,"embedding":[2.0]}]}')
	client.create_embedding(mut ctx, ['first', 'second']) or {
		assert err.msg().contains('duplicate input index')
		return
	}
	assert false, 'expected duplicate index error'
}

fn test_custom_model_dimensions_and_base_url() {
	mut ctx := context.background()
	mut state := &FakeHTTPState{
		response: httputil.Response{
			status_code: 200
			body:        '{"data":[{"index":0,"embedding":[0.5]}]}'
		}
	}
	client := new_client_with_options('test-secret', FakeHTTPClient{
		state: state
	}, Options{
		base_url:   'https://proxy.example/v1/'
		model:      'custom-embedding-model'
		dimensions: 1
	}) or { panic(err) }
	client.create_embedding(mut ctx, ['text']) or { panic(err) }
	assert state.requests[0].url == 'https://proxy.example/v1/embeddings'
	assert state.requests[0].body.contains('"model":"custom-embedding-model"')
	assert state.requests[0].body.contains('"dimensions":1')
}

fn test_empty_input_does_not_make_http_request() {
	mut ctx := context.background()
	client, state := fake_client('{"data":[]}')
	vectors := client.create_embedding(mut ctx, []) or { panic(err) }
	assert vectors.len == 0
	assert state.requests.len == 0
}

fn test_client_rejects_empty_api_key() {
	new_client('', FakeHTTPClient{
		state: &FakeHTTPState{}
	}) or {
		assert err.msg().contains('API key')
		return
	}
	assert false, 'expected empty key to fail'
}

fn test_client_rejects_invalid_dimensions() {
	new_client_with_options('test-secret', FakeHTTPClient{
		state: &FakeHTTPState{}
	}, Options{
		dimensions: 0
	}) or {
		assert err.msg().contains('dimensions must be greater than zero')
		return
	}
	assert false, 'expected zero dimensions to fail'
}
