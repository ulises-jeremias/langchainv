// Package textsplitter provides a small built-in dictionary tokenizer.
module textsplitter

import strings

// simple_vocabulary holds common English fragments encoded as single tokens
// with ids starting at 256. Ids 0 through 255 are single bytes, which makes
// the encoding lossless for arbitrary UTF-8 text.
const simple_vocabulary = [
	' the ',
	' the',
	'the ',
	'the',
	'and',
	' and ',
	' and',
	'ing ',
	'ing',
	'tion',
	'ent',
	'ion',
	'er ',
	'ed ',
	'es ',
	'en ',
	'at ',
	'on ',
	'an ',
	'in ',
	'is ',
	'it ',
	'to ',
	'of ',
	'a ',
	'th',
	'he',
	'ou',
	'ea',
	'ar',
	'st',
	'le',
	'nt',
	're',
	'co',
	'de',
	'li',
	'sa',
	'as',
	'ic',
	'e ',
	's ',
	't ',
]

// SimpleTokenizer is a built-in dictionary tokenizer. It approximates the
// token counts of provider tokenizers on English text, but its counts are
// not identical to any provider encoding such as tiktoken or SentencePiece.
// Use an injected Tokenizer when exact provider counts matter.
pub struct SimpleTokenizer {}

// encode converts text to token ids with greedy longest-fragment matching.
pub fn (tokenizer SimpleTokenizer) encode(text string) ![]int {
	bytes := text.bytes()
	mut tokens := []int{cap: bytes.len}
	mut index := 0
	for index < bytes.len {
		mut matched := -1
		mut matched_len := 0
		for vocabulary_index, fragment in simple_vocabulary {
			if fragment.len > matched_len && fragment.len <= bytes.len - index
				&& bytes[index..index + fragment.len] == fragment.bytes() {
				matched = vocabulary_index
				matched_len = fragment.len
			}
		}
		if matched >= 0 {
			tokens << 256 + matched
			index += matched_len
		} else {
			tokens << int(bytes[index])
			index++
		}
	}
	return tokens
}

// decode converts token ids produced by encode back to text.
pub fn (tokenizer SimpleTokenizer) decode(tokens []int) !string {
	mut builder := strings.new_builder(tokens.len)
	for token in tokens {
		if token >= 0 && token < 256 {
			builder.write_u8(u8(token))
		} else if token >= 256 && token < 256 + simple_vocabulary.len {
			builder.write_string(simple_vocabulary[token - 256])
		} else {
			return error('simple tokenizer received unknown token id ${token}')
		}
	}
	return builder.str()
}

// new_simple_token_splitter constructs a token splitter with the built-in
// SimpleTokenizer and validated chunk limits.
pub fn new_simple_token_splitter(options TokenSplitterOptions) !TokenSplitter {
	return new_token_splitter(Tokenizer(SimpleTokenizer{}), options)
}
