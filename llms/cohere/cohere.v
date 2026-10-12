// Package cohere implements the Cohere Chat API v2.
module cohere

import context
import json2
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

const default_base_url = 'https://api.cohere.com/v2'
const default_model = 'command-a-plus-05-2026'
const max_response_bytes = 16 * 1024 * 1024

// Client implements Cohere Chat over the injectable bounded transport.
pub struct Client {
	api_key     string
	http_client httputil.HTTPClient
pub:
	base_url string = default_base_url
	model    string = default_model
}

// Options configures the endpoint and default model.
pub struct Options {
pub:
	base_url string = default_base_url
	model    string = default_model
}

struct ChatResponse {
	message       ResponseMessage
	finish_reason string
	usage         Usage
}

struct ResponseMessage {
	content    []ContentBlock
	tool_calls []ResponseToolCall
}

struct ContentBlock {
	block_type string @[json: 'type']
	text       string
}

struct ResponseToolCall {
	id        string
	call_type string @[json: 'type']
	function  ResponseFunction
}

struct ResponseFunction {
	name      string
	arguments string
}

struct Usage {
	tokens Tokens
}

struct Tokens {
	input_tokens  int
	output_tokens int
}

struct StreamEvent {
	event_type string @[json: 'type']
	index      int = -1
	delta      StreamDelta
}

struct StreamDelta {
	message       StreamMessage
	finish_reason string
	usage         Usage
}

struct StreamMessage {
	content    StreamContent
	tool_calls StreamToolCall
}

struct StreamContent {
	text string
}

struct StreamToolCall {
	id        string
	call_type string @[json: 'type']
	function  StreamFunction
}

struct StreamFunction {
	name      string
	arguments string
}

struct CohereStreamState {
mut:
	content        string
	finish_reason  string
	input_tokens   int
	output_tokens  int
	tool_calls     []CohereStreamToolCall
	received_bytes i64
	error          string
}

struct CohereStreamToolCall {
	id        string
	call_type string
	name      string
	arguments string
}

// new_client creates a Cohere client with the default model and endpoint.
pub fn new_client(api_key string, http_client httputil.HTTPClient) !Client {
	return new_client_with_options(api_key, http_client, Options{})
}

// new_default_client uses the shared bounded standard-library HTTP transport.
pub fn new_default_client(api_key string) !Client {
	return new_client(api_key, httputil.HTTPClient(httputil.new_default_client()))
}

// new_client_with_options validates credentials and endpoint configuration.
pub fn new_client_with_options(api_key string, http_client httputil.HTTPClient, options Options) !Client {
	if api_key.trim_space() == '' {
		return error('Cohere API key must not be empty')
	}
	if options.base_url.trim_space() == '' || options.model.trim_space() == '' {
		return error('Cohere base URL and model must not be empty')
	}
	return Client{
		api_key:     api_key
		http_client: http_client
		base_url:    options.base_url.trim_space().trim_right('/')
		model:       options.model.trim_space()
	}
}

// complete implements llms.CompletionModel by sending the prompt as a user turn.
pub fn (client Client) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	response := client.generate_content(mut ctx, [schema.text_message(.human, prompt)], options)!
	if response.choices.len == 0 {
		return error('Cohere returned no completion choices')
	}
	return response.choices[0].content
}

// generate_content implements bounded non-streaming Cohere Chat API v2.
pub fn (client Client) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	options.validate()!
	llms.validate_messages(messages)!
	validate_options(options)!
	model := if options.model.trim_space() == '' {
		client.model
	} else {
		options.model.trim_space()
	}
	request := make_request(model, messages, options)!
	if _ := options.streaming_func {
		return client.generate_stream(mut ctx, request, options)
	}
	if _ := options.streaming_reasoning_func {
		return client.generate_stream(mut ctx, request, options)
	}
	body := json2.encode(request, json2.EncoderOptions{})
	response := client.http_client.do(mut ctx, httputil.Request{
		method:  .post
		url:     '${client.base_url}/chat'
		headers: {
			'Authorization': 'Bearer ${client.api_key}'
			'Content-Type':  'application/json'
			'Accept':        'application/json'
		}
		body:    body
	}) or {
		return error('Cohere chat request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Cohere chat request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_response_bytes {
		return error('Cohere chat response exceeds 16 MiB')
	}
	decoded := json2.decode[ChatResponse](response.body, json2.DecoderOptions{}) or {
		return error('could not decode Cohere chat response: ${err.msg()}')
	}
	choice := parse_choice(decoded)!
	return llms.Response{
		choices: [choice]
		usage:   llms.Usage{
			prompt_tokens:     decoded.usage.tokens.input_tokens
			completion_tokens: decoded.usage.tokens.output_tokens
			total_tokens:      decoded.usage.tokens.input_tokens + decoded.usage.tokens.output_tokens
		}
	}
}

