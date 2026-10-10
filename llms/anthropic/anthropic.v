// Package anthropic implements bounded non-streaming Anthropic Messages.
module anthropic

import context
import encoding.base64
import json2
import net.urllib
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

const default_base_url = 'https://api.anthropic.com/v1'
const default_model = 'claude-sonnet-4-6'
const default_max_tokens = 1024
const max_response_bytes = 16 * 1024 * 1024
const max_inline_image_bytes = 5 * 1024 * 1024

// Client implements Anthropic Messages over the bounded injectable transport.
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

struct MessagesResponse {
	content     []ContentBlock
	usage       Usage
	stop_reason string
}

struct ContentBlock {
	block_type string @[json: 'type']
	text       string
	id         string
	name       string
	input      json2.Any
}

struct Usage {
	input_tokens  int
	output_tokens int
}

// new_client constructs a client with default endpoint and model.
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
		return error('Anthropic API key must not be empty')
	}
	if options.base_url.trim_space() == '' || options.model.trim_space() == '' {
		return error('Anthropic base URL and model must not be empty')
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
		return error('Anthropic returned no completion choices')
	}
	return response.choices[0].content
}

// generate_content implements non-streaming Anthropic Messages.
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
	body := json2.encode(request, json2.EncoderOptions{})
	response := client.http_client.do(mut ctx, httputil.Request{
		method:  .post
		url:     '${client.base_url}/messages'
		headers: {
			'x-api-key':         client.api_key
			'anthropic-version': '2023-06-01'
			'Content-Type':      'application/json'
			'Accept':            'application/json'
		}
		body:    body
	}) or {
		return error('Anthropic message request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Anthropic message request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_response_bytes {
		return error('Anthropic message response exceeds 16 MiB')
	}
	decoded := json2.decode[MessagesResponse](response.body, json2.DecoderOptions{}) or {
		return error('could not decode Anthropic message response: ${err.msg()}')
	}
	choice := parse_choice(decoded)!
	return llms.Response{
		choices: [choice]
		usage:   llms.Usage{
			prompt_tokens:     decoded.usage.input_tokens
			completion_tokens: decoded.usage.output_tokens
			total_tokens:      decoded.usage.input_tokens + decoded.usage.output_tokens
		}
	}
}

fn validate_options(options llms.CallOptions) ! {
	if options.n > 1 || options.candidate_count > 1 {
		return error('Anthropic Messages returns exactly one candidate')
	}
	if options.min_length != 0 || options.max_length != 0 || options.seed != none
		|| options.repetition_penalty != 0 || options.frequency_penalty != 0
		|| options.presence_penalty != 0 || options.json_mode || options.response_mime_type != '' {
		return error('Anthropic Messages does not support one or more requested generation options')
	}
	if options.top_k < 0 || options.temperature < 0 || options.temperature > 1 {
		return error('Anthropic top_k must be non-negative and temperature must be between zero and one')
	}
	if options.provider_options.len > 0 || options.functions.len > 0 || options.web_search_options != none {
		return error('Anthropic provider_options, legacy functions, and web search options are not supported')
	}
	if options.tool_choice != none && options.tools.len == 0 {
		return error('Anthropic tool_choice requires at least one tool definition')
	}
	if _ := options.streaming_func {
		return error('Anthropic Messages streaming is not supported by this bounded transport')
	}
	if _ := options.streaming_reasoning_func {
		return error('Anthropic Messages streaming is not supported by this bounded transport')
	}
}

fn make_request(model string, messages []schema.Message, options llms.CallOptions) !map[string]json2.Any {
	mut wire_messages := []json2.Any{}
	mut system_prompts := []string{}
	for message in messages {
		if message.role == .system {
			for part in message.parts {
				match part {
					schema.TextPart {
						system_prompts << part.text
					}
					else {
						return error('Anthropic system messages support text parts only')
					}
				}
			}
			continue
		}
		wire_messages << json2.Any(convert_message(message)!)
	}
	if wire_messages.len == 0 {
		return error('Anthropic Messages requires at least one non-system message')
	}
	max_tokens := if options.max_tokens > 0 { options.max_tokens } else { default_max_tokens }
	mut request := map[string]json2.Any{
		'model':      json2.Any(model)
		'max_tokens': json2.Any(max_tokens)
		'messages':   json2.Any(wire_messages)
	}
	if system_prompts.len > 0 {
		request['system'] = json2.Any(system_prompts.join('\n\n'))
	}
	if options.temperature != 0 {
		request['temperature'] = json2.Any(options.temperature)
	}
	if options.top_p != 0 {
		request['top_p'] = json2.Any(options.top_p)
	}
	if options.top_k > 0 {
		request['top_k'] = json2.Any(options.top_k)
	}
	if options.stop_words.len > 0 {
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
				return error('Anthropic Messages does not support strict tool definitions')
			}
			mut tool := map[string]json2.Any{
				'name':         json2.Any(definition.name)
				'input_schema': definition.parameters
			}
			if definition.description != '' {
				tool['description'] = json2.Any(definition.description)
			}
			tools << json2.Any(tool)
		}
		request['tools'] = json2.Any(tools)
	}
	if tool_choice := options.tool_choice {
		request['tool_choice'] = json2.Any(convert_tool_choice(tool_choice)!)
	}
	return request
}

