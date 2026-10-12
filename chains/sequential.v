// Package chains implements validated sequential chain composition.
module chains

import context
import json2
import ulises_jeremias.langchainv.schema

// SequentialChain runs each child chain with the accumulated named values.
pub struct SequentialChain {
pub mut:
	chains       []Chain
	memory_store ?schema.Memory
pub:
	input_variables  []string
	output_variables []string
}

// new_sequential_chain validates key flow between ordered child chains.
pub fn new_sequential_chain(child_chains []Chain, input_keys []string, output_keys []string) !SequentialChain {
	if child_chains.len == 0 {
		return error('sequential chain requires at least one child chain')
	}
	if input_keys.len == 0 || output_keys.len == 0 {
		return error('sequential chain requires input and output keys')
	}
	mut known := map[string]bool{}
	for key in input_keys {
		if key.trim_space() == '' || key in known {
			return error('sequential chain input keys must be non-empty and unique')
		}
		known[key] = true
	}
	for index, chain in child_chains {
		for key in chain.input_keys() {
			if key !in known {
				return error('chain at index ${index} requires unavailable input `${key}`')
			}
		}
		child_outputs := chain.output_keys()
		if child_outputs.len == 0 {
			return error('chain at index ${index} declares no outputs')
		}
		for key in child_outputs {
			if key.trim_space() == '' || key in known {
				return error('chain at index ${index} output key `${key}` is empty or already available')
			}
			known[key] = true
		}
	}
	mut selected_outputs := map[string]bool{}
	for key in output_keys {
		if key.trim_space() == '' || key in selected_outputs {
			return error('sequential chain output keys must be non-empty and unique')
		}
		if key !in known {
			return error('sequential chain output key `${key}` is unavailable')
		}
		selected_outputs[key] = true
	}
	return SequentialChain{
		chains:           child_chains.clone()
		input_variables:  input_keys.clone()
		output_variables: output_keys.clone()
	}
}

// call runs children in order and returns the selected output keys.
pub fn (chain SequentialChain) call(mut ctx context.Context, inputs map[string]json2.Any) !map[string]json2.Any {
	mut values := inputs.clone()
	for child in chain.chains {
		child_outputs := call(mut ctx, child, values)!
		for key, value in child_outputs {
			values[key] = value
		}
	}
	mut result := map[string]json2.Any{}
	for key in chain.output_variables {
		result[key] = values[key] or { return error('sequential chain did not produce output `${key}`') }
	}
	return result
}

// memory returns optional memory shared by the sequential chain wrapper.
pub fn (chain SequentialChain) memory() ?schema.Memory {
	return chain.memory_store
}

// input_keys returns the keys required before the first child runs.
pub fn (chain SequentialChain) input_keys() []string {
	return chain.input_variables.clone()
}

// output_keys returns the selected values returned by the sequence.
pub fn (chain SequentialChain) output_keys() []string {
	return chain.output_variables.clone()
}

// SimpleSequentialChain composes single-input, single-output child chains.
pub struct SimpleSequentialChain {
pub mut:
	chains       []Chain
	memory_store ?schema.Memory
}

// new_simple_sequential_chain validates that every child has one input and output.
pub fn new_simple_sequential_chain(child_chains []Chain) !SimpleSequentialChain {
	if child_chains.len == 0 {
		return error('simple sequential chain requires at least one child chain')
	}
	for index, chain in child_chains {
		child_inputs := chain.input_keys()
		if child_inputs.len != 1 {
			return error('chain at index ${index} must declare exactly one input')
		}
		child_outputs := chain.output_keys()
		if child_outputs.len != 1 {
			return error('chain at index ${index} must declare exactly one output')
		}
		if child_inputs[0].trim_space() == '' || child_outputs[0].trim_space() == '' {
			return error('chain at index ${index} input and output keys must be non-empty')
		}
	}
	return SimpleSequentialChain{
		chains: child_chains.clone()
	}
}

// call passes one value through each child and returns it as `output`.
pub fn (chain SimpleSequentialChain) call(mut ctx context.Context, inputs map[string]json2.Any) !map[string]json2.Any {
	mut value := inputs['input'] or { return error('missing simple sequential chain input `input`') }
	for child in chain.chains {
		keys := child.input_keys()
		mut child_inputs := map[string]json2.Any{}
		child_inputs[keys[0]] = value
		child_outputs := call(mut ctx, child, child_inputs)!
		output_key := child.output_keys()[0]
		value = child_outputs[output_key] or {
			return error('chain did not produce declared output `${output_key}`')
		}
	}
	return {
		'output': value
	}
}

// memory returns optional memory shared by the simple sequential chain wrapper.
pub fn (chain SimpleSequentialChain) memory() ?schema.Memory {
	return chain.memory_store
}

// input_keys returns the single input name used by this chain.
pub fn (chain SimpleSequentialChain) input_keys() []string {
	return ['input']
}

// output_keys returns the single output name used by this chain.
pub fn (chain SimpleSequentialChain) output_keys() []string {
	return ['output']
}
