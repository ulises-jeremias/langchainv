// Package documentloaders reads source data into shared document values.
module documentloaders

import context
import json2
import net.urllib
import os
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.schema

const notion_api_base_url = 'https://api.notion.com/v1'
const notion_api_version = '2026-03-11'
const default_notion_max_blocks = 2000
const default_notion_max_depth = 8
const default_notion_max_requests = 100
const default_notion_max_output_bytes = i64(8 * 1024 * 1024)
const max_notion_page_size = 100
const max_notion_response_bytes = i64(2 * 1024 * 1024)

// NotionLoaderOptions sets traversal and output bounds. Zero selects a default.
pub struct NotionLoaderOptions {
pub:
	max_blocks       int
	max_depth        int
	max_output_bytes i64
}

// NotionLoader recursively reads one Notion page using the Blocks API.
pub struct NotionLoader {
pub:
	page_id string
mut:
	api_key          string
	max_blocks       int
	max_depth        int
	max_requests     int
	max_output_bytes i64
	http_client      httputil.HTTPClient
}

struct NotionLoadState {
mut:
	page_content string
	blocks_read  int
	requests     int
}

// new_notion_loader constructs a bounded loader with an explicit token.
pub fn new_notion_loader(page_id string, api_key string, http_client httputil.HTTPClient, options NotionLoaderOptions) !NotionLoader {
	if !valid_notion_page_id(page_id) {
		return error('Notion page ID must be a UUID')
	}
	if api_key.trim_space() == '' {
		return error('Notion API key must not be empty')
	}
	max_blocks := if options.max_blocks == 0 {
		default_notion_max_blocks
	} else {
		options.max_blocks
	}
	max_depth := if options.max_depth == 0 { default_notion_max_depth } else { options.max_depth }
	max_output_bytes := if options.max_output_bytes == 0 {
		default_notion_max_output_bytes
	} else {
		options.max_output_bytes
	}
	if max_blocks < 1 || max_blocks > 10000 {
		return error('Notion maximum block count must be between 1 and 10000')
	}
	if max_depth < 0 || max_depth > 32 {
		return error('Notion maximum depth must be between 0 and 32')
	}
	if max_output_bytes < 1 || max_output_bytes > i64(64 * 1024 * 1024) {
		return error('Notion maximum output size must be between 1 byte and 64 MiB')
	}
	return NotionLoader{
		page_id:          page_id.trim_space()
		api_key:          api_key.trim_space()
		max_blocks:       max_blocks
		max_depth:        max_depth
		max_requests:     default_notion_max_requests
		max_output_bytes: max_output_bytes
		http_client:      http_client
	}
}

// new_default_notion_loader reads NOTION_API_KEY and uses bounded default HTTP.
pub fn new_default_notion_loader(page_id string, options NotionLoaderOptions) !NotionLoader {
	api_key := os.getenv('NOTION_API_KEY')
	if api_key.trim_space() == '' {
		return error('NOTION_API_KEY is not set')
	}
	return new_notion_loader(page_id, api_key, httputil.HTTPClient(httputil.new_default_client()),
		options)
}

// load retrieves the page's block tree, checking cancellation and resource bounds.
pub fn (loader NotionLoader) load(mut ctx context.Context) ![]schema.Document {
	mut state := NotionLoadState{}
	loader.load_block_children(loader.page_id, 0, mut ctx, mut state)!
	mut metadata := map[string]json2.Any{}
	metadata['source'] = json2.Any('https://www.notion.so/${loader.page_id.replace('-', '')}')
	metadata['page_id'] = json2.Any(loader.page_id)
	return [schema.Document{
		page_content: state.page_content.trim_space()
		metadata:     metadata
	}]
}

