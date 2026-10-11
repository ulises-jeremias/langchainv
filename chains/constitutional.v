// Package chains provides bounded constitutional critique and revision.
module chains

import context
import json2
import ulises_jeremias.langchainv.memory
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema

const default_constitutional_output_key = 'output'
const default_constitutional_max_principles = 16
const default_constitutional_max_bytes = 65536

// ConstitutionalPrinciple describes one sequential critique and revision pass.
pub struct ConstitutionalPrinciple {
pub:
	name             string
	critique_request string
	revision_request string
}

// ConstitutionalOptions configures bounded critique and revision prompts.
pub struct ConstitutionalOptions {
pub:
	output_key          string = default_constitutional_output_key
	max_principles      int    = default_constitutional_max_principles
	max_prompt_bytes    int    = default_constitutional_max_bytes
	return_intermediate bool
pub mut:
	critique_prompt prompts.StringTemplate
	revision_prompt prompts.StringTemplate
}

// ConstitutionalChain critiques an LLM chain answer and revises it in order.
pub struct ConstitutionalChain {
	chain LLMChain
pub:
	principles []ConstitutionalPrinciple
	options    ConstitutionalOptions
mut:
	keys         []string
	output_keys  []string
	memory_store ?schema.Memory
}

// new_constitutional_chain wraps a completion chain with bounded critique passes.
pub fn new_constitutional_chain(chain LLMChain, principles []ConstitutionalPrinciple, options ConstitutionalOptions) !ConstitutionalChain {
	if options.output_key.trim_space() == '' {
		return error('constitutional output key cannot be empty')
	}
	if principles.len == 0 || principles.len > default_constitutional_max_principles {
		return error('constitutional principles must contain between 1 and 16 entries')
	}
	if options.max_principles <= 0 || options.max_principles > default_constitutional_max_principles
		|| principles.len > options.max_principles {
		return error('constitutional max_principles must be between 1 and 16 and cover all principles')
	}
	if options.max_prompt_bytes <= 0 || options.max_prompt_bytes > 1048576 {
		return error('constitutional max_prompt_bytes must be between 1 and 1048576')
	}
	mut configured := options
	if configured.critique_prompt.template.trim_space() == '' {
		configured.critique_prompt = prompts.StringTemplate{
			template: 'Review the original request and the assistant response. Apply this principle: {critique_request}\n\nOriginal request:\n{input_prompt}\n\nAssistant response:\n{response}\n\nReturn a concise critique, or exactly "No critique needed". Do not write a revision.'
		}
	}
	if configured.revision_prompt.template.trim_space() == '' {
		configured.revision_prompt = prompts.StringTemplate{
			template: 'Revise the assistant response according to this principle: {revision_request}\n\nOriginal request:\n{input_prompt}\n\nCritique:\n{critique}\n\nCurrent assistant response:\n{response}\n\nReturn only the revised assistant response.'
		}
	}
	critique_keys := configured.critique_prompt.input_variables()!
	revision_keys := configured.revision_prompt.input_variables()!
	for key in ['critique_request', 'input_prompt', 'response'] {
		if key !in critique_keys {
			return error('constitutional critique prompt must include `${key}`')
		}
	}
	for key in ['revision_request', 'input_prompt', 'critique', 'response'] {
		if key !in revision_keys {
			return error('constitutional revision prompt must include `${key}`')
		}
	}
	mut names := map[string]bool{}
	for principle in principles {
		if principle.name.trim_space() == '' || principle.critique_request.trim_space() == ''
			|| principle.revision_request.trim_space() == '' {
			return error('constitutional principle names and requests must not be empty')
		}
		if principle.name in names {
			return error('constitutional principle names must be unique')
		}
		names[principle.name] = true
	}
	if options.output_key in chain.input_keys() {
		return error('constitutional output key conflicts with a chain input')
	}
	mut output_keys := [options.output_key]
	if options.return_intermediate {
		for key in ['initial_output', 'critiques_and_revisions'] {
			if key in chain.input_keys() || key == options.output_key {
				return error('constitutional intermediate output key `${key}` conflicts with a chain input or output')
			}
		}
		output_keys << 'initial_output'
		output_keys << 'critiques_and_revisions'
	}
	mut input_keys := chain.input_keys()
	if base_memory := chain.memory() {
		memory_keys := base_memory.memory_keys()
		input_keys = input_keys.filter(it !in memory_keys)
	}
	return ConstitutionalChain{
		chain:        chain
		principles:   principles.clone()
		options:      configured
		keys:         input_keys
		output_keys:  output_keys
		memory_store: ?schema.Memory(memory.new_simple_memory())
	}
}

