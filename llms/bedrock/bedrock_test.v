module bedrock

import context
import net.http
import json2
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

@[heap]
struct BedrockFixtureState {
mut:
	requests []httputil.Request
	response httputil.Response
}

struct BedrockFixtureHTTP {
	state &BedrockFixtureState
}

fn (client BedrockFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	return state.response
}

fn new_bedrock_fixture(body string) (Client, &BedrockFixtureState) {
	mut state := &BedrockFixtureState{
		response: httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        body
		}
	}
	client := new_client('fixture-bedrock-key', httputil.HTTPClient(BedrockFixtureHTTP{
		state: state
	})) or { panic(err) }
	return client, state
}

fn test_converse_text_request_and_usage_mapping() {
	mut ctx := context.background()
	client, state := new_bedrock_fixture('{"output":{"message":{"role":"assistant","content":[{"text":"hello"}]}},"stopReason":"end_turn","usage":{"inputTokens":4,"outputTokens":2,"totalTokens":6}}')
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		max_tokens:  64
		temperature: 0.4
		top_p:       0.9
		stop_words:  ['END']
	}) or { panic(err) }
	assert response.choices.len == 1
	assert response.choices[0].content == 'hello'
	assert response.choices[0].stop_reason == 'end_turn'
	assert response.usage.prompt_tokens == 4
	assert response.usage.completion_tokens == 2
	assert response.usage.total_tokens == 6
	assert state.requests.len == 1
	assert state.requests[0].url == 'https://bedrock-runtime.us-east-1.amazonaws.com/model/${default_model}/converse'
	assert (state.requests[0].headers['Authorization'] or { '' }) == 'Bearer fixture-bedrock-key'
	assert state.requests[0].body.contains('"maxTokens":64')
	assert state.requests[0].body.contains('"temperature":0.4')
	assert state.requests[0].body.contains('"topP":0.9')
	assert state.requests[0].body.contains('"stopSequences"')
	assert state.requests[0].body.contains('"role":"user"')
}

fn test_converse_maps_tool_use_and_schema() {
	mut ctx := context.background()
	client, state := new_bedrock_fixture('{"output":{"message":{"role":"assistant","content":[{"toolUse":{"toolUseId":"tool-1","name":"lookup","input":{"q":"v"}}}]}},"stopReason":"tool_use"}')
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'lookup')], llms.CallOptions{
		tools:       [schema.ToolDefinition{
			name:       'lookup'
			parameters: json2.Any(map[string]json2.Any{
				'type': json2.Any('object')
			})
		}]
		tool_choice: schema.ToolChoice{
			mode: 'required'
		}
	}) or { panic(err) }
	assert response.choices[0].tool_calls.len == 1
	assert response.choices[0].tool_calls[0].id == 'tool-1'
	assert response.choices[0].tool_calls[0].function_call.name == 'lookup'
	assert response.choices[0].tool_calls[0].function_call.arguments.contains('"q":"v"')
	assert state.requests[0].body.contains('"toolChoice"')
	assert state.requests[0].body.contains('"any"')
	assert state.requests[0].body.contains('"inputSchema"')
}

fn test_converse_replays_tool_result_and_rejects_unsupported_options() {
	call := schema.ToolCall{
		id:            'tool-1'
		call_type:     'function'
		function_call: schema.FunctionCall{
			name:      'lookup'
			arguments: '{"q":"v"}'
		}
	}
	messages := [
		schema.Message{
			role:  .ai
			parts: [schema.ContentPart(call)]
		},
		schema.Message{
			role:  .tool
			parts: [schema.ContentPart(schema.ToolResult{
				call_id: 'tool-1'
				content: 'found'
			})]
		},
	]
	request := make_request(messages, llms.CallOptions{}) or { panic(err) }
	assert json2.encode(request, json2.EncoderOptions{}).contains('"toolUseId":"tool-1"')
	mut ctx := context.background()
	client, state := new_bedrock_fixture('{}')
	client.generate_content(mut ctx, [schema.text_message(.human, 'hi')], llms.CallOptions{
		top_k: 4
	}) or {
		assert err.msg().contains('generation options')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected unsupported top_k rejection'
}

fn test_client_rejects_empty_key() {
	new_client_with_options('', httputil.HTTPClient(BedrockFixtureHTTP{
		state: &BedrockFixtureState{}
	}), Options{}) or {
		assert err.msg().contains('API key')
		return
	}
	assert false, 'expected empty API key rejection'
}

fn test_client_rejects_invalid_model_id() {
	new_client_with_options('key', httputil.HTTPClient(BedrockFixtureHTTP{
		state: &BedrockFixtureState{}
	}), Options{
		model_id: 'model/with/path'
	}) or {
		assert err.msg().contains('model ID is invalid')
		return
	}
	assert false, 'expected invalid model ID rejection'
}

fn test_client_rejects_invalid_region() {
	new_client_with_options('key', httputil.HTTPClient(BedrockFixtureHTTP{
		state: &BedrockFixtureState{}
	}), Options{
		region: 'bad region'
	}) or {
		assert err.msg().contains('region is invalid')
		return
	}
	assert false, 'expected invalid region rejection'
}
