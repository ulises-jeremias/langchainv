// Package mistral adapts the OpenAI-compatible Mistral chat completions API.
module mistral

import context
import json2
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.openai
import ulises_jeremias.langchainv.schema

const default_base_url = 'https://api.mistral.ai/v1'
const default_model = 'mistral-large-latest'

// Client implements Mistral chat completions through its OpenAI-compatible API.
pub struct Client {
	inner openai.Client
pub:
	base_url string = default_base_url
	model    string = default_model
}

// Options configures the Mistral endpoint and default model.
pub struct Options {
pub:
	base_url string = default_base_url
	model    string = default_model
}

struct MistralHTTPClient {
	inner httputil.HTTPClient
}

// new_client creates a Mistral client with its default endpoint and model.
pub fn new_client(api_key string, http_client httputil.HTTPClient) !Client {
	return new_client_with_options(api_key, http_client, Options{})
}

// new_default_client uses the shared bounded standard-library HTTP transport.
pub fn new_default_client(api_key string) !Client {
	return new_client(api_key, httputil.HTTPClient(httputil.new_default_client()))
}

// new_client_with_options validates credentials and builds an OpenAI-compatible adapter.
pub fn new_client_with_options(api_key string, http_client httputil.HTTPClient, options Options) !Client {
	if options.base_url.trim_space() == '' || options.model.trim_space() == '' {
		return error('Mistral base URL and model must not be empty')
	}
	base_url := options.base_url.trim_space().trim_right('/')
	model := options.model.trim_space()
	inner := openai.new_client_with_options(api_key, httputil.HTTPClient(MistralHTTPClient{
		inner: http_client
	}), openai.Options{
		base_url: base_url
		model:    model
	})!
	return Client{
		inner:    inner
		base_url: base_url
		model:    model
	}
}

// complete implements llms.CompletionModel by sending the prompt as a user turn.
pub fn (client Client) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	return client.inner.complete(mut ctx, prompt, options)
}

// generate_content delegates the compatible request/response contract to OpenAI
// and translates Mistral-specific token option names at the HTTP boundary.
pub fn (client Client) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	return client.inner.generate_content(mut ctx, messages, options)
}

fn (client MistralHTTPClient) do(mut ctx context.Context, request httputil.Request) !httputil.Response {
	if request.body != '' {
		mut payload := json2.decode[map[string]json2.Any](request.body, json2.DecoderOptions{}) or {
			return error('could not decode Mistral-compatible request')
		}
		if max_tokens := payload['max_completion_tokens'] {
			payload['max_tokens'] = max_tokens
			payload.delete('max_completion_tokens')
		}
		if seed := payload['seed'] {
			payload['random_seed'] = seed
			payload.delete('seed')
		}
		translated := httputil.Request{
			method:  request.method
			url:     request.url
			headers: request.headers
			body:    json2.encode(payload, json2.EncoderOptions{})
		}
		return client.inner.do(mut ctx, translated)
	}
	return client.inner.do(mut ctx, request)
}
