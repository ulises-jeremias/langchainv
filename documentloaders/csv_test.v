module documentloaders

import context
import ulises_jeremias.langchainv.textsplitter

fn test_csv_loader_formats_each_row_and_keeps_one_based_row_metadata() {
	mut ctx := context.background()
	loader := new_csv_loader('name,age,city\nJane,32,London\nJohn,25,New York') or {
		panic(err)
	}
	documents := loader.load(mut ctx) or { panic(err) }
	assert documents.len == 2
	assert documents[0].page_content == 'name: Jane\nage: 32\ncity: London'
	assert (documents[0].metadata['row'] or { panic('missing first row metadata') }).int() == 1
	assert documents[1].page_content == 'name: John\nage: 25\ncity: New York'
	assert (documents[1].metadata['row'] or { panic('missing second row metadata') }).int() == 2
}

fn test_csv_loader_filters_columns_and_preserves_quoted_values() {
	mut ctx := context.background()
	loader := new_csv_loader('name,notes,city\nJane,"likes, tea",London\nJohn,"first line\nsecond line",Paris',
		columns: ['notes', 'city']
	) or { panic(err) }
	documents := loader.load(mut ctx) or { panic(err) }
	assert documents.len == 2
	assert documents[0].page_content == 'notes: likes, tea\ncity: London'
	assert documents[1].page_content == 'notes: first line\nsecond line\ncity: Paris'
}

fn test_csv_loader_unescapes_quotes_and_reads_crlf_records() {
	mut ctx := context.background()
	loader := new_csv_loader('name,notes\r\nJane,"says ""hello"""\r\n') or { panic(err) }
	documents := loader.load(mut ctx) or { panic(err) }
	assert documents.len == 1
	assert documents[0].page_content == 'name: Jane\nnotes: says "hello"'
}

fn test_csv_loader_treats_hash_prefixed_rows_as_data() {
	mut ctx := context.background()
	loader := new_csv_loader('name,city\n#tag,Somewhere') or { panic(err) }
	documents := loader.load(mut ctx) or { panic(err) }
	assert documents.len == 1
	assert documents[0].page_content == 'name: #tag\ncity: Somewhere'
}

fn test_csv_loader_returns_no_documents_for_empty_or_header_only_input() {
	mut ctx := context.background()
	empty_loader := new_csv_loader('') or { panic(err) }
	empty_documents := empty_loader.load(mut ctx) or { panic(err) }
	assert empty_documents.len == 0
	header_loader := new_csv_loader('name,city\n') or { panic(err) }
	header_documents := header_loader.load(mut ctx) or { panic(err) }
	assert header_documents.len == 0
}

fn test_csv_loader_rejects_rows_with_different_field_counts() {
	mut ctx := context.background()
	loader := new_csv_loader('name,city\nJane,London,UK') or { panic(err) }
	loader.load(mut ctx) or {
		assert err.msg().contains('row 2 has 3 fields; expected 2')
		return
	}
	assert false, 'expected inconsistent CSV row width to fail'
}

fn test_csv_loader_rejects_unclosed_and_misplaced_quotes() {
	mut ctx := context.background()
	for input, expected in {
		'name,notes\nJane,"unclosed':    'inside a quoted field'
		'name,notes\nJane,has"quote':    'unquoted CSV field'
		'name,notes\nJane,"closed"tail': 'after a quoted CSV field'
	} {
		loader := new_csv_loader(input) or { panic(err) }
		loader.load(mut ctx) or {
			assert err.msg().contains(expected)
			continue
		}
		assert false, 'expected malformed CSV quotes to fail'
	}
}

fn test_csv_loader_rejects_oversized_data() {
	new_csv_loader('name\nJane', max_bytes: 4) or {
		assert err.msg().contains('above the 4-byte limit')
		return
	}
	assert false, 'expected oversized CSV data to fail'
}

fn test_csv_loader_rejects_negative_byte_limit() {
	new_csv_loader('name', max_bytes: -1) or {
		assert err.msg().contains('cannot be negative')
		return
	}
	assert false, 'expected negative CSV byte limit to fail'
}

fn test_csv_loader_rejects_negative_document_limit() {
	new_csv_loader('name', max_documents: -1) or {
		assert err.msg().contains('document count cannot be negative')
		return
	}
	assert false, 'expected negative CSV limits to fail'
}

fn test_csv_loader_rejects_negative_output_limit() {
	new_csv_loader('name', max_output_bytes: -1) or {
		assert err.msg().contains('output size cannot be negative')
		return
	}
	assert false, 'expected negative CSV output limit to fail'
}

fn test_csv_loader_rejects_negative_split_input_limit() {
	new_csv_loader('name', max_split_input_bytes: -1) or {
		assert err.msg().contains('split input size cannot be negative')
		return
	}
	assert false, 'expected negative split input limit to fail'
}

fn test_csv_loader_rejects_negative_column_limit() {
	new_csv_loader('name', max_columns: -1) or {
		assert err.msg().contains('column count cannot be negative')
		return
	}
	assert false, 'expected negative column limit to fail'
}

fn test_csv_loader_preflights_column_count_before_parsing() {
	mut ctx := context.background()
	loader := new_csv_loader('a,b,c\n1,2,3', max_columns: 2) or { panic(err) }
	loader.load(mut ctx) or {
		assert err.msg().contains('exceeds the 2-column limit')
		return
	}
	assert false, 'expected the column count limit to be enforced'
}

fn test_csv_loader_bounds_formatted_output_bytes() {
	mut ctx := context.background()
	loader := new_csv_loader('long-header-name\nx', max_output_bytes: 10) or { panic(err) }
	loader.load(mut ctx) or {
		assert err.msg().contains('exceed the 10-byte output limit')
		return
	}
	assert false, 'expected formatted output size to be enforced'
}

fn test_csv_loader_bounds_document_count() {
	mut ctx := context.background()
	loader := new_csv_loader('name\nJane\nJohn', max_documents: 1) or { panic(err) }
	loader.load(mut ctx) or {
		assert err.msg().contains('exceeds the 1-document limit')
		return
	}
	assert false, 'expected the document count limit to be enforced'
}

fn test_csv_loader_can_split_documents_and_preserve_row_metadata() {
	mut ctx := context.background()
	loader := new_csv_loader('name,notes\nJane,"first paragraph\n\nsecond paragraph"', max_bytes: 0) or {
		panic(err)
	}
	splitter := textsplitter.new_recursive_character_text_splitter(
		chunk_size:     20
		chunk_overlap:  0
		separators:     ['\n\n', '\n', ' ', '']
		keep_separator: false
	) or { panic(err) }
	documents := loader.load_and_split(mut ctx, splitter) or { panic(err) }
	assert documents.len >= 2
	for document in documents {
		assert (document.metadata['row'] or { panic('missing row metadata') }).int() == 1
	}
}

fn test_csv_loader_preflights_split_document_budget() {
	mut ctx := context.background()
	loader := new_csv_loader('name\nJane Doe', max_split_input_bytes: 1) or { panic(err) }
	splitter := textsplitter.new_recursive_character_text_splitter(
		chunk_size:     1
		chunk_overlap:  0
		separators:     ['']
		keep_separator: false
	) or { panic(err) }
	loader.load_and_split(mut ctx, splitter) or {
		assert err.msg().contains('split input exceeds the 1-byte safety limit')
		return
	}
	assert false, 'expected split input budget to be enforced before allocation'
}
