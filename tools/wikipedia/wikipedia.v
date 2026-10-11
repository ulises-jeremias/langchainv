// Package wikipedia implements bounded Wikipedia search.
module wikipedia

import context
import encoding.html as html_entities
import json2
import net.html
import net.urllib
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.tools

const default_user_agent = 'github.com/ulises-jeremias/langchainv/tools/wikipedia'
const default_max_results = 3
const max_results_limit = 20
const max_query_bytes = 4096
const max_response_bytes = i64(2 * 1024 * 1024)
const no_results_message = 'No good Wikipedia Search Result was found'

// Tool performs a bounded search using the MediaWiki REST API.
pub struct Tool {
pub:
	max_results int
	language    string
mut:
	http_client httputil.HTTPClient
}

// new_tool creates a Wikipedia search tool with an injectable transport.
pub fn new_tool(max_results int, language string, http_client httputil.HTTPClient) !Tool {
	if max_results < 0 || max_results > max_results_limit {
		return error('Wikipedia result count must be between 0 and ${max_results_limit}')
	}
	selected_language := if language.trim_space() == '' { 'en' } else { language.trim_space() }
	if selected_language.len > 16 {
		return error('Wikipedia language must be a short language code')
	}
	for ch in selected_language {
		if !(ch.is_alnum() || ch == `-`) {
			return error('Wikipedia language must be a short language code')
		}
	}
	return Tool{
		max_results: if max_results == 0 { default_max_results } else { max_results }
		language:    selected_language
		http_client: http_client
	}
}

// new_default_tool uses the bounded default HTTP transport.
pub fn new_default_tool(max_results int, language string) !Tool {
	return new_tool(max_results, language, httputil.HTTPClient(httputil.new_default_client()))
}

// spec describes the query expected by this tool.
pub fn (tool Tool) spec() tools.ToolSpec {
	return tools.ToolSpec{
		name:        'Wikipedia'
		description: 'Search Wikipedia articles and return bounded title and excerpt results.'
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

// call searches Wikipedia and returns plain-text article excerpts.
pub fn (tool Tool) call(mut ctx context.Context, input string) !string {
	query := parse_query(input) or { return error('invalid Wikipedia query: ${err.msg()}') }
	if query.trim_space() == '' {
		return error('Wikipedia query must not be empty')
	}
	if query.len > max_query_bytes {
		return error('Wikipedia query exceeds ${max_query_bytes} bytes')
	}
	request := httputil.Request{
		url:     'https://${tool.language}.wikipedia.org/w/rest.php/v1/search/page?q=${urllib.query_escape(query)}&limit=${tool.max_results}'
		headers: {
			'Accept':     'application/json'
			'User-Agent': default_user_agent
		}
	}
	response := tool.http_client.do(mut ctx, request)!
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Wikipedia search returned HTTP ${response.status_code}')
	}
	if i64(response.body.len) > max_response_bytes {
		return error('Wikipedia response exceeds the 2 MiB limit')
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
		return error('Wikipedia returned an invalid search response')
	}
	pages := decoded['pages'] or { return error('Wikipedia response is missing search results') }
	if pages !is []json2.Any {
		return error('Wikipedia response has an invalid search results field')
	}
	mut formatted := []string{}
	for page_value in pages as []json2.Any {
		if formatted.len >= max_results {
			break
		}
		page := page_value.as_map()
		title_value := page['title'] or { continue }
		excerpt_value := page['excerpt'] or { continue }
		if title_value !is string || excerpt_value !is string {
			continue
		}
		title := (title_value as string).trim_space()
		if title == '' {
			continue
		}
		dom := html.parse(excerpt_value as string)
		excerpt := html_entities.unescape(dom.get_root().text().trim_space(), all: true)
		formatted << 'Title: ${title}\nDescription: ${excerpt}'
	}
	if formatted.len == 0 {
		return no_results_message
	}
	return '${formatted.join('\n\n')}\n\n'
}
