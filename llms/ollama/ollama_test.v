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
	requests         []httputil.Request
	response         httputil.Response
	version_response string
}

struct StreamCapture {
mut:
	value string
}

struct LegacyOptionBoundaryCase {
	version string
	key     string
	value   json2.Any
}

fn (client FakeHTTPClient) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	if request.url.ends_with('/api/version') && state.version_response != '' {
		return httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        state.version_response
		}
	}
	return state.response
}

fn (client FakeHTTPClient) do_stream(mut ctx context.Context, request httputil.Request, handler httputil.StreamHandler) !httputil.Response {
	mut state := client.state
	state.requests << request
	body := state.response.body.bytes()
	mut offset := 0
	for offset < body.len {
		end := if offset + 13 < body.len { offset + 13 } else { body.len }
		handler(mut ctx, body[offset..end])!
		offset = end
	}
	return state.response
}

fn new_fixture_client(body string, status int) (Client, &FakeHTTPState) {
	return new_fixture_client_with_version(body, status, '')
}

fn new_fixture_client_with_version(body string, status int, legacy_server_version string) (Client, &FakeHTTPState) {
	return new_fixture_client_with_server_version(body, status, legacy_server_version,
		legacy_server_version)
}

fn new_fixture_client_with_server_version(body string, status int, legacy_server_version string, actual_version string) (Client, &FakeHTTPState) {
	mut state := &FakeHTTPState{
		response:         httputil.Response{
			status_code: status
			headers:     http.Header{}
			body:        body
		}
		version_response: if actual_version != '' { '{"version":"${actual_version}"}' } else { '' }
	}
	client := new_client(FakeHTTPClient{
		state: state
	}, Options{
		base_url:              'http://ollama.test:11434'
		model:                 'gemma4'
		keep_alive:            '5m'
		legacy_server_version: legacy_server_version
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

fn test_complete_uses_generate_endpoint_and_maps_response() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"response":"completed","done":true,"done_reason":"stop","prompt_eval_count":7,"eval_count":3}', 200)
	completion := client.complete(mut ctx, 'write a sentence', llms.CallOptions{ max_tokens: 64 })!
	assert completion == 'completed'
	assert state.requests.len == 1
	assert state.requests[0].url == 'http://ollama.test:11434/api/generate'
	assert state.requests[0].body.contains('"prompt":"write a sentence"')
	assert state.requests[0].body.contains('"stream":false')
	assert state.requests[0].body.contains('"keep_alive":"5m"')
	assert state.requests[0].body.contains('"num_predict":64')
	assert !state.requests[0].body.contains('"messages"')
}

fn test_generate_completion_sends_typed_prompt_options_and_json_format() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"response":"{}","done":true}', 200)
	mut options := llms.CallOptions{ json_mode: true, max_tokens: 48 }
	options.provider_options['system'] = json2.Any('use concise answers')
	options.provider_options['suffix'] = json2.Any('END')
	options.provider_options['template'] = json2.Any('{{ .Prompt }}')
	options.provider_options['raw'] = json2.Any(true)
	client.complete(mut ctx, 'prompt', options) or { panic(err) }
	body := state.requests[0].body
	assert body.contains('"format":"json"')
	assert body.contains('"system":"use concise answers"')
	assert body.contains('"suffix":"END"')
	assert body.contains('"template":"{{ .Prompt }}"')
	assert body.contains('"raw":true')
	assert body.contains('"num_predict":48')
}

fn test_generate_completion_streams_ndjson_and_maps_usage() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"response":"hel","done":false}\n{"response":"lo","done":true,"done_reason":"stop","prompt_eval_count":7,"eval_count":3}\n', 200)
	mut streamed := &StreamCapture{}
	callback := llms.StreamFunc(fn [mut streamed] (mut _ctx context.Context, chunk []u8) ! {
		streamed.value += chunk.bytestr()
	})
	response := client.generate_completion(mut ctx, 'say hello', llms.CallOptions{ streaming_func: callback })!
	assert streamed.value == 'hello'
	assert response.choices[0].content == 'hello'
	assert response.choices[0].stop_reason == 'stop'
	assert response.usage.total_tokens == 10
	assert state.requests[0].url.ends_with('/api/generate')
	assert state.requests[0].body.contains('"stream":true')
}

fn test_generate_completion_rejects_incomplete_response() {
	mut ctx := context.background()
	client, _ := new_fixture_client('{"response":"partial","done":false}', 200)
	client.complete(mut ctx, 'prompt', llms.CallOptions{}) or {
		assert err.msg().contains('incomplete')
		return
	}
	assert false, 'expected incomplete response to fail'
}

