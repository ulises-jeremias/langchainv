// Package callbacks provides a standard-output lifecycle logger.
module callbacks

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

// LogHandler prints lifecycle events to standard output.
pub struct LogHandler {}

// text prints an unstructured text event.
pub fn (handler LogHandler) text(mut ctx context.Context, text string) {
	println(text)
}

// llm_start prints completion prompts.
pub fn (handler LogHandler) llm_start(mut ctx context.Context, prompts []string) {
	println('Entering LLM with prompts: ${prompts}')
}

// llm_generate_content_start prints the role and text for each chat message.
pub fn (handler LogHandler) llm_generate_content_start(mut ctx context.Context, messages []schema.Message) {
	println('Entering LLM with messages:')
	for message in messages {
		println('Role: ${message.role}')
		println('Text: ${message.text()}')
	}
}

// llm_generate_content_end prints generated content and generation metadata.
pub fn (handler LogHandler) llm_generate_content_end(mut ctx context.Context, response llms.Response) {
	println('Exiting LLM with response:')
	for choice in response.choices {
		if choice.content != '' {
			println('Content: ${choice.content}')
		}
		if choice.stop_reason != '' {
			println('StopReason: ${choice.stop_reason}')
		}
		if choice.generation_info.len > 0 {
			println('GenerationInfo: ${choice.generation_info}')
		}
		if choice.reasoning != '' {
			println('Reasoning: ${choice.reasoning}')
		}
		for call in choice.tool_calls {
			println('ToolCall: ${call}')
		}
	}
}

// llm_error prints a model failure.
pub fn (handler LogHandler) llm_error(mut ctx context.Context, err IError) {
	println('Exiting LLM with error: ${err.msg()}')
}

// chain_start prints chain inputs.
pub fn (handler LogHandler) chain_start(mut ctx context.Context, inputs map[string]json2.Any) {
	println('Entering chain with inputs: ${format_values(inputs)}')
}

// chain_end prints chain outputs.
pub fn (handler LogHandler) chain_end(mut ctx context.Context, outputs map[string]json2.Any) {
	println('Exiting chain with outputs: ${format_values(outputs)}')
}

// chain_error prints a chain failure.
pub fn (handler LogHandler) chain_error(mut ctx context.Context, err IError) {
	println('Exiting chain with error: ${err.msg()}')
}

// tool_start prints tool input with newlines flattened.
pub fn (handler LogHandler) tool_start(mut ctx context.Context, input string) {
	println('Entering tool with input: ${one_line(input)}')
}

// tool_end prints tool output with newlines flattened.
pub fn (handler LogHandler) tool_end(mut ctx context.Context, output string) {
	println('Exiting tool with output: ${one_line(output)}')
}

// tool_error prints a tool failure.
pub fn (handler LogHandler) tool_error(mut ctx context.Context, err IError) {
	println('Exiting tool with error: ${err.msg()}')
}

// agent_action prints the selected tool and its input.
pub fn (handler LogHandler) agent_action(mut ctx context.Context, action schema.AgentAction) {
	println('Agent selected action: "${one_line(action.tool)}" with input "${one_line(action.tool_input)}"')
}

// agent_finish prints the agent's returned values.
pub fn (handler LogHandler) agent_finish(mut ctx context.Context, finish schema.AgentFinish) {
	println('Agent finish: ${format_values(finish.return_values)} ${finish.log}')
}

// retriever_start prints the search query.
pub fn (handler LogHandler) retriever_start(mut ctx context.Context, query string) {
	println('Entering retriever with query: ${one_line(query)}')
}

// retriever_end prints documents returned for a search query.
pub fn (handler LogHandler) retriever_end(mut ctx context.Context, query string, documents []schema.Document) {
	println('Exiting retriever with documents for query: ${documents} ${one_line(query)}')
}

// streaming_chunk prints a streaming payload as text.
pub fn (handler LogHandler) streaming_chunk(mut ctx context.Context, chunk []u8) {
	println(chunk.bytestr())
}

fn format_values(values map[string]json2.Any) string {
	mut entries := []string{}
	for key, value in values {
		entries << '"${one_line(key)}" : "${one_line(value.str())}"'
	}
	return entries.join(', ')
}

fn one_line(value string) string {
	return value.replace('\n', ' ')
}
