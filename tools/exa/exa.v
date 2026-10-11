// Package exa implements bounded web search through Exa (formerly Metaphor).
module exa

import context
import json2
import os
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.tools

const exa_search_endpoint = 'https://api.exa.ai/search'
const default_max_results = 3
const max_results_limit = 10
const max_query_bytes = 4096
const max_response_bytes = i64(2 * 1024 * 1024)
const no_results_message = 'No good Exa Search Result was found'

// Tool searches Exa's semantic web index and returns bounded highlights.
pub struct Tool {
pub:
	max_results int
mut:
	api_key     string
	http_client httputil.HTTPClient
}

// new_tool creates an Exa search tool with an explicit key and injected transport.
pub fn new_tool(api_key string, max_results int, http_client httputil.HTTPClient) !Tool {
	if api_key.trim_space() == '' {
		return error('Exa API key must not be empty')
	}
	if max_results < 0 || max_results > max_results_limit {
		return error('Exa result count must be between 0 and ${max_results_limit}')
	}
	return Tool{
		api_key:     api_key.trim_space()
		max_results: if max_results == 0 { default_max_results } else { max_results }
		http_client: http_client
	}
}

// new_default_tool reads EXA_API_KEY and uses bounded default HTTP.
pub fn new_default_tool(max_results int) !Tool {
	api_key := os.getenv('EXA_API_KEY')
	if api_key.trim_space() == '' {
		return error('EXA_API_KEY is not set')
	}
	return new_tool(api_key, max_results, httputil.HTTPClient(httputil.new_default_client()))
}

// spec describes the query expected by this tool.
pub fn (tool Tool) spec() tools.ToolSpec {
	return tools.ToolSpec{
		name:        'Exa Search'
		description: 'Search the web semantically and return bounded result highlights.'
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

// call submits a bounded semantic search and formats excerpts as plain text.
pub fn (tool Tool) call(mut ctx context.Context, input string) !string {
	query := parse_query(input) or { return error('invalid Exa query: ${err.msg()}') }
	if query.trim_space() == '' {
		return error('Exa query must not be empty')
	}
	if query.len > max_query_bytes {
		return error('Exa query exceeds ${max_query_bytes} bytes')
	}
	mut body := map[string]json2.Any{}
	body['query'] = json2.Any(query)
	body['numResults'] = json2.Any(tool.max_results)
	body['contents'] = json2.Any({
		'highlights': json2.Any(true)
	})
	response := tool.http_client.do(mut ctx, httputil.Request{
		method:  .post
		url:     exa_search_endpoint
		headers: {
			'x-api-key':    tool.api_key
			'Content-Type': 'application/json'
			'Accept':       'application/json'
		}
		body:    json2.encode(body, json2.EncoderOptions{})
	})!
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Exa search returned HTTP ${response.status_code}')
	}
	if i64(response.body.len) > max_response_bytes {
		return error('Exa response exceeds the 2 MiB limit')
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
		return error('Exa returned an invalid search response')
	}
	if provider_error := decoded['error'] {
		if provider_error is string && (provider_error as string).trim_space() != '' {
			return error('Exa search failed')
		}
	}
	results := decoded['results'] or { return no_results_message }
	if results !is []json2.Any {
		return error('Exa response has an invalid results field')
	}
	mut formatted := []string{}
	for result_value in results as []json2.Any {
		if formatted.len >= max_results {
			break
		}
		if result_value !is map[string]json2.Any {
			continue
		}
		result := result_value as map[string]json2.Any
		title := exa_string(result, 'title')
		url := exa_string(result, 'url')
		if title == '' || url == '' {
			continue
		}
		excerpt := exa_excerpt(result)
		formatted << 'Title: ${title}\nDescription: ${excerpt}\nURL: ${url}'
	}
	if formatted.len == 0 {
		return no_results_message
	}
	return '${formatted.join('\n\n')}\n\n'
}

fn exa_string(result map[string]json2.Any, key string) string {
	value := result[key] or { return '' }
	if value is string {
		return (value as string).trim_space()
	}
	return ''
}

fn exa_excerpt(result map[string]json2.Any) string {
	if highlights := result['highlights'] {
		if highlights is []json2.Any {
			mut excerpts := []string{}
			for highlight in highlights as []json2.Any {
				if highlight is string && (highlight as string).trim_space() != '' {
					excerpts << (highlight as string).trim_space()
				}
			}
			if excerpts.len > 0 {
				return excerpts.join(' ')
			}
		}
	}
	return exa_string(result, 'text')
}
