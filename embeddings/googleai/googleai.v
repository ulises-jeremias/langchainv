// Package googleai implements Gemini's bounded batch embedding API.
module googleai

import context
import json2
import math
import ulises_jeremias.langchainv.embeddings
import ulises_jeremias.langchainv.httputil

const default_base_url = 'https://generativelanguage.googleapis.com/v1beta'
const default_model = 'gemini-embedding-2'
const max_batch_inputs = 100
const max_request_bytes = 8 * 1024 * 1024
const max_response_bytes = 16 * 1024 * 1024

struct EmbedResponse {
	embeddings []ContentEmbedding
}

struct ContentEmbedding {
	values []f32
}

// Client creates embeddings with Gemini batchEmbedContents.
pub struct Client {
	api_key     string
	http_client httputil.HTTPClient
pub:
	base_url              string = default_base_url
	model                 string = default_model
	task_type             string
	output_dimensionality int
}

// Options configures the Gemini endpoint, model, task type, and output size.
pub struct Options {
pub:
	base_url              string = default_base_url
	model                 string = default_model
	task_type             string
	output_dimensionality int
}

// new_client creates a Gemini embeddings client with default options.
pub fn new_client(api_key string, http_client httputil.HTTPClient) !Client {
	return new_client_with_options(api_key, http_client, Options{})
}

// new_default_client uses the shared bounded standard-library HTTP transport.
pub fn new_default_client(api_key string) !Client {
	return new_client(api_key, httputil.HTTPClient(httputil.new_default_client()))
}

// new_client_with_options validates endpoint, model and output configuration.
pub fn new_client_with_options(api_key string, http_client httputil.HTTPClient, options Options) !Client {
	if api_key.trim_space() == '' {
		return error('Google AI API key must not be empty')
	}
	if options.base_url.trim_space() == '' || options.model.trim_space() == '' {
		return error('Google AI base URL and embedding model must not be empty')
	}
	base_url := options.base_url.trim_space().trim_right('/')
	httputil.validate_url(base_url, 'https') or { return error('invalid Google AI base URL: ${err.msg()}') }
	model := normalize_model(options.model.trim_space())!
	if options.output_dimensionality < 0 || options.output_dimensionality > 3072
		|| (options.output_dimensionality > 0 && options.output_dimensionality < 128) {
		return error('Google AI output dimensionality must be zero or between 128 and 3072')
	}
	if options.task_type !in ['', 'RETRIEVAL_QUERY', 'RETRIEVAL_DOCUMENT', 'SEMANTIC_SIMILARITY',
		'CLASSIFICATION', 'CLUSTERING', 'QUESTION_ANSWERING', 'FACT_VERIFICATION',
		'CODE_RETRIEVAL_QUERY'] {
		return error('Google AI task type is not supported')
	}
	return Client{
		api_key:               api_key
		http_client:           http_client
		base_url:              base_url
		model:                 model
		task_type:             options.task_type
		output_dimensionality: options.output_dimensionality
	}
}

// create_embedding implements embeddings.EmbedderClient.
pub fn (client Client) create_embedding(mut ctx context.Context, texts []string) ![][]f32 {
	if texts.len == 0 {
		return [][]f32{}
	}
	if texts.len > max_batch_inputs {
		return error('Google AI embedding batch exceeds the 100-input limit')
	}
	for text in texts {
		if text == '' {
			return error('Google AI embedding input must not be empty')
		}
	}
	mut requests := []json2.Any{cap: texts.len}
	for text in texts {
		mut request := map[string]json2.Any{
			'model':   json2.Any('models/${client.model}')
			'content': json2.Any({
				'parts': json2.Any([json2.Any({
					'text': json2.Any(text)
				})])
			})
		}
		if client.task_type != '' {
			request['taskType'] = json2.Any(client.task_type)
		}
		if client.output_dimensionality > 0 {
			request['outputDimensionality'] = json2.Any(client.output_dimensionality)
		}
		requests << json2.Any(request)
	}
	body := json2.encode({
		'requests': json2.Any(requests)
	}, json2.EncoderOptions{})
	if body.len > max_request_bytes {
		return error('Google AI embedding request exceeds the 8 MiB size limit')
	}
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	response := client.http_client.do(mut ctx, httputil.Request{
		method:  .post
		url:     '${client.base_url}/models/${client.model}:batchEmbedContents'
		headers: {
			'x-goog-api-key': client.api_key
			'Content-Type':   'application/json'
			'Accept':         'application/json'
		}
		body:    body
	}) or {
		return error('Google AI embeddings request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Google AI embeddings request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_response_bytes {
		return error('Google AI embeddings response exceeds 16 MiB')
	}
	decoded := json2.decode[EmbedResponse](response.body, json2.DecoderOptions{}) or {
		return error('could not decode Google AI embeddings response: ${err.msg()}')
	}
	if decoded.embeddings.len != texts.len {
		return error('Google AI returned ${decoded.embeddings.len} vectors for ${texts.len} texts')
	}
	mut vectors := [][]f32{cap: decoded.embeddings.len}
	mut dimension := -1
	for embedding in decoded.embeddings {
		if embedding.values.len == 0 {
			return error('Google AI returned an empty embedding vector')
		}
		if dimension < 0 {
			dimension = embedding.values.len
		} else if embedding.values.len != dimension {
			return error('Google AI returned embeddings with different dimensions')
		}
		for value in embedding.values {
			if !math.is_finite(f64(value)) {
				return error('Google AI returned a non-finite embedding value')
			}
		}
		vectors << embedding.values.clone()
	}
	return vectors
}

// embedder builds the common batching and preprocessing adapter for this client.
pub fn (client Client) embedder(options embeddings.Options) !embeddings.EmbedderImpl {
	mut bounded_options := options
	if bounded_options.batch_size == 512 {
		bounded_options.batch_size = max_batch_inputs
	} else if bounded_options.batch_size > max_batch_inputs {
		return error('Google AI embedder batch size must not exceed 100')
	}
	return embeddings.new_embedder(client, bounded_options)
}

// default_embedder builds an adapter with upstream default batching behavior.
pub fn (client Client) default_embedder() !embeddings.EmbedderImpl {
	return embeddings.new_embedder(client, embeddings.Options{
		batch_size: max_batch_inputs
	})
}

fn normalize_model(raw string) !string {
	mut model := raw
	if model.starts_with('models/') {
		model = model['models/'.len..]
	}
	if model == '' || model.contains('/') || model.contains('?') || model.contains('#') {
		return error('Google AI embedding model must be a single model identifier')
	}
	return model
}