fn validate_options(options llms.CallOptions) ! {
	if options.n > 1 || options.candidate_count > 1 {
		return error('Cohere Chat returns exactly one candidate')
	}
	if options.min_length != 0 || options.max_length != 0 || options.repetition_penalty != 0 {
		return error('Cohere Chat does not support one or more requested generation options')
	}
	if options.presence_penalty < 0 || options.presence_penalty > 1 || options.frequency_penalty < 0
		|| options.frequency_penalty > 1 {
		return error('Cohere frequency and presence penalties must be between zero and one')
	}
	if options.top_k < 0 || options.top_k > 500 || options.temperature < 0 || options.top_p < 0
		|| options.top_p > 0 && (options.top_p < 0.01 || options.top_p > 0.99) {
		return error('Cohere top_k, temperature, or top_p is outside the supported range')
	}
	if (options.json_mode || options.response_mime_type == 'application/json') && options.tools.len > 0 {
		return error('Cohere JSON output cannot be combined with tools')
	}
	if options.response_mime_type != '' && options.response_mime_type != 'application/json' {
		return error('unsupported Cohere response MIME type `${options.response_mime_type}`')
	}
	if options.provider_options.len > 0 || options.metadata.len > 0 || options.functions.len > 0
		|| options.function_call_behavior != ''
		|| options.web_search_options != none {
		return error('Cohere metadata, provider_options, legacy functions, and web search options are not supported')
	}
	if options.tool_choice != none && options.tools.len == 0 {
		return error('Cohere tool_choice requires at least one tool definition')
	}
}

