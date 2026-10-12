module ollama

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
	client := new_client(FakeHTTPClient{
		state: state
	}, Options{
		base_url: 'http://ollama.test:11434'
		model:    'nomic-embed-text'
	}) or { panic(err) }
	return client, state
}

fn test_create_embedding_posts_batch_and_maps_vectors() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"model":"nomic-embed-text","embeddings":[[0.1,0.2],[0.3,0.4]]}', 200)
	vectors := client.create_embedding(mut ctx, ['first', 'second']) or { panic(err) }
	assert vectors == [[f32(0.1), 0.2], [f32(0.3), 0.4]]
	assert state.requests.len == 1
	assert state.requests[0].url == 'http://ollama.test:11434/api/embed'
	assert state.requests[0].body.contains('"model":"nomic-embed-text"')
	assert state.requests[0].body.contains('"input":["first","second"]')
}

fn test_create_embedding_rejects_invalid_inputs_before_network() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"embeddings":[]}', 200)
	client.create_embedding(mut ctx, ['']) or {
		assert err.msg().contains('empty text')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected empty input to fail'
}

fn test_create_embedding_rejects_invalid_response_shape() {
	mut ctx := context.background()
	client, _ := new_fixture_client('{"embeddings":[[0.1],[0.2,0.3]]}', 200)
	client.create_embedding(mut ctx, ['first', 'second']) or {
		assert err.msg().contains('different dimensions')
		return
	}
	assert false, 'expected inconsistent dimensions to fail'
}

fn test_create_embedding_rejects_http_errors_without_leaking_body() {
	mut ctx := context.background()
	client, _ := new_fixture_client('secret provider response', 500)
	client.create_embedding(mut ctx, ['first']) or {
		assert err.msg().contains('HTTP 500')
		assert !err.msg().contains('secret')
		return
	}
	assert false, 'expected server error to fail'
}
