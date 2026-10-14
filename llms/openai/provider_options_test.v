module openai

import context
import json2
import net.http
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

@[heap]
struct ProviderOptionsFakeState {
mut:
	requests []httputil.Request
	response httputil.Response
}

struct ProviderOptionsFakeClient {
	state &ProviderOptionsFakeState
}

fn (client ProviderOptionsFakeClient) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	return state.response
}

fn new_provider_options_client() (Client, &ProviderOptionsFakeState) {
	mut state := &ProviderOptionsFakeState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"choices":[{"index":0,"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}'
		}
	}
	client := new_client_with_options('test-secret', ProviderOptionsFakeClient{
		state: state
	}, Options{
		base_url: 'https://openai.test/v1'
		model:    'test-model'
	}) or { panic(err) }
	return client, state
}

fn test_generate_content_sends_typed_provider_options() {
	client, state := new_provider_options_client()
	mut ctx := context.background()
	mut options := llms.CallOptions{}
	options.provider_options['user'] = json2.Any('end-user-42')
	options.provider_options['parallel_tool_calls'] = json2.Any(false)
	options.provider_options['service_tier'] = json2.Any('flex')
	options.provider_options['logprobs'] = json2.Any(true)
	options.provider_options['top_logprobs'] = json2.Any(3)
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], options) or {
		panic(err)
	}
	assert response.choices[0].content == 'ok'
	body := state.requests[0].body
	assert body.contains('"user":"end-user-42"')
	assert body.contains('"parallel_tool_calls":false')
	assert body.contains('"service_tier":"flex"')
	assert body.contains('"logprobs":true')
	assert body.contains('"top_logprobs":3')
}

fn test_generate_content_rejects_invalid_provider_options() {
	mut ctx := context.background()
	for provider_options in [
		{
			'unknown_option': json2.Any(true)
		},
		{
			'user': json2.Any(42)
		},
		{
			'top_logprobs': json2.Any(21)
		},
		{
			'service_tier': json2.Any('turbo')
		},
	] {
		client, state := new_provider_options_client()
		mut options := llms.CallOptions{}
		for key, value in provider_options {
			options.provider_options[key] = value
		}
		client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], options) or {
			assert err.msg().contains('provider_options')
			assert state.requests.len == 0
			continue
		}
		assert false, 'expected invalid provider options to fail'
	}
}
