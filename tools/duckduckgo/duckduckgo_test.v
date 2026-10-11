module duckduckgo

import context
import ulises_jeremias.langchainv.httputil

const duckduckgo_fixture = '<div class="web-result"><a class="result__a" href="/l/?uddg=https%3A%2F%2Fexample.com%2Fv">V &amp; tools</a><a class="result__snippet">Compiler <b>language</b></a></div><div class="web-result"><a class="result__a" href="https://example.org">Second</a><a class="result__snippet">More</a></div>'

@[heap]
struct DuckDuckGoFixtureState {
mut:
	request httputil.Request
}

struct DuckDuckGoFixtureHTTP {
	state       &DuckDuckGoFixtureState
	response    string
	status_code int = 200
}

fn (client DuckDuckGoFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.request = request
	return httputil.Response{
		status_code: client.status_code
		body:        client.response
	}
}

fn test_duckduckgo_tool_encodes_query_and_formats_bounded_results() {
	mut state := &DuckDuckGoFixtureState{}
	http := DuckDuckGoFixtureHTTP{
		state:    state
		response: duckduckgo_fixture
	}
	tool := new_tool(1, 'fixture-agent', httputil.HTTPClient(http)) or { panic(err) }
	mut ctx := context.background()
	result := tool.call(mut ctx, '{"query":"V compiler"}') or { panic(err) }
	assert state.request.url == 'https://html.duckduckgo.com/html/?q=V+compiler'
	assert state.request.headers['User-Agent'] == 'fixture-agent'
	assert result == 'Title: V & tools\nDescription: Compiler language\nURL: https://example.com/v\n\n'
}

fn test_duckduckgo_tool_handles_empty_results_and_rejects_bad_queries() {
	mut state := &DuckDuckGoFixtureState{}
	http := DuckDuckGoFixtureHTTP{
		state:    state
		response: '<html><body>no matches</body></html>'
	}
	tool := new_tool(0, '', httputil.HTTPClient(http)) or { panic(err) }
	mut ctx := context.background()
	result := tool.call(mut ctx, 'a search') or { panic(err) }
	assert result == no_results_message
	tool.call(mut ctx, ' ') or {
		assert err.msg().contains('must not be empty')
		return
	}
	assert false, 'expected an empty query to fail'
}

fn test_duckduckgo_tool_rejects_non_success_status_without_body_leak() {
	mut state := &DuckDuckGoFixtureState{}
	http := DuckDuckGoFixtureHTTP{
		state:       state
		response:    'secret response body'
		status_code: 503
	}
	tool := new_tool(1, '', httputil.HTTPClient(http)) or { panic(err) }
	mut ctx := context.background()
	tool.call(mut ctx, 'a search') or {
		assert err.msg() == 'DuckDuckGo search returned HTTP 503'
		assert !err.msg().contains('secret response body')
		return
	}
	assert false, 'expected non-success status to fail'
}
