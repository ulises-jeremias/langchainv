// Package llmtest provides explicit contract checks for LLM model adapters.
module llmtest

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

const known_capabilities = ['multiturn', 'streaming', 'tools', 'usage']

struct ContractReport {
mut:
	issues []string
}

struct StreamCapture {
mut:
	chunks int
}

// test_model checks the base model contract and requested capabilities.
// It makes real model calls, including a canceled-context call; use it only
// when the supplied model and context are safe for live validation.
pub fn test_model(mut ctx context.Context, model llms.Model, capabilities ...string) ! {
	mut report := ContractReport{}
	mut requested := map[string]bool{}
	for capability in capabilities {
		if capability !in known_capabilities {
			report.issues << 'unknown model capability `${capability}`'
		} else {
			requested[capability] = true
		}
	}
	check_generation(mut ctx, model, mut report)
	check_cancellation(mut ctx, model, mut report)
	if requested['multiturn'] {
		check_multiturn(mut ctx, model, mut report)
	}
	if requested['streaming'] {
		check_streaming(mut ctx, model, mut report)
	}
	if requested['tools'] {
		check_tools(mut ctx, model, mut report)
	}
	if requested['usage'] {
		check_usage(mut ctx, model, mut report)
	}
	if report.issues.len > 0 {
		return error('LLM contract failures:\n- ${report.issues.join('\n- ')}')
	}
}

fn check_generation(mut ctx context.Context, model llms.Model, mut report ContractReport) {
	response := model.generate_content(mut ctx, [schema.text_message(.human, 'Reply with OK.')],
		llms.CallOptions{}) or {
		report.issues << 'generate_content failed: ${err.msg()}'
		return
	}
	if issue := response_issue('generate_content', response) {
		report.issues << issue
	}
}

fn check_cancellation(mut parent context.Context, model llms.Model, mut report ContractReport) {
	mut ctx, cancel := context.with_cancel(mut parent)
	cancel()
	model.generate_content(mut ctx, [schema.text_message(.human, 'Reply with OK.')], llms.CallOptions{}) or {
		return
	}
	report.issues << 'generate_content succeeded with a canceled context'
}

fn check_multiturn(mut ctx context.Context, model llms.Model, mut report ContractReport) {
	messages := [
		schema.text_message(.human, 'My name is Grace.'),
		schema.text_message(.ai, 'Hello, Grace.'),
		schema.text_message(.human, 'Reply with my name.'),
	]
	response := model.generate_content(mut ctx, messages, llms.CallOptions{}) or {
		report.issues << 'multiturn generation failed: ${err.msg()}'
		return
	}
	if issue := response_issue('multiturn', response) {
		report.issues << issue
	}
}

fn check_streaming(mut ctx context.Context, model llms.Model, mut report ContractReport) {
	mut capture := &StreamCapture{}
	streaming := llms.StreamFunc(fn [mut capture] (mut _ctx context.Context, _chunk []u8) ! {
		capture.chunks++
	})
	response := model.generate_content(mut ctx, [schema.text_message(.human, 'Count from 1 to 3.')], llms.CallOptions{
		streaming_func: streaming
	}) or {
		report.issues << 'streaming generation failed: ${err.msg()}'
		return
	}
	if issue := response_issue('streaming', response) {
		report.issues << issue
		return
	}
	if capture.chunks == 0 {
		report.issues << 'streaming callback received no chunks'
	}
	stopped := llms.StreamFunc(fn (mut _ctx context.Context, _chunk []u8) ! {
		return error('llmtest callback stop')
	})
	model.generate_content(mut ctx, [schema.text_message(.human, 'Count from 1 to 3.')], llms.CallOptions{
		streaming_func: stopped
	}) or {
		return
	}
	report.issues << 'streaming generation succeeded after its callback returned an error'
}

fn check_tools(mut ctx context.Context, model llms.Model, mut report ContractReport) {
	tool := schema.ToolDefinition{
		name:        'get_weather'
		description: 'Get the current weather for a city.'
		parameters:  json2.Any({
			'type':       json2.Any('object')
			'properties': json2.Any({
				'location': json2.Any({
					'type':        json2.Any('string')
					'description': json2.Any('City name.')
				})
			})
			'required':   json2.Any([json2.Any('location')])
		})
	}
	messages := [schema.text_message(.human, 'What is the weather in Paris? Use get_weather.')]
	response := model.generate_content(mut ctx, messages, llms.CallOptions{
		tools: [tool]
	}) or {
		report.issues << 'tool generation failed: ${err.msg()}'
		return
	}
	if response_issue := response_issue('tools', response) {
		report.issues << response_issue
		return
	}
	assistant := response.assistant_message()
	mut tool_calls := []schema.ToolCall{}
	for part in assistant.parts {
		match part {
			schema.ToolCall { tool_calls << part }
			else {}
		}
	}
	if tool_calls.len == 0 {
		report.issues << 'tools response did not contain a tool call'
		return
	}
	for call in tool_calls {
		if call.function_call.name != tool.name {
			report.issues << 'tools called `${call.function_call.name}`, expected `${tool.name}`'
		}
		json2.decode[map[string]json2.Any](call.function_call.arguments, json2.DecoderOptions{}) or {
			report.issues << 'tool arguments were not a JSON object: ${err.msg()}'
			continue
		}
		if !call.function_call.arguments.to_lower().contains('paris') {
			report.issues << 'tool arguments did not include Paris'
		}
	}
	mut replay := messages.clone()
	replay << assistant
	for call in tool_calls {
		replay << schema.Message{
			role:  .tool
			parts: [schema.ContentPart(schema.ToolResult{
				call_id: call.id
				name:    call.function_call.name
				content: '{"temperature":18,"conditions":"cloudy"}'
			})]
		}
	}
	final_response := model.generate_content(mut ctx, replay, llms.CallOptions{
		tools: [tool]
	}) or {
		report.issues << 'tool round-trip generation failed: ${err.msg()}'
		return
	}
	if issue := response_issue('tool round-trip', final_response) {
		report.issues << issue
	}
}

fn check_usage(mut ctx context.Context, model llms.Model, mut report ContractReport) {
	response := model.generate_content(mut ctx, [schema.text_message(.human, 'Reply with OK.')],
		llms.CallOptions{}) or {
		report.issues << 'usage generation failed: ${err.msg()}'
		return
	}
	if issue := response_issue('usage', response) {
		report.issues << issue
		return
	}
	usage := response.usage
	if usage.prompt_tokens <= 0 && usage.completion_tokens <= 0 && usage.total_tokens <= 0 {
		report.issues << 'usage response reported no positive token count'
	}
}

fn response_issue(operation string, response llms.Response) ?string {
	if response.choices.len == 0 {
		return '${operation}: response has no choices'
	}
	mut has_content := false
	for choice in response.choices {
		if choice.content != '' || choice.tool_calls.len > 0 || choice.parts.len > 0
			|| choice.function_call != none {
			has_content = true
		}
	}
	if !has_content {
		return '${operation}: no choice carries text, tool calls, or parts'
	}
	return none
}
