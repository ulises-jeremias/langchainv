// Package textsplitter divides text and documents into bounded chunks.
module textsplitter

import json2
import encoding.utf8
import ulises_jeremias.langchainv.schema

const default_separators = ['\n\n', '\n', ' ', '']
const default_max_fallback_runes = 4096
const maximum_fallback_runes = 1_000_000

// TextSplitter turns one text value into ordered chunks.
pub interface TextSplitter {
	split_text(text string) ![]string
}

// RecursiveCharacterOptions configures recursive separator selection.
@[params]
pub struct RecursiveCharacterOptions {
pub:
	chunk_size         int      = 512
	chunk_overlap      int      = 100
	separators         []string = default_separators
	keep_separator     bool
	length_fn          fn (string) int = rune_count
	max_fallback_runes int             = default_max_fallback_runes
}

// RecursiveCharacterTextSplitter prefers paragraph, line, and word boundaries
// before splitting by Unicode code point.
pub struct RecursiveCharacterTextSplitter {
	chunk_size         int
	chunk_overlap      int
	separators         []string
	keep_separator     bool
	length_fn          fn (string) int
	max_fallback_runes int
}

// new_recursive_character_text_splitter constructs a validated splitter.
pub fn new_recursive_character_text_splitter(options RecursiveCharacterOptions) !RecursiveCharacterTextSplitter {
	if options.chunk_size <= 0 {
		return error('chunk size must be greater than zero')
	}
	if options.chunk_overlap < 0 || options.chunk_overlap >= options.chunk_size {
		return error('chunk overlap must be non-negative and less than chunk size')
	}
	if options.max_fallback_runes <= 0 {
		return error('maximum fallback rune count must be greater than zero')
	}
	if options.max_fallback_runes > maximum_fallback_runes {
		return error('maximum fallback rune count cannot exceed ${maximum_fallback_runes}')
	}
	separators := if options.separators.len == 0 { default_separators } else { options.separators }
	if separators[separators.len - 1] != '' {
		return error('the final separator must be empty to enable Unicode-safe fallback')
	}
	return RecursiveCharacterTextSplitter{
		chunk_size:         options.chunk_size
		chunk_overlap:      options.chunk_overlap
		separators:         separators.clone()
		keep_separator:     options.keep_separator
		length_fn:          options.length_fn
		max_fallback_runes: options.max_fallback_runes
	}
}

// split_text recursively splits text using configured separators.
pub fn (splitter RecursiveCharacterTextSplitter) split_text(text string) ![]string {
	return splitter.split_recursive(text, splitter.separators)
}

fn (splitter RecursiveCharacterTextSplitter) split_recursive(text string, separators []string) ![]string {
	if text == '' {
		return []string{}
	}
	mut separator_index := separators.len - 1
	for i, separator in separators {
		if separator == '' || text.contains(separator) {
			separator_index = i
			break
		}
	}
	separator := separators[separator_index]
	remaining := if separator_index + 1 < separators.len {
		separators[separator_index + 1..]
	} else {
		[]string{}
	}
	if separator == '' {
		return split_runes(text, splitter.chunk_size, splitter.chunk_overlap, splitter.max_fallback_runes,
			splitter.length_fn)
	}
	mut splits := text.split(separator)
	merge_separator := if splitter.keep_separator {
		for i in 1 .. splits.len {
			splits[i] = separator + splits[i]
		}
		''
	} else {
		separator
	}
	mut chunks := []string{}
	mut good_splits := []string{}
	for split in splits {
		if splitter.length_fn(split) < splitter.chunk_size {
			good_splits << split
			continue
		}
		if good_splits.len > 0 {
			chunks << merge_splits(good_splits, merge_separator, splitter.chunk_size,
				splitter.chunk_overlap, splitter.length_fn)
			good_splits = []string{}
		}
		if remaining.len == 0 {
			chunks << split
		} else {
			chunks << splitter.split_recursive(split, remaining)!
		}
	}
	if good_splits.len > 0 {
		chunks << merge_splits(good_splits, merge_separator, splitter.chunk_size,
			splitter.chunk_overlap, splitter.length_fn)
	}
	return chunks
}

// split_documents preserves source metadata and score on every resulting chunk.
pub fn split_documents(splitter TextSplitter, documents []schema.Document) ![]schema.Document {
	mut results := []schema.Document{}
	for document in documents {
		chunks := splitter.split_text(document.page_content)!
		for chunk in chunks {
			results << schema.Document{
				page_content: chunk
				metadata:     clone_metadata(document.metadata)
				score:        document.score
			}
		}
	}
	return results
}