fn test_generate_completion_rejects_tools_before_network() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"response":"unused","done":true}', 200)
	client.complete(mut ctx, 'prompt', llms.CallOptions{ tools: [schema.ToolDefinition{ name: 'tool' }] }) or {
		assert err.msg().contains('tool calls')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected unsupported completion tools to fail'
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

fn test_generate_content_sends_schema_valued_format() {
	mut state := &FakeHTTPState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"message":{"role":"assistant","content":"{\\"name\\":\\"Ada\\"}"}}'
		}
	}
	client := new_client(FakeHTTPClient{
		state: state
	}, Options{
		base_url:      'http://ollama.test:11434'
		model:         'gemma4'
		format_schema: '{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}'
	}) or { panic(err) }
	mut ctx := context.background()
	client.generate_content(mut ctx, [schema.text_message(.human, 'return a name')], llms.CallOptions{
		json_mode: true
	}) or { panic(err) }
	assert state.requests.len == 1
	assert state.requests[0].body.contains('"format":{')
	assert state.requests[0].body.contains('"type":"object"')
	assert state.requests[0].body.contains('"properties":{"name":{"type":"string"}}')
	assert state.requests[0].body.contains('"required":["name"]')
}

fn test_generate_content_sends_ollama_provider_options() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"message":{"content":"ok"}}', 200)
	mut options := llms.CallOptions{
		max_tokens:  96
		temperature: 0.2
		stop_words:  ['END']
	}
	options.provider_options['num_ctx'] = json2.Any(4096)
	options.provider_options['num_thread'] = json2.Any(4)
	options.provider_options['min_p'] = json2.Any(0.1)
	options.provider_options['think'] = json2.Any(false)
	options.provider_options['logprobs'] = json2.Any(true)
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], options) or {
		panic(err)
	}
	body := state.requests[0].body
	assert body.contains('"num_predict":96')
	assert body.contains('"temperature":0.2')
	assert body.contains('"stop":["END"]')
	assert body.contains('"num_ctx":4096')
	assert body.contains('"num_thread":4')
	assert body.contains('"min_p":0.1')
	assert body.contains('"think":false')
	assert body.contains('"logprobs":true')
	assert !body.contains('"options":{"think"')
}

fn test_generate_content_rejects_invalid_provider_options_before_network() {
	mut ctx := context.background()
	for provider_options in [
		{
			'unsupported': json2.Any(true)
		},
		{
			'num_ctx': json2.Any('large')
		},
		{
			'logprobs': json2.Any(1)
		},
	] {
		client, state := new_fixture_client('{}', 200)
		client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
			provider_options: provider_options
		}) or {
			assert err.msg().contains('provider_options')
			assert state.requests.len == 0
			continue
		}
		assert false, 'expected invalid provider options to be rejected'
	}
}

fn test_legacy_runner_options_require_and_verify_a_matching_server_version() {
	mut ctx := context.background()
	client, state := new_fixture_client('{"message":{"content":"ok"}}', 200)
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		provider_options: {
			'num_gqa': json2.Any(8)
		}
	}) or {
		assert err.msg().contains('legacy_server_version')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected legacy provider option without a version contract to fail'
}

fn test_legacy_runner_options_send_only_after_matching_old_server_version() {
	mut ctx := context.background()
	client, state := new_fixture_client_with_version('{"message":{"content":"ok"}}', 200,
		'0.1.34')
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		provider_options: {
			'num_gqa':          json2.Any(8)
			'numa':             json2.Any(true)
			'tfs_z':            json2.Any(1.0)
			'penalize_newline': json2.Any(false)
			'low_vram':         json2.Any(false)
			'f16_kv':           json2.Any(true)
			'logits_all':       json2.Any(false)
			'vocab_only':       json2.Any(false)
			'use_mlock':        json2.Any(false)
			'mirostat':         json2.Any(2)
			'mirostat_tau':     json2.Any(5.0)
			'mirostat_eta':     json2.Any(0.1)
		}
	}) or { panic(err) }
	assert state.requests.len == 2
	assert state.requests[0].url.ends_with('/api/version')
	assert state.requests[1].url.ends_with('/api/chat')
	assert state.requests[1].body.contains('"num_gqa":8')
	assert state.requests[1].body.contains('"numa":true')
	assert state.requests[1].body.contains('"tfs_z":1')
	assert state.requests[1].body.contains('"penalize_newline":false')
	assert state.requests[1].body.contains('"f16_kv":true')
	assert state.requests[1].body.contains('"mirostat":2')
	assert state.requests[1].body.contains('"mirostat_tau":5')
	assert state.requests[1].body.contains('"mirostat_eta":0.1')
}

fn test_legacy_runner_options_never_reach_a_newer_server() {
	mut ctx := context.background()
	client, state := new_fixture_client_with_server_version('{"message":{"content":"unused"}}',
		200, '0.6.8', '0.7.0')
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		provider_options: {
			'mirostat': json2.Any(1)
		}
	}) or {
		assert err.msg().contains('does not match server version')
		assert state.requests.len == 1
		return
	}
	assert false, 'expected mismatched server version to fail before generation'
}

fn test_legacy_sampling_options_reject_current_server_versions_before_network() {
	mut ctx := context.background()
	client, state := new_fixture_client_with_version('{}', 200, '0.7.0')
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		provider_options: {
			'mirostat': json2.Any(1)
		}
	}) or {
		assert err.msg().contains('not supported by server version')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected unsupported legacy option to fail before network'
}

