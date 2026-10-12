module documentloaders

import context
import ulises_jeremias.langchainv.httputil

const assemblyai_test_id = '59833787-2cf9-4fdf-8782-e53db20768a5'

@[heap]
struct AssemblyAIFixtureState {
mut:
	requests []httputil.Request
}

struct AssemblyAIFixtureHTTP {
	state     &AssemblyAIFixtureState
	responses []string
}

fn (client AssemblyAIFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	index := state.requests.len - 1
	if index >= client.responses.len {
		return error('unexpected AssemblyAI fixture request')
	}
	return httputil.Response{
		status_code: 200
		body:        client.responses[index]
	}
}

fn test_assemblyai_loader_submits_and_polls_with_raw_api_key() {
	mut state := &AssemblyAIFixtureState{}
	http := AssemblyAIFixtureHTTP{
		state:     state
		responses: [
			'{"id":"${assemblyai_test_id}","status":"queued"}',
			'{"id":"${assemblyai_test_id}","status":"completed","text":"Transcript text."}',
		]
	}
	loader := new_assemblyai_loader('https://cdn.example/audio.mp3', 'integration-secret',
		httputil.HTTPClient(http), AssemblyAILoaderOptions{
			max_poll_requests: 2
			poll_interval_ms:  1
		}) or { panic(err) }
	mut ctx := context.background()
	documents := loader.load(mut ctx) or { panic(err) }
	assert documents.len == 1
	assert documents[0].page_content == 'Transcript text.'
	assert documents[0].metadata['transcript_id'] or { panic('missing transcript id') }.str() == assemblyai_test_id
	assert state.requests.len == 2
	assert state.requests[0].method == .post
	assert state.requests[0].url == '${assemblyai_api_base_url}/transcript'
	assert state.requests[0].headers['Authorization'] == 'integration-secret'
	assert state.requests[0].body.contains('"audio_url":"https://cdn.example/audio.mp3"')
	assert state.requests[1].url == '${assemblyai_api_base_url}/transcript/${assemblyai_test_id}'
	assert state.requests[1].headers['Authorization'] == 'integration-secret'
}

fn test_assemblyai_loader_rejects_unsafe_audio_urls_and_invalid_options() {
	new_assemblyai_loader('http://cdn.example/audio.mp3', 'test-key', httputil.HTTPClient(AssemblyAIErrorFixtureHTTP{}),
		AssemblyAILoaderOptions{}) or {
		assert err.msg() == 'AssemblyAI audio URL must be a valid HTTPS URL'
		return
	}
	assert false, 'expected non-HTTPS audio URL to fail'
	new_assemblyai_loader('https://cdn.example/audio.mp3', 'test-key', httputil.HTTPClient(AssemblyAIErrorFixtureHTTP{}),
		AssemblyAILoaderOptions{
			max_poll_requests: 1001
		}) or {
		assert err.msg() == 'AssemblyAI maximum poll requests must be between 1 and 1000'
		return
	}
	assert false, 'expected invalid polling bound to fail'
}

fn test_assemblyai_loader_redacts_http_error_body() {
	loader := new_assemblyai_loader('https://cdn.example/audio.mp3', 'credential-secret',
		httputil.HTTPClient(AssemblyAIErrorFixtureHTTP{}), AssemblyAILoaderOptions{}) or { panic(err) }
	mut ctx := context.background()
	loader.load(mut ctx) or {
		assert err.msg() == 'AssemblyAI submission returned HTTP 401'
		assert !err.msg().contains('credential-secret')
		return
	}
	assert false, 'expected failed AssemblyAI request'
}

struct AssemblyAIErrorFixtureHTTP {}

fn (client AssemblyAIErrorFixtureHTTP) do(mut _ctx context.Context, _request httputil.Request) !httputil.Response {
	return httputil.Response{
		status_code: 401
		body:        'credential-secret rejected'
	}
}
