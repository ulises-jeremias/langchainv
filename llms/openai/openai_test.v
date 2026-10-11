module openai

import context
import net.http
import json2
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
		end := if offset + 11 < body.len { offset + 11 } else { body.len }
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

fn test_generate_content_encodes_function_tools_and_tool_choice() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"choices":[{"index":0,"message":{"role":"assistant","content":"ready"},"finish_reason":"stop"}]}', 200)
	client.generate_content(mut ctx, [schema.text_message(.human, 'use lookup')], llms.CallOptions{
		tools:       [schema.ToolDefinition{
			name:        'lookup'
			description: 'Look up a value'
			parameters:  json2.Any(map[string]json2.Any{})
		}]
		tool_choice: schema.ToolChoice{
			mode: 'required'
		}
	}) or { panic(err) }
	assert state.requests[0].body.contains('"type":"function"')
	assert state.requests[0].body.contains('"name":"lookup"')
	assert state.requests[0].body.contains('"tool_choice":"required"')
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

fn test_client_rejects_unsupported_options_before_network() {
	mut ctx := context.background()
	client, state := new_fixture_client('{}', 200)
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		top_k: 3
	}) or {
		assert err.msg().contains('does not support')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected unsupported option error'
}

fn test_generate_content_streams_text_and_maps_usage() {
	mut ctx := context.background()
	response_body := 'data: {"choices":[{"index":0,"delta":{"content":"hel"}}]}\n\ndata: {"choices":[{"index":0,"delta":{"content":"lo"},"finish_reason":"stop"}]}\n\ndata: {"choices":[],"usage":{"prompt_tokens":2,"completion_tokens":2,"total_tokens":4}}\n\ndata: [DONE]\n\n'
	client, state := new_fixture_client(response_body, 200)
	mut streamed := &StreamCapture{}
	stream := llms.StreamFunc(fn [mut streamed] (mut _ context.Context, chunk []u8) ! {
		streamed.value += chunk.bytestr()
	})
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		streaming_func: stream
	}) or { panic(err) }
	assert streamed.value == 'hello'
	assert response.choices.len == 1
	assert response.choices[0].content == 'hello'
	assert response.choices[0].stop_reason == 'stop'
	assert response.usage.total_tokens == 4
	assert state.requests[0].headers['Accept'] == 'text/event-stream'
	assert state.requests[0].body.contains('"stream":true')
}
