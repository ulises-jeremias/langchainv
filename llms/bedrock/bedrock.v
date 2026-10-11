// Package bedrock implements bounded chat generation through Bedrock Converse.
module bedrock

import context
import encoding.base64
import json2
import math
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

const default_model = 'anthropic.claude-3-5-haiku-20241022-v1:0'
const max_request_bytes = 5 * 1024 * 1024
const max_response_bytes = 8 * 1024 * 1024
const max_image_bytes = 3 * 1024 * 1024
const max_message_content_bytes = 4 * 1024 * 1024

// Options configures an AWS region and a Bedrock Converse model ID.
pub struct Options {
pub:
	region   string = 'us-east-1'
	model_id string = default_model
}

// Client calls the Bedrock Runtime Converse operation using a Bedrock API key.
pub struct Client {
mut:
	api_key     string
	http_client httputil.HTTPClient
pub:
	region   string
	model_id string
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
	}
}

// generate_content sends text, image, and tool messages to Converse.
pub fn (client Client) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
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
	if _ := options.streaming_func {
		return error('Amazon Bedrock Converse streaming is not supported by the bounded transport')
	}
	if _ := options.streaming_reasoning_func {
		return error('Amazon Bedrock Converse streaming is not supported by the bounded transport')
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
			schema.ThinkingPart, schema.RedactedThinkingPart {
				return error('Amazon Bedrock Converse does not support reasoning replay')
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
			arguments := tool_use['input'] or { json2.Any(map[string]json2.Any{}) }
			call := schema.ToolCall{
				id:            id
				call_type:     'function'
				function_call: schema.FunctionCall{
					name:      name
					arguments: json2.encode(arguments, json2.EncoderOptions{})
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
