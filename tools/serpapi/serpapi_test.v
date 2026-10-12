module serpapi

import context
import ulises_jeremias.langchainv.httputil

@[heap]
struct SerpApiFixtureState {
mut:
	request httputil.Request
}

struct SerpApiFixtureHTTP {
	state       &SerpApiFixtureState
	response    string
	status_code int = 200
}

fn (client SerpApiFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.request = request
	return httputil.Response{
		status_code: client.status_code
		body:        client.response
	}
}

fn test_serpapi_tool_encodes_query_and_formats_bounded_results() {
	mut state := &SerpApiFixtureState{}
	http := SerpApiFixtureHTTP{
		state:    state
		response: '{"organic_results":[{"title":"V language","link":"https://vlang.io/","snippet":"A simple language."},{"title":"Second","link":"https://example.com","snippet":"Another result."}]}'
	}
	tool := new_tool('test/key', 1, httputil.HTTPClient(http)) or { panic(err) }
	mut ctx := context.background()
	result := tool.call(mut ctx, '{"query":"V compiler"}') or { panic(err) }
	assert state.request.url == 'https://serpapi.com/search.json?engine=google&q=V+compiler&api_key=test%2Fkey&output=json'
	assert state.request.headers['Accept'] == 'application/json'
	assert result == 'Title: V language\nDescription: A simple language.\nURL: https://vlang.io/\n\n'
}

fn test_serpapi_tool_handles_empty_results_and_rejects_empty_query() {
	mut state := &SerpApiFixtureState{}
	http := SerpApiFixtureHTTP{
		state:    state
		response: '{"organic_results":[]}'
	}
	tool := new_default_test_tool(http)
	mut ctx := context.background()
	result := tool.call(mut ctx, 'V') or { panic(err) }
	assert result == no_results_message
	tool.call(mut ctx, ' ') or {
		assert err.msg().contains('must not be empty')
		return
	}
	assert false, 'expected empty query to fail'
}

fn test_serpapi_tool_rejects_provider_errors_without_body_leak() {
	mut state := &SerpApiFixtureState{}
	http := SerpApiFixtureHTTP{
		state:    state
		response: '{"error":"invalid api key secret"}'
	}
	tool := new_tool('test-key', 1, httputil.HTTPClient(http)) or { panic(err) }
	mut ctx := context.background()
	tool.call(mut ctx, 'V') or {
		assert err.msg() == 'SerpApi search failed'
		assert !err.msg().contains('secret')
		return
	}
	assert false, 'expected provider error to fail'
}

fn new_default_test_tool(http httputil.HTTPClient) Tool {
	return new_tool('fixture-key', 0, http) or { panic(err) }
}
