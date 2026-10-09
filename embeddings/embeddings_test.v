module embeddings

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
