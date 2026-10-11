// Package documentloaders reads source data into shared document values.
module documentloaders

import context
import json2
import os
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.textsplitter

const default_directory_max_depth = 1
const default_directory_max_entries = 10_000
const default_directory_max_documents = 10_000
const default_directory_max_file_bytes = i64(16 * 1024 * 1024)
const default_directory_max_split_input_bytes = 16 * 1024
const default_directory_max_input_bytes = i64(64 * 1024 * 1024)
const default_directory_max_output_bytes = i64(64 * 1024 * 1024)
const supported_directory_extensions = ['.txt', '.md', '.csv', '.html', '.htm']

// RecursiveDirectoryLoaderOptions configures traversal and aggregate bounds.
@[params]
pub struct RecursiveDirectoryLoaderOptions {
pub:
	root                  string = '.'
	max_depth             int    = default_directory_max_depth
	allowed_extensions    []string
	csv_columns           []string
	max_entries           int = default_directory_max_entries
	max_documents         int = default_directory_max_documents
	max_file_bytes        i64 = default_directory_max_file_bytes
	max_split_input_bytes int = default_directory_max_split_input_bytes
	max_input_bytes       i64 = default_directory_max_input_bytes
	max_output_bytes      i64 = default_directory_max_output_bytes
}

// RecursiveDirectoryLoader reads supported files from a directory tree.
pub struct RecursiveDirectoryLoader {
	root                  string
	max_depth             int
	allowed_extensions    []string
	csv_columns           []string
	max_entries           int
	max_documents         int
	max_file_bytes        i64
	max_split_input_bytes int
	max_input_bytes       i64
	max_output_bytes      i64
}

struct DirectoryFrame {
	path  string
	depth int
}

// new_recursive_directory_loader constructs a loader with bounded traversal.
// It reads at most 10,000 entries/documents, 16 MiB per file, and 64 MiB total
// input/output by default. A depth of 1 includes files in the root and its
// immediate subdirectories.
pub fn new_recursive_directory_loader(options RecursiveDirectoryLoaderOptions) !RecursiveDirectoryLoader {
	if options.root.trim_space() == '' {
		return error('directory loader root cannot be empty')
	}
	if options.max_depth < 0 {
		return error('maximum directory depth cannot be negative')
	}
	if options.max_entries < 0 {
		return error('maximum directory entry count cannot be negative')
	}
	if options.max_documents < 0 {
		return error('maximum directory document count cannot be negative')
	}
	if options.max_file_bytes < 0 || options.max_split_input_bytes < 0 || options.max_input_bytes < 0
		|| options.max_output_bytes < 0 {
		return error('directory byte limits cannot be negative')
	}
	root := os.real_path(os.abs_path(options.root))
	if !os.is_dir(root) {
		return error('directory loader root `${options.root}` is not a directory')
	}
	mut allowed_extensions := []string{}
	for extension in options.allowed_extensions {
		normalized := normalize_directory_extension(extension)
		if normalized == '' {
			return error('allowed directory extensions cannot be empty')
		}
		if !supported_directory_extensions.contains(normalized) {
			return error('directory loader does not support `${normalized}` files')
		}
		if !allowed_extensions.contains(normalized) {
			allowed_extensions << normalized
		}
	}
	return RecursiveDirectoryLoader{
		root:                  root
		max_depth:             options.max_depth
		allowed_extensions:    allowed_extensions
		csv_columns:           options.csv_columns.clone()
		max_entries:           if options.max_entries == 0 {
			default_directory_max_entries
		} else {
			options.max_entries
		}
		max_documents:         if options.max_documents == 0 {
			default_directory_max_documents
		} else {
			options.max_documents
		}
		max_file_bytes:        if options.max_file_bytes == 0 {
			default_directory_max_file_bytes
		} else {
			options.max_file_bytes
		}
		max_split_input_bytes: if options.max_split_input_bytes == 0 {
			default_directory_max_split_input_bytes
		} else {
			options.max_split_input_bytes
		}
		max_input_bytes:       if options.max_input_bytes == 0 {
			default_directory_max_input_bytes
		} else {
			options.max_input_bytes
		}
		max_output_bytes:      if options.max_output_bytes == 0 {
			default_directory_max_output_bytes
		} else {
			options.max_output_bytes
		}
	}
}

fn normalize_directory_extension(extension string) string {
	mut normalized := extension.trim_space().to_lower()
	if normalized == '' {
		return ''
	}
	if !normalized.starts_with('.') {
		normalized = '.' + normalized
	}
	return normalized
}

