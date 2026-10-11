module llmtest

import context
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

struct FixtureModel {
	state &FixtureState
}

@[heap]
struct FixtureState {
mut:
	call_count                 int
	last_messages              []schema.Message
	ignore_cancellation        bool
	silent_stream              bool
	ignore_stream_callback_err bool
	no_tool_call               bool
	invalid_tool_args          bool
	no_usage                   bool
	empty_response             bool
}

fn (model FixtureModel) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	mut state := model.state
	state.call_count++
	state.last_messages = messages.clone()
	if !state.ignore_cancellation {
		ctx_error := ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
	}
	if state.empty_response {
		return llms.Response{}
	}
	if stream := options.streaming_func {
		if !state.silent_stream {
			stream(mut ctx, 'OK'.bytes()) or {
				if !state.ignore_stream_callback_err {
					return err
				}
			}
		}
	}
	if options.tools.len > 0 && !state.no_tool_call {
		for message in messages {
			for part in message.parts {
				if part is schema.ToolResult {
					return fixture_text_response(state.no_usage)
				}
			}
		}
		arguments := if state.invalid_tool_args {
			'{bad-json'
		} else {
			'{"location":"Paris"}'
		}
		call := schema.ToolCall{
			id:            'fixture-call'
			call_type:     'function'
			function_call: schema.FunctionCall{
				name:      options.tools[0].name
				arguments: arguments
			}
		}
		return llms.Response{
			choices: [llms.Choice{
				tool_calls: [call]
				parts:      [schema.ContentPart(call)]
			}]
		}
	}
	return fixture_text_response(state.no_usage)
}

fn fixture_text_response(no_usage bool) llms.Response {
	return llms.Response{
		choices: [llms.Choice{
			content: 'OK'
		}]
		usage:   if no_usage {
			llms.Usage{}
		} else {
			llms.Usage{
				prompt_tokens:     2
				completion_tokens: 1
				total_tokens:      3
			}
		}
	}
}

fn fixture_model() (FixtureModel, &FixtureState) {
	mut state := &FixtureState{}
	return FixtureModel{
		state: state
	}, state
}

fn test_test_model_checks_core_contract_and_cancellation() {
	mut ctx := context.background()
	model, state := fixture_model()
	test_model(mut ctx, model) or { panic(err) }
	assert state.call_count == 2
	assert state.last_messages.len == 1
}

fn test_test_model_checks_multiturn_streaming_tools_and_usage() {
	mut ctx := context.background()
	model, state := fixture_model()
	test_model(mut ctx, model, 'multiturn', 'streaming', 'tools', 'usage') or { panic(err) }
	assert state.call_count == 8
}

fn test_test_model_reports_unknown_capabilities_and_contract_failures() {
	mut ctx := context.background()
	mut model, state := fixture_model()
	state.silent_stream = true
	state.no_tool_call = true
	state.no_usage = true
	test_model(mut ctx, model, 'telepathy', 'streaming', 'tools', 'usage') or {
		assert err.msg().contains('unknown model capability `telepathy`')
		assert err.msg().contains('streaming callback received no chunks')
		assert err.msg().contains('did not contain a tool call')
		assert err.msg().contains('no positive token count')
		return
	}
	assert false, 'expected contract violations to be reported'
}

fn test_test_model_requires_callback_errors_to_abort_streaming() {
	mut ctx := context.background()
	mut model, state := fixture_model()
	state.ignore_stream_callback_err = true
	test_model(mut ctx, model, 'streaming') or {
		assert err.msg().contains('callback returned an error')
		return
	}
	assert false, 'expected swallowed callback failure to be reported'
}

fn test_test_model_reports_empty_success_responses() {
	mut ctx := context.background()
	mut model, state := fixture_model()
	state.empty_response = true
	test_model(mut ctx, model) or {
		assert err.msg().contains('response has no choices')
		return
	}
	assert false, 'expected an empty success response to be reported'
}

fn test_test_model_validates_tool_call_arguments() {
	mut ctx := context.background()
	mut model, state := fixture_model()
	state.invalid_tool_args = true
	test_model(mut ctx, model, 'tools') or {
		assert err.msg().contains('not a JSON object')
		return
	}
	assert false, 'expected invalid tool arguments to be reported'
}
