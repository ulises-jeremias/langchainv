module llamafile

import context
import net.http
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

@[heap]
struct LlamafileFixtureState {
mut:
	requests []httputil.Request
	response httputil.Response
}

struct LlamafileFixtureHTTP {
	state &LlamafileFixtureState
}

fn (client LlamafileFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	return state.response
}

fn test_default_client_uses_loopback_openai_compatible_endpoint() {
	mut state := &LlamafileFixtureState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"choices":[{"index":0,"message":{"role":"assistant","content":"hello"},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3}}'
		}
	}
	client := new_client(httputil.HTTPClient(LlamafileFixtureHTTP{
		state: state
	}), Options{}) or { panic(err) }
	mut ctx := context.background()
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{}) or {
		panic(err)
	}
	assert response.choices.len == 1
	assert response.choices[0].content == 'hello'
	assert response.usage.total_tokens == 3
	assert state.requests.len == 1
	assert state.requests[0].url == '${default_base_url}/chat/completions'
	assert (state.requests[0].headers['Authorization'] or { '' }) == 'Bearer ${default_api_key}'
	assert state.requests[0].body.contains('"model":"${default_model}"')
}

fn test_custom_secure_endpoint_and_completion_contract() {
	mut state := &LlamafileFixtureState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"choices":[{"index":0,"message":{"role":"assistant","content":"answer"},"finish_reason":"stop"}]}'
		}
	}
	client := new_client(httputil.HTTPClient(LlamafileFixtureHTTP{
		state: state
	}), Options{
		base_url: 'https://llamafile.example.test/v1'
		model:    'custom-model'
		api_key:  'custom-token'
	}) or { panic(err) }
	mut ctx := context.background()
	result := client.complete(mut ctx, 'question', llms.CallOptions{}) or { panic(err) }
	assert result == 'answer'
	assert state.requests[0].url == 'https://llamafile.example.test/v1/chat/completions'
	assert (state.requests[0].headers['Authorization'] or { '' }) == 'Bearer custom-token'
	assert state.requests[0].body.contains('"role":"user"')
}

fn test_client_rejects_remote_cleartext_urls() {
	new_client(httputil.HTTPClient(LlamafileFixtureHTTP{
		state: &LlamafileFixtureState{}
	}), Options{
		base_url: 'http://10.0.0.5:8080/v1'
	}) or {
		assert err.msg().contains('HTTPS or loopback HTTP')
		return
	}
	assert false, 'expected remote cleartext endpoint rejection'
}

fn test_client_rejects_base_url_with_user_information() {
	new_client(httputil.HTTPClient(LlamafileFixtureHTTP{
		state: &LlamafileFixtureState{}
	}), Options{
		base_url: 'https://user:password@llamafile.example.test/v1'
	}) or {
		assert err.msg().contains('valid HTTP(S)')
		return
	}
	assert false, 'expected URL user information rejection'
}
