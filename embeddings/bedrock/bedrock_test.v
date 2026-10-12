module bedrock

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
	client := new_client('bedrock-test-key', FakeHTTPClient{
		state: state
	}) or { panic(err) }
	return client, state
}

fn test_titan_embedding_uses_runtime_invoke_and_float_body() {
	mut ctx := context.background()
	client, state := fixture_client('{"embedding":[0.1,0.2]}', 200)
	vectors := client.create_embedding(mut ctx, ['hello']) or { panic(err) }
	assert vectors == [[f32(0.1), 0.2]]
	request := state.requests[0]
	assert request.url == 'https://bedrock-runtime.us-east-1.amazonaws.com/model/amazon.titan-embed-text-v2:0/invoke'
	assert (request.headers['Authorization'] or { '' }) == 'Bearer bedrock-test-key'
	assert request.body.contains('"inputText":"hello"')
	assert request.body.contains('"embeddingTypes":["float"]')
	assert request.body.contains('"normalize":true')
}

fn test_titan_v2_supports_dimensions_and_region() {
	mut state := &FakeHTTPState{
		response: httputil.Response{
			status_code: 200
			body:        '{"embedding":[1.0]}'
		}
	}
	client := new_client_with_options('key', FakeHTTPClient{
		state: state
	}, Options{
		region:     'eu-west-1'
		dimensions: 256
	}) or { panic(err) }
	mut ctx := context.background()
	client.create_embedding(mut ctx, ['text']) or { panic(err) }
	assert state.requests[0].url.starts_with('https://bedrock-runtime.eu-west-1.amazonaws.com/')
	assert state.requests[0].body.contains('"dimensions":256')
}

fn test_cohere_uses_search_document_and_query_modes() {
	mut state := &FakeHTTPState{
		response: httputil.Response{
			status_code: 200
			body:        '{"embeddings":[[1.0,0.0],[0.0,1.0]]}'
		}
	}
	client := new_client_with_options('key', FakeHTTPClient{
		state: state
	}, Options{
		model: 'cohere.embed-english-v3'
	}) or { panic(err) }
	mut ctx := context.background()
	client.create_embedding(mut ctx, ['document one', 'document two']) or { panic(err) }
	assert state.requests[0].body.contains('"input_type":"search_document"')
	state.response = httputil.Response{
		status_code: 200
		body:        '{"embeddings":[[1.0,0.0]]}'
	}
	query := client.create_query_embedding(mut ctx, 'query') or { panic(err) }
	assert query == [f32(1), 0]
	assert state.requests[1].body.contains('"input_type":"search_query"')
}

fn test_cohere_adapter_batches_documents() {
	mut state := &FakeHTTPState{
		response: httputil.Response{
			status_code: 200
			body:        '{"embeddings":[[1.0],[1.0]]}'
		}
	}
	client := new_client_with_options('key', FakeHTTPClient{
		state: state
	}, Options{
		model: 'cohere.embed-english-v3'
	}) or { panic(err) }
	mut embedder := client.embedder(embeddings.Options{
		batch_size: 2
	}) or { panic(err) }
	mut ctx := context.background()
	vectors := embedder.embed_documents(mut ctx, ['first', 'second']) or { panic(err) }
	assert vectors == [[f32(1)], [f32(1)]]
	assert state.requests.len == 1
}

fn test_titan_rejects_multi_input_request() {
	mut ctx := context.background()
	client, state := fixture_client('{"embedding":[1.0]}', 200)
	client.create_embedding(mut ctx, ['one', 'two']) or {
		assert err.msg().contains('one input at a time')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected multi-input Titan request to fail'
}

fn test_provider_errors_do_not_leak_response_body() {
	mut ctx := context.background()
	client, _ := fixture_client('secret AWS details', 403)
	client.create_embedding(mut ctx, ['text']) or {
		assert err.msg() == 'Amazon Bedrock embeddings request returned HTTP 403'
		assert !err.msg().contains('secret')
		return
	}
	assert false, 'expected HTTP error'
}
