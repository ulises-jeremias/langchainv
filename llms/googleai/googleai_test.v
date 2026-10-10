module googleai

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
	client := new_client_with_options('secret-key', FakeHTTPClient{
		state: state
	}, Options{
		base_url: 'https://generativelanguage.test/v1beta'
		model:    'gemini-test'
	}) or { panic(err) }
	return client, state
}

fn test_generate_content_maps_text_usage_and_google_wire_names() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"candidates":[{"content":{"parts":[{"text":"hello "},{"text":"Gemini"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":8,"candidatesTokenCount":3,"totalTokenCount":11}}', 200)
	response := client.generate_content(mut ctx, [
		schema.text_message(.system, 'Be brief'),
		schema.text_message(.human, 'Hi'),
	], llms.CallOptions{
		max_tokens:  20
		temperature: 0.7
		top_p:       0.8
		top_k:       5
		stop_words:  ['END']
	}) or { panic(err) }
	assert response.choices.len == 1
	assert response.choices[0].content == 'hello Gemini'
	assert response.choices[0].stop_reason == 'STOP'
	assert response.usage.prompt_tokens == 8
	assert response.usage.completion_tokens == 3
	assert response.usage.total_tokens == 11
	assert response.assistant_message().text() == 'hello Gemini'
	assert state.requests.len == 1
	assert state.requests[0].url == 'https://generativelanguage.test/v1beta/models/gemini-test:generateContent'
	assert state.requests[0].headers['x-goog-api-key'] == 'secret-key'
	assert state.requests[0].body.contains('"systemInstruction"')
	assert state.requests[0].body.contains('"generationConfig"')
	assert state.requests[0].body.contains('"maxOutputTokens":20')
	assert state.requests[0].body.contains('"stopSequences":["END"]')
	assert !state.requests[0].url.contains('secret-key')
}

fn test_generate_content_rejects_unsupported_forms_before_network() {
	mut ctx := context.background()
	client, state := new_fixture_client('{}', 200)
	client.generate_content(mut ctx, [schema.text_message(.human, 'Hi')], llms.CallOptions{
		json_mode: true
	}) or {
		assert err.msg().contains('unsupported')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected unsupported JSON mode to fail'
}

fn test_generate_content_requires_candidate_response() {
	mut ctx := context.background()
	client, _ := new_fixture_client('{"candidates":[]}', 200)
	client.generate_content(mut ctx, [schema.text_message(.human, 'Hi')], llms.CallOptions{}) or {
		assert err.msg().contains('no candidates')
		return
	}
	assert false, 'expected empty candidates to fail'
}

fn test_generate_content_hides_http_error_body() {
	mut ctx := context.background()
	client, _ := new_fixture_client('secret response', 403)
	client.generate_content(mut ctx, [schema.text_message(.human, 'Hi')], llms.CallOptions{}) or {
		assert err.msg().contains('HTTP 403')
		assert !err.msg().contains('secret response')
		return
	}
	assert false, 'expected HTTP error to fail'
}

fn test_new_client_rejects_non_https_and_invalid_model() {
	mut state := &FakeHTTPState{}
	new_client_with_options('key', FakeHTTPClient{
		state: state
	}, Options{
		base_url: 'http://google.test'
	}) or {
		assert err.msg().contains('https')
		return
	}
	assert false, 'expected HTTP endpoint to be rejected'
}
