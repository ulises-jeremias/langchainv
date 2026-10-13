module vertex

import context
import net.http
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

struct FixtureHTTPClient {
	state &FixtureHTTPState
}

struct FixtureHTTPState {
mut:
	requests []httputil.Request
	response httputil.Response
}

fn (client FixtureHTTPClient) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	return state.response
}

fn (client FixtureHTTPClient) do_stream(mut ctx context.Context, request httputil.Request, handler httputil.StreamHandler) !httputil.Response {
	mut state := client.state
	state.requests << request
	handler(mut ctx, state.response.body.bytes())!
	return state.response
}

fn test_generate_content_routes_to_project_location_and_uses_bearer_auth() {
	mut state := &FixtureHTTPState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"candidates":[{"content":{"parts":[{"text":"hello"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":2,"candidatesTokenCount":1,"totalTokenCount":3}}'
		}
	}
	mut client := new_client(Options{
		project:      'sample-project'
		location:     'europe-west4'
		model:        'gemini-2.5-flash'
		access_token: 'oauth-token'
		endpoint:     'https://vertex.test'
	}, httputil.HTTPClient(FixtureHTTPClient{
		state: state
	})) or { panic(err) }
	mut ctx := context.background()
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'hello?')], llms.CallOptions{}) or {
		panic(err)
	}
	assert response.choices[0].content == 'hello'
	assert response.usage.total_tokens == 3
	assert state.requests.len == 1
	assert state.requests[0].url == 'https://vertex.test/v1/projects/sample-project/locations/europe-west4/publishers/google/models/gemini-2.5-flash:generateContent'
	assert state.requests[0].headers['Authorization'] == 'Bearer oauth-token'
	assert 'x-goog-api-key' !in state.requests[0].headers
	assert !state.requests[0].url.contains('oauth-token')
}

fn test_new_client_requires_explicit_valid_configuration() {
	mut state := &FixtureHTTPState{}
	new_client(Options{
		project:      '../other-project'
		access_token: 'oauth-token'
	}, httputil.HTTPClient(FixtureHTTPClient{
		state: state
	})) or {
		assert err.msg().contains('project')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected invalid project path to be rejected'
}

fn test_streaming_preserves_vertex_route_query_and_bearer_auth() {
	mut state := &FixtureHTTPState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        'data: {"candidates":[{"content":{"parts":[{"text":"streamed"}]},"finishReason":"STOP"}]}\n\n'
		}
	}
	mut client := new_client(Options{
		project:      'sample-project'
		access_token: 'oauth-token'
	}, httputil.HTTPClient(FixtureHTTPClient{
		state: state
	})) or { panic(err) }
	mut ctx := context.background()
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'hello')], llms.CallOptions{
		streaming_func: llms.StreamFunc(fn (mut _ context.Context, _ []u8) ! {})
	}) or { panic(err) }
	assert response.choices[0].content == 'streamed'
	assert state.requests[0].url == 'https://aiplatform.googleapis.com/v1/projects/sample-project/locations/us-central1/publishers/google/models/gemini-2.5-flash:streamGenerateContent?alt=sse'
	assert state.requests[0].headers['Authorization'] == 'Bearer oauth-token'
}

fn test_new_client_rejects_missing_token_and_non_https_endpoint() {
	mut state := &FixtureHTTPState{}
	new_client(Options{
		project: 'sample-project'
	}, httputil.HTTPClient(FixtureHTTPClient{
		state: state
	})) or {
		assert err.msg().contains('access token')
		return
	}
	new_client(Options{
		project:      'sample-project'
		access_token: 'oauth-token'
		endpoint:     'http://vertex.test'
	}, httputil.HTTPClient(FixtureHTTPClient{
		state: state
	})) or {
		assert err.msg().contains('HTTPS')
		return
	}
	assert false, 'expected invalid Vertex AI endpoint to be rejected'
}

fn test_count_tokens_routes_to_vertex_model() {
	mut state := &FixtureHTTPState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"totalTokens":13}'
		}
	}
	mut client := new_client(Options{
		project:      'sample-project'
		location:     'europe-west4'
		model:        'gemini-2.5-flash'
		access_token: 'oauth-token'
		endpoint:     'https://vertex.test'
	}, httputil.HTTPClient(FixtureHTTPClient{
		state: state
	})) or { panic(err) }
	mut ctx := context.background()
	count := client.count_tokens(mut ctx, [schema.text_message(.human, 'hello')], '') or { panic(err) }
	assert count == 13
	assert state.requests.len == 1
	assert state.requests[0].url == 'https://vertex.test/v1/projects/sample-project/locations/europe-west4/publishers/google/models/gemini-2.5-flash:countTokens'
	assert state.requests[0].headers['Authorization'].starts_with('Bearer ')
	assert 'x-goog-api-key' !in state.requests[0].headers
}
