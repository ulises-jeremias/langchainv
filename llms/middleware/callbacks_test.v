module middleware

import context
import ulises_jeremias.langchainv.callbacks
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

struct FixtureModel {
	response llms.Response
	fail     bool
}

fn (model FixtureModel) generate_content(mut _ctx context.Context, _messages []schema.Message, _options llms.CallOptions) !llms.Response {
	if model.fail {
		return error('fixture model failure')
	}
	return model.response
}

struct CallbackState {
mut:
	events []string
}

struct RecordingHandler {
	callbacks.SimpleHandler
mut:
	state &CallbackState
}

fn (mut handler RecordingHandler) llm_generate_content_start(mut _ctx context.Context, _messages []schema.Message) {
	handler.state.events << 'start'
}

fn (mut handler RecordingHandler) llm_generate_content_end(mut _ctx context.Context, _response llms.Response) {
	handler.state.events << 'end'
}

fn (mut handler RecordingHandler) llm_error(mut _ctx context.Context, _err IError) {
	handler.state.events << 'error'
}

fn test_callback_model_dispatches_start_and_end() {
	mut state := &CallbackState{}
	mut model := with_callbacks(FixtureModel{
		response: llms.Response{
			choices: [llms.Choice{
				content: 'ok'
			}]
		}
	}, callbacks.Handler(RecordingHandler{
		state: state
	}))
	mut ctx := context.background()
	response := model.generate_content(mut ctx, [schema.text_message(.human, 'hello')], llms.CallOptions{}) or {
		panic(err)
	}
	assert response.choices[0].content == 'ok'
	assert state.events == ['start', 'end']
}

fn test_callback_model_dispatches_error_and_preserves_it() {
	mut state := &CallbackState{}
	mut model := with_callbacks(FixtureModel{
		fail: true
	}, callbacks.Handler(RecordingHandler{
		state: state
	}))
	mut ctx := context.background()
	model.generate_content(mut ctx, [schema.text_message(.human, 'hello')], llms.CallOptions{}) or {
		assert err.msg() == 'fixture model failure'
		assert state.events == ['start', 'error']
		return
	}
	assert false, 'expected the model error to propagate'
}
