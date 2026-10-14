module mistral

import context
import net.http
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

@[heap]
struct SafePromptFakeState {
mut:
	requests []httputil.Request
}

struct SafePromptFakeClient {
	state &SafePromptFakeState
}

fn (client SafePromptFakeClient) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	return httputil.Response{
		status_code: 200
		headers:     http.Header{}
		body:        '{"choices":[{"index":0,"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}'
	}
}

fn test_mistral_safe_prompt_is_sent_when_enabled() {
	mut state := &SafePromptFakeState{}
	client := new_client_with_options('test-secret', SafePromptFakeClient{
		state: state
	}, Options{
		base_url:    'https://mistral.test/v1'
		model:       'mistral-test'
		safe_prompt: true
	}) or { panic(err) }
	mut ctx := context.background()
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{}) or {
		panic(err)
	}
	assert state.requests[0].body.contains('"safe_prompt":true')
}

fn test_mistral_safe_prompt_is_omitted_by_default() {
	mut state := &SafePromptFakeState{}
	client := new_client_with_options('test-secret', SafePromptFakeClient{
		state: state
	}, Options{
		base_url: 'https://mistral.test/v1'
		model:    'mistral-test'
	}) or { panic(err) }
	mut ctx := context.background()
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{}) or {
		panic(err)
	}
	assert !state.requests[0].body.contains('safe_prompt')
}
