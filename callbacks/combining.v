// Package callbacks provides ordered fan-out to multiple lifecycle handlers.
module callbacks

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

// CombiningHandler forwards every event to its child handlers in order.
pub struct CombiningHandler {
pub mut:
	handlers Handlers
}

// new_combining_handler copies handlers so later edits to the caller's slice
// do not change this handler's dispatch list.
pub fn new_combining_handler(handlers []Handler) CombiningHandler {
	return CombiningHandler{
		handlers: Handlers{
			items: handlers.clone()
		}
	}
}

// text forwards text events to every child handler.
pub fn (mut handler CombiningHandler) text(mut ctx context.Context, text string) {
	handler.handlers.dispatch_text(mut ctx, text)
}

// llm_start forwards completion-model start events.
pub fn (mut handler CombiningHandler) llm_start(mut ctx context.Context, prompts []string) {
	handler.handlers.dispatch_llm_start(mut ctx, prompts)
}

// llm_generate_content_start forwards chat-model start events.
pub fn (mut handler CombiningHandler) llm_generate_content_start(mut ctx context.Context, messages []schema.Message) {
	handler.handlers.dispatch_llm_generate_content_start(mut ctx, messages)
}

// llm_generate_content_end forwards completed chat-model responses.
pub fn (mut handler CombiningHandler) llm_generate_content_end(mut ctx context.Context, response llms.Response) {
	handler.handlers.dispatch_llm_generate_content_end(mut ctx, response)
}

// llm_error forwards model errors.
pub fn (mut handler CombiningHandler) llm_error(mut ctx context.Context, err IError) {
	handler.handlers.dispatch_llm_error(mut ctx, err)
}

// chain_start forwards chain inputs.
pub fn (mut handler CombiningHandler) chain_start(mut ctx context.Context, inputs map[string]json2.Any) {
	handler.handlers.dispatch_chain_start(mut ctx, inputs)
}

// chain_end forwards chain outputs.
pub fn (mut handler CombiningHandler) chain_end(mut ctx context.Context, outputs map[string]json2.Any) {
	handler.handlers.dispatch_chain_end(mut ctx, outputs)
}

// chain_error forwards chain errors.
pub fn (mut handler CombiningHandler) chain_error(mut ctx context.Context, err IError) {
	handler.handlers.dispatch_chain_error(mut ctx, err)
}

// tool_start forwards tool inputs.
pub fn (mut handler CombiningHandler) tool_start(mut ctx context.Context, input string) {
	handler.handlers.dispatch_tool_start(mut ctx, input)
}

// tool_end forwards tool outputs.
pub fn (mut handler CombiningHandler) tool_end(mut ctx context.Context, output string) {
	handler.handlers.dispatch_tool_end(mut ctx, output)
}

// tool_error forwards tool errors.
pub fn (mut handler CombiningHandler) tool_error(mut ctx context.Context, err IError) {
	handler.handlers.dispatch_tool_error(mut ctx, err)
}

// agent_action forwards intermediate agent actions.
pub fn (mut handler CombiningHandler) agent_action(mut ctx context.Context, action schema.AgentAction) {
	handler.handlers.dispatch_agent_action(mut ctx, action)
}

// agent_finish forwards completed agent results.
pub fn (mut handler CombiningHandler) agent_finish(mut ctx context.Context, finish schema.AgentFinish) {
	handler.handlers.dispatch_agent_finish(mut ctx, finish)
}

// retriever_start forwards retrieval queries.
pub fn (mut handler CombiningHandler) retriever_start(mut ctx context.Context, query string) {
	handler.handlers.dispatch_retriever_start(mut ctx, query)
}

// retriever_end forwards retrieved documents.
pub fn (mut handler CombiningHandler) retriever_end(mut ctx context.Context, query string, documents []schema.Document) {
	handler.handlers.dispatch_retriever_end(mut ctx, query, documents)
}

// streaming_chunk forwards raw streaming payloads.
pub fn (mut handler CombiningHandler) streaming_chunk(mut ctx context.Context, chunk []u8) {
	handler.handlers.dispatch_streaming_chunk(mut ctx, chunk)
}
