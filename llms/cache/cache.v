// Package cache provides a model wrapper backed by a pluggable response cache.
module cache

import context
import crypto.sha256
import encoding.base64
import encoding.hex
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

// Backend stores responses under opaque, content-derived keys. Implementations
// must honor context cancellation and must return an independent response value.
pub interface Backend {
	get(mut ctx context.Context, key string) !?llms.Response
	put(mut ctx context.Context, key string, response llms.Response) !
}

// Cacher wraps a model and stores successful responses in a backend.
pub struct Cacher {
	model llms.Model
	backend Backend
}

// new_cacher creates a cached model wrapper.
pub fn new_cacher(model llms.Model, backend Backend) Cacher {
	return Cacher{model: model, backend: backend}
}

// generate_content returns a cached response or calls the wrapped model.
// Reasoning-stream requests bypass the cache because a Response does not retain
// the reasoning delta boundaries needed to replay that callback faithfully.
pub fn (cacher Cacher) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	if options.streaming_reasoning_func != none {
		return cacher.model.generate_content(mut ctx, messages, options)
	}
	key := cache_key(messages, options)
	if cached := cacher.backend.get(mut ctx, key)! {
		if stream := options.streaming_func {
			if cached.choices.len > 0 {
				stream(mut ctx, cached.choices[0].content.bytes())!
				if ctx_error := ctx.err(); ctx_error !is none {
					return ctx_error
				}
			}
		}
		return cached
	}
	response := cacher.model.generate_content(mut ctx, messages, options)!
	cacher.backend.put(mut ctx, key, response)!
	return response
}

struct CachePart {
pub:
	type       string
	text       string
	url        string
	detail     string
	mime_type  string
	data       string
	name       string
	arguments  string
	id         string
	call_type  string
	call_id    string
	content    string
	signature  string
}

struct CacheMessage {
pub:
	role     string
	parts    []CachePart
	metadata map[string]json2.Any
}

struct CacheKeyOptions {
pub:
	model                  string
	candidate_count        int
	max_tokens             int
	temperature            f64
	top_p                  f64
	top_k                 int
	stop_words             []string
	seed                   ?int
	min_length             int
	max_length             int
	n                      int
	repetition_penalty     f64
	frequency_penalty      f64
	presence_penalty       f64
	json_mode              bool
	tools                  []schema.ToolDefinition
	tool_choice            ?schema.ToolChoice
	functions              []schema.ToolDefinition
	function_call_behavior string
	response_mime_type     string
	web_search_options     ?schema.WebSearchOptions
	metadata               map[string]json2.Any
	provider_options       map[string]json2.Any
}

fn cache_key(messages []schema.Message, options llms.CallOptions) string {
	mut normalized := []CacheMessage{cap: messages.len}
	for message in messages {
		mut parts := []CachePart{cap: message.parts.len}
		for part in message.parts {
			parts << match part {
				schema.BinaryPart { CachePart{type: 'binary', mime_type: part.mime_type, data: base64.encode(part.data)} }
				schema.ImageURLPart { CachePart{type: 'image_url', url: part.url, detail: part.detail} }
				schema.RedactedThinkingPart { CachePart{type: 'redacted_thinking', data: part.data} }
				schema.TextPart { CachePart{type: 'text', text: part.text} }
				schema.ThinkingPart { CachePart{type: 'thinking', text: part.text, signature: part.signature} }
				schema.ToolCall { CachePart{type: 'tool_call', id: part.id, call_type: part.call_type, name: part.function_call.name, arguments: part.function_call.arguments} }
				schema.ToolResult { CachePart{type: 'tool_result', call_id: part.call_id, name: part.name, content: part.content} }
			}
		}
		normalized << CacheMessage{role: message.role.str(), parts: parts, metadata: message.metadata}
	}
	key_options := CacheKeyOptions{
		model: options.model
		candidate_count: options.candidate_count
		max_tokens: options.max_tokens
		temperature: options.temperature
		top_p: options.top_p
		top_k: options.top_k
		stop_words: options.stop_words
		seed: options.seed
		min_length: options.min_length
		max_length: options.max_length
		n: options.n
		repetition_penalty: options.repetition_penalty
		frequency_penalty: options.frequency_penalty
		presence_penalty: options.presence_penalty
		json_mode: options.json_mode
		tools: options.tools
		tool_choice: options.tool_choice
		functions: options.functions
		function_call_behavior: options.function_call_behavior
		response_mime_type: options.response_mime_type
		web_search_options: options.web_search_options
		metadata: options.metadata
		provider_options: options.provider_options
	}
	encoded := json2.encode(struct {
		messages []CacheMessage
		options  CacheKeyOptions
	}{
		messages: normalized
		options:  key_options
	})
	return hex.encode(sha256.sum256(encoded.bytes()), .{})
}
