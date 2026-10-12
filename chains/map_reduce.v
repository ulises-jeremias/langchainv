// Package chains maps individual documents then reduces their results.
module chains

import context
import json2
import ulises_jeremias.langchainv.schema

const default_map_reduce_documents_key = 'input_documents'
const default_map_reduce_map_variable = 'context'
const default_map_reduce_reduce_variable = 'input_documents'
const default_map_reduce_max_documents = 128
const default_map_reduce_max_bytes = 1048576
const map_reduce_intermediate_steps_key = 'intermediate_steps'

// MapReduceDocumentsOptions configures the inputs, limits, memory and outputs.
pub struct MapReduceDocumentsOptions {
pub:
	input_key                 string = default_map_reduce_documents_key
	map_document_variable     string = default_map_reduce_map_variable
	reduce_document_variable  string = default_map_reduce_reduce_variable
	max_documents             int    = 16
	max_document_bytes        int    = 65536
	return_intermediate_steps bool
	memory                    ?schema.Memory
}

// MapReduceDocumentsChain applies an LLMChain to each document, then reduces.
pub struct MapReduceDocumentsChain {
	map_chain    LLMChain
	reduce_chain Chain
pub:
	options MapReduceDocumentsOptions
mut:
	map_variable    string
	reduce_variable string
	keys            []string
	outputs         []string
	memory_store    ?schema.Memory
}

// new_map_reduce_documents_chain builds a bounded sequential map/reduce chain.
pub fn new_map_reduce_documents_chain(map_chain LLMChain, reduce_chain Chain, options MapReduceDocumentsOptions) !MapReduceDocumentsChain {
	if options.input_key.trim_space() == '' {
		return error('map-reduce input key must not be empty')
	}
	if options.max_documents <= 0 || options.max_documents > default_map_reduce_max_documents {
		return error('map-reduce max_documents must be between 1 and 128')
	}
	if options.max_document_bytes <= 0 || options.max_document_bytes > default_map_reduce_max_bytes {
		return error('map-reduce max_document_bytes must be between 1 and 1048576')
	}
	map_variable := select_document_variable(options.map_document_variable, map_chain.input_keys())!
	reduce_variable := select_document_variable(options.reduce_document_variable, reduce_chain.input_keys())!
	if options.input_key in map_chain.input_keys() && options.input_key != map_variable {
		return error('map-reduce input key conflicts with a map-chain variable')
	}
	if options.input_key in reduce_chain.input_keys() && options.input_key != reduce_variable {
		return error('map-reduce input key conflicts with a reducer variable')
	}
	mut keys := [options.input_key]
	for key in map_chain.input_keys() {
		if key != map_variable {
			append_unique_chain_key(mut keys, key)
		}
	}
	for key in reduce_chain.input_keys() {
		if key != reduce_variable {
			append_unique_chain_key(mut keys, key)
		}
	}
	mut outputs := reduce_chain.output_keys()
	if outputs.len == 0 {
		return error('map-reduce reducer must declare at least one output')
	}
	if options.return_intermediate_steps {
		if map_reduce_intermediate_steps_key in outputs {
			return error('map-reduce intermediate steps key conflicts with reducer output')
		}
		outputs << map_reduce_intermediate_steps_key
	}
	mut memory_store := reduce_chain.memory()
	if memory := options.memory {
		memory_store = memory
	}
	return MapReduceDocumentsChain{
		map_chain:       map_chain
		reduce_chain:    reduce_chain
		options:         options
		map_variable:    map_variable
		reduce_variable: reduce_variable
		keys:            keys
		outputs:         outputs
		memory_store:    memory_store
	}
}

fn select_document_variable(preferred string, keys []string) !string {
	if keys.len == 0 {
		return error('map-reduce child chain must declare input variables')
	}
	if keys.len == 1 {
		return keys[0]
	}
	if preferred.trim_space() == '' || preferred !in keys {
		return error('map-reduce document variable `${preferred}` is not an input of its child chain')
	}
	return preferred
}

fn append_unique_chain_key(mut keys []string, key string) {
	if key !in keys {
		keys << key
	}
}

