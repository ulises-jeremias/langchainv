module openai

import json2
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

fn test_parse_chat_response_and_usage() {
	response := json2.decode[ChatCompletionResponse]('{"choices":[{"index":0,"message":{"content":"ok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}',
		json2.DecoderOptions{}) or { panic(err) }
	assert response.choices.len == 1
	assert response.choices[0].message.content == 'ok'
	assert response.usage.total_tokens == 5
}

fn json_value(object map[string]json2.Any, key string) json2.Any {
	return object[key] or { panic('missing JSON key `${key}`') }
}

fn json_value_string(value json2.Any) string {
	return value as string
}

fn json_value_int(value json2.Any) int {
	return value as int
}

fn json_value_array(value json2.Any) []json2.Any {
	return value as []json2.Any
}
