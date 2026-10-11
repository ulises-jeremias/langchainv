// Package watsonx implements text generation through the IBM watsonx.ai API.
module watsonx

import context
import json2
import ulises_jeremias.langchainv.callbacks
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

const default_base_url = 'https://us-south.ml.cloud.ibm.com'
const default_api_version = '2024-05-20'
const max_prompt_bytes = 256 * 1024
const max_request_bytes = 512 * 1024
const max_response_bytes = 4 * 1024 * 1024

struct GenerateResult {
	generated_text        string @[json: 'generated_text']
	generated_token_count int    @[json: 'generated_token_count']
	input_token_count     int    @[json: 'input_token_count']
	stop_reason           string @[json: 'stop_reason']
}

struct GenerateResponse {
	results []GenerateResult @[json: 'results']
}

// Options configures project, model, IAM bearer token, and regional endpoint.
pub struct Options {
pub:
	project_id   string
	model        string
	access_token string
	base_url     string = default_base_url
	api_version  string = default_api_version
}

// Client generates bounded text using the IBM watsonx.ai foundation model API.
pub struct Client {
	project_id   string
	access_token string
	base_url     string
	api_version  string
	http_client  httputil.HTTPClient
pub:
	model string
pub mut:
	callbacks ?callbacks.Handler
}

// new_client validates configuration and uses an injected HTTP transport.
pub fn new_client(options Options, http_client httputil.HTTPClient) !Client {
	project_id := options.project_id.trim_space()
	model := options.model.trim_space()
	token := options.access_token.trim_space()
	base_url := options.base_url.trim_space().trim_right('/')
	version := options.api_version.trim_space()
	if project_id == '' || project_id.len > 256 || project_id.contains('\n') || project_id.contains('\r')
		|| project_id.contains('\0') {
		return error('watsonx project ID must be non-empty and no longer than 256 bytes')
	}
	if model == '' || model.len > 256 || model.contains('\n') || model.contains('\r') || model.contains('\0') {
		return error('watsonx model ID must be a non-empty model identifier')
	}
	if token == '' || token.len > 16 * 1024 {
		return error('watsonx IAM access token must be non-empty and no longer than 16 KiB')
	}
	for character in token.bytes() {
		if !(character >= `a` && character <= `z`) && !(character >= `A` && character <= `Z`)
			&& !(character >= `0` && character <= `9`) && character !in [`-`, `.`, `_`, `~`, `+`,
			`/`, `=`] {
			return error('watsonx IAM access token contains an invalid character')
		}
	}
	if !valid_api_version(version) {
		return error('watsonx API version must be a date-like query value')
	}
	if base_url.contains('?') || base_url.contains('#') {
		return error('watsonx base URL must not include a query or fragment')
	}
	httputil.validate_url(base_url, 'https') or {
		return error('invalid watsonx base URL: ${err.msg()}')
	}
	return Client{
		project_id:   project_id
		access_token: token
		base_url:     base_url
		api_version:  version
		http_client:  http_client
		model:        model
	}
}

// new_default_client uses the shared bounded HTTP transport.
pub fn new_default_client(options Options) !Client {
	return new_client(options, httputil.HTTPClient(httputil.new_default_client()))
}

// complete implements llms.CompletionModel.
pub fn (mut client Client) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	response := client.generate_content(mut ctx, [schema.text_message(.human, prompt)], options)!
	if response.choices.len == 0 {
		return error('watsonx returned no completion choices')
	}
	return response.choices[0].content
}