fn (client Client) generate_stream(mut ctx context.Context, request map[string]json2.Any, options llms.CallOptions) !llms.Response {
	if client.http_client !is httputil.StreamingHTTPClient {
		return error('configured Cohere HTTP transport does not support streaming responses')
	}
	stream_client := client.http_client as httputil.StreamingHTTPClient
	mut stream_request := map[string]json2.Any{}
	for key, value in request {
		stream_request[key] = value
	}
	stream_request['stream'] = json2.Any(true)
	body := json2.encode(stream_request, json2.EncoderOptions{})
	mut decoder := httputil.new_sse_decoder(max_response_bytes)!
	mut state := &CohereStreamState{}
	mut process_event := fn [options, mut state] (mut callback_ctx context.Context, payload []u8) {
		event := json2.decode[StreamEvent](payload.bytestr(), json2.DecoderOptions{}) or {
			state.error = 'could not decode Cohere streaming event'
			return
		}
		match event.event_type {
			'content-delta' {
				text := event.delta.message.content.text
				state.content += text
				if text != '' {
					if callback := options.streaming_func {
						callback(mut callback_ctx, text.bytes()) or {
							state.error = 'Cohere streaming callback failed: ${err.msg()}'
							return
						}
					}
					if callback := options.streaming_reasoning_func {
						callback(mut callback_ctx, []u8{}, text.bytes()) or {
							state.error = 'Cohere reasoning callback failed: ${err.msg()}'
							return
						}
					}
				}
			}
			'tool-call-start' {
				if event.index < 0 || event.index >= 128 {
					state.error = 'Cohere tool call index is outside the supported range'
					return
				}
				for state.tool_calls.len <= event.index {
					state.tool_calls << CohereStreamToolCall{}
				}
				call := event.delta.message.tool_calls
				state.tool_calls[event.index] = CohereStreamToolCall{
					id:        call.id
					call_type: call.call_type
					name:      call.function.name
					arguments: call.function.arguments
				}
			}
			'tool-call-delta' {
				if event.index < 0 || event.index >= state.tool_calls.len {
					state.error = 'Cohere tool call delta has no matching start event'
					return
				}
				call := state.tool_calls[event.index]
				state.tool_calls[event.index] = CohereStreamToolCall{
					id:        call.id
					call_type: call.call_type
					name:      call.name
					arguments: call.arguments + event.delta.message.tool_calls.function.arguments
				}
			}
			'message-end' {
				state.finish_reason = event.delta.finish_reason
				state.input_tokens = event.delta.usage.tokens.input_tokens
				state.output_tokens = event.delta.usage.tokens.output_tokens
			}
			'message-start', 'content-start', 'content-end', 'tool-call-end', 'tool-plan-delta',
			'citation-start', 'citation-end', 'debug' {
			}
			'error' {
				state.error = 'Cohere returned an error event while streaming'
			}
			else {
				state.error = 'Cohere returned unsupported streaming event `${event.event_type}`'
			}
		}
	}
	response := stream_client.do_stream(mut ctx, httputil.Request{
		method:  .post
		url:     '${client.base_url}/chat'
		headers: {
			'Authorization': 'Bearer ${client.api_key}'
			'Content-Type':  'application/json'
			'Accept':        'text/event-stream'
		}
		body:    body
	}, fn [mut decoder, mut state, mut process_event] (mut callback_ctx context.Context, bytes []u8) ! {
		state.received_bytes += i64(bytes.len)
		if state.received_bytes > max_response_bytes {
			return error('Cohere chat response exceeds 16 MiB')
		}
		for payload in decoder.push(bytes)! {
			process_event(mut callback_ctx, payload)
			if state.error != '' {
				return error(state.error)
			}
		}
	}) or {
		return error('Cohere chat stream failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Cohere chat request returned HTTP ${response.status_code}')
	}
	for payload in decoder.finish()! {
		process_event(mut ctx, payload)
		if state.error != '' {
			return error(state.error)
		}
	}
	mut calls := []ResponseToolCall{cap: state.tool_calls.len}
	for streamed_call in state.tool_calls {
		if streamed_call.id == '' || streamed_call.name == '' {
			return error('Cohere returned a tool call without an ID or function name')
		}
		calls << ResponseToolCall{
			id:        streamed_call.id
			call_type: streamed_call.call_type
			function:  ResponseFunction{
				name:      streamed_call.name
				arguments: streamed_call.arguments
			}
		}
	}
	choice := parse_choice(ChatResponse{
		message:       ResponseMessage{
			content:    if state.content == '' {
				[]ContentBlock{}
			} else {
				[ContentBlock{
					block_type: 'text'
					text:       state.content
				}]
			}
			tool_calls: calls
		}
		finish_reason: state.finish_reason
	})!
	return llms.Response{
		choices: [choice]
		usage:   llms.Usage{
			prompt_tokens:     state.input_tokens
			completion_tokens: state.output_tokens
			total_tokens:      state.input_tokens + state.output_tokens
		}
	}
}

