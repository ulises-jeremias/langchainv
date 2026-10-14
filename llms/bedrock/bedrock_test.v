module bedrock

import context
import hash.crc32
import net.http
import json2
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

@[heap]
struct BedrockFixtureState {
mut:
	requests []httputil.Request
	response httputil.Response
}

struct BedrockFixtureHTTP {
	state &BedrockFixtureState
}

fn (client BedrockFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	return state.response
}

fn (client BedrockFixtureHTTP) do_stream(mut ctx context.Context, request httputil.Request, handler httputil.StreamHandler) !httputil.Response {
	mut state := client.state
	state.requests << request
	body := state.response.body.bytes()
	mut offset := 0
	for offset < body.len {
		end := if offset + 19 < body.len { offset + 19 } else { body.len }
		handler(mut ctx, body[offset..end])!
		offset = end
	}
	return state.response
}

struct StreamCapture {
mut:
	value string
}

struct ReasoningCapture {
mut:
	value string
}

fn append_u32_be(mut bytes []u8, value u32) {
	bytes << u8(value >> 24)
	bytes << u8(value >> 16)
	bytes << u8(value >> 8)
	bytes << u8(value)
}

fn event_stream_frame(payload string) []u8 {
	mut frame := []u8{}
	append_u32_be(mut frame, u32(payload.len + 16))
	append_u32_be(mut frame, 0)
	append_u32_be(mut frame, crc32.sum(frame))
	frame << payload.bytes()
	append_u32_be(mut frame, crc32.sum(frame))
	return frame
}

fn event_stream_body(payloads []string) string {
	mut bytes := []u8{}
	for payload in payloads {
		bytes << event_stream_frame(payload)
	}
	return bytes.bytestr()
}

fn new_bedrock_fixture(body string) (Client, &BedrockFixtureState) {
	mut state := &BedrockFixtureState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        body
		}
	}
	client := new_client('fixture-bedrock-key', httputil.HTTPClient(BedrockFixtureHTTP{
		state: state
	})) or { panic(err) }
	return client, state
}

fn test_converse_text_request_and_usage_mapping() {
	mut ctx := context.background()
	client, state := new_bedrock_fixture('{"output":{"message":{"role":"assistant","content":[{"text":"hello"}]}},"stopReason":"end_turn","usage":{"inputTokens":4,"outputTokens":2,"totalTokens":6}}')
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		max_tokens:  64
		temperature: 0.4
		top_p:       0.9
		stop_words:  ['END']
	}) or { panic(err) }
	assert response.choices.len == 1
	assert response.choices[0].content == 'hello'
	assert response.choices[0].stop_reason == 'end_turn'
	assert response.usage.prompt_tokens == 4
	assert response.usage.completion_tokens == 2
	assert response.usage.total_tokens == 6
	assert state.requests.len == 1
	assert state.requests[0].url == 'https://bedrock-runtime.us-east-1.amazonaws.com/model/${default_model}/converse'
	assert (state.requests[0].headers['Authorization'] or { '' }) == 'Bearer fixture-bedrock-key'
	assert state.requests[0].body.contains('"maxTokens":64')
	assert state.requests[0].body.contains('"temperature":0.4')
	assert state.requests[0].body.contains('"topP":0.9')
	assert state.requests[0].body.contains('"stopSequences"')
	assert state.requests[0].body.contains('"role":"user"')
}

fn test_converse_maps_tool_use_and_schema() {
	mut ctx := context.background()
	client, state := new_bedrock_fixture('{"output":{"message":{"role":"assistant","content":[{"toolUse":{"toolUseId":"tool-1","name":"lookup","input":{"q":"v"}}}]}},"stopReason":"tool_use"}')
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'lookup')], llms.CallOptions{
		tools:       [schema.ToolDefinition{
			name:       'lookup'
			parameters: json2.Any(map[string]json2.Any{
				'type': json2.Any('object')
			})
		}]
		tool_choice: schema.ToolChoice{
			mode: 'required'
		}
	}) or { panic(err) }
	assert response.choices[0].tool_calls.len == 1
	assert response.choices[0].tool_calls[0].id == 'tool-1'
	assert response.choices[0].tool_calls[0].function_call.name == 'lookup'
	assert response.choices[0].tool_calls[0].function_call.arguments.contains('"q":"v"')
	assert state.requests[0].body.contains('"toolChoice"')
	assert state.requests[0].body.contains('"any"')
	assert state.requests[0].body.contains('"inputSchema"')
}