// create_documents splits text values and copies corresponding metadata.
// When metadatas is empty, each resulting document starts without metadata.
pub fn create_documents(splitter TextSplitter, texts []string, metadatas []map[string]json2.Any) ![]schema.Document {
	if metadatas.len != 0 && metadatas.len != texts.len {
		return error('number of texts and metadata entries must match')
	}
	mut documents := []schema.Document{}
	for i, text in texts {
		chunks := splitter.split_text(text)!
		for chunk in chunks {
			documents << schema.Document{
				page_content: chunk
				metadata:     if metadatas.len > 0 {
					clone_metadata(metadatas[i])
				} else {
					map[string]json2.Any{}
				}
			}
		}
	}
	return documents
}

fn clone_metadata(metadata map[string]json2.Any) map[string]json2.Any {
	mut copy := map[string]json2.Any{}
	for key, value in metadata {
		copy[key] = value
	}
	return copy
}

fn merge_splits(splits []string, separator string, chunk_size int, chunk_overlap int, length_fn fn (string) int) []string {
	mut documents := []string{}
	mut current := []string{}
	mut total := 0
	separator_length := length_fn(separator)
	for split in splits {
		split_length := length_fn(split)
		total_with_split := total + split_length
		if current.len > 0 {
			total_with_split += separator_length
		}
		if total_with_split > chunk_size && current.len > 0 {
			document := current.join(separator).trim_space()
			if document != '' {
				documents << document
			}
			for current.len > 0
				&& (total > chunk_overlap || (total + split_length + separator_length > chunk_size
					&& total > 0)) {
				total -= length_fn(current[0])
				if current.len > 1 {
					total -= separator_length
				}
				current = current[1..]
			}
		}
		current << split
		total += split_length
		if current.len > 1 {
			total += separator_length
		}
	}
	final_document := current.join(separator).trim_space()
	if final_document != '' {
		documents << final_document
	}
	return documents
}

fn split_runes(text string, chunk_size int, chunk_overlap int, max_fallback_runes int, length_fn fn (string) int) ![]string {
	return split_runes_with_prefix(text, chunk_size, chunk_overlap, max_fallback_runes, length_fn,
		'')
}

fn split_runes_with_prefix(text string, chunk_size int, chunk_overlap int, max_fallback_runes int, length_fn fn (string) int, prefix string) ![]string {
	if max_fallback_runes <= 0 || max_fallback_runes > maximum_fallback_runes {
		return error('maximum fallback rune count must be between 1 and ${maximum_fallback_runes}')
	}
	if !utf8.validate_str(text) {
		return error('text must be valid UTF-8 for Unicode-safe splitting')
	}
	total_runes := utf8.len(text)
	boundary_capacity := if total_runes < max_fallback_runes {
		total_runes + 1
	} else {
		max_fallback_runes + 1
	}
	mut chunks := []string{}
	mut start_byte := 0
	for start_byte < text.len {
		mut rune_boundaries := []int{cap: boundary_capacity}
		rune_boundaries << start_byte
		mut byte_index := start_byte
		mut iterator := text.substr_unsafe(start_byte, text.len).runes_iterator()
		for character in iterator {
			byte_index += rune_byte_width(character)
			rune_boundaries << byte_index
			if rune_boundaries.len > max_fallback_runes {
				break
			}
		}
		mut low := 1
		mut high := rune_boundaries.len - 1
		mut best_end := 0
		for low <= high {
			middle := low + (high - low) / 2
			candidate := '${prefix}${text.substr(start_byte, rune_boundaries[middle])}'
			if length_fn(candidate) <= chunk_size {
				best_end = middle
				low = middle + 1
			} else {
				high = middle - 1
			}
		}
		if best_end == 0 {
			return error('one Unicode code point exceeds the configured chunk size')
		}
		best_end_byte := rune_boundaries[best_end]
		chunks << text.substr(start_byte, best_end_byte)
		if best_end_byte == text.len {
			break
		}
		mut overlap_start := best_end
		for overlap_start > 0 {
			candidate_start := overlap_start - 1
			candidate := text.substr(rune_boundaries[candidate_start], best_end_byte)
			candidate_length := length_fn(candidate)
			if candidate_length > chunk_overlap {
				break
			}
			overlap_start = candidate_start
		}
		start_byte = if overlap_start == 0 { best_end_byte } else { rune_boundaries[overlap_start] }
	}
	return chunks
}

fn rune_byte_width(character rune) int {
	if character <= 0x7f {
		return 1
	}
	if character <= 0x7ff {
		return 2
	}
	if character <= 0xffff {
		return 3
	}
	return 4
}

fn rune_count(text string) int {
	return utf8.len(text)
}
