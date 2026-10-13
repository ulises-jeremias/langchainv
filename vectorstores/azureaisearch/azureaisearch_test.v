module azureaisearch

import context
import json2
import net.http
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.vectorstores

struct AzureFixtureEmbedder {}

fn (embedder AzureFixtureEmbedder) embed_documents(mut _ctx context.Context, texts []string) ![][]f32 {
	return texts.map([f32(0.25), f32(0.75)])
}

fn (embedder AzureFixtureEmbedder) embed_query(mut _ctx context.Context, _text string) ![]f32 {
	return [f32(0.25), f32(0.75)]
}

@[heap]
struct AzureFixtureState {
mut:
	requests  []httputil.Request
	responses []httputil.Response
}

struct AzureFixtureHTTP {
	state &AzureFixtureState
}

fn (client AzureFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	if state.responses.len == 0 {
		return error('unexpected Azure AI Search request')
	}
	response := state.responses[0]
	state.responses.delete(0)
	return response
}

fn fixture_store(state &AzureFixtureState) !Store {
	return new_store_with_client(AzureFixtureEmbedder{}, Options{
		endpoint:   'https://example.search.windows.net'
		index_name: 'documents'
		api_key:    'fixture-key'
	}, httputil.HTTPClient(AzureFixtureHTTP{
		state: state
	}))
}

fn test_azure_search_creates_a_cosine_hnsw_index_without_update_semantics() {
	mut state := &AzureFixtureState{
		responses: [httputil.Response{
			status_code: 201
			headers:     http.Header{}
			body:        '{"name":"documents"}'
		}]
	}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.create_index(mut ctx, 1536) or { panic(err) }
	assert state.requests.len == 1
	request := state.requests[0]
	assert request.method == .post
	assert request.url == 'https://example.search.windows.net/indexes?api-version=${api_version}'
	assert (request.headers['api-key'] or { '' }) == 'fixture-key'
	assert request.body.contains('"name":"documents"')
	assert request.body.contains('"dimensions":1536')
	assert request.body.contains('"vectorSearchProfile":"langchainv-cosine-profile"')
	assert request.body.contains('"metric":"cosine"')
	assert request.body.contains('"filterable":true')
}

fn test_azure_search_index_creation_rejects_invalid_dimensions_without_request() {
	mut state := &AzureFixtureState{}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.create_index(mut ctx, 0) or {
		assert err.msg().contains('dimensions')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected invalid Azure vector dimensions to fail'
}

fn test_azure_search_index_creation_rejects_one_dimension_without_request() {
	mut state := &AzureFixtureState{}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.new_context()
	store.create_index(mut ctx, 1) or {
		assert err.msg().contains('between 2 and 4096')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected one-dimensional Azure vector index creation to fail'
}

fn test_azure_search_create_only_operation_does_not_update_existing_index() {
	mut state := &AzureFixtureState{
		responses: [httputil.Response{
			status_code: 409
			headers:     http.Header{}
			body:        '{"error":{"code":"indexAlreadyExists"}}'
		}]
	}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.create_index(mut ctx, 1536) or {
		assert err.msg().contains('409')
		assert state.requests.len == 1
		assert state.requests[0].method == .post
		return
	}
	assert false, 'expected create-only request to reject an existing index'
}

fn test_azure_search_uploads_embedded_documents_with_safe_bounds() {
	mut state := &AzureFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"value":[{"key":"fixture","status":true}]}'
		}]
	}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	ids := store.add_documents(mut ctx, [schema.new_document('alpha')], vectorstores.StoreOptions{
		namespace: 'tenant-a'
	}) or { panic(err) }
	assert ids.len == 1
	assert state.requests.len == 1
	request := state.requests[0]
	assert request.method == .post
	assert request.url == "https://example.search.windows.net/indexes('documents')/docs/search.index?api-version=${api_version}"
	assert (request.headers['api-key'] or { '' }) == 'fixture-key'
	assert request.body.contains('tenant-a')
	assert request.body.contains('contentVector')
	assert request.body.contains('[0.25,0.75]')
}

