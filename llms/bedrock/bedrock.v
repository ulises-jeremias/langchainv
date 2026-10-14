// Package bedrock implements bounded chat generation through Bedrock Converse.
module bedrock

import context
import encoding.base64
import hash.crc32
import json2
import math
import ulises_jeremias.langchainv.callbacks
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

const default_model = 'anthropic.claude-3-5-haiku-20241022-v1:0'
const max_request_bytes = 5 * 1024 * 1024
const max_response_bytes = 8 * 1024 * 1024
const max_reasoning_bytes = 1024 * 1024
const max_image_bytes = 3 * 1024 * 1024
const max_message_content_bytes = 4 * 1024 * 1024
const max_stream_frame_bytes = 1024 * 1024

struct BedrockStreamEvent {
	content_block_start ?BedrockStreamStartEvent @[json: 'contentBlockStart']
	content_block_delta ?BedrockStreamDeltaEvent @[json: 'contentBlockDelta']
	message_stop        ?BedrockStreamStopEvent  @[json: 'messageStop']
	metadata            ?BedrockStreamMetadataEvent
}

struct BedrockStreamStartEvent {
	content_block_index int @[json: 'contentBlockIndex']
	start               BedrockStreamBlockStart
}

struct BedrockStreamBlockStart {
	tool_use ?BedrockStreamToolStart @[json: 'toolUse']
}

struct BedrockStreamToolStart {
	tool_use_id string @[json: 'toolUseId']
	name        string
}

struct BedrockStreamDeltaEvent {
	content_block_index int @[json: 'contentBlockIndex']
	delta               BedrockStreamDelta
}

struct BedrockStreamDelta {
	text      string
	tool_use  ?BedrockStreamToolDelta @[json: 'toolUse']
	reasoning ?BedrockStreamReasoning @[json: 'reasoningContent']
}

struct BedrockStreamToolDelta {
	input string
}

struct BedrockStreamReasoning {
	text             string
	signature        string
	redacted_content string @[json: 'redactedContent']
}

struct BedrockStreamStopEvent {
	stop_reason string @[json: 'stopReason']
}

struct BedrockStreamMetadataEvent {
	usage BedrockStreamUsage
}

struct BedrockStreamUsage {
	input_tokens  int @[json: 'inputTokens']
	output_tokens int @[json: 'outputTokens']
	total_tokens  int @[json: 'totalTokens']
}

struct BedrockStreamBlock {
	index     int
	text      string
	reasoning string
	signature string
	redacted  string
	tool_id   string
	tool_name string
	tool_json string
}

struct BedrockStreamState {
mut:
	content        string
	stop_reason    string
	input_tokens   int
	output_tokens  int
	total_tokens   int
	blocks         []BedrockStreamBlock
	received_bytes i64
	error          string
}

struct EventStreamDecoder {
mut:
	buffer []u8
pub:
	max_frame_bytes int = max_stream_frame_bytes
}

fn (mut decoder EventStreamDecoder) push(chunk []u8) ![][]u8 {
	if chunk.len > max_response_bytes - decoder.buffer.len {
		return error('Amazon Bedrock Converse stream exceeds 8 MiB')
	}
	decoder.buffer << chunk
	mut payloads := [][]u8{}
	for decoder.buffer.len >= 12 {
		total_length := read_u32_be(decoder.buffer, 0)
		header_length := read_u32_be(decoder.buffer, 4)
		if total_length < 16 || total_length > u32(decoder.max_frame_bytes)
			|| header_length > total_length - 16 {
			return error('Amazon Bedrock event stream frame has invalid lengths')
		}
		if decoder.buffer.len < int(total_length) {
			break
		}
		frame := decoder.buffer[..int(total_length)].clone()
		if crc32.sum(frame[..8]) != read_u32_be(frame, 8) {
			return error('Amazon Bedrock event stream prelude checksum is invalid')
		}
		if crc32.sum(frame[..int(total_length) - 4]) != read_u32_be(frame,
			int(total_length) - 4) {
			return error('Amazon Bedrock event stream message checksum is invalid')
		}
		payload_start := 12 + int(header_length)
		payloads << frame[payload_start..int(total_length) - 4].clone()
		decoder.buffer = decoder.buffer[int(total_length)..].clone()
	}
	return payloads
}

