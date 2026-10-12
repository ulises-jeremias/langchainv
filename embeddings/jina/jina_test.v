module jina

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

fn fixture_client(body string, status int) (Client, &FakeHTTPState) {
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

fn test_create_embedding_authenticates_and_restores_input_order() {
	mut ctx := context.background()
	client, state := fixture_client('{"data":[{"index":1,"embedding":[0.0,1.0]},{"index":0,"embedding":[1.0,0.0]}]}',
		200)
	vectors := client.create_embedding(mut ctx, ['first', 'second']) or { panic(err) }
	assert vectors == [[f32(1), 0], [0, f32(1)]]
	assert state.requests.len == 1
	request := state.requests[0]
	assert request.url == 'https://api.jina.ai/v1/embeddings'
	assert (request.headers['Authorization'] or { '' }) == 'Bearer test-secret'
	assert request.body.contains('"model":"jina-embeddings-v2-small-en"')
	assert request.body.contains('"embedding_type":"float"')
	assert request.body.contains('"input":["first","second"]')
}

fn test_create_embedding_rejects_empty_input_before_network() {
	mut ctx := context.background()
	client, state := fixture_client('{"data":[]}', 200)
	client.create_embedding(mut ctx, ['']) or {
		assert err.msg().contains('empty text')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected empty input to fail'
}

fn test_create_embedding_rejects_missing_or_duplicate_indices() {
	mut ctx := context.background()
	client, _ := fixture_client('{"data":[{"index":0,"embedding":[1.0]},{"index":0,"embedding":[2.0]}]}',
		200)
	client.create_embedding(mut ctx, ['first', 'second']) or {
		assert err.msg().contains('duplicate input index')
		return
	}
	assert false, 'expected duplicate input index to fail'
}

fn test_create_embedding_rejects_provider_errors_without_leaking_body() {
	mut ctx := context.background()
	client, _ := fixture_client('secret provider response', 401)
	client.create_embedding(mut ctx, ['text']) or {
		assert err.msg() == 'Jina embeddings request returned HTTP 401'
		assert !err.msg().contains('secret')
		return
	}
	assert false, 'expected HTTP error'
}

fn test_new_client_rejects_insecure_custom_url() {
	new_client_with_options('test-secret', FakeHTTPClient{
		state: &FakeHTTPState{}
	}, Options{
		base_url: 'http://api.jina.ai/v1'
	}) or {
		assert err.msg().contains('invalid Jina base URL')
		return
	}
	assert false, 'expected insecure endpoint to fail'
}
