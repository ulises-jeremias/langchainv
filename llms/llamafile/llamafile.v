// Package llamafile adapts the current OpenAI-compatible llamafile server API.
module llamafile

import context
import net.urllib
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.openai
import ulises_jeremias.langchainv.schema

const default_base_url = 'http://127.0.0.1:8080/v1'
const default_model = 'LLaMA_CPP'
const default_api_key = 'no-key'
const max_base_url_bytes = 4096
const max_model_bytes = 512
const max_api_key_bytes = 16 * 1024

// Options configures the local server endpoint and default model.
pub struct Options {
pub:
	base_url string = default_base_url
	model    string = default_model
	api_key  string = default_api_key
}

// Client implements LangChainV model contracts using llamafile's current
// OpenAI-compatible Chat Completions endpoint.
pub struct Client {
	inner openai.Client
}

// new_client creates a llamafile client with an injected HTTP transport.
pub fn new_client(http_client httputil.HTTPClient, options Options) !Client {
	base_url := options.base_url.trim_space().trim_right('/')
	model := options.model.trim_space()
	api_key := options.api_key.trim_space()
	if base_url == '' || model == '' || api_key == '' {
		return error('llamafile base URL, model, and API key must not be empty')
	}
	if base_url.len > max_base_url_bytes || model.len > max_model_bytes
		|| api_key.len > max_api_key_bytes {
		return error('llamafile base URL, model, or API key exceeds its size limit')
	}
	validate_base_url(base_url)!
	return Client{
		inner: openai.new_client_with_options(api_key, http_client, openai.Options{
			base_url: base_url
			model:    model
		})!
	}
}

// new_default_client uses the loopback llamafile server and bounded transport.
pub fn new_default_client() !Client {
	return new_client(httputil.HTTPClient(httputil.new_default_client()), Options{})
}

// generate_content delegates bounded non-streaming generation and message
// conversion to the shared OpenAI-compatible implementation.
pub fn (client Client) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	return client.inner.generate_content(mut ctx, messages, options)
}

// complete wraps a prompt as a user message and returns the first choice.
pub fn (client Client) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	return client.inner.complete(mut ctx, prompt, options)
}

fn validate_base_url(base_url string) ! {
	httputil.validate_url(base_url, '') or {
		return error('llamafile base URL must be valid HTTP(S) without user information')
	}
	parsed := urllib.parse(base_url) or { return error('invalid llamafile base URL') }
	if parsed.scheme.to_lower() == 'https' {
		return
	}
	if parsed.scheme.to_lower() == 'http' && parsed.hostname().to_lower() in [
		'localhost',
		'127.0.0.1',
		'::1',
	] {
		return
	}
	return error('llamafile base URL must use HTTPS or loopback HTTP')
}
