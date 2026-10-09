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
