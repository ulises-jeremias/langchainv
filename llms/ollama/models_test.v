module ollama

import context
import net.http
import ulises_jeremias.langchainv.httputil

@[heap]
struct ModelsFakeState {
mut:
	requests []httputil.Request
	response httputil.Response
}

struct ModelsFakeClient {
	state &ModelsFakeState
}

fn (client ModelsFakeClient) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	return state.response
}

fn new_models_client(body string, status int) (Client, &ModelsFakeState) {
	mut state := &ModelsFakeState{
		response: httputil.Response{
			status_code: status
			headers:     http.Header{}
			body:        body
		}
	}
	client := new_client(ModelsFakeClient{
		state: state
	}, Options{
		base_url: 'http://ollama.test:11434'
		model:    'gemma4'
	}) or { panic(err) }
	return client, state
}

fn test_list_models_maps_tags_response() {
	mut ctx := context.background()
	client, state := new_models_client('{"models":[{"name":"gemma4:latest","size":4300000000,"digest":"abc123","modified_at":"2026-01-01T00:00:00Z","details":{"family":"gemma3","parameter_size":"4.3B","quantization_level":"Q4_K_M"}}]}', 200)
	models := client.list_models(mut ctx) or { panic(err) }
	assert models.len == 1
	assert models[0].name == 'gemma4:latest'
	assert models[0].size == 4300000000
	assert models[0].digest == 'abc123'
	assert models[0].family == 'gemma3'
	assert models[0].parameter_size == '4.3B'
	assert models[0].quantization_level == 'Q4_K_M'
	assert state.requests[0].method == http.Method.get
	assert state.requests[0].url == 'http://ollama.test:11434/api/tags'
}

fn test_pull_and_delete_model_use_model_endpoints() {
	mut ctx := context.background()
	client, state := new_models_client('{"status":"success"}', 200)
	client.pull_model(mut ctx, 'gemma4:latest') or { panic(err) }
	assert state.requests[0].method == http.Method.post
	assert state.requests[0].url == 'http://ollama.test:11434/api/pull'
	assert state.requests[0].body.contains('"name":"gemma4:latest"')
	assert state.requests[0].body.contains('"stream":false')

	mut delete_state := &ModelsFakeState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
		}
	}
	delete_client := new_client(ModelsFakeClient{
		state: delete_state
	}, Options{
		base_url: 'http://ollama.test:11434'
		model:    'gemma4'
	}) or { panic(err) }
	delete_client.delete_model(mut ctx, 'gemma4:latest') or { panic(err) }
	assert delete_state.requests[0].method == http.Method.delete
	assert delete_state.requests[0].url == 'http://ollama.test:11434/api/delete'
	assert delete_state.requests[0].body.contains('"name":"gemma4:latest"')
}

fn test_show_model_maps_details() {
	mut ctx := context.background()
	client, state := new_models_client('{"details":{"family":"gemma3","parameter_size":"4.3B","quantization_level":"Q4_K_M"},"size":4300000000}', 200)
	info := client.show_model(mut ctx, 'gemma4:latest') or { panic(err) }
	assert info.name == 'gemma4:latest'
	assert info.family == 'gemma3'
	assert info.parameter_size == '4.3B'
	assert state.requests[0].url == 'http://ollama.test:11434/api/show'
}

fn test_model_management_rejects_invalid_names_before_network() {
	mut ctx := context.background()
	client, state := new_models_client('{}', 200)
	client.pull_model(mut ctx, '  ') or {
		assert err.msg().contains('model name')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected an empty model name to fail'
}

fn test_model_management_hides_http_error_body() {
	mut ctx := context.background()
	client, _ := new_models_client('secret failure body', 404)
	client.list_models(mut ctx) or {
		assert err.msg().contains('HTTP 404')
		assert !err.msg().contains('secret failure body')
		return
	}
	assert false, 'expected the HTTP error to fail'
}
