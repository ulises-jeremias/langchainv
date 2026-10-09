module openai

import json2
import context
import encoding.base64
import net.http
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

fn test_chat_payload_maps_text_roles_and_generation_options() {
	client := Config{
		api_key: 'unit-test-key'
		model:   'gpt-test'
	}
	options := llms.CallOptions{
		max_tokens:        80
		temperature:       0.4
		frequency_penalty: 0.2
		stop_words:        ['END']
		json_mode:         true
	}
	payload := chat_payload(client, [schema.text_message(.system, 'rules'), schema.text_message(.human,
		'hello')], options) or { panic(err) }
	encoded := json2.encode(payload, json2.EncoderOptions{})
	decoded := json2.decode[json2.Any](encoded, json2.DecoderOptions{}) or { panic(err) }
	object := decoded as map[string]json2.Any
	assert json_value_string(json_value(object, 'model')) == 'gpt-test'
	assert json_value_int(json_value(object, 'max_completion_tokens')) == 80
	assert json_value(object, 'response_format') is map[string]json2.Any
	messages := json_value_array(json_value(object, 'messages'))
	assert messages.len == 2
	assert json_value_string(json_value(messages[0] as map[string]json2.Any, 'role')) == 'system'
	assert json_value_string(json_value(messages[1] as map[string]json2.Any, 'content')) == 'hello'
}

fn test_azure_foundry_api_key_auth_uses_api_key_header() {
	client := new(Config{
		api_key:           'unit-test-key'
		base_url:          'https://example.test/openai/v1/'
		azure_api_key_auth: true
	}) or { panic(err) }
	header := client.request_header() or { panic(err) }
	assert header.get_custom('api-key', http.HeaderQueryConfig{}) or { '' } == 'unit-test-key'
	assert header.get(.authorization) == none
	assert client.config.base_url == 'https://example.test/openai/v1'
}

fn test_azure_foundry_api_key_auth_requires_v1_base_url() {
	new(Config{
		api_key:            'unit-test-key'
		azure_api_key_auth: true
	}) or {
		assert err.msg().contains('base URL ending in `/openai/v1`')
		return
	}
	assert false, 'expected Azure AI Foundry auth to require an explicit v1 base URL'
}

fn test_azure_foundry_api_key_auth_requires_https() {
	new(Config{
		api_key:            'unit-test-key'
		base_url:           'http://example.test/openai/v1'
		azure_api_key_auth: true
	}) or {
		assert err.msg().contains('HTTPS base URL')
		return
	}
	assert false, 'expected Azure AI Foundry auth to require HTTPS'
}

fn test_azure_foundry_api_key_auth_rejects_query_and_fragment() {
	for base_url in ['https://example.test/openai/v1?x=1', 'https://example.test/openai/v1#fragment'] {
		new(Config{
			api_key:            'unit-test-key'
			base_url:           base_url
			azure_api_key_auth: true
		}) or {
			assert err.msg().contains('HTTPS base URL')
			continue
		}
		assert false, 'expected Azure AI Foundry auth to reject query and fragment components'
	}
}

fn test_azure_foundry_api_key_auth_rejects_openai_organization() {
	new(Config{
		api_key:            'unit-test-key'
		base_url:           'https://example.test/openai/v1'
		organization:       'org-test'
		azure_api_key_auth: true
	}) or {
		assert err.msg().contains('organization headers are not supported')
		return
	}
	assert false, 'expected Azure AI Foundry auth to reject the OpenAI organization header'
}

fn test_chat_payload_rejects_unsupported_content_parts() {
	client := Config{
		api_key: 'unit-test-key'
	}
	message := schema.Message{
		role:  .human
		parts: [schema.ContentPart(schema.ThinkingPart{
			text: 'private reasoning'
		})]
	}
	chat_payload(client, [message], llms.CallOptions{}) or {
		assert err.msg().contains('does not support this message content part')
		return
	}
	assert false
}