fn test_legacy_options_validate_values_before_version_lookup() {
	mut ctx := context.background()
	for provider_options in [
		{
			'num_gqa': json2.Any(0)
		},
		{
			'mirostat': json2.Any(3)
		},
	] {
		client, state := new_fixture_client_with_version('{}', 200, '0.1.34')
		client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
			provider_options: provider_options
		}) or {
			assert err.msg().contains('provider_options')
			assert state.requests.len == 0
			continue
		}
		assert false, 'expected invalid legacy provider option to fail before network'
	}
}

fn test_legacy_option_version_boundaries_reject_removed_fields_before_network() {
	mut ctx := context.background()
	for test_case in [
		LegacyOptionBoundaryCase{
			version: '0.1.33'
			key:     'num_gqa'
			value:   json2.Any(8)
		},
		LegacyOptionBoundaryCase{
			version: '0.1.39'
			key:     'num_gqa'
			value:   json2.Any(8)
		},
		LegacyOptionBoundaryCase{
			version: '0.4.0'
			key:     'numa'
			value:   json2.Any(true)
		},
		LegacyOptionBoundaryCase{
			version: '0.5.12'
			key:     'tfs_z'
			value:   json2.Any(1.0)
		},
		LegacyOptionBoundaryCase{
			version: '0.5.12'
			key:     'penalize_newline'
			value:   json2.Any(false)
		},
		LegacyOptionBoundaryCase{
			version: '0.7.0'
			key:     'low_vram'
			value:   json2.Any(false)
		},
		LegacyOptionBoundaryCase{
			version: '0.7.0'
			key:     'mirostat'
			value:   json2.Any(1)
		},
	] {
		client, state := new_fixture_client_with_version('{}', 200, test_case.version)
		mut provider_options := map[string]json2.Any{}
		provider_options[test_case.key] = test_case.value
		client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
			provider_options: provider_options
		}) or {
			assert err.msg().contains('Ollama')
			assert state.requests.len == 0
			continue
		}
		assert false, 'expected ${test_case.key} to be rejected for ${test_case.version}'
	}
}

fn test_legacy_sampling_options_work_with_completion_after_version_check() {
	mut ctx := context.background()
	client, state := new_fixture_client_with_version('{"response":"legacy","done":true}', 200,
		'0.6.8')
	mut options := llms.CallOptions{}
	options.provider_options['mirostat'] = json2.Any(2)
	assert client.complete(mut ctx, 'prompt', options)! == 'legacy'
	assert state.requests.len == 2
	assert state.requests[0].url.ends_with('/api/version')
	assert state.requests[1].url.ends_with('/api/generate')
	assert state.requests[1].body.contains('"mirostat":2')
}

fn test_generate_content_streams_ndjson_content_and_usage() {
	mut ctx := context.background()
	body := '{"message":{"content":"hel"},"done":false}\n{"message":{"content":"lo"},"done":false}\n{"message":{},"done":true,"done_reason":"stop","prompt_eval_count":2,"eval_count":2}\n'
	client, state := new_fixture_client(body, 200)
	mut streamed := &StreamCapture{}
	stream := llms.StreamFunc(fn [mut streamed] (mut _ context.Context, chunk []u8) ! {
		streamed.value += chunk.bytestr()
	})
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		streaming_func:   stream
		provider_options: {
			'num_ctx': json2.Any(2048)
			'think':   json2.Any(true)
		}
	}) or { panic(err) }
	assert streamed.value == 'hello'
	assert response.choices[0].content == 'hello'
	assert response.choices[0].stop_reason == 'stop'
	assert response.usage.total_tokens == 4
	assert state.requests[0].body.contains('"stream":true')
	assert state.requests[0].body.contains('"num_ctx":2048')
	assert state.requests[0].body.contains('"think":true')
	assert (state.requests[0].headers['Accept'] or { '' }) == 'application/x-ndjson'
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

fn test_client_rejects_empty_model() {
	new_client(FakeHTTPClient{
		state: &FakeHTTPState{}
	}, Options{}) or {
		assert err.msg().contains('model must not be empty')
		return
	}
	assert false, 'expected an empty model to fail'
}

fn test_client_rejects_unsupported_format() {
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
}

fn test_client_rejects_non_object_format_schema() {
	new_client(FakeHTTPClient{
		state: &FakeHTTPState{}
	}, Options{
		model:         'gemma4'
		format_schema: '[]'
	}) or {
		assert err.msg().contains('valid JSON object')
		return
	}
	assert false, 'expected a non-object format schema to fail'
}

fn test_client_rejects_empty_format_schema() {
	new_client(FakeHTTPClient{
		state: &FakeHTTPState{}
	}, Options{
		model:         'gemma4'
		format_schema: '{}'
	}) or {
		assert err.msg().contains('must not be an empty JSON object')
		return
	}
	assert false, 'expected an empty format schema to fail'
}

fn test_client_rejects_conflicting_formats() {
	new_client(FakeHTTPClient{
		state: &FakeHTTPState{}
	}, Options{
		model:         'gemma4'
		format:        'json'
		format_schema: '{"type":"object"}'
	}) or {
		assert err.msg().contains('cannot both be configured')
		return
	}
	assert false, 'expected conflicting output formats to fail'
}

fn test_client_rejects_base_url_userinfo() {
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
