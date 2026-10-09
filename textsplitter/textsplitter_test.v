module textsplitter

import json2
import ulises_jeremias.langchainv.schema

struct RuneTokenizer {}

fn byte_length(text string) int {
	return text.len
}

fn heading_sensitive_length(text string) int {
	if text.starts_with('# H\n') {
		return text.len + 5
	}
	return text.len
}

pub fn (_ RuneTokenizer) encode(text string) ![]int {
	mut tokens := []int{}
	for character in text.runes() {
		tokens << int(character)
	}
	return tokens
}

pub fn (_ RuneTokenizer) decode(tokens []int) !string {
	mut characters := []rune{len: tokens.len}
	for i, token in tokens {
		characters[i] = rune(token)
	}
	return characters.string()
}

fn test_recursive_splitter_merges_with_overlap() {
	splitter := new_recursive_character_text_splitter(
		chunk_size:    6
		chunk_overlap: 3
		separators:    [' ', '']
	) or { panic(err) }
	chunks := splitter.split_text('aa bb cc dd') or { panic(err) }
	assert chunks == ['aa bb', 'bb cc', 'cc dd']
}

fn test_recursive_splitter_splits_unicode_code_points() {
	splitter := new_recursive_character_text_splitter(chunk_size: 2, chunk_overlap: 1) or {
		panic(err)
	}
	chunks := splitter.split_text('A😀中') or { panic(err) }
	assert chunks == ['A😀', '😀中']
}

fn test_recursive_splitter_uses_custom_length_function() {
	splitter := new_recursive_character_text_splitter(
		chunk_size:    5
		chunk_overlap: 0
		length_fn:     byte_length
	) or { panic(err) }
	chunks := splitter.split_text('a😀b') or { panic(err) }
	assert chunks == ['a😀', 'b']
}

fn test_recursive_splitter_errors_when_one_code_point_exceeds_limit() {
	splitter := new_recursive_character_text_splitter(
		chunk_size:    3
		chunk_overlap: 0
		length_fn:     byte_length
	) or { panic(err) }
	if _ := splitter.split_text('😀') {
		assert false, 'expected an oversized code point to fail'
	}
}

fn test_recursive_splitter_bounds_unicode_fallback_work() {
	splitter := new_recursive_character_text_splitter(
		chunk_size:         10
		chunk_overlap:      0
		separators:         ['']
		max_fallback_runes: 2
	) or { panic(err) }
	chunks := splitter.split_text('abcde') or { panic(err) }
	assert chunks == ['ab', 'cd', 'e']
}

fn test_recursive_splitter_can_keep_non_whitespace_separators() {
	splitter := new_recursive_character_text_splitter(
		chunk_size:     3
		chunk_overlap:  0
		separators:     ['|', '']
		keep_separator: true
	) or { panic(err) }
	chunks := splitter.split_text('aa|bb') or { panic(err) }
	assert chunks == ['aa', '|bb']
}

fn test_token_splitter_uses_injected_tokenizer_and_overlap() {
	splitter := new_token_splitter(RuneTokenizer{}, chunk_size: 3, chunk_overlap: 1) or {
		panic(err)
	}
	chunks := splitter.split_text('abcdefg') or { panic(err) }
	assert chunks == ['abc', 'cde', 'efg']
}

fn test_split_documents_copies_metadata_and_score() {
	splitter := new_recursive_character_text_splitter(
		chunk_size:    6
		chunk_overlap: 3
		separators:    [' ', '']
	) or { panic(err) }
	mut source := schema.new_document('aa bb cc')
	source.metadata['origin'] = json2.Any('fixture.txt')
	source.score = 0.75
	documents := split_documents(splitter, [source]) or { panic(err) }
	assert documents.len == 2
	assert documents[0].page_content == 'aa bb'
	assert documents[1].page_content == 'bb cc'
	assert documents[0].metadata['origin'] == json2.Any('fixture.txt')
	assert documents[1].metadata['origin'] == json2.Any('fixture.txt')
	assert documents[0].score == 0.75
	assert documents[1].score == 0.75
}

fn test_create_documents_without_metadata() {
	splitter := new_recursive_character_text_splitter(chunk_size: 2, chunk_overlap: 0) or {
		panic(err)
	}
	documents := create_documents(splitter, ['hello'], []) or { panic(err) }
	assert documents.len == 3
	assert documents[0].page_content == 'he'
	assert documents[1].page_content == 'll'
	assert documents[2].page_content == 'o'
	assert documents[0].metadata.len == 0
}

fn test_create_documents_copies_metadata_maps() {
	splitter := new_recursive_character_text_splitter(chunk_size: 10, chunk_overlap: 0) or {
		panic(err)
	}
	mut metadata := map[string]json2.Any{}
	metadata['origin'] = json2.Any('source')
	mut documents := create_documents(splitter, ['text'], [metadata]) or { panic(err) }
	documents[0].metadata['origin'] = json2.Any('changed')
	assert (metadata['origin'] or { panic('missing origin') }) == json2.Any('source')
}

