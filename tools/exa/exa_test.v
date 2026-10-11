module exa

import context
import ulises_jeremias.langchainv.httputil

@[heap]
struct ExaFixtureState {
mut:
	request httputil.Request
}

struct ExaFixtureHTTP {
	state       &ExaFixtureState
	response    string
	status_code int = 200
}

fn (client ExaFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.request = request
	return httputil.Response{
		status_code: client.status_code
		body:        client.response
	}
}

fn test_exa_tool_posts_semantic_query_and_formats_highlights() {
	mut state := &ExaFixtureState{}
	http := ExaFixtureHTTP{
		state:    state
		response: '{"results":[{"title":"V language","url":"https://vlang.io/","highlights":["Fast compilation.","Simple syntax."]},{"title":"Second","url":"https://example.com","text":"Fallback body."}]}'
	}
	tool := new_tool('test-api-key', 2, httputil.HTTPClient(http)) or { panic(err) }
	mut ctx := context.background()
	result := tool.call(mut ctx, '{"query":"fast V compiler"}') or { panic(err) }
	assert state.request.method == .post
	assert state.request.url == exa_search_endpoint
	assert state.request.headers['x-api-key'] == 'test-api-key'
	assert state.request.headers['Content-Type'] == 'application/json'
	assert state.request.body.contains('"numResults":2')
	assert state.request.body.contains('"highlights":true')
	assert result == 'Title: V language\nDescription: Fast compilation. Simple syntax.\nURL: https://vlang.io/\n\nTitle: Second\nDescription: Fallback body.\nURL: https://example.com\n\n'
}

fn test_exa_tool_returns_empty_message_and_rejects_empty_queries() {
	mut state := &ExaFixtureState{}
	http := ExaFixtureHTTP{
		state:    state
		response: '{"results":[]}'
	}
	tool := new_tool('test-key', 0, httputil.HTTPClient(http)) or { panic(err) }
	mut ctx := context.background()
	assert tool.call(mut ctx, 'V') or { panic(err) } == no_results_message
	tool.call(mut ctx, ' ') or {
		assert err.msg().contains('must not be empty')
		return
	}
	assert false, 'expected empty query to fail'
}

fn test_exa_tool_hides_provider_error_details() {
	mut state := &ExaFixtureState{}
	http := ExaFixtureHTTP{
		state:    state
		response: '{"error":"invalid key with secret detail"}'
	}
	tool := new_tool('test-key', 1, httputil.HTTPClient(http)) or { panic(err) }
	mut ctx := context.background()
	tool.call(mut ctx, 'V') or {
		assert err.msg() == 'Exa search failed'
		assert !err.msg().contains('secret')
		return
	}
	assert false, 'expected Exa provider error to fail'
}
