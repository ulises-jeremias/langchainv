// Package vertex implements Google Vertex AI Gemini generation over REST.
module vertex

import context
import ulises_jeremias.langchainv.callbacks
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.googleai
import ulises_jeremias.langchainv.schema

const default_endpoint = 'https://aiplatform.googleapis.com'
const default_location = 'us-central1'
const default_model = 'gemini-2.5-flash'
const google_request_prefix = 'https://generativelanguage.googleapis.com/v1beta/models/'

// Options configures an explicitly authenticated Vertex AI endpoint.
pub struct Options {
pub:
	project      string
	location     string = default_location
	model        string = default_model
	access_token string
	endpoint     string = default_endpoint
}

// Client generates content through Vertex AI's Gemini publisher models API.
pub struct Client {
	inner googleai.Client
pub:
	project  string
	location string
	model    string
pub mut:
	callbacks ?callbacks.Handler
}

// new_client creates a client using an explicitly supplied OAuth access token.
// Tokens are not refreshed by this adapter; callers must supply a valid token.
pub fn new_client(options Options, http_client httputil.HTTPClient) !Client {
	project := options.project.trim_space()
	location := options.location.trim_space()
	model := options.model.trim_space()
	token := options.access_token.trim_space()
	endpoint := options.endpoint.trim_space().trim_right('/')
	if !valid_resource_component(project) {
		return error('Vertex AI project must be a non-empty project identifier')
	}
	if !valid_resource_component(location) {
		return error('Vertex AI location must be a non-empty location identifier')
	}
	if !valid_resource_component(model) {
		return error('Vertex AI model must be a non-empty model identifier')
	}
	if token == '' || token.len > 16 * 1024 {
		return error('Vertex AI OAuth access token must be between 1 byte and 16 KiB')
	}
	for character in token.bytes() {
		if !(character >= `a` && character <= `z`) && !(character >= `A` && character <= `Z`)
			&& !(character >= `0` && character <= `9`) && character !in [`-`, `.`, `_`, `~`, `+`,
			`/`, `=`] {
			return error('Vertex AI OAuth access token contains an invalid character')
		}
	}
	if endpoint.contains('?') || endpoint.contains('#') {
		return error('Vertex AI endpoint must not include a query or fragment')
	}
	httputil.validate_url(endpoint, 'https') or {
		return error('invalid Vertex AI endpoint: ${err.msg()}')
	}
	transport := VertexTransport{
		inner:        http_client
		endpoint:     endpoint
		project:      project
		location:     location
		access_token: token
	}
	inner := googleai.new_client_with_options(token, httputil.HTTPClient(transport), googleai.Options{
		base_url: 'https://generativelanguage.googleapis.com/v1beta'
		model:    model
	})!
	return Client{
		inner:    inner
		project:  project
		location: location
		model:    model
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
		return error('Vertex AI returned no completion choices')
	}
	return response.choices[0].content
}

// generate_content implements bounded Vertex AI Gemini generation.
pub fn (mut client Client) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	if mut handler := client.callbacks {
		handler.llm_generate_content_start(mut ctx, messages)
	}
	response := client.inner.generate_content(mut ctx, messages, options)!
	if mut handler := client.callbacks {
		handler.llm_generate_content_end(mut ctx, response)
	}
	return response
}

fn valid_resource_component(value string) bool {
	if value == '' || value.len > 128 {
		return false
	}
	for character in value.bytes() {
		if !(character >= `a` && character <= `z`) && !(character >= `A` && character <= `Z`)
			&& !(character >= `0` && character <= `9`) && character !in [`-`, `_`, `.`] {
			return false
		}
	}
	return value !in ['.', '..']
}

struct VertexTransport {
	inner        httputil.HTTPClient
	endpoint     string
	project      string
	location     string
	access_token string
}

fn (transport VertexTransport) do(mut ctx context.Context, request httputil.Request) !httputil.Response {
	return transport.inner.do(mut ctx, transport.vertex_request(request)!)
}

fn (transport VertexTransport) do_stream(mut ctx context.Context, request httputil.Request, handler httputil.StreamHandler) !httputil.Response {
	if transport.inner !is httputil.StreamingHTTPClient {
		return error('configured Vertex AI HTTP transport does not support streaming responses')
	}
	mut streaming := transport.inner as httputil.StreamingHTTPClient
	return streaming.do_stream(mut ctx, transport.vertex_request(request)!, handler)
}

fn (transport VertexTransport) vertex_request(request httputil.Request) !httputil.Request {
	if !request.url.starts_with(google_request_prefix) {
		return error('unexpected Google AI request path for Vertex AI transport')
	}
	mut model_and_action := request.url[google_request_prefix.len..]
	mut query := ''
	if query_index := model_and_action.index('?') {
		query = model_and_action[query_index..]
		model_and_action = model_and_action[..query_index]
	}
	action_separator := model_and_action.index(':') or {
		return error('invalid Vertex AI model request path')
	}
	model := model_and_action[..action_separator]
	action := model_and_action[action_separator + 1..]
	if !valid_resource_component(model) || action !in ['generateContent', 'streamGenerateContent']
		|| query !in ['', '?alt=sse'] || (query != '' && action != 'streamGenerateContent') {
		return error('invalid Vertex AI model request path')
	}
	mut headers := map[string]string{}
	for key, value in request.headers {
		if key.to_lower() != 'x-goog-api-key' {
			headers[key] = value
		}
	}
	headers['Authorization'] = 'Bearer ${transport.access_token}'
	return httputil.Request{
		method:  request.method
		url:     '${transport.endpoint}/v1/projects/${transport.project}/locations/${transport.location}/publishers/google/models/${model_and_action}${query}'
		headers: headers
		body:    request.body
	}
}
