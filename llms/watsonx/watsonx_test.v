module watsonx

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
	requests     []httputil.Request
	response     httputil.Response
	iam_response httputil.Response
}

fn (client FixtureHTTPClient) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	if request.url == default_iam_url {
		return state.iam_response
	}
	return state.response
}

fn new_fixture_client(body string, status int) (Client, &FixtureHTTPState) {
	mut state := &FixtureHTTPState{
		response: httputil.Response{
			status_code: status
			headers:     http.Header{}
			body:        body
		}
	}
	client := new_client(Options{
		project_id:   'project-123'
		model:        'ibm/granite-3-8b-instruct'
		access_token: 'iam-access-token'
		base_url:     'https://watsonx.test'
	}, httputil.HTTPClient(FixtureHTTPClient{
		state: state
	})) or { panic(err) }
	return client, state
}

fn test_generate_content_maps_text_usage_and_generation_options() {
	mut ctx := context.background()
	mut client, state := new_fixture_client('{"results":[{"generated_text":"answer","generated_token_count":4,"input_token_count":9,"stop_reason":"EOS_TOKEN"}]}', 200)
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'question')], llms.CallOptions{
		max_tokens:         30
		temperature:        0.8
		top_p:              0.7
		top_k:              40
		repetition_penalty: 1.1
		seed:               12
		stop_words:         ['END']
	}) or { panic(err) }
	assert response.choices[0].content == 'answer'
	assert response.choices[0].stop_reason == 'EOS_TOKEN'
	assert response.usage.prompt_tokens == 9
	assert response.usage.completion_tokens == 4
	assert response.usage.total_tokens == 13
	assert state.requests.len == 1
	assert state.requests[0].url == 'https://watsonx.test/ml/v1/text/generation?version=2024-05-20'
	assert state.requests[0].headers['Authorization'] == 'Bearer iam-access-token'
	assert state.requests[0].body.contains('"project_id":"project-123"')
	assert state.requests[0].body.contains('"model_id":"ibm/granite-3-8b-instruct"')
	assert state.requests[0].body.contains('"max_new_tokens":30')
	assert state.requests[0].body.contains('"random_seed":12')
	assert state.requests[0].body.contains('"stop_sequences":["END"]')
	assert !state.requests[0].url.contains('iam-access-token')
}

fn test_generate_content_rejects_unsupported_input_before_network() {
	mut ctx := context.background()
	mut client, state := new_fixture_client('{}', 200)
	client.generate_content(mut ctx, [schema.text_message(.system, 'instruction'), schema.text_message(.human,
		'question')], llms.CallOptions{}) or {
		assert err.msg().contains('exactly one human text message')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected multi-message input to be rejected'
}

fn test_generate_content_requires_a_streaming_transport() {
	mut ctx := context.background()
	mut client, state := new_fixture_client('{}', 200)
	client.generate_content(mut ctx, [schema.text_message(.human, 'question')], llms.CallOptions{
		streaming_func: llms.StreamFunc(fn (mut _ context.Context, _ []u8) ! {})
	}) or {
		assert err.msg().contains('unsupported')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected a streaming transport to be required'
}

fn test_generate_content_hides_provider_error_body_and_requires_results() {
	mut ctx := context.background()
	mut client, _ := new_fixture_client('private provider detail', 403)
	client.generate_content(mut ctx, [schema.text_message(.human, 'question')], llms.CallOptions{}) or {
		assert err.msg().contains('HTTP 403')
		assert !err.msg().contains('private provider detail')
		return
	}
	assert false, 'expected HTTP error to fail'
}

fn test_generate_content_requires_results() {
	mut ctx := context.background()
	mut empty_client, _ := new_fixture_client('{"results":[]}', 200)
	empty_client.generate_content(mut ctx, [schema.text_message(.human, 'question')], llms.CallOptions{}) or {
		assert err.msg().contains('no generation results')
		return
	}
	assert false, 'expected an empty result list to fail'
}

fn test_api_key_exchanges_and_caches_iam_token() {
	mut state := &FixtureHTTPState{
		response:     httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"results":[{"generated_text":"answer"}]}'
		}
		iam_response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"access_token":"cached-iam-token","expiration":2000000000}'
		}
	}
	mut client := new_client(Options{
		project_id: 'project-123'
		model:      'ibm/granite-3-8b-instruct'
		api_key:    'key+/with=reserved'
	}, httputil.HTTPClient(FixtureHTTPClient{
		state: state
	})) or { panic(err) }
	mut ctx := context.background()
	for _ in 0 .. 2 {
		assert client.complete(mut ctx, 'question', llms.CallOptions{}) or { panic(err) } == 'answer'
	}
	assert state.requests.len == 3
	assert state.requests[0].url == default_iam_url
	assert state.requests[0].headers['Content-Type'] == 'application/x-www-form-urlencoded'
	assert state.requests[0].body.contains('grant_type=urn%3Aibm%3Aparams%3Aoauth%3Agrant-type%3Aapikey')
	assert state.requests[0].body.contains('apikey=key%2B%2Fwith%3Dreserved')
	assert state.requests[1].headers['Authorization'] == 'Bearer cached-iam-token'
	assert state.requests[2].headers['Authorization'] == 'Bearer cached-iam-token'
}

fn test_new_client_rejects_invalid_credentials_and_urls() {
	mut state := &FixtureHTTPState{}
	new_client(Options{
		project_id: 'project-123'
		model:      'ibm/granite-3-8b-instruct'
	}, httputil.HTTPClient(FixtureHTTPClient{
		state: state
	})) or {
		assert err.msg().contains('exactly one')
		return
	}
	new_client(Options{
		project_id:   'project-123'
		model:        'ibm/granite-3-8b-instruct'
		access_token: 'token'
		base_url:     'http://watsonx.test'
	}, httputil.HTTPClient(FixtureHTTPClient{
		state: state
	})) or {
		assert err.msg().contains('HTTPS')
		return
	}
	assert false, 'expected invalid watsonx configuration to fail'
}
