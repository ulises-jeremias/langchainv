// Package openai contains the OpenAI chat completions adapter.
module openai

import json2
import net.http
import os
import strings
import context
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

const default_base_url = 'https://api.openai.com/v1'
const default_model = 'gpt-3.5-turbo'
const default_embedding_model = 'text-embedding-ada-002'
const max_sse_event_bytes = 1_048_576

// Config configures the OpenAI chat completion and embedding client.
@[params]
pub struct Config {
pub:
	api_key              string
	model                string = default_model
	base_url             string = default_base_url
	organization         string
	embedding_model      string = default_embedding_model
	embedding_dimensions int
}

// Client implements the provider-neutral model and completion contracts.
pub struct Client {
pub:
	config Config
}

// new creates a client using the key in config or OPENAI_API_KEY.
pub fn new(config Config) !Client {
	api_key := if config.api_key == '' { os.getenv('OPENAI_API_KEY') } else { config.api_key }
	if api_key.trim_space() == '' {
		return error('OpenAI API key is required; set Config.api_key or OPENAI_API_KEY')
	}
	if config.embedding_dimensions < 0 {
		return error('embedding dimensions cannot be negative')
	}
	model := if config.model.trim_space() == '' { default_model } else { config.model }
	base_url := if config.base_url.trim_space() == '' {
		default_base_url
	} else {
		config.base_url.trim_right('/')
	}
	return Client{
		config: Config{
			api_key:              api_key
			model:                model
			base_url:             base_url
			organization:         config.organization
			embedding_model:      if config.embedding_model.trim_space() == '' {
				default_embedding_model
			} else {
				config.embedding_model
			}
			embedding_dimensions: config.embedding_dimensions
		}
	}
}

// generate_content sends text messages to the OpenAI chat completions endpoint.
// It checks context cancellation before and after the HTTP call. V's net.http
// does not currently expose request-context cancellation to an in-flight fetch.
pub fn (client Client) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	err := ctx.err()
	if err !is none {
		return err
	}
	if options.streaming_reasoning_func != none {
		return error('OpenAI reasoning streaming is not implemented')
	}
	if options.streaming_func != none {
		return client.stream_content(mut ctx, messages, options)
	}
	llms.validate_messages(messages)!
	options.validate()!
	payload := chat_payload(client.config, messages, options)!
	body := json2.encode(payload, json2.EncoderOptions{})
	mut header := http.new_header()
	header.set(.content_type, 'application/json')
	header.set(.authorization, 'Bearer ${client.config.api_key}')
	if client.config.organization != '' {
		header.set_custom('OpenAI-Organization', client.config.organization)!
	}
	response := httputil.fetch(http.FetchConfig{
		url:            '${client.config.base_url}/chat/completions'
		method:         .post
		header:         header
		data:           body
		allow_redirect: false
	})!
	request_context_error := ctx.err()
	if request_context_error !is none {
		return request_context_error
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('OpenAI chat request failed with HTTP ${response.status_code}')
	}
	decoded := json2.decode[ChatCompletionResponse](response.body, json2.DecoderOptions{}) or {
		return error('OpenAI returned an invalid chat response')
	}
	if decoded.choices.len == 0 {
		return error('OpenAI returned no chat choices')
	}
	mut choices := []llms.Choice{cap: decoded.choices.len}
	for choice in decoded.choices {
		choices << llms.Choice{
			content:         choice.message.content
			stop_reason:     choice.finish_reason
			generation_info: {
				'index': i64(choice.index)
			}
		}
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

fn (client Client) stream_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	llms.validate_messages(messages)!
	options.validate()!
	choice_count := if options.n > 0 { options.n } else { options.candidate_count }
	if choice_count > 1 {
		return error('OpenAI streaming supports one choice because StreamFunc has no choice index')
	}
	callback := options.streaming_func or {
		return error('OpenAI streaming requires a streaming callback')
	}
	mut payload := chat_payload(client.config, messages, options)!
	mut request_payload := payload as map[string]json2.Any
	request_payload['stream'] = true
	request_payload['stream_options'] = json2.Any(map[string]json2.Any{
		'include_usage': true
	})
	body := json2.encode(json2.Any(request_payload), json2.EncoderOptions{})
	mut header := http.new_header()
	header.set(.content_type, 'application/json')
	header.set(.authorization, 'Bearer ${client.config.api_key}')
	header.set_custom('Accept', 'text/event-stream')!
	if client.config.organization != '' {
		header.set_custom('OpenAI-Organization', client.config.organization)!
	}
	mut state := StreamState{
		ctx:      ctx
		callback: callback
	}
	response := httputil.fetch(http.FetchConfig{
		url:              '${client.config.base_url}/chat/completions'
		method:           .post
		header:           header
		data:             body
		allow_redirect:   false
		max_retries:      1
		on_progress_body: fn [mut state] (request &http.Request, chunk []u8, body_read_so_far u64, body_expected_size u64, status_code int) ! {
			_ = request
			_ = body_read_so_far
			_ = body_expected_size
			if status_code < 200 || status_code >= 300 {
				return
			}
			consume_stream_bytes(mut state, chunk) or {
				state.callback_failed = true
				return err
			}
		}
	}) or {
		request_context_error := ctx.err()
		if request_context_error !is none {
			return request_context_error
		}
		if state.callback_failed {
			return error('OpenAI streaming callback or event processing failed')
		}
		return err
	}
	request_context_error := ctx.err()
	if request_context_error !is none {
		return request_context_error
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('OpenAI chat request failed with HTTP ${response.status_code}')
	}
	flush_stream_pending(mut state) or {
		return error('OpenAI returned an invalid event stream')
	}
	if !state.done {
		return error('OpenAI event stream ended before the completion marker')
	}
	if state.content == '' && state.finish_reason == '' {
		return error('OpenAI returned no streamed chat choice')
	}
	return llms.Response{
		choices: [llms.Choice{
			content:         state.content
			stop_reason:     state.finish_reason
			generation_info: {
				'index': i64(0)
			}
		}]
		usage:   state.usage
	}
}

