// Package huggingface implements Hugging Face Inference Providers feature extraction.
module huggingface

import context
import json2
import math
import ulises_jeremias.langchainv.embeddings
import ulises_jeremias.langchainv.httputil

const default_base_url = 'https://router.huggingface.co/hf-inference'
const default_model = 'sentence-transformers/all-MiniLM-L6-v2'
const default_task = 'pipeline/feature-extraction'
const max_embedding_inputs = 64
const max_input_bytes = 1024 * 1024
const max_request_bytes = 8 * 1024 * 1024
const max_response_bytes = 16 * 1024 * 1024

struct EmbeddingRequest {
	inputs []json2.Any
}

// Client embeds text through Hugging Face's hosted inference router.
pub struct Client {
	token       string
	http_client httputil.HTTPClient
pub:
	base_url string = default_base_url
	model    string = default_model
	task     string = default_task
}

// Options configures the Hugging Face endpoint, model, and feature-extraction task.
pub struct Options {
pub:
	base_url string = default_base_url
	model    string = default_model
	task     string = default_task
}

// new_client configures the default Hugging Face feature extraction client.
pub fn new_client(token string, http_client httputil.HTTPClient) !Client {
	return new_client_with_options(token, http_client, Options{})
}

// new_default_client uses the shared bounded standard-library HTTP transport.
pub fn new_default_client(token string) !Client {
	return new_client(token, httputil.HTTPClient(httputil.new_default_client()))
}

// new_client_with_options validates credentials, HTTPS endpoint, model ID, and task.
pub fn new_client_with_options(token string, http_client httputil.HTTPClient, options Options) !Client {
	if token.trim_space() == '' {
		return error('Hugging Face API token must not be empty')
	}
	if options.base_url.trim_space() == '' || options.model.trim_space() == '' {
		return error('Hugging Face base URL and embedding model must not be empty')
	}
	base_url := options.base_url.trim_space().trim_right('/')
	httputil.validate_url(base_url, 'https') or { return error('invalid Hugging Face base URL: ${err.msg()}') }
	model := options.model.trim_space()
	if !valid_model_id(model) {
		return error('Hugging Face model must be a two-part model ID such as `owner/model`')
	}
	task := options.task.trim_space().trim('/')
	if task == '' || task.contains('..') || task.contains('?') || task.contains('#')
		|| task.contains('%') || task.contains('\\') || task.contains(' ') {
		return error('Hugging Face inference task is invalid')
	}
	return Client{
		token:       token
		http_client: http_client
		base_url:    base_url
		model:       model
		task:        task
	}
}

// create_embedding implements embeddings.EmbedderClient.
pub fn (client Client) create_embedding(mut ctx context.Context, texts []string) ![][]f32 {
	if texts.len == 0 {
		return [][]f32{}
	}
	if texts.len > max_embedding_inputs {
		return error('Hugging Face embedding request exceeds the 64-input limit')
	}
	mut input_bytes := 0
	mut inputs := []json2.Any{cap: texts.len}
	for text in texts {
		if text == '' {
			return error('Hugging Face embedding input must not be empty')
		}
		input_bytes += text.len
		if input_bytes > max_input_bytes {
			return error('Hugging Face embedding input exceeds the 1 MiB aggregate limit')
		}
		inputs << json2.Any(text)
	}
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	body := json2.encode(EmbeddingRequest{
		inputs: inputs
	}, json2.EncoderOptions{})
	if body.len > max_request_bytes {
		return error('Hugging Face embedding request exceeds the 8 MiB size limit')
	}
	response := client.http_client.do(mut ctx, httputil.Request{
		method:  .post
		url:     '${client.base_url}/models/${client.model}/${client.task}'
		headers: {
			'Authorization': 'Bearer ${client.token}'
			'Content-Type':  'application/json'
			'Accept':        'application/json'
		}
		body:    body
	}) or {
		return error('Hugging Face embeddings request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Hugging Face embeddings request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_response_bytes {
		return error('Hugging Face embeddings response exceeds 16 MiB')
	}
	vectors := json2.decode[[][]f32](response.body, json2.DecoderOptions{}) or {
		return error('could not decode Hugging Face embeddings response: ${err.msg()}')
	}
	if vectors.len != texts.len {
		return error('Hugging Face returned ${vectors.len} vectors for ${texts.len} texts')
	}
	mut dimension := -1
	for vector in vectors {
		if vector.len == 0 {
			return error('Hugging Face returned an empty embedding vector')
		}
		if dimension < 0 {
			dimension = vector.len
		} else if vector.len != dimension {
			return error('Hugging Face returned embeddings with different dimensions')
		}
		for value in vector {
			if !math.is_finite(f64(value)) {
				return error('Hugging Face returned a non-finite embedding value')
			}
		}
	}
	return vectors.map(it.clone())
}

// embedder adds common newline preprocessing and sequential batching.
pub fn (client Client) embedder(options embeddings.Options) !embeddings.EmbedderImpl {
	if options.batch_size > max_embedding_inputs {
		return error('Hugging Face embedder batch size must not exceed 64')
	}
	return embeddings.new_embedder(client, options)
}

// default_embedder uses the common batching and preprocessing defaults.
pub fn (client Client) default_embedder() !embeddings.EmbedderImpl {
	return embeddings.new_embedder(client, embeddings.Options{
		batch_size: max_embedding_inputs
	})
}

fn valid_model_id(model string) bool {
	parts := model.split('/')
	if parts.len != 2 || parts[0] == '' || parts[1] == '' {
		return false
	}
	for part in parts {
		if part.contains('..') || part.contains('?') || part.contains('#') || part.contains('%')
			|| part.contains('\\') || part.contains(' ') {
			return false
		}
	}
	return true
}
