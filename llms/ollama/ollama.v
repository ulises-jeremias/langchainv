// Package ollama implements Ollama chat generation.
module ollama

import context
import encoding.base64
import json2
import math
import ulises_jeremias.langchainv.callbacks
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
	base_url              string = default_base_url
	model                 string
	format                string
	format_schema         map[string]json2.Any
	keep_alive            string
	legacy_server_version string
pub mut:
	callbacks ?callbacks.Handler
}

// Options configures the Ollama server, model, output format, legacy server
// compatibility, model lifetime, and lifecycle callbacks.
pub struct Options {
pub:
	base_url      string = default_base_url
	model         string
	format        string
	format_schema string
	keep_alive    string
	// legacy_server_version is the exact Ollama server version expected when
	// sending legacy runner options. It is verified through GET /api/version.
	legacy_server_version string
	callbacks             ?callbacks.Handler
}

struct ChatResponse {
	message           ChatMessage
	done_reason       string
	prompt_eval_count int
	eval_count        int
}

struct GenerateResponse {
	response          string
	thinking          string
	done              bool
	done_reason       string
	prompt_eval_count int
	eval_count        int
}

struct GenerateStreamState {
mut:
	buffer            string
	content           string
	thinking          string
	done_reason       string
	prompt_tokens     int
	completion_tokens int
	received_bytes    i64
	done              bool
	error             string
}

struct OllamaStreamState {
mut:
	buffer            string
	content           string
	thinking          string
	tool_calls        []ChatToolCall
	done_reason       string
	prompt_tokens     int
	completion_tokens int
	received_bytes    i64
	error             string
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
	if options.legacy_server_version.trim_space() != '' {
		parse_ollama_version(options.legacy_server_version) or {
			return error('Ollama legacy_server_version must use major.minor.patch format')
		}
	}
	if options.format !in ['', 'json'] {
		return error('Ollama format must be empty or `json`; use format_schema for a JSON Schema')
	}
	if options.format != '' && options.format_schema.trim_space() != '' {
		return error('Ollama format and format_schema cannot both be configured')
	}
	mut format_schema := map[string]json2.Any{}
	if options.format_schema.trim_space() != '' {
		if options.format_schema.len > max_request_bytes {
			return error('Ollama format_schema exceeds the 8 MiB request size limit')
		}
		format_schema = json2.decode[map[string]json2.Any](options.format_schema,
			json2.DecoderOptions{}) or {
			return error('Ollama format_schema must be a valid JSON object: ${err.msg()}')
		}
		if format_schema.len == 0 {
			return error('Ollama format_schema must not be an empty JSON object')
		}
	}
	base_url := options.base_url.trim_space().trim_right('/')
	httputil.validate_url(base_url, '') or { return error('invalid Ollama base URL: ${err.msg()}') }
	return Client{
		http_client:           http_client
		base_url:              base_url
		model:                 options.model.trim_space()
		format:                options.format
		format_schema:         format_schema
		keep_alive:            options.keep_alive.trim_space()
		legacy_server_version: options.legacy_server_version.trim_space()
		callbacks:             options.callbacks
	}
}

// new_default_client creates a client for a local Ollama server.
pub fn new_default_client(model string) !Client {
	return new_client(httputil.HTTPClient(httputil.new_default_client()), Options{
		model: model
	})
}

// complete implements CompletionModel through Ollama's prompt-oriented /api/generate endpoint.
pub fn (client Client) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	response := client.generate_completion(mut ctx, prompt, options)!
	if response.choices.len == 0 {
		return error('Ollama returned no completion choices')
	}
	return response.choices[0].content
}

