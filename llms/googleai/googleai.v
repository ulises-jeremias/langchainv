// Package googleai implements non-streaming Gemini generateContent requests.
module googleai

import context
import encoding.base64
import json2
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

const default_base_url = 'https://generativelanguage.googleapis.com/v1beta'
const default_model = 'gemini-3.6-flash'
const max_messages = 1024
const max_candidates = 8
const max_request_bytes = 8 * 1024 * 1024
const max_response_bytes = 16 * 1024 * 1024
const max_inline_image_bytes = 5 * 1024 * 1024

struct CandidateResponse {
	content       CandidateContent
	finish_reason string @[json: 'finishReason']
}

struct CandidateContent {
	parts []CandidatePart
}

struct CandidatePart {
	text          string
	function_call ?GoogleFunctionCall @[json: 'functionCall']
}

struct GoogleFunctionCall {
	name string
	args map[string]json2.Any
}

struct GenerateResponse {
	candidates     []CandidateResponse
	usage_metadata UsageMetadata @[json: 'usageMetadata']
}

struct UsageMetadata {
	prompt_token_count     int @[json: 'promptTokenCount']
	candidates_token_count int @[json: 'candidatesTokenCount']
	total_token_count      int @[json: 'totalTokenCount']
}

// Client generates Gemini content with an injected bounded transport.
pub struct Client {
	api_key     string
	http_client httputil.HTTPClient
pub:
	base_url string = default_base_url
	model    string = default_model
}

// Options configures the Gemini API endpoint and model.
pub struct Options {
pub:
	base_url string = default_base_url
	model    string = default_model
}

// new_client creates a client using explicit endpoint and model options.
pub fn new_client(api_key string, http_client httputil.HTTPClient) !Client {
	return new_client_with_options(api_key, http_client, Options{})
}

// new_default_client uses the shared bounded standard-library HTTP transport.
pub fn new_default_client(api_key string) !Client {
	return new_client(api_key, httputil.HTTPClient(httputil.new_default_client()))
}

// new_client_with_options validates and configures the client.
pub fn new_client_with_options(api_key string, http_client httputil.HTTPClient, options Options) !Client {
	if api_key.trim_space() == '' {
		return error('Google AI API key must not be empty')
	}
	if options.base_url.trim_space() == '' || options.model.trim_space() == '' {
		return error('Google AI base URL and model must not be empty')
	}
	base_url := options.base_url.trim_space().trim_right('/')
	httputil.validate_url(base_url, 'https') or { return error('invalid Google AI base URL: ${err.msg()}') }
	mut model := options.model.trim_space()
	if model.starts_with('models/') {
		model = model['models/'.len..]
	}
	if model == '' || model.contains('/') || model.contains('?') || model.contains('#') {
		return error('Google AI model must be a single model identifier')
	}
	return Client{
		api_key:     api_key
		http_client: http_client
		base_url:    base_url
		model:       model
	}
}

// complete implements llms.CompletionModel by sending a user content turn.
pub fn (client Client) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	response := client.generate_content(mut ctx, [schema.text_message(.human, prompt)], options)!
	if response.choices.len == 0 {
		return error('Google AI returned no completion choices')
	}
	return response.choices[0].content
}

