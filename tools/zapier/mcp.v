// Package zapier connects LangChainV tools to Zapier's current MCP service.
module zapier

import context
import json2
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.tools

const default_zapier_mcp_endpoint = 'https://mcp.zapier.com/api/v1/connect'
const mcp_protocol_version = '2025-03-26'
const max_mcp_response_bytes = i64(2 * 1024 * 1024)
const max_mcp_tool_input_bytes = 1024 * 1024
const max_mcp_tool_count = 256
const max_mcp_tool_name_bytes = 256
const max_mcp_access_token_bytes = 16 * 1024

// ClientOptions configures a remote Zapier MCP Streamable HTTP endpoint.
pub struct ClientOptions {
pub:
	endpoint     string
	access_token string
}

// Client keeps one bounded, injectable connection to a remote MCP endpoint.
pub struct Client {
pub:
	endpoint string
mut:
	access_token string
	http_client  httputil.HTTPClient
	state        &MCPState
}

@[heap]
struct MCPState {
mut:
	initialized bool
	session_id  string
	next_id     int = 1
}

// ToolInfo describes one server-provided tool and its JSON input schema.
pub struct ToolInfo {
pub:
	name         string
	description  string
	input_schema json2.Any
}

// Tool adapts one Zapier MCP tool to the shared LangChainV tool contract.
pub struct Tool {
pub:
	info ToolInfo
mut:
	client Client
}

// new_client constructs a client with an explicit HTTPS endpoint and transport.
pub fn new_client(options ClientOptions, http_client httputil.HTTPClient) !Client {
	endpoint := if options.endpoint.trim_space() == '' {
		default_zapier_mcp_endpoint
	} else {
		options.endpoint.trim_space()
	}
	if endpoint.len > 4096 {
		return error('Zapier MCP endpoint exceeds 4096 bytes')
	}
	if options.access_token.len > max_mcp_access_token_bytes {
		return error('Zapier MCP access token exceeds 16 KiB')
	}
	httputil.validate_url(endpoint, 'https') or {
		return error('Zapier MCP endpoint must be a valid HTTPS URL without user information')
	}
	return Client{
		endpoint:     endpoint
		access_token: options.access_token.trim_space()
		http_client:  http_client
		state:        &MCPState{}
	}
}

// new_default_client connects to Zapier's hosted MCP endpoint.
pub fn new_default_client(access_token string, http_client httputil.HTTPClient) !Client {
	return new_client(ClientOptions{
		endpoint:     default_zapier_mcp_endpoint
		access_token: access_token
	}, http_client)
}

// list_tools initializes the streamable client and returns the server tools.
pub fn (client Client) list_tools(mut ctx context.Context) ![]ToolInfo {
	client.initialize(mut ctx)!
	response := client.request(mut ctx, 'tools/list', json2.Any(map[string]json2.Any{}))!
	result := mcp_result(response)!
	tools_value := result['tools'] or { return error('Zapier MCP tools/list response is missing tools') }
	if tools_value !is []json2.Any {
		return error('Zapier MCP tools/list response has an invalid tools field')
	}
	tools_list := tools_value as []json2.Any
	if tools_list.len > max_mcp_tool_count {
		return error('Zapier MCP returned more than ${max_mcp_tool_count} tools')
	}
	mut infos := []ToolInfo{}
	for tool_value in tools_list {
		if tool_value !is map[string]json2.Any {
			continue
		}
		tool_map := tool_value as map[string]json2.Any
		name := mcp_string(tool_map, 'name')
		if name == '' || name.len > max_mcp_tool_name_bytes {
			continue
		}
		description := mcp_string(tool_map, 'description')
		input_schema := tool_map['inputSchema'] or {
			json2.Any({
				'type': json2.Any('object')
			})
		}
		infos << ToolInfo{
			name:         name
			description:  description
			input_schema: input_schema
		}
	}
	return infos
}

// tool adapts a server-provided tool to the common tool interface.
pub fn (client Client) tool(info ToolInfo) Tool {
	return Tool{
		info:   info
		client: client
	}
}

// spec exposes the server's name, description, and input schema to agents.
pub fn (tool Tool) spec() tools.ToolSpec {
	return tools.ToolSpec{
		name:        tool.info.name
		description: tool.info.description
		parameters:  tool.info.input_schema
	}
}

// call invokes the named remote tool with JSON object arguments.
pub fn (tool Tool) call(mut ctx context.Context, input string) !string {
	if i64(input.len) > max_mcp_tool_input_bytes {
		return error('Zapier MCP tool input exceeds the 1 MiB limit')
	}
	mut tool_arguments := map[string]json2.Any{}
	if input.trim_space() != '' {
		tool_arguments = json2.decode[map[string]json2.Any](input, json2.DecoderOptions{}) or {
			return error('Zapier MCP tool input must be a JSON object')
		}
	}
	mut params := map[string]json2.Any{}
	params['name'] = json2.Any(tool.info.name)
	params['arguments'] = json2.Any(tool_arguments)
	response := tool.client.request(mut ctx, 'tools/call', json2.Any(params))!
	result := mcp_result(response)!
	if mcp_bool(result, 'isError') {
		return error('Zapier MCP tool returned an error')
	}
	return format_tool_result(result)
}