// generate_completion sends a prompt to /api/generate and returns its response,
// usage, stop reason, and optional reasoning. It does not convert the prompt to chat.
pub fn (client Client) generate_completion(mut ctx context.Context, prompt string, options llms.CallOptions) !llms.Response {
	options.validate()!
	validate_completion_options(options)!
	if prompt.len > max_request_bytes {
		return error('Ollama generate request exceeds the 8 MiB size limit')
	}
	if mut handler := client.callbacks {
		handler.llm_start(mut ctx, [prompt])
	}
	response := client.generate_completion_request(mut ctx, prompt, options) or {
		if mut handler := client.callbacks {
			handler.llm_error(mut ctx, err)
		}
		return err
	}
	if mut handler := client.callbacks {
		if response.choices.len > 0 {
			handler.llm_complete_end(mut ctx, response.choices[0].content)
		}
	}
	return response
}

fn (client Client) generate_completion_request(mut ctx context.Context, prompt string, options llms.CallOptions) !llms.Response {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	model := if options.model.trim_space() == '' {
		client.model
	} else {
		options.model.trim_space()
	}
	request := make_generate_request(client, model, prompt, options)!
	client.validate_legacy_server_version(mut ctx, options.provider_options)!
	if options.streaming_func != none || options.streaming_reasoning_func != none {
		return client.generate_completion_stream(mut ctx, request, options)
	}
	body := json2.encode(request, json2.EncoderOptions{})
	if body.len > max_request_bytes {
		return error('Ollama generate request exceeds the 8 MiB size limit')
	}
	response := client.http_client.do(mut ctx, httputil.Request{
		method:  .post
		url:     '${client.base_url}/api/generate'
		headers: {
			'Content-Type': 'application/json'
			'Accept':       'application/json'
		}
		body:    body
	}) or {
		return error('Ollama generate request failed: ${err.msg()}')
	}
	ctx_error_after_request := ctx.err()
	if ctx_error_after_request !is none {
		return ctx_error_after_request
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Ollama generate request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_response_bytes {
		return error('Ollama generate response exceeds the 16 MiB size limit')
	}
	decoded := json2.decode[GenerateResponse](response.body, json2.DecoderOptions{}) or {
		return error('could not decode Ollama generate response: ${err.msg()}')
	}
	if !decoded.done {
		return error('Ollama generate response is incomplete')
	}
	return response_from_generate(decoded)
}

// generate_content implements streaming and non-streaming Ollama /api/chat requests.
pub fn (client Client) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	options.validate()!
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
	client.validate_legacy_server_version(mut ctx, options.provider_options)!
	if _ := options.streaming_func {
		return client.generate_stream(mut ctx, request, options)
	}
	if _ := options.streaming_reasoning_func {
		return client.generate_stream(mut ctx, request, options)
	}
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
	return response_from_chat(decoded)!
}

