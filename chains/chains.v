// Package chains defines the contract and input/output validation for chains.
module chains

import context
import json2
import ulises_jeremias.langchainv.schema

// Chain executes a reusable operation over named inputs.
pub interface Chain {
	call(mut ctx context.Context, inputs map[string]json2.Any) !map[string]json2.Any
	memory() ?schema.Memory
	input_keys() []string
	output_keys() []string
}

// validate_inputs ensures every declared chain input is present.
pub fn validate_inputs(chain Chain, inputs map[string]json2.Any) ! {
	for key in chain.input_keys() {
		if key !in inputs {
			return error('missing required chain input `${key}`')
		}
	}
}

// validate_outputs ensures every declared output was produced.
pub fn validate_outputs(chain Chain, outputs map[string]json2.Any) ! {
	for key in chain.output_keys() {
		if key !in outputs {
			return error('chain did not produce declared output `${key}`')
		}
	}
}

// call validates inputs, invokes the chain, then validates outputs.
pub fn call(mut ctx context.Context, chain Chain, inputs map[string]json2.Any) !map[string]json2.Any {
	mut full_inputs := inputs.clone()
	if chain_memory := chain.memory() {
		mut active_memory := chain_memory
		memory_values := active_memory.load_memory_variables(mut ctx, inputs)!
		for key, value in memory_values {
			full_inputs[key] = value
		}
	}
	validate_inputs(chain, full_inputs)!
	outputs := chain.call(mut ctx, full_inputs)!
	validate_outputs(chain, outputs)!
	if chain_memory := chain.memory() {
		mut active_memory := chain_memory
		active_memory.save_context(mut ctx, inputs, outputs)!
	}
	return outputs
}
