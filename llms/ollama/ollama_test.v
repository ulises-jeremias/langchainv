module ollama

import context
import net.http
import json2
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

struct FakeHTTPClient {
	state &FakeHTTPState
}

struct FakeHTTPState {
mut:
	requests []httputil.Request
	response httputil.Response
}

fn (client FakeHTTPClient) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	return state.response
}

fn new_fixture_client(body string, status int) (Client, &FakeHTTPState) {
	mut state := &FakeHTTPState{
		response: httputil.Response{
			status_code: status
			headers:     http.Header{}
			body:        body
		}
	}
	client := new_client(FakeHTTPClient{
		state: state
	}, Options{
		base_url:   'http://ollama.test:11434'
		model:      'gemma4'
		keep_alive: '5m'
	}) or { panic(err) }
	return client, state
}

fn test_generate_content_sends_chat_options_and_maps_usage() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"message":{"role":"assistant","content":"hello"},"done_reason":"stop","prompt_eval_count":7,"eval_count":3}', 200)
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		max_tokens:  128
		temperature: 0.5
		top_k:       8
		top_p:       0.9
		stop_words:  ['END']
	}) or { panic(err) }
	assert response.choices.len == 1
	assert response.choices[0].content == 'hello'
	assert response.choices[0].stop_reason == 'stop'
	assert response.usage.prompt_tokens == 7
	assert response.usage.completion_tokens == 3
	assert response.usage.total_tokens == 10
	assert response.assistant_message().text() == 'hello'
	assert state.requests.len == 1
	assert state.requests[0].url == 'http://ollama.test:11434/api/chat'
	assert state.requests[0].body.contains('"model":"gemma4"')
	assert state.requests[0].body.contains('"keep_alive":"5m"')
	assert state.requests[0].body.contains('"stream":false')
	assert state.requests[0].body.contains('"num_predict":128')
	assert state.requests[0].body.contains('"temperature":0.5')
	assert state.requests[0].body.contains('"top_k":8')
	assert state.requests[0].body.contains('"top_p":0.9')
	assert state.requests[0].body.contains('"stop":["END"]')
}

fn test_generate_content_encodes_tools_and_maps_tool_calls() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"lookup","arguments":{"q":"v"}}}]},"done_reason":"tool_calls"}', 200)
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'lookup')], llms.CallOptions{
		tools: [schema.ToolDefinition{
			name:        'lookup'
			description: 'Look up a value'
			parameters:  json2.Any(map[string]json2.Any{
				'type': json2.Any('object')
			})
		}]
	}) or { panic(err) }
	assert response.choices[0].tool_calls.len == 1
	assert response.choices[0].tool_calls[0].function_call.name == 'lookup'
	assert response.choices[0].tool_calls[0].function_call.arguments.contains('"q":"v"')
	assert response.assistant_message().text() == ''
	assert response.assistant_message().parts.len == 1
	assert state.requests[0].body.contains('"tools"')
	assert state.requests[0].body.contains('"description":"Look up a value"')
}

fn test_generate_content_replays_assistant_tool_history_and_thinking() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"message":{"role":"assistant","content":"done","thinking":"reason"}}', 200)
	client.generate_content(mut ctx, [
		schema.Message{
			role:  .ai
			parts: [schema.ContentPart(schema.ThinkingPart{
				text: 'prior reasoning'
			}), schema.ContentPart(schema.ToolCall{
				id:            'call-1'
				call_type:     'function'
				function_call: schema.FunctionCall{
					name:      'lookup'
					arguments: '{"q":"old"}'
				}
			})]
		},
		schema.Message{
			role:  .tool
			parts: [schema.ContentPart(schema.ToolResult{
				call_id: 'call-1'
				name:    'lookup'
				content: 'found'
			})]
		},
	], llms.CallOptions{}) or { panic(err) }
	assert state.requests[0].body.contains('"thinking":"prior reasoning"')
	assert state.requests[0].body.contains('"tool_calls"')
	assert state.requests[0].body.contains('"tool_name":"lookup"')
	assert state.requests[0].body.contains('"content":"found"')
}

fn test_generate_content_encodes_inline_image_and_json_mode() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"message":{"role":"assistant","content":"{}"}}', 200)
	client.generate_content(mut ctx, [schema.Message{
		role:  .human
		parts: [
			schema.ContentPart(schema.TextPart{
				text: 'describe'
			}),
			schema.ContentPart(schema.BinaryPart{
				mime_type: 'image/png'
				data:      [u8(1), 2]
			}),
		]
	}], llms.CallOptions{
		json_mode: true
	}) or { panic(err) }
	assert state.requests[0].body.contains('"format":"json"')
	assert state.requests[0].body.contains('"images":["AQI="]')
}

fn test_generate_content_rejects_unsupported_options_before_network() {
	mut ctx := context.background()
	client, state := new_fixture_client('{}', 200)
	stream := llms.StreamFunc(fn (mut _ context.Context, _ []u8) ! {})
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		streaming_func: stream
	}) or {
		assert err.msg().contains('streaming is not supported')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected streaming to be rejected'
}

fn test_generate_content_bounds_message_count_before_network() {
	mut ctx := context.background()
	client, state := new_fixture_client('{}', 200)
	mut messages := []schema.Message{cap: 1025}
	for _ in 0 .. 1025 {
		messages << schema.text_message(.human, 'x')
	}
	client.generate_content(mut ctx, messages, llms.CallOptions{}) or {
		assert err.msg().contains('1024-message limit')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected excess messages to fail'
}

fn test_generate_content_bounds_tool_count_before_network() {
	mut ctx := context.background()
	client, state := new_fixture_client('{}', 200)
	mut tools := []schema.ToolDefinition{cap: 129}
	for index in 0 .. 129 {
		tools << schema.ToolDefinition{
			name: 'tool-${index}'
		}
	}
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		tools: tools
	}) or {
		assert err.msg().contains('128-tool limit')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected excess tools to fail'
}

fn test_generate_content_rejects_image_urls_and_redacts_http_errors() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"error":"private server detail"}', 500)
	client.generate_content(mut ctx, [schema.Message{
		role:  .human
		parts: [schema.ContentPart(schema.ImageURLPart{
			url: 'https://example.test/image.png'
		})]
	}], llms.CallOptions{}) or {
		assert err.msg().contains('inline image data')
		assert state.requests.len == 0
		return
	}
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{}) or {
		assert err.msg() == 'Ollama chat request returned HTTP 500'
		assert !err.msg().contains('private server detail')
		return
	}
	assert false, 'expected an HTTP status error'
}

fn test_client_rejects_invalid_model_format_and_userinfo() {
	new_client(FakeHTTPClient{
		state: &FakeHTTPState{}
	}, Options{}) or {
		assert err.msg().contains('model must not be empty')
		return
	}
	assert false, 'expected an empty model to fail'
	new_client(FakeHTTPClient{
		state: &FakeHTTPState{}
	}, Options{
		model:  'gemma4'
		format: 'xml'
	}) or {
		assert err.msg().contains('format must be empty or `json`')
		return
	}
	assert false, 'expected an unsupported format to fail'
	new_client(FakeHTTPClient{
		state: &FakeHTTPState{}
	}, Options{
		base_url: 'http://user:secret@localhost:11434'
		model:    'gemma4'
	}) or {
		assert err.msg().contains('user information')
		return
	}
	assert false, 'expected URL credentials to fail'
}
