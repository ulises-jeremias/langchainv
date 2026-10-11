// Package chains provides bounded retrieval-augmented question answering.
module chains

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema

const default_retrieval_k = 4
const max_retrieval_documents = 128
const max_retrieval_context_bytes = 1048576
const max_retrieval_prompt_bytes = 2097152

// RetrievalQAOptions configures retrieval, prompt keys, context limits, and memory.
pub struct RetrievalQAOptions {
pub:
	question_key            string = 'question'
	document_key            string = 'context'
	output_key              string = 'answer'
	source_documents_key    string = 'source_documents'
	return_source_documents bool
	document_separator      string = '\n\n'
	retrieval               schema.RetrievalOptions
	max_documents           int = 16
	max_context_bytes       int = 65536
	max_prompt_bytes        int = 131072
	call_options            llms.CallOptions
	memory                  ?schema.Memory
}

// RetrievalQAChain retrieves documents, combines their content, and answers with a completion model.
pub struct RetrievalQAChain {
	retriever               schema.Retriever
	model                   llms.CompletionModel
	prompt                  prompts.StringTemplate
	question_key            string
	document_key            string
	output_key              string
	source_documents_key    string
	return_source_documents bool
	document_separator      string
	retrieval               schema.RetrievalOptions
	max_documents           int
	max_context_bytes       int
	max_prompt_bytes        int
	call_options            llms.CallOptions
	memory_store            ?schema.Memory
mut:
	keys []string
}

// new_retrieval_qa_chain constructs a bounded retriever-to-completion chain.
pub fn new_retrieval_qa_chain(retriever schema.Retriever, model llms.CompletionModel, prompt prompts.StringTemplate, options RetrievalQAOptions) !RetrievalQAChain {
	if options.question_key.trim_space() == '' || options.document_key.trim_space() == ''
		|| options.output_key.trim_space() == '' || options.question_key == options.document_key
		|| options.question_key == options.output_key || options.document_key == options.output_key {
		return error('retrieval QA question, document, and output keys must be non-empty and distinct')
	}
	if options.return_source_documents && (options.source_documents_key.trim_space() == ''
		|| options.source_documents_key in [options.question_key, options.document_key,
			options.output_key]) {
		return error('retrieval QA source document key must be non-empty and distinct')
	}
	if options.max_documents <= 0 || options.max_documents > max_retrieval_documents {
		return error('retrieval QA max_documents is outside the supported range 1..128')
	}
	if options.max_context_bytes <= 0 || options.max_context_bytes > max_retrieval_context_bytes {
		return error('retrieval QA max_context_bytes is outside the supported range 1..1048576')
	}
	if options.max_prompt_bytes <= 0 || options.max_prompt_bytes > max_retrieval_prompt_bytes {
		return error('retrieval QA max_prompt_bytes is outside the supported range 1..2097152')
	}
	mut keys := prompt.input_variables()!
	if options.question_key !in keys || options.document_key !in keys {
		return error('retrieval QA prompt must include question and document variables')
	}
	keys.delete(keys.index(options.document_key))
	mut retrieval := options.retrieval
	if retrieval.k <= 0 {
		retrieval.k = if default_retrieval_k < options.max_documents {
			default_retrieval_k
		} else {
			options.max_documents
		}
	} else if retrieval.k > options.max_documents {
		return error('retrieval QA k cannot exceed max_documents')
	}
	return RetrievalQAChain{
		retriever:               retriever
		model:                   model
		prompt:                  prompt
		question_key:            options.question_key
		document_key:            options.document_key
		output_key:              options.output_key
		source_documents_key:    options.source_documents_key
		return_source_documents: options.return_source_documents
		document_separator:      options.document_separator
		retrieval:               retrieval
		max_documents:           options.max_documents
		max_context_bytes:       options.max_context_bytes
		max_prompt_bytes:        options.max_prompt_bytes
		call_options:            options.call_options
		memory_store:            options.memory
		keys:                    keys
	}
}

// call retrieves and bounds context before rendering the prompt.
pub fn (chain RetrievalQAChain) call(mut ctx context.Context, inputs map[string]json2.Any) !map[string]json2.Any {
	chain.call_options.validate()!
	query_value := inputs[chain.question_key] or { return error('missing retrieval QA question') }
	query := match query_value {
		string {
			query_value
		}
		else {
			return error('retrieval QA question must be a string')
		}
	}
	documents := chain.retriever.get_relevant_documents(mut ctx, query, chain.retrieval)!
	if documents.len > chain.max_documents {
		return error('retriever returned more documents than the configured limit')
	}
	mut contents := []string{cap: documents.len}
	mut context_bytes := 0
	for document in documents {
		separator_bytes := if contents.len > 0 { chain.document_separator.len } else { 0 }
		remaining_bytes := chain.max_context_bytes - context_bytes
		if document.page_content.len > remaining_bytes
			|| separator_bytes > remaining_bytes - document.page_content.len {
			return error('retrieved context exceeds the configured byte limit')
		}
		context_bytes += separator_bytes + document.page_content.len
		contents << document.page_content
	}
	mut prompt_values := inputs.clone()
	prompt_values[chain.document_key] = json2.Any(contents.join(chain.document_separator))
	formatted_prompt := chain.prompt.format(prompt_values)!
	if formatted_prompt.len > chain.max_prompt_bytes {
		return error('formatted retrieval QA prompt exceeds the configured byte limit')
	}
	answer := chain.model.complete(mut ctx, formatted_prompt, chain.call_options)!
	mut outputs := {
		chain.output_key: json2.Any(answer)
	}
	if chain.return_source_documents {
		mut source_documents := []json2.Any{cap: documents.len}
		for document in documents {
			source_documents << json2.Any({
				'page_content': json2.Any(document.page_content)
				'metadata':     json2.Any(document.metadata.clone())
				'score':        json2.Any(document.score)
			})
		}
		outputs[chain.source_documents_key] = json2.Any(source_documents)
	}
	return outputs
}

// memory returns the optional memory configured on this chain.
pub fn (chain RetrievalQAChain) memory() ?schema.Memory {
	return chain.memory_store
}

// input_keys returns caller-supplied prompt variables, excluding retrieved context.
pub fn (chain RetrievalQAChain) input_keys() []string {
	return chain.keys.clone()
}

// output_keys returns the answer key.
pub fn (chain RetrievalQAChain) output_keys() []string {
	if chain.return_source_documents {
		return [chain.output_key, chain.source_documents_key]
	}
	return [chain.output_key]
}
