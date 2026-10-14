module textsplitter

fn test_simple_tokenizer_round_trips_text() {
	tokenizer := SimpleTokenizer{}
	for text in ['Hello, world!', 'the quick brown fox jumps over the lazy dog',
		'Ünïcödé — text with punctuation… and numbers 12345', ''] {
		tokens := tokenizer.encode(text) or { panic(err) }
		decoded := tokenizer.decode(tokens) or { panic(err) }
		assert decoded == text
	}
}

fn test_simple_tokenizer_compresses_common_fragments() {
	tokenizer := SimpleTokenizer{}
	text := 'the and the and the'
	tokens := tokenizer.encode(text) or { panic(err) }
	assert tokens.len < text.len
	assert tokens.len <= 6
}

fn test_simple_tokenizer_rejects_unknown_token_ids() {
	tokenizer := SimpleTokenizer{}
	tokenizer.decode([100000]) or {
		assert err.msg().contains('unknown token')
		return
	}
	assert false, 'expected an unknown token id to fail'
}

fn test_simple_token_splitter_chunks_by_token_windows() {
	splitter := new_simple_token_splitter(TokenSplitterOptions{
		chunk_size:    4
		chunk_overlap: 1
	}) or { panic(err) }
	chunks := splitter.split_text('one two three four five six seven') or { panic(err) }
	assert chunks.len >= 2
	for chunk in chunks {
		assert chunk.len <= 24
	}
	assert chunks[0].starts_with('one')
	assert chunks.last().len > 0
}
