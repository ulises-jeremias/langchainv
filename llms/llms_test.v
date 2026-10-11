module llms

import ulises_jeremias.langchainv.schema

fn test_validate_messages() {
	validate_messages([schema.text_message(.human, 'hello')]) or { panic(err) }
}

fn test_validate_messages_requires_at_least_one_message() {
	validate_messages([]) or {
		assert err.msg().contains('at least one message')
		return
	}
	assert false, 'expected empty messages to fail'
}

fn test_assistant_message_preserves_typed_parts() {
	response := Response{
		choices: [
			Choice{
				content:    'answer'
				tool_calls: [
					schema.ToolCall{
						id:            'call-1'
						call_type:     'function'
						function_call: schema.FunctionCall{
							name:      'lookup'
							arguments: '{}'
						}
					},
				]
			},
		]
	}
	message := response.assistant_message()
	assert message.role == .ai
	assert message.parts.len == 2
	assert message.text() == 'answer'
}

fn test_assistant_message_uses_parts_for_replay() {
	response := Response{
		choices: [
			Choice{
				parts: [schema.ContentPart(schema.TextPart{
					text: 'answer'
				})]
			},
			Choice{
				parts: [schema.ContentPart(schema.ThinkingPart{
					text:      'reasoning'
					signature: 'opaque'
				})]
			},
		]
	}
	message := response.assistant_message()
	assert message.parts.len == 2
	assert message.text() == 'answerreasoning'
}

fn test_call_options_validate_provider_independent_constraints() {
	valid := CallOptions{
		min_length: 2
		max_length: 5
		top_p:      0.8
		tools:      [
			schema.ToolDefinition{
				name: 'lookup'
			},
		]
	}
	valid.validate() or { panic(err) }

	invalid := CallOptions{
		min_length: 8
		max_length: 5
	}
	invalid.validate() or {
		assert err.msg().contains('minimum generation length')
		return
	}
	assert false, 'expected inconsistent lengths to fail'
}

fn test_call_options_reject_duplicate_tools() {
	options := CallOptions{
		tools: [
			schema.ToolDefinition{
				name: 'lookup'
			},
			schema.ToolDefinition{
				name: 'lookup'
			},
		]
	}
	options.validate() or {
		assert err.msg().contains('duplicate tool name')
		return
	}
	assert false, 'expected duplicate names to fail'
}
