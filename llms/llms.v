// Package llms defines language model contracts and provider-neutral options.
module llms

import context
import json2
import ulises_jeremias.langchainv.schema

// StreamFunc receives an incremental generation chunk. Returning an error
// stops generation and is propagated by the provider.
pub type StreamFunc = fn (mut context.Context, []u8) !

// ReasoningStreamFunc receives a reasoning delta and its associated output.
pub type ReasoningStreamFunc = fn (mut context.Context, []u8, []u8) !

// CallOptions contains common generation controls. Provider adapters may expose
// additional typed configuration without changing the core model contract.
pub struct CallOptions {
pub mut:
	model                    string
	candidate_count          int
	max_tokens               int
	temperature              f64
	top_p                    f64
	top_k                    int
	stop_words               []string
	seed                     ?int
	min_length               int
	max_length               int
	n                        int
	repetition_penalty       f64
	frequency_penalty        f64
	presence_penalty         f64
	json_mode                bool
	tools                    []schema.ToolDefinition
	tool_choice              ?schema.ToolChoice
	functions                []schema.ToolDefinition
	function_call_behavior   string
	response_mime_type       string
	streaming_func           ?StreamFunc
	streaming_reasoning_func ?ReasoningStreamFunc
	web_search_options       ?schema.WebSearchOptions
	metadata                 map[string]json2.Any
	provider_options         map[string]json2.Any
}

// Usage reports token accounting when a provider supplies it.
pub struct Usage {
pub:
	prompt_tokens     int
	completion_tokens int
	total_tokens      int
}

// Choice is one generated alternative.
pub struct Choice {
pub:
	content         string
	stop_reason     string
	function_call   ?schema.FunctionCall
	tool_calls      []schema.ToolCall
	reasoning       string
	parts           []schema.ContentPart
	generation_info map[string]json2.Any
}

// Response contains generation choices and provider usage information.
pub struct Response {
pub:
	choices []Choice
	usage   Usage
}

// assistant_message converts a response into a replayable assistant message.
pub fn (response Response) assistant_message() schema.Message {
	mut message := schema.Message{
		role: .ai
	}
	for choice in response.choices {
		for part in choice.parts {
			message.parts << part
		}
	}
	if message.parts.len > 0 || response.choices.len == 0 {
		return message
	}
	choice := response.choices[0]
	if choice.content != '' {
		message.parts << schema.ContentPart(schema.TextPart{
			text: choice.content
		})
	}
	for call in choice.tool_calls {
		message.parts << schema.ContentPart(call)
	}
	return message
}

// Model generates content from an ordered sequence of multimodal messages.
// Implementations must check ctx cancellation around blocking operations.
pub interface Model {
	generate_content(mut ctx context.Context, messages []schema.Message, options CallOptions) !Response
}

// CompletionModel supports string-in/string-out completion APIs.
pub interface CompletionModel {
	complete(mut ctx context.Context, prompt string, options CallOptions) !string
}

// ReasoningModel exposes provider reasoning output when supported.
pub interface ReasoningModel {
	generate_reasoning(mut ctx context.Context, messages []schema.Message, options CallOptions) !Response
}

// TokenCounter estimates the token count for a model request when supported.
pub interface TokenCounter {
	count_tokens(mut ctx context.Context, messages []schema.Message, model string) !int
}

// validate checks values with provider-independent constraints.
pub fn (options CallOptions) validate() ! {
	if options.max_tokens < 0 || options.candidate_count < 0 || options.n < 0 {
		return error('token and candidate counts cannot be negative')
	}
	if options.min_length < 0 || options.max_length < 0 {
		return error('generation lengths cannot be negative')
	}
	if options.min_length > 0 && options.max_length > 0 && options.min_length > options.max_length {
		return error('minimum generation length cannot exceed maximum length')
	}
	if options.top_p < 0 || options.top_p > 1 {
		return error('top_p must be between zero and one')
	}
	mut seen := map[string]bool{}
	for tool in options.tools {
		if tool.name.trim_space() == '' {
			return error('tool names cannot be empty')
		}
		if tool.name in seen {
			return error('duplicate tool name `${tool.name}`')
		}
		seen[tool.name] = true
	}
}

// validate_messages checks the provider-neutral message invariants.
pub fn validate_messages(messages []schema.Message) ! {
	if messages.len == 0 {
		return error('at least one message is required')
	}
	for index, message in messages {
		if message.parts.len == 0 {
			return error('message at index ${index} has no content parts')
		}
	}
}
