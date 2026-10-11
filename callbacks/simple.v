// Package callbacks provides a no-op handler for selectively implemented hooks.
module callbacks

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

// SimpleHandler implements every hook without taking action. Embed it in a
// custom handler to provide no-op behavior for events that are not needed.
pub struct SimpleHandler {}

// text ignores text events.
pub fn (mut handler SimpleHandler) text(mut ctx context.Context, text string) {}

// llm_start ignores completion-model start events.
pub fn (mut handler SimpleHandler) llm_start(mut ctx context.Context, prompts []string) {}

// llm_generate_content_start ignores chat-model start events.
pub fn (mut handler SimpleHandler) llm_generate_content_start(mut ctx context.Context, messages []schema.Message) {}

// llm_generate_content_end ignores completed chat-model responses.
pub fn (mut handler SimpleHandler) llm_generate_content_end(mut ctx context.Context, response llms.Response) {}

// llm_error ignores model errors.
pub fn (mut handler SimpleHandler) llm_error(mut ctx context.Context, err IError) {}

// chain_start ignores chain start events.
pub fn (mut handler SimpleHandler) chain_start(mut ctx context.Context, inputs map[string]json2.Any) {}

// chain_end ignores chain end events.
pub fn (mut handler SimpleHandler) chain_end(mut ctx context.Context, outputs map[string]json2.Any) {}

// chain_error ignores chain errors.
pub fn (mut handler SimpleHandler) chain_error(mut ctx context.Context, err IError) {}

// tool_start ignores tool start events.
pub fn (mut handler SimpleHandler) tool_start(mut ctx context.Context, input string) {}

// tool_end ignores tool end events.
pub fn (mut handler SimpleHandler) tool_end(mut ctx context.Context, output string) {}

// tool_error ignores tool errors.
pub fn (mut handler SimpleHandler) tool_error(mut ctx context.Context, err IError) {}

// agent_action ignores intermediate agent actions.
pub fn (mut handler SimpleHandler) agent_action(mut ctx context.Context, action schema.AgentAction) {}

// agent_finish ignores agent completion events.
pub fn (mut handler SimpleHandler) agent_finish(mut ctx context.Context, finish schema.AgentFinish) {}

// retriever_start ignores retriever start events.
pub fn (mut handler SimpleHandler) retriever_start(mut ctx context.Context, query string) {}

// retriever_end ignores retriever results.
pub fn (mut handler SimpleHandler) retriever_end(mut ctx context.Context, query string, documents []schema.Document) {}

// streaming_chunk ignores streaming payloads.
pub fn (mut handler SimpleHandler) streaming_chunk(mut ctx context.Context, chunk []u8) {}