fn test_chat_payload_encodes_mixed_text_and_image_parts() {
	client := Config{
		api_key: 'unit-test-key'
		model:   'gpt-4o'
	}
	message := schema.Message{
		role:  .human
		parts: [
			schema.ContentPart(schema.TextPart{
				text: 'Describe this'
			}),
			schema.ContentPart(schema.ImageURLPart{
				url:    'https://example.test/image.png'
				detail: 'high'
			}),
			schema.ContentPart(schema.TextPart{
				text: ' in one sentence'
			}),
		]
	}
	payload := chat_payload(client, [message], llms.CallOptions{}) or { panic(err) }
	decoded := json2.decode[json2.Any](json2.encode(payload, json2.EncoderOptions{}),
		json2.DecoderOptions{}) or { panic(err) }
	assert decoded is map[string]json2.Any, 'chat payload must encode as an object'
	object := decoded as map[string]json2.Any
	messages := json_value_array(json_value(object, 'messages'))
	assert messages[0] is map[string]json2.Any, 'message must encode as an object'
	parts := json_value_array(json_value(messages[0] as map[string]json2.Any, 'content'))
	assert parts.len == 3
	assert parts[0] is map[string]json2.Any, 'text content part must encode as an object'
	assert json_value_string(json_value(parts[0] as map[string]json2.Any, 'text')) == 'Describe this'
	assert parts[1] is map[string]json2.Any, 'image content part must encode as an object'
	image_part := parts[1] as map[string]json2.Any
	assert json_value_string(json_value(image_part, 'type')) == 'image_url'
	image_url_value := json_value(image_part, 'image_url')
	assert image_url_value is map[string]json2.Any, 'image_url must encode as an object'
	image_url := image_url_value as map[string]json2.Any
	assert json_value_string(json_value(image_url, 'url')) == 'https://example.test/image.png'
	assert json_value_string(json_value(image_url, 'detail')) == 'high'
	assert parts[2] is map[string]json2.Any, 'trailing text content part must encode as an object'
	assert json_value_string(json_value(parts[2] as map[string]json2.Any, 'text')) == ' in one sentence'
}

fn test_chat_payload_encodes_mixed_text_and_audio_parts() {
	message := schema.Message{
		role:  .human
		parts: [
			schema.ContentPart(schema.TextPart{
				text: 'Transcribe this:'
			}),
			schema.ContentPart(schema.BinaryPart{
				mime_type: 'audio/wav'
				data:      'audio'.bytes()
			}),
			schema.ContentPart(schema.BinaryPart{
				mime_type: 'audio/mpeg'
				data:      'audio'.bytes()
			}),
		]
	}
	payload := chat_payload(Config{
		api_key: 'unit-test-key'
	}, [message], llms.CallOptions{}) or { panic(err) }
	decoded := json2.decode[json2.Any](json2.encode(payload, json2.EncoderOptions{}),
		json2.DecoderOptions{}) or { panic(err) }
	object := decoded as map[string]json2.Any
	messages := json_value_array(json_value(object, 'messages'))
	parts := json_value_array(json_value(messages[0] as map[string]json2.Any, 'content'))
	assert parts.len == 3
	assert json_value_string(json_value(parts[0] as map[string]json2.Any, 'text')) == 'Transcribe this:'
	audio_part := parts[1] as map[string]json2.Any
	assert json_value_string(json_value(audio_part, 'type')) == 'input_audio'
	input_audio := json_value(audio_part, 'input_audio') as map[string]json2.Any
	assert json_value_string(json_value(input_audio, 'data')) == base64.encode('audio'.bytes())
	assert json_value_string(json_value(input_audio, 'format')) == 'wav'
	mp3_part := parts[2] as map[string]json2.Any
	mp3_audio := json_value(mp3_part, 'input_audio') as map[string]json2.Any
	assert json_value_string(json_value(mp3_audio, 'format')) == 'mp3'
}

fn test_chat_payload_rejects_unsupported_audio_input() {
	invalid_audio := schema.Message{
		role:  .human
		parts: [schema.ContentPart(schema.BinaryPart{
			mime_type: 'application/octet-stream'
			data:      [u8(1)]
		})]
	}
	chat_payload(Config{
		api_key: 'unit-test-key'
	}, [invalid_audio], llms.CallOptions{}) or {
		assert err.msg().contains('must use WAV or MP3 format')
		return
	}
	assert false, 'expected an unsupported audio format to fail'
}

