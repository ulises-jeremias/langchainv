// Package chains refines a running LLM answer with each successive document.
module chains

import context
import json2
import ulises_jeremias.langchainv.memory
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema

const default_refine_input_key = 'input_documents'
const default_refine_document_variable = 'context'
const default_refine_output_key = 'output'
const default_refine_initial_response_name = 'existing_answer'
const default_refine_document_prompt = '{page_content}'

// RefineDocumentsOptions sets prompt keys and bounds the document work.
pub struct RefineDocumentsOptions {
pub:
	input_key             string = default_refine_input_key
	output_key            string = default_refine_output_key
	document_variable     string = default_refine_document_variable
	initial_response_name string = default_refine_initial_response_name
	document_prompt       prompts.StringTemplate
	max_documents         int = 16
	max_document_bytes    int = 65536
}

// RefineDocumentsChain starts with the first document, then revises the answer.
pub struct RefineDocumentsChain {
	initial_chain LLMChain
	refine_chain  LLMChain
pub:
	options RefineDocumentsOptions
mut:
	keys         []string
	output_keys  []string
	memory_store ?schema.Memory
}

// new_refine_documents_chain creates a bounded document-refinement chain.
pub fn new_refine_documents_chain(initial_chain LLMChain, refine_chain LLMChain, options RefineDocumentsOptions) !RefineDocumentsChain {
	mut configured_options := options
	if configured_options.document_prompt.template.trim_space() == '' {
		configured_options.document_prompt = prompts.StringTemplate{
			template: default_refine_document_prompt
		}
	}
	if options.input_key.trim_space() == '' || options.output_key.trim_space() == ''
		|| options.document_variable.trim_space() == '' || options.initial_response_name.trim_space() == '' {
		return error('refine documents keys must not be empty')
	}
	if options.input_key in [options.output_key, options.document_variable]
		|| options.output_key in [options.document_variable, options.initial_response_name]
		|| options.document_variable == options.initial_response_name {
		return error('refine documents input, output, and prompt keys must be distinct')
	}
	if options.max_documents <= 0 || options.max_documents > default_map_reduce_max_documents {
		return error('refine documents max_documents must be between 1 and 128')
	}
	if options.max_document_bytes <= 0 || options.max_document_bytes > default_map_reduce_max_bytes {
		return error('refine documents max_document_bytes must be between 1 and 1048576')
	}
	initial_keys := initial_chain.input_keys()
	refine_keys := refine_chain.input_keys()
	if options.document_variable !in initial_keys || options.document_variable !in refine_keys {
		return error('refine documents prompt chains must include the document variable')
	}
	if options.initial_response_name !in refine_keys {
		return error('refine documents prompt must include the initial response variable')
	}
	if options.initial_response_name in initial_keys {
		return error('refine initial response variable conflicts with an initial prompt variable')
	}
	mut keys := [options.input_key]
	for key in initial_keys {
		if key != options.document_variable {
			if key == options.input_key {
				return error('refine documents input key conflicts with an initial prompt variable')
			}
			append_unique_chain_key(mut keys, key)
		}
	}
	for key in refine_keys {
		if key !in [options.document_variable, options.initial_response_name] {
			if key == options.input_key {
				return error('refine documents input key conflicts with a refine prompt variable')
			}
			append_unique_chain_key(mut keys, key)
		}
	}
	if options.output_key in keys {
		return error('refine documents output key conflicts with a prompt input')
	}
	configured_options.document_prompt.input_variables()!
	return RefineDocumentsChain{
		initial_chain: initial_chain
		refine_chain:  refine_chain
		options:       configured_options
		keys:          keys
		output_keys:   [options.output_key]
		memory_store:  ?schema.Memory(memory.new_simple_memory())
	}
}

fn format_refine_document(document schema.Document, prompt prompts.StringTemplate) !string {
	mut values := document.metadata.clone()
	values['page_content'] = json2.Any(document.page_content)
	for variable in prompt.input_variables()! {
		if variable !in values {
			return error('refine document is missing metadata `${variable}` used by the document prompt')
		}
	}
	return prompt.format(values)
}

fn prepare_refine_inputs(inputs map[string]json2.Any, input_key string, document_variable string, document_text string) map[string]json2.Any {
	mut result := copy_chain_values(inputs)
	result.delete(input_key)
	result[document_variable] = json2.Any(document_text)
	return result
}

// call initializes an answer from the first document and refines it in order.
pub fn (chain RefineDocumentsChain) call(mut ctx context.Context, inputs map[string]json2.Any) !map[string]json2.Any {
	document_value := inputs[chain.options.input_key] or {
		return error('missing refine documents input `${chain.options.input_key}`')
	}
	documents := read_map_reduce_documents(document_value, chain.options.max_documents,
		chain.options.max_document_bytes)!
	if documents.len == 0 {
		return error('refine documents input must contain at least one document')
	}
	mut document_texts := []string{cap: documents.len}
	mut total_bytes := 0
	for document in documents {
		text := format_refine_document(document, chain.options.document_prompt)!
		if text.len > chain.options.max_document_bytes - total_bytes {
			return error('formatted refine documents exceed the configured byte limit')
		}
		total_bytes += text.len
		document_texts << text
	}
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	mut initial_inputs := prepare_refine_inputs(inputs, chain.options.input_key,
		chain.options.document_variable, document_texts[0])
	initial_outputs := call(mut ctx, chain.initial_chain, initial_inputs)!
	mut response_value := initial_outputs[chain.initial_chain.output_key] or {
		return error('initial refine chain did not produce `${chain.initial_chain.output_key}`')
	}
	if response_value !is string {
		return error('initial refine chain output must be a string')
	}
	mut response := response_value as string
	for index in 1 .. document_texts.len {
		ctx_error := ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
		mut refine_inputs := prepare_refine_inputs(inputs, chain.options.input_key,
			chain.options.document_variable, document_texts[index])
		refine_inputs[chain.options.initial_response_name] = json2.Any(response)
		refine_outputs := call(mut ctx, chain.refine_chain, refine_inputs)!
		response_value = refine_outputs[chain.refine_chain.output_key] or {
			return error('refine chain did not produce `${chain.refine_chain.output_key}`')
		}
		if response_value !is string {
			return error('refine chain output must be a string')
		}
		response = response_value as string
	}
	mut outputs := map[string]json2.Any{}
	outputs[chain.options.output_key] = json2.Any(response)
	return outputs
}

// memory returns the upstream-compatible no-op memory for this chain.
pub fn (chain RefineDocumentsChain) memory() ?schema.Memory {
	return chain.memory_store
}

// input_keys returns caller variables required by both prompts.
pub fn (chain RefineDocumentsChain) input_keys() []string {
	return chain.keys.clone()
}

// output_keys returns the final refined answer key.
pub fn (chain RefineDocumentsChain) output_keys() []string {
	return chain.output_keys.clone()
}
