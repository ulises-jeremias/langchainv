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

// Config configures a text chat completion client.
@[params]
pub struct Config {
pub:
	api_key      string
	model        string = default_model
	base_url     string = default_base_url
	organization string
}

// Client implements the provider-neutral model and completion contracts.
pub struct Client {
pub:
	config Config
}

// new creates a client using the key in config or OPENAI_API_KEY.
pub fn new(config Config) !Client {
	mut resolved := config
	if resolved.api_key == '' {
		resolved.api_key = os.getenv('OPENAI_API_KEY')
	}
	if resolved.api_key.trim_space() == '' {
		return error('OpenAI API key is required; set Config.api_key or OPENAI_API_KEY')
	}
	if resolved.model.trim_space() == '' {
		resolved.model = default_model
	}
	if resolved.base_url.trim_space() == '' {
		resolved.base_url = default_base_url
	}
	resolved.base_url = resolved.base_url.trim_right('/')
	return Client{
		config: resolved
	}
}

// generate_content sends text messages to the OpenAI chat completions endpoint.
// It checks context cancellation before and after the HTTP call. V's net.http
// does not currently expose request-context cancellation to an in-flight fetch.
pub fn (client Client) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	if err := ctx.err() {
		return err
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
		url:           '${client.config.base_url}/chat/completions'
		method:        .post
		header:        header
		data:          body
		allow_redirect: false
	})!
	if err := ctx.err() {
		return err
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
	mut result := llms.Response{
		usage: llms.Usage{
			prompt_tokens:     decoded.usage.prompt_tokens
			completion_tokens: decoded.usage.completion_tokens
			total_tokens:      decoded.usage.total_tokens
		}
	}
	for choice in decoded.choices {
		result.choices << llms.Choice{
			content:         choice.message.content
			stop_reason:     choice.finish_reason
			generation_info: {
				'index': i64(choice.index)
			}
		}
	}
	return result
}

// complete generates text from a prompt using the configured chat model.
pub fn (client Client) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	response := client.generate_content(mut ctx, [schema.text_message(.human, prompt)], options)!
	if response.choices.len == 0 {
		return error('OpenAI returned no completion choices')
	}
	return response.choices[0].content
}

fn chat_payload(config Config, messages []schema.Message, options llms.CallOptions) !json2.Any {
	model_name := if options.model != '' { options.model } else { config.model }
	if options.streaming_func != none || options.streaming_reasoning_func != none {
		return error('OpenAI streaming is not implemented yet')
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
						return error('OpenAI text adapter does not support non-text message parts yet')
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
		for part in message.parts {
			match part {
				schema.TextPart {
					content.write_string(part.text)
				}
				else {
					return error('OpenAI text adapter does not support non-text message parts yet')
				}
			}
		}
		message_content := if system_content != '' && !system_supported && message.role == .human {
			combined := '${system_content}\n\n${content.str()}'
			system_content = ''
			combined
		} else {
			content.str()
		}
		item := map[string]json2.Any{
			'role':    role
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
		'model':       model_name
		'messages':    request_messages
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
