module httputil

import context
import net.http

struct FixtureHTTPClient {
	state &FixtureHTTPClientState
}

struct FixtureStreamingHTTPClient {}

fn (_client FixtureStreamingHTTPClient) do_stream(mut ctx context.Context, _request Request, handler StreamHandler) !Response {
	handler(mut ctx, 'chunk'.bytes())!
	return Response{
		status_code: 200
		body:        'chunk'
	}
}

struct FixtureHTTPClientState {
mut:
	requests []Request
}

struct FixtureHTTPLoggerState {
mut:
	events []HTTPLogEvent
}

struct FixtureChunkState {
mut:
	chunks []string
}

struct FixtureHTTPLogger {
	state &FixtureHTTPLoggerState
}

fn (logger FixtureHTTPLogger) log_http(event HTTPLogEvent) {
	mut state := logger.state
	state.events << event
}

fn (client FixtureHTTPClient) do(mut _ctx context.Context, request Request) !Response {
	mut state := client.state
	state.requests << request
	mut headers := http.Header{}
	headers.set_custom('x-request-id', 'fixture-1')!
	return Response{
		status_code: 200
		headers:     headers
		body:        '{"ok":true}'
	}
}

fn test_http_client_contract_is_fakeable_without_network() {
	mut ctx := context.background()
	mut state := &FixtureHTTPClientState{}
	client := HTTPClient(FixtureHTTPClient{
		state: state
	})
	response := client.do(mut ctx, Request{
		method:  .post
		url:     'https://example.invalid/v1/embeddings'
		headers: {
			'Authorization': 'Bearer test-token'
			'Content-Type':  'application/json'
		}
		body:    '{"input":["safe"]}'
	}) or { panic(err) }
	assert response.status_code == 200
	assert response.body == '{"ok":true}'
	assert (response.headers.get_custom('x-request-id', exact: false) or { '' }) == 'fixture-1'
	assert state.requests.len == 1
	assert state.requests[0].method == .post
	assert (state.requests[0].headers['Authorization'] or { '' }) == 'Bearer test-token'
}

fn test_logging_client_emits_redacted_request_metadata() {
	mut ctx := context.background()
	mut client_state := &FixtureHTTPClientState{}
	mut logger_state := &FixtureHTTPLoggerState{}
	client := new_logging_client(HTTPClient(FixtureHTTPClient{
		state: client_state
	}), HTTPLogger(FixtureHTTPLogger{
		state: logger_state
	}))
	response := client.do(mut ctx, Request{
		method:  .post
		url:     'https://example.test/private/path?token=secret-query'
		headers: {
			'Authorization': 'Bearer secret-header'
		}
		body:    'secret-body'
	}) or { panic(err) }
	assert response.status_code == 200
	assert logger_state.events.len == 1
	event := logger_state.events[0]
	assert event.method == 'POST'
	assert event.host == 'example.test'
	assert event.request_bytes == 'secret-body'.len
	assert event.status_code == 200
	assert event.response_bytes == '{"ok":true}'.len
	assert !event.failed
}

fn test_logging_streaming_client_preserves_chunks_and_emits_one_event() {
	mut ctx := context.background()
	mut logger_state := &FixtureHTTPLoggerState{}
	client := new_logging_streaming_client(StreamingHTTPClient(FixtureStreamingHTTPClient{}),
		HTTPLogger(FixtureHTTPLogger{
			state: logger_state
		}))
	mut chunk_state := &FixtureChunkState{}
	response := client.do_stream(mut ctx, Request{
		method: .post
		url:    'https://example.test/v1/chat'
		body:   'request'
	}, fn [mut chunk_state] (mut _ctx context.Context, chunk []u8) ! {
		chunk_state.chunks << chunk.bytestr()
	}) or { panic(err) }
	assert response.body == 'chunk'
	assert chunk_state.chunks == ['chunk']
	assert logger_state.events.len == 1
	assert logger_state.events[0].response_bytes == 5
}

fn test_default_client_rejects_non_http_urls_before_network() {
	mut ctx := context.background()
	client := HTTPClient(new_default_client())
	client.do(mut ctx, Request{
		url: 'file:///etc/passwd'
	}) or {
		assert err.msg().contains('http or https')
		return
	}
	assert false, 'expected non-HTTP scheme to fail'
}

fn test_default_client_rejects_urls_with_user_information() {
	mut ctx := context.background()
	client := HTTPClient(new_default_client())
	client.do(mut ctx, Request{
		url: 'https://token@example.com/path'
	}) or {
		assert err.msg().contains('user information')
		return
	}
	assert false, 'expected URL user information to fail'
}

fn test_url_validation_accepts_http_and_https_without_userinfo() {
	validate_url('http://localhost:11434/api/chat', '') or { panic(err) }
	validate_url('https://api.example.test/v1/chat', '') or { panic(err) }
	validate_url('https://api.example.test/v1/chat', 'https') or { panic(err) }
	validate_url('https://@api.example.test/v1/chat', '') or {
		assert err.msg().contains('user information')
		return
	}
	assert false, 'expected even empty URL user information to fail'
	validate_url('http://localhost:11434/api/chat', 'https') or {
		assert err.msg().contains('must use https')
		return
	}
	assert false, 'expected the required scheme to be enforced'
}

fn test_default_client_enforces_request_size_before_network() {
	mut ctx := context.background()
	client := DefaultClient{
		max_request_bytes: 2
	}
	client.do(mut ctx, Request{
		url:  'https://example.invalid/'
		body: 'too long'
	}) or {
		assert err.msg().contains('request body exceeds')
		return
	}
	assert false, 'expected oversized request body to fail'
}

fn test_sse_decoder_handles_arbitrary_chunks_multiline_data_and_crlf() {
	mut decoder := new_sse_decoder(128) or { panic(err) }
	first := decoder.push(':keepalive\r\ndata: {"text":'.bytes()) or { panic(err) }
	assert first.len == 0
	second := decoder.push('"hello"}\r\ndata: second\r\n\r\ndata: [DONE]\n\n'.bytes()) or {
		panic(err)
	}
	assert second.len == 2
	assert second[0].bytestr() == '{"text":"hello"}\nsecond'
	assert second[1].bytestr() == '[DONE]'
}

fn test_sse_decoder_enforces_line_and_event_limits() {
	mut decoder := new_sse_decoder(8) or { panic(err) }
	decoder.push('data: 12345678\n'.bytes()) or { panic(err) }
	decoder.push('data: x\n'.bytes()) or {
		assert err.msg().contains('event limit')
		return
	}
	assert false, 'expected an oversized SSE event to fail'
	mut line_decoder := new_sse_decoder(8) or { panic(err) }
	line_decoder.push('123456789'.bytes()) or {
		assert err.msg().contains('line exceeds')
		return
	}
	assert false, 'expected an oversized SSE line to fail'
}

fn test_default_http_client_implements_streaming_transport() {
	mut ctx := context.background()
	client := StreamingHTTPClient(new_default_client())
	client.do_stream(mut ctx, Request{
		url: 'file:///etc/passwd'
	}, fn (mut _ context.Context, _ []u8) ! {
	}) or {
		assert err.msg().contains('http or https')
		return
	}
	assert false, 'expected invalid URL rejection before opening a connection'
}
