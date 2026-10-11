// Package duckduckgo implements bounded HTML DuckDuckGo search.
module duckduckgo

import context
import encoding.html as html_entities
import json2
import net.html
import net.urllib
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.tools

const default_user_agent = 'github.com/ulises-jeremias/langchainv/tools/duckduckgo'
const default_max_results = 1
const max_results_limit = 30
const max_query_bytes = 4096
const max_response_bytes = i64(2 * 1024 * 1024)
const no_results_message = 'No good DuckDuckGo Search Results was found'

// Tool performs a bounded search against DuckDuckGo's HTML endpoint.
pub struct Tool {
pub:
	max_results int
	user_agent  string
mut:
	http_client httputil.HTTPClient
}

// new_tool constructs a DuckDuckGo tool with an injectable transport.
pub fn new_tool(max_results int, user_agent string, http_client httputil.HTTPClient) !Tool {
	if max_results < 0 || max_results > max_results_limit {
		return error('DuckDuckGo result count must be between 0 and ${max_results_limit}')
	}
	return Tool{
		max_results: if max_results == 0 { default_max_results } else { max_results }
		user_agent:  if user_agent.trim_space() == '' {
			default_user_agent
		} else {
			user_agent.trim_space()
		}
		http_client: http_client
	}
}

// new_default_tool uses the bounded default HTTP transport.
pub fn new_default_tool(max_results int, user_agent string) !Tool {
	return new_tool(max_results, user_agent, httputil.HTTPClient(httputil.new_default_client()))
}

// spec describes the search query expected by this tool.
pub fn (tool Tool) spec() tools.ToolSpec {
	return tools.ToolSpec{
		name:        'DuckDuckGo Search'
		description: 'Search the web with DuckDuckGo and return a bounded list of results.'
		parameters:  json2.Any({
			'type':       json2.Any('object')
			'properties': json2.Any({
				'query': json2.Any({
					'type': json2.Any('string')
				})
			})
			'required':   json2.Any([json2.Any('query')])
		})
	}
}

// call accepts a search string or JSON object containing `query`.
pub fn (tool Tool) call(mut ctx context.Context, input string) !string {
	query := parse_query(input) or { return error('invalid DuckDuckGo query: ${err.msg()}') }
	if query.trim_space() == '' {
		return error('DuckDuckGo query must not be empty')
	}
	if query.len > max_query_bytes {
		return error('DuckDuckGo query exceeds ${max_query_bytes} bytes')
	}
	request := httputil.Request{
		url:     'https://html.duckduckgo.com/html/?q=${urllib.query_escape(query)}'
		headers: {
			'Accept':     'text/html'
			'User-Agent': tool.user_agent
		}
	}
	response := tool.http_client.do(mut ctx, request)!
	if response.status_code < 200 || response.status_code >= 300 {
		return error('DuckDuckGo search returned HTTP ${response.status_code}')
	}
	if i64(response.body.len) > max_response_bytes {
		return error('DuckDuckGo response exceeds the 2 MiB limit')
	}
	return format_results(response.body, tool.max_results)
}

fn parse_query(input string) !string {
	if !input.trim_space().starts_with('{') {
		return input
	}
	values := json2.decode[map[string]json2.Any](input, json2.DecoderOptions{}) or {
		return error('input must be a search query or JSON object')
	}
	query := values['query'] or { return error('missing `query` field') }
	if query !is string {
		return error('`query` must be a string')
	}
	return query as string
}

fn format_results(document string, max_results int) !string {
	dom := html.parse(document)
	root := dom.get_root()
	result_nodes := root.get_tags_by_class_name('web-result')
	mut formatted := []string{}
	for result in result_nodes {
		if formatted.len >= max_results {
			break
		}
		anchor := result.get_tag_by_class_name('result__a') or { continue }
		snippet := result.get_tag_by_class_name('result__snippet') or { continue }
		title := html_entities.unescape(anchor.text().trim_space(), all: true)
		if title == '' {
			continue
		}
		url := decode_result_url(anchor.attributes['href'])!
		description := html_entities.unescape(snippet.text().trim_space(), all: true)
		formatted << 'Title: ${title}\nDescription: ${description}\nURL: ${url}'
	}
	if formatted.len == 0 {
		return no_results_message
	}
	return '${formatted.join('\n\n')}\n\n'
}

fn decode_result_url(href string) !string {
	marker := 'uddg='
	marker_index := href.index(marker) or { return href }
	encoded_url := href[marker_index + marker.len..].split('&')[0]
	return urllib.query_unescape(encoded_url)
}
