// Package sqlite implements bounded SQLite-backed chat message history.
module sqlite

import context
import db.sqlite
import json2
import sync
import ulises_jeremias.langchainv.schema

const default_max_messages = 1024
const max_messages_limit = 4096
const default_max_message_bytes = 16 * 1024
const max_message_bytes_limit = 64 * 1024
const max_history_bytes = 16 * 1024 * 1024

// SQLiteChatMessageHistory stores typed messages in a SQLite database.
pub struct SQLiteChatMessageHistory {
	state &SQLiteChatMessageHistoryState
}

@[heap]
struct SQLiteChatMessageHistoryState {
mut:
	mutex             sync.Mutex
	db                sqlite.DB
	session           string
	max_messages      int
	max_message_bytes int
	closed            bool
}

// new_sqlite_chat_message_history opens a database and creates its message table.
// An empty session selects "default". Sessions in the same database stay isolated.
// A zero message limit selects the default of 1024. A zero byte limit selects
// the default of 16 KiB. The combined read bound cannot exceed 16 MiB.
pub fn new_sqlite_chat_message_history(database_path string, session string, max_messages int, max_message_bytes int) !&SQLiteChatMessageHistory {
	if database_path.trim_space() == '' || database_path.len > 4096 {
		return error('SQLite database path must contain between 1 and 4096 bytes')
	}
	actual_session := if session == '' { 'default' } else { session }
	if actual_session.len > 1024 || actual_session.contains('\0') {
		return error('SQLite history session must be at most 1024 bytes and contain no NUL')
	}
	message_limit := if max_messages == 0 { default_max_messages } else { max_messages }
	message_bytes_limit := if max_message_bytes == 0 {
		default_max_message_bytes
	} else {
		max_message_bytes
	}
	if message_limit < 1 || message_limit > max_messages_limit {
		return error('SQLite history message limit must be between 1 and ${max_messages_limit}')
	}
	if message_bytes_limit < 1 || message_bytes_limit > max_message_bytes_limit {
		return error('SQLite history message byte limit must be between 1 and ${max_message_bytes_limit}')
	}
	if message_limit * message_bytes_limit > max_history_bytes {
		return error('SQLite history read bound must not exceed 16 MiB')
	}
	mut db := sqlite.connect(database_path) or {
		return error('could not open SQLite chat history database: ${err.msg()}')
	}
	db.exec('CREATE TABLE IF NOT EXISTS langchain_messages (id INTEGER PRIMARY KEY, session TEXT NOT NULL, payload TEXT NOT NULL)') or {
		db.close() or {}
		return error('could not initialize SQLite chat history')
	}
	db.exec('CREATE INDEX IF NOT EXISTS idx_langchain_messages_session_id ON langchain_messages(session, id)') or {
		db.close() or {}
		return error('could not index SQLite chat history')
	}
	db.exec_param_many('DELETE FROM langchain_messages WHERE session = ? AND id NOT IN (SELECT id FROM langchain_messages WHERE session = ? ORDER BY id DESC LIMIT ?)', [
		actual_session,
		actual_session,
		message_limit.str(),
	]) or {
		db.close() or {}
		return error('could not trim SQLite chat history')
	}
	return &SQLiteChatMessageHistory{
		state: &SQLiteChatMessageHistoryState{
			db:                db
			session:           actual_session
			max_messages:      message_limit
			max_message_bytes: message_bytes_limit
		}
	}
}

// get_messages returns the most recent messages in insertion order.
pub fn (history SQLiteChatMessageHistory) get_messages(mut ctx context.Context) ![]schema.Message {
	mut err := ctx.err()
	if err !is none {
		return err
	}
	mut state := history.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if state.closed {
		return error('SQLite chat history is closed')
	}
	rows := state.db.exec_param_many('SELECT CAST(substr(CAST(payload AS BLOB), 1, ${state.max_message_bytes + 1}) AS TEXT) FROM langchain_messages WHERE session = ? ORDER BY id DESC LIMIT ?', [
		state.session,
		state.max_messages.str(),
	]) or {
		return error('could not read SQLite chat history')
	}
	mut messages := []schema.Message{cap: rows.len}
	for row in rows.reverse() {
		if row.vals.len != 1 || row.vals[0].len > state.max_message_bytes {
			return error('SQLite chat history contains an oversized or invalid message')
		}
		message := json2.decode[schema.Message](row.vals[0], json2.DecoderOptions{}) or {
			return error('SQLite chat history contains an invalid message')
		}
		messages << message
	}
	err = ctx.err()
	if err !is none {
		return err
	}
	return messages
}

// add_message stores one typed message and removes rows beyond the configured limit.
pub fn (history SQLiteChatMessageHistory) add_message(mut ctx context.Context, message schema.Message) ! {
	mut err := ctx.err()
	if err !is none {
		return err
	}
	payload := json2.encode(message, json2.EncoderOptions{})
	mut state := history.state
	if payload.len > state.max_message_bytes {
		return error('SQLite chat history message exceeds ${state.max_message_bytes} bytes')
	}
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if state.closed {
		return error('SQLite chat history is closed')
	}
	err = ctx.err()
	if err !is none {
		return err
	}
	state.db.begin() or { return error('could not start SQLite chat history transaction') }
	mut committed := false
	defer {
		if !committed {
			state.db.rollback() or {}
		}
	}
	state.db.exec_param2('INSERT INTO langchain_messages (session, payload) VALUES (?, ?)', state.session, payload) or {
		return error('could not store SQLite chat history message')
	}
	state.db.exec_param_many('DELETE FROM langchain_messages WHERE session = ? AND id NOT IN (SELECT id FROM langchain_messages WHERE session = ? ORDER BY id DESC LIMIT ?)', [
		state.session,
		state.session,
		state.max_messages.str(),
	]) or {
		return error('could not trim SQLite chat history')
	}
	err = ctx.err()
	if err !is none {
		return err
	}
	state.db.commit() or { return error('could not commit SQLite chat history message') }
	committed = true
}

// clear removes all stored messages.
pub fn (history SQLiteChatMessageHistory) clear(mut ctx context.Context) ! {
	mut err := ctx.err()
	if err !is none {
		return err
	}
	mut state := history.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if state.closed {
		return error('SQLite chat history is closed')
	}
	err = ctx.err()
	if err !is none {
		return err
	}
	state.db.exec_param('DELETE FROM langchain_messages WHERE session = ?', state.session) or {
		return error('could not clear SQLite chat history')
	}
}

// close closes the underlying database connection.
pub fn (history SQLiteChatMessageHistory) close() ! {
	mut state := history.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if !state.closed {
		state.db.close() or { return error('could not close SQLite chat history') }
		state.closed = true
	}
}
