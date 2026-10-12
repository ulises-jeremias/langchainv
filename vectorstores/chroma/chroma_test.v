module chroma

import context
import json2
import net.http
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.vectorstores

struct ChromaFixtureEmbedder {}

fn (_embedder ChromaFixtureEmbedder) embed_documents(mut _ctx context.Context, texts []string) ![][]f32 {
	return texts.map([f32(0.4), 0.6])
}

fn (_embedder ChromaFixtureEmbedder) embed_query(mut _ctx context.Context, _text string) ![]f32 {
	return [f32(0.4), 0.6]
}

@[heap]
struct ChromaFixtureState {
mut:
	requests  []httputil.Request
	responses []httputil.Response
}

struct ChromaFixtureHTTP {
	state &ChromaFixtureState
}

fn (client ChromaFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	if state.responses.len == 0 {
		return error('unexpected Chroma request')
	}
	response := state.responses[0]
	state.responses.delete(0)
	return response
}

fn chroma_fixture_store(state &ChromaFixtureState) !Store {
	mut store := new_store(ChromaFixtureEmbedder{}, Options{
		base_url:      'https://chroma.example.test'
		tenant:        'tenant-a'
		database:      'database-a'
		collection_id: '11111111-1111-4111-8111-111111111111'
		api_key:       'fixture-key'
	})!
	store.http_client = httputil.HTTPClient(ChromaFixtureHTTP{
		state: state
	})
	return store
}

fn chroma_response(body string) httputil.Response {
	return httputil.Response{
		status_code: 200
		headers:     http.Header{}
		body:        body
	}
}

fn test_chroma_upserts_documents_with_namespace_and_injected_embedding() {
	mut state := &ChromaFixtureState{
		responses: [chroma_response('{}')]
	}
	mut store := chroma_fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	mut document := schema.new_document('stored text')
	document.metadata['category'] = json2.Any('guide')
	ids := store.add_documents(mut ctx, [document], vectorstores.StoreOptions{
		namespace: 'tenant-1'
	}) or { panic(err) }
	assert ids.len == 1
	assert state.requests.len == 1
	request := state.requests[0]
	assert request.method == .post
	assert request.url.ends_with('/api/v2/tenants/tenant-a/databases/database-a/collections/11111111-1111-4111-8111-111111111111/upsert')
	assert (request.headers['x-chroma-token'] or { '' }) == 'fixture-key'
	assert request.body.contains('stored text')
	assert request.body.contains('tenant-1')
	assert request.body.contains('[0.4,0.6]')
}

fn test_chroma_creates_named_collection_and_uses_returned_id() {
	mut state := &ChromaFixtureState{
		responses: [
			chroma_response('{"id":"22222222-2222-4222-8222-222222222222","name":"guides"}'),
			chroma_response('{}'),
		]
	}
	mut ctx := context.background()
	mut store := new_store_with_collection_and_client(mut ctx, ChromaFixtureEmbedder{}, Options{
		base_url: 'https://chroma.example.test'
		tenant:   'tenant-a'
		database: 'database-a'
		api_key:  'fixture-key'
	}, 'guides', true, httputil.HTTPClient(ChromaFixtureHTTP{
		state: state
	})) or { panic(err) }
	assert store.collection_id == '22222222-2222-4222-8222-222222222222'
	assert state.requests.len == 1
	assert state.requests[0].method == .post
	assert state.requests[0].url.ends_with('/api/v2/tenants/tenant-a/databases/database-a/collections')
	assert state.requests[0].body.contains('"name":"guides"')
	assert state.requests[0].body.contains('"get_or_create":true')
	store.add_documents(mut ctx, [schema.new_document('new collection document')],
		vectorstores.StoreOptions{}) or { panic(err) }
	assert state.requests.len == 2
	assert state.requests[1].url.ends_with('/collections/22222222-2222-4222-8222-222222222222/upsert')
}

fn test_chroma_deletes_bound_collection() {
	mut state := &ChromaFixtureState{
		responses: [chroma_response('{}')]
	}
	mut store := chroma_fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.delete_collection(mut ctx) or { panic(err) }
	assert state.requests.len == 1
	assert state.requests[0].method == .delete
	assert state.requests[0].url.ends_with('/collections/11111111-1111-4111-8111-111111111111')
}

fn test_chroma_rejects_unsafe_server_collection_id() {
	mut state := &ChromaFixtureState{
		responses: [chroma_response('{"id":"../unsafe"}')]
	}
	mut ctx := context.background()
	new_store_with_collection_and_client(mut ctx, ChromaFixtureEmbedder{}, Options{
		base_url: 'https://chroma.example.test'
	}, 'guides', false, httputil.HTTPClient(ChromaFixtureHTTP{
		state: state
	})) or {
		assert err.msg().contains('invalid collection ID')
		return
	}
	assert false, 'expected unsafe server collection ID to fail'
}

