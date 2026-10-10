module documentloaders

import context
import os
import ulises_jeremias.langchainv.textsplitter

fn create_directory_loader_fixture() !string {
	root := os.join_path(os.temp_dir(), 'langchainv-directory-loader-${os.getpid()}')
	os.rmdir_all(root) or {}
	os.mkdir_all(os.join_path(root, 'first', 'deep'))!
	os.write_file(os.join_path(root, 'root.txt'), 'root text')!
	os.write_file(os.join_path(root, 'first', 'nested.md'), 'nested markdown')!
	os.write_file(os.join_path(root, 'first', 'deep', 'deep.txt'), 'deep text')!
	os.write_file(os.join_path(root, 'ignored.bin'), 'ignored')!
	return root
}

fn test_recursive_directory_loader_reads_root_and_one_nested_level() {
	root := create_directory_loader_fixture() or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	loader := new_recursive_directory_loader(root: root) or { panic(err) }
	mut ctx := context.background()
	documents := loader.load(mut ctx) or { panic(err) }
	assert documents.len == 2
	mut contents := []string{}
	for document in documents {
		contents << document.page_content
		assert (document.metadata['source'] or { panic('missing source metadata') }).str().starts_with(root)
	}
	assert contents.contains('root text')
	assert contents.contains('nested markdown')
	assert !contents.contains('deep text')
}

fn test_recursive_directory_loader_filters_extensions_case_insensitively() {
	root := create_directory_loader_fixture() or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	os.write_file(os.join_path(root, 'only.CsV'), 'name,ignored\nAda,value') or { panic(err) }
	loader := new_recursive_directory_loader(
		root:               root
		allowed_extensions: [' CSV ']
		csv_columns:        ['name']
	) or {
		panic(err)
	}
	mut ctx := context.background()
	documents := loader.load(mut ctx) or { panic(err) }
	assert documents.len == 1
	assert documents[0].page_content == 'name: Ada'
	assert (documents[0].metadata['source'] or { panic('missing source metadata') }).str().ends_with('only.CsV')
}

fn test_recursive_directory_loader_enforces_entry_limit() {
	root := create_directory_loader_fixture() or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	mut ctx := context.background()
	entry_limited := new_recursive_directory_loader(root: root, max_entries: 1) or { panic(err) }
	entry_limited.load(mut ctx) or {
		assert err.msg().contains('1-entry limit')
		return
	}
	assert false, 'expected directory entry count to be bounded'
}

fn test_recursive_directory_loader_enforces_document_limit() {
	root := create_directory_loader_fixture() or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	document_limited := new_recursive_directory_loader(root: root, max_documents: 1) or {
		panic(err)
	}
	mut ctx := context.background()
	document_limited.load(mut ctx) or {
		assert err.msg().contains('1-document limit')
		return
	}
	assert false, 'expected directory document count to be bounded'
}

fn test_recursive_directory_loader_can_limit_depth_to_root() {
	root := create_directory_loader_fixture() or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	loader := new_recursive_directory_loader(root: root, max_depth: 0) or { panic(err) }
	mut ctx := context.background()
	documents := loader.load(mut ctx) or { panic(err) }
	assert documents.len == 1
	assert documents[0].page_content == 'root text'
}

fn test_recursive_directory_loader_splits_and_preserves_source_metadata() {
	root := create_directory_loader_fixture() or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	loader := new_recursive_directory_loader(root: root) or { panic(err) }
	splitter := textsplitter.new_recursive_character_text_splitter(
		chunk_size:    4
		chunk_overlap: 0
		separators:    ['']
	) or { panic(err) }
	mut ctx := context.background()
	documents := loader.load_and_split(mut ctx, splitter) or { panic(err) }
	assert documents.len > 2
	for document in documents {
		assert (document.metadata['source'] or { panic('missing source metadata') }).str().starts_with(root)
	}
}

fn test_recursive_directory_loader_preflights_split_input_bytes() {
	root := create_directory_loader_fixture() or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	loader := new_recursive_directory_loader(root: root, max_split_input_bytes: 1) or {
		panic(err)
	}
	splitter := textsplitter.new_recursive_character_text_splitter() or { panic(err) }
	mut ctx := context.background()
	loader.load_and_split(mut ctx, splitter) or {
		assert err.msg().contains('split input exceeds the 1-byte safety limit')
		return
	}
	assert false, 'expected split input limit to be enforced'
}

fn test_recursive_directory_loader_rejects_invalid_roots_and_limits() {
	new_recursive_directory_loader(root: '/path/that/does/not/exist') or {
		assert err.msg().contains('is not a directory')
		return
	}
	assert false, 'expected an invalid root to fail'
}
