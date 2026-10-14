// Package inmemory implements a bounded FIFO response cache.
module inmemory

import context
import json2
import sync
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

@[heap]
struct State {
mut:
	mutex sync.Mutex
	values map[string]llms.Response
	keys   []string
}

// Cache is a concurrency-safe FIFO cache with a fixed maximum entry count.
pub struct Cache {
	state    &State
	capacity int
}

// new_cache creates a cache that retains at most capacity entries.
pub fn new_cache(capacity int) !Cache {
	if capacity <= 0 {
		return error('cache capacity must be greater than zero')
	}
	return Cache{state: &State{values: map[string]llms.Response{}}, capacity: capacity}
}

// get returns an independent snapshot of the cached response, if present.
pub fn (cache Cache) get(mut ctx context.Context, key string) !?llms.Response {
	if err := ctx.err(); err !is none {
		return err
	}
	mut state := cache.state
	state.mutex.lock()
	if response := state.values[key] {
		cloned := clone_response(response)
		state.mutex.unlock()
		return cloned
	}
	state.mutex.unlock()
	return none
}

// put stores a snapshot, evicting the oldest inserted key when full.
pub fn (cache Cache) put(mut ctx context.Context, key string, response llms.Response) ! {
	if err := ctx.err(); err !is none {
		return err
	}
	mut state := cache.state
	state.mutex.lock()
	if key !in state.values {
		if state.keys.len >= cache.capacity {
			oldest := state.keys[0]
			state.keys.delete(0)
			state.values.delete(oldest)
		}
		state.keys << key
	}
	state.values[key] = clone_response(response)
	state.mutex.unlock()
}

fn clone_response(response llms.Response) llms.Response {
	mut choices := []llms.Choice{cap: response.choices.len}
	for choice in response.choices {
		mut parts := []schema.ContentPart{cap: choice.parts.len}
		for part in choice.parts {
			parts << match part {
				schema.BinaryPart { schema.ContentPart(schema.BinaryPart{mime_type: part.mime_type, data: part.data.clone()}) }
				schema.ImageURLPart { schema.ContentPart(part) }
				schema.RedactedThinkingPart { schema.ContentPart(part) }
				schema.TextPart { schema.ContentPart(part) }
				schema.ThinkingPart { schema.ContentPart(part) }
				schema.ToolCall { schema.ContentPart(part) }
				schema.ToolResult { schema.ContentPart(part) }
			}
		}
		mut info := map[string]json2.Any{}
		for key, value in choice.generation_info {
			info[key] = clone_any(value)
		}
		choices << llms.Choice{content: choice.content, stop_reason: choice.stop_reason, function_call: choice.function_call, tool_calls: choice.tool_calls.clone(), reasoning: choice.reasoning, parts: parts, generation_info: info}
	}
	return llms.Response{choices: choices, usage: response.usage}
}

fn clone_any(value json2.Any) json2.Any {
	if value is []json2.Any {
		array := value as []json2.Any
		mut cloned := []json2.Any{cap: array.len}
		for item in array { cloned << clone_any(item) }
		return json2.Any(cloned)
	}
	if value is map[string]json2.Any {
		object := value as map[string]json2.Any
		mut cloned := map[string]json2.Any{}
		for key, item in object { cloned[key] = clone_any(item) }
		return json2.Any(cloned)
	}
	return value
}
