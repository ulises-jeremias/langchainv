// Package bedrock implements text embeddings through the Amazon Bedrock Runtime API.
module bedrock

import context
import json2
import math
import ulises_jeremias.langchainv.embeddings
import ulises_jeremias.langchainv.httputil

const default_model = 'amazon.titan-embed-text-v2:0'
const max_request_bytes = 1024 * 1024
const max_response_bytes = 16 * 1024 * 1024
const max_cohere_inputs = 96

struct TitanResponse {
	embedding []f32
}

struct CohereResponse {
	embeddings [][]f32
}

// Client invokes Titan or Cohere embedding models through Bedrock Runtime.
pub struct Client {
	api_key     string
	http_client httputil.HTTPClient
pub:
	base_url   string
	model      string = default_model
	dimensions int
	normalize  bool = true
}

// Options configures the Bedrock API key, AWS region, model, and Titan dimensions.
pub struct Options {
pub:
	base_url   string
	region     string = 'us-east-1'
	model      string = default_model
	dimensions int
	normalize  bool = true
}

// Embedder preserves Cohere's query/document input modes under the common interface.
pub struct Embedder {
	client         Client
	strip_newlines bool
	batch_size     int
}

// new_client configures a Bedrock Runtime client using defaults.
pub fn new_client(api_key string, http_client httputil.HTTPClient) !Client {
	return new_client_with_options(api_key, http_client, Options{})
}

// new_default_client uses the shared bounded HTTP transport.
pub fn new_default_client(api_key string) !Client {
	return new_client(api_key, httputil.HTTPClient(httputil.new_default_client()))
}

// new_client_with_options validates API-key authentication and model settings.
pub fn new_client_with_options(api_key string, http_client httputil.HTTPClient, options Options) !Client {
	if api_key.trim_space() == '' {
		return error('Amazon Bedrock API key must not be empty')
	}
	if options.model.trim_space() == '' {
		return error('Amazon Bedrock embedding model must not be empty')
	}
	model := options.model.trim_space()
	if !supported_model(model) {
		return error('Amazon Bedrock supports Titan Text Embeddings and Cohere Embed v3 models')
	}
	base_url := if options.base_url.trim_space() != '' {
		options.base_url.trim_space().trim_right('/')
	} else {
		region := options.region.trim_space()
		if !valid_region(region) {
			return error('Amazon Bedrock region is invalid')
		}
		'https://bedrock-runtime.${region}.amazonaws.com'
	}
	httputil.validate_url(base_url, 'https') or {
		return error('invalid Amazon Bedrock base URL: ${err.msg()}')
	}
	if options.dimensions !in [0, 256, 512, 1024] {
		return error('Amazon Titan dimensions must be zero, 256, 512, or 1024')
	}
	if options.dimensions > 0 && model != 'amazon.titan-embed-text-v2:0' {
		return error('dimensions are only supported by Amazon Titan Text Embeddings V2')
	}
	return Client{
		api_key:     api_key
		http_client: http_client
		base_url:    base_url
		model:       model
		dimensions:  options.dimensions
		normalize:   options.normalize
	}
}

// create_embedding implements embeddings.EmbedderClient for document input.
pub fn (client Client) create_embedding(mut ctx context.Context, texts []string) ![][]f32 {
	return client.create_embedding_with_type(mut ctx, texts, 'document')
}

// create_query_embedding uses Cohere's query-specific input type where available.
pub fn (client Client) create_query_embedding(mut ctx context.Context, text string) ![]f32 {
	if text == '' {
		return error('Amazon Bedrock embedding input must not be empty')
	}
	vectors := client.create_embedding_with_type(mut ctx, [text], 'query')!
	if vectors.len != 1 {
		return error('Amazon Bedrock returned ${vectors.len} vectors for one query')
	}
	return vectors[0].clone()
}