fn (mut decoder EventStreamDecoder) finish() ! {
	if decoder.buffer.len != 0 {
		return error('Amazon Bedrock event stream ended with a truncated frame')
	}
}

fn read_u32_be(bytes []u8, offset int) u32 {
	return (u32(bytes[offset]) << 24) | (u32(bytes[offset + 1]) << 16) |
		(u32(bytes[offset + 2]) << 8) | u32(bytes[offset + 3])
}

// Options configures an AWS region and a Bedrock Converse model ID.
pub struct Options {
pub:
	region    string = 'us-east-1'
	model_id  string = default_model
	callbacks ?callbacks.Handler
}

// Client calls the Bedrock Runtime Converse operation using a Bedrock API key.
pub struct Client {
mut:
	api_key     string
	http_client httputil.HTTPClient
pub:
	region   string
	model_id string
pub mut:
	callbacks ?callbacks.Handler
}

// new_client constructs a client with default region and model settings.
pub fn new_client(api_key string, http_client httputil.HTTPClient) !Client {
	return new_client_with_options(api_key, http_client, Options{})
}

// new_default_client uses the shared bounded standard-library HTTP transport.
pub fn new_default_client(api_key string) !Client {
	return new_client(api_key, httputil.HTTPClient(httputil.new_default_client()))
}

// new_client_with_options validates key, region, and model ID configuration.
pub fn new_client_with_options(api_key string, http_client httputil.HTTPClient, options Options) !Client {
	key := api_key.trim_space()
	region := options.region.trim_space().to_lower()
	model_id := options.model_id.trim_space()
	if key == '' {
		return error('Amazon Bedrock API key must not be empty')
	}
	if key.len > 16 * 1024 {
		return error('Amazon Bedrock API key exceeds 16 KiB')
	}
	if !valid_region(region) {
		return error('Amazon Bedrock region is invalid')
	}
	if !valid_model_id(model_id) {
		return error('Amazon Bedrock model ID is invalid or exceeds 512 bytes')
	}
	return Client{
		api_key:     key
		http_client: http_client
		region:      region
		model_id:    model_id
		callbacks:   options.callbacks
	}
}

// generate_content sends text, image, and tool messages to Converse.
pub fn (client Client) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	llms.validate_messages(messages)!
	if mut handler := client.callbacks {
		handler.llm_generate_content_start(mut ctx, messages)
	}
	response := client.generate_content_request(mut ctx, messages, options) or {
		if mut handler := client.callbacks {
			handler.llm_error(mut ctx, err)
		}
		return err
	}
	if mut handler := client.callbacks {
		handler.llm_generate_content_end(mut ctx, response)
	}
	return response
}

