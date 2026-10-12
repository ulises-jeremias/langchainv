module documentloaders

import context
import ulises_jeremias.langchainv.textsplitter

fn test_html_loader_uses_body_text_and_decodes_entities() {
	loader := new_html_loader('<html><head><title>ignored</title></head><body><h1>Hello</h1><p>A &amp; B</p></body></html>', 0) or {
		panic(err)
	}
	mut ctx := context.background()
	documents := loader.load(mut ctx) or { panic(err) }
	assert documents.len == 1
	assert documents[0].page_content == 'HelloA & B'
	assert documents[0].metadata.len == 0
}

fn test_html_loader_falls_back_to_document_text_and_splits() {
	loader := new_html_loader('<p>one two three four</p>', 0) or { panic(err) }
	splitter := textsplitter.new_recursive_character_text_splitter(
		chunk_size:    7
		chunk_overlap: 0
		separators:    [' ', '']
	) or { panic(err) }
	mut ctx := context.background()
	documents := loader.load_and_split(mut ctx, splitter) or { panic(err) }
	assert documents.len >= 2
	assert documents.map(it.page_content).join(' ') == 'one two three four'
}

fn test_html_loader_rejects_oversized_input_and_negative_limit() {
	new_html_loader('<p>large</p>', 4) or {
		assert err.msg().contains('above the 4-byte limit')
		return
	}
	assert false, 'expected oversized HTML to fail'
	new_html_loader('', -1) or {
		assert err.msg().contains('cannot be negative')
		return
	}
	assert false, 'expected a negative limit to fail'
}
