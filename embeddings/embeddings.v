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

// Options controls text preprocessing and provider batch size.
pub struct Options {
pub mut:
	strip_newlines bool = true
	batch_size     int  = 128
}

// BatchedEmbedder preprocesses input and uses an EmbedderClient for requests.
pub struct BatchedEmbedder {
	client  EmbedderClient
	options Options
}

// new_embedder creates an embedder that strips newlines and batches by default.
pub fn new_embedder(client EmbedderClient, options Options) !BatchedEmbedder {
	if options.batch_size <= 0 {
		return error('batch size must be greater than zero')
	}
	return BatchedEmbedder{
		client:  client
		options: options
	}
}

// embed_query creates a vector for a single query.
pub fn (embedder BatchedEmbedder) embed_query(mut ctx context.Context, text string) ![]f32 {
	err := ctx.err()
	if err !is none {
		return err
	}
	input := remove_newlines([text], embedder.options.strip_newlines)
	embeddings := embedder.client.create_embedding(mut ctx, input)!
	request_error := ctx.err()
	if request_error !is none {
		return request_error
	}
	if embeddings.len != 1 {
		return error('embedding client returned ${embeddings.len} vectors for one query')
	}
	return embeddings[0]
}

// embed_documents preprocesses and embeds documents in bounded batches.
pub fn (embedder BatchedEmbedder) embed_documents(mut ctx context.Context, texts []string) ![][]f32 {
	inputs := remove_newlines(texts, embedder.options.strip_newlines)
	batches := batch_texts(inputs, embedder.options.batch_size)!
	mut vectors := [][]f32{cap: texts.len}
	for batch in batches {
		err := ctx.err()
		if err !is none {
			return err
		}
		batch_vectors := embedder.client.create_embedding(mut ctx, batch)!
		request_error := ctx.err()
		if request_error !is none {
			return request_error
		}
		if batch_vectors.len != batch.len {
			return error('embedding client returned ${batch_vectors.len} vectors for ${batch.len} inputs')
		}
		vectors << batch_vectors
	}
	return vectors
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
		batches << texts[start..end]
		start = end
	}
	return batches
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
