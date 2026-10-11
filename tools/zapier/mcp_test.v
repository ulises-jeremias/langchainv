module zapier

import context
import json2
import net.http
import ulises_jeremias.langchainv.httputil

@[heap]
struct ZapierMCPFixtureState {
mut:
	requests []httputil.Request
	use_sse  bool
}

struct ZapierMCPFixtureHTTP {
	state &ZapierMCPFixtureState
}

fn (client ZapierMCPFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	payload := json2.decode[map[string]json2.Any](request.body, json2.DecoderOptions{}) or {
		return error('invalid fixture request JSON')
	}
	method_value := payload['method'] or { return error('fixture request missing method') }
	if method_value !is string {
		return error('fixture method must be a string')
	}
	method := method_value as string
	if method == 'notifications/initialized' {
		return httputil.Response{
			status_code: 202
		}
	}
	match method {
		'initialize' {
			return json_response('{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"${mcp_protocol_version}","capabilities":{"tools":{}},"serverInfo":{"name":"Zapier MCP","version":"1"}}}')
		}
		'tools/list' {
			if client.state.use_sse {
				mut headers := http.Header{}
				headers.set_custom('Content-Type', 'text/event-stream') or { panic(err) }
				return httputil.Response{
					status_code: 200
					headers:     headers
					body:        'event: message\ndata: {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"send_message","description":"Send a message","inputSchema":{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}}]}}\n\n'
				}
			}
			return json_response('{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"send_message","description":"Send a message","inputSchema":{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}}]}}')
		}
		'tools/call' {
			return json_response('{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"Message sent."}]}}')
		}
		else {
			return error('unexpected MCP method ${method}')
		}
	}
}

fn test_zapier_mcp_lists_tools_and_calls_through_streamable_http() {
	mut state := &ZapierMCPFixtureState{
		use_sse: true
	}
	client := new_client(ClientOptions{
		endpoint:     'https://mcp.example.test/connect'
		access_token: 'fixture-token'
	}, httputil.HTTPClient(ZapierMCPFixtureHTTP{
		state: state
	})) or { panic(err) }
	mut ctx := context.background()
	infos := client.list_tools(mut ctx) or { panic(err) }
	assert infos.len == 1
	assert infos[0].name == 'send_message'
	assert infos[0].description == 'Send a message'
	tool := client.tool(infos[0])
	assert tool.spec().name == 'send_message'
	assert tool.spec().parameters is map[string]json2.Any
	result := tool.call(mut ctx, '{"text":"hello"}') or { panic(err) }
	assert result == 'Message sent.'
	assert state.requests.len == 4
	assert state.requests[0].headers['Authorization'] == 'Bearer fixture-token'
	assert state.requests[0].headers['MCP-Protocol-Version'] == ''
	assert state.requests[0].url == 'https://mcp.example.test/connect'
	assert state.requests[1].body.contains('notifications/initialized')
	assert state.requests[1].headers['MCP-Protocol-Version'] == mcp_protocol_version
	assert state.requests[2].body.contains('tools/list')
	assert state.requests[3].body.contains('tools/call')
	assert state.requests[3].body.contains('send_message')
	assert state.requests[3].body.contains('hello')
}

fn test_zapier_mcp_rejects_http_endpoints_and_non_json_tool_input() {
	new_client(ClientOptions{
		endpoint: 'http://mcp.example.test/connect'
	}, httputil.HTTPClient(ZapierMCPFixtureHTTP{
		state: &ZapierMCPFixtureState{}
	})) or {
		assert err.msg().contains('valid HTTPS URL')
		return
	}
	assert false, 'expected HTTP endpoint to fail'
	mut state := &ZapierMCPFixtureState{}
	client := new_client(ClientOptions{
		endpoint: 'https://mcp.example.test/connect'
	}, httputil.HTTPClient(ZapierMCPFixtureHTTP{
		state: state
	})) or { panic(err) }
	mut ctx := context.background()
	infos := client.list_tools(mut ctx) or { panic(err) }
	client.tool(infos[0]).call(mut ctx, 'not JSON') or {
		assert err.msg() == 'Zapier MCP tool input must be a JSON object'
		return
	}
	assert false, 'expected malformed tool input to fail'
}

fn json_response(body string) httputil.Response {
	return httputil.Response{
		status_code: 200
		body:        body
	}
}
