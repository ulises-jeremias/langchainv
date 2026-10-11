module wikipedia

import context
import json2
import ulises_jeremias.langchainv.httputil

@[heap]
struct WikipediaFixtureState {
mut:
	request httputil.Request
}

struct WikipediaFixtureHTTP {
	state       &WikipediaFixtureState
	response    string
	status_code int = 200
}

fn (client WikipediaFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.request = request
	return httputil.Response{
		status_code: client.status_code
		body:        client.response
	}
}

fn test_wikipedia_tool_encodes_query_and_formats_plain_text_results() {
	wikipedia_response := '{"pages":[{"id":1,"key":"V_language","title":"V (programming language)","excerpt":"<span class=\"searchmatch\">V</span> is a compiled programming language."}]}'
	json2.decode[map[string]json2.Any](wikipedia_response, json2.DecoderOptions{}) or {
		panic('Wikipedia fixture JSON did not decode: ${err.msg()}')
	}
	mut state := &WikipediaFixtureState{}
	http := WikipediaFixtureHTTP{
		state:    state
		response: wikipedia_response
	}
	tool := new_tool(1, 'en', httputil.HTTPClient(http)) or { panic(err) }
	mut ctx := context.background()
	result := tool.call(mut ctx, '{"query":"V language"}') or { panic(err) }
	assert state.request.url == 'https://en.wikipedia.org/w/rest.php/v1/search/page?q=V+language&limit=1'
	assert state.request.headers['Accept'] == 'application/json'
	assert result == 'Title: V (programming language)\nDescription: V is a compiled programming language.\n\n'
}

fn test_wikipedia_tool_returns_empty_search_message_and_validates_input() {
	mut state := &WikipediaFixtureState{}
	http := WikipediaFixtureHTTP{
		state:    state
		response: '{"pages":[]}'
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

fn test_wikipedia_tool_rejects_non_success_status_without_body_leak() {
	mut state := &WikipediaFixtureState{}
	http := WikipediaFixtureHTTP{
		state:       state
		response:    'private response body'
		status_code: 429
	}
	tool := new_tool(1, 'en', httputil.HTTPClient(http)) or { panic(err) }
	mut ctx := context.background()
	tool.call(mut ctx, 'V') or {
		assert err.msg() == 'Wikipedia search returned HTTP 429'
		assert !err.msg().contains('private response body')
		return
	}
	assert false, 'expected non-success status to fail'
}

fn new_default_test_tool(http httputil.HTTPClient) Tool {
	return new_tool(0, '', http) or { panic(err) }
}
