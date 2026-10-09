module memory

import context
import json2
import ulises_jeremias.langchainv.schema

fn test_in_memory_history_snapshots_binary_content() {
	mut ctx := context.background()
	mut history := new_in_memory_chat_message_history()
	mut message := schema.Message{
		role: .human
		parts: [
			schema.ContentPart(schema.BinaryPart{
				mime_type: 'image/png'
				data:      [u8(1), 2]
			}),
		]
	}
	history.add_message(mut ctx, message) or { panic(err) }
	message.parts[0] = schema.ContentPart(schema.BinaryPart{
		mime_type: 'image/png'
		data:      [u8(9), 9]
	})
	result := history.get_messages(mut ctx) or { panic(err) }
	assert result.len == 1
	match result[0].parts[0] {
		schema.BinaryPart {
			assert part.data == [u8(1), 2]
		}
		else {
			assert false, 'expected binary content'
		}
	}
}

fn test_conversation_buffer_load_save_and_clear() {
	mut ctx := context.background()
	mut memory := new_conversation_buffer('history', 'question', 'answer') or { panic(err) }
	mut inputs := map[string]json2.Any{}
	inputs['question'] = json2.Any('What is V?')
	mut outputs := map[string]json2.Any{}
	outputs['answer'] = json2.Any('A programming language.')
	memory.save_context(mut ctx, inputs, outputs) or { panic(err) }
	loaded := memory.load_memory_variables(mut ctx, inputs) or { panic(err) }
	assert loaded['history'].str() == 'Human: What is V?\nAI: A programming language.'
	assert memory.memory_keys() == ['history']
	memory.clear(mut ctx) or { panic(err) }
	cleared := memory.load_memory_variables(mut ctx, inputs) or { panic(err) }
	assert cleared['history'].str() == ''
}