// complete generates text from a prompt using the configured chat model.
pub fn (client Client) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	response := client.generate_content(mut ctx, [schema.text_message(.human, prompt)], options)!
	if response.choices.len == 0 {
		return error('OpenAI returned no completion choices')
	}
	return response.choices[0].content
}

// create_embedding returns one vector for each input text. It implements the
// shared embeddings.EmbedderClient contract and preserves the API response order.
pub fn (client Client) create_embedding(mut ctx context.Context, texts []string) ![][]f32 {
	if texts.len == 0 {
		return []
	}
	context_error := ctx.err()
	if context_error !is none {
		return context_error
	}
	body := json2.encode(embedding_payload(client.config, texts), json2.EncoderOptions{})
	mut header := http.new_header()
	header.set(.content_type, 'application/json')
	header.set(.authorization, 'Bearer ${client.config.api_key}')
	if client.config.organization != '' {
		header.set_custom('OpenAI-Organization', client.config.organization)!
	}
	response := httputil.fetch(http.FetchConfig{
		url:            '${client.config.base_url}/embeddings'
		method:         .post
		header:         header
		data:           body
		allow_redirect: false
	})!
	request_context_error := ctx.err()
	if request_context_error !is none {
		return request_context_error
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('OpenAI embedding request failed with HTTP ${response.status_code}')
	}
	decoded := json2.decode[EmbeddingResponse](response.body, json2.DecoderOptions{}) or {
		return error('OpenAI returned an invalid embedding response')
	}
	return embeddings_from_response(decoded, texts.len)
}

fn embedding_payload(config Config, texts []string) json2.Any {
	mut inputs := []json2.Any{cap: texts.len}
	for text in texts {
		inputs << json2.Any(text)
	}
	mut payload := map[string]json2.Any{
		'model': json2.Any(config.embedding_model)
		'input': json2.Any(inputs)
	}
	if config.embedding_dimensions > 0 {
		payload['dimensions'] = config.embedding_dimensions
	}
	return json2.Any(payload)
}

fn embeddings_from_response(response EmbeddingResponse, expected_count int) ![][]f32 {
	if response.data.len != expected_count {
		return error('OpenAI returned ${response.data.len} embeddings for ${expected_count} inputs')
	}
	return response.data.map(it.embedding)
}