fn make_request(model string, messages []schema.Message, options llms.CallOptions) !map[string]json2.Any {
	mut wire_messages := []json2.Any{cap: messages.len}
	for message in messages {
		wire_messages << json2.Any(convert_message(message)!)
	}
	mut request := map[string]json2.Any{
		'model':    json2.Any(model)
		'messages': json2.Any(wire_messages)
	}
	if options.max_tokens > 0 {
		request['max_tokens'] = json2.Any(options.max_tokens)
	}
	if options.temperature != 0 {
		request['temperature'] = json2.Any(options.temperature)
	}
	if options.top_p != 0 {
		request['p'] = json2.Any(options.top_p)
	}
	if options.top_k > 0 {
		request['k'] = json2.Any(options.top_k)
	}
	if seed := options.seed {
		request['seed'] = json2.Any(seed)
	}
	if options.frequency_penalty != 0 {
		request['frequency_penalty'] = json2.Any(options.frequency_penalty)
	}
	if options.presence_penalty != 0 {
		request['presence_penalty'] = json2.Any(options.presence_penalty)
	}
	if options.stop_words.len > 0 {
		if options.stop_words.len > 5 {
			return error('Cohere accepts at most five stop sequences')
		}
		mut stop_sequences := []json2.Any{cap: options.stop_words.len}
		for stop_word in options.stop_words {
			stop_sequences << json2.Any(stop_word)
		}
		request['stop_sequences'] = json2.Any(stop_sequences)
	}
	if options.tools.len > 0 {
		mut tools := []json2.Any{cap: options.tools.len}
		for definition in options.tools {
			if definition.strict {
				return error('Cohere strict tools are not supported by this adapter')
			}
			mut function := map[string]json2.Any{
				'name':       json2.Any(definition.name)
				'parameters': definition.parameters
			}
			if definition.description != '' {
				function['description'] = json2.Any(definition.description)
			}
			tools << json2.Any({
				'type':     json2.Any('function')
				'function': json2.Any(function)
			})
		}
		request['tools'] = json2.Any(tools)
	}
	if choice := options.tool_choice {
		mode := choice.mode.to_lower()
		if choice.name != '' || mode !in ['required', 'none'] {
			return error('Cohere supports tool_choice modes `required` and `none` only')
		}
		request['tool_choice'] = json2.Any(mode.to_upper())
	}
	if options.json_mode || options.response_mime_type == 'application/json' {
		request['response_format'] = json2.Any({
			'type': json2.Any('json_object')
		})
	}
	return request
}

fn convert_message(message schema.Message) !map[string]json2.Any {
	role := match message.role {
		.system { 'system' }
		.human, .generic { 'user' }
		.ai { 'assistant' }
		.tool { 'tool' }
	}
	mut result := map[string]json2.Any{
		'role': json2.Any(role)
	}
	mut text := []string{}
	mut calls := []json2.Any{}
	mut has_tool_result := false
	for part in message.parts {
		match part {
			schema.TextPart {
				text << part.text
			}
			schema.ToolCall {
				if message.role != .ai || part.function_call.name == '' {
					return error('Cohere tool calls require a named function on an assistant message')
				}
				calls << json2.Any({
					'id':       json2.Any(part.id)
					'type':     json2.Any('function')
					'function': json2.Any({
						'name':      json2.Any(part.function_call.name)
						'arguments': json2.Any(part.function_call.arguments)
					})
				})
			}
			schema.ToolResult {
				if message.role != .tool || message.parts.len != 1 || part.call_id == '' {
					return error('Cohere tool results require a matching call ID in a tool message')
				}
				result['tool_call_id'] = json2.Any(part.call_id)
				result['content'] = json2.Any([json2.Any({
					'type':     json2.Any('document')
					'document': json2.Any({
						'data': json2.Any(part.content)
					})
				})])
				has_tool_result = true
			}
			schema.ImageURLPart, schema.BinaryPart {
				return error('Cohere Chat image inputs are not supported by this adapter')
			}
			schema.ThinkingPart, schema.RedactedThinkingPart {
				return error('Cohere reasoning replay is not supported by this adapter')
			}
		}
	}
	if message.role == .tool && !has_tool_result {
		return error('Cohere tool messages require a tool result part')
	}
	if text.len > 0 {
		result['content'] = json2.Any(text.join(''))
	}
	if calls.len > 0 {
		result['tool_calls'] = json2.Any(calls)
	}
	if text.len == 0 && calls.len == 0 && !has_tool_result {
		return error('Cohere chat message has no supported content')
	}
	return result
}

fn parse_choice(response ChatResponse) !llms.Choice {
	mut text := []string{}
	for block in response.message.content {
		if block.block_type == 'text' {
			text << block.text
		}
	}
	content := text.join('')
	mut tool_calls := []schema.ToolCall{cap: response.message.tool_calls.len}
	mut parts := []schema.ContentPart{}
	if content != '' {
		parts << schema.ContentPart(schema.TextPart{
			text: content
		})
	}
	for tool in response.message.tool_calls {
		if tool.function.name == '' || tool.id == '' {
			return error('Cohere returned a tool call without an ID or function name')
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
	if content == '' && tool_calls.len == 0 {
		return error('Cohere returned an empty response')
	}
	return llms.Choice{
		content:     content
		stop_reason: response.finish_reason.to_lower()
		tool_calls:  tool_calls
		parts:       parts
	}
}
