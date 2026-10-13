// Package zep implements bounded Zep chat message history over its HTTP API.
module zep

import context
import json2
import net.http
import net.urllib
import os
import sync
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.schema

const default_base_url = 'https://api.getzep.com/api/v2'
const max_response_bytes = 4 * 1024 * 1024
const default_max_messages = 1024
const max_messages_limit = 4096
const max_message_bytes = 64 * 1024

struct ZepMessage {
	role_type string @[json: 'role_type']
	role      string
	content   string
}

struct ZepSummary {
	content string
}

struct ZepMemory {
	messages []ZepMessage
	facts    []string
	summary  ?ZepSummary
}

struct ZepAddMemoryRequest {
	messages []map[string]json2.Any
}

// Options configures the Zep API, session, memory selection, and history bound.
pub struct Options {
pub:
	api_key      string
	base_url     string = default_base_url
	session_id   string
	memory_type  string = 'perpetual'
	max_messages int    = default_max_messages
	human_prefix string
	ai_prefix    string
}

// ChatMessageHistory stores typed messages in one Zep session. The HTTP client
// is injected and remains owned by the caller.
pub struct ChatMessageHistory {
	state &HistoryState
}

@[heap]
struct HistoryState {
mut:
	mutex        sync.Mutex
	api_key      string
	base_url     string
	session_id   string
	memory_type  string
	max_messages int
	human_prefix string
	ai_prefix    string
	http_client  httputil.HTTPClient
	closed       bool
}

// new_chat_message_history creates a history using the bounded default HTTP
// client. The API key comes from options.api_key or ZEP_API_KEY.
pub fn new_chat_message_history(options Options) !&ChatMessageHistory {
	return new_chat_message_history_with_client(options,
		httputil.HTTPClient(httputil.new_default_client()))
}

// new_chat_message_history_with_client creates a history with an injected HTTP
// client, allowing deterministic offline tests. A blank session selects
// "default". Supported memory types are perpetual, summary_retriever, and
// message_window. Reads request at most max_messages and 4 MiB of response data.
pub fn new_chat_message_history_with_client(options Options, http_client httputil.HTTPClient) !&ChatMessageHistory {
	api_key := if options.api_key.trim_space() == '' {
		os.getenv('ZEP_API_KEY').trim_space()
	} else {
		options.api_key.trim_space()
	}
	base_url := options.base_url.trim_space().trim_right('/')
	session_id := if options.session_id == '' { 'default' } else { options.session_id }
	max_messages := if options.max_messages == 0 { default_max_messages } else { options.max_messages }
	if api_key == '' || api_key.len > 16 * 1024 || api_key.contains('\r') || api_key.contains('\n') {
		return error('Zep API key must be configured and contain no line breaks')
	}
	if base_url.contains('?') || base_url.contains('#') {
		return error('Zep base URL must not include a query or fragment')
	}
	httputil.validate_url(base_url, 'https') or {
		return error('Zep base URL must be a valid HTTPS URL')
	}
	if session_id.trim_space() == '' || session_id.len > 1024 || session_id.contains('\0') {
		return error('Zep session ID must contain between 1 and 1024 bytes')
	}
	if options.memory_type !in ['perpetual', 'summary_retriever', 'message_window'] {
		return error('Zep memory type must be perpetual, summary_retriever, or message_window')
	}
	if max_messages < 1 || max_messages > max_messages_limit {
		return error('Zep message limit must be between 1 and ${max_messages_limit}')
	}
	for prefix in [options.human_prefix, options.ai_prefix] {
		if prefix.len > 1024 || prefix.contains('\0') {
			return error('Zep message prefixes must be at most 1024 bytes and contain no NUL')
		}
	}
	return &ChatMessageHistory{
		state: &HistoryState{
			api_key:      api_key
			base_url:     base_url
			session_id:   session_id
			memory_type:  options.memory_type
			max_messages: max_messages
			human_prefix: options.human_prefix
			ai_prefix:    options.ai_prefix
			http_client:  http_client
		}
	}
}