fn chat_payload(config Config, messages []schema.Message, options llms.CallOptions) !json2.Any {
	model_name := if options.model != '' { options.model } else { config.model }
	if options.streaming_reasoning_func != none {
		return error('OpenAI reasoning streaming is not implemented')
	}
	if options.tools.len > 0 || options.functions.len > 0 || options.tool_choice != none
		|| options.function_call_behavior != '' {
		return error('OpenAI tool calling is not implemented yet')
	}
	if options.top_k != 0 || options.min_length != 0 || options.max_length != 0
		|| options.repetition_penalty != 0 {
		return error('requested generation option is not supported by the OpenAI adapter')
	}
	if options.web_search_options != none || options.metadata.len > 0 || options.provider_options.len > 0
		|| options.response_mime_type != '' {
		return error('requested provider option is not supported by the OpenAI adapter')
	}
	if options.candidate_count > 0 && options.n > 0 && options.candidate_count != options.n {
		return error('candidate_count and n cannot request different choice counts')
	}
	choice_count := if options.n > 0 { options.n } else { options.candidate_count }
	system_supported := supports_system_messages(model_name)
	mut system_content := ''
	if !system_supported {
		for message in messages {
			if message.role == .system {
				mut part_text := strings.new_builder(64)
				for part in message.parts {
					if part is schema.TextPart {
						part_text.write_string(part.text)
					} else {
						return error('OpenAI chat adapter requires text-only system messages for reasoning models')
					}
				}
				if system_content != '' {
					system_content += '\n\n'
				}
				system_content += part_text.str()
			}
		}
	}
	mut request_messages := []json2.Any{cap: messages.len}
	for message in messages {
		if message.role == .system && !system_supported {
			continue
		}
		role := match message.role {
			.system { 'system' }
			.human { 'user' }
			.ai { 'assistant' }
			.tool { 'tool' }
			.generic { 'user' }
		}
		mut content := strings.new_builder(64)
		mut content_parts := []json2.Any{cap: message.parts.len}
		mut has_image := false
		for part in message.parts {
			match part {
				schema.TextPart {
					content.write_string(part.text)
					content_parts << json2.Any(map[string]json2.Any{
						'type': 'text'
						'text': part.text
					})
				}
				schema.ImageURLPart {
					if message.role != .human && message.role != .generic {
						return error('OpenAI image inputs are only supported in user messages')
					}
					if part.url.trim_space() == '' {
						return error('OpenAI image URL cannot be empty')
					}
					if part.detail != '' && part.detail !in ['auto', 'low', 'high'] {
						return error('OpenAI image detail must be auto, low, or high')
					}
					mut image_url := map[string]json2.Any{
						'url': part.url
					}
					if part.detail != '' {
						image_url['detail'] = part.detail
					}
					content_parts << json2.Any(map[string]json2.Any{
						'type':      json2.Any('image_url')
						'image_url': json2.Any(image_url)
					})
					has_image = true
				}
				else {
					return error('OpenAI chat adapter does not support this message content part yet')
				}
			}
		}
		mut message_content := json2.Any(content.str())
		if has_image {
			if system_content != '' && !system_supported && message.role == .human {
				mut with_system := []json2.Any{cap: content_parts.len + 1}
				with_system << json2.Any(map[string]json2.Any{
					'type': 'text'
					'text': '${system_content}\n\n'
				})
				for part in content_parts {
					with_system << part
				}
				content_parts = with_system.clone()
				system_content = ''
			}
			message_content = json2.Any(content_parts)
		} else if system_content != '' && !system_supported && message.role == .human {
			message_content = json2.Any('${system_content}\n\n${content.str()}')
			system_content = ''
		}
		item := map[string]json2.Any{
			'role':    json2.Any(role)
			'content': message_content
		}
		if role == 'tool' {
			return error('OpenAI tool replies require tool-call metadata, not supported yet')
		}
		request_messages << item
	}
	if system_content != '' {
		return error('reasoning models require a user message to carry system instructions')
	}
	mut payload := map[string]json2.Any{
		'model':    json2.Any(model_name)
		'messages': json2.Any(request_messages)
	}
	if !omits_temperature(model_name) {
		payload['temperature'] = options.temperature
	}
	if options.max_tokens > 0 {
		payload['max_completion_tokens'] = options.max_tokens
	}
	if choice_count > 0 {
		payload['n'] = choice_count
	}
	if options.top_p > 0 {
		payload['top_p'] = options.top_p
	}
	if options.frequency_penalty != 0 {
		payload['frequency_penalty'] = options.frequency_penalty
	}
	if options.presence_penalty != 0 {
		payload['presence_penalty'] = options.presence_penalty
	}
	if options.stop_words.len > 0 {
		mut stop_values := []json2.Any{cap: options.stop_words.len}
		for stop_word in options.stop_words {
			stop_values << json2.Any(stop_word)
		}
		payload['stop'] = stop_values
	}
	if seed := options.seed {
		payload['seed'] = seed
	}
	if options.json_mode {
		payload['response_format'] = json2.Any(map[string]json2.Any{
			'type': 'json_object'
		})
	}
	return json2.Any(payload)
}