// generate_content implements bounded non-streaming Gemini generateContent.
pub fn (client Client) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	options.validate()!
	llms.validate_messages(messages)!
	if messages.len > max_messages {
		return error('Google AI request exceeds the 1024-message limit')
	}
	validate_options(options)!
	model := if options.model.trim_space() == '' {
		client.model
	} else {
		options.model.trim_space()
	}
	validate_model(model)!
	request := make_request(messages, options)!
	body := json2.encode(request, json2.EncoderOptions{})
	if body.len > max_request_bytes {
		return error('Google AI request exceeds the 8 MiB size limit')
	}
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	response := client.http_client.do(mut ctx, httputil.Request{
		method:  .post
		url:     '${client.base_url}/models/${model}:generateContent'
		headers: {
			'x-goog-api-key': client.api_key
			'Content-Type':   'application/json'
			'Accept':         'application/json'
		}
		body:    body
	}) or {
		return error('Google AI generateContent request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Google AI generateContent request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_response_bytes {
		return error('Google AI response exceeds 16 MiB')
	}
	decoded := json2.decode[GenerateResponse](response.body, json2.DecoderOptions{}) or {
		return error('could not decode Google AI response: ${err.msg()}')
	}
	if decoded.candidates.len == 0 {
		return error('Google AI returned no candidates')
	}
	mut choices := []llms.Choice{cap: decoded.candidates.len}
	for candidate_index, candidate in decoded.candidates {
		mut text := []string{}
		mut choice_parts := []schema.ContentPart{}
		mut tool_calls := []schema.ToolCall{}
		for part_index, part in candidate.content.parts {
			if part.text != '' {
				text << part.text
				choice_parts << schema.ContentPart(schema.TextPart{
					text: part.text
				})
			}
			if function_call := part.function_call {
				if function_call.name.trim_space() == '' {
					return error('Google AI returned a function call with an empty name')
				}
				arguments := json2.encode(function_call.args, json2.EncoderOptions{})
				tool_call := schema.ToolCall{
					id:            'gemini-${candidate_index}-${part_index}'
					call_type:     'function'
					function_call: schema.FunctionCall{
						name:      function_call.name
						arguments: arguments
					}
				}
				tool_calls << tool_call
				choice_parts << schema.ContentPart(tool_call)
			}
		}
		choices << llms.Choice{
			content:     text.join('')
			stop_reason: candidate.finish_reason
			tool_calls:  tool_calls
			parts:       choice_parts
		}
	}
	return llms.Response{
		choices: choices
		usage:   llms.Usage{
			prompt_tokens:     decoded.usage_metadata.prompt_token_count
			completion_tokens: decoded.usage_metadata.candidates_token_count
			total_tokens:      decoded.usage_metadata.total_token_count
		}
	}
}

fn validate_options(options llms.CallOptions) ! {
	if options.candidate_count > max_candidates || options.n > max_candidates {
		return error('Google AI candidate count must not exceed 8')
	}
	if options.candidate_count > 0 && options.n > 0 && options.candidate_count != options.n {
		return error('Google AI candidate_count and n must agree when both are set')
	}
	if options.top_p < 0 || options.top_p > 1 || options.temperature < 0 || options.temperature > 2 {
		return error('Google AI top_p must be between zero and one and temperature between zero and two')
	}
	if options.top_k < 0 || options.min_length > 0 || options.max_length > 0
		|| options.repetition_penalty != 0 || options.frequency_penalty != 0
		|| options.presence_penalty != 0 || options.functions.len > 0 || options.function_call_behavior != ''
		|| options.web_search_options != none || options.provider_options.len > 0 {
		return error('Google AI requested option is unsupported by this client')
	}
	if options.response_mime_type !in ['', 'application/json'] {
		return error('Google AI response_mime_type only supports application/json')
	}
	for tool in options.tools {
		if tool.strict {
			return error('Google AI strict tool parameter mode is not supported')
		}
	}
	if choice := options.tool_choice {
		if options.tools.len == 0 {
			return error('Google AI tool_choice requires at least one tool definition')
		}
		if choice.name != '' && choice.name !in options.tools.map(it.name) {
			return error('Google AI named tool_choice must match a declared tool')
		}
		if choice.mode.to_lower() !in ['auto', 'none', 'any', 'required', 'function', 'tool'] {
			return error('Google AI tool_choice mode is not supported')
		}
	}
	if _ := options.streaming_func {
		return error('Google AI streaming is not supported by this bounded transport')
	}
	if _ := options.streaming_reasoning_func {
		return error('Google AI streaming is not supported by this bounded transport')
	}
}

