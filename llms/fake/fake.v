// Package fake provides a deterministic canned-response language model.
module fake

import context
import sync
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

@[heap]
struct State {
mut:
	mutex     sync.Mutex
	responses []string
	index     int
}

// LLM implements llms.Model by returning configured responses in order.
// Calls are concurrency-safe; concurrent callers consume distinct responses.
pub struct LLM {
	state &State
}

// new_fake_llm returns a model that cycles through responses in order.
// An empty response list produces an error until add_response is called.
pub fn new_fake_llm(responses []string) LLM {
	return LLM{
		state: &State{
			responses: responses.clone()
		}
	}
}

// generate_content returns the next response, wrapping to the first response
// after the configured sequence is exhausted. It checks cancellation before
// consuming a response and sends the response to the streaming callback when
// one is configured.
pub fn (llm LLM) generate_content(mut ctx context.Context, _messages []schema.Message, options llms.CallOptions) !llms.Response {
	mut ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}

	mut state := llm.state
	state.mutex.lock()
	if state.responses.len == 0 {
		state.mutex.unlock()
		return error('no responses configured')
	}
	if state.index >= state.responses.len {
		state.index = 0
	}
	response_text := state.responses[state.index]
	state.index++
	state.mutex.unlock()

	if stream := options.streaming_func {
		stream(mut ctx, response_text.bytes()) or {
			return err
		}
		ctx_error = ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
	}

	return llms.Response{
		choices: [llms.Choice{
			content: response_text
		}]
	}
}

// call is the text-only convenience form of generate_content.
pub fn (llm LLM) call(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	response := llm.generate_content(mut ctx, [schema.text_message(.human, prompt)], options)!
	if response.choices.len == 0 {
		return error('empty response from model')
	}
	return response.choices[0].content
}

// complete implements llms.CompletionModel using the canned response sequence.
pub fn (llm LLM) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	return llm.call(mut ctx, prompt, options)
}

// reset restarts the response sequence at its first entry.
pub fn (llm LLM) reset() {
	mut state := llm.state
	state.mutex.lock()
	state.index = 0
	state.mutex.unlock()
}

// add_response appends a response to the sequence.
pub fn (llm LLM) add_response(response string) {
	mut state := llm.state
	state.mutex.lock()
	state.responses << response
	state.mutex.unlock()
}
