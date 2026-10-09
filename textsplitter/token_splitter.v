module textsplitter

// Tokenizer converts text to and from one provider's token identifiers.
pub interface Tokenizer {
	encode(text string) ![]int
	decode(tokens []int) !string
}

// TokenSplitterOptions configures token count and overlap limits.
@[params]
pub struct TokenSplitterOptions {
pub:
	chunk_size    int = 512
	chunk_overlap int = 100
}

// TokenTextSplitter chunks text using an injected tokenizer. Keeping the
// tokenizer behind an interface avoids coupling core to a provider or network.
pub struct TokenSplitter {
	tokenizer     Tokenizer
	chunk_size    int
	chunk_overlap int
}

// split_text_bounded encodes once, checks the maximum number of token windows
// before decoding chunks, and stops if decoded output exceeds its byte budget.
pub fn (splitter TokenSplitter) split_text_bounded(text string, max_chunks int, max_input_bytes int, max_output_bytes i64) ![]string {
	if max_chunks < 0 || max_input_bytes < 0 || max_output_bytes < 0 {
		return error('split limits cannot be negative')
	}
	if text.len > max_input_bytes {
		return error('split input exceeds the ${max_input_bytes}-byte safety limit')
	}
	tokens := splitter.tokenizer.encode(text)!
	count_bound := estimate_chunk_count(tokens.len, splitter.chunk_size, splitter.chunk_overlap)
	if count_bound > max_chunks {
		return error('split output exceeds the ${max_chunks}-chunk limit')
	}
	mut chunks := []string{}
	mut total_bytes := i64(0)
	mut start := 0
	for start < tokens.len {
		end := if tokens.len - start > splitter.chunk_size {
			start + splitter.chunk_size
		} else {
			tokens.len
		}
		chunk := splitter.tokenizer.decode(tokens[start..end])!
		total_bytes += i64(chunk.len)
		if total_bytes > max_output_bytes {
			return error('split result exceeds the ${max_output_bytes}-byte limit')
		}
		chunks << chunk
		if end == tokens.len {
			break
		}
		start = end - splitter.chunk_overlap
	}
	return chunks
}

// new_token_text_splitter constructs a validated token-based splitter.
pub fn new_token_splitter(tokenizer Tokenizer, options TokenSplitterOptions) !TokenSplitter {
	if options.chunk_size <= 0 {
		return error('chunk size must be greater than zero')
	}
	if options.chunk_overlap < 0 || options.chunk_overlap >= options.chunk_size {
		return error('chunk overlap must be non-negative and less than chunk size')
	}
	return TokenSplitter{
		tokenizer:     tokenizer
		chunk_size:    options.chunk_size
		chunk_overlap: options.chunk_overlap
	}
}

// split_text encodes once and decodes each overlapping token window.
pub fn (splitter TokenSplitter) split_text(text string) ![]string {
	tokens := splitter.tokenizer.encode(text)!
	mut chunks := []string{}
	mut start := 0
	for start < tokens.len {
		end := if tokens.len - start > splitter.chunk_size {
			start + splitter.chunk_size
		} else {
			tokens.len
		}
		chunks << splitter.tokenizer.decode(tokens[start..end])!
		if end == tokens.len {
			break
		}
		start = end - splitter.chunk_overlap
	}
	return chunks
}
