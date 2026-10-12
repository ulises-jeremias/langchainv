// Package llmtest provides explicit contract checks and test doubles for model adapters.
module llmtest

import context
import json2
import sync
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

@[heap]
struct MockModelState {
mut:
	mutex         sync.Mutex
	response      llms.Response
	error_message string
	calls         int
}

// MockModel is a concurrency-safe, configurable implementation of llms.Model.
// Responses are copied when configured and when returned so callers do not
// share mutable slices or maps with the mock's internal state.
pub struct MockModel {
	state &MockModelState
}

// new_mock_model creates a mock that returns response from each model call.
pub fn new_mock_model(response llms.Response) MockModel {
	return MockModel{
		state: &MockModelState{
			response: clone_response(response)
		}
	}
}

// set_response replaces the response returned by future calls and clears any
// configured error.
pub fn (model MockModel) set_response(response llms.Response) {
	response_copy := clone_response(response)
	mut state := model.state
	state.mutex.lock()
	state.response = response_copy
	state.error_message = ''
	state.mutex.unlock()
}

// set_error makes future calls return an error with message. An empty message
// clears the configured error.
pub fn (model MockModel) set_error(message string) {
	mut state := model.state
	state.mutex.lock()
	state.error_message = message
	state.mutex.unlock()
}

// call_count returns the number of generation attempts made so far.
pub fn (model MockModel) call_count() int {
	mut state := model.state
	state.mutex.lock()
	calls := state.calls
	state.mutex.unlock()
	return calls
}

// generate_content implements llms.Model with the configured response or error.
pub fn (model MockModel) generate_content(mut ctx context.Context, _messages []schema.Message, options llms.CallOptions) !llms.Response {
	mut state := model.state
	state.mutex.lock()
	state.calls++
	response := clone_response(state.response)
	error_message := state.error_message
	state.mutex.unlock()

	if error_message != '' {
		return error(error_message)
	}
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	if callback := options.streaming_func {
		if response.choices.len > 0 {
			callback(mut ctx, response.choices[0].content.bytes()) or {
				return error('mock streaming callback failed: ${err.msg()}')
			}
		}
	}
	return response
}

fn clone_response(response llms.Response) llms.Response {
	mut choices := []llms.Choice{cap: response.choices.len}
	for choice in response.choices {
		mut generation_info := map[string]json2.Any{}
		for key, value in choice.generation_info {
			generation_info[key] = clone_any(value)
		}
		mut parts := []schema.ContentPart{cap: choice.parts.len}
		for part in choice.parts {
			parts << clone_content_part(part)
		}
		choices << llms.Choice{
			content:         choice.content
			stop_reason:     choice.stop_reason
			function_call:   choice.function_call
			tool_calls:      choice.tool_calls.clone()
			reasoning:       choice.reasoning
			parts:           parts
			generation_info: generation_info
		}
	}
	return llms.Response{
		choices: choices
		usage:   response.usage
	}
}

fn clone_any(value json2.Any) json2.Any {
	if value is []json2.Any {
		array := value as []json2.Any
		mut result := []json2.Any{cap: array.len}
		for item in array {
			result << clone_any(item)
		}
		return json2.Any(result)
	}
	if value is map[string]json2.Any {
		object := value as map[string]json2.Any
		mut result := map[string]json2.Any{}
		for key, item in object {
			result[key] = clone_any(item)
		}
		return json2.Any(result)
	}
	return value
}

fn clone_content_part(part schema.ContentPart) schema.ContentPart {
	return match part {
		schema.BinaryPart {
			schema.ContentPart(schema.BinaryPart{
				mime_type: part.mime_type
				data:      part.data.clone()
			})
		}
		schema.ImageURLPart {
			schema.ContentPart(schema.ImageURLPart{
				url:    part.url
				detail: part.detail
			})
		}
		schema.RedactedThinkingPart {
			schema.ContentPart(schema.RedactedThinkingPart{
				data: part.data
			})
		}
		schema.TextPart {
			schema.ContentPart(schema.TextPart{
				text: part.text
			})
		}
		schema.ThinkingPart {
			schema.ContentPart(schema.ThinkingPart{
				text:      part.text
				signature: part.signature
			})
		}
		schema.ToolCall {
			schema.ContentPart(schema.ToolCall{
				id:            part.id
				call_type:     part.call_type
				function_call: part.function_call
			})
		}
		schema.ToolResult {
			schema.ContentPart(schema.ToolResult{
				call_id: part.call_id
				name:    part.name
				content: part.content
			})
		}
	}
}
