module opensearch

import context
import encoding.base64
import json2
import net.http
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.vectorstores

struct OpenSearchFixtureEmbedder {}

fn (embedder OpenSearchFixtureEmbedder) embed_documents(mut _ctx context.Context, texts []string) ![][]f32 {
	return texts.map([f32(0.25), 0.75])
}

fn (embedder OpenSearchFixtureEmbedder) embed_query(mut _ctx context.Context, _text string) ![]f32 {
	return [f32(0.25), 0.75]
}

@[heap]
struct OpenSearchFixtureState {
mut:
	requests  []httputil.Request
	responses []httputil.Response
}

struct OpenSearchFixtureHTTP {
	state &OpenSearchFixtureState
}

fn (client OpenSearchFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	if state.responses.len == 0 {
		return error('unexpected OpenSearch request')
	}
	mut response := state.responses[0]
	state.responses.delete(0)
	return response
}

fn fixture_store(state &OpenSearchFixtureState) !Store {
	mut store := new_store(OpenSearchFixtureEmbedder{}, Options{
		base_url: 'https://search.example.test'
		index:    'docs'
		api_key:  'fixture-key'
	})!
	store.http_client = httputil.HTTPClient(OpenSearchFixtureHTTP{
		state: state
	})
	return store
}

fn test_opensearch_bulk_indexes_documents_with_auth_metadata_and_namespace() {
	mut state := &OpenSearchFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"errors":false,"items":[{"index":{"status":201}}]}'
		}]
	}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	mut document := schema.new_document('stored text')
	document.metadata['kind'] = json2.Any('guide')
	ids := store.add_documents(mut ctx, [document], vectorstores.StoreOptions{
		namespace: 'tenant-1'
	}) or { panic(err) }
	assert ids.len == 1
	request := state.requests[0]
	assert request.url == 'https://search.example.test/_bulk?refresh=true'
	assert (request.headers['Authorization'] or { '' }) == 'ApiKey fixture-key'
	assert request.headers['Content-Type'] == 'application/x-ndjson'
	assert request.body.contains('tenant-1')
	assert request.body.contains('stored text')
	assert request.body.contains('[0.25,0.75]')
	assert request.body.contains('"kind":"guide"')
}

fn test_opensearch_explicitly_initializes_cosine_index() {
	mut state := &OpenSearchFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"acknowledged":true}'
		}]
	}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.initialize_index(mut ctx, 384) or { panic(err) }
	request := state.requests[0]
	assert request.method == http.Method.put
	assert request.url == 'https://search.example.test/docs'
	assert request.body.contains('"knn_vector"')
	assert request.body.contains('"dimension":384')
	assert request.body.contains('"space_type":"cosinesimil"')
	assert request.body.contains('"engine":"lucene"')
	assert request.body.contains('"page_content":{"type":"text"}')
	assert (request.headers['Authorization'] or { '' }) == 'ApiKey fixture-key'
}

fn test_opensearch_index_initialization_rejects_invalid_dimensions_without_request() {
	mut state := &OpenSearchFixtureState{}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.initialize_index(mut ctx, 0) or {
		assert err.msg().contains('dimensions')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected invalid dimensions to fail'
}

fn test_opensearch_search_sends_knn_filters_and_restores_document() {
	mut state := &OpenSearchFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"hits":{"hits":[{"_score":0.91,"_source":{"page_content":"answer","metadata":{"kind":"guide"},"namespace":"tenant-1"}}]}}'
		}]
	}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	mut options := vectorstores.SearchOptions{
		namespace: 'tenant-1'
	}
	options.filter['kind'] = json2.Any('guide')
	documents := store.similarity_search(mut ctx, 'query', 3, options) or { panic(err) }
	assert documents.len == 1
	assert documents[0].page_content == 'answer'
	assert documents[0].score == f32(0.91)
	assert (documents[0].metadata['kind'] or { json2.Any('') }) == json2.Any('guide')
	request := state.requests[0]
	assert request.url == 'https://search.example.test/docs/_search'
	assert request.body.contains('"knn"')
	assert request.body.contains('metadata.kind')
	assert request.body.contains('tenant-1')
}

