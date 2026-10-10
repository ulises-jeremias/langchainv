// Package memory provides a no-op Memory implementation for chains without state.
module memory

import context
import json2

// SimpleMemory satisfies the memory contract without loading or saving values.
pub struct SimpleMemory {}

// new_simple_memory creates a no-op memory implementation.
pub fn new_simple_memory() SimpleMemory {
	return SimpleMemory{}
}

// memory_keys returns no keys because this memory supplies no values.
pub fn (instance SimpleMemory) memory_keys() []string {
	return []string{}
}

// load_memory_variables returns an empty map.
pub fn (instance SimpleMemory) load_memory_variables(mut ctx context.Context, _inputs map[string]json2.Any) !map[string]json2.Any {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	return map[string]json2.Any{}
}

// save_context accepts values without storing them.
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