fn (client Client) generate_content_request(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	llms.validate_messages(messages)!
	validate_options(options)!
	model := if options.model.trim_space() == '' {
		client.model_id
	} else {
		options.model.trim_space()
	}
	if !valid_model_id(model) {
		return error('Amazon Bedrock model ID is invalid or exceeds 512 bytes')
	}
	request := make_request(messages, options)!
	body := json2.encode(request, json2.EncoderOptions{})
	if body.len > max_request_bytes {
		return error('Amazon Bedrock Converse request exceeds 5 MiB')
	}
	if _ := options.streaming_func {
		return client.generate_stream(mut ctx, model, body, options)
	}
	if _ := options.streaming_reasoning_func {
		return client.generate_stream(mut ctx, model, body, options)
	}
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	response := client.http_client.do(mut ctx, httputil.Request{
		method:  .post
		url:     'https://bedrock-runtime.${client.region}.amazonaws.com/model/${model}/converse'
		headers: {
			'Authorization': 'Bearer ${client.api_key}'
			'Content-Type':  'application/json'
			'Accept':        'application/json'
		}
		body:    body
	}) or {
		return error('Amazon Bedrock Converse request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Amazon Bedrock Converse request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_response_bytes {
		return error('Amazon Bedrock Converse response exceeds 8 MiB')
	}
	decoded := json2.decode[map[string]json2.Any](response.body, json2.DecoderOptions{}) or {
		return error('Amazon Bedrock returned an invalid Converse response')
	}
	return parse_response(decoded)
}

fn (client Client) generate_stream(mut ctx context.Context, model string, body string, options llms.CallOptions) !llms.Response {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	if client.http_client !is httputil.StreamingHTTPClient {
		return error('configured Amazon Bedrock HTTP transport does not support streaming responses')
	}
	stream_client := client.http_client as httputil.StreamingHTTPClient
	mut decoder := EventStreamDecoder{}
	mut state := &BedrockStreamState{}
	mut process_event := fn [options, mut state] (mut callback_ctx context.Context, payload []u8) {
		raw := json2.decode[map[string]json2.Any](payload.bytestr(), json2.DecoderOptions{}) or {
			state.error = 'Amazon Bedrock returned an invalid event stream payload'
			return
		}
		event := json2.decode[BedrockStreamEvent](payload.bytestr(), json2.DecoderOptions{}) or {
			state.error = 'Amazon Bedrock returned an invalid event stream payload'
			return
		}
		if start := event.content_block_start {
			if start.content_block_index < 0 || start.content_block_index >= 128 {
				state.error = 'Amazon Bedrock content block index is outside the supported range'
				return
			}
			for state.blocks.len <= start.content_block_index {
				state.blocks << BedrockStreamBlock{
					index: state.blocks.len
				}
			}
			if start_value := raw['contentBlockStart'] {
				if start_value is map[string]json2.Any {
					start_map := start_value as map[string]json2.Any
					if start_data := start_map['start'] {
						if start_data is map[string]json2.Any {
							for key in (start_data as map[string]json2.Any).keys() {
								if key != 'toolUse' {
									state.error = 'Amazon Bedrock returned an unsupported content block start'
									return
								}
							}
						}
					}
				}
			}
			if tool := start.start.tool_use {
				state.blocks[start.content_block_index] = BedrockStreamBlock{
					index:     start.content_block_index
					tool_id:   tool.tool_use_id
					tool_name: tool.name
				}
			}
			return
		}
		if delta_event := event.content_block_delta {
			if delta_event.content_block_index < 0 || delta_event.content_block_index >= 128 {
				state.error = 'Amazon Bedrock content block index is outside the supported range'
				return
			}
			for state.blocks.len <= delta_event.content_block_index {
				state.blocks << BedrockStreamBlock{
					index: state.blocks.len
				}
			}
			if delta_value := raw['contentBlockDelta'] {
				if delta_value is map[string]json2.Any {
					delta_map := delta_value as map[string]json2.Any
					if delta_content := delta_map['delta'] {
						if delta_content is map[string]json2.Any {
							for key in (delta_content as map[string]json2.Any).keys() {
								if key !in ['text', 'toolUse', 'reasoningContent'] {
									state.error = 'Amazon Bedrock returned an unsupported content block delta'
									return
								}
							}
						}
					}
				}
			}
			if delta_event.delta.text != '' {
				state.content += delta_event.delta.text
				block := state.blocks[delta_event.content_block_index]
				state.blocks[delta_event.content_block_index] = BedrockStreamBlock{
					index:     block.index
					text:      block.text + delta_event.delta.text
					reasoning: block.reasoning
					signature: block.signature
					redacted:  block.redacted
					tool_id:   block.tool_id
					tool_name: block.tool_name
					tool_json: block.tool_json
				}
				if callback := options.streaming_func {
					callback(mut callback_ctx, delta_event.delta.text.bytes()) or {
						state.error = 'Amazon Bedrock streaming callback failed: ${err.msg()}'
						return
					}
				}
				if callback := options.streaming_reasoning_func {
					callback(mut callback_ctx, []u8{}, delta_event.delta.text.bytes()) or {
						state.error = 'Amazon Bedrock reasoning callback failed: ${err.msg()}'
						return
					}
				}
			}
			if reasoning := delta_event.delta.reasoning {
				block := state.blocks[delta_event.content_block_index]
				state.blocks[delta_event.content_block_index] = BedrockStreamBlock{
					index:     block.index
					text:      block.text
					reasoning: block.reasoning + reasoning.text
					signature: block.signature + reasoning.signature
					redacted:  block.redacted + reasoning.redacted_content
					tool_id:   block.tool_id
					tool_name: block.tool_name
					tool_json: block.tool_json
				}
				if reasoning.text != '' {
					if callback := options.streaming_reasoning_func {
						callback(mut callback_ctx, reasoning.text.bytes(), []u8{}) or {
							state.error = 'Amazon Bedrock reasoning callback failed: ${err.msg()}'
							return
						}
					}
				}
			}
			if tool_delta := delta_event.delta.tool_use {
				block := state.blocks[delta_event.content_block_index]
				state.blocks[delta_event.content_block_index] = BedrockStreamBlock{
					index:     block.index
					text:      block.text
					reasoning: block.reasoning
					signature: block.signature
					redacted:  block.redacted
					tool_id:   block.tool_id
					tool_name: block.tool_name
					tool_json: block.tool_json + tool_delta.input
				}
			}
			return
		}
		if stop := event.message_stop {
			state.stop_reason = stop.stop_reason
			return
		}
		if metadata := event.metadata {
			state.input_tokens = metadata.usage.input_tokens
			state.output_tokens = metadata.usage.output_tokens
			state.total_tokens = metadata.usage.total_tokens
			return
		}
		for key in ['internalServerException', 'modelStreamErrorException',
			'serviceUnavailableException', 'throttlingException', 'validationException'] {
			if _ := raw[key] {
				state.error = 'Amazon Bedrock returned an error event while streaming'
				return
			}
		}
		for key in raw.keys() {
			if key in ['messageStart', 'contentBlockStop'] {
				return
			}
		}
		state.error = 'Amazon Bedrock returned an unsupported event while streaming'
	}
	response := stream_client.do_stream(mut ctx, httputil.Request{
		method:  .post
		url:     'https://bedrock-runtime.${client.region}.amazonaws.com/model/${model}/converse-stream'
		headers: {
			'Authorization': 'Bearer ${client.api_key}'
			'Content-Type':  'application/json'
			'Accept':        'application/vnd.amazon.eventstream'
		}
		body:    body
	}, fn [mut decoder, mut state, mut process_event] (mut callback_ctx context.Context, bytes []u8) ! {
		state.received_bytes += i64(bytes.len)
		if state.received_bytes > max_response_bytes {
			return error('Amazon Bedrock Converse response exceeds 8 MiB')
		}
		for payload in decoder.push(bytes)! {
			process_event(mut callback_ctx, payload)
			if state.error != '' {
				return error(state.error)
			}
		}
	}) or {
		return error('Amazon Bedrock ConverseStream request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Amazon Bedrock ConverseStream request returned HTTP ${response.status_code}')
	}
	decoder.finish()!
	mut parts := []schema.ContentPart{}
	mut tool_calls := []schema.ToolCall{}
	for block in state.blocks {
		if block.text != '' {
			parts << schema.ContentPart(schema.TextPart{
				text: block.text
			})
		}
		if block.reasoning != '' {
			parts << schema.ContentPart(schema.ThinkingPart{
				text:      block.reasoning
				signature: block.signature
			})
		}
		if block.redacted != '' {
			parts << schema.ContentPart(schema.RedactedThinkingPart{
				data: block.redacted
			})
		}
		if block.tool_id != '' || block.tool_name != '' || block.tool_json != '' {
			if block.tool_id == '' || block.tool_name == '' {
				return error('Amazon Bedrock toolUse block is missing name or ID')
			}
			input := json2.decode[json2.Any](block.tool_json, json2.DecoderOptions{}) or {
				return error('Amazon Bedrock streamed tool input is invalid JSON')
			}
			call := schema.ToolCall{
				id:            block.tool_id
				call_type:     'function'
				function_call: schema.FunctionCall{
					name:      block.tool_name
					arguments: json2.encode(input, json2.EncoderOptions{})
				}
			}
			tool_calls << call
			parts << schema.ContentPart(call)
		}
	}
	if parts.len == 0 {
		return error('Amazon Bedrock returned an empty streaming response')
	}
	total_tokens := if state.total_tokens > 0 {
		state.total_tokens
	} else {
		state.input_tokens + state.output_tokens
	}
	return llms.Response{
		choices: [llms.Choice{
			content:     state.content
			stop_reason: state.stop_reason
			tool_calls:  tool_calls
			parts:       parts
		}]
		usage:   llms.Usage{
			prompt_tokens:     state.input_tokens
			completion_tokens: state.output_tokens
			total_tokens:      total_tokens
		}
	}
}

// complete wraps a prompt as a user message and returns the first choice.
pub fn (client Client) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	response := client.generate_content(mut ctx, [schema.text_message(.human, prompt)], options)!
	if response.choices.len == 0 {
		return error('Amazon Bedrock returned no completion choices')
	}
	return response.choices[0].content
}

