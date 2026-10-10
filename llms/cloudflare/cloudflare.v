// Package cloudflare adapts Cloudflare Workers AI's OpenAI-compatible chat API.
module cloudflare

import context
import json2
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.openai
import ulises_jeremias.langchainv.schema

const default_base_url = 'https://api.cloudflare.com/client/v4/accounts'

// Client calls Workers AI chat completions for a configured account and model.
pub struct Client {
	inner openai.Client
pub:
	base_url   string
	account_id string
	model      string
}

// Options configures Workers AI's account, API base, and model.
pub struct Options {
pub:
	base_url   string = default_base_url
	account_id string
	model      string
}

struct CloudflareHTTPClient {
	inner httputil.HTTPClient
}

// new_client creates a Workers AI client for an account and model.
pub fn new_client(api_token string, account_id string, model string, http_client httputil.HTTPClient) !Client {
	return new_client_with_options(api_token, http_client, Options{
		account_id: account_id
		model:      model
	})
}

// new_default_client uses the shared bounded HTTP transport.
pub fn new_default_client(api_token string, account_id string, model string) !Client {
	return new_client(api_token, account_id, model, httputil.HTTPClient(httputil.new_default_client()))
}

// new_client_with_options validates the token, account ID, and model.
pub fn new_client_with_options(api_token string, http_client httputil.HTTPClient, options Options) !Client {
	account_id := options.account_id.trim_space().to_lower()
	if account_id.len != 32 {
		return error('Cloudflare account ID must contain exactly 32 hexadecimal characters')
	}
	for ch in account_id {
		if !((ch >= `0` && ch <= `9`) || (ch >= `a` && ch <= `f`)) {
			return error('Cloudflare account ID must contain exactly 32 hexadecimal characters')
		}
	}
	if api_token.trim_space() == '' || options.model.trim_space() == '' || options.base_url.trim_space() == '' {
		return error('Cloudflare API token, model, and base URL must not be empty')
	}
	base_url := '${options.base_url.trim_space().trim_right('/')}/${account_id}/ai/v1'
	model := options.model.trim_space()
	inner := openai.new_client_with_options(api_token, httputil.HTTPClient(CloudflareHTTPClient{
		inner: http_client
	}), openai.Options{
		base_url: base_url
		model:    model
	})!
	return Client{
		inner:      inner
		base_url:   base_url
		account_id: account_id
		model:      model
	}
}

// complete implements llms.CompletionModel by sending the prompt as a user turn.
pub fn (client Client) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	return client.inner.complete(mut ctx, prompt, options)
}

// generate_content delegates the OpenAI-compatible chat contract to Workers AI.
pub fn (client Client) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	return client.inner.generate_content(mut ctx, messages, options)
}

fn (client CloudflareHTTPClient) do(mut ctx context.Context, request httputil.Request) !httputil.Response {
	if request.body != '' {
		mut payload := json2.decode[map[string]json2.Any](request.body, json2.DecoderOptions{}) or {
			return error('could not decode Cloudflare chat request')
		}
		if max_tokens := payload['max_completion_tokens'] {
			payload['max_tokens'] = max_tokens
			payload.delete('max_completion_tokens')
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
