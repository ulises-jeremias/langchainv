// Package openai implements OpenAI Chat Completions for LangChainV models.
module openai

import context
import encoding.base64
import json2
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

const default_base_url = 'https://api.openai.com/v1'
const default_model = 'gpt-4o-mini'
const max_request_bytes = 8 * 1024 * 1024
const max_response_bytes = 16 * 1024 * 1024
const max_inline_image_bytes = 5 * 1024 * 1024

// Client implements chat generation over the injectable bounded HTTP transport.
pub struct Client {
	api_key     string
	http_client httputil.HTTPClient
	response_format ?ResponseFormat
pub:
	base_url string = default_base_url
	model    string = default_model
}

// Options configures endpoint and default model.
pub struct Options {
pub:
	base_url       string = default_base_url
	model          string = default_model
	response_format ?ResponseFormat
}

// JSONSchemaResponseFormat configures OpenAI structured output.
pub struct JSONSchemaResponseFormat {
pub:
	name        string
	description string
	schema      map[string]json2.Any
	strict      bool
}

// ResponseFormat selects ordinary JSON mode or JSON Schema constrained output.
pub struct ResponseFormat {
pub:
	kind        string
	json_schema ?JSONSchemaResponseFormat
}

struct ChatResponse {
	choices []ChatChoice
	usage   ChatUsage
}

struct ChatChoice {
	index         int
	message       ChatMessage
	finish_reason string
}

struct ChatMessage {
	role          string
	content       ?string
	reasoning     string @[json: 'reasoning_content']
	tool_calls    []ChatToolCall
	function_call ?ChatFunction
}

struct ChatToolCall {
	id        string
	call_type string @[json: 'type']
	function  ChatFunction
}

struct ChatFunction {
	name      string
	arguments string
}

struct ChatUsage {
	prompt_tokens     int
	completion_tokens int
	total_tokens      int
}

struct ChatStreamResponse {
	choices []ChatStreamChoice
	usage   ChatUsage
}

struct ChatStreamChoice {
	index         int
	delta         ChatStreamDelta
	finish_reason ?string
}

struct ChatStreamDelta {
	content    ?string
	reasoning  ?string @[json: 'reasoning_content']
	tool_calls []ChatStreamToolCall
}

struct ChatStreamToolCall {
	index     int
	id        string
	call_type string @[json: 'type']
	function  ChatStreamFunction
}

struct ChatStreamFunction {
	name      string
	arguments string
}

struct StreamToolAccumulator {
mut:
	id        string
	call_type string
	name      string
	arguments string
}

struct OpenAIStreamState {
mut:
	content           string
	reasoning         string
	finish_reason     string
	usage             llms.Usage
	tool_accumulators []StreamToolAccumulator
	saw_done          bool
	error             string
}

// new_client constructs an OpenAI client with the default model and endpoint.
pub fn new_client(api_key string, http_client httputil.HTTPClient) !Client {
	return new_client_with_options(api_key, http_client, Options{})
}

// new_default_client uses the shared bounded standard-library HTTP transport.
pub fn new_default_client(api_key string) !Client {
	return new_client(api_key, httputil.HTTPClient(httputil.new_default_client()))
}

// new_client_with_options validates endpoint, model, and credential configuration.
pub fn new_client_with_options(api_key string, http_client httputil.HTTPClient, options Options) !Client {
	if api_key.trim_space() == '' {
		return error('OpenAI API key must not be empty')
	}
	if options.base_url.trim_space() == '' || options.model.trim_space() == '' {
		return error('OpenAI base URL and model must not be empty')
	}
	validate_response_format(options.response_format)!
	return Client{
		api_key:        api_key
		http_client:    http_client
		response_format: options.response_format
		base_url:       options.base_url.trim_space().trim_right('/')
		model:          options.model.trim_space()
	}
}

// complete implements llms.CompletionModel by sending the prompt as a user turn.
pub fn (client Client) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	response := client.generate_content(mut ctx, [schema.text_message(.human, prompt)], options)!
	if response.choices.len == 0 {
		return error('OpenAI returned no completion choices')
	}
	return response.choices[0].content
}

