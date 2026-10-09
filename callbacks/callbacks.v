// Package callbacks defines lifecycle hooks shared by chains, models, tools,
// agents, and retrievers.
module callbacks

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

// Handler receives optional lifecycle events. Implementations should be quick
// and must not mutate request-owned values.
pub interface Handler {
mut:
	text(mut ctx context.Context, text string)
	llm_start(mut ctx context.Context, prompts []string)
	llm_generate_content_start(mut ctx context.Context, messages []schema.Message)
	llm_generate_content_end(mut ctx context.Context, response llms.Response)
	llm_error(mut ctx context.Context, err IError)
	chain_start(mut ctx context.Context, inputs map[string]json2.Any)
	chain_end(mut ctx context.Context, outputs map[string]json2.Any)
	chain_error(mut ctx context.Context, err IError)
	tool_start(mut ctx context.Context, input string)
	tool_end(mut ctx context.Context, output string)
	tool_error(mut ctx context.Context, err IError)
	agent_action(mut ctx context.Context, action schema.AgentAction)
	agent_finish(mut ctx context.Context, finish schema.AgentFinish)
	retriever_start(mut ctx context.Context, query string)
	retriever_end(mut ctx context.Context, query string, documents []schema.Document)
	streaming_chunk(mut ctx context.Context, chunk []u8)
}

// Handlers is an ordered collection of event handlers.
pub struct Handlers {
pub mut:
	items []Handler
}

// add appends a handler to the dispatch order.
pub fn (mut handlers Handlers) add(handler Handler) {
	handlers.items << handler
}

// dispatch_text delivers a text event to handlers in registration order.
pub fn (mut handlers Handlers) dispatch_text(mut ctx context.Context, text string) {
	for mut handler in handlers.items {
		handler.text(mut ctx, text)
	}
}

// dispatch_llm_start delivers the legacy completion-model start event.
pub fn (mut handlers Handlers) dispatch_llm_start(mut ctx context.Context, prompts []string) {
	for mut handler in handlers.items {
		handler.llm_start(mut ctx, prompts)
	}
}

// dispatch_llm_generate_content_start delivers the chat-model start event.
pub fn (mut handlers Handlers) dispatch_llm_generate_content_start(mut ctx context.Context, messages []schema.Message) {
	for mut handler in handlers.items {
		handler.llm_generate_content_start(mut ctx, messages)
	}
}

// dispatch_llm_generate_content_end delivers a completed chat-model response.
pub fn (mut handlers Handlers) dispatch_llm_generate_content_end(mut ctx context.Context, response llms.Response) {
	for mut handler in handlers.items {
		handler.llm_generate_content_end(mut ctx, response)
	}
}

// dispatch_llm_error delivers a model failure to each handler.
pub fn (mut handlers Handlers) dispatch_llm_error(mut ctx context.Context, err IError) {
	for mut handler in handlers.items {
		handler.llm_error(mut ctx, err)
	}
}

// dispatch_chain_start delivers chain input values.
pub fn (mut handlers Handlers) dispatch_chain_start(mut ctx context.Context, inputs map[string]json2.Any) {
	for mut handler in handlers.items {
		handler.chain_start(mut ctx, inputs)
	}
}

// dispatch_chain_end delivers chain output values.
pub fn (mut handlers Handlers) dispatch_chain_end(mut ctx context.Context, outputs map[string]json2.Any) {
	for mut handler in handlers.items {
		handler.chain_end(mut ctx, outputs)
	}
}

// dispatch_chain_error delivers a chain failure to each handler.
pub fn (mut handlers Handlers) dispatch_chain_error(mut ctx context.Context, err IError) {
	for mut handler in handlers.items {
		handler.chain_error(mut ctx, err)
	}
}

// dispatch_tool_start delivers a tool's input.
pub fn (mut handlers Handlers) dispatch_tool_start(mut ctx context.Context, input string) {
	for mut handler in handlers.items {
		handler.tool_start(mut ctx, input)
	}
}

// dispatch_tool_end delivers a tool's output.
pub fn (mut handlers Handlers) dispatch_tool_end(mut ctx context.Context, output string) {
	for mut handler in handlers.items {
		handler.tool_end(mut ctx, output)
	}
}

// dispatch_tool_error delivers a tool failure to each handler.
pub fn (mut handlers Handlers) dispatch_tool_error(mut ctx context.Context, err IError) {
	for mut handler in handlers.items {
		handler.tool_error(mut ctx, err)
	}
}

// dispatch_agent_action delivers an intermediate agent action.
pub fn (mut handlers Handlers) dispatch_agent_action(mut ctx context.Context, action schema.AgentAction) {
	for mut handler in handlers.items {
		handler.agent_action(mut ctx, action)
	}
}

// dispatch_agent_finish delivers a completed agent result.
pub fn (mut handlers Handlers) dispatch_agent_finish(mut ctx context.Context, finish schema.AgentFinish) {
	for mut handler in handlers.items {
		handler.agent_finish(mut ctx, finish)
	}
}

// dispatch_retriever_start delivers the query sent to a retriever.
pub fn (mut handlers Handlers) dispatch_retriever_start(mut ctx context.Context, query string) {
	for mut handler in handlers.items {
		handler.retriever_start(mut ctx, query)
	}
}

// dispatch_retriever_end delivers the query and documents returned by a retriever.
pub fn (mut handlers Handlers) dispatch_retriever_end(mut ctx context.Context, query string, documents []schema.Document) {
	for mut handler in handlers.items {
		handler.retriever_end(mut ctx, query, documents)
	}
}

// dispatch_streaming_chunk delivers one raw streaming payload.
pub fn (mut handlers Handlers) dispatch_streaming_chunk(mut ctx context.Context, chunk []u8) {
	for mut handler in handlers.items {
		handler.streaming_chunk(mut ctx, chunk)
	}
}
