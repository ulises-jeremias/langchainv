// Package serpapi implements bounded Google search through SerpApi.
module serpapi

import context
import json2
import net.urllib
import os
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.tools

const serpapi_endpoint = 'https://serpapi.com/search.json'
const default_user_agent = 'github.com/ulises-jeremias/langchainv/tools/serpapi'
const default_max_results = 3
const max_results_limit = 10
const max_query_bytes = 4096
const max_response_bytes = i64(2 * 1024 * 1024)
const no_results_message = 'No good SerpApi Search Result was found'

// Tool searches Google through the SerpApi Search API.
pub struct Tool {
pub:
	max_results int
mut:
	api_key     string
	http_client httputil.HTTPClient
}

// new_tool creates a SerpApi tool with an explicit key and injected transport.
pub fn new_tool(api_key string, max_results int, http_client httputil.HTTPClient) !Tool {
	if api_key.trim_space() == '' {
		return error('SerpApi API key must not be empty')
	}
	if max_results < 0 || max_results > max_results_limit {
		return error('SerpApi result count must be between 0 and ${max_results_limit}')
	}
	return Tool{
		api_key:     api_key.trim_space()
		max_results: if max_results == 0 { default_max_results } else { max_results }
		http_client: http_client
	}
}

// new_default_tool reads SERPAPI_API_KEY and uses bounded default HTTP.
pub fn new_default_tool(max_results int) !Tool {
	api_key := os.getenv('SERPAPI_API_KEY')
	if api_key.trim_space() == '' {
		return error('SERPAPI_API_KEY is not set')
	}
	return new_tool(api_key, max_results, httputil.HTTPClient(httputil.new_default_client()))
}

// spec describes the search query expected by this tool.
pub fn (tool Tool) spec() tools.ToolSpec {
	return tools.ToolSpec{
		name:        'SerpApi Search'
		description: 'Search Google and return a bounded list of organic results.'
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

// call sends a bounded search and returns plain-text organic results.
pub fn (tool Tool) call(mut ctx context.Context, input string) !string {
	query := parse_query(input) or { return error('invalid SerpApi query: ${err.msg()}') }
	if query.trim_space() == '' {
		return error('SerpApi query must not be empty')
	}
	if query.len > max_query_bytes {
		return error('SerpApi query exceeds ${max_query_bytes} bytes')
	}
	request := httputil.Request{
		url:     '${serpapi_endpoint}?engine=google&q=${urllib.query_escape(query)}&api_key=${urllib.query_escape(tool.api_key)}&output=json'
		headers: {
			'Accept':     'application/json'
			'User-Agent': default_user_agent
		}
	}
	response := tool.http_client.do(mut ctx, request)!
	if response.status_code < 200 || response.status_code >= 300 {
		return error('SerpApi search returned HTTP ${response.status_code}')
	}
	if i64(response.body.len) > max_response_bytes {
		return error('SerpApi response exceeds the 2 MiB limit')
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
	decoded := json2.decode[map[string]json2.Any](document, json2.DecoderOptions{}) or {
		return error('SerpApi returned an invalid search response')
	}
	if provider_error := decoded['error'] {
		if provider_error is string && (provider_error as string).trim_space() != '' {
			return error('SerpApi search failed')
		}
	}
	organic := decoded['organic_results'] or { return no_results_message }
	if organic !is []json2.Any {
		return error('SerpApi response has an invalid organic_results field')
	}
	mut formatted := []string{}
	for item_value in organic as []json2.Any {
		if formatted.len >= max_results {
			break
		}
		item := item_value.as_map()
		title_value := item['title'] or { continue }
		link_value := item['link'] or { continue }
		snippet_value := item['snippet'] or { json2.Any('') }
		if title_value !is string || link_value !is string || snippet_value !is string {
			continue
		}
		title := (title_value as string).trim_space()
		link := (link_value as string).trim_space()
		if title == '' || link == '' {
			continue
		}
		snippet := (snippet_value as string).trim_space()
		formatted << 'Title: ${title}\nDescription: ${snippet}\nURL: ${link}'
	}
	if formatted.len == 0 {
		return no_results_message
	}
	return '${formatted.join('\n\n')}\n\n'
}
