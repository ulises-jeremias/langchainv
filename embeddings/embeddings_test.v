module embeddings

import context

struct LengthEmbedderClient {}

fn (client LengthEmbedderClient) create_embedding(mut ctx context.Context, texts []string) ![][]f32 {
	return texts.map([f32(it.len)])
}

struct EmptyEmbedderClient {}

fn (client EmptyEmbedderClient) create_embedding(mut ctx context.Context, texts []string) ![][]f32 {
	return []
}

fn test_batched_embedder_preprocesses_and_batches_documents() {
	mut ctx := context.background()
	embedder := new_embedder(LengthEmbedderClient{}, Options{
		batch_size: 2
	}) or { panic(err) }
	vectors := embedder.embed_documents(mut ctx, ['a\nb', 'cat', 'fox']) or { panic(err) }
	assert vectors == [[3.0], [3.0], [3.0]]
}

fn test_batched_embedder_preserves_newlines_when_configured() {
	mut ctx := context.background()
	embedder := new_embedder(LengthEmbedderClient{}, Options{
		strip_newlines: false
	}) or { panic(err) }
	vector := embedder.embed_query(mut ctx, 'a\nb') or { panic(err) }
	assert vector == [f32(3)]
}

fn test_batched_embedder_rejects_incomplete_client_response() {
	mut ctx := context.background()
	embedder := new_embedder(EmptyEmbedderClient{}, Options{}) or { panic(err) }
	embedder.embed_documents(mut ctx, ['one']) or {
		assert err.msg().contains('returned 0 vectors for 1 inputs')
		return
	}
	assert false, 'expected incomplete embedding response to fail'
}

fn test_batch_texts_preserves_order_and_bounds() {
	batches := batch_texts(['a', 'b', 'c', 'd', 'e'], 2) or { panic(err) }
	assert batches == [['a', 'b'], ['c', 'd'], ['e']]
}

fn test_batch_texts_rejects_non_positive_size() {
	batch_texts(['a'], 0) or {
		assert err.msg().contains('greater than zero')
		return
	}
	assert false, 'expected invalid batch size to fail'
}

fn test_batch_texts_empty_input() {
	batches := batch_texts([], 4) or { panic(err) }
	assert batches.len == 0
}

fn test_remove_newlines() {
	assert remove_newlines(['first\nsecond'], true) == ['first second']
	assert remove_newlines(['first\nsecond'], false) == ['first\nsecond']
}

fn test_dot_product() {
	assert (dot_product([1.0, 2.0, 3.0], [4.0, 5.0, 6.0]) or { panic(err) }) == 32.0
}

fn test_dot_product_rejects_mismatched_dimensions() {
	dot_product([1.0], [1.0, 2.0]) or {
		assert err.msg().contains('dimensions differ')
		return
	}
	assert false, 'expected different dimensions to fail'
}

fn test_cosine_similarity() {
	result := cosine_similarity([1.0, 0.0], [1.0, 0.0]) or { panic(err) }
	assert result > 0.999 && result <= 1.0
}

fn test_cosine_similarity_rejects_zero_vector() {
	cosine_similarity([0.0, 0.0], [1.0, 0.0]) or {
		assert err.msg().contains('zero vector')
		return
	}
	assert false, 'expected zero vector to fail'
}