// get_messages returns Zep's selected session memory as typed chat messages.
// Facts and the latest summary are prepended as one system message, matching
// LangChainGo's Zep adapter behavior.
pub fn (history ChatMessageHistory) get_messages(mut ctx context.Context) ![]schema.Message {
	mut state := history.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if state.closed {
		return error('Zep chat history is closed')
	}
	url := '${memory_url(state)}?memoryType=${urllib.query_escape(state.memory_type)}&lastn=${state.max_messages}'
	response := state.request(mut ctx, .get, url, '')!
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Zep memory read returned HTTP ${response.status_code}')
	}
	if response.body.len > max_response_bytes {
		return error('Zep memory response exceeds 4 MiB')
	}
	memory := json2.decode[ZepMemory](response.body, json2.DecoderOptions{}) or {
		return error('Zep returned invalid memory JSON')
	}
	if memory.messages.len > state.max_messages {
		return error('Zep returned more messages than requested')
	}
	mut messages := []schema.Message{cap: memory.messages.len + 1}
	for item in memory.messages {
		if item.content.len > max_message_bytes {
			return error('Zep message exceeds 64 KiB')
		}
		role_type := if item.role_type != '' { item.role_type } else { item.role }
		match role_type.to_lower() {
			'user' {
				messages << schema.text_message(.human, item.content)
			}
			'assistant' {
				messages << schema.text_message(.ai, item.content)
			}
			'tool', 'function' {
				messages << schema.text_message(.tool, item.content)
			}
			else {}
		}
	}
	mut system_content := memory.facts.join('\n')
	if summary := memory.summary {
		if summary.content.len > max_message_bytes {
			return error('Zep summary exceeds 64 KiB')
		}
		if summary.content != '' {
			if system_content != '' {
				system_content += '\n'
			}
			system_content += summary.content
		}
	}
	if system_content.len > max_message_bytes {
		return error('Zep facts and summary exceed 64 KiB')
	}
	if system_content != '' {
		messages.insert(0, schema.text_message(.system, system_content))
	}
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	return messages
}

// add_message appends one human, assistant, or tool message to Zep memory.
pub fn (history ChatMessageHistory) add_message(mut ctx context.Context, message schema.Message) ! {
	mut state := history.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if state.closed {
		return error('Zep chat history is closed')
	}
	content := message.text()
	if content.len > max_message_bytes {
		return error('Zep message exceeds 64 KiB')
	}
	mut remote := map[string]json2.Any{
		'content':   json2.Any(content)
		'role_type': json2.Any('')
	}
	match message.role {
		.human {
			remote['role_type'] = json2.Any('user')
			if state.human_prefix != '' {
				remote['role'] = json2.Any(state.human_prefix)
			}
		}
		.ai {
			remote['role_type'] = json2.Any('assistant')
			if state.ai_prefix != '' {
				remote['role'] = json2.Any(state.ai_prefix)
			}
		}
		.tool {
			remote['role_type'] = json2.Any('tool')
		}
		.system, .generic {
			return error('Zep history supports human, assistant, and tool messages only')
		}
	}
	request_body := json2.encode(ZepAddMemoryRequest{messages: [remote]}, json2.EncoderOptions{})
	response := state.request(mut ctx, .post, memory_url(state), request_body)!
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Zep memory write returned HTTP ${response.status_code}')
	}
}

// clear removes all messages from the configured Zep session.
pub fn (history ChatMessageHistory) clear(mut ctx context.Context) ! {
	mut state := history.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if state.closed {
		return error('Zep chat history is closed')
	}
	response := state.request(mut ctx, .delete, memory_url(state), '')!
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Zep memory deletion returned HTTP ${response.status_code}')
	}
}

// close prevents further calls without closing the caller-owned HTTP client.
pub fn (history ChatMessageHistory) close() {
	mut state := history.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	state.closed = true
}

fn memory_url(state &HistoryState) string {
	return '${state.base_url}/sessions/${urllib.query_escape(state.session_id)}/memory'
}

fn (state &HistoryState) request(mut ctx context.Context, method http.Method, url string, body string) !httputil.Response {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	if body.len > max_message_bytes * 2 {
		return error('Zep request exceeds 128 KiB')
	}
	return state.http_client.do(mut ctx, httputil.Request{
		method:  method
		url:     url
		headers: {
			'Authorization': 'Api-Key ${state.api_key}'
			'Accept':        'application/json'
			'Content-Type':  'application/json'
		}
		body:    body
	}) or {
		return error('Zep HTTP request failed')
	}
}