fn test_chat_payload_rejects_empty_audio_input() {
	empty_audio := schema.Message{
		role:  .human
		parts: [schema.ContentPart(schema.BinaryPart{
			mime_type: 'audio/wav'
		})]
	}
	chat_payload(Config{
		api_key: 'unit-test-key'
	}, [empty_audio], llms.CallOptions{}) or {
		assert err.msg().contains('audio input cannot be empty')
		return
	}
	assert false, 'expected empty audio input to fail'
}

fn test_chat_payload_rejects_invalid_image_detail() {
	client := Config{
		api_key: 'unit-test-key'
	}
	invalid_detail := schema.Message{
		role:  .human
		parts: [schema.ContentPart(schema.ImageURLPart{
			url:    'https://example.test/image.png'
			detail: 'medium'
		})]
	}
	chat_payload(client, [invalid_detail], llms.CallOptions{}) or {
		assert err.msg().contains('detail must be auto, low, or high')
		return
	}
	assert false, 'expected invalid image detail to fail'
}

fn test_chat_payload_rejects_image_in_assistant_message() {
	client := Config{
		api_key: 'unit-test-key'
	}
	assistant_image := schema.Message{
		role:  .ai
		parts: [schema.ContentPart(schema.ImageURLPart{
			url: 'https://example.test/image.png'
		})]
	}
	chat_payload(client, [assistant_image], llms.CallOptions{}) or {
		assert err.msg().contains('only supported in user messages')
		return
	}
	assert false, 'expected assistant image input to fail'
}

fn test_chat_payload_maps_tool_definitions_and_named_choice() {
	parameters := json2.decode[json2.Any]('{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}',
		json2.DecoderOptions{}) or { panic(err) }
	payload := chat_payload(Config{
		api_key: 'unit-test-key'
	}, [schema.text_message(.human, 'Weather in Paris?')], llms.CallOptions{
		tools:       [schema.ToolDefinition{
			name:        'lookup_weather'
			description: 'Look up current weather'
			parameters:  ?json2.Any(parameters)
			strict:      true
		}]
		tool_choice: schema.ToolChoice{
			mode: 'function'
			name: 'lookup_weather'
		}
	}) or { panic(err) }
	decoded := json2.decode[json2.Any](json2.encode(payload, json2.EncoderOptions{}),
		json2.DecoderOptions{}) or { panic(err) }
	object := decoded as map[string]json2.Any
	tools := json_value_array(json_value(object, 'tools'))
	assert tools.len == 1
	tool := tools[0] as map[string]json2.Any
	assert json_value_string(json_value(tool, 'type')) == 'function'
	function := json_value(tool, 'function') as map[string]json2.Any
	assert json_value_string(json_value(function, 'name')) == 'lookup_weather'
	assert json_value_string(json_value(function, 'description')) == 'Look up current weather'
	assert json_value(function, 'strict') == json2.Any(true)
	assert json_value(function, 'parameters') is map[string]json2.Any
	choice := json_value(object, 'tool_choice') as map[string]json2.Any
	assert json_value_string(json_value(choice, 'type')) == 'function'
	choice_function := json_value(choice, 'function') as map[string]json2.Any
	assert json_value_string(json_value(choice_function, 'name')) == 'lookup_weather'
}

