module httputil

import context
import net.http

struct FixtureHTTPClient {
	state &FixtureHTTPClientState
}

struct FixtureHTTPClientState {
mut:
	requests []Request
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
