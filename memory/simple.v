// Package memory provides no-op and static-value Memory implementations.
module memory

import context
import json2

// SimpleMemory loads fixed values and ignores saved outputs.
pub struct SimpleMemory {
	values map[string]json2.Any
}

// new_simple_memory creates a no-op memory implementation.
pub fn new_simple_memory() SimpleMemory {
	return SimpleMemory{
		values: map[string]json2.Any{}
	}
}

// new_simple_memory_with_values creates a memory that supplies fixed values.
// Values are snapshotted at construction and on each load.
pub fn new_simple_memory_with_values(values map[string]json2.Any) !SimpleMemory {
	for key in values.keys() {
		if key.trim_space() == '' {
			return error('simple memory keys must be non-empty')
		}
	}
	return SimpleMemory{
		values: clone_json_map(values)
	}
}

// memory_keys returns the configured keys in stable sorted order.
pub fn (instance SimpleMemory) memory_keys() []string {
	mut keys := instance.values.keys()
	keys.sort()
	return keys
}

// load_memory_variables returns a snapshot of the configured values.
pub fn (instance SimpleMemory) load_memory_variables(mut ctx context.Context, _inputs map[string]json2.Any) !map[string]json2.Any {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	return clone_json_map(instance.values)
}

// save_context accepts values without changing the configured memory.
pub fn (instance SimpleMemory) save_context(mut ctx context.Context, _inputs map[string]json2.Any, _outputs map[string]json2.Any) ! {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
}

// clear succeeds without changing state.
pub fn (instance SimpleMemory) clear(mut ctx context.Context) ! {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
}
