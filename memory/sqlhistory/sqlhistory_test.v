module sqlhistory

import context
import json2
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.tools.sqldatabase

@[heap]
struct HistoryFixtureState {
mut:
	statements []string
	parameters [][]string
	result     sqldatabase.QueryResult
}

struct HistoryFixtureEngine {
	state        &HistoryFixtureState
	dialect_name string
}

fn (engine HistoryFixtureEngine) dialect() string {
	return if engine.dialect_name == '' { 'pgx' } else { engine.dialect_name }
}

fn (engine HistoryFixtureEngine) query(mut _ctx context.Context, statement string) !sqldatabase.QueryResult {
	mut state := engine.state
	state.statements << statement
	return sqldatabase.QueryResult{}
}

fn (engine HistoryFixtureEngine) query_params(mut _ctx context.Context, statement string, parameters []string) !sqldatabase.QueryResult {
	mut state := engine.state
	state.statements << statement
	state.parameters << parameters.clone()
	return state.result
}

fn (engine HistoryFixtureEngine) table_names(mut _ctx context.Context, _max_tables int) ![]string {
	return []string{}
}

fn (engine HistoryFixtureEngine) table_info(mut _ctx context.Context, _table string) !string {
	return ''
}

fn (engine HistoryFixtureEngine) close() ! {}

fn new_fixture(state &HistoryFixtureState) !&PostgresChatMessageHistory {
	mut ctx := context.background()
	return new_postgres_chat_message_history(mut ctx, HistoryFixtureEngine{
		state: state
	}, 'session-a', 2, 1024)
}

fn test_postgres_chat_history_initializes_and_trims_bounded_session() {
	mut state := &HistoryFixtureState{}
	history := new_fixture(state) or { panic(err) }
	assert state.statements.len == 3
	assert state.statements[0].starts_with('CREATE TABLE IF NOT EXISTS langchain_chat_messages')
	assert state.statements[1].contains('CREATE INDEX IF NOT EXISTS')
	assert state.statements[2].starts_with('DELETE FROM langchain_chat_messages')
	assert state.parameters[0] == ['session-a', 'session-a', '2']
	history.close()
}

fn test_postgres_chat_history_round_trips_typed_messages_and_trims() {
	mut state := &HistoryFixtureState{}
	history := new_fixture(state) or { panic(err) }
	mut ctx := context.background()
	message := schema.text_message(.human, 'hello')
	history.add_message(mut ctx, message) or { panic(err) }
	assert state.parameters[1] == ['session-a', json2.encode(message, json2.EncoderOptions{})]
	assert state.parameters[2] == ['session-a', 'session-a', '2']
	payload := json2.encode(message, json2.EncoderOptions{})
	state.result = sqldatabase.QueryResult{
		rows: [[payload, payload.len.str()]]
	}
	messages := history.get_messages(mut ctx) or { panic(err) }
	assert messages.len == 1
	assert messages[0].role == .human
	assert messages[0].text() == 'hello'
	assert state.parameters[3] == ['session-a', '1024', '2']
	history.clear(mut ctx) or { panic(err) }
	assert state.statements.last().starts_with('DELETE FROM langchain_chat_messages WHERE session')
}

fn test_postgres_chat_history_rejects_invalid_configuration_and_rows() {
	mut state := &HistoryFixtureState{}
	mut ctx := context.background()
	new_postgres_chat_message_history(mut ctx, HistoryFixtureEngine{
		state: state
	}, 'session-a', 4096, 65536) or {
		assert err.msg().contains('16 MiB')
		return
	}
	assert false, 'expected an excessive read bound to fail'
	history := new_fixture(state) or { panic(err) }
	state.result = sqldatabase.QueryResult{
		rows: [['', '2048']]
	}
	history.get_messages(mut ctx) or {
		assert err.msg().contains('oversized or invalid message')
		history.close()
		return
	}
	history.close()
	assert false, 'expected an oversized stored message to fail'
}

fn test_postgres_chat_history_rejects_non_postgres_engine() {
	mut state := &HistoryFixtureState{}
	mut ctx := context.background()
	new_postgres_chat_message_history(mut ctx, HistoryFixtureEngine{
		state:        state
		dialect_name: 'sqlite3'
	}, 'session-a', 2, 1024) or {
		assert err.msg().contains('PostgreSQL engine')
		assert state.statements.len == 0
		return
	}
	assert false, 'expected a non-PostgreSQL engine to fail'
}
