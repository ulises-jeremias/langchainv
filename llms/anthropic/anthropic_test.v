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

struct StreamCapture {
mut:
	value string
}

struct ReasoningCapture {
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

fn test_generate_content_streams_text_and_usage() {
	mut ctx := context.background()
	body := 'event: message_start\ndata: {"type":"message_start","message":{"usage":{"input_tokens":5}}}\n\nevent: content_block_start\ndata: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\nevent: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hel"}}\n\nevent: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lo"}}\n\nevent: content_block_stop\ndata: {"type":"content_block_stop","index":0}\n\nevent: message_delta\ndata: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":3}}\n\nevent: message_stop\ndata: {"type":"message_stop"}\n\n'
	client, state := new_fixture_client(body, 200)
	mut streamed := &StreamCapture{}
	stream := llms.StreamFunc(fn [mut streamed] (mut _ context.Context, chunk []u8) ! {
		streamed.value += chunk.bytestr()
	})
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		streaming_func: stream
	}) or { panic(err) }
	assert streamed.value == 'hello'
	assert response.choices[0].content == 'hello'
	assert response.choices[0].stop_reason == 'end_turn'
	assert response.usage.prompt_tokens == 5
	assert response.usage.completion_tokens == 3
	assert state.requests[0].body.contains('"stream":true')
	assert (state.requests[0].headers['Accept'] or { '' }) == 'text/event-stream'
}

fn test_generate_content_streams_tool_use_json_fragments() {
	mut ctx := context.background()
	body := 'event: message_start\ndata: {"type":"message_start","message":{"usage":{"input_tokens":4}}}\n\nevent: content_block_start\ndata: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu-1","name":"lookup","input":{}}}\n\nevent: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"q\\":"}}\n\nevent: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\\"v\\"}"}}\n\nevent: content_block_stop\ndata: {"type":"content_block_stop","index":0}\n\nevent: message_delta\ndata: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":3}}\n\nevent: message_stop\ndata: {"type":"message_stop"}\n\n'
	client, _ := new_fixture_client(body, 200)
	stream := llms.StreamFunc(fn (mut _ context.Context, _ []u8) ! {})
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'lookup')], llms.CallOptions{
		streaming_func: stream
	}) or { panic(err) }
	assert response.choices[0].tool_calls.len == 1
	assert response.choices[0].tool_calls[0].id == 'toolu-1'
	assert response.choices[0].tool_calls[0].function_call.name == 'lookup'
	assert response.choices[0].tool_calls[0].function_call.arguments == '{"q":"v"}'
	assert response.choices[0].stop_reason == 'tool_use'
}

fn test_generate_content_streams_reasoning_deltas() {
	mut ctx := context.background()
	body := 'event: message_start\ndata: {"type":"message_start","message":{"usage":{"input_tokens":2}}}\n\nevent: content_block_start\ndata: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}\n\nevent: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"plan"}}\n\nevent: message_delta\ndata: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":2}}\n\nevent: message_stop\ndata: {"type":"message_stop"}\n\n'
	client, _ := new_fixture_client(body, 200)
	mut captured := &ReasoningCapture{}
	stream := llms.ReasoningStreamFunc(fn [mut captured] (mut _ context.Context, reasoning []u8, _ []u8) ! {
		captured.value += reasoning.bytestr()
	})
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'reason')], llms.CallOptions{
		streaming_reasoning_func: stream
	}) or { panic(err) }
	assert captured.value == 'plan'
	assert response.choices[0].reasoning == 'plan'
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

fn test_client_rejects_unsupported_provider_options_before_network() {
	mut ctx := context.background()
	client, state := new_fixture_client('{}', 200)
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		provider_options: {
			'unsupported': json2.Any(true)
		}
	}) or {
		assert err.msg().contains('provider_options')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected unsupported provider options to fail'
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

fn test_generate_content_replays_thinking_and_redacted_parts() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"content":[{"type":"text","text":"final answer"}],"stop_reason":"end_turn","usage":{"input_tokens":5,"output_tokens":7}}', 200)
	messages := [
		schema.Message{
			role:  .ai
			parts: [
				schema.ContentPart(schema.ThinkingPart{
					text:      'let me think'
					signature: 'sig-123'
				}),
				schema.ContentPart(schema.RedactedThinkingPart{
					data: 'opaque-data'
				}),
				schema.ContentPart(schema.TextPart{
					text: 'previous answer'
				}),
			]
		},
		schema.text_message(.human, 'continue'),
	]
	response := client.generate_content(mut ctx, messages, llms.CallOptions{}) or { panic(err) }
	assert response.choices[0].content == 'final answer'
	body := state.requests[0].body
	assert body.contains('"type":"thinking"')
	assert body.contains('"signature":"sig-123"')
	assert body.contains('"type":"redacted_thinking"')
	assert body.contains('"data":"opaque-data"')
}

fn test_generate_content_parses_thinking_signature_and_redacted() {
	mut ctx := context.background()
	client, _ := new_fixture_client('{"content":[{"type":"thinking","thinking":"deep thought","signature":"sig-xyz"},{"type":"redacted_thinking","data":"hidden"},{"type":"text","text":"done"}],"stop_reason":"end_turn","usage":{"input_tokens":5,"output_tokens":7}}', 200)
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'think')], llms.CallOptions{}) or {
		panic(err)
	}
	choice := response.choices[0]
	assert choice.content == 'done'
	assert choice.reasoning == 'deep thought'
	assert choice.parts.len == 3
	thinking := choice.parts[0]
	assert thinking is schema.ThinkingPart
	if thinking is schema.ThinkingPart {
		assert thinking.signature == 'sig-xyz'
	}
	redacted := choice.parts[1]
	assert redacted is schema.RedactedThinkingPart
	if redacted is schema.RedactedThinkingPart {
		assert redacted.data == 'hidden'
	}
}

fn test_generate_content_rejects_unsigned_thinking_replay() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"content":[]}', 200)
	messages := [
		schema.Message{
			role:  .ai
			parts: [
				schema.ContentPart(schema.ThinkingPart{
					text: 'unsigned thought'
				}),
			]
		},
	]
	client.generate_content(mut ctx, messages, llms.CallOptions{}) or {
		assert err.msg().contains('signature')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected unsigned thinking replay to fail'
}
