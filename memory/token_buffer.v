// Package memory contains token-bounded conversation memory.
module memory

import context
import json2
import sync
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

struct TokenBufferMemoryState {
mut:
	mutex    sync.Mutex
	messages []schema.Message
}

// TokenBufferMemory keeps recent complete turns within a model token budget.
pub struct TokenBufferMemory {
	state       &TokenBufferMemoryState
	counter     llms.TokenCounter
	model       string
	token_limit int
pub:
	memory_key string
	input_key  string
	output_key string
}

// new_token_buffer_memory constructs a memory using an injected token counter.
pub fn new_token_buffer_memory(counter llms.TokenCounter, model string, token_limit int, memory_key string, input_key string, output_key string) !&TokenBufferMemory {
	if model.trim_space() == '' || memory_key.trim_space() == '' || input_key.trim_space() == ''
		|| output_key.trim_space() == '' {
		return error('token buffer model and memory keys must be non-empty')
	}
	if token_limit <= 0 {
		return error('token buffer token_limit must be positive')
	}
	return &TokenBufferMemory{
		state:       &TokenBufferMemoryState{}
		counter:     counter
		model:       model
		token_limit: token_limit
		memory_key:  memory_key
		input_key:   input_key
		output_key:  output_key
	}
}

// memory_keys returns the key populated by this memory.
pub fn (memory TokenBufferMemory) memory_keys() []string {
	return [memory.memory_key]
}

// load_memory_variables returns the retained token-bounded transcript.
pub fn (memory TokenBufferMemory) load_memory_variables(mut ctx context.Context, _inputs map[string]json2.Any) !map[string]json2.Any {
	if ctx_error := ctx.err() {
		return ctx_error
	}
	mut state := memory.state
	state.mutex.lock()
	messages := state.messages.clone()
	state.mutex.unlock()
	mut lines := []string{cap: messages.len}
	for message in messages {
		role := match message.role {
			.system { 'System' }
			.human { 'Human' }
			.ai { 'AI' }
			.tool { 'Tool' }
			.generic { 'Message' }
		}
		lines << '${role}: ${message.text()}'
	}
	return {
		memory.memory_key: json2.Any(lines.join('\n'))
	}
}

// save_context appends a turn and evicts oldest turns until within the token limit.
// If counting fails, the existing history remains unchanged.
pub fn (memory TokenBufferMemory) save_context(mut ctx context.Context, inputs map[string]json2.Any, outputs map[string]json2.Any) ! {
	if memory.input_key !in inputs {
		return error('missing memory input ${memory.input_key}')
	}
	if memory.output_key !in outputs {
		return error('missing memory output ${memory.output_key}')
	}
	input := inputs[memory.input_key] or { return error('missing memory input ${memory.input_key}') }
	output := outputs[memory.output_key] or { return error('missing memory output ${memory.output_key}') }
	if ctx_error := ctx.err() {
		return ctx_error
	}
	mut state := memory.state
	state.mutex.lock()
	mut candidate := state.messages.clone()
	candidate << schema.text_message(.human, input.str())
	candidate << schema.text_message(.ai, output.str())
	for candidate.len > 0 {
		token_count := memory.counter.count_tokens(mut ctx, candidate, memory.model) or {
			state.mutex.unlock()
			return error('token buffer counting failed: ${err.msg()}')
		}
		if ctx_error := ctx.err() {
			state.mutex.unlock()
			return ctx_error
		}
		if token_count < 0 {
			state.mutex.unlock()
			return error('token counter returned a negative count')
		}
		if token_count <= memory.token_limit {
			break
		}
		if candidate.len <= 2 {
			candidate.clear()
		} else {
			candidate = candidate[2..].clone()
		}
	}
	state.messages = candidate
	state.mutex.unlock()
}

// clear removes all retained turns.
pub fn (memory TokenBufferMemory) clear(mut ctx context.Context) ! {
	if ctx_error := ctx.err() {
		return ctx_error
	}
	mut state := memory.state
	state.mutex.lock()
	state.messages.clear()
	state.mutex.unlock()
}
