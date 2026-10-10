// Package documentloaders reads source data into shared document values.
module documentloaders

import context
import json2
import net.html
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.textsplitter

const default_max_html_bytes = i64(16 * 1024 * 1024)
const max_html_documents = 10_000

// HTMLLoader parses bounded HTML text into one plain-text document.
pub struct HTMLLoader {
	data      string
	max_bytes i64
}

// new_html_loader constructs an HTML loader. A zero limit selects 16 MiB.
pub fn new_html_loader(data string, max_bytes i64) !HTMLLoader {
	if max_bytes < 0 {
		return error('maximum HTML size cannot be negative')
	}
	limit := if max_bytes == 0 { default_max_html_bytes } else { max_bytes }
	if i64(data.len) > limit {
		return error('HTML data is ${data.len} bytes, above the ${limit}-byte limit')
	}
	return HTMLLoader{
		data:      data
		max_bytes: limit
	}
}

// load parses HTML and returns body text when a body exists, otherwise the
// document text. It checks cancellation before parsing and enforces the input
// limit again at use time.
pub fn (loader HTMLLoader) load(mut ctx context.Context) ![]schema.Document {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	if loader.max_bytes <= 0 || i64(loader.data.len) > loader.max_bytes {
		return error('HTML data exceeds the configured size limit')
	}
	dom := html.parse(loader.data)
	root := dom.get_root()
	body := root.get_tag('body') or { root }
	return [schema.Document{
		page_content: body.text().trim_space()
		metadata:     map[string]json2.Any{}
	}]
}

// load_and_split parses HTML and splits its text into bounded documents.
pub fn (loader HTMLLoader) load_and_split(mut ctx context.Context, splitter textsplitter.BoundedTextSplitter) ![]schema.Document {
	documents := loader.load(mut ctx)!
	mut result := []schema.Document{}
	for document in documents {
		ctx_error := ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
		chunks := splitter.split_text_bounded(document.page_content, max_html_documents,
			int(loader.max_bytes), loader.max_bytes)!
		for chunk in chunks {
			result << schema.Document{
				page_content: chunk
				metadata:     document.metadata.clone()
			}
		}
	}
	return result
}
