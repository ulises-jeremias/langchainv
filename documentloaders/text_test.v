module documentloaders

import context
import os

fn fixture_path() string {
	return os.join_path(os.dir(@FILE), 'fixtures', 'hello.txt')
}

fn test_text_loader_reads_document_and_source() {
	mut ctx := context.background()
	loader := new_text_loader(fixture_path(), 0) or { panic(err) }
	documents := loader.load(mut ctx) or { panic(err) }
	assert documents.len == 1
	assert documents[0].page_content == 'Hello from LangChainV.\n'
	assert documents[0].metadata['source'].str() == fixture_path()
}

fn test_text_loader_rejects_oversized_file() {
	mut ctx := context.background()
	loader := new_text_loader(fixture_path(), 4) or { panic(err) }
	loader.load(mut ctx) or {
		assert err.msg().contains('above the 4-byte limit')
		return
	}
	assert false, 'expected the file size limit to be enforced'
}

fn test_text_loader_rejects_invalid_limits() {
	new_text_loader(fixture_path(), -1) or {
		assert err.msg().contains('cannot be negative')
		return
	}
	assert false, 'expected negative size to fail'
}
