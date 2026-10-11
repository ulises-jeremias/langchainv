module cohere

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

fn test_generate_content_encodes_v2_chat_options_and_usage() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"message":{"content":[{"type":"text","text":"hello"}]},"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":7,"output_tokens":3}}}', 200)
	response := client.generate_content(mut ctx, [
		schema.text_message(.system, 'Be concise.'),
		schema.text_message(.human, 'hi'),
	], llms.CallOptions{
		model:       'command-test'
		max_tokens:  32
		temperature: 0.2
		top_p:       0.7
		top_k:       40
		stop_words:  ['STOP']
	}) or { panic(err) }
	assert response.choices.len == 1
	assert response.choices[0].content == 'hello'
	assert response.choices[0].stop_reason == 'complete'
	assert response.usage.prompt_tokens == 7
	assert response.usage.completion_tokens == 3
	assert response.usage.total_tokens == 10
	assert state.requests.len == 1
	assert state.requests[0].url == 'https://api.cohere.com/v2/chat'
	assert (state.requests[0].headers['Authorization'] or { '' }) == 'Bearer test-secret'
	assert state.requests[0].body.contains('"model":"command-test"')
	assert state.requests[0].body.contains('"max_tokens":32')
	assert state.requests[0].body.contains('"temperature":0.2')
	assert state.requests[0].body.contains('"p":0.7')
	assert state.requests[0].body.contains('"k":40')
	assert state.requests[0].body.contains('"stop_sequences":["STOP"]')
	assert state.requests[0].body.contains('"role":"system"')
}

fn test_generate_content_encodes_tools_and_maps_tool_calls() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"message":{"tool_calls":[{"id":"lookup-1","type":"function","function":{"name":"lookup","arguments":"{\\"query\\":\\"v\\"}"}}]},"finish_reason":"TOOL_CALL"}', 200)
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'lookup')], llms.CallOptions{
		tools:       [schema.ToolDefinition{
			name:        'lookup'
			description: 'Look up a value'
			parameters:  json2.Any({
				'type': json2.Any('object')
			})
		}]
		tool_choice: schema.ToolChoice{
			mode: 'required'
		}
	}) or { panic(err) }
	assert response.choices[0].tool_calls.len == 1
	assert response.choices[0].tool_calls[0].id == 'lookup-1'
	assert response.choices[0].tool_calls[0].function_call.name == 'lookup'
	assert response.choices[0].tool_calls[0].function_call.arguments.contains('"query":"v"')
	assert response.choices[0].stop_reason == 'tool_call'
	assert state.requests[0].body.contains('"type":"function"')
	assert state.requests[0].body.contains('"tool_choice":"REQUIRED"')
}

fn test_generate_content_replays_tool_results() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"message":{"content":[{"type":"text","text":"done"}]}}', 200)
	message := schema.Message{
		role:  .tool
		parts: [schema.ContentPart(schema.ToolResult{
			call_id: 'lookup-1'
			name:    'lookup'
			content: 'found'
		})]
	}
	client.generate_content(mut ctx, [message], llms.CallOptions{}) or { panic(err) }
	assert state.requests[0].body.contains('"tool_call_id":"lookup-1"')
	assert state.requests[0].body.contains('"type":"document"')
	assert state.requests[0].body.contains('"data":"found"')
}

fn test_client_rejects_streaming_before_network() {
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

fn test_client_rejects_out_of_range_top_p_before_network() {
	mut ctx := context.background()
	client, state := new_fixture_client('{}', 200)
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		top_p: 1
	}) or {
		assert err.msg().contains('top_k')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected top_p range error'
}

fn test_generate_content_does_not_return_provider_error_body() {
	mut ctx := context.background()
	client, _ := new_fixture_client('{"error":"private detail"}', 401)
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{}) or {
		assert err.msg() == 'Cohere chat request returned HTTP 401'
		return
	}
	assert false, 'expected HTTP status error'
}
