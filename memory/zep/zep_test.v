module zep

import context
import net.http
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.schema

struct FakeHTTPClient {
	state &FakeHTTPState
}

struct FakeHTTPState {
mut:
	requests []httputil.Request
	response httputil.Response
}

fn (client FakeHTTPClient) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	return state.response
}

fn fake_history(body string) (&ChatMessageHistory, &FakeHTTPState) {
	mut state := &FakeHTTPState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        body
		}
	}
	history := new_chat_message_history_with_client(Options{
		api_key:      'test-secret'
		session_id:   'tenant/one'
		human_prefix: 'Human'
		ai_prefix:    'Assistant'
	}, FakeHTTPClient{
		state: state
	}) or { panic(err) }
	return history, state
}

fn test_zep_reads_recent_messages_and_prepends_summary_and_facts() {
	mut ctx := context.background()
	history, state := fake_history('{"messages":[{"role_type":"user","content":"hello"},{"role_type":"assistant","content":"hi"},{"role_type":"tool","content":"done"}],"facts":["likes V"],"summary":{"content":"Asked about V"}}')
	messages := history.get_messages(mut ctx) or { panic(err) }
	assert messages.len == 4
	assert messages[0].role == .system
	assert messages[0].text() == 'likes V\nAsked about V'
	assert messages[1].role == .human
	assert messages[1].text() == 'hello'
	assert messages[2].role == .ai
	assert messages[3].role == .tool
	request := state.requests[0]
	assert request.method == .get
	assert request.url == 'https://api.getzep.com/api/v2/sessions/tenant%2Fone/memory?memoryType=perpetual&lastn=1024'
	assert (request.headers['Authorization'] or { '' }) == 'Api-Key test-secret'
}

fn test_zep_adds_supported_messages_and_clears_only_the_selected_session() {
	mut ctx := context.background()
	history, state := fake_history('{}')
	history.add_message(mut ctx, schema.text_message(.human, 'question')) or { panic(err) }
	assert state.requests.len == 1
	request := state.requests[0]
	assert request.method == .post
	assert request.body.contains('"role_type":"user"')
	assert request.body.contains('"role":"Human"')
	assert request.body.contains('"content":"question"')
	history.clear(mut ctx) or { panic(err) }
	assert state.requests.len == 2
	assert state.requests[1].method == .delete
	assert state.requests[1].url.contains('/sessions/tenant%2Fone/memory')
}

fn test_zep_rejects_unsupported_messages_and_http_errors() {
	mut ctx := context.background()
	history, state := fake_history('{}')
	history.add_message(mut ctx, schema.text_message(.system, 'system')) or {
		assert err.msg().contains('supports human, assistant, and tool')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected system message to fail'
}

fn test_zep_rejects_http_errors_without_echoing_response_body() {
	mut state := &FakeHTTPState{
		response: httputil.Response{
			status_code: 401
			body:        'sensitive provider response'
		}
	}
	history := new_chat_message_history_with_client(Options{
		api_key: 'test-secret'
	}, FakeHTTPClient{
		state: state
	}) or { panic(err) }
	mut ctx := context.background()
	history.get_messages(mut ctx) or {
		assert err.msg() == 'Zep memory read returned HTTP 401'
		assert !err.msg().contains('sensitive')
		return
	}
	assert false, 'expected HTTP status error'
}

fn test_zep_rejects_insecure_base_url() {
	new_chat_message_history_with_client(Options{
		api_key:  'test-secret'
		base_url: 'http://zep.example/api/v2'
	}, FakeHTTPClient{
		state: &FakeHTTPState{}
	}) or {
		assert err.msg().contains('HTTPS')
		return
	}
	assert false, 'expected insecure URL to fail'
}

fn test_zep_bounds_message_payloads() {
	mut ctx := context.background()
	history, state := fake_history('{"messages":[{"role_type":"user","content":"${'x'.repeat(65537)}"}]}')
	history.get_messages(mut ctx) or {
		assert err.msg().contains('exceeds 64 KiB')
		assert state.requests.len == 1
		return
	}
	assert false, 'expected oversized message to fail'
}
