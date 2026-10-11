module voyageai

import context
import net.http
import ulises_jeremias.langchainv.embeddings
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

fn test_create_embedding_sends_document_mode_and_maps_vectors() {
	mut ctx := context.background()
	client, state := fixture_client('{"data":[{"embedding":[0.1,0.2]},{"embedding":[0.3,0.4]}]}', 200)
	vectors := client.create_embedding(mut ctx, ['first', 'second']) or { panic(err) }
	assert vectors == [[f32(0.1), 0.2], [f32(0.3), 0.4]]
	assert state.requests.len == 1
	request := state.requests[0]
	assert request.url == 'https://api.voyageai.com/v1/embeddings'
	assert (request.headers['Authorization'] or { '' }) == 'Bearer test-secret'
	assert request.body.contains('"model":"voyage-2"')
	assert request.body.contains('"input_type":"document"')
	assert request.body.contains('"output_dtype":"float"')
	assert request.body.contains('"input":["first","second"]')
}

fn test_embedder_uses_query_mode_and_shared_text_preprocessing() {
	mut ctx := context.background()
	client, state := fixture_client('{"data":[{"embedding":[1.0,0.0]}]}', 200)
	mut embedder := client.default_embedder() or { panic(err) }
	vector := embedder.embed_query(mut ctx, 'first\nquery') or { panic(err) }
	assert vector == [f32(1), 0]
	assert state.requests[0].body.contains('"input_type":"query"')
	assert state.requests[0].body.contains('"input":["first query"]')
}

fn test_embedder_uses_document_mode_for_each_batch() {
	mut ctx := context.background()
	client, state := fixture_client('{"data":[{"embedding":[1.0]}]}', 200)
	mut embedder := client.embedder(embeddings.Options{
		batch_size: 1
	}) or { panic(err) }
	vectors := embedder.embed_documents(mut ctx, ['first', 'second']) or { panic(err) }
	assert vectors == [[f32(1)], [f32(1)]]
	assert state.requests.len == 2
	assert state.requests[0].body.contains('"input_type":"document"')
	assert state.requests[1].body.contains('"input_type":"document"')
}

fn test_create_embedding_rejects_wrong_vector_count() {
	mut ctx := context.background()
	client, _ := fixture_client('{"data":[{"embedding":[1.0]}]}', 200)
	client.create_embedding(mut ctx, ['first', 'second']) or {
		assert err.msg().contains('1 vectors for 2 texts')
		return
	}
	assert false, 'expected wrong vector count to fail'
}

fn test_create_embedding_rejects_provider_errors_without_leaking_body() {
	mut ctx := context.background()
	client, _ := fixture_client('secret provider response', 429)
	client.create_embedding(mut ctx, ['text']) or {
		assert err.msg() == 'Voyage embeddings request returned HTTP 429'
		assert !err.msg().contains('secret')
		return
	}
	assert false, 'expected HTTP error'
}

fn test_new_client_rejects_http_custom_endpoints() {
	new_client_with_options('test-secret', FakeHTTPClient{
		state: &FakeHTTPState{}
	}, Options{
		base_url: 'http://api.voyageai.com/v1'
	}) or {
		assert err.msg().contains('invalid Voyage base URL')
		return
	}
	assert false, 'expected insecure endpoint to fail'
}
