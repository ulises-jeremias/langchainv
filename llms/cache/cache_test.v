module cache

import context
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.fake
import ulises_jeremias.langchainv.llms.cache.inmemory
import ulises_jeremias.langchainv.schema

fn test_cache_reuses_model_response_for_same_request() {
	model := fake.new_fake_llm(['first', 'second'])
	backend := inmemory.new_cache(4) or { panic(err) }
	cacher := new_cacher(llms.Model(model), backend)
	mut ctx := context.background()
	messages := [schema.text_message(.human, 'hello')]
	first := cacher.generate_content(mut ctx, messages, llms.CallOptions{})!
	second := cacher.generate_content(mut ctx, messages, llms.CallOptions{})!
	assert first.choices[0].content == 'first'
	assert second.choices[0].content == 'first'
}

fn test_cache_key_includes_message_and_generation_options() {
	messages := [schema.text_message(.human, 'hello')]
	base := cache_key(messages, llms.CallOptions{})
	assert base != cache_key([schema.text_message(.human, 'different')], llms.CallOptions{})
	assert base != cache_key(messages, llms.CallOptions{ temperature: 0.5 })
	assert base == cache_key(messages, llms.CallOptions{ streaming_func: llms.StreamFunc(fn (mut _ctx context.Context, _chunk []u8) ! {}) })
}

@[heap]
struct StreamCapture {
mut:
	text string
}

fn test_cache_hit_replays_streaming_callback() {
	backend := inmemory.new_cache(2) or { panic(err) }
	model := fake.new_fake_llm(['unused'])
	cacher := new_cacher(llms.Model(model), backend)
	mut ctx := context.background()
	messages := [schema.text_message(.human, 'prompt')]
	mut captured := &StreamCapture{}
	callback := llms.StreamFunc(fn [mut captured] (mut _ctx context.Context, chunk []u8) ! {
		captured.text += chunk.bytestr()
	})
	options := llms.CallOptions{ streaming_func: callback }
	backend.put(mut ctx, cache_key(messages, options), llms.Response{ choices: [llms.Choice{ content: 'cached' }] })!
	response := cacher.generate_content(mut ctx, messages, options)!
	assert response.choices[0].content == 'cached'
	assert captured.text == 'cached'
}

fn test_reasoning_stream_requests_bypass_cache() {
	backend := inmemory.new_cache(2) or { panic(err) }
	model := fake.new_fake_llm(['first', 'second'])
	cacher := new_cacher(llms.Model(model), backend)
	mut ctx := context.background()
	options := llms.CallOptions{streaming_reasoning_func: llms.ReasoningStreamFunc(fn (mut _ctx context.Context, _reasoning []u8, _content []u8) ! {})}
	messages := [schema.text_message(.human, 'prompt')]
	first := cacher.generate_content(mut ctx, messages, options)!
	second := cacher.generate_content(mut ctx, messages, options)!
	assert first.choices[0].content == 'first'
	assert second.choices[0].content == 'second'
}
