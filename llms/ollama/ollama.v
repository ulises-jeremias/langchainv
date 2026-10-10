// Package ollama implements non-streaming Ollama chat generation.
module ollama

import context
import encoding.base64
import json2
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

const default_base_url = 'http://127.0.0.1:11434'
const max_request_bytes = 8 * 1024 * 1024
const max_response_bytes = 16 * 1024 * 1024
const max_inline_image_bytes = 5 * 1024 * 1024
const max_chat_messages = 1024
const max_tools = 128

// Client implements Ollama chat generation through an injectable HTTP client.
pub struct Client {
	http_client httputil.HTTPClient
pub:
	base_url   string = default_base_url
	model      string
	format     string
	keep_alive string
}

// Options configures the Ollama server, model, output format, and model lifetime.
pub struct Options {
pub:
	base_url   string = default_base_url
	model      string
	format     string
	keep_alive string
}

struct ChatResponse {
	message           ChatMessage
	done_reason       string
	prompt_eval_count int
	eval_count        int
}

struct ChatMessage {
	content    string
	thinking   string
	tool_calls []ChatToolCall
}

struct ChatToolCall {
	function ChatFunction
}

struct ChatFunction {
	name      string
	arguments map[string]json2.Any
}

// new_client constructs an Ollama client with a custom server, transport, or model.
pub fn new_client(http_client httputil.HTTPClient, options Options) !Client {
	if options.model.trim_space() == '' {
		return error('Ollama model must not be empty')
	}
	if options.base_url.trim_space() == '' {
		return error('Ollama base URL must not be empty')
	}
	if options.format !in ['', 'json'] {
		return error('Ollama format must be empty or `json`')
	}
	base_url := options.base_url.trim_space().trim_right('/')
	httputil.validate_url(base_url, '') or { return error('invalid Ollama base URL: ${err.msg()}') }
	return Client{
		http_client: http_client
		base_url:    base_url
		model:       options.model.trim_space()
		format:      options.format
		keep_alive:  options.keep_alive.trim_space()
	}
}

// new_default_client creates a client for a local Ollama server.
pub fn new_default_client(model string) !Client {
	return new_client(httputil.HTTPClient(httputil.new_default_client()), Options{
		model: model
	})
}

// complete implements CompletionModel by wrapping the prompt in a user message.
pub fn (client Client) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	response := client.generate_content(mut ctx, [schema.text_message(.human, prompt)], options)!
	if response.choices.len == 0 {
		return error('Ollama returned no completion choices')
	}
	return response.choices[0].content
}

