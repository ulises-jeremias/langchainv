// Package chains implements a prompt-backed completion-model chain.
module chains

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema

// LLMChain formats named inputs and sends the resulting prompt to a completion model.
pub struct LLMChain {
pub mut:
	model        llms.CompletionModel
	prompt       prompts.StringTemplate
	output_key   string
	options      llms.CallOptions
	memory_store ?schema.Memory
mut:
	keys []string
}

// new_llm_chain creates a completion chain from a prompt template.
pub fn new_llm_chain(model llms.CompletionModel, prompt prompts.StringTemplate, output_key string) !LLMChain {
	if output_key.trim_space() == '' {
		return error('chain output key cannot be empty')
	}
	keys := prompt.input_variables()!
	return LLMChain{
		model:      model
		prompt:     prompt
		output_key: output_key
		keys:       keys
	}
}

// new_conversation_chain creates a completion chain with a transcript prompt
// and required memory under the `history` key. Configure that memory to save
// turns from the `input` and `output` keys.
pub fn new_conversation_chain(model llms.CompletionModel, conversation_memory schema.Memory) !LLMChain {
	if 'history' !in conversation_memory.memory_keys() {
		return error('conversation chain memory must provide the `history` key')
	}
	mut chain := new_llm_chain(model, prompts.StringTemplate{
		template: 'The following is a friendly conversation between a human and an AI. The AI is talkative and provides lots of specific details from its context. If the AI does not know the answer to a question, it truthfully says it does not know.\n\nCurrent conversation:\n{history}\nHuman: {input}\nAI:'
	}, 'output')!
	chain.memory_store = conversation_memory
	return chain
}

// call formats the prompt and returns the model completion under output_key.
pub fn (chain LLMChain) call(mut ctx context.Context, inputs map[string]json2.Any) !map[string]json2.Any {
	chain.options.validate()!
	prompt_text := chain.prompt.format(inputs)!
	result := chain.model.complete(mut ctx, prompt_text, chain.options)!
	mut outputs := map[string]json2.Any{}
	outputs[chain.output_key] = json2.Any(result)
	return outputs
}

// memory returns the optional memory configured on this chain.
pub fn (chain LLMChain) memory() ?schema.Memory {
	return chain.memory_store
}

// input_keys returns the unique variables required by the prompt.
pub fn (chain LLMChain) input_keys() []string {
	return chain.keys.clone()
}

// output_keys returns the single completion result key.
pub fn (chain LLMChain) output_keys() []string {
	return [chain.output_key]
}