fn validate_options(options llms.CallOptions) ! {
	options.validate()!
	if options.top_k != 0 || options.seed != none || options.min_length != 0 || options.max_length != 0
		|| options.repetition_penalty != 0 || options.frequency_penalty != 0
		|| options.presence_penalty != 0 || options.n > 1 || options.candidate_count > 1 {
		return error('Amazon Bedrock Converse does not support one or more requested generation options')
	}
	if options.json_mode || options.response_mime_type != '' {
		return error('Amazon Bedrock Converse JSON response mode is not supported')
	}
	if options.functions.len > 0 || options.function_call_behavior != '' {
		return error('Amazon Bedrock Converse supports tools but not legacy function options')
	}
	if options.provider_options.len > 0 || options.metadata.len > 0 || options.web_search_options != none {
		return error('Amazon Bedrock Converse provider options are not supported')
	}
	if !math.is_finite(options.temperature) || options.temperature < 0 || options.temperature > 1
		|| !math.is_finite(options.top_p) {
		return error('Amazon Bedrock Converse temperature must be between zero and one')
	}
}

fn make_request(messages []schema.Message, options llms.CallOptions) !map[string]json2.Any {
	mut system_parts := []json2.Any{}
	mut wire_messages := []json2.Any{}
	mut limits := ConversionLimits{}
	for message in messages {
		if message.role == .system {
			for part in message.parts {
				if part !is schema.TextPart {
					return error('Amazon Bedrock system messages support text content only')
				}
				text := (part as schema.TextPart).text
				if text.len > max_message_content_bytes - limits.content_bytes {
					return error('Amazon Bedrock message content exceeds 4 MiB')
				}
				limits.content_bytes += text.len
				system_parts << json2.Any({
					'text': json2.Any(text)
				})
			}
			continue
		}
		wire_messages << json2.Any(convert_message(message, mut limits)!)
	}
	if wire_messages.len == 0 {
		return error('Amazon Bedrock requires at least one non-system message')
	}
	mut request := map[string]json2.Any{
		'messages': json2.Any(wire_messages)
	}
	if system_parts.len > 0 {
		request['system'] = json2.Any(system_parts)
	}
	mut inference := map[string]json2.Any{}
	if options.max_tokens > 0 {
		inference['maxTokens'] = json2.Any(options.max_tokens)
	}
	if options.temperature != 0 {
		inference['temperature'] = json2.Any(options.temperature)
	}
	if options.top_p > 0 {
		inference['topP'] = json2.Any(options.top_p)
	}
	if options.stop_words.len > 0 {
		mut stop_words := []json2.Any{cap: options.stop_words.len}
		for word in options.stop_words {
			stop_words << json2.Any(word)
		}
		inference['stopSequences'] = json2.Any(stop_words)
	}
	if inference.len > 0 {
		request['inferenceConfig'] = json2.Any(inference)
	}
	if options.tools.len > 0 {
		mut tool_specs := []json2.Any{cap: options.tools.len}
		for definition in options.tools {
			if definition.name.trim_space() == '' || definition.strict {
				return error('Amazon Bedrock tool names must be non-empty and strict mode is unsupported')
			}
			mut spec := map[string]json2.Any{
				'name':        json2.Any(definition.name)
				'inputSchema': json2.Any({
					'json': definition.parameters
				})
			}
			if definition.description != '' {
				spec['description'] = json2.Any(definition.description)
			}
			tool_specs << json2.Any({
				'toolSpec': json2.Any(spec)
			})
		}
		mut tool_config := map[string]json2.Any{
			'tools': json2.Any(tool_specs)
		}
		if choice := options.tool_choice {
			if choice.name != '' {
				tool_config['toolChoice'] = json2.Any({
					'tool': json2.Any({
						'name': json2.Any(choice.name)
					})
				})
			} else if choice.mode == 'auto' {
				tool_config['toolChoice'] = json2.Any({
					'auto': json2.Any(map[string]json2.Any{})
				})
			} else if choice.mode == 'required' {
				tool_config['toolChoice'] = json2.Any({
					'any': json2.Any(map[string]json2.Any{})
				})
			} else {
				return error('Amazon Bedrock Converse supports auto, required, or named tool choice')
			}
		}
		request['toolConfig'] = json2.Any(tool_config)
	} else if options.tool_choice != none {
		return error('Amazon Bedrock tool choice requires tool definitions')
	}
	return request
}

