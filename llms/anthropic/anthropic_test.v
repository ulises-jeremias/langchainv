module anthropic

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

fn test_generate_content_sends_text_messages_and_maps_usage() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"content":[{"type":"text","text":"hello"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}', 200)
	response := client.generate_content(mut ctx, [
		schema.text_message(.system, 'Be concise.'),
		schema.text_message(.human, 'hi'),
	], llms.CallOptions{
		model:      'claude-test'
		max_tokens: 32
		stop_words: ['STOP']
	}) or { panic(err) }
	assert response.choices.len == 1
	assert response.choices[0].content == 'hello'
	assert response.choices[0].stop_reason == 'end_turn'
	assert response.usage.prompt_tokens == 3
	assert response.usage.completion_tokens == 2
	assert response.usage.total_tokens == 5
	assert state.requests.len == 1
	assert state.requests[0].url == 'https://api.anthropic.com/v1/messages'
	assert (state.requests[0].headers['x-api-key'] or { '' }) == 'test-secret'
	assert (state.requests[0].headers['anthropic-version'] or { '' }) == '2023-06-01'
	assert state.requests[0].body.contains('"model":"claude-test"')
	assert state.requests[0].body.contains('"max_tokens":32')
	assert state.requests[0].body.contains('"system":"Be concise."')
	assert state.requests[0].body.contains('"stop_sequences":["STOP"]')
	assert state.requests[0].body.contains('"role":"user"')
}

fn test_generate_content_maps_tool_use_blocks() {
	mut ctx := context.background()
	client, _ := new_fixture_client('{"content":[{"type":"tool_use","id":"toolu-1","name":"lookup","input":{"query":"v"}}],"stop_reason":"tool_use","usage":{"input_tokens":4,"output_tokens":3}}', 200)
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'lookup')], llms.CallOptions{}) or {
		panic(err)
	}
	assert response.choices[0].tool_calls.len == 1
	assert response.choices[0].tool_calls[0].id == 'toolu-1'
	assert response.choices[0].tool_calls[0].function_call.name == 'lookup'
	assert response.choices[0].tool_calls[0].function_call.arguments.contains('"query":"v"')
}

fn test_generate_content_encodes_remote_and_inline_images() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"content":[{"type":"text","text":"seen"}]}', 200)
	message := schema.Message{
		role:  .human
		parts: [
			schema.ContentPart(schema.TextPart{
				text: 'Describe these.'
			}),
			schema.ContentPart(schema.ImageURLPart{
				url: 'https://example.test/image.png'
			}),
			schema.ContentPart(schema.BinaryPart{
				mime_type: 'image/png'
				data:      [u8(1), 2]
			}),
		]
	}
	client.generate_content(mut ctx, [message], llms.CallOptions{}) or { panic(err) }
	assert state.requests[0].body.contains('"type":"url"')
	assert state.requests[0].body.contains('"url":"https://example.test/image.png"')
	assert state.requests[0].body.contains('"type":"base64"')
	assert state.requests[0].body.contains('"media_type":"image/png"')
	assert state.requests[0].body.contains('"data":"AQI="')
}

fn test_generate_content_rejects_unsafe_image_urls() {
	mut ctx := context.background()
	client, state := new_fixture_client('{}', 200)
	message := schema.Message{
		role:  .human
		parts: [
			schema.ContentPart(schema.ImageURLPart{
				url: 'http://example.test/image.png'
			}),
		]
	}
	client.generate_content(mut ctx, [message], llms.CallOptions{}) or {
		assert err.msg().contains('HTTPS')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected non-HTTPS image URL to fail'
}

fn test_generate_content_rejects_image_url_credentials() {
	mut ctx := context.background()
	client, state := new_fixture_client('{}', 200)
	message := schema.Message{
		role:  .human
		parts: [
			schema.ContentPart(schema.ImageURLPart{
				url: 'https://user:secret@example.test/image.png'
			}),
		]
	}
	client.generate_content(mut ctx, [message], llms.CallOptions{}) or {
		assert err.msg().contains('user information')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected image URL credentials to fail'
}

fn test_generate_content_encodes_tools_and_choice() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"content":[{"type":"text","text":"ready"}],"stop_reason":"end_turn"}', 200)
	client.generate_content(mut ctx, [schema.text_message(.human, 'use lookup')], llms.CallOptions{
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
	assert state.requests[0].body.contains('"input_schema"')
	assert state.requests[0].body.contains('"type":"any"')
}

fn test_generate_content_replays_tool_results_as_user_content() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"content":[{"type":"text","text":"done"}]}', 200)
	message := schema.Message{
		role:  .tool
		parts: [
			schema.ContentPart(schema.ToolResult{
				call_id: 'toolu-1'
				name:    'lookup'
				content: 'found'
			}),
		]
	}
	client.generate_content(mut ctx, [message], llms.CallOptions{}) or { panic(err) }
	assert state.requests[0].body.contains('"type":"tool_result"')
	assert state.requests[0].body.contains('"tool_use_id":"toolu-1"')
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

fn test_generate_content_does_not_return_provider_error_body() {
	mut ctx := context.background()
	client, _ := new_fixture_client('{"error":"private detail"}', 401)
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{}) or {
		assert err.msg() == 'Anthropic message request returned HTTP 401'
		return
	}
	assert false, 'expected HTTP status error'
}
