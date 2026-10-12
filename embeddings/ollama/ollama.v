// Package ollama implements Ollama's embeddings API client.
module ollama

import context
import json2
import math
import ulises_jeremias.langchainv.embeddings
import ulises_jeremias.langchainv.httputil

const default_base_url = 'http://127.0.0.1:11434'
const max_request_bytes = 8 * 1024 * 1024
const max_response_bytes = 16 * 1024 * 1024
const max_embedding_inputs = 1024

struct EmbeddingRequest {
	model string
	input []string
}

struct EmbeddingResponse {
	embeddings [][]f32
}

// Client creates embeddings through an injected bounded HTTP transport.
pub struct Client {
	http_client httputil.HTTPClient
pub:
	base_url string = default_base_url
	model    string
}

// Options configures the Ollama server and embedding model.
pub struct Options {
pub:
	base_url string = default_base_url
	model    string
}

// new_client configures an Ollama embeddings client.
pub fn new_client(http_client httputil.HTTPClient, options Options) !Client {
	if options.model.trim_space() == '' {
		return error('Ollama embedding model must not be empty')
	}
	if options.base_url.trim_space() == '' {
		return error('Ollama base URL must not be empty')
	}
	base_url := options.base_url.trim_space().trim_right('/')
	httputil.validate_url(base_url, '') or { return error('invalid Ollama base URL: ${err.msg()}') }
	return Client{
		http_client: http_client
		base_url:    base_url
		model:       options.model.trim_space()
	}
}

// new_default_client uses the bounded standard HTTP transport and localhost.
pub fn new_default_client(model string) !Client {
	return new_client(httputil.HTTPClient(httputil.new_default_client()), Options{
		model: model
	})
}

// create_embedding implements embeddings.EmbedderClient via /api/embed.
pub fn (client Client) create_embedding(mut ctx context.Context, texts []string) ![][]f32 {
	if texts.len == 0 {
		return [][]f32{}
	}
	if texts.len > max_embedding_inputs {
		return error('Ollama embedding request exceeds the 1024-input limit')
	}
	for text in texts {
		if text == '' {
			return error('Ollama embedding input must not contain empty text')
		}
	}
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	body := json2.encode(EmbeddingRequest{
		model: client.model
		input: texts.clone()
	}, json2.EncoderOptions{})
	if body.len > max_request_bytes {
		return error('Ollama embedding request exceeds the 8 MiB size limit')
	}
	response := client.http_client.do(mut ctx, httputil.Request{
		method:  .post
		url:     '${client.base_url}/api/embed'
		headers: {
			'Content-Type': 'application/json'
			'Accept':       'application/json'
		}
		body:    body
	}) or {
		return error('Ollama embeddings request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Ollama embeddings request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_response_bytes {
		return error('Ollama embeddings response exceeds 16 MiB')
	}
	decoded := json2.decode[EmbeddingResponse](response.body, json2.DecoderOptions{}) or {
		return error('could not decode Ollama embeddings response: ${err.msg()}')
	}
	if decoded.embeddings.len != texts.len {
		return error('Ollama returned ${decoded.embeddings.len} vectors for ${texts.len} texts')
	}
	mut dimension := -1
	for vector in decoded.embeddings {
		if vector.len == 0 {
			return error('Ollama returned an empty embedding vector')
		}
		if dimension < 0 {
			dimension = vector.len
		} else if vector.len != dimension {
			return error('Ollama returned embeddings with different dimensions')
		}
		for value in vector {
			if !math.is_finite(f64(value)) {
				return error('Ollama returned a non-finite embedding value')
			}
		}
	}
	return decoded.embeddings.map(it.clone())
}

// embedder builds the common batching and preprocessing adapter for this client.
pub fn (client Client) embedder(options embeddings.Options) !embeddings.EmbedderImpl {
	return embeddings.new_embedder(client, options)
}

// default_embedder builds an adapter with upstream default batching behavior.
pub fn (client Client) default_embedder() !embeddings.EmbedderImpl {
	return embeddings.new_default_embedder(client)
}
