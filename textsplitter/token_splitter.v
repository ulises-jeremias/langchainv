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