fn test_converse_replays_tool_result_and_rejects_unsupported_options() {
	call := schema.ToolCall{
		id:            'tool-1'
		call_type:     'function'
		function_call: schema.FunctionCall{
			name:      'lookup'
			arguments: '{"q":"v"}'
		}
	}
	messages := [
		schema.Message{
			role:  .ai
			parts: [schema.ContentPart(call)]
		},
		schema.Message{
			role:  .tool
			parts: [schema.ContentPart(schema.ToolResult{
				call_id: 'tool-1'
				content: 'found'
			})]
		},
	]
	request := make_request(messages, llms.CallOptions{}) or { panic(err) }
	assert json2.encode(request, json2.EncoderOptions{}).contains('"toolUseId":"tool-1"')
	mut ctx := context.background()
	client, state := new_bedrock_fixture('{}')
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		top_k: 4
	}) or {
		assert err.msg().contains('generation options')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected unsupported top_k rejection'
}

fn test_client_rejects_empty_key() {
	new_client_with_options('', httputil.HTTPClient(BedrockFixtureHTTP{
		state: &BedrockFixtureState{}
	}), Options{}) or {
		assert err.msg().contains('API key')
		return
	}
	assert false, 'expected empty API key rejection'
}

fn test_client_rejects_invalid_model_id() {
	new_client_with_options('key', httputil.HTTPClient(BedrockFixtureHTTP{
		state: &BedrockFixtureState{}
	}), Options{
		model_id: 'model/with/path'
	}) or {
		assert err.msg().contains('model ID is invalid')
		return
	}
	assert false, 'expected invalid model ID rejection'
}

fn test_client_rejects_invalid_region() {
	new_client_with_options('key', httputil.HTTPClient(BedrockFixtureHTTP{
		state: &BedrockFixtureState{}
	}), Options{
		region: 'bad region'
	}) or {
		assert err.msg().contains('region is invalid')
		return
	}
	assert false, 'expected invalid region rejection'
}

fn test_converse_streams_text_and_usage() {
	mut ctx := context.background()
	body := event_stream_body([
		'{"messageStart":{"role":"assistant"}}',
		'{"contentBlockDelta":{"contentBlockIndex":0,"delta":{"text":"hel"}}}',
		'{"contentBlockDelta":{"contentBlockIndex":0,"delta":{"text":"lo"}}}',
		'{"messageStop":{"stopReason":"end_turn"}}',
		'{"metadata":{"usage":{"inputTokens":5,"outputTokens":2,"totalTokens":7}}}',
	])
	client, state := new_bedrock_fixture(body)
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
	assert response.usage.completion_tokens == 2
	assert response.usage.total_tokens == 7
	assert state.requests[0].url.ends_with('/converse-stream')
	assert (state.requests[0].headers['Accept'] or { '' }) == 'application/vnd.amazon.eventstream'
}

fn test_converse_streams_fragmented_tool_input() {
	mut ctx := context.background()
	body := event_stream_body([
		'{"contentBlockStart":{"contentBlockIndex":0,"start":{"toolUse":{"toolUseId":"call-1","name":"lookup"}}}}',
		'{"contentBlockDelta":{"contentBlockIndex":0,"delta":{"toolUse":{"input":"{\\"q\\":"}}}}',
		'{"contentBlockDelta":{"contentBlockIndex":0,"delta":{"toolUse":{"input":"\\"v\\"}"}}}}',
		'{"messageStop":{"stopReason":"tool_use"}}',
	])
	client, _ := new_bedrock_fixture(body)
	stream := llms.StreamFunc(fn (mut _ context.Context, _ []u8) ! {})
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'lookup')], llms.CallOptions{
		streaming_func: stream
	}) or { panic(err) }
	assert response.choices[0].tool_calls.len == 1
	assert response.choices[0].tool_calls[0].id == 'call-1'
	assert response.choices[0].tool_calls[0].function_call.name == 'lookup'
	assert response.choices[0].tool_calls[0].function_call.arguments == '{"q":"v"}'
}