fn test_create_documents_rejects_metadata_count_mismatch() {
	splitter := new_recursive_character_text_splitter() or { panic(err) }
	if _ := create_documents(splitter, ['one', 'two'], [map[string]json2.Any{}]) {
		assert false, 'expected metadata count mismatch to fail'
	}
}

fn test_recursive_splitter_returns_no_chunks_for_empty_text() {
	splitter := new_recursive_character_text_splitter() or { panic(err) }
	assert (splitter.split_text('') or { panic(err) }) == []string{}
}

fn test_markdown_splitter_resolves_reference_links() {
	splitter := new_markdown_text_splitter(
		chunk_size:      256
		chunk_overlap:   0
		reference_links: true
	) or { panic(err) }
	text := '[V][docs]\n\n[docs]: https://example.com "Reference"'
	chunks := splitter.split_text(text) or { panic(err) }
	assert chunks.len == 1
	assert chunks[0].contains('[V](<https://example.com>')
}

fn test_markdown_splitter_resolves_escaped_destination_and_following_line_title() {
	splitter := new_markdown_text_splitter(
		chunk_size:      256
		chunk_overlap:   0
		reference_links: true
	) or { panic(err) }
	text := '[V][docs]\n\n[docs]: https://example.com/a\\ b\n"Reference"'
	chunks := splitter.split_text(text) or { panic(err) }
	assert chunks.len == 1
	assert chunks[0].contains('[V](https://example.com/a\\ b "Reference")')
}

fn test_markdown_splitter_keeps_first_duplicate_reference_definition() {
	splitter := new_markdown_text_splitter(
		chunk_size:      256
		chunk_overlap:   0
		reference_links: true
	) or { panic(err) }
	text := '[docs]: not a title with spaces\n[V][docs]\n\n[docs]: https://first.example\n[docs]: https://second.example'
	chunks := splitter.split_text(text) or { panic(err) }
	assert chunks.len == 1
	assert chunks[0].contains('[V](<https://first.example>)')
	assert !chunks[0].contains('second.example')
}

fn test_markdown_splitter_ignores_reference_title_with_escaped_closing_quote() {
	splitter := new_markdown_text_splitter(
		chunk_size:      256
		chunk_overlap:   0
		reference_links: true
	) or { panic(err) }
	invalid_definition := '[docs]: https://broken.example "bad\\"'
	text := invalid_definition + '\n[V][docs]\n\n[docs]: https://good.example "Good"'
	chunks := splitter.split_text(text) or { panic(err) }
	assert chunks.len == 1
	assert chunks[0].contains('https://good.example')
	assert !chunks[0].contains('https://broken.example')
}

fn test_markdown_splitter_keeps_indented_code_reference_unchanged() {
	splitter := new_markdown_text_splitter(
		chunk_size:      256
		chunk_overlap:   0
		reference_links: true
	) or { panic(err) }
	text := '[V][docs]\n\n    [V][docs]\n\n[docs]: https://example.com'
	chunks := splitter.split_text(text) or { panic(err) }
	assert chunks.len == 1
	assert chunks[0].contains('    [V][docs]')
}

fn test_markdown_splitter_counts_heading_context_in_chunk_size() {
	splitter := new_markdown_text_splitter(
		chunk_size:             6
		chunk_overlap:          3
		keep_heading_hierarchy: true
	) or { panic(err) }
	chunks := splitter.split_text('# H\n\nabcdef') or { panic(err) }
	assert chunks.len > 1
	for chunk in chunks {
		assert rune_count(chunk) <= 6
	}
}

fn test_markdown_splitter_checks_complete_chunk_with_custom_length_function() {
	splitter := new_markdown_text_splitter(
		chunk_size:             12
		chunk_overlap:          0
		keep_heading_hierarchy: true
		length_fn:              heading_sensitive_length
	) or { panic(err) }
	chunks := splitter.split_text('# H\n\nabcdefghij') or { panic(err) }
	assert chunks.len > 1
	for chunk in chunks {
		assert heading_sensitive_length(chunk) <= 12
	}
}

fn test_markdown_splitter_requires_closing_fence_to_match_opening_length() {
	splitter := new_markdown_text_splitter(
		chunk_size:    256
		chunk_overlap: 0
		code_blocks:   true
	) or { panic(err) }
	text := '````\ninside\n```\nstill inside\n````\nafter'
	chunks := splitter.split_text(text) or { panic(err) }
	assert chunks.len == 2
	assert chunks[0].contains('still inside')
	assert chunks[1].contains('after')
}

fn test_markdown_splitter_does_not_treat_indented_fence_as_fence() {
	splitter := new_markdown_text_splitter(
		chunk_size:    256
		chunk_overlap: 0
	) or { panic(err) }
	chunks := splitter.split_text('    ```\n    keep this\n    ```\nafter') or { panic(err) }
	assert chunks.join('\n').contains('keep this')
}
