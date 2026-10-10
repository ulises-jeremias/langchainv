module openai

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
	client := new_client('test-secret', FakeHTTPClient{
		state: state
	}) or { panic(err) }
	return client, state
}

fn test_generate_content_sends_text_chat_and_maps_usage() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"choices":[{"index":0,"message":{"role":"assistant","content":"hello","tool_calls":[]},"finish_reason":"stop"}],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}', 200)
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		model:      'gpt-test'
		max_tokens: 32
	}) or { panic(err) }
	assert response.choices.len == 1
	assert response.choices[0].content == 'hello'
	assert response.choices[0].stop_reason == 'stop'
	assert response.usage.prompt_tokens == 3
	assert response.usage.completion_tokens == 2
	assert state.requests.len == 1
	assert state.requests[0].url == 'https://api.openai.com/v1/chat/completions'
	assert (state.requests[0].headers['Authorization'] or { '' }) == 'Bearer test-secret'
	assert state.requests[0].body.contains('"model":"gpt-test"')
	assert state.requests[0].body.contains('"max_completion_tokens":32')
	assert state.requests[0].body.contains('"content":"hi"')
}

fn test_generate_content_maps_tool_calls() {
	mut ctx := context.background()
	client, _ := new_fixture_client('{"choices":[{"index":0,"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call-1","type":"function","function":{"name":"lookup","arguments":"{\\"q\\":\\"v\\"}"}}]},"finish_reason":"tool_calls"}]}', 200)
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'lookup')], llms.CallOptions{}) or {
		panic(err)
	}
	assert response.choices[0].tool_calls.len == 1
	assert response.choices[0].tool_calls[0].id == 'call-1'
	assert response.choices[0].tool_calls[0].function_call.name == 'lookup'
}

fn test_generate_content_does_not_return_provider_error_body() {
	mut ctx := context.background()
	client, _ := new_fixture_client('{"error":"contains sensitive provider detail"}', 429)
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{}) or {
		assert err.msg() == 'OpenAI chat completion request returned HTTP 429'
		return
	}
	assert false, 'expected HTTP status error'
}

fn test_complete_uses_user_message() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"choices":[{"index":0,"message":{"role":"assistant","content":"answer"},"finish_reason":"stop"}]}', 200)
	result := client.complete(mut ctx, 'question', llms.CallOptions{}) or { panic(err) }
	assert result == 'answer'
	assert state.requests[0].body.contains('"role":"user"')
}

fn test_client_rejects_streaming_and_unsupported_options_before_network() {
	mut ctx := context.background()
	client, state := new_fixture_client('{}', 200)
	stream := llms.StreamFunc(fn (mut _ context.Context, _ []u8) ! {})
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		streaming_func: stream
	}) or {
		assert err.msg().contains('streaming is not supported')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected streaming option error'
}