fn test_azure_search_queries_vector_and_maps_result_fields() {
	mut state := &AzureFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"value":[{"id":"doc-1","content":"answer","metadata":"{\\"kind\\":\\"guide\\"}","namespace":"tenant-a","@search.score":0.875}]}'
		}]
	}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	documents := store.similarity_search(mut ctx, 'query', 3, vectorstores.SearchOptions{
		namespace: "tenant-'a"
	}) or { panic(err) }
	assert documents.len == 1
	assert documents[0].page_content == 'answer'
	assert documents[0].score == f32(0.875)
	assert documents[0].metadata.len == 1
	kind_any := documents[0].metadata['kind'] or { json2.Any('') }
	assert (kind_any as string) == 'guide'
	assert state.requests[0].url.ends_with('/docs/search.post.search?api-version=${api_version}')
	assert state.requests[0].body.contains('vectorQueries')
	assert state.requests[0].body.contains("namespace eq 'tenant-''a'")
}

fn test_azure_search_returns_stored_vector_only_when_requested() {
	mut state := &AzureFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"value":[{"id":"doc-1","content":"answer","metadata":"{}","namespace":"tenant-a","contentVector":[0.25,0.75],"@search.score":0.875}]}'
		}]
	}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	documents := store.similarity_search(mut ctx, 'query', 3, vectorstores.SearchOptions{
		include_vectors: true
	}) or { panic(err) }
	assert documents.len == 1
	assert documents[0].embedding == [f32(0.25), 0.75]
	assert state.requests[0].body.contains('"select":"id,content,metadata,namespace,contentVector"')
}

fn test_azure_search_rejects_returned_vectors_with_wrong_dimensions() {
	mut state := &AzureFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"value":[{"id":"doc-1","content":"answer","metadata":"{}","namespace":"tenant-a","contentVector":[0.25],"@search.score":0.875}]}'
		}]
	}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.similarity_search(mut ctx, 'query', 3, vectorstores.SearchOptions{
		include_vectors: true
	}) or {
		assert err.msg().contains('invalid dimension')
		return
	}
	assert false, 'expected an Azure vector with the wrong dimensions to fail'
}

fn test_azure_search_deletes_document_keys_and_rejects_partial_batch_failure() {
	mut state := &AzureFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"value":[{"key":"doc-1","status":true}]}'
		}]
	}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.delete(mut ctx, ['doc-1'], vectorstores.StoreOptions{}) or { panic(err) }
	assert state.requests[0].body.contains('"@search.action":"delete"')
	assert state.requests[0].body.contains('"id":"doc-1"')
	mut failed_state := &AzureFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"value":[{"key":"fixture","status":false}]}'
		}]
	}
	failed_store := fixture_store(failed_state) or { panic(err) }
	failed_store.add_documents(mut ctx, [schema.new_document('not stored')],
		vectorstores.StoreOptions{}) or {
		assert err.msg().contains('rejected')
		return
	}
	assert false, 'expected partial Azure indexing failure to be reported'
}

fn test_azure_search_rejects_invalid_endpoint_limits_and_unsupported_filters() {
	if _ := new_store(AzureFixtureEmbedder{}, Options{
		endpoint:   'http://example.search.windows.net'
		index_name: 'documents'
		api_key:    'fixture-key'
	}) {
		assert false, 'expected insecure endpoint to be rejected'
	} else {
		assert err.msg().contains('https')
	}
	mut state := &AzureFixtureState{}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	if _ := store.similarity_search(mut ctx, 'query', 1001, vectorstores.SearchOptions{}) {
		assert false, 'expected over-limit search to fail'
	} else {
		assert err.msg().contains('between zero and 1000')
	}
	mut filtered := vectorstores.SearchOptions{}
	filtered.filter['category'] = json2.Any('docs')
	if _ := store.similarity_search(mut ctx, 'query', 1, filtered) {
		assert false, 'expected unsupported metadata filter to be rejected'
	} else {
		assert err.msg().contains('metadata filters')
		assert state.requests.len == 0
	}
}
