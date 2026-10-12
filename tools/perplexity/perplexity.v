// Package perplexity implements the Perplexity AI search tool.
module perplexity

import context
import json2
import os
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.openai
import ulises_jeremias.langchainv.tools

const default_model = 'sonar'
const perplexity_base_url = 'https://api.perplexity.ai'
const max_query_bytes = 8192

// Model names currently supported by the Perplexity Sonar API.
pub const model_sonar = 'sonar'
pub const model_sonar_reasoning = 'sonar-reasoning'
pub const model_sonar_deep_research = 'sonar-deep-research'

// Tool sends searches to Perplexity's OpenAI-compatible Chat Completions API.
pub struct Tool {
	client openai.Client
}

// new_tool creates a Perplexity tool with an explicit API key and transport.
pub fn new_tool(api_key string, http_client httputil.HTTPClient, model string) !Tool {
	selected_model := if model.trim_space() == '' { default_model } else { model.trim_space() }
	client := openai.new_client_with_options(api_key, http_client, openai.Options{
		base_url: perplexity_base_url
		model:    selected_model
	})!
	return Tool{
		client: client
	}
}

// new_default_tool reads PERPLEXITY_API_KEY and uses bounded default HTTP.
pub fn new_default_tool(model string) !Tool {
	api_key := os.getenv('PERPLEXITY_API_KEY')
	if api_key.trim_space() == '' {
		return error('PERPLEXITY_API_KEY is not set')
	}
	return new_tool(api_key, httputil.HTTPClient(httputil.new_default_client()), model)
}

// spec returns the model-facing query schema.
pub fn (tool Tool) spec() tools.ToolSpec {
	mut query_schema := map[string]json2.Any{}
	query_schema['type'] = json2.Any('string')
	mut properties := map[string]json2.Any{}
	properties['query'] = json2.Any(query_schema)
	return tools.ToolSpec{
		name:        'PerplexityAI'
		description: 'Search the web and summarize current information using Perplexity AI.'
		parameters:  json2.Any({
			'type':       json2.Any('object')
			'properties': json2.Any(properties)
			'required':   json2.Any([json2.Any('query')])
		})
	}
}

// call sends a bounded query and returns the model's grounded answer.
pub fn (tool Tool) call(mut ctx context.Context, input string) !string {
	query := parse_query(input) or { return error('invalid Perplexity query: ${err.msg()}') }
	if query.len > max_query_bytes {
		return error('Perplexity query exceeds ${max_query_bytes} bytes')
	}
	if query.trim_space() == '' {
		return error('Perplexity query must not be empty')
	}
	return tool.client.complete(mut ctx, query, llms.CallOptions{})
}

fn parse_query(input string) !string {
	if !input.trim_space().starts_with('{') {
		return input
	}
	values := json2.decode[map[string]json2.Any](input, json2.DecoderOptions{}) or {
		return error('input must be a search query or a JSON object')
	}
	query := values['query'] or { return error('missing `query` field') }
	if query !is string {
		return error('`query` must be a string')
	}
	return query as string
}
