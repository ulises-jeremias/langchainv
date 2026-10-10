// Package openai implements OpenAI's embeddings API client.
module openai

import context
import json2
import ulises_jeremias.langchainv.embeddings
import ulises_jeremias.langchainv.httputil

const default_base_url = 'https://api.openai.com/v1'
const default_model = 'text-embedding-3-small'

struct embedding_request {
	model           string
	input           []string
	encoding_format string = 'float'
}

struct embedding_request_with_dimensions {
	model           string
	input           []string
	encoding_format string = 'float'
	dimensions      int
}

struct embedding_response {
	data []embedding_item
}

struct embedding_item {
	index     int
	embedding []f32
}

// Client creates embeddings through an injected bounded HTTP transport.
pub struct Client {
	api_key     string
	http_client httputil.HTTPClient
pub:
	base_url   string = default_base_url
	model      string = default_model
	dimensions ?int
}

// new_client configures the OpenAI embeddings API client.
pub fn new_client(api_key string, http_client httputil.HTTPClient) !Client {
	return new_client_with_options(api_key, http_client, Options{})
}

// new_default_client uses the bounded standard HTTP transport.
pub fn new_default_client(api_key string) !Client {
	return new_client(api_key, httputil.HTTPClient(httputil.new_default_client()))
}

// Options configures the endpoint, model and optional output dimensions.
pub struct Options {
pub:
	base_url   string = default_base_url
	model      string = default_model
	dimensions ?int
}

// new_client_with_options validates and creates an OpenAI embeddings client.
pub fn new_client_with_options(api_key string, http_client httputil.HTTPClient, options Options) !Client {
	if api_key.trim_space() == '' {
		return error('OpenAI API key must not be empty')
	}
	if options.base_url.trim_space() == '' || options.model.trim_space() == '' {
		return error('OpenAI base URL and model must not be empty')
	}
	if dimensions := options.dimensions {
		if dimensions <= 0 {
			return error('OpenAI embedding dimensions must be greater than zero')
		}
	}
	base_url := options.base_url.trim_space().trim_right('/')
	return Client{
		api_key:     api_key
		base_url:    base_url
		model:       options.model.trim_space()
		dimensions:  options.dimensions
		http_client: http_client
	}
}

// create_embedding implements embeddings.EmbedderClient.
pub fn (client Client) create_embedding(mut ctx context.Context, texts []string) ![][]f32 {
	if texts.len == 0 {
		return [][]f32{}
	}
	for text in texts {
		if text == '' {
			return error('OpenAI embedding input must not contain empty text')
		}
	}
	mut payload := ''
	if dimensions := client.dimensions {
		payload = json2.encode(embedding_request_with_dimensions{
			model:      client.model
			input:      texts.clone()
			dimensions: dimensions
		})
	} else {
		payload = json2.encode(embedding_request{
			model: client.model
			input: texts.clone()
		})
	}
	response := client.http_client.do(mut ctx, httputil.Request{
		method:  .post
		url:     '${client.base_url}/embeddings'
		headers: {
			'Authorization': 'Bearer ${client.api_key}'
			'Content-Type':  'application/json'
			'Accept':        'application/json'
		}
		body:    payload
	}) or {
		return error('OpenAI embeddings request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('OpenAI embeddings request returned HTTP ${response.status_code}')
	}
	if response.body.len > 16 * 1024 * 1024 {
		return error('OpenAI embeddings response exceeds 16 MiB')
	}
	decoded := json2.decode[embedding_response](response.body, json2.DecoderOptions{}) or {
		return error('could not decode OpenAI embeddings response: ${err.msg()}')
	}
	if decoded.data.len != texts.len {
		return error('OpenAI returned ${decoded.data.len} vectors for ${texts.len} texts')
	}
	mut vectors := [][]f32{len: texts.len}
	mut seen := []bool{len: texts.len, init: false}
	for item in decoded.data {
		if item.index < 0 || item.index >= texts.len {
			return error('OpenAI embedding response contains an invalid input index')
		}
		if seen[item.index] {
			return error('OpenAI embedding response contains a duplicate input index')
		}
		seen[item.index] = true
		vectors[item.index] = item.embedding.clone()
	}
	for index, vector in vectors {
		if !seen[index] {
			return error('OpenAI embedding response is missing an input index')
		}
		if vector.len == 0 {
			return error('OpenAI returned an empty embedding vector')
		}
	}
	return vectors
}

// embedder builds the common batching and preprocessing adapter for this client.
pub fn (client Client) embedder(options embeddings.Options) !embeddings.EmbedderImpl {
	return embeddings.new_embedder(client, options)
}

// default_embedder builds an adapter with upstream default batching behavior.
pub fn (client Client) default_embedder() !embeddings.EmbedderImpl {
	return embeddings.new_default_embedder(client)
}