// generate_content implements non-streaming Ollama /api/chat requests.
pub fn (client Client) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	options.validate()!
	if messages.len > max_chat_messages {
		return error('Ollama chat request exceeds the 1024-message limit')
	}
	llms.validate_messages(messages)!
	validate_call_options(options)!
	if options.tools.len > max_tools {
		return error('Ollama chat request exceeds the 128-tool limit')
	}
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	model := if options.model.trim_space() == '' {
		client.model
	} else {
		options.model.trim_space()
	}
	request := make_request(client, model, messages, options)!
	body := json2.encode(request, json2.EncoderOptions{})
	if body.len > max_request_bytes {
		return error('Ollama chat request exceeds the 8 MiB size limit')
	}
	response := client.http_client.do(mut ctx, httputil.Request{
		method:  .post
		url:     '${client.base_url}/api/chat'
		headers: {
			'Content-Type': 'application/json'
			'Accept':       'application/json'
		}
		body:    body
	}) or {
		return error('Ollama chat request failed: ${err.msg()}')
	}
	ctx_error_after_request := ctx.err()
	if ctx_error_after_request !is none {
		return ctx_error_after_request
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Ollama chat request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_response_bytes {
		return error('Ollama chat response exceeds the 16 MiB size limit')
	}
	decoded := json2.decode[ChatResponse](response.body, json2.DecoderOptions{}) or {
		return error('could not decode Ollama chat response: ${err.msg()}')
	}
	if decoded.message.content == '' && decoded.message.thinking == ''
		&& decoded.message.tool_calls.len == 0 {
		return error('Ollama returned an empty chat response')
	}
	mut tool_calls := []schema.ToolCall{cap: decoded.message.tool_calls.len}
	for tool_call in decoded.message.tool_calls {
		if tool_call.function.name.trim_space() == '' {
			return error('Ollama returned a tool call without a function name')
		}
		tool_calls << schema.ToolCall{
			id:            ''
			call_type:     'function'
			function_call: schema.FunctionCall{
				name:      tool_call.function.name
				arguments: json2.encode(tool_call.function.arguments, json2.EncoderOptions{})
			}
		}
	}
	mut choice_parts := []schema.ContentPart{}
	if decoded.message.thinking != '' {
		choice_parts << schema.ContentPart(schema.ThinkingPart{
			text: decoded.message.thinking
		})
	}
	if decoded.message.content != '' {
		choice_parts << schema.ContentPart(schema.TextPart{
			text: decoded.message.content
		})
	}
	for tool_call in tool_calls {
		choice_parts << schema.ContentPart(tool_call)
	}
	choice := llms.Choice{
		content:     decoded.message.content
		stop_reason: decoded.done_reason
		tool_calls:  tool_calls
		reasoning:   decoded.message.thinking
		parts:       choice_parts
	}
	return llms.Response{
		choices: [choice]
		usage:   llms.Usage{
			prompt_tokens:     decoded.prompt_eval_count
			completion_tokens: decoded.eval_count
			total_tokens:      decoded.prompt_eval_count + decoded.eval_count
		}
	}
}

fn validate_call_options(options llms.CallOptions) ! {
	if _ := options.streaming_func {
		return error('Ollama streaming is not supported by the bounded HTTP transport')
	}
	if _ := options.streaming_reasoning_func {
		return error('Ollama streaming is not supported by the bounded HTTP transport')
	}
	if options.provider_options.len > 0 {
		return error('Ollama provider_options are not supported; use typed call options')
	}
	if _ := options.web_search_options {
		return error('Ollama web search options are not supported')
	}
	if options.candidate_count > 1 || options.n > 1 || options.min_length > 0 || options.max_length > 0 {
		return error('Ollama does not support one or more requested generation options')
	}
	if _ := options.tool_choice {
		return error('Ollama supports tools but not tool choice or legacy function options')
	}
	if options.functions.len > 0 || options.function_call_behavior != '' {
		return error('Ollama supports tools but not tool choice or legacy function options')
	}
	if options.response_mime_type !in ['', 'application/json'] {
		return error('Ollama does not support response MIME type `${options.response_mime_type}`')
	}
	if options.top_k < 0 {
		return error('Ollama top_k cannot be negative')
	}
}

fn validate_image_limits(messages []schema.Message) ! {
	mut total_image_bytes := 0
	for message in messages {
		for part in message.parts {
			match part {
				schema.BinaryPart {
					if !part.mime_type.to_lower().starts_with('image/') {
						return error('Ollama only supports inline image binary parts')
					}
					if part.data.len > max_inline_image_bytes - total_image_bytes {
						return error('Ollama inline images exceed the 5 MiB request limit')
					}
					total_image_bytes += part.data.len
				}
				else {}
			}
		}
	}
}

