// Package voyageai implements Voyage AI's bounded text embeddings API client.
module voyageai

import context
import json2
import math
import ulises_jeremias.langchainv.embeddings
import ulises_jeremias.langchainv.httputil

const default_base_url = 'https://api.voyageai.com/v1'
const default_model = 'voyage-2'
const max_embedding_inputs = 1000
const max_input_bytes = 4 * 1024 * 1024
const max_request_bytes = 8 * 1024 * 1024
const max_response_bytes = 16 * 1024 * 1024

struct EmbeddingResponse {
	data []EmbeddingData
}

struct EmbeddingData {
	embedding []f32
}

// Client creates Voyage embeddings through /v1/embeddings.
pub struct Client {
	api_key     string
	http_client httputil.HTTPClient
pub:
	base_url string = default_base_url
	model    string = default_model
}

// Options configures the Voyage endpoint and model.
pub struct Options {
pub:
	base_url string = default_base_url
	model    string = default_model
}

// Embedder adapts Voyage document/query modes to the common Embedder contract.
pub struct Embedder {
	client         Client
	strip_newlines bool
	batch_size     int
}

// new_client configures a Voyage client with its default endpoint and model.
pub fn new_client(api_key string, http_client httputil.HTTPClient) !Client {
	return new_client_with_options(api_key, http_client, Options{})
}

// new_default_client uses the bounded shared standard-library HTTP transport.
pub fn new_default_client(api_key string) !Client {
	return new_client(api_key, httputil.HTTPClient(httputil.new_default_client()))
}

// new_client_with_options validates the API key, endpoint and model.
pub fn new_client_with_options(api_key string, http_client httputil.HTTPClient, options Options) !Client {
	if api_key.trim_space() == '' {
		return error('Voyage API key must not be empty')
	}
	if options.base_url.trim_space() == '' || options.model.trim_space() == '' {
		return error('Voyage base URL and embedding model must not be empty')
	}
	base_url := options.base_url.trim_space().trim_right('/')
	httputil.validate_url(base_url, 'https') or { return error('invalid Voyage base URL: ${err.msg()}') }
	return Client{
		api_key:     api_key
		http_client: http_client
		base_url:    base_url
		model:       options.model.trim_space()
	}
}

// create_embedding implements embeddings.EmbedderClient for document inputs.
pub fn (client Client) create_embedding(mut ctx context.Context, texts []string) ![][]f32 {
	return client.create_embedding_with_type(mut ctx, texts, 'document')
}

// create_query_embedding creates one query vector with Voyage's query mode.
pub fn (client Client) create_query_embedding(mut ctx context.Context, text string) ![]f32 {
	if text == '' {
		return error('Voyage embedding input must not be empty')
	}
	vectors := client.create_embedding_with_type(mut ctx, [text], 'query')!
	if vectors.len != 1 {
		return error('Voyage returned ${vectors.len} vectors for one query')
	}
	return vectors[0].clone()
}

fn (client Client) create_embedding_with_type(mut ctx context.Context, texts []string, input_type string) ![][]f32 {
	if texts.len == 0 {
		return [][]f32{}
	}
	if texts.len > max_embedding_inputs {
		return error('Voyage embedding request exceeds the 1000-input limit')
	}
	mut input_bytes := 0
	mut input := []json2.Any{cap: texts.len}
	for text in texts {
		if text == '' {
			return error('Voyage embedding input must not be empty')
		}
		input_bytes += text.len
		if input_bytes > max_input_bytes {
			return error('Voyage embedding input exceeds the 4 MiB aggregate limit')
		}
		input << json2.Any(text)
	}
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	body := json2.encode({
		'model':        json2.Any(client.model)
		'input':        json2.Any(input)
		'input_type':   json2.Any(input_type)
		'output_dtype': json2.Any('float')
	}, json2.EncoderOptions{})
	if body.len > max_request_bytes {
		return error('Voyage embedding request exceeds the 8 MiB size limit')
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
		return error('Voyage embeddings request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Voyage embeddings request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_response_bytes {
		return error('Voyage embeddings response exceeds 16 MiB')
	}
	decoded := json2.decode[EmbeddingResponse](response.body, json2.DecoderOptions{}) or {
		return error('could not decode Voyage embeddings response: ${err.msg()}')
	}
	if decoded.data.len != texts.len {
		return error('Voyage returned ${decoded.data.len} vectors for ${texts.len} texts')
	}
	mut vectors := [][]f32{cap: decoded.data.len}
	mut dimension := -1
	for item in decoded.data {
		if item.embedding.len == 0 {
			return error('Voyage returned an empty embedding vector')
		}
		if dimension < 0 {
			dimension = item.embedding.len
		} else if item.embedding.len != dimension {
			return error('Voyage returned embeddings with different dimensions')
		}
		for value in item.embedding {
			if !math.is_finite(f64(value)) {
				return error('Voyage returned a non-finite embedding value')
			}
		}
		vectors << item.embedding.clone()
	}
	return vectors
}

// embedder builds the common preprocessing and bounded batching adapter.
pub fn (client Client) embedder(options embeddings.Options) !Embedder {
	if options.batch_size > max_embedding_inputs {
		return error('Voyage embedder batch size must not exceed 1000')
	}
	if options.batch_size <= 0 {
		return error('batch size must be greater than zero')
	}
	return Embedder{
		client:         client
		strip_newlines: options.strip_newlines
		batch_size:     options.batch_size
	}
}

// default_embedder uses the common defaults with Voyage's document/query modes.
pub fn (client Client) default_embedder() !Embedder {
	return client.embedder(embeddings.Options{})
}

// embed_documents embeds texts sequentially in bounded document batches.
pub fn (embedder Embedder) embed_documents(mut ctx context.Context, texts []string) ![][]f32 {
	prepared := embeddings.remove_newlines(texts, embedder.strip_newlines)
	return embeddings.batched_embed(mut ctx, embedder.client, prepared, embedder.batch_size)
}

// embed_query embeds one text using Voyage's query-specific input mode.
pub fn (embedder Embedder) embed_query(mut ctx context.Context, text string) ![]f32 {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	prepared := if embedder.strip_newlines { text.replace('\n', ' ') } else { text }
	vector := embedder.client.create_query_embedding(mut ctx, prepared)!
	if vector.len == 0 {
		return error('embedding vector must not be empty')
	}
	for value in vector {
		if !math.is_finite(f64(value)) {
			return error('embedding vector must contain finite values')
		}
	}
	return vector.clone()
}
