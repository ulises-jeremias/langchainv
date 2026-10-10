// Package chains maps documents to answers and selects the highest-ranked result.
module chains

import context
import json2
import strconv
import ulises_jeremias.langchainv.outputparser
import ulises_jeremias.langchainv.schema

const default_map_rerank_input_key = 'input_documents'
const default_map_rerank_document_variable = 'context'
const default_map_rerank_rank_key = 'score'
const default_map_rerank_answer_key = 'answer'
const map_rerank_intermediate_steps_key = 'intermediate_steps'
const map_rerank_max_documents = 128
const map_rerank_max_document_bytes = 1048576

// MapRerankDocumentsOptions configures prompt variables, ranked outputs, and limits.
pub struct MapRerankDocumentsOptions {
pub:
	input_key                 string = default_map_rerank_input_key
	document_variable         string = default_map_rerank_document_variable
	rank_key                  string = default_map_rerank_rank_key
	answer_key                string = default_map_rerank_answer_key
	return_intermediate_steps bool
	max_documents             int = 16
	max_document_bytes        int = 65536
}

// MapRerankDocumentsChain ranks each document independently with an LLMChain.
pub struct MapRerankDocumentsChain {
	llm_chain LLMChain
pub:
	options MapRerankDocumentsOptions
mut:
	map_variable string
	keys         []string
	outputs      []string
}

struct RankedMapRerankResult {
	answer string
	score  int
}

// new_map_rerank_documents_chain builds a bounded sequential map-rerank chain.
pub fn new_map_rerank_documents_chain(llm_chain LLMChain, options MapRerankDocumentsOptions) !MapRerankDocumentsChain {
	if options.input_key.trim_space() == '' || options.document_variable.trim_space() == ''
		|| options.rank_key.trim_space() == '' || options.answer_key.trim_space() == '' {
		return error('map-rerank keys must not be empty')
	}
	if options.answer_key == options.rank_key {
		return error('map-rerank answer and rank keys must be distinct')
	}
	if options.max_documents <= 0 || options.max_documents > map_rerank_max_documents {
		return error('map-rerank max_documents must be between 1 and 128')
	}
	if options.max_document_bytes <= 0 || options.max_document_bytes > map_rerank_max_document_bytes {
		return error('map-rerank max_document_bytes must be between 1 and 1048576')
	}
	map_variable := select_document_variable(options.document_variable, llm_chain.input_keys())!
	if options.input_key in llm_chain.input_keys() && options.input_key != map_variable {
		return error('map-rerank input key conflicts with an LLM-chain variable')
	}
	mut outputs := llm_chain.output_keys()
	if outputs.len != 1 {
		return error('map-rerank LLM chain must declare exactly one output')
	}
	if options.return_intermediate_steps {
		if map_rerank_intermediate_steps_key in outputs {
			return error('map-rerank intermediate steps key conflicts with LLM-chain output')
		}
		outputs << map_rerank_intermediate_steps_key
	}
	mut keys := [options.input_key]
	for key in llm_chain.input_keys() {
		if key != map_variable {
			append_unique_chain_key(mut keys, key)
		}
	}
	return MapRerankDocumentsChain{
		llm_chain:    llm_chain
		options:      options
		map_variable: map_variable
		keys:         keys
		outputs:      outputs
	}
}

fn parse_map_rerank_result(text string, answer_key string, rank_key string) !RankedMapRerankResult {
	parser := outputparser.new_regex_parser(r'\s*(?P<answer>.*?)\nScore: (?P<score>.*)')!
	parsed := parser.parse(text)!
	if parsed !is map[string]json2.Any {
		return error('map-rerank output parser did not return a named result map')
	}
	values := parsed as map[string]json2.Any
	answer_value := values[answer_key] or {
		return error('map-rerank output is missing answer key `${answer_key}`')
	}
	score_value := values[rank_key] or {
		return error('map-rerank output is missing rank key `${rank_key}`')
	}
	if answer_value !is string || score_value !is string {
		return error('map-rerank answer and score outputs must be strings')
	}
	score := strconv.atoi((score_value as string).trim_space()) or {
		return error('map-rerank score must be an integer')
	}
	return RankedMapRerankResult{
		answer: answer_value as string
		score:  score
	}
}

fn map_rerank_step(result RankedMapRerankResult, options MapRerankDocumentsOptions) json2.Any {
	return json2.Any({
		options.answer_key: json2.Any(result.answer)
		options.rank_key:   json2.Any(result.score.str())
	})
}

// call maps documents in order and returns the answer with the highest score.
pub fn (chain MapRerankDocumentsChain) call(mut ctx context.Context, inputs map[string]json2.Any) !map[string]json2.Any {
	document_value := inputs[chain.options.input_key] or {
		return error('missing map-rerank input `${chain.options.input_key}`')
	}
	documents := read_map_reduce_documents(document_value, chain.options.max_documents,
		chain.options.max_document_bytes)!
	if documents.len == 0 {
		return error('map-rerank input must contain at least one document')
	}
	mut ranked_results := []RankedMapRerankResult{cap: documents.len}
	for document in documents {
		ctx_error := ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
		mut map_inputs := copy_chain_values(inputs)
		map_inputs.delete(chain.options.input_key)
		map_inputs[chain.map_variable] = json2.Any(document.page_content)
		map_outputs := chain.llm_chain.call(mut ctx, map_inputs)!
		output_value := map_outputs[chain.llm_chain.output_key] or {
			return error('map-rerank LLM chain did not produce `${chain.llm_chain.output_key}`')
		}
		if output_value !is string {
			return error('map-rerank LLM chain output must be a string')
		}
		result := parse_map_rerank_result(output_value as string, chain.options.answer_key,
			chain.options.rank_key)!
		mut insert_at := ranked_results.len
		for index, existing in ranked_results {
			if result.score > existing.score {
				insert_at = index
				break
			}
		}
		ranked_results.insert(insert_at, result)
	}
	mut outputs := map[string]json2.Any{}
	outputs[chain.llm_chain.output_key] = json2.Any(ranked_results[0].answer)
	if chain.options.return_intermediate_steps {
		mut steps := []json2.Any{cap: ranked_results.len}
		for result in ranked_results {
			steps << map_rerank_step(result, chain.options)
		}
		outputs[map_rerank_intermediate_steps_key] = json2.Any(steps)
	}
	return outputs
}

// memory returns the memory configured on the mapping LLM chain.
pub fn (chain MapRerankDocumentsChain) memory() ?schema.Memory {
	return chain.llm_chain.memory()
}

// input_keys returns the documents and passthrough LLM prompt variables.
pub fn (chain MapRerankDocumentsChain) input_keys() []string {
	return chain.keys.clone()
}

// output_keys returns the top answer and optional ranked intermediate steps.
pub fn (chain MapRerankDocumentsChain) output_keys() []string {
	return chain.outputs.clone()
}
