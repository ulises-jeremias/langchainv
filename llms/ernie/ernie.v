// Package ernie adapts Baidu Qianfan's OpenAI-compatible Chat Completions API.
module ernie

import context
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.openai
import ulises_jeremias.langchainv.schema

const default_base_url = 'https://qianfan.baidubce.com/v2'
const default_model = 'ernie-4.5-turbo-128k'

// Client implements current Qianfan v2 chat using its Bearer API key.
pub struct Client {
	inner openai.Client
pub:
	base_url string = default_base_url
	model    string = default_model
}

// Options configures the Qianfan v2 endpoint and model.
pub struct Options {
pub:
	base_url string = default_base_url
	model    string = default_model
}

// new_client creates a client using Qianfan's default endpoint and model.
pub fn new_client(api_key string, http_client httputil.HTTPClient) !Client {
	return new_client_with_options(api_key, http_client, Options{})
}

// new_default_client uses the shared bounded standard-library HTTP transport.
pub fn new_default_client(api_key string) !Client {
	return new_client(api_key, httputil.HTTPClient(httputil.new_default_client()))
}

// new_client_with_options validates configuration and constructs the adapter.
pub fn new_client_with_options(api_key string, http_client httputil.HTTPClient, options Options) !Client {
	if options.base_url.trim_space() == '' || options.model.trim_space() == '' {
		return error('ERNIE base URL and model must not be empty')
	}
	base_url := options.base_url.trim_space().trim_right('/')
	model := options.model.trim_space()
	inner := openai.new_client_with_options(api_key, http_client, openai.Options{
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

// generate_content implements non-streaming Qianfan v2 chat completions.
pub fn (client Client) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	return client.inner.generate_content(mut ctx, messages, options)
}
