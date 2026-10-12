module googleai

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
	client := new_client_with_options('google-secret', FakeHTTPClient{
		state: state
	}, Options{
		base_url:              'https://google.test/v1beta'
		model:                 'gemini-embedding-2'
		task_type:             'RETRIEVAL_DOCUMENT'
		output_dimensionality: 768
	}) or { panic(err) }
	return client, state
}

fn test_create_embedding_posts_batch_and_maps_vectors() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"embeddings":[{"values":[0.1,0.2]},{"values":[0.3,0.4]}]}', 200)
	vectors := client.create_embedding(mut ctx, ['first', 'second']) or { panic(err) }
	assert vectors == [[f32(0.1), 0.2], [f32(0.3), 0.4]]
	assert state.requests.len == 1
	assert state.requests[0].url == 'https://google.test/v1beta/models/gemini-embedding-2:batchEmbedContents'
	assert state.requests[0].headers['x-goog-api-key'] == 'google-secret'
	assert state.requests[0].body.contains('"model":"models/gemini-embedding-2"')
	assert state.requests[0].body.contains('"taskType":"RETRIEVAL_DOCUMENT"')
	assert state.requests[0].body.contains('"outputDimensionality":768')
	assert state.requests[0].body.contains('"text":"first"')
	assert !state.requests[0].url.contains('google-secret')
}

fn test_create_embedding_rejects_bad_input_before_network() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"embeddings":[]}', 200)
	client.create_embedding(mut ctx, ['']) or {
		assert err.msg().contains('must not be empty')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected empty text to be rejected'
}

fn test_create_embedding_enforces_provider_batch_limit_before_network() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"embeddings":[]}', 200)
	texts := []string{len: 101, init: 'item'}
	client.create_embedding(mut ctx, texts) or {
		assert err.msg().contains('100-input limit')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected an oversized provider batch to fail'
}

fn test_default_embedder_respects_provider_batch_limit() {
	client, _ := new_fixture_client('{"embeddings":[]}', 200)
	embedder := client.default_embedder() or { panic(err) }
	assert embedder.batch_size == 100
}

fn test_create_embedding_rejects_wrong_vector_count() {
	mut ctx := context.background()
	client, _ := new_fixture_client('{"embeddings":[{"values":[0.1]}]}', 200)
	client.create_embedding(mut ctx, ['first', 'second']) or {
		assert err.msg().contains('1 vectors for 2 texts')
		return
	}
	assert false, 'expected missing vector to fail'
}

fn test_create_embedding_hides_http_error_body() {
	mut ctx := context.background()
	client, _ := new_fixture_client('private provider detail', 429)
	client.create_embedding(mut ctx, ['first']) or {
		assert err.msg().contains('HTTP 429')
		assert !err.msg().contains('private provider detail')
		return
	}
	assert false, 'expected HTTP error to fail'
}
