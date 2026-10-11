// Package chains provides conversational retrieval-augmented QA.
module chains

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema

const default_max_retrieval_history_bytes = 32 * 1024
const max_retrieval_history_bytes = 1024 * 1024
const default_max_standalone_question_bytes = 8192

// ConversationalRetrievalQAOptions bounds and configures query rewriting.
pub struct ConversationalRetrievalQAOptions {
pub:
	retrieval_qa          RetrievalQAOptions
	history_key           string = 'history'
	max_history_bytes     int    = default_max_retrieval_history_bytes
	max_question_bytes    int    = default_max_standalone_question_bytes
	condense_call_options llms.CallOptions
}

// ConversationalRetrievalQAChain rewrites a question using memory before retrieval.
pub struct ConversationalRetrievalQAChain {
	retrieval_chain       RetrievalQAChain
	model                 llms.CompletionModel
	question_prompt       prompts.StringTemplate
	question_key          string
	history_key           string
	max_history_bytes     int
	max_question_bytes    int
	condense_call_options llms.CallOptions
}

// new_conversational_retrieval_qa_chain constructs a memory-backed chain that
// condenses chat history and the latest question before running retrieval QA.
pub fn new_conversational_retrieval_qa_chain(retriever schema.Retriever, model llms.CompletionModel, question_prompt prompts.StringTemplate, answer_prompt prompts.StringTemplate, options ConversationalRetrievalQAOptions) !ConversationalRetrievalQAChain {
	qa_options := options.retrieval_qa
	if options.history_key.trim_space() == '' || options.history_key in [
		qa_options.question_key,
		qa_options.document_key,
		qa_options.output_key,
	] {
		return error('conversational retrieval history key must be non-empty and distinct from QA keys')
	}
	if options.max_history_bytes <= 0 || options.max_history_bytes > max_retrieval_history_bytes {
		return error('conversational retrieval max_history_bytes is outside the supported range 1..1048576')
	}
	if options.max_question_bytes <= 0 || options.max_question_bytes > 65536 {
		return error('conversational retrieval max_question_bytes is outside the supported range 1..65536')
	}
	options.condense_call_options.validate()!
	question_variables := question_prompt.input_variables()!
	if question_variables.len != 2 || qa_options.question_key !in question_variables
		|| options.history_key !in question_variables {
		return error('question condensing prompt must contain only the configured question and history variables')
	}
	retrieval_chain := new_retrieval_qa_chain(retriever, model, answer_prompt, qa_options)!
	if retrieval_chain.input_keys() != [qa_options.question_key] {
		return error('conversational retrieval answer prompt must only require the question besides retrieved context')
	}
	if memory := retrieval_chain.memory() {
		if options.history_key !in memory.memory_keys() {
			return error('conversational retrieval memory must provide `${options.history_key}`')
		}
	} else {
		return error('conversational retrieval QA requires memory')
	}
	return ConversationalRetrievalQAChain{
		retrieval_chain:       retrieval_chain
		model:                 model
		question_prompt:       question_prompt
		question_key:          qa_options.question_key
		history_key:           options.history_key
		max_history_bytes:     options.max_history_bytes
		max_question_bytes:    options.max_question_bytes
		condense_call_options: options.condense_call_options
	}
}

// call condenses a user question against loaded history, then delegates QA.
pub fn (chain ConversationalRetrievalQAChain) call(mut ctx context.Context, inputs map[string]json2.Any) !map[string]json2.Any {
	question_value := inputs[chain.question_key] or { return error('missing conversational retrieval question') }
	question := match question_value {
		string {
			question_value
		}
		else {
			return error('conversational retrieval question must be a string')
		}
	}
	if question.trim_space() == '' || question.len > chain.max_question_bytes {
		return error('conversational retrieval question is empty or exceeds the configured byte limit')
	}
	history_value := inputs[chain.history_key] or { return error('missing conversational retrieval history') }
	history := match history_value {
		string {
			history_value
		}
		else {
			return error('conversational retrieval history must be a string')
		}
	}
	if history.len > chain.max_history_bytes {
		return error('conversational retrieval history exceeds the configured byte limit')
	}
	condense_prompt := chain.question_prompt.format({
		chain.question_key: json2.Any(question)
		chain.history_key:  json2.Any(history)
	})!
	if condense_prompt.len > max_retrieval_prompt_bytes {
		return error('formatted conversational retrieval prompt exceeds the configured byte limit')
	}
	standalone_question := chain.model.complete(mut ctx, condense_prompt,
		chain.condense_call_options)!.trim_space()
	if standalone_question == '' || standalone_question.len > chain.max_question_bytes {
		return error('condensed retrieval question is empty or exceeds the configured byte limit')
	}
	mut retrieval_inputs := inputs.clone()
	retrieval_inputs[chain.question_key] = json2.Any(standalone_question)
	return chain.retrieval_chain.call(mut ctx, retrieval_inputs)
}

// memory returns the conversation memory configured on retrieval QA.
pub fn (chain ConversationalRetrievalQAChain) memory() ?schema.Memory {
	return chain.retrieval_chain.memory()
}

// input_keys returns the question expected from the caller.
pub fn (chain ConversationalRetrievalQAChain) input_keys() []string {
	return [chain.question_key]
}

// output_keys returns the configured retrieval QA outputs.
pub fn (chain ConversationalRetrievalQAChain) output_keys() []string {
	return chain.retrieval_chain.output_keys()
}