fn test_chat_payload_replays_assistant_tool_calls_and_results() {
	assistant := schema.Message{
		role:  .ai
		parts: [
			schema.ContentPart(schema.TextPart{
				text: 'Checking the weather.'
			}),
			schema.ContentPart(schema.ToolCall{
				id:            'call_weather'
				call_type:     'function'
				function_call: schema.FunctionCall{
					name:      'lookup_weather'
					arguments: '{"city":"Paris"}'
				}
			}),
		]
	}
	tool_result := schema.Message{
		role:  .tool
		parts: [schema.ContentPart(schema.ToolResult{
			call_id: 'call_weather'
			name:    'lookup_weather'
			content: 'Sunny'
		})]
	}
	payload := chat_payload(Config{
		api_key: 'unit-test-key'
	}, [assistant, tool_result], llms.CallOptions{}) or { panic(err) }
	decoded := json2.decode[json2.Any](json2.encode(payload, json2.EncoderOptions{}),
		json2.DecoderOptions{}) or { panic(err) }
	object := decoded as map[string]json2.Any
	messages := json_value_array(json_value(object, 'messages'))
	assert messages.len == 2
	assistant_message := messages[0] as map[string]json2.Any
	assert json_value_string(json_value(assistant_message, 'role')) == 'assistant'
	assert json_value_string(json_value(assistant_message, 'content')) == 'Checking the weather.'
	calls := json_value_array(json_value(assistant_message, 'tool_calls'))
	assert calls.len == 1
	call := calls[0] as map[string]json2.Any
	assert json_value_string(json_value(call, 'id')) == 'call_weather'
	assert json_value_string(json_value(call, 'type')) == 'function'
	function := json_value(call, 'function') as map[string]json2.Any
	assert json_value_string(json_value(function, 'name')) == 'lookup_weather'
	assert json_value_string(json_value(function, 'arguments')) == '{"city":"Paris"}'
	result := messages[1] as map[string]json2.Any
	assert json_value_string(json_value(result, 'role')) == 'tool'
	assert json_value_string(json_value(result, 'tool_call_id')) == 'call_weather'
	assert json_value_string(json_value(result, 'content')) == 'Sunny'
	assert json_value_string(json_value(result, 'name')) == 'lookup_weather'
}

fn test_chat_payload_rejects_non_function_tool_calls_and_non_object_parameters() {
	client := Config{
		api_key: 'unit-test-key'
	}
	invalid_call := schema.Message{
		role:  .ai
		parts: [schema.ContentPart(schema.ToolCall{
			id:            'call_custom'
			call_type:     'custom'
			function_call: schema.FunctionCall{
				name:      'lookup'
				arguments: '{}'
			}
		})]
	}
	chat_payload(client, [invalid_call], llms.CallOptions{}) or {
		assert err.msg().contains('only supports function tool calls')
		return
	}
	assert false, 'expected an unsupported tool call type to fail'
	invalid_parameters := schema.ToolDefinition{
		name:       'lookup'
		parameters: ?json2.Any(json2.Any([json2.Any('invalid')]))
	}
	chat_payload(client, [schema.text_message(.human, 'hello')], llms.CallOptions{
		tools: [invalid_parameters]
	}) or {
		assert err.msg().contains('parameters must be a JSON object')
		return
	}
	assert false, 'expected non-object tool parameters to fail'
}

fn test_chat_payload_allows_tools_without_parameters() {
	payload := chat_payload(Config{
		api_key: 'unit-test-key'
	}, [schema.text_message(.human, 'hello')], llms.CallOptions{
		tools: [schema.ToolDefinition{
			name: 'ping'
		}]
	}) or { panic(err) }
	object := payload as map[string]json2.Any
	tool := json_value_array(json_value(object, 'tools'))[0] as map[string]json2.Any
	function := json_value(tool, 'function') as map[string]json2.Any
	assert 'parameters' !in function
}

