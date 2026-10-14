// Package mongodb implements bounded MongoDB-backed chat message history.
module mongodb

import context
import json2
import sync
import ulises_jeremias.langchainv.schema

const default_max_messages = 1024
const max_messages_limit = 4096
const default_max_message_bytes = 16 * 1024
const max_message_bytes_limit = 64 * 1024
const max_history_bytes = 16 * 1024 * 1024

// MongoCollection is the narrow set of collection operations the history
// needs. A caller adapts a real MongoDB driver collection to this interface;
// documents are plain JSON-shaped maps so no driver is bundled here.
pub interface MongoCollection {
	insert_one(mut ctx context.Context, document map[string]json2.Any) !string
	find_sorted(mut ctx context.Context, filter map[string]json2.Any, sort_field string, ascending bool, limit int) ![]map[string]json2.Any
	delete_many(mut ctx context.Context, filter map[string]json2.Any) !int
}

// MongoChatMessageHistory stores typed messages as documents in an injected
// collection. Documents carry session_id, a per-session sequence number, and
// the JSON-encoded message in payload. One history instance should own a
// session at a time, because sequence numbers are assigned in memory.
pub struct MongoChatMessageHistory {
	state &HistoryState
}

@[heap]
struct HistoryState {
mut:
	mutex             sync.Mutex
	collection        MongoCollection
	session           string
	max_messages      int
	max_message_bytes int
	next_seq          int
	closed            bool
}

// new_mongo_chat_message_history resumes a session in the collection. Empty
// session selects "default". Zero limits select 1024 messages and 16 KiB per
// message. The combined read bound cannot exceed 16 MiB.
pub fn new_mongo_chat_message_history(mut ctx context.Context, collection MongoCollection, session string, max_messages int, max_message_bytes int) !&MongoChatMessageHistory {
	actual_session := if session == '' { 'default' } else { session }
	if actual_session.len > 1024 || actual_session.contains('\0') {
		return error('MongoDB history session must be at most 1024 bytes and contain no NUL')
	}
	message_limit := if max_messages == 0 { default_max_messages } else { max_messages }
	message_bytes_limit := if max_message_bytes == 0 {
		default_max_message_bytes
	} else {
		max_message_bytes
	}
	if message_limit < 1 || message_limit > max_messages_limit {
		return error('MongoDB history message limit must be between 1 and ${max_messages_limit}')
	}
	if message_bytes_limit < 1 || message_bytes_limit > max_message_bytes_limit {
		return error('MongoDB history message byte limit must be between 1 and ${max_message_bytes_limit}')
	}
	if message_limit * message_bytes_limit > max_history_bytes {
		return error('MongoDB history read bound must not exceed 16 MiB')
	}
	latest := collection.find_sorted(mut ctx, session_filter(actual_session), 'seq', false,
		1)!
	mut next_seq := 1
	if latest.len > 0 {
		seq_any := latest[0]['seq'] or {
			return error('MongoDB chat history contains a document without a sequence number')
		}
		next_seq = seq_any.int() + 1
		if next_seq < 1 {
			return error('MongoDB chat history contains an invalid sequence number')
		}
	}
	return &MongoChatMessageHistory{
		state: &HistoryState{
			collection:        collection
			session:           actual_session
			max_messages:      message_limit
			max_message_bytes: message_bytes_limit
			next_seq:          next_seq
		}
	}
}

// get_messages returns the recent messages in insertion order.
pub fn (history MongoChatMessageHistory) get_messages(mut ctx context.Context) ![]schema.Message {
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
		return error('MongoDB chat history is closed')
	}
	documents := state.collection.find_sorted(mut ctx, session_filter(state.session),
		'seq', false, state.max_messages)!
	if documents.len > state.max_messages {
		return error('MongoDB chat history returned too many messages')
	}
	mut messages := []schema.Message{cap: documents.len}
	for index := documents.len - 1; index >= 0; index-- {
		payload_any := documents[index]['payload'] or {
			return error('MongoDB chat history contains a document without a payload')
		}
		if payload_any !is string {
			return error('MongoDB chat history payload must be a string')
		}
		payload := payload_any as string
		if payload.len > state.max_message_bytes {
			return error('MongoDB chat history contains an oversized message')
		}
		message := json2.decode[schema.Message](payload, json2.DecoderOptions{}) or {
			return error('MongoDB chat history contains an invalid message')
		}
		messages << message
	}
	return messages
}

// add_message appends one message and trims older documents for this session.
pub fn (history MongoChatMessageHistory) add_message(mut ctx context.Context, message schema.Message) ! {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	payload := json2.encode(message, json2.EncoderOptions{})
	mut state := history.state
	if payload.len > state.max_message_bytes {
		return error('MongoDB chat history message exceeds ${state.max_message_bytes} bytes')
	}
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if state.closed {
		return error('MongoDB chat history is closed')
	}
	seq := state.next_seq
	state.collection.insert_one(mut ctx, {
		'session_id': json2.Any(state.session)
		'seq':        json2.Any(seq)
		'payload':    json2.Any(payload)
	})!
	state.next_seq++
	history.trim(mut ctx, state)!
}

fn (history MongoChatMessageHistory) trim(mut ctx context.Context, state &HistoryState) ! {
	recent := state.collection.find_sorted(mut ctx, session_filter(state.session), 'seq',
		false, state.max_messages + 1)!
	if recent.len <= state.max_messages {
		return
	}
	oldest_kept := recent[state.max_messages - 1]['seq'] or {
		return error('MongoDB chat history contains a document without a sequence number')
	}
	mut filter := session_filter(state.session)
	filter['seq'] = json2.Any({
		'$lt': oldest_kept
	})
	state.collection.delete_many(mut ctx, filter)!
}

// clear removes stored messages for this session.
pub fn (history MongoChatMessageHistory) clear(mut ctx context.Context) ! {
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
		return error('MongoDB chat history is closed')
	}
	state.collection.delete_many(mut ctx, session_filter(state.session))!
}

// close prevents further operations without closing the caller-owned collection.
pub fn (history MongoChatMessageHistory) close() {
	mut state := history.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	state.closed = true
}

fn session_filter(session string) map[string]json2.Any {
	return {
		'session_id': json2.Any(session)
	}
}
