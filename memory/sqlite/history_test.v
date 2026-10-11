module sqlite

import context
import os
import time
import ulises_jeremias.langchainv.schema

fn test_sqlite_chat_message_history_round_trip_limit_and_clear() {
	history := new_sqlite_chat_message_history(':memory:', 'window-test', 2, 1024) or { panic(err) }
	mut ctx := context.background()
	history.add_message(mut ctx, schema.text_message(.human, 'first')) or { panic(err) }
	history.add_message(mut ctx, schema.text_message(.ai, 'second')) or { panic(err) }
	history.add_message(mut ctx, schema.text_message(.human, 'third')) or { panic(err) }
	messages := history.get_messages(mut ctx) or { panic(err) }
	assert messages.len == 2
	assert messages[0].role == .ai
	assert messages[0].text() == 'second'
	assert messages[1].role == .human
	assert messages[1].text() == 'third'
	tool_message := schema.Message{
		role:  .ai
		parts: [schema.ContentPart(schema.ToolCall{
			id:            'call-1'
			call_type:     'function'
			function_call: schema.FunctionCall{
				name:      'lookup'
				arguments: '{"id":7}'
			}
		})]
	}
	history.add_message(mut ctx, tool_message) or { panic(err) }
	messages_with_tool := history.get_messages(mut ctx) or { panic(err) }
	assert messages_with_tool.len == 2
	assert messages_with_tool[1].parts[0] is schema.ToolCall
	tool_call := messages_with_tool[1].parts[0] as schema.ToolCall
	assert tool_call.function_call.name == 'lookup'
	history.clear(mut ctx) or { panic(err) }
	empty_messages := history.get_messages(mut ctx) or { panic(err) }
	assert empty_messages.len == 0
	history.close() or { panic(err) }
}

fn test_sqlite_chat_message_history_bounds_configuration_and_payload() {
	new_sqlite_chat_message_history(':memory:', 'bounds-test', 1024, 64 * 1024) or {
		assert err.msg().contains('16 MiB')
		return
	}
	assert false, 'expected the combined history bound to be rejected'

	history := new_sqlite_chat_message_history(':memory:', 'size-test', 1, 1024) or { panic(err) }
	mut ctx := context.background()
	history.add_message(mut ctx, schema.text_message(.human, 'x'.repeat(2048))) or {
		assert err.msg().contains('exceeds 1024 bytes')
		history.close() or { panic(err) }
		return
	}
	history.close() or { panic(err) }
	assert false, 'expected an oversized message to be rejected'
}

fn test_sqlite_chat_message_history_persists_across_reopen() {
	path := os.join_path(os.temp_dir(), 'langchainv-memory-${os.getpid()}-${time.now().unix_nano()}.sqlite')
	defer {
		os.rm(path) or {}
	}
	mut ctx := context.background()
	history := new_sqlite_chat_message_history(path, 'alpha', 10, 1024) or { panic(err) }
	history.add_message(mut ctx, schema.text_message(.human, 'persisted')) or { panic(err) }
	history.close() or { panic(err) }

	other_session := new_sqlite_chat_message_history(path, 'beta', 10, 1024) or { panic(err) }
	other_session.add_message(mut ctx, schema.text_message(.human, 'separate')) or { panic(err) }
	other_messages := other_session.get_messages(mut ctx) or { panic(err) }
	assert other_messages.len == 1
	assert other_messages[0].text() == 'separate'
	other_session.close() or { panic(err) }

	reopened := new_sqlite_chat_message_history(path, 'alpha', 10, 1024) or { panic(err) }
	messages := reopened.get_messages(mut ctx) or { panic(err) }
	assert messages.len == 1
	assert messages[0].text() == 'persisted'
	reopened.close() or { panic(err) }
}