fn copy_chain_values(values map[string]json2.Any) map[string]json2.Any {
	mut copied := map[string]json2.Any{}
	for key, value in values {
		copied[key] = value
	}
	return copied
}

fn read_map_reduce_documents(value json2.Any, max_documents int, max_bytes int) ![]schema.Document {
	if value !is []json2.Any {
		return error('map-reduce input must be an array of document objects')
	}
	items := value as []json2.Any
	if items.len > max_documents {
		return error('map-reduce input exceeds the configured document count limit')
	}
	mut documents := []schema.Document{cap: items.len}
	mut total_bytes := 0
	for index, item_value in items {
		if item_value !is map[string]json2.Any {
			return error('map-reduce document ${index} must be an object')
		}
		item := item_value as map[string]json2.Any
		content_value := item['page_content'] or {
			return error('map-reduce document ${index} is missing page_content')
		}
		if content_value !is string {
			return error('map-reduce document ${index} page_content must be a string')
		}
		content := content_value as string
		if content.len > max_bytes - total_bytes {
			return error('map-reduce documents exceed the configured byte limit')
		}
		total_bytes += content.len
		mut metadata := map[string]json2.Any{}
		if metadata_value := item['metadata'] {
			if metadata_value !is map[string]json2.Any {
				return error('map-reduce document ${index} metadata must be an object')
			}
			metadata = (metadata_value as map[string]json2.Any).clone()
		}
		documents << schema.Document{
			page_content: content
			metadata:     metadata
		}
	}
	return documents
}

// call maps documents in order, then passes the mapped documents to the reducer.
pub fn (chain MapReduceDocumentsChain) call(mut ctx context.Context, inputs map[string]json2.Any) !map[string]json2.Any {
	document_value := inputs[chain.options.input_key] or {
		return error('missing map-reduce input `${chain.options.input_key}`')
	}
	documents := read_map_reduce_documents(document_value, chain.options.max_documents,
		chain.options.max_document_bytes)!
	mut mapped_documents := []schema.Document{cap: documents.len}
	mut intermediate_steps := []json2.Any{cap: documents.len}
	mut mapped_bytes := 0
	for document in documents {
		ctx_error := ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
		mut map_inputs := copy_chain_values(inputs)
		map_inputs.delete(chain.options.input_key)
		map_inputs[chain.map_variable] = json2.Any(document.page_content)
		map_outputs := chain.map_chain.call(mut ctx, map_inputs)!
		mapped_value := map_outputs[chain.map_chain.output_key] or {
			return error('map-reduce map chain did not produce `${chain.map_chain.output_key}`')
		}
		if mapped_value !is string {
			return error('map-reduce map chain output must be a string')
		}
		mapped_content := mapped_value as string
		if mapped_content.len > chain.options.max_document_bytes - mapped_bytes {
			return error('map-reduce outputs exceed the configured byte limit')
		}
		mapped_bytes += mapped_content.len
		mapped_documents << schema.Document{
			page_content: mapped_content
			metadata:     document.metadata.clone()
		}
		if chain.options.return_intermediate_steps {
			intermediate_steps << json2.Any(map_outputs)
		}
	}
	mut reduce_inputs := copy_chain_values(inputs)
	reduce_inputs.delete(chain.options.input_key)
	reduce_inputs[chain.reduce_variable] = documents_value(mapped_documents)
	mut outputs := chain.reduce_chain.call(mut ctx, reduce_inputs)!
	if chain.options.return_intermediate_steps {
		outputs[map_reduce_intermediate_steps_key] = json2.Any(intermediate_steps)
	}
	return outputs
}

// memory returns the configured memory or the reducer's memory.
pub fn (chain MapReduceDocumentsChain) memory() ?schema.Memory {
	return chain.memory_store
}

// input_keys returns the documents and passthrough variables needed by children.
pub fn (chain MapReduceDocumentsChain) input_keys() []string {
	return chain.keys.clone()
}

// output_keys returns reducer outputs and optional map-step results.
pub fn (chain MapReduceDocumentsChain) output_keys() []string {
	return chain.outputs.clone()
}