fn test_opensearch_search_returns_vectors_when_requested() {
	mut state := &OpenSearchFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"hits":{"hits":[{"_score":0.91,"_source":{"page_content":"answer","metadata":{},"namespace":"tenant-1","vector":[0.25,0.75]}}]}}'
		}]
	}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	documents := store.similarity_search(mut ctx, 'query', 1, vectorstores.SearchOptions{
		include_vectors: true
	}) or { panic(err) }
	assert documents.len == 1
	assert documents[0].embedding == [f32(0.25), f32(0.75)]
	assert state.requests[0].body.contains('"_source":["page_content","metadata","namespace","vector"]')
}

fn test_opensearch_rejects_non_numeric_returned_vector_values() {
	mut state := &OpenSearchFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"hits":{"hits":[{"_score":0.91,"_source":{"page_content":"answer","metadata":{},"namespace":"tenant-1","vector":[0.25,"bad"]}}]}}'
		}]
	}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.similarity_search(mut ctx, 'query', 1, vectorstores.SearchOptions{
		include_vectors: true
	}) or {
		assert err.msg().contains('score must be numeric')
		return
	}
	assert false, 'expected malformed OpenSearch vector to fail'
}

fn test_opensearch_deletes_ids_with_bulk_api() {
	mut state := &OpenSearchFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"errors":false,"items":[{"delete":{"status":200}}]}'
		}]
	}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.delete(mut ctx, ['doc-1'], vectorstores.StoreOptions{}) or { panic(err) }
	assert state.requests[0].body.contains('"delete"')
	assert state.requests[0].body.contains('doc-1')
}

fn test_opensearch_rejects_unsafe_endpoint_and_invalid_index() {
	new_store(OpenSearchFixtureEmbedder{}, Options{
		base_url: 'http://search.example.test'
		index:    'docs'
	}) or {
		assert err.msg().contains('HTTPS')
		return
	}
	assert false, 'expected remote HTTP to fail'
	new_store(OpenSearchFixtureEmbedder{}, Options{
		index: '+docs'
	}) or {
		assert err.msg().contains('index name')
		return
	}
	assert false, 'expected invalid index to fail'
	new_store(OpenSearchFixtureEmbedder{}, Options{
		index: 'docs-'
	}) or {
		assert err.msg().contains('index name')
		return
	}
	assert false, 'expected an invalid index suffix to fail'
	new_store(OpenSearchFixtureEmbedder{}, Options{
		index:      'docs'
		text_field: 'content.page'
	}) or {
		assert err.msg().contains('simple field names')
		return
	}
	assert false, 'expected a dotted configured field to fail'
}

fn test_opensearch_rejects_incomplete_basic_auth() {
	new_store(OpenSearchFixtureEmbedder{}, Options{
		base_url: 'https://search.example.test'
		index:    'docs'
		username: 'user'
	}) or {
		assert err.msg().contains('authentication'), err.msg()
		return
	}
	assert false, 'expected incomplete credentials to fail'
}

fn test_opensearch_rejects_failed_bulk_item() {
	mut state := &OpenSearchFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"errors":false,"items":[{"index":{"status":429}}]}'
		}]
	}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.add_documents(mut ctx, [schema.new_document('text')], vectorstores.StoreOptions{}) or {
		assert err.msg().contains('HTTP 429')
		return
	}
	assert false, 'expected failed bulk item to fail'
}

fn test_opensearch_uses_basic_auth_when_configured() {
	mut store := new_store(OpenSearchFixtureEmbedder{}, Options{
		base_url: 'https://search.example.test'
		index:    'docs'
		username: 'user'
		password: 'secret'
	}) or { panic(err) }
	mut state := &OpenSearchFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"hits":{"hits":[]}}'
		}]
	}
	store.http_client = httputil.HTTPClient(OpenSearchFixtureHTTP{
		state: state
	})
	mut ctx := context.background()
	store.similarity_search(mut ctx, 'query', 1, vectorstores.SearchOptions{}) or { panic(err) }
	assert (state.requests[0].headers['Authorization'] or { '' }) == 'Basic ${base64.encode('user:secret'.bytes())}'
}
