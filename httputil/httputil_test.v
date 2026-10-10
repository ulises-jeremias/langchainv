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
		method: .post
		url:    'https://example.invalid/v1/embeddings'
		headers: {
			'Authorization': 'Bearer test-token'
			'Content-Type':  'application/json'
		}
		body:   '{"input":["safe"]}'
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
