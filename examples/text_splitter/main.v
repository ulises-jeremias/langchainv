module main

import ulises_jeremias.langchainv.textsplitter

fn main() {
	text := 'LangChainV splits long text into overlapping chunks.\n\nParagraph boundaries are preferred, then lines and words. Unicode code points remain intact.'
	splitter := textsplitter.new_recursive_character_text_splitter(
		chunk_size:    48
		chunk_overlap: 10
	) or { panic(err) }
	chunks := splitter.split_text(text) or { panic(err) }
	for index, chunk in chunks {
		println('Chunk ${index + 1}: ${chunk}')
	}

	markdown := '# Retrieval notes\n\nVector stores index meaningful sections, not arbitrary byte ranges.'
	markdown_splitter := textsplitter.new_markdown_text_splitter(
		chunk_size:             96
		chunk_overlap:          12
		keep_heading_hierarchy: true
	) or { panic(err) }
	for index, chunk in markdown_splitter.split_text(markdown) or { panic(err) } {
		println('Markdown chunk ${index + 1}: ${chunk}')
	}
}
