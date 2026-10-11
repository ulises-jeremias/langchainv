module local

import context
import time
import ulises_jeremias.langchainv.callbacks
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

@[heap]
struct LocalFixtureCallbackState {
mut:
	start_count      int
	end_count        int
	started_messages int
	final_output     string
}

struct LocalFixtureCallbacks {
	callbacks.SimpleHandler
	state &LocalFixtureCallbackState
}

fn (mut handler LocalFixtureCallbacks) llm_generate_content_start(mut _ctx context.Context, messages []schema.Message) {
	mut state := handler.state
	state.start_count++
	state.started_messages = messages.len
}

fn (mut handler LocalFixtureCallbacks) llm_generate_content_end(mut _ctx context.Context, response llms.Response) {
	mut state := handler.state
	state.end_count++
	state.final_output = response.choices[0].content
}

fn test_client_runs_configured_binary_with_literal_arguments() {
	mut client := new_client(Options{
		bin_path: 'echo'
		args:     ['-n']
	}) or { panic(err) }
	mut ctx := context.background()
	assert client.complete(mut ctx, 'hello world', llms.CallOptions{}) or { panic(err) } == 'hello world'
}

fn test_global_generation_arguments_are_built_per_call() {
	mut client := new_client(Options{
		bin_path:       'echo'
		args:           ['-n']
		global_as_args: true
	}) or { panic(err) }
	mut ctx := context.background()
	options := llms.CallOptions{
		temperature: 0.7
		top_k:       40
		max_length:  100
	}
	want := '--temperature=0.700000 --top_k=40 --max_length=100 prompt'
	assert client.complete(mut ctx, 'prompt', options) or { panic(err) } == want
	assert client.complete(mut ctx, 'prompt', options) or { panic(err) } == want
}

fn test_client_dispatches_generation_callbacks() {
	mut client := new_client(Options{
		bin_path: 'echo'
		args:     ['-n']
	}) or { panic(err) }
	mut state := &LocalFixtureCallbackState{}
	client.callbacks = callbacks.Handler(LocalFixtureCallbacks{
		state: state
	})
	mut ctx := context.background()
	assert client.complete(mut ctx, 'callback output', llms.CallOptions{}) or { panic(err) } == 'callback output'
	assert state.start_count == 1
	assert state.end_count == 1
	assert state.started_messages == 1
	assert state.final_output == 'callback output'
}

fn test_client_rejects_missing_binaries_and_oversized_inputs() {
	new_client(Options{
		bin_path: 'langchainv-binary-that-does-not-exist'
	}) or {
		assert err.msg().contains('not found')
		return
	}
	mut client := new_client(Options{
		bin_path:         'echo'
		args:             ['-n']
		max_prompt_bytes: 3
	}) or { panic(err) }
	mut ctx := context.background()
	client.complete(mut ctx, 'long', llms.CallOptions{}) or {
		assert err.msg().contains('prompt exceeds')
		return
	}
	assert false, 'expected the configured prompt limit to be enforced'
}

fn test_client_rejects_multimodal_messages() {
	mut client := new_client(Options{
		bin_path: 'echo'
	}) or { panic(err) }
	mut ctx := context.background()
	client.generate_content(mut ctx, [schema.Message{
		role:  .human
		parts: [schema.ContentPart(schema.TextPart{
			text: 'text'
		}), schema.ContentPart(schema.ImageURLPart{
			url: 'https://example.test/image.png'
		})]
	}], llms.CallOptions{}) or {
		assert err.msg().contains('exactly one text content part')
		return
	}
	assert false, 'expected multimodal input to be rejected'
}

fn test_client_honors_context_deadline_and_kills_child_process_group() {
	mut client := new_client(Options{
		bin_path: 'sh'
		args:     ['-c', 'sleep 30', '_']
	}) or { panic(err) }
	mut parent := context.background()
	mut ctx, cancel := context.with_timeout(mut parent, 50 * time.millisecond)
	defer {
		cancel()
	}
	client.complete(mut ctx, 'unused', llms.CallOptions{}) or {
		assert err.msg().contains('deadline')
		return
	}
	assert false, 'expected the local command deadline to cancel'
}

fn test_client_stops_process_when_output_exceeds_limit() {
	mut client := new_client(Options{
		bin_path:         'sh'
		args:             ['-c', 'head -c 4096 /dev/zero', '_']
		max_output_bytes: 64
	}) or { panic(err) }
	mut ctx := context.background()
	client.complete(mut ctx, 'unused', llms.CallOptions{}) or {
		assert err.msg().contains('output exceeds 64 bytes')
		return
	}
	assert false, 'expected output beyond the configured cap to fail'
}
