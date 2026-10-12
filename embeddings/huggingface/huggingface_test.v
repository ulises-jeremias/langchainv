module huggingface

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
	client := new_client('hf-test-token', FakeHTTPClient{
		state: state
	}) or { panic(err) }
	return client, state
}

fn test_create_embedding_calls_current_router_and_maps_vectors() {
	mut ctx := context.background()
	client, state := fixture_client('[[0.1,0.2],[0.3,0.4]]', 200)
	vectors := client.create_embedding(mut ctx, ['first', 'second']) or { panic(err) }
	assert vectors == [[f32(0.1), 0.2], [f32(0.3), 0.4]]
	assert state.requests.len == 1
	request := state.requests[0]
	assert request.url == 'https://router.huggingface.co/hf-inference/models/sentence-transformers/all-MiniLM-L6-v2/pipeline/feature-extraction'
	assert (request.headers['Authorization'] or { '' }) == 'Bearer hf-test-token'
	assert request.body.contains('"inputs":["first","second"]')
}

fn test_create_embedding_supports_custom_model_and_task() {
	mut state := &FakeHTTPState{
		response: httputil.Response{
			status_code: 200
			body:        '[[1.0]]'
		}
	}
	client := new_client_with_options('hf-test-token', FakeHTTPClient{
		state: state
	}, Options{
		model: 'my-org/my-embedding-model'
		task:  'pipeline/feature-extraction'
	}) or { panic(err) }
	mut ctx := context.background()
	client.create_embedding(mut ctx, ['text']) or { panic(err) }
	assert state.requests[0].url.contains('/models/my-org/my-embedding-model/pipeline/feature-extraction')
}

fn test_embedder_batches_through_shared_adapter() {
	mut ctx := context.background()
	client, state := fixture_client('[[1.0]]', 200)
	mut embedder := client.embedder(embeddings.Options{
		batch_size: 1
	}) or { panic(err) }
	vectors := embedder.embed_documents(mut ctx, ['first', 'second']) or { panic(err) }
	assert vectors == [[f32(1)], [f32(1)]]
	assert state.requests.len == 2
}

fn test_create_embedding_rejects_invalid_vector_count() {
	mut ctx := context.background()
	client, _ := fixture_client('[[0.1,0.2]]', 200)
	client.create_embedding(mut ctx, ['first', 'second']) or {
		assert err.msg().contains('1 vectors for 2 texts')
		return
	}
	assert false, 'expected wrong vector count to fail'
}

fn test_create_embedding_rejects_provider_errors_without_leaking_body() {
	mut ctx := context.background()
	client, _ := fixture_client('private provider response', 503)
	client.create_embedding(mut ctx, ['text']) or {
		assert err.msg() == 'Hugging Face embeddings request returned HTTP 503'
		assert !err.msg().contains('private')
		return
	}
	assert false, 'expected HTTP error'
}

fn test_new_client_rejects_invalid_model_path() {
	new_client_with_options('hf-test-token', FakeHTTPClient{
		state: &FakeHTTPState{}
	}, Options{
		model: 'other-org/model/extra'
	}) or {
		assert err.msg().contains('two-part model ID')
		return
	}
	assert false, 'expected invalid model ID to fail'
}
