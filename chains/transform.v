// Package chains provides chains backed by caller-supplied transformations.
module chains

import context
import json2
import ulises_jeremias.langchainv.schema

// TransformFunc maps named inputs to named outputs and may return an error.
pub type TransformFunc = fn (mut context.Context, map[string]json2.Any) !map[string]json2.Any

// TransformChain adapts a V function to the Chain interface.
pub struct TransformChain {
pub mut:
	transform    TransformFunc
	memory_store ?schema.Memory
pub:
	input_variables  []string
	output_variables []string
}

// new_transform_chain creates a chain with declared input and output keys.
pub fn new_transform_chain(transform TransformFunc, input_keys []string, output_keys []string) !TransformChain {
	if output_keys.len == 0 {
		return error('transform chain requires at least one output key')
	}
	validate_unique_keys(input_keys, 'input')!
	validate_unique_keys(output_keys, 'output')!
	return TransformChain{
		transform:        transform
		input_variables:  input_keys.clone()
		output_variables: output_keys.clone()
	}
}

// call applies the transform to a copy of the input map and validates its outputs.
pub fn (chain TransformChain) call(mut ctx context.Context, inputs map[string]json2.Any) !map[string]json2.Any {
	copied_inputs := inputs.clone()
	outputs := chain.transform(mut ctx, copied_inputs)!
	validate_outputs(chain, outputs)!
	return outputs
}

// memory returns optional memory configured on this transform chain.
pub fn (chain TransformChain) memory() ?schema.Memory {
	return chain.memory_store
}

// input_keys returns the input keys required by the transform.
pub fn (chain TransformChain) input_keys() []string {
	return chain.input_variables.clone()
}

// output_keys returns the keys the transform must produce.
pub fn (chain TransformChain) output_keys() []string {
	return chain.output_variables.clone()
}

fn validate_unique_keys(keys []string, label string) ! {
	mut seen := map[string]bool{}
	for key in keys {
		if key.trim_space() == '' || key in seen {
			return error('transform chain ${label} keys must be non-empty and unique')
		}
		seen[key] = true
	}
}