struct ConversionLimits {
mut:
	image_bytes   int
	content_bytes int
}

fn convert_message(message schema.Message, mut limits ConversionLimits) !map[string]json2.Any {
	role := match message.role {
		.human, .generic, .tool { 'user' }
		.ai { 'assistant' }
		.system { return error('invalid system message conversion') }
	}
	mut content := []json2.Any{}
	for part in message.parts {
		match part {
			schema.TextPart {
				if part.text.len > max_message_content_bytes - limits.content_bytes {
					return error('Amazon Bedrock message content exceeds 4 MiB')
				}
				limits.content_bytes += part.text.len
				content << json2.Any({
					'text': json2.Any(part.text)
				})
			}
			schema.BinaryPart {
				if message.role !in [.human, .generic] {
					return error('Amazon Bedrock inline images require user messages')
				}
				if part.mime_type !in ['image/jpeg', 'image/png'] || part.data.len == 0
					|| part.data.len > max_image_bytes - limits.image_bytes {
					return error('Amazon Bedrock images must be non-empty JPEG/PNG within the 3 MiB total limit')
				}
				limits.image_bytes += part.data.len
				format := if part.mime_type == 'image/jpeg' { 'jpeg' } else { 'png' }
				content << json2.Any({
					'image': json2.Any({
						'format': json2.Any(format)
						'source': json2.Any({
							'bytes': json2.Any(base64.encode(part.data))
						})
					})
				})
			}
			schema.ToolCall {
				if message.role != .ai || part.id == '' || part.function_call.name.trim_space() == '' {
					return error('Amazon Bedrock tool calls require assistant messages and a non-empty name')
				}
				if part.function_call.arguments.len > max_message_content_bytes - limits.content_bytes {
					return error('Amazon Bedrock message content exceeds 4 MiB')
				}
				limits.content_bytes += part.function_call.arguments.len
				tool_arguments := json2.decode[map[string]json2.Any](part.function_call.arguments,
					json2.DecoderOptions{}) or {
					return error('Amazon Bedrock tool call arguments must be a JSON object')
				}
				content << json2.Any({
					'toolUse': json2.Any({
						'toolUseId': json2.Any(part.id)
						'name':      json2.Any(part.function_call.name)
						'input':     json2.Any(tool_arguments)
					})
				})
			}
			schema.ToolResult {
				if message.role != .tool || part.call_id == '' {
					return error('Amazon Bedrock tool results require tool-role messages and a call ID')
				}
				if part.content.len > max_message_content_bytes - limits.content_bytes {
					return error('Amazon Bedrock message content exceeds 4 MiB')
				}
				limits.content_bytes += part.content.len
				content << json2.Any({
					'toolResult': json2.Any(map[string]json2.Any{
						'toolUseId': json2.Any(part.call_id)
						'content':   json2.Any([json2.Any(map[string]json2.Any{
							'text': json2.Any(part.content)
						})])
					})
				})
			}
			schema.ImageURLPart {
				return error('Amazon Bedrock Converse requires inline image data')
			}
			schema.ThinkingPart {
				if part.signature.trim_space() == '' {
					return error('Amazon Bedrock reasoning replay requires a signature from the original response')
				}
				if part.text.len > max_reasoning_bytes || part.signature.len > max_reasoning_bytes {
					return error('Amazon Bedrock reasoning replay exceeds the 1 MiB size limit')
				}
				content << json2.Any({
					'reasoningContent': json2.Any({
						'reasoningText': json2.Any({
							'text':      json2.Any(part.text)
							'signature': json2.Any(part.signature)
						})
					})
				})
			}
			schema.RedactedThinkingPart {
				if part.data.trim_space() == '' || part.data.len > max_reasoning_bytes {
					return error('Amazon Bedrock redacted reasoning replay requires opaque data up to 1 MiB')
				}
				content << json2.Any({
					'reasoningContent': json2.Any({
						'redactedContent': json2.Any(part.data)
					})
				})
			}
		}
	}
	if content.len == 0 {
		return error('Amazon Bedrock message has no supported content')
	}
	return {
		'role':    json2.Any(role)
		'content': json2.Any(content)
	}
}