fn response_from_chat(decoded ChatResponse) !llms.Response {
	if decoded.message.content == '' && decoded.message.thinking == '' && decoded.message.tool_calls.len == 0 {
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

fn (client Client) generate_stream(mut ctx context.Context, request map[string]json2.Any, options llms.CallOptions) !llms.Response {
	if client.http_client !is httputil.StreamingHTTPClient {
		return error('configured Ollama HTTP transport does not support streaming responses')
	}
	stream_client := client.http_client as httputil.StreamingHTTPClient
	mut stream_request := map[string]json2.Any{}
	for key, value in request {
		stream_request[key] = value
	}
	stream_request['stream'] = json2.Any(true)
	body := json2.encode(stream_request, json2.EncoderOptions{})
	if body.len > max_request_bytes {
		return error('Ollama chat request exceeds the 8 MiB size limit')
	}
	mut state := &OllamaStreamState{}
	mut process_line := fn [options, mut state] (mut callback_ctx context.Context, line string) {
		if line.trim_space() == '' {
			return
		}
		chunk := json2.decode[ChatResponse](line, json2.DecoderOptions{}) or {
			state.error = 'could not decode Ollama streaming response'
			return
		}
		if chunk.message.content != '' {
			state.content += chunk.message.content
			if callback := options.streaming_func {
				callback(mut callback_ctx, chunk.message.content.bytes()) or {
					state.error = 'Ollama streaming callback failed: ${err.msg()}'
					return
				}
			}
		}
		if chunk.message.thinking != '' {
			state.thinking += chunk.message.thinking
			if callback := options.streaming_reasoning_func {
				callback(mut callback_ctx, chunk.message.thinking.bytes(), chunk.message.content.bytes()) or {
					state.error = 'Ollama reasoning callback failed: ${err.msg()}'
					return
				}
			}
		} else if chunk.message.content != '' {
			if callback := options.streaming_reasoning_func {
				callback(mut callback_ctx, []u8{}, chunk.message.content.bytes()) or {
					state.error = 'Ollama reasoning callback failed: ${err.msg()}'
					return
				}
			}
		}
		if chunk.message.tool_calls.len > 0 {
			state.tool_calls = chunk.message.tool_calls
		}
		if chunk.done_reason != '' {
			state.done_reason = chunk.done_reason
		}
		if chunk.prompt_eval_count > 0 {
			state.prompt_tokens = chunk.prompt_eval_count
		}
		if chunk.eval_count > 0 {
			state.completion_tokens = chunk.eval_count
		}
	}
	response := stream_client.do_stream(mut ctx, httputil.Request{
		method:  .post
		url:     '${client.base_url}/api/chat'
		headers: {
			'Content-Type': 'application/json'
			'Accept':       'application/x-ndjson'
		}
		body:    body
	}, fn [mut state, mut process_line] (mut callback_ctx context.Context, bytes []u8) ! {
		state.received_bytes += i64(bytes.len)
		if state.received_bytes > max_response_bytes {
			return error('Ollama chat response exceeds the 16 MiB size limit')
		}
		state.buffer += bytes.bytestr()
		for {
			line_end := state.buffer.index('\n') or { break }
			line := state.buffer[..line_end].trim_right('\r')
			state.buffer = state.buffer[line_end + 1..]
			process_line(mut callback_ctx, line)
			if state.error != '' {
				return error(state.error)
			}
		}
	}) or {
		return error('Ollama chat stream failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Ollama chat request returned HTTP ${response.status_code}')
	}
	if state.buffer.trim_space() != '' {
		process_line(mut ctx, state.buffer.trim_right('\r'))
	}
	if state.error != '' {
		return error(state.error)
	}
	return response_from_chat(ChatResponse{
		message:           ChatMessage{
			content:    state.content
			thinking:   state.thinking
			tool_calls: state.tool_calls
		}
		done_reason:       state.done_reason
		prompt_eval_count: state.prompt_tokens
		eval_count:        state.completion_tokens
	})
}

fn validate_call_options(options llms.CallOptions) ! {
	validate_provider_options(options.provider_options)!
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

fn validate_completion_options(options llms.CallOptions) ! {
	validate_call_options(options)!
	if options.tools.len > 0 || options.functions.len > 0 || options.function_call_behavior != '' {
		return error('Ollama /api/generate does not support tool calls')
	}
	if 'truncate' in options.provider_options || 'shift' in options.provider_options {
		return error('Ollama /api/generate does not support truncate or shift options')
	}
}

// validate_provider_options accepts Ollama's native runner fields while
// rejecting misspellings and values that would produce invalid API payloads.
fn validate_provider_options(provider_options map[string]json2.Any) ! {
	for key, value in provider_options {
		match key {
			'num_ctx', 'num_batch', 'num_gpu', 'main_gpu', 'num_thread', 'repeat_last_n', 'seed',
			'top_k', 'num_keep', 'num_predict', 'draft_num_predict', 'top_logprobs', 'num_gqa',
			'mirostat' {
				if !is_integer_value(value) {
					return error('Ollama provider_options ${key} must be an integer')
				}
				if key == 'num_gqa' && value.i64() <= 0 {
					return error('Ollama provider_options num_gqa must be positive')
				}
				if key == 'mirostat' && value.i64() !in [i64(0), i64(1), i64(2)] {
					return error('Ollama provider_options mirostat must be 0, 1, or 2')
				}
			}
			'typical_p', 'repeat_penalty', 'presence_penalty', 'frequency_penalty', 'top_p',
			'min_p', 'temperature', 'tfs_z', 'mirostat_tau', 'mirostat_eta' {
				if !is_numeric_value(value) || !math.is_finite(value.f64()) {
					return error('Ollama provider_options ${key} must be numeric')
				}
			}
			'use_mmap', 'logprobs', 'truncate', 'shift', 'raw', 'numa', 'low_vram', 'f16_kv',
			'logits_all', 'vocab_only', 'use_mlock', 'penalize_newline' {
				if value !is bool {
					return error('Ollama provider_options ${key} must be a boolean')
				}
			}
			'suffix', 'system', 'template' {
				if value !is string {
					return error('Ollama provider_options ${key} must be a string')
				}
			}
			'think' {
				if value !is bool && (value !is string || (value as string).trim_space() == '') {
					return error('Ollama provider_options think must be a boolean or non-empty string')
				}
			}
			else {
				return error('Ollama provider_options key `${key}` is not supported; use stop_words for stop sequences')
			}
		}
	}
}

fn is_integer_value(value json2.Any) bool {
	return match value {
		int, i64, i32, i16, i8, u64, u32, u16, u8 { true }
		else { false }
	}
}

fn is_numeric_value(value json2.Any) bool {
	return match value {
		int, i64, i32, i16, i8, u64, u32, u16, u8, f64, f32 { true }
		else { false }
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
	if client.format_schema.len > 0 {
		request['format'] = json2.Any(client.format_schema)
	} else {
		format := if options.json_mode || options.response_mime_type == 'application/json' {
			'json'
		} else {
			client.format
		}
		if format != '' {
			request['format'] = json2.Any(format)
		}
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
	for key, value in options.provider_options {
		if key in ['think', 'logprobs', 'top_logprobs', 'truncate', 'shift'] {
			request[key] = value
		} else {
			generation_options[key] = value
		}
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

fn make_generate_request(client Client, model string, prompt string, options llms.CallOptions) !map[string]json2.Any {
	validate_provider_options(options.provider_options)!
	mut request := map[string]json2.Any{
		'model':  json2.Any(model)
		'prompt': json2.Any(prompt)
		'stream': json2.Any(options.streaming_func != none || options.streaming_reasoning_func != none)
	}
	if client.format_schema.len > 0 {
		request['format'] = json2.Any(client.format_schema)
	} else {
		format := if options.json_mode || options.response_mime_type == 'application/json' {
			'json'
		} else {
			client.format
		}
		if format != '' {
			request['format'] = json2.Any(format)
		}
	}
	if client.keep_alive != '' {
		request['keep_alive'] = json2.Any(client.keep_alive)
	}
	mut generation_options := map[string]json2.Any{}
	if options.max_tokens > 0 { generation_options['num_predict'] = json2.Any(options.max_tokens) }
	if options.temperature != 0 {
		generation_options['temperature'] = json2.Any(options.temperature)
	}
	if options.top_k > 0 { generation_options['top_k'] = json2.Any(options.top_k) }
	if options.top_p > 0 { generation_options['top_p'] = json2.Any(options.top_p) }
	if seed := options.seed { generation_options['seed'] = json2.Any(seed) }
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
		mut stop := []json2.Any{cap: options.stop_words.len}
		for word in options.stop_words { stop << json2.Any(word) }
		generation_options['stop'] = json2.Any(stop)
	}
	for key, value in options.provider_options {
		if key in ['think', 'logprobs', 'top_logprobs', 'raw', 'suffix', 'system', 'template'] {
			request[key] = value
		} else if key !in ['truncate', 'shift'] {
			generation_options[key] = value
		}
	}
	if generation_options.len > 0 {
		request['options'] = json2.Any(generation_options)
	}
	return request
}

fn response_from_generate(decoded GenerateResponse) llms.Response {
	mut parts := []schema.ContentPart{}
	if decoded.thinking != '' {
		parts << schema.ContentPart(schema.ThinkingPart{ text: decoded.thinking })
	}
	if decoded.response != '' {
		parts << schema.ContentPart(schema.TextPart{ text: decoded.response })
	}
	return llms.Response{
		choices: [llms.Choice{
			content:     decoded.response
			stop_reason: decoded.done_reason
			reasoning:   decoded.thinking
			parts:       parts
		}]
		usage:   llms.Usage{
			prompt_tokens:     decoded.prompt_eval_count
			completion_tokens: decoded.eval_count
			total_tokens:      decoded.prompt_eval_count + decoded.eval_count
		}
	}
}

fn (client Client) generate_completion_stream(mut ctx context.Context, request map[string]json2.Any, options llms.CallOptions) !llms.Response {
	if client.http_client !is httputil.StreamingHTTPClient {
		return error('configured Ollama HTTP transport does not support streaming responses')
	}
	stream_client := client.http_client as httputil.StreamingHTTPClient
	mut state := &GenerateStreamState{}
	mut process_line := fn [options, mut state] (mut callback_ctx context.Context, line string) {
		if line.trim_space() == '' { return }
		chunk := json2.decode[GenerateResponse](line, json2.DecoderOptions{}) or {
			state.error = 'could not decode Ollama generate streaming response'
			return
		}
		if chunk.response != '' {
			state.content += chunk.response
			if callback := options.streaming_func {
				callback(mut callback_ctx, chunk.response.bytes()) or {
					state.error = 'Ollama generate streaming callback failed: ${err.msg()}'
					return
				}
				ctx_error := callback_ctx.err()
				if ctx_error !is none {
					state.error = ctx_error.msg()
					return
				}
			}
		}
		if chunk.thinking != '' { state.thinking += chunk.thinking }
		if reasoning_callback := options.streaming_reasoning_func {
			reasoning_callback(mut callback_ctx, chunk.thinking.bytes(), chunk.response.bytes()) or {
				state.error = 'Ollama generate reasoning callback failed: ${err.msg()}'
				return
			}
			ctx_error := callback_ctx.err()
			if ctx_error !is none {
				state.error = ctx_error.msg()
				return
			}
		}
		if chunk.done_reason != '' { state.done_reason = chunk.done_reason }
		if chunk.prompt_eval_count > 0 { state.prompt_tokens = chunk.prompt_eval_count }
		if chunk.eval_count > 0 { state.completion_tokens = chunk.eval_count }
		state.done = chunk.done
	}
	body := json2.encode(request, json2.EncoderOptions{})
	if body.len > max_request_bytes {
		return error('Ollama generate request exceeds the 8 MiB size limit')
	}
	response := stream_client.do_stream(mut ctx, httputil.Request{
		method:  .post
		url:     '${client.base_url}/api/generate'
		headers: {
			'Content-Type': 'application/json'
			'Accept':       'application/x-ndjson'
		}
		body:    body
	}, fn [mut state, mut process_line] (mut callback_ctx context.Context, bytes []u8) ! {
		state.received_bytes += i64(bytes.len)
		if state.received_bytes > max_response_bytes {
			return error('Ollama generate response exceeds the 16 MiB size limit')
		}
		state.buffer += bytes.bytestr()
		for {
			line_end := state.buffer.index('\n') or { break }
			line := state.buffer[..line_end].trim_right('\r')
			state.buffer = state.buffer[line_end + 1..]
			process_line(mut callback_ctx, line)
			if state.error != '' { return error(state.error) }
		}
	}) or {
		return error('Ollama generate stream failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Ollama generate request returned HTTP ${response.status_code}')
	}
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	if state.buffer.trim_space() != '' { process_line(mut ctx, state.buffer.trim_right('\r')) }
	if state.error != '' { return error(state.error) }
	if !state.done { return error('Ollama generate stream ended before completion') }
	return response_from_generate(GenerateResponse{
		response:          state.content
		thinking:          state.thinking
		done:              state.done
		done_reason:       state.done_reason
		prompt_eval_count: state.prompt_tokens
		eval_count:        state.completion_tokens
	})
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
