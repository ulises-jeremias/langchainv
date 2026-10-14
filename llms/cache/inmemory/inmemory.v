// Package inmemory implements a bounded FIFO response cache.
module inmemory

import context
import json2
import sync
import ulises_jeremias.langchainv.llms.cache as responsecache
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

@[heap]
struct State {
mut:
	mutex       sync.Mutex
	values      map[string]llms.Response
	entry_bytes map[string]i64
	keys        []string
	used_bytes  i64
}

// Cache is a concurrency-safe FIFO cache with configurable entry and payload limits.
pub struct Cache {
	state     &State
	capacity  int
	max_bytes i64
}

// new_cache creates a cache that retains at most capacity entries without a
// total response-payload byte limit.
pub fn new_cache(capacity int) !Cache {
	if capacity <= 0 {
		return error('cache capacity must be greater than zero')
	}
	return Cache{
		state:    &State{
			values:      map[string]llms.Response{}
			entry_bytes: map[string]i64{}
		}
		capacity: capacity
	}
}

// new_cache_with_limits creates a FIFO cache bounded by both entry count and
// the combined JSON-encoded response size. A response larger than max_bytes is
// not cached; existing entries remain available.
pub fn new_cache_with_limits(capacity int, max_bytes i64) !Cache {
	if capacity <= 0 {
		return error('cache capacity must be greater than zero')
	}
	if max_bytes <= 0 || max_bytes > 1024 * 1024 * 1024 {
		return error('cache byte limit must be between 1 byte and 1 GiB')
	}
	return Cache{
		state:     &State{
			values:      map[string]llms.Response{}
			entry_bytes: map[string]i64{}
		}
		capacity:  capacity
		max_bytes: max_bytes
	}
}

// get returns an independent snapshot of the cached response, if present.
pub fn (cache Cache) get(mut ctx context.Context, key string) !responsecache.Lookup {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	mut state := cache.state
	state.mutex.lock()
	if response := state.values[key] {
		cloned := clone_response(response)
		state.mutex.unlock()
		return responsecache.Lookup{ found: true, response: cloned }
	}
	state.mutex.unlock()
	return responsecache.Lookup{}
}

// put stores a snapshot, evicting the oldest inserted key when full.
pub fn (cache Cache) put(mut ctx context.Context, key string, response llms.Response) ! {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	mut response_bytes := i64(0)
	if cache.max_bytes > 0 {
		response_bytes = i64(json2.encode(response, json2.EncoderOptions{}).len)
	}
	if cache.max_bytes > 0 && response_bytes > cache.max_bytes {
		return
	}
	response_snapshot := clone_response(response)
	mut state := cache.state
	state.mutex.lock()
	if key in state.values {
		state.used_bytes -= state.entry_bytes[key]
	} else {
		state.keys << key
	}
	state.values[key] = response_snapshot
	state.entry_bytes[key] = response_bytes
	state.used_bytes += response_bytes
	for state.keys.len > cache.capacity || (cache.max_bytes > 0 && state.used_bytes > cache.max_bytes) {
		oldest := state.keys[0]
		state.keys.delete(0)
		state.values.delete(oldest)
		state.used_bytes -= state.entry_bytes[oldest]
		state.entry_bytes.delete(oldest)
	}
	state.mutex.unlock()
}

fn clone_response(response llms.Response) llms.Response {
	mut choices := []llms.Choice{cap: response.choices.len}
	for choice in response.choices {
		mut parts := []schema.ContentPart{cap: choice.parts.len}
		for part in choice.parts {
			parts << match part {
				schema.BinaryPart {
					schema.ContentPart(schema.BinaryPart{ mime_type: part.mime_type, data: part.data.clone() })
				}
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
		choices << llms.Choice{ content: choice.content, stop_reason: choice.stop_reason, function_call: choice.function_call, tool_calls: choice.tool_calls.clone(), reasoning: choice.reasoning, parts: parts, generation_info: info }
	}
	return llms.Response{ choices: choices, usage: response.usage }
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