fn (loader RecursiveDirectoryLoader) load_supported_file(path string, extension string, mut ctx context.Context, max_documents int, max_output_bytes i64) ![]schema.Document {
	if extension == '.csv' {
		csv_text := os.read_file(path) or {
			return error('failed to read `${path}`: ${err}')
		}
		csv_output_limit := if max_output_bytes <= 0 { i64(1) } else { max_output_bytes }
		csv_loader := new_csv_loader(csv_text,
			max_bytes:        loader.max_file_bytes
			columns:          loader.csv_columns
			max_documents:    max_documents
			max_output_bytes: csv_output_limit
		) or { return error('failed to load `${path}`: ${err}') }
		return csv_loader.load(mut ctx) or { return error('failed to load `${path}`: ${err}') }
	}
	file_size := os.file_size(path)
	if file_size > u64(max_output_bytes) {
		return error('file `${path}` exceeds the remaining directory output-byte budget')
	}
	if extension in ['.html', '.htm'] {
		html_text := os.read_file(path) or {
			return error('failed to read `${path}`: ${err}')
		}
		html_loader := new_html_loader(html_text, loader.max_file_bytes) or {
			return error('failed to load `${path}`: ${err}')
		}
		return html_loader.load(mut ctx) or { return error('failed to load `${path}`: ${err}') }
	}
	text_loader := new_text_loader(path, loader.max_file_bytes) or {
		return error('failed to load `${path}`: ${err}')
	}
	return text_loader.load(mut ctx) or { return error('failed to load `${path}`: ${err}') }
}

// load walks supported text, CSV, and HTML files, attaching paths as source
// metadata. Symlinks and unsupported file types are skipped.
pub fn (loader RecursiveDirectoryLoader) load(mut ctx context.Context) ![]schema.Document {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	mut pending := [DirectoryFrame{
		path:  loader.root
		depth: 0
	}]
	mut documents := []schema.Document{}
	mut files := []string{}
	mut entries_seen := 0
	mut input_bytes := i64(0)
	mut output_bytes := i64(0)
	for pending.len > 0 {
		cancel_error := ctx.err()
		if cancel_error !is none {
			return cancel_error
		}
		frame := pending.pop()
		mut names := os.ls(frame.path) or {
			return error('failed to list directory `${frame.path}`: ${err}')
		}
		if names.len > loader.max_entries - entries_seen {
			return error('directory traversal exceeds the ${loader.max_entries}-entry limit')
		}
		entries_seen += names.len
		names.sort()
		for name in names {
			path := os.join_path(frame.path, name)
			if os.is_link(path) {
				continue
			}
			if os.is_dir(path) {
				if frame.depth < loader.max_depth {
					pending << DirectoryFrame{
						path:  path
						depth: frame.depth + 1
					}
				}
				continue
			}
			if !os.is_file(path) {
				continue
			}
			extension := os.file_ext(path).to_lower()
			if !supported_directory_extensions.contains(extension) {
				continue
			}
			if loader.allowed_extensions.len > 0 && !loader.allowed_extensions.contains(extension) {
				continue
			}
			file_size := os.file_size(path)
			if file_size > u64(loader.max_file_bytes) {
				return error('file `${path}` is ${file_size} bytes, above the ${loader.max_file_bytes}-byte per-file limit')
			}
			if input_bytes + i64(file_size) > loader.max_input_bytes {
				return error('directory input exceeds the ${loader.max_input_bytes}-byte limit')
			}
			input_bytes += i64(file_size)
			files << path
		}
	}
	files.sort()
	for path in files {
		cancel_error := ctx.err()
		if cancel_error !is none {
			return cancel_error
		}
		remaining_documents := loader.max_documents - documents.len
		if remaining_documents <= 0 {
			return error('directory document count exceeds the ${loader.max_documents}-document limit')
		}
		remaining_output_bytes := loader.max_output_bytes - output_bytes
		extension := os.file_ext(path).to_lower()
		loaded := loader.load_supported_file(path, extension, mut ctx, remaining_documents,
			remaining_output_bytes)!
		if loaded.len > loader.max_documents - documents.len {
			return error('directory document count exceeds the ${loader.max_documents}-document limit')
		}
		for document in loaded {
			if output_bytes + i64(document.page_content.len) > loader.max_output_bytes {
				return error('directory output exceeds the ${loader.max_output_bytes}-byte limit')
			}
			output_bytes += i64(document.page_content.len)
			mut metadata := map[string]json2.Any{}
			for key, value in document.metadata {
				metadata[key] = value
			}
			metadata['source'] = json2.Any(path)
			documents << schema.Document{
				page_content: document.page_content
				metadata:     metadata
				score:        document.score
			}
		}
	}
	return documents
}

// load_and_split loads supported files and splits them within the configured
// per-document input, aggregate chunk-count, and output-byte limits.
pub fn (loader RecursiveDirectoryLoader) load_and_split(mut ctx context.Context, splitter textsplitter.BoundedTextSplitter) ![]schema.Document {
	documents := loader.load(mut ctx)!
	mut results := []schema.Document{}
	mut output_bytes := i64(0)
	for document in documents {
		ctx_error := ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
		remaining_documents := loader.max_documents - results.len
		remaining_output_bytes := loader.max_output_bytes - output_bytes
		chunks := splitter.split_text_bounded(document.page_content, remaining_documents,
			loader.max_split_input_bytes, remaining_output_bytes)!
		for chunk in chunks {
			if results.len >= loader.max_documents {
				return error('directory split documents exceed the ${loader.max_documents}-document limit')
			}
			if output_bytes + i64(chunk.len) > loader.max_output_bytes {
				return error('split directory output exceeds the ${loader.max_output_bytes}-byte limit')
			}
			output_bytes += i64(chunk.len)
			mut metadata := map[string]json2.Any{}
			for key, value in document.metadata {
				metadata[key] = value
			}
			results << schema.Document{
				page_content: chunk
				metadata:     metadata
				score:        document.score
			}
		}
	}
	return results
}
