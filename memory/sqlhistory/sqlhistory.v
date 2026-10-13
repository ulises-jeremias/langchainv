// Package sqlhistory implements bounded PostgreSQL-backed chat message history.
module sqlhistory

import context
import json2
import strconv
import sync
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.tools.sqldatabase

const default_max_messages = 1024
const max_messages_limit = 4096
const default_max_message_bytes = 16 * 1024
const max_message_bytes_limit = 64 * 1024
const max_history_bytes = 16 * 1024 * 1024
const table_name = 'langchain_chat_messages'

// PostgresChatMessageHistory stores typed messages in an existing PostgreSQL
// engine. The engine is injected and remains owned by the caller.
pub struct PostgresChatMessageHistory {
	state &HistoryState
}

@[heap]
struct HistoryState {
mut:
	mutex             sync.Mutex
	engine            sqldatabase.Engine
	session           string
	max_messages      int
	max_message_bytes int
	closed            bool
}

// new_postgres_chat_message_history creates the shared history table and index
// when missing, trims old messages for this session, and returns a bounded
// history. Empty session selects "default". Zero limits select 1024 messages
// and 16 KiB per message. The combined read bound cannot exceed 16 MiB.
// This function accepts pgx/PostgreSQL engines and does not own the connection.
pub fn new_postgres_chat_message_history(mut ctx context.Context, engine sqldatabase.Engine, session string, max_messages int, max_message_bytes int) !&PostgresChatMessageHistory {
	if engine.dialect() !in ['pgx', 'postgresql'] {
		return error('PostgreSQL chat history requires a PostgreSQL engine')
	}
	actual_session := if session == '' { 'default' } else { session }
	if actual_session.len > 1024 || actual_session.contains('\0') {
		return error('PostgreSQL history session must be at most 1024 bytes and contain no NUL')
	}
	message_limit := if max_messages == 0 { default_max_messages } else { max_messages }
	message_bytes_limit := if max_message_bytes == 0 {
		default_max_message_bytes
	} else {
		max_message_bytes
	}
	if message_limit < 1 || message_limit > max_messages_limit {
		return error('PostgreSQL history message limit must be between 1 and ${max_messages_limit}')
	}
	if message_bytes_limit < 1 || message_bytes_limit > max_message_bytes_limit {
		return error('PostgreSQL history message byte limit must be between 1 and ${max_message_bytes_limit}')
	}
	if message_limit * message_bytes_limit > max_history_bytes {
		return error('PostgreSQL history read bound must not exceed 16 MiB')
	}
	engine.query(mut ctx, 'CREATE TABLE IF NOT EXISTS ${table_name} (id BIGSERIAL PRIMARY KEY, session TEXT NOT NULL, payload TEXT NOT NULL)') or {
		return error('could not initialize PostgreSQL chat history')
	}
	engine.query(mut ctx, 'CREATE INDEX IF NOT EXISTS idx_langchain_chat_messages_session_id ON ${table_name}(session, id)') or {
		return error('could not index PostgreSQL chat history')
	}
	trim_history(mut ctx, engine, actual_session, message_limit)!
	return &PostgresChatMessageHistory{
		state: &HistoryState{
			engine:            engine
			session:           actual_session
			max_messages:      message_limit
			max_message_bytes: message_bytes_limit
		}
	}
}

// get_messages returns the recent messages in insertion order. Oversized rows
// are detected by PostgreSQL without transferring their full payload.
pub fn (history PostgresChatMessageHistory) get_messages(mut ctx context.Context) ![]schema.Message {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	mut state := history.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if state.closed {
		return error('PostgreSQL chat history is closed')
	}
	statement := "SELECT CASE WHEN octet_length(payload) > $2::int THEN '' ELSE payload END, octet_length(payload)::text FROM (SELECT id, payload FROM ${table_name} WHERE session = $1 ORDER BY id DESC LIMIT $3::int) AS recent ORDER BY id ASC"
	result := state.engine.query_params(mut ctx, statement, [state.session,
		state.max_message_bytes.str(), state.max_messages.str()])!
	if result.rows.len > state.max_messages {
		return error('PostgreSQL chat history returned too many messages')
	}
	mut messages := []schema.Message{cap: result.rows.len}
	for row in result.rows {
		if row.len != 2 {
			return error('PostgreSQL chat history returned a malformed row')
		}
		payload_bytes := strconv.atoi(row[1]) or {
			return error('PostgreSQL chat history returned an invalid message size')
		}
		if payload_bytes < 0 || payload_bytes > state.max_message_bytes || row[0].len != payload_bytes {
			return error('PostgreSQL chat history contains an oversized or invalid message')
		}
		message := json2.decode[schema.Message](row[0], json2.DecoderOptions{}) or {
			return error('PostgreSQL chat history contains an invalid message')
		}
		messages << message
	}
	ctx_error_after_read := ctx.err()
	if ctx_error_after_read !is none {
		return ctx_error_after_read
	}
	return messages
}

// add_message appends one message and trims older rows for this session.
// The caller owns the engine; an insert may remain stored if trimming fails.
pub fn (history PostgresChatMessageHistory) add_message(mut ctx context.Context, message schema.Message) ! {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	payload := json2.encode(message, json2.EncoderOptions{})
	mut state := history.state
	if payload.len > state.max_message_bytes {
		return error('PostgreSQL chat history message exceeds ${state.max_message_bytes} bytes')
	}
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if state.closed {
		return error('PostgreSQL chat history is closed')
	}
	ctx_error_after_lock := ctx.err()
	if ctx_error_after_lock !is none {
		return ctx_error_after_lock
	}
	state.engine.query_params(mut ctx, 'INSERT INTO ${table_name} (session, payload) VALUES ($1, $2)', [
		state.session,
		payload,
	])!
	trim_history(mut ctx, state.engine, state.session, state.max_messages)!
}

// clear removes stored messages for this session.
pub fn (history PostgresChatMessageHistory) clear(mut ctx context.Context) ! {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	mut state := history.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if state.closed {
		return error('PostgreSQL chat history is closed')
	}
	state.engine.query_params(mut ctx, 'DELETE FROM ${table_name} WHERE session = $1', [state.session])!
	ctx_error_after_clear := ctx.err()
	if ctx_error_after_clear !is none {
		return ctx_error_after_clear
	}
}

// close prevents further operations without closing the caller-owned engine.
pub fn (history PostgresChatMessageHistory) close() {
	mut state := history.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	state.closed = true
}

fn trim_history(mut ctx context.Context, engine sqldatabase.Engine, session string, limit int) ! {
	engine.query_params(mut ctx, 'DELETE FROM ${table_name} WHERE session = $1 AND id NOT IN (SELECT id FROM ${table_name} WHERE session = $2 ORDER BY id DESC LIMIT $3::int)', [
		session,
		session,
		limit.str(),
	])!
}