fn parse_response(response map[string]json2.Any) !llms.Response {
	output := response['output'] or { return error('Amazon Bedrock response is missing output') }
	if output !is map[string]json2.Any {
		return error('Amazon Bedrock response output is invalid')
	}
	message_value := (output as map[string]json2.Any)['message'] or {
		return error('Amazon Bedrock response is missing assistant message')
	}
	if message_value !is map[string]json2.Any {
		return error('Amazon Bedrock response assistant message is invalid')
	}
	message := message_value as map[string]json2.Any
	blocks_value := message['content'] or { return error('Amazon Bedrock response content is missing') }
	if blocks_value !is []json2.Any {
		return error('Amazon Bedrock response content is invalid')
	}
	mut content := ''
	mut reasoning := ''
	mut parts := []schema.ContentPart{}
	mut tool_calls := []schema.ToolCall{}
	for block_value in blocks_value as []json2.Any {
		if block_value !is map[string]json2.Any {
			continue
		}
		block := block_value as map[string]json2.Any
		text := any_string(block['text'] or { json2.Any('') })
		if text != '' {
			content += text
			parts << schema.ContentPart(schema.TextPart{
				text: text
			})
		}
		if reasoning_value := block['reasoningContent'] {
			if reasoning_value !is map[string]json2.Any {
				return error('Amazon Bedrock reasoningContent block is invalid')
			}
			reasoning_block := reasoning_value as map[string]json2.Any
			if reasoning_text_value := reasoning_block['reasoningText'] {
				if reasoning_text_value !is map[string]json2.Any {
					return error('Amazon Bedrock reasoningText block is invalid')
				}
				reasoning_text := reasoning_text_value as map[string]json2.Any
				thought := any_string(reasoning_text['text'] or { json2.Any('') })
				reasoning += thought
				parts << schema.ContentPart(schema.ThinkingPart{
					text:      thought
					signature: any_string(reasoning_text['signature'] or { json2.Any('') })
				})
			}
			if redacted := reasoning_block['redactedContent'] {
				redacted_text := any_string(redacted)
				if redacted_text != '' {
					parts << schema.ContentPart(schema.RedactedThinkingPart{
						data: redacted_text
					})
				}
			}
		}
		if tool_use_value := block['toolUse'] {
			if tool_use_value !is map[string]json2.Any {
				return error('Amazon Bedrock toolUse block is invalid')
			}
			tool_use := tool_use_value as map[string]json2.Any
			name := any_string(tool_use['name'] or { json2.Any('') })
			id := any_string(tool_use['toolUseId'] or { json2.Any('') })
			if name == '' || id == '' {
				return error('Amazon Bedrock toolUse block is missing name or ID')
			}
			tool_input := tool_use['input'] or { json2.Any(map[string]json2.Any{}) }
			call := schema.ToolCall{
				id:            id
				call_type:     'function'
				function_call: schema.FunctionCall{
					name:      name
					arguments: json2.encode(tool_input, json2.EncoderOptions{})
				}
			}
			tool_calls << call
			parts << schema.ContentPart(call)
		}
	}
	usage_value := response['usage'] or { json2.Any(map[string]json2.Any{}) }
	mut prompt_tokens := 0
	mut completion_tokens := 0
	mut total_tokens := 0
	if usage_value is map[string]json2.Any {
		usage_map := usage_value as map[string]json2.Any
		prompt_tokens = any_int(usage_map['inputTokens'] or { json2.Any(0) })
		completion_tokens = any_int(usage_map['outputTokens'] or { json2.Any(0) })
		total_tokens = any_int(usage_map['totalTokens'] or { json2.Any(0) })
	}
	if total_tokens == 0 {
		total_tokens = prompt_tokens + completion_tokens
	}
	stop_reason := any_string(response['stopReason'] or { json2.Any('') })
	return llms.Response{
		choices: [llms.Choice{
			content:     content
			reasoning:   reasoning
			stop_reason: stop_reason
			tool_calls:  tool_calls
			parts:       parts
		}]
		usage:   llms.Usage{
			prompt_tokens:     prompt_tokens
			completion_tokens: completion_tokens
			total_tokens:      total_tokens
		}
	}
}