fn supports_system_messages(model string) bool {
	lower := model.to_lower()
	return lower !in ['o1', 'o1-mini', 'o1-preview', 'o3', 'o3-mini', 'o3-preview']
}

fn omits_temperature(model string) bool {
	lower := model.to_lower()
	return lower.starts_with('o1') || lower.starts_with('o3') || lower.starts_with('o4')
		|| lower.starts_with('gpt-5') || lower.contains('-search-preview')
}

struct ChatCompletionResponse {
	choices []ChatChoice
	usage   ChatUsage
}

struct ChatChoice {
	index         int
	message       ChatMessage
	finish_reason string
}

struct ChatMessage {
	content string
}

struct ChatUsage {
	prompt_tokens     int
	completion_tokens int
	total_tokens      int
}

struct StreamState {
mut:
	ctx             context.Context
	callback        llms.StreamFunc @[required]
	pending         string
	content         string
	finish_reason   string
	usage           llms.Usage
	done            bool
	callback_failed bool
}

struct ChatCompletionChunk {
	choices []ChatChunkChoice
	usage   ?ChatUsage
}

struct ChatChunkChoice {
	index         int
	delta         ChatDelta
	finish_reason ?string
}

struct ChatDelta {
	content ?string
}

fn consume_stream_bytes(mut state StreamState, chunk []u8) ! {
	context_error := state.ctx.err()
	if context_error !is none {
		return context_error
	}
	state.pending += chunk.bytestr()
	state.pending = state.pending.replace('\r\n', '\n')
	for {
		separator := state.pending.index('\n\n') or { break }
		if separator > max_sse_event_bytes {
			state.callback_failed = true
			return error('OpenAI stream event exceeded the configured buffer limit')
		}
		event := state.pending[..separator]
		state.pending = state.pending[separator + 2..]
		process_stream_event(mut state, event)!
	}
	if state.pending.len > max_sse_event_bytes {
		state.callback_failed = true
		return error('OpenAI stream event exceeded the configured buffer limit')
	}
}

fn flush_stream_pending(mut state StreamState) ! {
	if state.pending.trim_space() != '' {
		process_stream_event(mut state, state.pending)!
		state.pending = ''
	}
}

fn process_stream_event(mut state StreamState, event string) ! {
	data := sse_event_data(event) or { return }
	if data == '[DONE]' {
		state.done = true
		return
	}
	chunk := json2.decode[ChatCompletionChunk](data, json2.DecoderOptions{}) or {
		state.callback_failed = true
		return error('invalid OpenAI stream event')
	}
	if usage := chunk.usage {
		state.usage = llms.Usage{
			prompt_tokens:     usage.prompt_tokens
			completion_tokens: usage.completion_tokens
			total_tokens:      usage.total_tokens
		}
	}
	for choice in chunk.choices {
		if choice.index != 0 {
			state.callback_failed = true
			return error('OpenAI returned an unsupported streamed choice index')
		}
		if content := choice.delta.content {
			if content != '' {
				state.content += content
				state.callback(mut state.ctx, content.bytes()) or {
					state.callback_failed = true
					return err
				}
			}
		}
		if finish_reason := choice.finish_reason {
			if finish_reason != '' {
				state.finish_reason = finish_reason
			}
		}
	}
}

fn sse_event_data(event string) ?string {
	mut lines := []string{}
	for line in event.split('\n') {
		if line.starts_with('data:') {
			value := line[5..]
			lines << if value.starts_with(' ') { value[1..] } else { value }
		}
	}
	if lines.len == 0 {
		return none
	}
	return lines.join('\n')
}

struct EmbeddingResponse {
	data []EmbeddingDatum
}

struct EmbeddingDatum {
	embedding []f32
}
