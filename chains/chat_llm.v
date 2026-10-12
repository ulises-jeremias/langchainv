// Package chains includes a chat-model chain backed by schema messages.
module chains

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema

// ChatLLMChain formats a chat prompt and sends the messages to a chat model.
pub struct ChatLLMChain {
pub mut:
	model        llms.Model
	prompt       prompts.ChatPromptTemplate
	output_key   string
	options      llms.CallOptions
	memory_store ?schema.Memory
mut:
	keys []string
}

// new_chat_llm_chain creates a chain using a role-tagged chat prompt.
pub fn new_chat_llm_chain(model llms.Model, prompt prompts.ChatPromptTemplate, output_key string) !ChatLLMChain {
	if output_key.trim_space() == '' {
		return error('chain output key cannot be empty')
	}
	keys := prompt.input_variables()!
	return ChatLLMChain{
		model:      model
		prompt:     prompt
		output_key: output_key
		keys:       keys
	}
}

// call formats chat messages, invokes the model, and returns its first choice.
pub fn (chain ChatLLMChain) call(mut ctx context.Context, inputs map[string]json2.Any) !map[string]json2.Any {
	chain.options.validate()!
	messages := chain.prompt.format_messages(inputs)!
	llms.validate_messages(messages)!
	response := chain.model.generate_content(mut ctx, messages, chain.options)!
	if response.choices.len == 0 {
		return error('chat model returned no choices')
	}
	mut outputs := map[string]json2.Any{}
	outputs[chain.output_key] = json2.Any(response.choices[0].content)
	return outputs
}

// memory returns the optional memory configured on this chain.
pub fn (chain ChatLLMChain) memory() ?schema.Memory {
	return chain.memory_store
}

// input_keys returns the unique variables required by the chat prompt.
pub fn (chain ChatLLMChain) input_keys() []string {
	return chain.keys.clone()
}

// output_keys returns the single chat result key.
pub fn (chain ChatLLMChain) output_keys() []string {
	return [chain.output_key]
}
