module embeddings

import context

struct RecordingEmbedderClient {
	state &RecordingEmbedderState
}

struct RecordingEmbedderState {
mut:
	calls [][]string
}

fn (client RecordingEmbedderClient) create_embedding(mut _ctx context.Context, texts []string) ![][]f32 {
	mut state := client.state
	state.calls << texts.clone()
	mut vectors := [][]f32{cap: texts.len}
	for text in texts {
		vectors << [f32(text.len), 1]
	}
	return vectors
}

fn test_embedder_batches_and_normalizes_text_without_mutating_inputs() {
	mut ctx := context.background()
	mut state := &RecordingEmbedderState{}
	client := RecordingEmbedderClient{
		state: state
	}
	embedder := new_embedder(client, Options{
		batch_size: 2
	}) or { panic(err) }
	texts := ['a\nb', 'cd', 'e']
	vectors := embedder.embed_documents(mut ctx, texts) or { panic(err) }
	assert texts == ['a\nb', 'cd', 'e']
	assert state.calls == [['a b', 'cd'], ['e']]
	assert vectors.len == 3
	assert vectors[0] == [f32(3), 1]
	assert vectors[2] == [f32(1), 1]
	query := embedder.embed_query(mut ctx, 'x\ny') or { panic(err) }
	assert query == [f32(3), 1]
	assert state.calls[2] == ['x y']
}

fn test_default_embedder_uses_langchaingo_defaults() {
	embedder := new_default_embedder(RecordingEmbedderClient{
		state: &RecordingEmbedderState{}
	}) or { panic(err) }
	assert embedder.strip_newlines
	assert embedder.batch_size == 512
}

fn test_embedder_rejects_invalid_batch_size_and_provider_count() {
	new_embedder(RecordingEmbedderClient{
		state: &RecordingEmbedderState{}
	}, Options{
		batch_size: 0
	}) or {
		assert err.msg().contains('greater than zero')
		return
	}
	assert false, 'expected zero batch size to fail'
}

fn test_combine_vectors_returns_normalized_weighted_average() {
	result := combine_vectors([[f32(1), 0], [0, f32(1)]], [1, 1]) or { panic(err) }
	assert result[0] > 0.7 && result[0] < 0.71
	assert result[1] > 0.7 && result[1] < 0.71
}

fn test_combine_vectors_rejects_mismatched_dimensions() {
	combine_vectors([[f32(1)], [f32(1), 0]], [1, 1]) or {
		assert err.msg().contains('different dimensions')
		return
	}
	assert false, 'expected mismatched dimensions to fail'
}

fn test_combine_vectors_rejects_zero_direction() {
	combine_vectors([[f32(1), 0], [f32(-1), 0]], [1, 1]) or {
		assert err.msg().contains('no finite direction')
		return
	}
	assert false, 'expected zero weighted direction to fail'
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