fn (loader NotionLoader) load_block_children(block_id string, depth int, mut ctx context.Context, mut state NotionLoadState) ! {
	if depth > loader.max_depth {
		return error('Notion page exceeds the configured child-block depth limit')
	}
	mut cursor := ''
	mut seen_cursors := map[string]bool{}
	for {
		ctx_error := ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
		if state.requests >= loader.max_requests {
			return error('Notion page exceeds the configured request limit')
		}
		state.requests++
		mut url := '${notion_api_base_url}/blocks/${urllib.query_escape(block_id)}/children?page_size=${max_notion_page_size}'
		if cursor != '' {
			url += '&start_cursor=${urllib.query_escape(cursor)}'
		}
		response := loader.http_client.do(mut ctx, httputil.Request{
			url:     url
			headers: {
				'Authorization':  'Bearer ${loader.api_key}'
				'Accept':         'application/json'
				'Notion-Version': notion_api_version
			}
		})!
		if response.status_code < 200 || response.status_code >= 300 {
			return error('Notion block request returned HTTP ${response.status_code}')
		}
		if i64(response.body.len) > max_notion_response_bytes {
			return error('Notion response exceeds the 2 MiB per-request limit')
		}
		decoded := json2.decode[map[string]json2.Any](response.body, json2.DecoderOptions{}) or {
			return error('Notion returned an invalid block response')
		}
		results_value := decoded['results'] or { return error('Notion response is missing blocks') }
		if results_value !is []json2.Any {
			return error('Notion response has an invalid blocks field')
		}
		for block_value in results_value as []json2.Any {
			state.blocks_read++
			if state.blocks_read > loader.max_blocks {
				return error('Notion page exceeds the configured block limit')
			}
			block := block_value.as_map()
			block_type_value := block['type'] or { continue }
			if block_type_value !is string {
				continue
			}
			block_type := block_type_value as string
			if block_data_value := block[block_type] {
				if block_data_value is map[string]json2.Any {
					loader.append_block_text(block_type, block_data_value as map[string]json2.Any,
						mut state)!
				}
			}
			if json_bool(block, 'has_children') {
				if depth >= loader.max_depth {
					return error('Notion page exceeds the configured child-block depth limit')
				}
				child_id_value := block['id'] or { continue }
				if child_id_value is string {
					child_id := child_id_value as string
					if valid_notion_page_id(child_id) {
						loader.load_block_children(child_id, depth + 1, mut ctx, mut state)!
					}
				}
			}
		}
		has_more_value := decoded['has_more'] or { json2.Any(false) }
		if has_more_value !is bool || !(has_more_value as bool) {
			break
		}
		next_cursor_value := decoded['next_cursor'] or { return error('Notion response is missing its next cursor') }
		if next_cursor_value !is string {
			return error('Notion response has an invalid next cursor')
		}
		cursor = next_cursor_value as string
		if cursor == '' || seen_cursors[cursor] {
			return error('Notion returned an empty or repeated pagination cursor')
		}
		seen_cursors[cursor] = true
	}
}

fn (loader NotionLoader) append_block_text(block_type string, block_data map[string]json2.Any, mut state NotionLoadState) ! {
	rich_text_value := block_data['rich_text'] or { return }
	if rich_text_value !is []json2.Any {
		return
	}
	mut text := ''
	for text_value in rich_text_value as []json2.Any {
		text_item := text_value.as_map()
		plain_text_value := text_item['plain_text'] or { continue }
		if plain_text_value is string {
			text += plain_text_value as string
		}
	}
	if text == '' {
		return
	}
	match block_type {
		'heading_1' { text = '# ${text}' }
		'heading_2' { text = '## ${text}' }
		'heading_3' { text = '### ${text}' }
		'heading_4' { text = '#### ${text}' }
		'bulleted_list_item' { text = '- ${text}' }
		'numbered_list_item' { text = '1. ${text}' }
		'to_do' {
			checked_value := block_data['checked'] or { json2.Any(false) }
			text = if checked_value is bool && (checked_value as bool) {
				'- [x] ${text}'
			} else {
				'- [ ] ${text}'
			}
		}
		'quote' { text = '> ${text}' }
		'code' { text = '```\n${text}\n```' }
		else {}
	}
	addition := if state.page_content == '' { text } else { '\n${text}' }
	if i64(state.page_content.len + addition.len) > loader.max_output_bytes {
		return error('Notion page exceeds the configured output byte limit')
	}
	state.page_content += addition
}

fn valid_notion_page_id(page_id string) bool {
	trimmed := page_id.trim_space()
	compact := trimmed.replace('-', '')
	if compact.len != 32 || (trimmed.len != 32 && trimmed.len != 36) {
		return false
	}
	for ch in compact {
		if !(ch.is_hex_digit()) {
			return false
		}
	}
	return true
}

fn json_bool(object map[string]json2.Any, key string) bool {
	value := object[key] or { return false }
	return if value is bool { value as bool } else { false }
}