fn test_converse_streams_reasoning_deltas_and_signature() {
	mut ctx := context.background()
	body := event_stream_body([
		'{"contentBlockDelta":{"contentBlockIndex":0,"delta":{"reasoningContent":{"text":"plan"}}}}',
		'{"contentBlockDelta":{"contentBlockIndex":0,"delta":{"reasoningContent":{"signature":"sig-1"}}}}',
		'{"contentBlockDelta":{"contentBlockIndex":1,"delta":{"text":"answer"}}}',
		'{"messageStop":{"stopReason":"end_turn"}}',
	])
	client, _ := new_bedrock_fixture(body)
	mut captured := &ReasoningCapture{}
	stream := llms.ReasoningStreamFunc(fn [mut captured] (mut _ context.Context, reasoning []u8, output []u8) ! {
		captured.value += reasoning.bytestr() + output.bytestr()
	})
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'why?')], llms.CallOptions{
		streaming_reasoning_func: stream
	}) or { panic(err) }
	assert captured.value == 'plananswer'
	assert response.choices[0].content == 'answer'
	assert response.choices[0].parts.len == 2
	part := response.choices[0].parts[0]
	assert part is schema.ThinkingPart
	thinking := part as schema.ThinkingPart
	assert thinking.text == 'plan'
	assert thinking.signature == 'sig-1'
}

fn test_eventstream_decoder_rejects_bad_checksums_and_truncated_frames() {
	frame := event_stream_frame('{"messageStart":{"role":"assistant"}}')
	mut corrupted := frame.clone()
	corrupted[8] ^= u8(1)
	mut bad_crc_decoder := EventStreamDecoder{}
	bad_crc_decoder.push(corrupted) or {
		assert err.msg().contains('prelude checksum')
		return
	}
	assert false, 'expected invalid prelude checksum to fail'

	mut truncated_decoder := EventStreamDecoder{}
	truncated_decoder.push(frame[..frame.len - 1]) or { panic(err) }
	truncated_decoder.finish() or {
		assert err.msg().contains('truncated frame')
		return
	}
	assert false, 'expected truncated event stream frame to fail'
}

fn test_converse_parses_and_replays_reasoning_content() {
	mut ctx := context.background()
	client, state := new_bedrock_fixture('{"output":{"message":{"role":"assistant","content":[{"reasoningContent":{"reasoningText":{"text":"deep thought","signature":"sig-9"}}},{"reasoningContent":{"redactedContent":"hidden"}},{"text":"done"}]}},"stopReason":"end_turn","usage":{"inputTokens":5,"outputTokens":7,"totalTokens":12}}')
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'think')], llms.CallOptions{}) or {
		panic(err)
	}
	choice := response.choices[0]
	assert choice.content == 'done'
	assert choice.reasoning == 'deep thought'
	assert choice.parts.len == 3
	thinking := choice.parts[0]
	if thinking is schema.ThinkingPart {
		assert thinking.signature == 'sig-9'
	} else {
		assert false, 'expected a thinking part'
	}

	replay_client, replay_state := new_bedrock_fixture('{"output":{"message":{"role":"assistant","content":[{"text":"next"}]}},"stopReason":"end_turn"}')
	messages := [
		schema.Message{
			role:  .ai
			parts: choice.parts.clone()
		},
		schema.text_message(.human, 'continue'),
	]
	replay_client.generate_content(mut ctx, messages, llms.CallOptions{}) or { panic(err) }
	body := replay_state.requests[0].body
	assert body.contains('"reasoningContent":{"reasoningText":{"signature":"sig-9","text":"deep thought"}}')
		|| body.contains('"signature":"sig-9"')
	assert body.contains('"redactedContent":"hidden"')
	assert state.requests.len == 1
}

fn test_converse_rejects_unsigned_reasoning_replay() {
	mut ctx := context.background()
	client, state := new_bedrock_fixture('{}')
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
	assert false, 'expected unsigned reasoning replay to fail'
}
