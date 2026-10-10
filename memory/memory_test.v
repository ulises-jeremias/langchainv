module memory

import context
import json2
import ulises_jeremias.langchainv.schema

struct CharacterTokenCounter {}

fn (_counter CharacterTokenCounter) count_tokens(mut _ctx context.Context, messages []schema.Message, _model string) !int {
	mut count := 0
	for message in messages {
		count += message.text().len
	}
	return count
}

struct FailingTokenCounterState {
mut:
	calls int
}

struct FailingTokenCounter {
	state &FailingTokenCounterState
}

fn (counter FailingTokenCounter) count_tokens(mut _ctx context.Context, messages []schema.Message, _model string) !int {
	mut state := counter.state
	state.calls++
	if state.calls > 1 {
		return error('count unavailable')
	}
	mut count := 0
	for message in messages {
		count += message.text().len
	}
	return count
}

fn test_in_memory_history_snapshots_binary_content() {
	mut ctx := context.background()
	mut history := new_in_memory_chat_message_history()
	mut message := schema.Message{
		role:  .human
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
	part := result[0].parts[0]
	match part {
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
	mut buffer := new_conversation_buffer('history', 'question', 'answer') or { panic(err) }
	mut inputs := map[string]json2.Any{}
	inputs['question'] = json2.Any('What is V?')
	mut outputs := map[string]json2.Any{}
	outputs['answer'] = json2.Any('A programming language.')
	buffer.save_context(mut ctx, inputs, outputs) or { panic(err) }
	loaded := buffer.load_memory_variables(mut ctx, inputs) or { panic(err) }
	loaded_history := loaded['history'] or { panic('missing history') }
	assert loaded_history.str() == 'Human: What is V?\nAI: A programming language.'
	assert buffer.memory_keys() == ['history']
	buffer.clear(mut ctx) or { panic(err) }
	cleared := buffer.load_memory_variables(mut ctx, inputs) or { panic(err) }
	cleared_history := cleared['history'] or { panic('missing cleared history') }
	assert cleared_history.str() == ''
}

fn test_conversation_window_buffer_keeps_only_recent_turns() {
	mut ctx := context.background()
	mut window := new_conversation_window_buffer(2, 'history', 'question', 'answer') or {
		panic(err)
	}
	for index in 1 .. 4 {
		mut inputs := map[string]json2.Any{}
		inputs['question'] = json2.Any('question ${index}')
		mut outputs := map[string]json2.Any{}
		outputs['answer'] = json2.Any('answer ${index}')
		window.save_context(mut ctx, inputs, outputs) or { panic(err) }
	}
	loaded := window.load_memory_variables(mut ctx, map[string]json2.Any{}) or { panic(err) }
	history := loaded['history'] or { panic('missing history') }
	assert history.str() == 'Human: question 2\nAI: answer 2\nHuman: question 3\nAI: answer 3'
	assert window.window_size == 2
	assert window.memory_keys() == ['history']
	mut memory_contract := schema.Memory(window)
	assert memory_contract.memory_keys() == ['history']
	window.clear(mut ctx) or { panic(err) }
	cleared := window.load_memory_variables(mut ctx, map[string]json2.Any{}) or { panic(err) }
	assert (cleared['history'] or { panic('missing cleared history') }).str() == ''
}

fn test_conversation_window_buffer_defaults_and_limits_window_size() {
	default_window := new_conversation_window_buffer(0, 'history', 'question', 'answer') or {
		panic(err)
	}
	assert default_window.window_size == 5
	new_conversation_window_buffer(10001, 'history', 'question', 'answer') or {
		assert err.msg().contains('at most 10000')
		return
	}
	assert false, 'expected oversized window to fail'
}

fn test_simple_memory_implements_no_op_memory_contract() {
	mut ctx := context.background()
	mut memory_contract := schema.Memory(new_simple_memory())
	assert memory_contract.memory_keys().len == 0
	loaded := memory_contract.load_memory_variables(mut ctx, map[string]json2.Any{}) or { panic(err) }
	assert loaded.len == 0
	memory_contract.save_context(mut ctx, map[string]json2.Any{}, map[string]json2.Any{}) or {
		panic(err)
	}
	memory_contract.clear(mut ctx) or { panic(err) }
}

fn test_token_buffer_memory_evicts_oldest_complete_turns() {
	mut ctx := context.background()
	token_memory := new_token_buffer_memory(CharacterTokenCounter{}, 'fake', 12, 'history', 'question',
		'answer') or { panic(err) }
	for turn in [['one', 'first'], ['two', 'second'], ['three', 'third']] {
		token_memory.save_context(mut ctx, {
			'question': json2.Any(turn[0])
		}, {
			'answer': json2.Any(turn[1])
		}) or { panic(err) }
	}
	loaded := token_memory.load_memory_variables(mut ctx, map[string]json2.Any{}) or { panic(err) }
	history := loaded['history'] or { panic('missing token buffer history') }
	assert history.str() == 'Human: three\nAI: third'
	mut memory_contract := schema.Memory(token_memory)
	assert memory_contract.memory_keys() == ['history']
	memory_contract.clear(mut ctx) or { panic(err) }
	cleared := memory_contract.load_memory_variables(mut ctx, map[string]json2.Any{}) or {
		panic(err)
	}
	assert (cleared['history'] or { panic('missing cleared history') }).str() == ''
}

fn test_token_buffer_memory_keeps_history_when_counter_fails() {
	mut ctx := context.background()
	token_memory := new_token_buffer_memory(FailingTokenCounter{
		state: &FailingTokenCounterState{}
	}, 'fake', 100, 'history', 'question',
		'answer') or { panic(err) }
	token_memory.save_context(mut ctx, {
		'question': json2.Any('old question')
	}, {
		'answer': json2.Any('old answer')
	}) or { panic(err) }
	token_memory.save_context(mut ctx, {
		'question': json2.Any('new question')
	}, {
		'answer': json2.Any('new answer')
	}) or {
		assert err.msg().contains('counting failed')
		loaded := token_memory.load_memory_variables(mut ctx, map[string]json2.Any{}) or { panic(err) }
		assert (loaded['history'] or { panic('missing history') }).str() == 'Human: old question\nAI: old answer'
		return
	}
	assert false, 'expected token counting to fail'
}