fn test_reasoning_model_keeps_image_after_system_prefix() {
	client := Config{
		api_key: 'unit-test-key'
		model:   'o1-mini'
	}
	image_message := schema.Message{
		role:  .human
		parts: [schema.ContentPart(schema.ImageURLPart{
			url: 'https://example.test/image.png'
		})]
	}
	payload := chat_payload(client, [
		schema.text_message(.system, 'inspect carefully'),
		image_message,
	],
		llms.CallOptions{}) or { panic(err) }
	decoded := json2.decode[json2.Any](json2.encode(payload, json2.EncoderOptions{}),
		json2.DecoderOptions{}) or { panic(err) }
	assert decoded is map[string]json2.Any, 'reasoning chat payload must encode as an object'
	object := decoded as map[string]json2.Any
	messages := json_value_array(json_value(object, 'messages'))
	assert messages[0] is map[string]json2.Any, 'reasoning message must encode as an object'
	parts := json_value_array(json_value(messages[0] as map[string]json2.Any, 'content'))
	assert parts.len == 2
	assert parts[0] is map[string]json2.Any, 'reasoning prefix must encode as an object'
	assert json_value_string(json_value(parts[0] as map[string]json2.Any, 'text')) == 'inspect carefully\n\n'
	assert parts[1] is map[string]json2.Any, 'reasoning image must encode as an object'
	assert json_value_string(json_value(parts[1] as map[string]json2.Any, 'type')) == 'image_url'
}

fn test_reasoning_model_payload_merges_system_prompt_and_omits_temperature() {
	client := Config{
		api_key: 'unit-test-key'
		model:   'o1-mini'
	}
	payload := chat_payload(client, [schema.text_message(.system, 'think carefully'),
		schema.text_message(.human, 'solve')], llms.CallOptions{
		temperature: 0.8
	}) or {
		panic(err)
	}
	encoded := json2.encode(payload, json2.EncoderOptions{})
	decoded := json2.decode[json2.Any](encoded, json2.DecoderOptions{}) or { panic(err) }
	object := decoded as map[string]json2.Any
	assert 'temperature' !in object
	messages := json_value_array(json_value(object, 'messages'))
	assert messages.len == 1
	assert json_value_string(json_value(messages[0] as map[string]json2.Any, 'role')) == 'user'
	content := json_value_string(json_value(messages[0] as map[string]json2.Any, 'content'))
	assert content == 'think carefully\n\nsolve', 'unexpected reasoning prompt content: ${content}'
}

fn test_chat_payload_rejects_unimplemented_requested_options() {
	client := Config{
		api_key: 'unit-test-key'
	}
	chat_payload(client, [schema.text_message(.human, 'hello')], llms.CallOptions{
		top_k: 1
	}) or {
		assert err.msg().contains('requested generation option is not supported')
		return
	}
	assert false
}

fn test_chat_payload_rejects_tool_streaming_and_choice_without_tools() {
	client := Config{
		api_key: 'unit-test-key'
	}
	streaming_tools := llms.CallOptions{
		tools:          [schema.ToolDefinition{
			name: 'lookup'
		}]
		streaming_func: discard_stream_chunk
	}
	chat_payload(client, [schema.text_message(.human, 'hello')], streaming_tools) or {
		assert err.msg().contains('streaming tool calls are not implemented')
		return
	}
	assert false, 'expected streamed tool calls to fail'
	chat_payload(client, [schema.text_message(.human, 'hello')], llms.CallOptions{
		tool_choice: schema.ToolChoice{
			mode: 'auto'
		}
	}) or {
		assert err.msg().contains('requires at least one tool definition')
		return
	}
	chat_payload(client, [schema.text_message(.human, 'hello')], llms.CallOptions{
		tools:       [schema.ToolDefinition{
			name: 'ping'
		}]
		tool_choice: schema.ToolChoice{
			mode: 'function'
			name: 'missing'
		}
	}) or {
		assert err.msg().contains('must match a provided tool definition')
		return
	}
	assert false, 'expected invalid tool choice configuration to fail'
}

fn test_process_stream_event_emits_content_and_records_finish_reason() {
	mut ctx := context.background()
	mut state := StreamState{
		ctx:      ctx
		callback: discard_stream_chunk
	}
	process_stream_event(mut state, 'data: {"choices":[{"index":0,"delta":{"content":"hel"}}]}') or {
		panic(err)
	}
	process_stream_event(mut state, 'data: {"choices":[{"index":0,"delta":{"content":"lo"},"finish_reason":"stop"}]}') or {
		panic(err)
	}
	process_stream_event(mut state, 'data: [DONE]') or { panic(err) }
	assert state.content == 'hello'
	assert state.finish_reason == 'stop'
	assert state.done
}