fn make_request(client Client, model string, messages []schema.Message, options llms.CallOptions) !map[string]json2.Any {
	validate_image_limits(messages)!
	mut wire_messages := []json2.Any{cap: messages.len}
	for message in messages {
		wire_messages << json2.Any(convert_message(message)!)
	}
	mut request := map[string]json2.Any{
		'model':    json2.Any(model)
		'messages': json2.Any(wire_messages)
		'stream':   json2.Any(false)
	}
	format := if options.json_mode || options.response_mime_type == 'application/json' {
		'json'
	} else {
		client.format
	}
	if format != '' {
		request['format'] = json2.Any(format)
	}
	if client.keep_alive != '' {
		request['keep_alive'] = json2.Any(client.keep_alive)
	}
	mut generation_options := map[string]json2.Any{}
	if options.max_tokens > 0 {
		generation_options['num_predict'] = json2.Any(options.max_tokens)
	}
	if options.temperature != 0 {
		generation_options['temperature'] = json2.Any(options.temperature)
	}
	if options.top_k > 0 {
		generation_options['top_k'] = json2.Any(options.top_k)
	}
	if options.top_p > 0 {
		generation_options['top_p'] = json2.Any(options.top_p)
	}
	if seed := options.seed {
		generation_options['seed'] = json2.Any(seed)
	}
	if options.repetition_penalty != 0 {
		generation_options['repeat_penalty'] = json2.Any(options.repetition_penalty)
	}
	if options.frequency_penalty != 0 {
		generation_options['frequency_penalty'] = json2.Any(options.frequency_penalty)
	}
	if options.presence_penalty != 0 {
		generation_options['presence_penalty'] = json2.Any(options.presence_penalty)
	}
	if options.stop_words.len > 0 {
		mut stop_words := []json2.Any{cap: options.stop_words.len}
		for stop_word in options.stop_words {
			stop_words << json2.Any(stop_word)
		}
		generation_options['stop'] = json2.Any(stop_words)
	}
	if generation_options.len > 0 {
		request['options'] = json2.Any(generation_options)
	}
	mut wire_tools := []json2.Any{cap: options.tools.len}
	for tool in options.tools {
		mut function := map[string]json2.Any{
			'name':       json2.Any(tool.name)
			'parameters': tool.parameters
		}
		if tool.description != '' {
			function['description'] = json2.Any(tool.description)
		}
		wire_tools << json2.Any({
			'type':     json2.Any('function')
			'function': json2.Any(function)
		})
	}
	if wire_tools.len > 0 {
		request['tools'] = json2.Any(wire_tools)
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
	mut content := []string{}
	mut images := []string{}
	mut tool_calls := []json2.Any{}
	mut thinking := []string{}
	mut tool_name := ''
	for part in message.parts {
		match part {
			schema.TextPart {
				content << part.text
			}
			schema.BinaryPart {
				images << base64.encode(part.data)
			}
			schema.ImageURLPart {
				return error('Ollama requires inline image data; image URLs are not supported')
			}
			schema.ToolCall {
				if message.role != .ai {
					return error('Ollama tool calls must be in assistant messages')
				}
				if part.function_call.name.trim_space() == '' {
					return error('Ollama tool call function name must not be empty')
				}
				tool_arguments := json2.decode[map[string]json2.Any](part.function_call.arguments,
					json2.DecoderOptions{}) or {
					return error('Ollama tool call arguments must be a JSON object')
				}
				tool_calls << json2.Any({
					'function': json2.Any({
						'name':      json2.Any(part.function_call.name)
						'arguments': json2.Any(tool_arguments)
					})
				})
			}
			schema.ToolResult {
				if message.role != .tool {
					return error('Ollama tool results must use the tool role')
				}
				content << part.content
				tool_name = part.name
			}
			schema.ThinkingPart {
				thinking << part.text
			}
			schema.RedactedThinkingPart {
				return error('Ollama cannot replay redacted reasoning data')
			}
		}
	}
	mut result := map[string]json2.Any{
		'role':    json2.Any(role)
		'content': json2.Any(content.join(''))
	}
	if images.len > 0 {
		mut wire_images := []json2.Any{cap: images.len}
		for image in images {
			wire_images << json2.Any(image)
		}
		result['images'] = json2.Any(wire_images)
	}
	if tool_calls.len > 0 {
		result['tool_calls'] = json2.Any(tool_calls)
	}
	if thinking.len > 0 {
		result['thinking'] = json2.Any(thinking.join(''))
	}
	if tool_name != '' {
		result['tool_name'] = json2.Any(tool_name)
	}
	return result
}