fn convert_tool_choice(choice schema.ToolChoice) !map[string]json2.Any {
	match choice.mode.to_lower() {
		'auto' {
			return {
				'type': json2.Any('auto')
			}
		}
		'any', 'required' {
			return {
				'type': json2.Any('any')
			}
		}
		'tool', 'function' {
			if choice.name.trim_space() == '' {
				return error('Anthropic named tool choice requires a tool name')
			}
			return {
				'type': json2.Any('tool')
				'name': json2.Any(choice.name)
			}
		}
		else {
			return error('unsupported Anthropic tool choice `${choice.mode}`')
		}
	}
}

fn convert_message(message schema.Message) !map[string]json2.Any {
	role := match message.role {
		.human, .generic, .tool { 'user' }
		.ai { 'assistant' }
		.system { return error('Anthropic system messages must be extracted before conversion') }
	}
	mut content := []json2.Any{}
	for part in message.parts {
		match part {
			schema.TextPart {
				content << json2.Any({
					'type': json2.Any('text')
					'text': json2.Any(part.text)
				})
			}
			schema.ToolCall {
				if message.role != .ai {
					return error('Anthropic tool calls require an assistant-role message')
				}
				tool_arguments := json2.decode[json2.Any](part.function_call.arguments, json2.DecoderOptions{}) or {
					return error('Anthropic tool call arguments must be valid JSON: ${err.msg()}')
				}
				content << json2.Any({
					'type':  json2.Any('tool_use')
					'id':    json2.Any(part.id)
					'name':  json2.Any(part.function_call.name)
					'input': tool_arguments
				})
			}
			schema.ToolResult {
				if message.role != .tool {
					return error('Anthropic tool results require a tool-role message')
				}
				content << json2.Any({
					'type':        json2.Any('tool_result')
					'tool_use_id': json2.Any(part.call_id)
					'content':     json2.Any(part.content)
				})
			}
			schema.ImageURLPart {
				if part.detail != '' {
					return error('Anthropic image detail hints are not supported')
				}
				parsed_url := urllib.parse(part.url) or {
					return error('Anthropic image URL is invalid')
				}
				if parsed_url.scheme.to_lower() != 'https' || parsed_url.host == '' || part.url.len > 8192 {
					return error('Anthropic image URL must be HTTPS, include a host, and be at most 8192 bytes')
				}
				if _ := parsed_url.user {
					return error('Anthropic image URL user information is not allowed')
				}
				content << json2.Any({
					'type':   json2.Any('image')
					'source': json2.Any({
						'type': json2.Any('url')
						'url':  json2.Any(part.url)
					})
				})
			}
			schema.BinaryPart {
				if part.mime_type !in ['image/jpeg', 'image/png', 'image/gif', 'image/webp'] {
					return error('Anthropic binary image MIME type is unsupported')
				}
				if part.data.len == 0 || part.data.len > max_inline_image_bytes {
					return error('Anthropic inline image must be between 1 byte and 5 MiB')
				}
				content << json2.Any({
					'type':   json2.Any('image')
					'source': json2.Any({
						'type':       json2.Any('base64')
						'media_type': json2.Any(part.mime_type)
						'data':       json2.Any(base64.encode(part.data))
					})
				})
			}
			schema.ThinkingPart, schema.RedactedThinkingPart {
				return error('Anthropic reasoning message replay is not supported yet')
			}
		}
	}
	if content.len == 0 {
		return error('Anthropic message has no supported content')
	}
	return {
		'role':    json2.Any(role)
		'content': json2.Any(content)
	}
}

fn parse_choice(response MessagesResponse) !llms.Choice {
	mut text_parts := []string{}
	mut tool_calls := []schema.ToolCall{}
	mut parts := []schema.ContentPart{}
	for block in response.content {
		match block.block_type {
			'text' {
				text_parts << block.text
				parts << schema.ContentPart(schema.TextPart{
					text: block.text
				})
			}
			'tool_use' {
				if block.id.trim_space() == '' || block.name.trim_space() == '' {
					return error('Anthropic returned a tool call without an id or name')
				}
				call := schema.ToolCall{
					id:            block.id
					call_type:     'tool_use'
					function_call: schema.FunctionCall{
						name:      block.name
						arguments: json2.encode(block.input, json2.EncoderOptions{})
					}
				}
				tool_calls << call
				parts << schema.ContentPart(call)
			}
			else {
				return error('Anthropic returned unsupported content block `${block.block_type}`')
			}
		}
	}
	if text_parts.len == 0 && tool_calls.len == 0 {
		return error('Anthropic returned no text or tool-use content')
	}
	return llms.Choice{
		content:     text_parts.join('')
		stop_reason: response.stop_reason
		tool_calls:  tool_calls
		parts:       parts
	}
}
