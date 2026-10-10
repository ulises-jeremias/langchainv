module cloudflare

import context
import net.http
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

const test_account_id = '0123456789abcdef0123456789abcdef'

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
	client := new_client('test-token', test_account_id, '@cf/meta/llama-3.1-8b-instruct', FakeHTTPClient{
		state: state
	}) or { panic(err) }
	return client, state
}

fn test_generate_content_uses_workers_ai_openai_compatible_route() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"choices":[{"index":0,"message":{"role":"assistant","content":"hello"},"finish_reason":"stop"}],"usage":{"prompt_tokens":4,"completion_tokens":2,"total_tokens":6}}', 200)
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		max_tokens: 24
	}) or { panic(err) }
	assert response.choices[0].content == 'hello'
	assert response.usage.total_tokens == 6
	assert state.requests.len == 1
	assert state.requests[0].url == 'https://api.cloudflare.com/client/v4/accounts/${test_account_id}/ai/v1/chat/completions'
	assert (state.requests[0].headers['Authorization'] or { '' }) == 'Bearer test-token'
	assert state.requests[0].body.contains('"model":"@cf/meta/llama-3.1-8b-instruct"')
	assert state.requests[0].body.contains('"max_tokens":24')
	assert !state.requests[0].body.contains('"max_completion_tokens"')
}

fn test_client_accepts_custom_base_url_and_uppercase_account_id() {
	mut ctx := context.background()
	mut state := &FakeHTTPState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"choices":[{"message":{"content":"ok"}}]}'
		}
	}
	client := new_client_with_options('test-token', FakeHTTPClient{
		state: state
	}, Options{
		base_url:   'https://api.example.test/client/v4/accounts/'
		account_id: test_account_id.to_upper()
		model:      '@cf/openai/gpt-oss-20b'
	}) or { panic(err) }
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{}) or {
		panic(err)
	}
	assert client.account_id == test_account_id
	assert state.requests[0].url == 'https://api.example.test/client/v4/accounts/${test_account_id}/ai/v1/chat/completions'
}

fn test_constructor_rejects_malformed_account_id_before_request() {
	new_client('test-token', 'not-an-account-id', '@cf/model', FakeHTTPClient{
		state: &FakeHTTPState{}
	}) or {
		assert err.msg().contains('32 hexadecimal')
		return
	}
	assert false, 'expected malformed account ID to fail'
}