// generate_content submits a single text prompt to watsonx.ai.
pub fn (mut client Client) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	options.validate()!
	llms.validate_messages(messages)!
	prompt := extract_prompt(messages, max_prompt_bytes)!
	validate_options(options)!
	if mut handler := client.callbacks {
		handler.llm_generate_content_start(mut ctx, messages)
	}
	model := if options.model.trim_space() == '' {
		client.model
	} else {
		options.model.trim_space()
	}
	if model == '' || model.len > 256 || model.contains('\n') || model.contains('\r') || model.contains('\0') {
		return error('watsonx model ID must be a non-empty model identifier')
	}
	request_body := make_request(client.project_id, model, prompt, options)
	if request_body.len > max_request_bytes {
		return error('watsonx request exceeds the 512 KiB limit')
	}
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	response := client.http_client.do(mut ctx, httputil.Request{
		method:  .post
		url:     '${client.base_url}/ml/v1-beta/generation/text?version=${client.api_version}'
		headers: {
			'Authorization': 'Bearer ${client.access_token}'
			'Content-Type':  'application/json'
			'Accept':        'application/json'
		}
		body:    request_body
	}) or {
		return error('watsonx generation request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('watsonx generation request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_response_bytes {
		return error('watsonx response exceeds 4 MiB')
	}
	decoded := json2.decode[GenerateResponse](response.body, json2.DecoderOptions{}) or {
		return error('could not decode watsonx generation response: ${err.msg()}')
	}
	if decoded.results.len == 0 {
		return error('watsonx returned no generation results')
	}
	result := decoded.results[0]
	if result.generated_text == '' {
		return error('watsonx returned an empty completion')
	}
	answer := llms.Response{
		choices: [llms.Choice{
			content:     result.generated_text
			stop_reason: result.stop_reason
		}]
		usage:   llms.Usage{
			prompt_tokens:     result.input_token_count
			completion_tokens: result.generated_token_count
			total_tokens:      result.input_token_count + result.generated_token_count
		}
	}
	if mut handler := client.callbacks {
		handler.llm_generate_content_end(mut ctx, answer)
	}
	return answer
}

fn extract_prompt(messages []schema.Message, limit int) !string {
	if messages.len != 1 || messages[0].role != .human || messages[0].parts.len != 1 {
		return error('watsonx accepts exactly one human text message')
	}
	part := messages[0].parts[0]
	prompt := match part {
		schema.TextPart { part.text }
		else { return error('watsonx accepts exactly one human text message') }
	}
	if prompt.trim_space() == '' || prompt.len > limit {
		return error('watsonx prompt must be non-empty and no larger than ${limit} bytes')
	}
	return prompt
}

fn validate_options(options llms.CallOptions) ! {
	if options.temperature < 0 || options.temperature > 2 || options.repetition_penalty < 0
		|| options.repetition_penalty > 2 {
		return error('watsonx temperature and repetition penalty are outside supported bounds')
	}
	if options.top_k < 0 {
		return error('watsonx top_k must not be negative')
	}
	if seed := options.seed {
		if seed < 0 {
			return error('watsonx seed must not be negative')
		}
	}
	if options.candidate_count > 1 || options.n > 1 || options.min_length != 0 || options.max_length != 0
		|| options.json_mode || options.tools.len > 0 || options.tool_choice != none || options.functions.len > 0
		|| options.function_call_behavior != '' || options.frequency_penalty != 0
		|| options.presence_penalty != 0 || options.streaming_func != none
		|| options.streaming_reasoning_func != none || options.web_search_options != none
		|| options.provider_options.len > 0 || options.metadata.len > 0 {
		return error('watsonx requested option is unsupported by this client')
	}
}

fn make_request(project_id string, model string, prompt string, options llms.CallOptions) string {
	mut payload := map[string]json2.Any{
		'input':      json2.Any(prompt)
		'model_id':   json2.Any(model)
		'project_id': json2.Any(project_id)
	}
	mut parameters := map[string]json2.Any{}
	if options.max_tokens > 0 {
		parameters['max_new_tokens'] = json2.Any(options.max_tokens)
	}
	if options.temperature > 0 {
		parameters['temperature'] = json2.Any(options.temperature)
	}
	if options.top_p > 0 {
		parameters['top_p'] = json2.Any(options.top_p)
	}
	if options.top_k > 0 {
		parameters['top_k'] = json2.Any(options.top_k)
	}
	if options.repetition_penalty > 0 {
		parameters['repetition_penalty'] = json2.Any(options.repetition_penalty)
	}
	if seed := options.seed {
		if seed >= 0 {
			parameters['random_seed'] = json2.Any(seed)
		}
	}
	if options.stop_words.len > 0 {
		mut stop_sequences := []json2.Any{}
		for word in options.stop_words {
			stop_sequences << json2.Any(word)
		}
		parameters['stop_sequences'] = json2.Any(stop_sequences)
	}
	if parameters.len > 0 {
		payload['parameters'] = json2.Any(parameters)
	}
	return json2.encode(payload, json2.EncoderOptions{})
}

fn valid_api_version(version string) bool {
	if version.len != 10 || version[4] != `-` || version[7] != `-` {
		return false
	}
	for index, character in version.bytes() {
		if index !in [4, 7] && (character < `0` || character > `9`) {
			return false
		}
	}
	return true
}
