module perplexity

import context
import ulises_jeremias.langchainv.httputil

@[heap]
struct PerplexityFixtureState {
mut:
	requests []httputil.Request
}

struct PerplexityFixtureHTTP {
	state &PerplexityFixtureState
}

fn (client PerplexityFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	return httputil.Response{
		status_code: 200
		body:        '{"choices":[{"message":{"role":"assistant","content":"Grounded answer"}}],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}'
	}
}

fn test_perplexity_tool_sends_bounded_query_to_configured_endpoint() {
	mut state := &PerplexityFixtureState{}
	tool := new_tool('test-key', httputil.HTTPClient(PerplexityFixtureHTTP{
		state: state
	}), model_sonar_reasoning) or { panic(err) }
	mut ctx := context.background()
	answer := tool.call(mut ctx, '{"query":"latest V release"}') or { panic(err) }
	assert answer == 'Grounded answer'
	assert state.requests.len == 1
	request := state.requests[0]
	assert request.url == 'https://api.perplexity.ai/chat/completions'
	assert request.headers['Authorization'] == 'Bearer test-key'
	assert request.body.contains('"model":"sonar-reasoning"')
	assert request.body.contains('"content":"latest V release"')
}

fn test_perplexity_tool_rejects_empty_queries_before_http() {
	mut state := &PerplexityFixtureState{}
	tool := new_tool('test-key', httputil.HTTPClient(PerplexityFixtureHTTP{
		state: state
	}), '') or { panic(err) }
	mut ctx := context.background()
	tool.call(mut ctx, '   ') or {
		assert err.msg().contains('must not be empty')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected an empty query to fail'
	assert state.requests.len == 0
}

fn test_perplexity_tool_rejects_oversized_queries_before_http() {
	mut state := &PerplexityFixtureState{}
	tool := new_tool('test-key', httputil.HTTPClient(PerplexityFixtureHTTP{
		state: state
	}), '') or { panic(err) }
	mut ctx := context.background()
	tool.call(mut ctx, 'q'.repeat(max_query_bytes + 1)) or {
		assert err.msg().contains('exceeds')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected an oversized query to fail'
	assert state.requests.len == 0
}

fn test_perplexity_tool_spec_describes_required_query() {
	mut state := &PerplexityFixtureState{}
	tool := new_tool('test-key', httputil.HTTPClient(PerplexityFixtureHTTP{
		state: state
	}), '') or { panic(err) }
	spec := tool.spec()
	assert spec.name == 'PerplexityAI'
	assert spec.description.contains('Perplexity AI')
	assert spec.parameters.str().contains('"query"')
}
