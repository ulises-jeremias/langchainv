module mistral

import context
import net.http
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

struct FakeHTTPClient {
	state &FakeHTTPState
}

struct FakeHTTPState {
mut:
	requests []httputil.Request
	response httputil.Response
}

struct StreamCapture {
mut:
	value string
}

fn (client FakeHTTPClient) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	return state.response
}

fn (client FakeHTTPClient) do_stream(mut ctx context.Context, request httputil.Request, handler httputil.StreamHandler) !httputil.Response {
	mut state := client.state
	state.requests << request
	body := state.response.body.bytes()
	mut offset := 0
	for offset < body.len {
		end := if offset + 9 < body.len { offset + 9 } else { body.len }
		handler(mut ctx, body[offset..end])!
		offset = end
	}
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

fn test_generate_content_translates_openai_compatible_options() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"choices":[{"index":0,"message":{"role":"assistant","content":"hello"},"finish_reason":"stop"}],"usage":{"prompt_tokens":4,"completion_tokens":2,"total_tokens":6}}', 200)
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		max_tokens: 24
		seed:       17
	}) or { panic(err) }
	assert response.choices[0].content == 'hello'
	assert response.usage.total_tokens == 6
	assert state.requests.len == 1
	assert state.requests[0].url == 'https://api.mistral.ai/v1/chat/completions'
	assert (state.requests[0].headers['Authorization'] or { '' }) == 'Bearer test-secret'
	assert state.requests[0].body.contains('"model":"mistral-large-latest"')
	assert state.requests[0].body.contains('"max_tokens":24')
	assert !state.requests[0].body.contains('"max_completion_tokens"')
	assert state.requests[0].body.contains('"random_seed":17')
	assert !state.requests[0].body.contains('"seed":17')
}

fn test_client_accepts_custom_regional_endpoint_and_model() {
	mut ctx := context.background()
	mut state := &FakeHTTPState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"choices":[{"message":{"content":"ok"}}]}'
		}
	}
	client := new_client_with_options('test-secret', FakeHTTPClient{
		state: state
	}, Options{
		base_url: 'https://api.eu.mistral.ai/v1/'
		model:    'mistral-small-latest'
	}) or { panic(err) }
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{}) or {
		panic(err)
	}
	assert state.requests[0].url == 'https://api.eu.mistral.ai/v1/chat/completions'
	assert state.requests[0].body.contains('"model":"mistral-small-latest"')
}

fn test_streaming_translates_mistral_request_fields() {
	mut ctx := context.background()
	client, state := new_fixture_client('data: {"choices":[{"index":0,"delta":{"content":"ok"},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n', 200)
	mut streamed := &StreamCapture{}
	stream := llms.StreamFunc(fn [mut streamed] (mut _ context.Context, chunk []u8) ! {
		streamed.value += chunk.bytestr()
	})
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		max_tokens:     24
		seed:           17
		streaming_func: stream
	}) or { panic(err) }
	assert response.choices[0].content == 'ok'
	assert streamed.value == 'ok'
	assert state.requests[0].body.contains('"stream":true')
	assert state.requests[0].body.contains('"max_tokens":24')
	assert state.requests[0].body.contains('"random_seed":17')
	assert !state.requests[0].body.contains('"max_completion_tokens"')
	assert !state.requests[0].body.contains('"seed":17')
}

fn test_constructor_rejects_empty_api_key() {
	new_client('', FakeHTTPClient{
		state: &FakeHTTPState{}
	}) or {
		assert err.msg().contains('API key')
		return
	}
	assert false, 'expected empty key to fail'
}