// call runs the wrapped chain, then critiques and revises sequentially.
pub fn (chain ConstitutionalChain) call(mut ctx context.Context, inputs map[string]json2.Any) !map[string]json2.Any {
	mut ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	mut full_inputs := inputs.clone()
	if base_memory := chain.chain.memory() {
		mut active_memory := base_memory
		memory_values := active_memory.load_memory_variables(mut ctx, inputs)!
		for key, value in memory_values {
			full_inputs[key] = value
		}
	}
	validate_inputs(chain.chain, full_inputs)!
	input_prompt := chain.chain.prompt.format(full_inputs)!
	if input_prompt.len > chain.options.max_prompt_bytes {
		return error('constitutional input prompt exceeds the configured byte limit')
	}
	initial_outputs := chain.chain.call(mut ctx, full_inputs)!
	validate_outputs(chain.chain, initial_outputs)!
	if base_memory := chain.chain.memory() {
		mut active_memory := base_memory
		active_memory.save_context(mut ctx, inputs, initial_outputs)!
	}
	initial_value := initial_outputs[chain.chain.output_key] or {
		return error('constitutional base chain did not produce `${chain.chain.output_key}`')
	}
	if initial_value !is string {
		return error('constitutional base chain output must be a string')
	}
	initial_response := initial_value as string
	if initial_response.len > chain.options.max_prompt_bytes {
		return error('constitutional response exceeds the configured byte limit')
	}
	mut response := initial_response
	mut pairs := []json2.Any{cap: chain.principles.len}
	for principle in chain.principles {
		ctx_error = ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
		critique_prompt := chain.options.critique_prompt.format({
			'critique_request': json2.Any(principle.critique_request)
			'input_prompt':     json2.Any(input_prompt)
			'response':         json2.Any(response)
		})!
		if critique_prompt.len > chain.options.max_prompt_bytes {
			return error('formatted constitutional critique prompt exceeds the configured byte limit')
		}
		critique := chain.chain.model.complete(mut ctx, critique_prompt, chain.chain.options)!.trim_space()
		if critique.len > chain.options.max_prompt_bytes {
			return error('constitutional critique exceeds the configured byte limit')
		}
		mut revision := ''
		if critique.to_lower() != 'no critique needed' && !critique.to_lower().contains('no critique needed') {
			ctx_error = ctx.err()
			if ctx_error !is none {
				return ctx_error
			}
			revision_prompt := chain.options.revision_prompt.format({
				'revision_request': json2.Any(principle.revision_request)
				'input_prompt':     json2.Any(input_prompt)
				'critique':         json2.Any(critique)
				'response':         json2.Any(response)
			})!
			if revision_prompt.len > chain.options.max_prompt_bytes {
				return error('formatted constitutional revision prompt exceeds the configured byte limit')
			}
			revision = chain.chain.model.complete(mut ctx, revision_prompt, chain.chain.options)!.trim_space()
			if revision.len == 0 || revision.len > chain.options.max_prompt_bytes {
				return error('constitutional revision must be non-empty and within the configured byte limit')
			}
			response = revision
		}
		if chain.options.return_intermediate {
			pairs << json2.Any({
				'name':     json2.Any(principle.name)
				'critique': json2.Any(critique)
				'revision': json2.Any(revision)
			})
		}
	}
	mut outputs := map[string]json2.Any{
		chain.options.output_key: json2.Any(response)
	}
	if chain.options.return_intermediate {
		outputs['initial_output'] = json2.Any(initial_response)
		outputs['critiques_and_revisions'] = json2.Any(pairs)
	}
	return outputs
}

// memory returns a no-op memory because the wrapped chain owns conversation memory.
pub fn (chain ConstitutionalChain) memory() ?schema.Memory {
	return chain.memory_store
}

// input_keys returns inputs required by the wrapped chain.
pub fn (chain ConstitutionalChain) input_keys() []string {
	return chain.keys.clone()
}

// output_keys returns the configured answer and optional intermediate keys.
pub fn (chain ConstitutionalChain) output_keys() []string {
	return chain.output_keys.clone()
}
