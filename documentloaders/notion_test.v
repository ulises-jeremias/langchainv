module documentloaders

import context
import ulises_jeremias.langchainv.httputil

const notion_page_id = '59833787-2cf9-4fdf-8782-e53db20768a5'
const notion_nested_block_id = 'c02fc1d3-db8b-45c5-a222-27595b15aea7'

@[heap]
struct NotionFixtureState {
mut:
	requests []httputil.Request
}

struct NotionFixtureHTTP {
	state     &NotionFixtureState
	responses []string
}

fn (client NotionFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	index := state.requests.len - 1
	if index >= client.responses.len {
		return error('unexpected Notion fixture request')
	}
	return httputil.Response{
		status_code: 200
		body:        client.responses[index]
	}
}

fn test_notion_loader_formats_text_and_records_source_metadata() {
	mut state := &NotionFixtureState{}
	http := NotionFixtureHTTP{
		state:     state
		responses: [
			'{"has_more":false,"results":[{"id":"${notion_nested_block_id}","type":"heading_1","has_children":false,"heading_1":{"rich_text":[{"plain_text":"Project notes"}]}},{"id":"b13","type":"paragraph","has_children":false,"paragraph":{"rich_text":[{"plain_text":"First "},{"plain_text":"paragraph."}]}}]}',
		]
	}
	loader := new_notion_loader(notion_page_id, 'integration-secret', httputil.HTTPClient(http),
		NotionLoaderOptions{}) or { panic(err) }
	mut ctx := context.background()
	documents := loader.load(mut ctx) or { panic(err) }
	assert documents.len == 1
	assert documents[0].page_content == '# Project notes\nFirst paragraph.'
	page_id_value := documents[0].metadata['page_id'] or { panic('missing page_id metadata') }
	source_value := documents[0].metadata['source'] or { panic('missing source metadata') }
	assert page_id_value.str() == notion_page_id
	assert source_value.str() == 'https://www.notion.so/598337872cf94fdf8782e53db20768a5'
	assert state.requests.len == 1
	assert state.requests[0].url == 'https://api.notion.com/v1/blocks/${notion_page_id}/children?page_size=100'
	assert state.requests[0].headers['Authorization'] == 'Bearer integration-secret'
	assert state.requests[0].headers['Notion-Version'] == notion_api_version
}

fn test_notion_loader_paginates_and_recurses_with_global_bounds() {
	mut state := &NotionFixtureState{}
	http := NotionFixtureHTTP{
		state:     state
		responses: [
			'{"has_more":true,"next_cursor":"e6cc1a0a-9773-4c87-ae79-7bdc7d02077d","results":[{"id":"${notion_nested_block_id}","type":"toggle","has_children":true,"toggle":{"rich_text":[{"plain_text":"Details"}]}}]}',
			'{"has_more":false,"results":[{"id":"b14","type":"paragraph","has_children":false,"paragraph":{"rich_text":[{"plain_text":"Nested text"}]}}]}',
			'{"has_more":false,"results":[{"id":"b15","type":"paragraph","has_children":false,"paragraph":{"rich_text":[{"plain_text":"Later page"}]}}]}',
		]
	}
	loader := new_notion_loader(notion_page_id, 'test-token', httputil.HTTPClient(http), NotionLoaderOptions{
		max_blocks: 3
		max_depth:  2
	}) or { panic(err) }
	mut ctx := context.background()
	documents := loader.load(mut ctx) or { panic(err) }
	assert documents[0].page_content == 'Details\nNested text\nLater page'
	assert state.requests.len == 3
	assert state.requests[1].url.contains('/blocks/${notion_nested_block_id}/children')
	assert state.requests[2].url.contains('start_cursor=e6cc1a0a-9773-4c87-ae79-7bdc7d02077d')
}

fn test_notion_loader_rejects_bad_page_id_and_redacts_http_errors() {
	mut state := &NotionFixtureState{}
	new_notion_loader('invalid/uuid', 'test-token', httputil.HTTPClient(NotionFixtureHTTP{
		state:     state
		responses: []
	}), NotionLoaderOptions{}) or {
		assert err.msg() == 'Notion page ID must be a UUID'
		return
	}
	assert false, 'expected invalid Notion page ID to fail'
	loader := new_notion_loader(notion_page_id, 'test-token', httputil.HTTPClient(NotionErrorFixtureHTTP{}),
		NotionLoaderOptions{}) or { panic(err) }
	mut ctx := context.background()
	loader.load(mut ctx) or {
		assert err.msg() == 'Notion block request returned HTTP 401'
		assert !err.msg().contains('credential')
		return
	}
	assert false, 'expected a failed Notion request'
}

struct NotionErrorFixtureHTTP {}

fn (client NotionErrorFixtureHTTP) do(mut _ctx context.Context, _request httputil.Request) !httputil.Response {
	return httputil.Response{
		status_code: 401
		body:        'credential rejected'
	}
}