fn (client Client) initialize(mut ctx context.Context) ! {
	mut state := client.state
	if state.initialized {
		return
	}
	mut params := map[string]json2.Any{}
	params['protocolVersion'] = json2.Any(mcp_protocol_version)
	params['capabilities'] = json2.Any(map[string]json2.Any{})
	params['clientInfo'] = json2.Any({
		'name':    json2.Any('langchainv')
		'version': json2.Any('0.1.0')
	})
	response := client.request(mut ctx, 'initialize', json2.Any(params))!
	result := mcp_result(response)!
	protocol_value := result['protocolVersion'] or {
		return error('Zapier MCP initialize response is missing protocolVersion')
	}
	if protocol_value !is string || (protocol_value as string) != mcp_protocol_version {
		return error('Zapier MCP server selected an unsupported protocol version')
	}
	client.notification(mut ctx, 'notifications/initialized')!
	state.initialized = true
}

fn (client Client) request(mut ctx context.Context, method string, params json2.Any) !map[string]json2.Any {
	mut state := client.state
	request_id := state.next_id
	state.next_id++
	mut payload := map[string]json2.Any{}
	payload['jsonrpc'] = json2.Any('2.0')
	payload['id'] = json2.Any(request_id)
	payload['method'] = json2.Any(method)
	payload['params'] = params
	response := client.send(mut ctx, json2.encode(payload, json2.EncoderOptions{}))!
	decoded := json2.decode[map[string]json2.Any](response.body, json2.DecoderOptions{}) or {
		return error('Zapier MCP returned an invalid JSON-RPC response')
	}
	response_id := decoded['id'] or { return error('Zapier MCP response is missing id') }
	if response_id != json2.Any(request_id) {
		return error('Zapier MCP response id does not match the request')
	}
	return decoded
}

fn (client Client) notification(mut ctx context.Context, method string) ! {
	mut payload := map[string]json2.Any{}
	payload['jsonrpc'] = json2.Any('2.0')
	payload['method'] = json2.Any(method)
	response := client.send(mut ctx, json2.encode(payload, json2.EncoderOptions{}))!
	if response.status_code != 202 && (response.status_code < 200 || response.status_code >= 300) {
		return error('Zapier MCP initialization notification returned HTTP ${response.status_code}')
	}
}

fn (client Client) send(mut ctx context.Context, body string) !httputil.Response {
	mut headers := {
		'Accept':       'application/json, text/event-stream'
		'Content-Type': 'application/json'
	}
	if client.state.initialized {
		headers['MCP-Protocol-Version'] = mcp_protocol_version
	}
	if client.access_token != '' {
		headers['Authorization'] = 'Bearer ${client.access_token}'
	}
	if client.state.session_id != '' {
		headers['Mcp-Session-Id'] = client.state.session_id
	}
	response := client.http_client.do(mut ctx, httputil.Request{
		method:  .post
		url:     client.endpoint
		headers: headers
		body:    body
	})!
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Zapier MCP request returned HTTP ${response.status_code}')
	}
	if i64(response.body.len) > max_mcp_response_bytes {
		return error('Zapier MCP response exceeds the 2 MiB limit')
	}
	if session_id := response.headers.get_custom('Mcp-Session-Id') {
		mut state := client.state
		state.session_id = session_id
	}
	content_type := response.headers.get_custom('Content-Type') or { '' }
	if content_type.starts_with('text/event-stream') {
		mut event_json := ''
		for line in response.body.split_into_lines() {
			if line.starts_with('data:') {
				data := line[5..].trim_space()
				if data != '' && data != '[DONE]' {
					event_json = data
				}
			}
		}
		if event_json == '' {
			return error('Zapier MCP SSE response has no JSON-RPC data event')
		}
		return httputil.Response{
			status_code: response.status_code
			headers:     response.headers
			body:        event_json
		}
	}
	return response
}

fn mcp_result(response map[string]json2.Any) !map[string]json2.Any {
	if response_error := response['error'] {
		if response_error is map[string]json2.Any {
			return error('Zapier MCP returned a JSON-RPC error')
		}
	}
	result := response['result'] or { return error('Zapier MCP response is missing result') }
	if result !is map[string]json2.Any {
		return error('Zapier MCP response has an invalid result')
	}
	return result as map[string]json2.Any
}

fn mcp_string(values map[string]json2.Any, key string) string {
	value := values[key] or { return '' }
	if value is string {
		return value as string
	}
	return ''
}

fn mcp_bool(values map[string]json2.Any, key string) bool {
	value := values[key] or { return false }
	if value is bool {
		return value as bool
	}
	return false
}

fn format_tool_result(result map[string]json2.Any) !string {
	content_value := result['content'] or { return '' }
	if content_value !is []json2.Any {
		return error('Zapier MCP tool response has an invalid content field')
	}
	mut parts := []string{}
	for item_value in content_value as []json2.Any {
		if item_value !is map[string]json2.Any {
			continue
		}
		item := item_value as map[string]json2.Any
		if mcp_string(item, 'type') == 'text' {
			text := mcp_string(item, 'text')
			if text != '' {
				parts << text
			}
		}
	}
	return parts.join('\n')
}