fn make_request(messages []schema.Message, options llms.CallOptions) !map[string]json2.Any {
	mut contents := []json2.Any{}
	mut system_text := []string{}
	for message in messages {
		if message.role == .system {
			for part in message.parts {
				match part {
					schema.TextPart { system_text << part.text }
					else { return error('Google AI system messages support text parts only') }
				}
			}
			continue
		}
		role := match message.role {
			.human { 'user' }
			.ai { 'model' }
			.tool { 'user' }
			else {
				return error('Google AI currently supports user, model, and system messages only')
			}
		}
		mut parts := []json2.Any{}
		for part in message.parts {
			match part {
				schema.TextPart {
					parts << json2.Any({
						'text': json2.Any(part.text)
					})
				}
				schema.BinaryPart {
					if part.data.len == 0 || part.data.len > max_inline_image_bytes {
						return error('Google AI inline image must be non-empty and no larger than 5 MiB')
					}
					if !part.mime_type.to_lower().starts_with('image/') {
						return error('Google AI binary message parts must be images')
					}
					parts << json2.Any({
						'inlineData': json2.Any({
							'mimeType': json2.Any(part.mime_type)
							'data':     json2.Any(base64.encode(part.data))
						})
					})
				}
				schema.ToolCall {
					args := json2.decode[map[string]json2.Any](part.function_call.arguments,
						json2.DecoderOptions{}) or {
						return error('Google AI function call history must contain a JSON object')
					}
					parts << json2.Any({
						'functionCall': json2.Any({
							'name': json2.Any(part.function_call.name)
							'args': json2.Any(args)
						})
					})
				}
				schema.ToolResult {
					parts << json2.Any({
						'functionResponse': json2.Any({
							'name':     json2.Any(part.name)
							'response': json2.Any({
								'result': json2.Any(part.content)
							})
						})
					})
				}
				schema.ImageURLPart {
					return error('Google AI image URLs must be converted to bounded inline data first')
				}
				else { return error('Google AI message part is not supported') }
			}
		}
		contents << json2.Any({
			'role':  json2.Any(role)
			'parts': json2.Any(parts)
		})
	}
	if contents.len == 0 {
		return error('Google AI requires at least one non-system message')
	}
	mut request := map[string]json2.Any{
		'contents': json2.Any(contents)
	}
	if system_text.len > 0 {
		request['systemInstruction'] = json2.Any({
			'parts': json2.Any([json2.Any({
				'text': json2.Any(system_text.join('\n\n'))
			})])
		})
	}
	mut generation := map[string]json2.Any{}
	if options.max_tokens > 0 {
		generation['maxOutputTokens'] = json2.Any(options.max_tokens)
	}
	if options.temperature > 0 {
		generation['temperature'] = json2.Any(options.temperature)
	}
	if options.top_p > 0 {
		generation['topP'] = json2.Any(options.top_p)
	}
	if options.top_k > 0 {
		generation['topK'] = json2.Any(options.top_k)
	}
	if options.stop_words.len > 0 {
		mut stop_sequences := []json2.Any{}
		for stop_word in options.stop_words {
			stop_sequences << json2.Any(stop_word)
		}
		generation['stopSequences'] = json2.Any(stop_sequences)
	}
	candidate_count := if options.candidate_count > 0 {
		options.candidate_count
	} else {
		options.n
	}
	if candidate_count > 0 {
		generation['candidateCount'] = json2.Any(candidate_count)
	}
	if seed := options.seed {
		if seed < 0 {
			return error('Google AI seed must be non-negative')
		}
		generation['seed'] = json2.Any(seed)
	}
	if options.json_mode || options.response_mime_type == 'application/json' {
		generation['responseMimeType'] = json2.Any('application/json')
	}
	if generation.len > 0 {
		request['generationConfig'] = json2.Any(generation)
	}
	if options.tools.len > 0 {
		mut declarations := []json2.Any{cap: options.tools.len}
		for tool in options.tools {
			if tool.name.trim_space() == '' {
				return error('Google AI tool name must not be empty')
			}
			mut declaration := map[string]json2.Any{
				'name':       json2.Any(tool.name)
				'parameters': tool.parameters
			}
			if tool.description != '' {
				declaration['description'] = json2.Any(tool.description)
			}
			declarations << json2.Any(declaration)
		}
		request['tools'] = json2.Any([json2.Any({
			'functionDeclarations': json2.Any(declarations)
		})])
	}
	if tool_choice := options.tool_choice {
		mode := if tool_choice.name != '' {
			'ANY'
		} else {
			match tool_choice.mode.to_lower() {
				'none' { 'NONE' }
				'any', 'required', 'function', 'tool' { 'ANY' }
				else { 'AUTO' }
			}
		}
		mut function_calling_config := map[string]json2.Any{
			'mode': json2.Any(mode)
		}
		if tool_choice.name != '' {
			function_calling_config['allowedFunctionNames'] = json2.Any([json2.Any(tool_choice.name)])
		}
		request['toolConfig'] = json2.Any({
			'functionCallingConfig': json2.Any(function_calling_config)
		})
	}
	return request
}

fn validate_model(model string) ! {
	if model.trim_space() == '' || model.contains('/') || model.contains('?') || model.contains('#') {
		return error('Google AI model must be a single model identifier')
	}
}