fn test_sse_event_data_joins_data_lines_and_ignores_comments() {
	data := sse_event_data(': keepalive\ndata: first\ndata: second') or {
		panic('missing SSE data lines')
	}
	assert data == 'first\nsecond'
	assert sse_event_data(': keepalive') == none
}

fn discard_stream_chunk(mut ctx context.Context, chunk []u8) ! {
	_ = ctx
	_ = chunk
}

fn test_parse_chat_response_and_usage() {
	response := json2.decode[ChatCompletionResponse]('{"choices":[{"index":0,"message":{"content":"ok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}',
		json2.DecoderOptions{}) or { panic(err) }
	assert response.choices.len == 1
	assert response.choices[0].message.content or { '' } == 'ok'
	assert response.usage.total_tokens == 5
}

fn test_parse_tool_call_response_and_build_replayable_message() {
	decoded := json2.decode[ChatCompletionResponse]('{"choices":[{"index":0,"message":{"content":null,"tool_calls":[{"id":"call_weather","type":"function","function":{"name":"lookup_weather","arguments":"{\\"city\\":\\"Paris\\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":8,"completion_tokens":4,"total_tokens":12}}',
		json2.DecoderOptions{}) or { panic(err) }
	response := response_from_chat_completion(decoded) or { panic(err) }
	assert response.choices.len == 1
	assert response.choices[0].content == ''
	assert response.choices[0].stop_reason == 'tool_calls'
	assert response.choices[0].tool_calls.len == 1
	call := response.choices[0].tool_calls[0]
	assert call.id == 'call_weather'
	assert call.call_type == 'function'
	assert call.function_call.name == 'lookup_weather'
	assert call.function_call.arguments == '{"city":"Paris"}'
	assert response.usage.total_tokens == 12
	message := response.assistant_message()
	assert message.role == .ai
	assert message.parts.len == 1
	assert message.parts[0] is schema.ToolCall
}

fn test_embedding_payload_maps_model_inputs_and_dimensions() {
	encoded := json2.encode(embedding_payload(Config{
		embedding_model:      'text-embedding-3-small'
		embedding_dimensions: 256
	}, ['first', 'second']), json2.EncoderOptions{})
	decoded := json2.decode[json2.Any](encoded, json2.DecoderOptions{}) or { panic(err) }
	object := decoded as map[string]json2.Any
	assert json_value_string(json_value(object, 'model')) == 'text-embedding-3-small'
	assert json_value_int(json_value(object, 'dimensions')) == 256
	inputs := json_value_array(json_value(object, 'input'))
	assert inputs.len == 2
	assert json_value_string(inputs[0]) == 'first'
	assert json_value_string(inputs[1]) == 'second'
}

fn test_parse_embeddings_in_response_order() {
	response := json2.decode[EmbeddingResponse]('{"data":[{"embedding":[0.1,0.2],"index":0},{"embedding":[0.3,0.4],"index":1}]}',
		json2.DecoderOptions{}) or { panic(err) }
	assert response.data.len == 2
	assert response.data[0].embedding == [f32(0.1), f32(0.2)]
	assert response.data[1].embedding == [f32(0.3), f32(0.4)]
	embeddings := embeddings_from_response(response, 2) or { panic(err) }
	assert embeddings.len == 2
	assert embeddings[1] == [f32(0.3), f32(0.4)]
}

fn test_reject_partial_embedding_response() {
	response := EmbeddingResponse{
		data: [EmbeddingDatum{
			embedding: [f32(0.1)]
		}]
	}
	embeddings_from_response(response, 2) or {
		assert err.msg() == 'OpenAI returned 1 embeddings for 2 inputs'
		return
	}
	assert false
}

fn json_value(object map[string]json2.Any, key string) json2.Any {
	return object[key] or { panic('missing JSON key `${key}`') }
}

fn json_value_string(value json2.Any) string {
	return value as string
}

fn json_value_int(value json2.Any) int {
	return int(value as f64)
}

fn json_value_array(value json2.Any) []json2.Any {
	return value as []json2.Any
}
