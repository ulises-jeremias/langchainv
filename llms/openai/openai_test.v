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
	assert object['model'] as string == 'gpt-test'
	assert object['max_completion_tokens'] as int == 80
	assert object['response_format'] is map[string]json2.Any
	messages := object['messages'] as []json2.Any
	assert messages.len == 2
	assert (messages[0] as map[string]json2.Any)['role'] as string == 'system'
	assert (messages[1] as map[string]json2.Any)['content'] as string == 'hello'
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
	messages := object['messages'] as []json2.Any
	assert messages.len == 1
	assert (messages[0] as map[string]json2.Any)['role'] as string == 'user'
	assert (messages[0] as map[string]json2.Any)['content'] as string == 'think carefully\n\nsolve'
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