// generate_content implements non-streaming OpenAI Chat Completions.
pub fn (client Client) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	options.validate()!
	llms.validate_messages(messages)!
	if options.top_k != 0 || options.min_length != 0 || options.max_length != 0
		|| options.repetition_penalty != 0 {
		return error('OpenAI Chat Completions does not support one or more requested generation options')
	}
	if options.provider_options.len > 0 {
		return error('OpenAI provider_options are not supported yet; use typed call options')
	}
	model := if options.model.trim_space() == '' {
		client.model
	} else {
		options.model.trim_space()
	}
	request := make_request(model, messages, options, client.response_format)!
	if _ := options.streaming_func {
		return client.generate_stream(mut ctx, request, options)
	}
	if _ := options.streaming_reasoning_func {
		return client.generate_stream(mut ctx, request, options)
	}
	body := json2.encode(request, json2.EncoderOptions{})
	if body.len > max_request_bytes {
		return error('OpenAI chat completion request exceeds 8 MiB')
	}
	response := client.http_client.do(mut ctx, httputil.Request{
		method:  .post
		url:     '${client.base_url}/chat/completions'
		headers: {
			'Authorization': 'Bearer ${client.api_key}'
			'Content-Type':  'application/json'
			'Accept':        'application/json'
		}
		body:    body
	}) or {
		return error('OpenAI chat completion request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('OpenAI chat completion request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_response_bytes {
		return error('OpenAI chat completion response exceeds 16 MiB')
	}
	decoded := json2.decode[ChatResponse](response.body, json2.DecoderOptions{}) or {
		return error('could not decode OpenAI chat completion response: ${err.msg()}')
	}
	if decoded.choices.len == 0 {
		return error('OpenAI returned no completion choices')
	}
	mut choices := []llms.Choice{cap: decoded.choices.len}
	for choice in decoded.choices {
		choices << parse_choice(choice)!
	}
	return llms.Response{
		choices: choices
		usage:   llms.Usage{
			prompt_tokens:     decoded.usage.prompt_tokens
			completion_tokens: decoded.usage.completion_tokens
			total_tokens:      decoded.usage.total_tokens
		}
	}
}

fn (client Client) generate_stream(mut ctx context.Context, request map[string]json2.Any, options llms.CallOptions) !llms.Response {
	if options.candidate_count > 1 || options.n > 1 {
		return error('OpenAI streaming supports one candidate because stream callbacks do not identify candidate indexes')
	}
	if client.http_client !is httputil.StreamingHTTPClient {
		return error('configured HTTP transport does not support streaming responses')
	}
	stream_client := client.http_client as httputil.StreamingHTTPClient
	mut stream_request := map[string]json2.Any{}
	for key, value in request {
		stream_request[key] = value
	}
	stream_request['stream'] = json2.Any(true)
	stream_request['stream_options'] = json2.Any({
		'include_usage': json2.Any(true)
	})
	headers := {
		'Authorization': 'Bearer ${client.api_key}'
		'Content-Type':  'application/json'
		'Accept':        'text/event-stream'
	}
	body := json2.encode(stream_request, json2.EncoderOptions{})
	if body.len > max_request_bytes {
		return error('OpenAI chat completion request exceeds 8 MiB')
	}
	mut decoder := httputil.new_sse_decoder(max_response_bytes)!
	mut state := &OpenAIStreamState{}
	mut process_event := fn [options, mut state] (mut callback_ctx context.Context, event []u8) {
		if event.bytestr() == '[DONE]' {
			state.saw_done = true
			return
		}
		chunk := json2.decode[ChatStreamResponse](event.bytestr(), json2.DecoderOptions{}) or {
			state.error = 'could not decode OpenAI streaming response'
			return
		}
		if chunk.usage.total_tokens > 0 {
			state.usage = llms.Usage{
				prompt_tokens:     chunk.usage.prompt_tokens
				completion_tokens: chunk.usage.completion_tokens
				total_tokens:      chunk.usage.total_tokens
			}
		}
		if chunk.choices.len > 1 {
			state.error = 'OpenAI streaming supports one candidate because stream callbacks do not identify candidate indexes'
			return
		}
		for choice in chunk.choices {
			if choice.index != 0 {
				state.error = 'OpenAI streaming returned an unexpected candidate index'
				return
			}
			mut content_delta := ''
			mut reasoning_delta := ''
			if delta := choice.delta.content {
				content_delta = delta
				state.content += delta
				if callback := options.streaming_func {
					callback(mut callback_ctx, delta.bytes()) or {
						state.error = 'OpenAI streaming callback failed: ${err.msg()}'
						return
					}
				}
			}
			if delta := choice.delta.reasoning {
				reasoning_delta = delta
				state.reasoning += delta
			}
			if callback := options.streaming_reasoning_func {
				if content_delta != '' || reasoning_delta != '' {
					callback(mut callback_ctx, reasoning_delta.bytes(), content_delta.bytes()) or {
						state.error = 'OpenAI reasoning callback failed: ${err.msg()}'
						return
					}
				}
			}
			if reason := choice.finish_reason {
				state.finish_reason = reason
			}
			for tool_delta in choice.delta.tool_calls {
				if tool_delta.index < 0 || tool_delta.index >= 128 {
					state.error = 'OpenAI streamed tool-call index is outside the supported range'
					return
				}
				for state.tool_accumulators.len <= tool_delta.index {
					state.tool_accumulators << StreamToolAccumulator{}
				}
				mut accumulator := state.tool_accumulators[tool_delta.index]
				if tool_delta.id != '' { accumulator.id += tool_delta.id }
				if tool_delta.call_type != '' { accumulator.call_type = tool_delta.call_type }
				accumulator.name += tool_delta.function.name
				accumulator.arguments += tool_delta.function.arguments
				state.tool_accumulators[tool_delta.index] = accumulator
			}
		}
	}
	response := stream_client.do_stream(mut ctx, httputil.Request{
		method:  .post
		url:     '${client.base_url}/chat/completions'
		headers: headers
		body:    body
	}, fn [mut decoder, mut process_event, mut state] (mut callback_ctx context.Context, bytes []u8) ! {
		events := decoder.push(bytes) or {
			return error(err.msg())
		}
		for event in events {
			process_event(mut callback_ctx, event)
			if state.error != '' {
				return error(state.error)
			}
			if state.saw_done {
				break
			}
		}
	}) or {
		return error('OpenAI chat completion stream failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('OpenAI chat completion request returned HTTP ${response.status_code}')
	}
	if state.error != '' {
		return error(state.error)
	}
	if !state.saw_done {
		for event in decoder.finish()! {
			process_event(mut ctx, event)
			if state.error != '' { return error(state.error) }
		}
	}
	mut tool_calls := []schema.ToolCall{cap: state.tool_accumulators.len}
	mut parts := []schema.ContentPart{}
	if state.content != '' {
		parts << schema.ContentPart(schema.TextPart{ text: state.content })
	}
	for accumulator in state.tool_accumulators {
		if accumulator.name == '' {
			return error('OpenAI returned a streamed tool call without a function name')
		}
		call := schema.ToolCall{
			id:            accumulator.id
			call_type:     if accumulator.call_type == '' {
				'function'
			} else {
				accumulator.call_type
			}
			function_call: schema.FunctionCall{
				name:      accumulator.name
				arguments: accumulator.arguments
			}
		}
		tool_calls << call
		parts << schema.ContentPart(call)
	}
	return llms.Response{
		choices: [llms.Choice{
			content:     state.content
			reasoning:   state.reasoning
			stop_reason: state.finish_reason
			tool_calls:  tool_calls
			parts:       parts
		}]
		usage:   state.usage
	}
}

fn make_request(model string, messages []schema.Message, options llms.CallOptions, response_format ?ResponseFormat) !map[string]json2.Any {
	mut wire_messages := []json2.Any{cap: messages.len}
	for message in messages {
		wire_messages << json2.Any(convert_message(message)!)
	}
	mut tools := []json2.Any{}
	for definition in options.tools {
		if definition.name.trim_space() == '' {
			return error('OpenAI tool name must not be empty')
		}
		mut function := map[string]json2.Any{}
		function['name'] = json2.Any(definition.name)
		function['parameters'] = definition.parameters
		if definition.description != '' {
			function['description'] = json2.Any(definition.description)
		}
		if definition.strict {
			function['strict'] = json2.Any(true)
		}
		tools << json2.Any({
			'type':     json2.Any('function')
			'function': json2.Any(function)
		})
	}
	for definition in options.functions {
		if definition.name.trim_space() == '' {
			return error('OpenAI function name must not be empty')
		}
		mut function := map[string]json2.Any{}
		function['name'] = json2.Any(definition.name)
		function['parameters'] = definition.parameters
		if definition.description != '' {
			function['description'] = json2.Any(definition.description)
		}
		if definition.strict {
			function['strict'] = json2.Any(true)
		}
		tools << json2.Any({
			'type':     json2.Any('function')
			'function': json2.Any(function)
		})
	}
	mut tool_choice := json2.Any(json2.null)
	mut has_tool_choice := false
	if choice := options.tool_choice {
		if choice.name != '' {
			mut function_choice := map[string]json2.Any{}
			function_choice['name'] = json2.Any(choice.name)
			mut named_choice := map[string]json2.Any{}
			named_choice['type'] = json2.Any('function')
			named_choice['function'] = json2.Any(function_choice)
			tool_choice = json2.Any(named_choice)
			has_tool_choice = true
		} else if choice.mode in ['none', 'auto', 'required'] {
			tool_choice = json2.Any(choice.mode)
			has_tool_choice = true
		} else {
			return error('unsupported OpenAI tool choice mode `${choice.mode}`')
		}
	}
	mut legacy_function_call := json2.Any(json2.null)
	mut has_legacy_function_call := false
	if options.function_call_behavior != '' {
		if options.function_call_behavior !in ['none', 'auto'] {
			return error('unsupported legacy OpenAI function call behavior')
		}
		legacy_function_call = json2.Any(options.function_call_behavior)
		has_legacy_function_call = true
	}
	if !options.json_mode && options.response_mime_type != '' && options.response_mime_type != 'application/json' {
		return error('unsupported OpenAI response MIME type `${options.response_mime_type}`')
	}
	mut metadata := map[string]json2.Any{}
	for key, value in options.metadata {
		if !key.starts_with('openai:') && key != 'thinking_config' {
			metadata[key] = value
		}
	}
	mut result := map[string]json2.Any{}
	result['model'] = json2.Any(model)
	result['messages'] = json2.Any(wire_messages)
	if metadata.len > 0 {
		result['metadata'] = json2.Any(metadata)
	}
	if tools.len > 0 {
		result['tools'] = json2.Any(tools)
	}
	if has_tool_choice {
		result['tool_choice'] = tool_choice
	}
	if has_legacy_function_call {
		result['function_call'] = legacy_function_call
	}
	if options.json_mode || options.response_mime_type == 'application/json' {
		result['response_format'] = json2.Any({
			'type': json2.Any('json_object')
		})
	}
	if format := response_format {
		result['response_format'] = json2.Any(encode_response_format(format)!)
	}
	if options.max_tokens > 0 {
		result['max_completion_tokens'] = json2.Any(options.max_tokens)
	}
	requested_n := if options.n > 0 { options.n } else { options.candidate_count }
	if requested_n > 0 {
		result['n'] = json2.Any(requested_n)
	}
	if options.stop_words.len > 0 {
		mut stop_values := []json2.Any{cap: options.stop_words.len}
		for stop_word in options.stop_words {
			stop_values << json2.Any(stop_word)
		}
		result['stop'] = json2.Any(stop_values)
	}
	if !is_reasoning_model(model) {
		result['temperature'] = json2.Any(options.temperature)
		if options.top_p != 0 {
			result['top_p'] = json2.Any(options.top_p)
		}
		if options.presence_penalty != 0 {
			result['presence_penalty'] = json2.Any(options.presence_penalty)
		}
		if options.frequency_penalty != 0 {
			result['frequency_penalty'] = json2.Any(options.frequency_penalty)
		}
		if seed := options.seed {
			result['seed'] = json2.Any(seed)
		}
	} else if options.temperature != 0 || options.top_p != 0 || options.presence_penalty != 0
		|| options.frequency_penalty != 0 || options.seed != none {
		return error('sampling controls are not supported for OpenAI reasoning models')
	}
	return result
}

fn validate_response_format(response_format ?ResponseFormat) ! {
	if format := response_format {
		match format.kind {
			'json_object' {
				if format.json_schema != none {
					return error('OpenAI json_object response format cannot include a JSON schema')
				}
			}
			'json_schema' {
				schema := format.json_schema or {
					return error('OpenAI json_schema response format requires a schema definition')
				}
				if !valid_response_format_name(schema.name) {
					return error('OpenAI JSON schema name must be 1..64 ASCII letters, digits, underscores, or hyphens')
				}
				if schema.schema.len == 0 {
					return error('OpenAI JSON schema must not be an empty object')
				}
				schema_bytes := json2.encode(schema.schema, json2.EncoderOptions{}).len
				if schema_bytes > max_request_bytes {
					return error('OpenAI JSON schema exceeds the 8 MiB request size limit')
				}
			}
			else {
				return error('OpenAI response format kind must be json_object or json_schema')
			}
		}
	}
}

fn valid_response_format_name(name string) bool {
	if name.len == 0 || name.len > 64 {
		return false
	}
	for character in name.bytes() {
		if !(character.is_letter() || character.is_digit() || character == `_` || character == `-`) {
			return false
		}
	}
	return true
}

fn encode_response_format(format ResponseFormat) !map[string]json2.Any {
	mut result := map[string]json2.Any{
		'type': json2.Any(format.kind)
	}
	if format.kind == 'json_schema' {
		schema := format.json_schema or {
			return error('OpenAI json_schema response format requires a schema definition')
		}
		mut json_schema := map[string]json2.Any{
			'name':   json2.Any(schema.name)
			'schema': json2.Any(schema.schema)
		}
		if schema.description != '' {
			json_schema['description'] = json2.Any(schema.description)
		}
		if schema.strict {
			json_schema['strict'] = json2.Any(true)
		}
		result['json_schema'] = json2.Any(json_schema)
	}
	return result
}

fn convert_message(message schema.Message) !map[string]json2.Any {
	role := match message.role {
		.system { 'system' }
		.human { 'user' }
		.ai { 'assistant' }
		.generic { 'user' }
		.tool { 'tool' }
	}
	mut result := map[string]json2.Any{
		'role': json2.Any(role)
	}
	mut content := []json2.Any{}
	mut tool_calls := []json2.Any{}
	mut plain_text := []string{}
	mut text_only := true
	mut has_tool_result := false
	for part in message.parts {
		match part {
			schema.TextPart {
				plain_text << part.text
				content << json2.Any({
					'type': json2.Any('text')
					'text': json2.Any(part.text)
				})
			}
			schema.ImageURLPart {
				mut image := map[string]json2.Any{
					'url': json2.Any(part.url)
				}
				if part.detail != '' {
					image['detail'] = json2.Any(part.detail)
				}
				content << json2.Any({
					'type':      json2.Any('image_url')
					'image_url': json2.Any(image)
				})
				text_only = false
			}
			schema.BinaryPart {
				if part.mime_type !in ['image/jpeg', 'image/png', 'image/gif', 'image/webp'] {
					return error('OpenAI binary image MIME type is unsupported')
				}
				if part.data.len == 0 || part.data.len > max_inline_image_bytes {
					return error('OpenAI inline image must be between 1 byte and 5 MiB')
				}
				data_url := 'data:${part.mime_type};base64,${base64.encode(part.data)}'
				content << json2.Any({
					'type':      json2.Any('image_url')
					'image_url': json2.Any({
						'url': json2.Any(data_url)
					})
				})
				text_only = false
			}
			schema.ToolCall {
				if message.role != .ai {
					return error('OpenAI tool calls require an assistant-role message')
				}
				tool_calls << json2.Any({
					'id':       json2.Any(part.id)
					'type':     json2.Any(if part.call_type == '' {
						'function'
					} else {
						part.call_type
					})
					'function': json2.Any({
						'name':      json2.Any(part.function_call.name)
						'arguments': json2.Any(part.function_call.arguments)
					})
				})
				text_only = false
			}
			schema.ToolResult {
				if message.role != .tool || message.parts.len != 1 {
					return error('OpenAI tool results require a tool-role message')
				}
				result['tool_call_id'] = json2.Any(part.call_id)
				result['content'] = json2.Any(part.content)
				text_only = false
				has_tool_result = true
			}
			schema.ThinkingPart, schema.RedactedThinkingPart {
				return error('OpenAI chat client does not support replaying reasoning parts')
			}
		}
	}
	if message.role == .tool && !has_tool_result {
		return error('OpenAI tool-role messages require a tool result part')
	}
	if content.len == 0 && tool_calls.len == 0 && !has_tool_result {
		return error('OpenAI chat message has no supported content')
	}
	if text_only && plain_text.len > 0 {
		result['content'] = json2.Any(plain_text.join(''))
	} else if content.len > 0 {
		result['content'] = json2.Any(content)
	}
	if tool_calls.len > 0 {
		result['tool_calls'] = json2.Any(tool_calls)
	}
	return result
}

fn parse_choice(choice ChatChoice) !llms.Choice {
	mut parts := []schema.ContentPart{}
	content := choice.message.content or { '' }
	if content != '' {
		parts << schema.ContentPart(schema.TextPart{
			text: content
		})
	}
	mut tool_calls := []schema.ToolCall{}
	for tool in choice.message.tool_calls {
		if tool.function.name == '' {
			return error('OpenAI returned a tool call without a function name')
		}
		call := schema.ToolCall{
			id:            tool.id
			call_type:     if tool.call_type == '' { 'function' } else { tool.call_type }
			function_call: schema.FunctionCall{
				name:      tool.function.name
				arguments: tool.function.arguments
			}
		}
		tool_calls << call
		parts << schema.ContentPart(call)
	}
	mut function_call := ?schema.FunctionCall(none)
	if legacy := choice.message.function_call {
		function_call = schema.FunctionCall{
			name:      legacy.name
			arguments: legacy.arguments
		}
	}
	return llms.Choice{
		content:       content
		stop_reason:   choice.finish_reason
		reasoning:     choice.message.reasoning
		function_call: function_call
		tool_calls:    tool_calls
		parts:         parts
	}
}

fn is_reasoning_model(model string) bool {
	lower := model.to_lower()
	return lower.starts_with('o1') || lower.starts_with('o3') || lower.starts_with('o4')
		|| lower.starts_with('gpt-5')
}
