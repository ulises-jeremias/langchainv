// Package mistral implements Mistral's bounded embeddings API client.
module mistral

import context
import json2
import math
import ulises_jeremias.langchainv.embeddings
import ulises_jeremias.langchainv.httputil

const default_base_url = 'https://api.mistral.ai/v1'
const default_model = 'mistral-embed'
const max_embedding_inputs = 512
const max_input_bytes = 1024 * 1024
const max_request_bytes = 8 * 1024 * 1024
const max_response_bytes = 16 * 1024 * 1024

struct EmbeddingResponse {
	data []EmbeddingItem
}

struct EmbeddingItem {
	index     int
	embedding []f32
}

// Client creates text embeddings through Mistral's /v1/embeddings endpoint.
pub struct Client {
	api_key     string
	http_client httputil.HTTPClient
pub:
	base_url         string = default_base_url
	model            string = default_model
	output_dimension ?int
}

// Options configures the Mistral endpoint, model, and optional output dimension.
pub struct Options {
pub:
	base_url         string = default_base_url
	model            string = default_model
	output_dimension ?int
}

// new_client creates a Mistral embeddings client with default endpoint and model.
pub fn new_client(api_key string, http_client httputil.HTTPClient) !Client {
	return new_client_with_options(api_key, http_client, Options{})
}

// new_default_client uses the bounded standard-library HTTP transport.
pub fn new_default_client(api_key string) !Client {
	return new_client(api_key, httputil.HTTPClient(httputil.new_default_client()))
}

// new_client_with_options validates and creates a Mistral embeddings client.
pub fn new_client_with_options(api_key string, http_client httputil.HTTPClient, options Options) !Client {
	if api_key.trim_space() == '' {
		return error('Mistral API key must not be empty')
	}
	if options.base_url.trim_space() == '' || options.model.trim_space() == '' {
		return error('Mistral base URL and embedding model must not be empty')
	}
	if dimension := options.output_dimension {
		if dimension <= 0 || dimension > 4096 {
			return error('Mistral output dimension must be between 1 and 4096')
		}
	}
	base_url := options.base_url.trim_space().trim_right('/')
	httputil.validate_url(base_url, 'https') or {
		return error('invalid Mistral base URL: ${err.msg()}')
	}
	return Client{
		api_key:          api_key.trim_space()
		http_client:      http_client
		base_url:         base_url
		model:            options.model.trim_space()
		output_dimension: options.output_dimension
	}
}

// create_embedding implements embeddings.EmbedderClient.
pub fn (client Client) create_embedding(mut ctx context.Context, texts []string) ![][]f32 {
	if texts.len == 0 {
		return [][]f32{}
	}
	if texts.len > max_embedding_inputs {
		return error('Mistral embedding request exceeds the 512-input limit')
	}
	mut input_bytes := 0
	for text in texts {
		if text == '' {
			return error('Mistral embedding input must not contain empty text')
		}
		input_bytes += text.len
		if input_bytes > max_input_bytes {
			return error('Mistral embedding input exceeds the 1 MiB aggregate limit')
		}
	}
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	mut input := []json2.Any{cap: texts.len}
	for text in texts {
		input << json2.Any(text)
	}
	mut payload := map[string]json2.Any{
		'model':           json2.Any(client.model)
		'input':           json2.Any(input)
		'encoding_format': json2.Any('float')
	}
	if dimension := client.output_dimension {
		payload['output_dimension'] = json2.Any(dimension)
	}
	body := json2.encode(payload, json2.EncoderOptions{})
	if body.len > max_request_bytes {
		return error('Mistral embedding request exceeds the 8 MiB size limit')
	}
	response := client.http_client.do(mut ctx, httputil.Request{
		method:  .post
		url:     '${client.base_url}/embeddings'
		headers: {
			'Authorization': 'Bearer ${client.api_key}'
			'Content-Type':  'application/json'
			'Accept':        'application/json'
		}
		body:    body
	}) or {
		return error('Mistral embeddings request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Mistral embeddings request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_response_bytes {
		return error('Mistral embeddings response exceeds 16 MiB')
	}
	decoded := json2.decode[EmbeddingResponse](response.body, json2.DecoderOptions{}) or {
		return error('could not decode Mistral embeddings response: ${err.msg()}')
	}
	if decoded.data.len != texts.len {
		return error('Mistral returned ${decoded.data.len} vectors for ${texts.len} texts')
	}
	mut vectors := [][]f32{len: texts.len}
	mut seen := []bool{len: texts.len}
	mut dimension := -1
	for item in decoded.data {
		if item.index < 0 || item.index >= texts.len {
			return error('Mistral returned an out-of-range input index')
		}
		if seen[item.index] {
			return error('Mistral returned a duplicate input index')
		}
		if item.embedding.len == 0 {
			return error('Mistral returned an empty embedding vector')
		}
		if dimension < 0 {
			dimension = item.embedding.len
		} else if item.embedding.len != dimension {
			return error('Mistral returned embeddings with different dimensions')
		}
		for value in item.embedding {
			if !math.is_finite(f64(value)) {
				return error('Mistral returned a non-finite embedding value')
			}
		}
		vectors[item.index] = item.embedding.clone()
		seen[item.index] = true
	}
	for index, found in seen {
		if !found {
			return error('Mistral omitted input index ${index}')
		}
	}
	if expected_dimension := client.output_dimension {
		for vector in vectors {
			if vector.len != expected_dimension {
				return error('Mistral returned a vector with ${vector.len} values; expected ${expected_dimension}')
			}
		}
	}
	return vectors
}

// embedder builds the common batching and preprocessing adapter for this client.
pub fn (client Client) embedder(options embeddings.Options) !embeddings.EmbedderImpl {
	mut bounded_options := options
	if bounded_options.batch_size == 512 {
		bounded_options.batch_size = max_embedding_inputs
	} else if bounded_options.batch_size > max_embedding_inputs {
		return error('Mistral embedder batch size must not exceed 512')
	}
	return embeddings.new_embedder(client, bounded_options)
}

// default_embedder builds an adapter with upstream default batching behavior.
pub fn (client Client) default_embedder() !embeddings.EmbedderImpl {
	return embeddings.new_embedder(client, embeddings.Options{
		batch_size: max_embedding_inputs
	})
}
