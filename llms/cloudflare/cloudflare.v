// Package cloudflare adapts Cloudflare Workers AI's OpenAI-compatible chat and embedding APIs.
module cloudflare

import context
import json2
import ulises_jeremias.langchainv.callbacks
import ulises_jeremias.langchainv.embeddings
import ulises_jeremias.langchainv.embeddings.openai as openai_embeddings
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.openai
import ulises_jeremias.langchainv.schema

const default_base_url = 'https://api.cloudflare.com/client/v4/accounts'
const default_embedding_model = '@cf/baai/bge-base-en-v1.5'

// Client calls Workers AI chat completions and embeddings for one account.
pub struct Client {
	inner            openai.Client
	embedding_client EmbeddingClient
pub:
	base_url   string
	account_id string
	model      string
}

// Options configures the Workers AI account, endpoint, models, and request controls.
pub struct Options {
pub:
	base_url        string = default_base_url
	account_id      string
	model           string
	embedding_model string = default_embedding_model
	reject_if_busy  bool
	callbacks       ?callbacks.Handler
}

// EmbeddingClient calls the Workers AI OpenAI-compatible embeddings route.
pub struct EmbeddingClient {
	inner openai_embeddings.Client
pub:
	base_url   string
	account_id string
	model      string
}

// EmbeddingOptions configures a standalone Workers AI embedding client.
pub struct EmbeddingOptions {
pub:
	base_url   string = default_base_url
	account_id string
	model      string = default_embedding_model
}

struct CloudflareHTTPClient {
	inner          httputil.HTTPClient
	reject_if_busy bool
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
	if api_token.trim_space() == '' || options.model.trim_space() == '' || options.base_url.trim_space() == ''
		|| options.embedding_model.trim_space() == '' {
		return error('Cloudflare API token, chat and embedding models, and base URL must not be empty')
	}
	base_url := '${options.base_url.trim_space().trim_right('/')}/${account_id}/ai/v1'
	model := options.model.trim_space()
	embedding_model := options.embedding_model.trim_space()
	inner := openai.new_client_with_options(api_token, httputil.HTTPClient(CloudflareHTTPClient{
		inner:          http_client
		reject_if_busy: options.reject_if_busy
	}), openai.Options{
		base_url:  base_url
		model:     model
		callbacks: options.callbacks
	})!
	embedding_client := new_embedding_client_with_options(api_token, http_client, EmbeddingOptions{
		base_url:   options.base_url
		account_id: account_id
		model:      embedding_model
	})!
	return Client{
		inner:            inner
		embedding_client: embedding_client
		base_url:         base_url
		account_id:       account_id
		model:            model
	}
}

// new_embedding_client configures a standalone Workers AI embedding client.
pub fn new_embedding_client(api_token string, account_id string, model string,
	http_client httputil.HTTPClient) !EmbeddingClient {
	return new_embedding_client_with_options(api_token, http_client, EmbeddingOptions{
		account_id: account_id
		model:      model
	})
}

// new_default_embedding_client uses the default model and bounded HTTP transport.
pub fn new_default_embedding_client(api_token string, account_id string) !EmbeddingClient {
	return new_embedding_client(api_token, account_id, default_embedding_model,
		httputil.HTTPClient(httputil.new_default_client()))
}

// new_embedding_client_with_options validates credentials and endpoint settings.
pub fn new_embedding_client_with_options(api_token string, http_client httputil.HTTPClient,
	options EmbeddingOptions) !EmbeddingClient {
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
		return error('Cloudflare API token, embedding model, and base URL must not be empty')
	}
	base_url := '${options.base_url.trim_space().trim_right('/')}/${account_id}/ai/v1'
	model := options.model.trim_space()
	inner := openai_embeddings.new_client_with_options(api_token, httputil.HTTPClient(CloudflareHTTPClient{
		inner: http_client
	}), openai_embeddings.Options{
		base_url: base_url
		model:    model
	})!
	return EmbeddingClient{
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

// create_embedding implements embeddings.EmbedderClient with the configured
// Cloudflare Workers AI embedding model.
pub fn (client Client) create_embedding(mut ctx context.Context, texts []string) ![][]f32 {
	return client.embedding_client.create_embedding(mut ctx, texts)
}

// embedder builds the common batching and preprocessing adapter for this client.
pub fn (client Client) embedder(options embeddings.Options) !embeddings.EmbedderImpl {
	return embeddings.new_embedder(client, options)
}

// default_embedder builds an adapter with upstream default batching behavior.
pub fn (client Client) default_embedder() !embeddings.EmbedderImpl {
	return embeddings.new_default_embedder(client)
}

// create_embedding implements embeddings.EmbedderClient.
pub fn (client EmbeddingClient) create_embedding(mut ctx context.Context, texts []string) ![][]f32 {
	return client.inner.create_embedding(mut ctx, texts) or {
		return error(err.msg().replace('OpenAI', 'Cloudflare Workers AI'))
	}
}

// embedder builds the common batching and preprocessing adapter for this client.
pub fn (client EmbeddingClient) embedder(options embeddings.Options) !embeddings.EmbedderImpl {
	return embeddings.new_embedder(client, options)
}

// default_embedder builds an adapter with upstream default batching behavior.
pub fn (client EmbeddingClient) default_embedder() !embeddings.EmbedderImpl {
	return embeddings.new_default_embedder(client)
}

fn (client CloudflareHTTPClient) do(mut ctx context.Context, request httputil.Request) !httputil.Response {
	if request.body != '' {
		translated := httputil.Request{
			method:  request.method
			url:     request.url
			headers: request.headers
			body:    translate_cloudflare_payload(request.body, client.reject_if_busy)!
		}
		return client.inner.do(mut ctx, translated)
	}
	return client.inner.do(mut ctx, request)
}

fn (client CloudflareHTTPClient) do_stream(mut ctx context.Context, request httputil.Request, handler httputil.StreamHandler) !httputil.Response {
	if client.inner !is httputil.StreamingHTTPClient {
		return error('configured Cloudflare HTTP transport does not support streaming responses')
	}
	stream_client := client.inner as httputil.StreamingHTTPClient
	if request.body == '' {
		return stream_client.do_stream(mut ctx, request, handler)
	}
	return stream_client.do_stream(mut ctx, httputil.Request{
		method:  request.method
		url:     request.url
		headers: request.headers
		body:    translate_cloudflare_payload(request.body, false)!
	}, handler)
}

fn translate_cloudflare_payload(body string, reject_if_busy bool) !string {
	mut payload := json2.decode[map[string]json2.Any](body, json2.DecoderOptions{}) or {
		return error('could not decode Cloudflare request')
	}
	if max_tokens := payload['max_completion_tokens'] {
		payload['max_tokens'] = max_tokens
		payload.delete('max_completion_tokens')
	}
	if reject_if_busy {
		payload['options'] = json2.Any({
			'rejectIfBusy': json2.Any(true)
		})
	}
	return json2.encode(payload, json2.EncoderOptions{})
}
