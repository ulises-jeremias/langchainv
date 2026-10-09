module openai

import json2
import context
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

fn test_chat_payload_rejects_unsupported_multimodal_parts() {
	client := Config{
		api_key: 'unit-test-key'
	}
	message := schema.Message{
		role:  .human
		parts: [schema.ContentPart(schema.ImageURLPart{
			url: 'https://example.test/image.png'
		})]
	}
	chat_payload(client, [message], llms.CallOptions{}) or {
		assert err.msg().contains('does not support non-text')
		return
	}
	assert false
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
	assert json_value_string(json_value(messages[0] as map[string]json2.Any, 'content')) == 'think carefully\n\nsolve'
}

fn test_chat_payload_rejects_unimplemented_requested_options() {
	client := Config{
		api_key: 'unit-test-key'
	}
	chat_payload(client, [schema.text_message(.human, 'hello')], llms.CallOptions{
		tools: [schema.ToolDefinition{
			name: 'lookup'
		}]
	}) or {
		assert err.msg().contains('tool calling is not implemented')
		return
	}
	assert false
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
	assert response.choices[0].message.content == 'ok'
	assert response.usage.total_tokens == 5
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