fn test_chroma_query_maps_distances_metadata_and_exact_filters() {
	mut state := &ChromaFixtureState{
		responses: [chroma_response('{"ids":[["id-1"]],"documents":[["answer"]],"metadatas":[[{"category":"guide","_langchainv_namespace":"tenant-1"}]],"distances":[[0.09]]}')]
	}
	mut store := chroma_fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	mut options := vectorstores.SearchOptions{
		namespace: 'tenant-1'
	}
	options.filter['category'] = json2.Any('guide')
	documents := store.similarity_search(mut ctx, 'query', 2, options) or { panic(err) }
	assert documents.len == 1
	assert documents[0].page_content == 'answer'
	assert documents[0].score > f32(0.90) && documents[0].score < f32(0.92)
	assert (documents[0].metadata['category'] or { json2.Any('') }) == json2.Any('guide')
	assert '_langchainv_namespace' !in documents[0].metadata
	request := state.requests[0]
	assert request.url.ends_with('/query')
	assert request.body.contains('query_embeddings')
	assert request.body.contains('\$and')
	assert request.body.contains('category')
	assert request.body.contains('"include":["documents","metadatas","distances"]')
}

fn test_chroma_query_can_return_stored_embeddings() {
	mut state := &ChromaFixtureState{
		responses: [chroma_response('{"ids":[["id-1"]],"documents":[["answer"]],"metadatas":[[{}]],"distances":[[0.09]],"embeddings":[[[0.4,0.6]]]}')]
	}
	mut store := chroma_fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	documents := store.similarity_search(mut ctx, 'query', 2, vectorstores.SearchOptions{
		include_vectors: true
	}) or { panic(err) }
	assert documents.len == 1
	assert documents[0].embedding == [f32(0.4), f32(0.6)]
	assert state.requests[0].body.contains('"include":["documents","metadatas","distances","embeddings"]')
}

fn test_chroma_rejects_malformed_returned_embeddings() {
	mut state := &ChromaFixtureState{
		responses: [chroma_response('{"ids":[["id-1"]],"documents":[["answer"]],"metadatas":[[{}]],"distances":[[0.09]],"embeddings":[[[0.4,"bad"]]]}')]
	}
	mut store := chroma_fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.similarity_search(mut ctx, 'query', 1, vectorstores.SearchOptions{
		include_vectors: true
	}) or {
		assert err.msg().contains('non-numeric')
		return
	}
	assert false, 'expected malformed Chroma embedding to fail'
}

fn test_chroma_delete_limits_ids_and_applies_namespace_filter() {
	mut state := &ChromaFixtureState{
		responses: [chroma_response('{}')]
	}
	mut store := chroma_fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.delete(mut ctx, ['id-1', 'id-2'], vectorstores.StoreOptions{
		namespace: 'tenant-1'
	}) or { panic(err) }
	assert state.requests[0].url.ends_with('/delete')
	assert state.requests[0].body.contains('id-1')
	assert state.requests[0].body.contains('_langchainv_namespace')
}

fn test_chroma_rejects_remote_http_endpoint() {
	new_store(ChromaFixtureEmbedder{}, Options{
		base_url:      'http://remote.example.test'
		collection_id: 'collection-1'
	}) or {
		assert err.msg().contains('HTTPS')
		return
	}
	assert false, 'expected remote HTTP endpoint to fail'
}

fn test_chroma_rejects_unsafe_collection_and_oversized_writes() {
	new_store(ChromaFixtureEmbedder{}, Options{
		base_url:      'https://chroma.example.test'
		collection_id: '../collection'
	}) or {
		assert err.msg().contains('safe path segment')
		return
	}
	assert false, 'expected unsafe collection ID to fail'
	mut state := &ChromaFixtureState{}
	mut store := chroma_fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	documents := []schema.Document{len: 65}
	store.add_documents(mut ctx, documents, vectorstores.StoreOptions{}) or {
		assert err.msg().contains('limited to 64')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected oversized write to fail'
}

fn test_chroma_redacts_http_error_bodies() {
	mut state := &ChromaFixtureState{
		responses: [httputil.Response{
			status_code: 403
			headers:     http.Header{}
			body:        'secret-provider-error'
		}]
	}
	mut store := chroma_fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.delete(mut ctx, ['id-1'], vectorstores.StoreOptions{}) or {
		assert err.msg().contains('HTTP 403')
		assert !err.msg().contains('secret-provider-error')
		return
	}
	assert false, 'expected non-success response to fail'
}

fn test_chroma_rejects_mismatched_query_result_arrays() {
	mut state := &ChromaFixtureState{
		responses: [chroma_response('{"ids":[["id-1"]],"documents":[[]],"metadatas":[[]],"distances":[[]]}')]
	}
	mut store := chroma_fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.similarity_search(mut ctx, 'query', 1, vectorstores.SearchOptions{}) or {
		assert err.msg().contains('mismatched')
		return
	}
	assert false, 'expected mismatched response lengths to fail'
}
