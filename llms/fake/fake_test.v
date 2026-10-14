module fake

import context
import sync
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

@[heap]
struct StreamTextCapture {
mut:
	value string
}

@[heap]
struct ResponseCapture {
mut:
	mutex  sync.Mutex
	values map[string]int
}

fn next_response(mut ctx context.Context, model LLM) !string {
	response := model.generate_content(mut ctx, [schema.text_message(.human, 'hello')], llms.CallOptions{})!
	if response.choices.len == 0 {
		return error('fake model returned no choices')
	}
	return response.choices[0].content
}

fn test_fake_model_returns_responses_in_order_and_wraps() {
	model := new_fake_llm(['first', 'second'])
	mut ctx := context.background()
	assert next_response(mut ctx, model)! == 'first'
	assert next_response(mut ctx, model)! == 'second'
	assert next_response(mut ctx, model)! == 'first'
	model.reset()
	assert next_response(mut ctx, model)! == 'first'
}

fn test_empty_model_can_receive_responses_later() {
	model := new_fake_llm([])
	mut ctx := context.background()
	next_response(mut ctx, model) or {
		assert err.msg() == 'no responses configured'
		model.add_response('added')
		assert next_response(mut ctx, model)! == 'added'
		return
	}
	assert false, 'expected an error when no responses are configured'
}

fn test_cancelled_context_does_not_consume_response() {
	model := new_fake_llm(['first', 'second'])
	mut parent := context.background()
	mut ctx, cancel := context.with_cancel(mut parent)
	cancel()
	next_response(mut ctx, model) or {
		assert err.msg().contains('cancel')
		mut live_ctx := context.background()
		assert next_response(mut live_ctx, model)! == 'first'
		return
	}
	assert false, 'expected canceled generation to fail'
}

fn test_streaming_callback_receives_response() {
	model := new_fake_llm(['stream me'])
	mut ctx := context.background()
	mut streamed := &StreamTextCapture{}
	stream := llms.StreamFunc(fn [mut streamed] (mut _ctx context.Context, chunk []u8) ! {
		streamed.value += chunk.bytestr()
	})
	response := model.generate_content(mut ctx, [schema.text_message(.human, 'hello')], llms.CallOptions{
		streaming_func: stream
	})!
	assert streamed.value == 'stream me'
	assert response.choices[0].content == streamed.value
}

fn test_streaming_callback_error_is_returned_and_response_is_consumed() {
	model := new_fake_llm(['first', 'second'])
	mut ctx := context.background()
	stream := llms.StreamFunc(fn (mut _ctx context.Context, _chunk []u8) ! {
		return error('stop stream')
	})
	model.generate_content(mut ctx, [schema.text_message(.human, 'hello')], llms.CallOptions{
		streaming_func: stream
	}) or {
		assert err.msg() == 'stop stream'
		assert next_response(mut ctx, model)! == 'second'
		return
	}
	assert false, 'expected the streaming callback error'
}

fn test_streaming_callback_cancellation_is_returned() {
	model := new_fake_llm(['response'])
	mut parent := context.background()
	mut ctx, cancel := context.with_cancel(mut parent)
	stream := llms.StreamFunc(fn [cancel] (mut _ctx context.Context, _chunk []u8) ! {
		cancel()
	})
	model.generate_content(mut ctx, [schema.text_message(.human, 'hello')], llms.CallOptions{
		streaming_func: stream
	}) or {
		assert err.msg().contains('cancel')
		return
	}
	assert false, 'expected callback cancellation to abort generation'
}

fn test_call_and_completion_model_use_the_response_sequence() {
	model := new_fake_llm(['reply'])
	mut ctx := context.background()
	assert model.call(mut ctx, 'prompt', llms.CallOptions{})! == 'reply'
	assert model.complete(mut ctx, 'prompt', llms.CallOptions{})! == 'reply'
}

fn test_concurrent_calls_consume_distinct_responses() {
	model := new_fake_llm(['one', 'two'])
	mut capture := &ResponseCapture{
		values: map[string]int{}
	}
	mut wait_group := sync.new_waitgroup()
	wait_group.add(2)
	for _ in 0 .. 2 {
		go fn [model, mut capture, mut wait_group] () {
			mut ctx := context.background()
			response := model.generate_content(mut ctx, [schema.text_message(.human, 'hello')],
				llms.CallOptions{}) or {
				wait_group.done()
				panic(err)
			}
			mut state := capture
			state.mutex.lock()
			state.values[response.choices[0].content]++
			state.mutex.unlock()
			wait_group.done()
		}()
	}
	wait_group.wait()
	assert capture.values['one'] == 1
	assert capture.values['two'] == 1
}
