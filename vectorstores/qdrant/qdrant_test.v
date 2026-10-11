module qdrant

import context
import json2
import net.http
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.vectorstores

struct QdrantFixtureEmbedder {}

fn (embedder QdrantFixtureEmbedder) embed_documents(mut _ctx context.Context, texts []string) ![][]f32 {
	return texts.map([f32(0.25), 0.75])
}

fn (embedder QdrantFixtureEmbedder) embed_query(mut _ctx context.Context, _text string) ![]f32 {
	return [f32(0.25), 0.75]
}

@[heap]
struct QdrantFixtureState {
mut:
	requests  []httputil.Request
	responses []httputil.Response
}

struct QdrantFixtureHTTP {
	state &QdrantFixtureState
}

fn (client QdrantFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	if state.responses.len == 0 {
		return error('unexpected Qdrant request')
	}
	response := state.responses[0]
	state.responses.delete(0)
	return response
}

fn fixture_store(state &QdrantFixtureState) !Store {
	mut store := new_store('docs', QdrantFixtureEmbedder{}, StoreOptions{
		base_url: 'https://qdrant.example.test'
		api_key:  'fixture-token'
	})!
	store.http_client = httputil.HTTPClient(QdrantFixtureHTTP{
		state: state
	})
	return store
}

fn test_qdrant_upserts_documents_with_uuid_and_bounded_payload() {
	mut state := &QdrantFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"result":{"status":"ok"}}'
		}]
	}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	document := schema.new_document('alpha')
	ids := store.add_documents(mut ctx, [document], vectorstores.StoreOptions{
		namespace: 'tenant-a'
	}) or { panic(err) }
	assert ids.len == 1
	assert valid_uuid(ids[0])
	assert state.requests.len == 1
	request := state.requests[0]
	assert request.method == .put
	assert request.url == 'https://qdrant.example.test/collections/docs/points?wait=true'
	assert (request.headers['api-key'] or { '' }) == 'fixture-token'
	assert request.body.contains('tenant-a')
	assert request.body.contains('page_content')
	assert request.body.contains('[0.25,0.75]')
}

fn test_qdrant_search_maps_payload_filter_and_score() {
	mut state := &QdrantFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"result":{"points":[{"id":"123e4567-e89b-12d3-a456-426614174000","score":0.875,"payload":{"page_content":"answer","metadata":{"kind":"guide"}}}]}}'
		}]
	}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	mut options := vectorstores.SearchOptions{
		namespace: 'tenant-a'
	}
	options.filter['kind'] = json2.Any('guide')
	documents := store.similarity_search(mut ctx, 'query', 3, options) or { panic(err) }
	assert documents.len == 1
	assert documents[0].page_content == 'answer'
	assert documents[0].score == f32(0.875)
	assert documents[0].metadata['kind'] == json2.Any('guide')
	assert state.requests[0].url.ends_with('/points/query')
	assert state.requests[0].body.contains('metadata.kind')
	assert state.requests[0].body.contains('tenant-a')
}

fn test_qdrant_delete_uses_ids_and_namespace_filter() {
	mut state := &QdrantFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"result":{"status":"ok"}}'
		}]
	}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.delete(mut ctx, ['123e4567-e89b-12d3-a456-426614174000'], vectorstores.StoreOptions{
		namespace: 'tenant-a'
	}) or { panic(err) }
	assert state.requests[0].url.ends_with('/points/delete?wait=true')
	assert state.requests[0].body.contains('has_id')
	assert state.requests[0].body.contains('tenant-a')
}

fn test_qdrant_rejects_invalid_configuration_and_limits() {
	new_store('bad/name', QdrantFixtureEmbedder{}, StoreOptions{}) or {
		assert err.msg().contains('collection name')
		return
	}
	assert false, 'expected invalid collection name to fail'
	mut state := &QdrantFixtureState{}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.similarity_search(mut ctx, 'query', 1001, vectorstores.SearchOptions{}) or {
		assert err.msg().contains('between zero and 1000')
		return
	}
	assert false, 'expected over-limit search to fail'
}
