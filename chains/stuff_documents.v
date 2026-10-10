// Package chains combines documents before passing them to an LLM chain.
module chains

import context
import json2
import ulises_jeremias.langchainv.schema

const default_stuff_documents_key = 'input_documents'
const default_stuff_document_variable = 'context'
const default_stuff_separator = '\n\n'
const max_stuff_documents = 128
const max_stuff_document_bytes = 1048576

// StuffDocumentsOptions controls document inputs, prompt variable, and limits.
pub struct StuffDocumentsOptions {
pub:
	input_key            string = default_stuff_documents_key
	document_variable    string = default_stuff_document_variable
	separator            string = default_stuff_separator
	max_documents        int    = 16
	max_document_bytes   int    = 65536
}

// StuffDocumentsChain joins bounded documents and calls an LLMChain.
pub struct StuffDocumentsChain {
	llm_chain LLMChain
pub:
	options StuffDocumentsOptions
mut:
	keys []string
}

// new_stuff_documents_chain creates a bounded document-combination chain.
pub fn new_stuff_documents_chain(llm_chain LLMChain, options StuffDocumentsOptions) !StuffDocumentsChain {
	if options.input_key.trim_space() == '' || options.document_variable.trim_space() == ''
		|| options.input_key == options.document_variable {
		return error('stuff documents input and document variable keys must be non-empty and distinct')
	}
	if options.max_documents <= 0 || options.max_documents > max_stuff_documents {
		return error('stuff documents max_documents must be between 1 and 128')
	}
	if options.max_document_bytes <= 0 || options.max_document_bytes > max_stuff_document_bytes {
		return error('stuff documents max_document_bytes must be between 1 and 1048576')
	}
	mut keys := [options.input_key]
	for key in llm_chain.input_keys() {
		if key != options.document_variable {
			if key == options.input_key {
				return error('stuff documents input key conflicts with an LLM prompt variable')
			}
			keys << key
		}
	}
	return StuffDocumentsChain{
		llm_chain: llm_chain
		options:   options
		keys:      keys
	}
}

// documents_value converts documents to the JSON-compatible chain input form.
pub fn documents_value(documents []schema.Document) json2.Any {
	mut values := []json2.Any{cap: documents.len}
	for document in documents {
		values << json2.Any({
			'page_content': json2.Any(document.page_content)
			'metadata':     json2.Any(document.metadata.clone())
		})
	}
	return json2.Any(values)
}

// call joins the document page content and invokes the configured LLM chain.
pub fn (chain StuffDocumentsChain) call(mut ctx context.Context, inputs map[string]json2.Any) !map[string]json2.Any {
	chain.llm_chain.options.validate()!
	document_value := inputs[chain.options.input_key] or {
		return error('missing stuff documents input `${chain.options.input_key}`')
	}
	if document_value !is []json2.Any {
		return error('stuff documents input must be an array of document objects')
	}
	documents := document_value as []json2.Any
	if documents.len > chain.options.max_documents {
		return error('stuff documents input exceeds the configured document count limit')
	}
	mut contents := []string{cap: documents.len}
	mut combined_bytes := 0
	for index, value in documents {
		if value !is map[string]json2.Any {
			return error('stuff documents item ${index} must be a document object')
		}
		item := value as map[string]json2.Any
		page_content_value := item['page_content'] or {
			return error('stuff documents item ${index} is missing page_content')
		}
		if page_content_value !is string {
			return error('stuff documents item ${index} page_content must be a string')
		}
		page_content := page_content_value as string
		separator_bytes := if contents.len > 0 { chain.options.separator.len } else { 0 }
		remaining_bytes := chain.options.max_document_bytes - combined_bytes
		if page_content.len > remaining_bytes || separator_bytes > remaining_bytes - page_content.len {
			return error('combined stuff documents exceed the configured byte limit')
		}
		combined_bytes += page_content.len + separator_bytes
		contents << page_content
	}
	mut values := inputs.clone()
	values[chain.options.document_variable] = json2.Any(contents.join(chain.options.separator))
	values.delete(chain.options.input_key)
	return chain.llm_chain.call(mut ctx, values)
}

// memory returns the inner LLM chain's optional memory.
pub fn (chain StuffDocumentsChain) memory() ?schema.Memory {
	return chain.llm_chain.memory()
}

// input_keys returns the document input and other prompt variables.
pub fn (chain StuffDocumentsChain) input_keys() []string {
	return chain.keys.clone()
}

// output_keys returns the outputs declared by the inner LLM chain.
pub fn (chain StuffDocumentsChain) output_keys() []string {
	return chain.llm_chain.output_keys()
}
