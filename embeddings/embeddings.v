// Package embeddings defines common embedding operations and vector helpers.
module embeddings

import context
import math

// Embedder creates vectors for documents and queries.
pub interface Embedder {
	embed_documents(mut ctx context.Context, texts []string) ![][]f32
	embed_query(mut ctx context.Context, text string) ![]f32
}

// EmbedderClient is the provider-facing batched embedding contract.
pub interface EmbedderClient {
	create_embedding(mut ctx context.Context, texts []string) ![][]f32
}

// EmbedderClientFunc adapts a function into an EmbedderClient.
pub type EmbedderClientFunc = fn (mut context.Context, []string) ![][]f32

// create_embedding calls the wrapped embedding function.
pub fn (client EmbedderClientFunc) create_embedding(mut ctx context.Context, texts []string) ![][]f32 {
	return client(mut ctx, texts)
}

// Options controls text preprocessing and provider batch size.
pub struct Options {
pub mut:
	strip_newlines bool = true
	batch_size     int  = 512
}

// EmbedderImpl adapts an EmbedderClient with text normalization and batching.
pub struct EmbedderImpl {
pub mut:
	strip_newlines bool = true
	batch_size     int  = 512
pub:
	client EmbedderClient
}

// new_embedder wraps a provider client with validated preprocessing options.
pub fn new_embedder(client EmbedderClient, options Options) !EmbedderImpl {
	if options.batch_size <= 0 {
		return error('batch size must be greater than zero')
	}
	return EmbedderImpl{
		client:         client
		strip_newlines: options.strip_newlines
		batch_size:     options.batch_size
	}
}

// new_default_embedder wraps a provider client with the upstream defaults.
pub fn new_default_embedder(client EmbedderClient) !EmbedderImpl {
	return new_embedder(client, Options{})
}

// embed_documents embeds texts sequentially in bounded batches.
pub fn (embedder EmbedderImpl) embed_documents(mut ctx context.Context, texts []string) ![][]f32 {
	prepared := remove_newlines(texts, embedder.strip_newlines)
	return batched_embed(mut ctx, embedder.client, prepared, embedder.batch_size)
}

// embed_query embeds a single query using the same text normalization policy.
pub fn (embedder EmbedderImpl) embed_query(mut ctx context.Context, text string) ![]f32 {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	prepared := if embedder.strip_newlines { text.replace('\n', ' ') } else { text }
	vectors := embedder.client.create_embedding(mut ctx, [prepared])!
	if vectors.len != 1 {
		return error('embedder returned ${vectors.len} vectors for one query')
	}
	validate_vectors(vectors)!
	return vectors[0].clone()
}

// remove_newlines returns a copy whose line breaks are replaced with spaces.
pub fn remove_newlines(texts []string, enabled bool) []string {
	if !enabled {
		return texts.clone()
	}
	return texts.map(it.replace('\n', ' '))
}

// batch_texts divides input into batches no larger than batch_size.
pub fn batch_texts(texts []string, batch_size int) ![][]string {
	if batch_size <= 0 {
		return error('batch size must be greater than zero')
	}
	mut batches := [][]string{}
	mut start := 0
	for start < texts.len {
		end := if start + batch_size < texts.len { start + batch_size } else { texts.len }
		batches << texts[start..end].clone()
		start = end
	}
	return batches
}

// batched_embed embeds input texts in order and verifies every provider batch.
pub fn batched_embed(mut ctx context.Context, client EmbedderClient, texts []string, batch_size int) ![][]f32 {
	batches := batch_texts(texts, batch_size)!
	mut vectors := [][]f32{cap: texts.len}
	mut dimension := -1
	for batch in batches {
		ctx_error := ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
		batch_vectors := client.create_embedding(mut ctx, batch) or {
			return error('error embedding batch: ${err.msg()}')
		}
		if batch_vectors.len != batch.len {
			return error('embedder returned ${batch_vectors.len} vectors for ${batch.len} texts')
		}
		validate_vectors(batch_vectors)!
		for vector in batch_vectors {
			if dimension < 0 {
				dimension = vector.len
			} else if vector.len != dimension {
				return error('embedding vectors have different dimensions')
			}
			vectors << vector.clone()
		}
	}
	return vectors
}

// combine_vectors computes the weighted average and returns its unit vector.
pub fn combine_vectors(vectors [][]f32, weights []int) ![]f32 {
	if vectors.len != weights.len {
		return error('vector and weight counts differ')
	}
	if vectors.len == 0 {
		return []f32{}
	}
	dimension := vectors[0].len
	if dimension == 0 {
		return error('embedding vectors must not be empty')
	}
	mut weight_sum := i64(0)
	for index, vector in vectors {
		if vector.len != dimension {
			return error('embedding vectors have different dimensions')
		}
		weight_sum += i64(weights[index])
		for value in vector {
			if !math.is_finite(f64(value)) {
				return error('embedding vectors must contain finite values')
			}
		}
	}
	if weight_sum == 0 {
		return error('sum of embedding weights must not be zero')
	}
	mut average := []f32{len: dimension, init: 0}
	for index, vector in vectors {
		for j, value in vector {
			average[j] += value * f32(weights[index]) / f32(weight_sum)
		}
	}
	mut norm := f64(0)
	for value in average {
		norm += f64(value) * f64(value)
	}
	if norm == 0 || !math.is_finite(norm) {
		return error('weighted average has no finite direction')
	}
	denominator := f32(math.sqrt(norm))
	for i in 0 .. average.len {
		average[i] /= denominator
	}
	return average
}

fn validate_vectors(vectors [][]f32) ! {
	mut dimension := -1
	for vector in vectors {
		if vector.len == 0 {
			return error('embedding vectors must not be empty')
		}
		if dimension < 0 {
			dimension = vector.len
		} else if vector.len != dimension {
			return error('embedding vectors have different dimensions')
		}
		for value in vector {
			if !math.is_finite(f64(value)) {
				return error('embedding vectors must contain finite values')
			}
		}
	}
}

// dot_product returns the dot product of equal-length vectors.
pub fn dot_product(left []f32, right []f32) !f32 {
	if left.len != right.len {
		return error('vector dimensions differ: ${left.len} and ${right.len}')
	}
	mut sum := f64(0)
	for i, value in left {
		sum += f64(value) * f64(right[i])
	}
	return f32(sum)
}

// cosine_similarity returns the cosine similarity of equal-length nonzero vectors.
pub fn cosine_similarity(left []f32, right []f32) !f32 {
	product := dot_product(left, right)!
	mut left_norm := f64(0)
	mut right_norm := f64(0)
	for i, value in left {
		left_norm += f64(value) * f64(value)
		right_norm += f64(right[i]) * f64(right[i])
	}
	if left_norm == 0 || right_norm == 0 {
		return error('cosine similarity is undefined for a zero vector')
	}
	return f32(f64(product) / (math.sqrt(left_norm) * math.sqrt(right_norm)))
}
