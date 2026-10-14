module watsonx

import context
import net.http
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

@[heap]
struct StreamFixtureState {
mut:
	requests []httputil.Request
	body     string
}

struct StreamFixtureClient {
	state &StreamFixtureState
}

fn (client StreamFixtureClient) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	return httputil.Response{
		status_code: 200
		headers:     http.Header{}
		body:        state.body
	}
}

fn (client StreamFixtureClient) do_stream(mut ctx context.Context, request httputil.Request, handler httputil.StreamHandler) !httputil.Response {
	mut state := client.state
	state.requests << request
	body := state.body.bytes()
	mut offset := 0
	for offset < body.len {
		end := if offset + 17 < body.len { offset + 17 } else { body.len }
		handler(mut ctx, body[offset..end])!
		offset = end
	}
	return httputil.Response{
		status_code: 200
		headers:     http.Header{}
	}
}

struct StreamTextCapture {
mut:
	value string
}

fn test_generate_content_streams_cumulative_text() {
	mut state := &StreamFixtureState{
		body: 'id: 1\nevent: message\ndata: {"results":[{"generated_text":"","generated_token_count":0,"input_token_count":9,"stop_reason":"not_finished"}]}\n\nid: 2\nevent: message\ndata: {"results":[{"generated_text":"hel","generated_token_count":1,"input_token_count":0,"stop_reason":"not_finished"}]}\n\nid: 3\nevent: message\ndata: {"results":[{"generated_text":"lo","generated_token_count":2,"input_token_count":0,"stop_reason":"EOS_TOKEN"}]}\n\n'
	}
	mut client := new_client(Options{
		project_id:   'project-123'
		model:        'ibm/granite-3-8b-instruct'
		access_token: 'iam-access-token'
		base_url:     'https://watsonx.test'
	}, httputil.HTTPClient(StreamFixtureClient{
		state: state
	})) or { panic(err) }
	mut streamed := &StreamTextCapture{}
	stream := llms.StreamFunc(fn [mut streamed] (mut _ context.Context, chunk []u8) ! {
		streamed.value += chunk.bytestr()
	})
	mut ctx := context.background()
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'question')], llms.CallOptions{
		streaming_func: stream
	}) or { panic(err) }
	assert streamed.value == 'hello'
	assert response.choices[0].content == 'hello'
	assert response.choices[0].stop_reason == 'EOS_TOKEN'
	assert response.usage.prompt_tokens == 9
	assert response.usage.completion_tokens == 2
	assert state.requests[0].url == 'https://watsonx.test/ml/v1/text/generation_stream?version=2024-05-20'
	assert state.requests[0].headers['Accept'] == 'text/event-stream'
}

fn test_generate_content_rejects_reasoning_streaming() {
	mut state := &StreamFixtureState{}
	mut client := new_client(Options{
		project_id:   'project-123'
		model:        'ibm/granite-3-8b-instruct'
		access_token: 'iam-access-token'
		base_url:     'https://watsonx.test'
	}, httputil.HTTPClient(StreamFixtureClient{
		state: state
	})) or { panic(err) }
	reasoning_stream := llms.ReasoningStreamFunc(fn (mut _ context.Context, _ []u8, _ []u8) ! {})
	mut ctx := context.background()
	client.generate_content(mut ctx, [schema.text_message(.human, 'question')], llms.CallOptions{
		streaming_reasoning_func: reasoning_stream
	}) or {
		assert err.msg().contains('unsupported')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected reasoning streaming to fail'
}

fn test_generate_content_propagates_stream_callback_errors() {
	mut state := &StreamFixtureState{
		body: 'data: {"results":[{"generated_text":"chunk","generated_token_count":1,"input_token_count":1,"stop_reason":"not_finished"}]}\n\n'
	}
	mut client := new_client(Options{
		project_id:   'project-123'
		model:        'ibm/granite-3-8b-instruct'
		access_token: 'iam-access-token'
		base_url:     'https://watsonx.test'
	}, httputil.HTTPClient(StreamFixtureClient{
		state: state
	})) or { panic(err) }
	stream := llms.StreamFunc(fn (mut _ context.Context, _ []u8) ! {
		return error('consumer stopped')
	})
	mut ctx := context.background()
	client.generate_content(mut ctx, [schema.text_message(.human, 'question')], llms.CallOptions{
		streaming_func: stream
	}) or {
		assert err.msg().contains('consumer stopped')
		return
	}
	assert false, 'expected callback failure to stop the stream'
}
