// Package chains maps a bounded batch of documents through an LLM chain.
module chains

import context
import json2
import ulises_jeremias.langchainv.schema

const max_document_map_concurrency = 5

struct DocumentMapResult {
	outputs map[string]json2.Any
}

struct IndexedDocumentMapResult {
	index         int
	outputs       map[string]json2.Any
	error_message string
}

fn run_document_map(mut ctx context.Context, chain LLMChain, inputs map[string]json2.Any,
	input_key string, document_variable string, document schema.Document) !map[string]json2.Any {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	mut map_inputs := copy_chain_values(inputs)
	map_inputs.delete(input_key)
	map_inputs[document_variable] = json2.Any(document.page_content)
	return chain.call(mut ctx, map_inputs)
}

fn run_document_map_task(mut ctx context.Context, chain LLMChain, inputs map[string]json2.Any,
	input_key string, document_variable string, document schema.Document, index int,
	results chan IndexedDocumentMapResult) {
	outputs := run_document_map(mut ctx, chain, inputs, input_key, document_variable, document) or {
		results <- IndexedDocumentMapResult{
			index:         index
			error_message: err.msg()
		}
		return
	}
	results <- IndexedDocumentMapResult{
		index:   index
		outputs: outputs
	}
}

fn map_document_batch(mut ctx context.Context, chain LLMChain, inputs map[string]json2.Any,
	input_key string, document_variable string, documents []schema.Document, first_index int,
	max_concurrency int) ![]DocumentMapResult {
	if max_concurrency == 1 {
		outputs := run_document_map(mut ctx, chain, inputs, input_key, document_variable,
			documents[first_index])!
		ctx_error := ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
		return [DocumentMapResult{
			outputs: outputs
		}]
	}
	mut ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	batch_count := if documents.len - first_index < max_concurrency {
		documents.len - first_index
	} else {
		max_concurrency
	}
	result_channel := chan IndexedDocumentMapResult{cap: batch_count}
	mut workers := []thread{cap: batch_count}
	for offset in 0 .. batch_count {
		index := first_index + offset
		document := documents[index]
		worker_context := ctx
		workers << spawn fn [worker_context, chain, inputs, input_key, document_variable, document, index, result_channel] () {
			mut active_context := worker_context
			run_document_map_task(mut active_context, chain, inputs, input_key,
				document_variable, document, index, result_channel)
		}()
	}
	mut results := []DocumentMapResult{len: batch_count}
	mut error_messages := []string{len: batch_count}
	for _ in 0 .. batch_count {
		worker_result := <-result_channel
		offset := worker_result.index - first_index
		results[offset] = DocumentMapResult{
			outputs: worker_result.outputs
		}
		error_messages[offset] = worker_result.error_message
	}
	workers.wait()
	ctx_error = ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	for offset, error_message in error_messages {
		if error_message != '' {
			return error('document ${first_index + offset} mapping failed: ${error_message}')
		}
	}
	return results
}