fn (client Client) create_embedding_with_type(mut ctx context.Context, texts []string, input_type string) ![][]f32 {
	if texts.len == 0 {
		return [][]f32{}
	}
	if is_cohere(client.model) {
		if texts.len > max_cohere_inputs {
			return error('Amazon Bedrock Cohere request exceeds the 96-input limit')
		}
	} else if texts.len > 1 {
		return error('Amazon Titan embedding requests accept one input at a time')
	}
	mut total_input_bytes := 0
	for text in texts {
		if text == '' {
			return error('Amazon Bedrock embedding input must not be empty')
		}
		total_input_bytes += text.len
		if total_input_bytes > max_request_bytes {
			return error('Amazon Bedrock embedding input exceeds the 1 MiB limit')
		}
	}
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	body := client.request_body(texts, input_type)
	if body.len > max_request_bytes {
		return error('Amazon Bedrock embedding request exceeds the 1 MiB size limit')
	}
	response := client.http_client.do(mut ctx, httputil.Request{
		method:  .post
		url:     '${client.base_url}/model/${client.model}/invoke'
		headers: {
			'Authorization': 'Bearer ${client.api_key}'
			'Content-Type':  'application/json'
			'Accept':        'application/json'
		}
		body:    body
	}) or {
		return error('Amazon Bedrock embeddings request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Amazon Bedrock embeddings request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_response_bytes {
		return error('Amazon Bedrock embeddings response exceeds 16 MiB')
	}
	if is_cohere(client.model) {
		decoded := json2.decode[CohereResponse](response.body, json2.DecoderOptions{}) or {
			return error('could not decode Amazon Bedrock Cohere response: ${err.msg()}')
		}
		return validate_vectors(decoded.embeddings, texts.len)
	}
	decoded := json2.decode[TitanResponse](response.body, json2.DecoderOptions{}) or {
		return error('could not decode Amazon Bedrock Titan response: ${err.msg()}')
	}
	return validate_vectors([decoded.embedding], 1)
}

fn (client Client) request_body(texts []string, input_type string) string {
	if is_cohere(client.model) {
		mut inputs := []json2.Any{cap: texts.len}
		for text in texts {
			inputs << json2.Any(text)
		}
		return json2.encode({
			'texts':      json2.Any(inputs)
			'input_type': json2.Any(if input_type == 'query' {
				'search_query'
			} else {
				'search_document'
			})
		}, json2.EncoderOptions{})
	}
	mut request := map[string]json2.Any{
		'inputText': json2.Any(texts[0])
	}
	if client.model == 'amazon.titan-embed-text-v2:0' {
		request['normalize'] = json2.Any(client.normalize)
		request['embeddingTypes'] = json2.Any([json2.Any('float')])
		if client.dimensions > 0 {
			request['dimensions'] = json2.Any(client.dimensions)
		}
	}
	return json2.encode(request, json2.EncoderOptions{})
}

fn (client Client) embedder(options embeddings.Options) !Embedder {
	max_batch := if is_cohere(client.model) { max_cohere_inputs } else { 1 }
	if options.batch_size <= 0 || options.batch_size > max_batch {
		return error('Amazon Bedrock embedder batch size must be between 1 and ${max_batch}')
	}
	return Embedder{
		client:         client
		strip_newlines: options.strip_newlines
		batch_size:     options.batch_size
	}
}

// new_embedder constructs the common adapter with a provider-appropriate batch size.
pub fn (client Client) new_embedder(options embeddings.Options) !Embedder {
	mut bounded := options
	if bounded.batch_size == 512 {
		bounded.batch_size = if is_cohere(client.model) { max_cohere_inputs } else { 1 }
	}
	return client.embedder(bounded)
}

// default_embedder uses one-at-a-time Titan calls or bounded Cohere batches.
pub fn (client Client) default_embedder() !Embedder {
	return client.new_embedder(embeddings.Options{})
}

// embed_documents preprocesses and embeds text using model-appropriate batches.
pub fn (embedder Embedder) embed_documents(mut ctx context.Context, texts []string) ![][]f32 {
	prepared := embeddings.remove_newlines(texts, embedder.strip_newlines)
	return embeddings.batched_embed(mut ctx, embedder.client, prepared, embedder.batch_size)
}

// embed_query embeds text using the Cohere query input mode when applicable.
pub fn (embedder Embedder) embed_query(mut ctx context.Context, text string) ![]f32 {
	prepared := if embedder.strip_newlines { text.replace('\n', ' ') } else { text }
	vector := embedder.client.create_query_embedding(mut ctx, prepared)!
	return vector.clone()
}

fn supported_model(model string) bool {
	return model in ['amazon.titan-embed-text-v1', 'amazon.titan-embed-text-v2:0',
		'cohere.embed-english-v3', 'cohere.embed-multilingual-v3']
}

fn is_cohere(model string) bool {
	return model.starts_with('cohere.embed-')
}

fn valid_region(region string) bool {
	if region == '' || region.contains('.') || region.contains('/') || region.contains(':') {
		return false
	}
	for ch in region {
		if !(ch.is_alnum() || ch == `-`) {
			return false
		}
	}
	return true
}

fn validate_vectors(vectors [][]f32, expected_count int) ![][]f32 {
	if vectors.len != expected_count {
		return error('Amazon Bedrock returned ${vectors.len} vectors for ${expected_count} texts')
	}
	mut dimension := -1
	for vector in vectors {
		if vector.len == 0 {
			return error('Amazon Bedrock returned an empty embedding vector')
		}
		if dimension < 0 {
			dimension = vector.len
		} else if vector.len != dimension {
			return error('Amazon Bedrock returned embeddings with different dimensions')
		}
		for value in vector {
			if !math.is_finite(f64(value)) {
				return error('Amazon Bedrock returned a non-finite embedding value')
			}
		}
	}
	return vectors.map(it.clone())
}