fn any_string(value json2.Any) string {
	if value is string {
		return value as string
	}
	return ''
}

fn any_int(value json2.Any) int {
	if value is int {
		number := value as int
		if number >= 0 && number <= 1000000000 {
			return number
		}
		return 0
	}
	if value is i64 {
		number := value as i64
		if number >= 0 && number <= 1000000000 {
			return int(number)
		}
		return 0
	}
	if value is f64 {
		number := value as f64
		if number >= 0 && number <= 1000000000 && number == f64(int(number)) {
			return int(number)
		}
		return 0
	}
	return 0
}

fn valid_region(region string) bool {
	if region.len < 6 || region.len > 32 {
		return false
	}
	parts := region.split('-')
	if parts.len < 3 || parts[0].len != 2 || parts[parts.len - 1] == '' {
		return false
	}
	for byte_value in parts[0].bytes() {
		if byte_value < `a` || byte_value > `z` {
			return false
		}
	}
	for byte_value in parts[parts.len - 1].bytes() {
		if byte_value < `0` || byte_value > `9` {
			return false
		}
	}
	for part in parts[1..parts.len - 1] {
		if part == '' {
			return false
		}
		for byte_value in part.bytes() {
			if byte_value < `a` || byte_value > `z` {
				return false
			}
		}
	}
	return true
}

fn valid_model_id(model_id string) bool {
	if model_id == '' || model_id.len > 512 {
		return false
	}
	for byte_value in model_id.bytes() {
		if !(byte_value >= `a` && byte_value <= `z`) && !(byte_value >= `A` && byte_value <= `Z`)
			&& !(byte_value >= `0` && byte_value <= `9`) && byte_value !in [`-`, `_`, `.`, `:`] {
			return false
		}
	}
	return true
}
