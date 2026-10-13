module openai

import context
import net.http
import ulises_jeremias.langchainv.callbacks
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

struct CallbackFakeState {
mut:
	response httputil.Response
}

struct CallbackFakeClient {
	state &CallbackFakeState
}

fn (client CallbackFakeClient) do(mut _ctx context.Context, _request httputil.Request) !httputil.Response {
	return client.state.response
}

struct CallbackRecorder {
	callbacks.SimpleHandler
	state &CallbackRecorderState
}

struct CallbackRecorderState {
mut:
	events  []string
	content string
	err_msg string
}

fn (mut handler CallbackRecorder) llm_generate_content_start(mut _ctx context.Context, _messages []schema.Message) {
	mut state := handler.state
	state.events << 'start'
}

fn (mut handler CallbackRecorder) llm_generate_content_end(mut _ctx context.Context, response llms.Response) {
	mut state := handler.state
	state.events << 'end'
	if response.choices.len > 0 {
		state.content = response.choices[0].content
	}
}

fn (mut handler CallbackRecorder) llm_error(mut _ctx context.Context, err IError) {
	mut state := handler.state
	state.events << 'error'
	state.err_msg = err.msg()
}

fn new_callback_client(body string, status int, state &CallbackRecorderState) Client {
	return new_client_with_options('test-secret', CallbackFakeClient{
		state: &CallbackFakeState{
			response: httputil.Response{
				status_code: status
				headers:     http.Header{}
				body:        body
			}
		}
	}, Options{
		base_url:  'https://openai.test/v1'
		model:     'test-model'
		callbacks: callbacks.Handler(CallbackRecorder{
			state: state
		})
	}) or { panic(err) }
}

fn test_generate_content_dispatches_start_and_end_callbacks() {
	mut recorder := &CallbackRecorderState{}
	client := new_callback_client('{"choices":[{"index":0,"message":{"role":"assistant","content":"hello"},"finish_reason":"stop"}],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}', 200, recorder)
	mut ctx := context.background()
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{}) or {
		panic(err)
	}
	assert response.choices[0].content == 'hello'
	assert recorder.events == ['start', 'end']
	assert recorder.content == 'hello'
}

fn test_generate_content_dispatches_error_callback() {
	mut recorder := &CallbackRecorderState{}
	client := new_callback_client('secret failure body', 500, recorder)
	mut ctx := context.background()
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{}) or {
		assert recorder.events == ['start', 'error']
		assert recorder.err_msg.contains('HTTP 500')
		assert !recorder.err_msg.contains('secret failure body')
		return
	}
	assert false, 'expected the HTTP error to fail'
}

fn test_generate_content_without_callbacks_still_works() {
	mut state := &CallbackFakeState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"choices":[{"index":0,"message":{"role":"assistant","content":"plain"},"finish_reason":"stop"}]}'
		}
	}
	client := new_client_with_options('test-secret', CallbackFakeClient{
		state: state
	}, Options{
		base_url: 'https://openai.test/v1'
		model:    'test-model'
	}) or { panic(err) }
	mut ctx := context.background()
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{}) or {
		panic(err)
	}
	assert response.choices[0].content == 'plain'
}
