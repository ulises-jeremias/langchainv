// Package documentloaders reads source data into shared document values.
module documentloaders

import context
import json2
import os
import ulises_jeremias.langchainv.schema

const default_max_text_bytes = i64(16 * 1024 * 1024)

// Loader loads documents while honoring request cancellation.
pub interface Loader {
	load(mut ctx context.Context) ![]schema.Document
}

// TextLoader loads one UTF-8 text file as a document.
pub struct TextLoader {
max_bytes i64 = default_max_text_bytes
pub:
	path string
}

// new_text_loader creates a loader with a bounded read size. A zero limit uses
// the 16 MiB default.
pub fn new_text_loader(path string, max_bytes i64) !TextLoader {
	if path.trim_space() == '' {
		return error('text loader path cannot be empty')
	}
	if max_bytes < 0 {
		return error('maximum text size cannot be negative')
	}
	return TextLoader{
		path:      path
		max_bytes: if max_bytes == 0 { default_max_text_bytes } else { max_bytes }
	}
}

// load reads the file only after checking cancellation and its size.
pub fn (loader TextLoader) load(mut ctx context.Context) ![]schema.Document {
	if err := ctx.err() {
		return err
	}
	if loader.max_bytes <= 0 {
		return error('maximum text size must be greater than zero')
	}
	size := os.file_size(loader.path)
	if size > u64(loader.max_bytes) {
		return error('text file is ${size} bytes, above the ${loader.max_bytes}-byte limit')
	}
	content := os.read_file(loader.path)!
	mut metadata := map[string]json2.Any{}
	metadata['source'] = json2.Any(loader.path)
	return [schema.Document{
		page_content: content
		metadata:     metadata
	}]
}
