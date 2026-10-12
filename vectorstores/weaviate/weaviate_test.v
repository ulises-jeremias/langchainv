module weaviate

import context
import json2
import net.http
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.vectorstores

struct WeaviateFixtureEmbedder {}

fn (_ WeaviateFixtureEmbedder) embed_documents(mut _ctx context.Context, texts []string) ![][]f32 {
	return texts.map([f32(0.4), 0.6])
}

fn (_ WeaviateFixtureEmbedder) embed_query(mut _ctx context.Context, _text string) ![]f32 {
	return [f32(0.4), 0.6]
}

@[heap]
struct WeaviateFixtureState {
mut:
	requests  []httputil.Request
	responses []httputil.Response
}

struct WeaviateFixtureHTTP {
	state &WeaviateFixtureState
}

fn (client WeaviateFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	if state.responses.len == 0 {
		return error('unexpected Weaviate request')
	}
	response := state.responses[0]
	state.responses.delete(0)
	return response
}

fn weaviate_fixture_store(state &WeaviateFixtureState) !Store {
	return new_store_with_client(WeaviateFixtureEmbedder{}, Options{
		base_url:   'https://weaviate.example.test'
		class_name: 'Guide'
		api_key:    'fixture-key'
	}, httputil.HTTPClient(WeaviateFixtureHTTP{
		state: state
	}))
}

fn weaviate_response(body string) httputil.Response {
	return httputil.Response{
		status_code: 200
		headers:     http.Header{}
		body:        body
	}
}

fn test_weaviate_batch_upserts_document_with_namespace_auth_and_vector() {
	mut state := &WeaviateFixtureState{
		responses: [weaviate_response('[{"result":{}}]')]
	}
	mut store := weaviate_fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	mut document := schema.new_document('stored text')
	document.metadata['category'] = 'guide'
	ids := store.add_documents(mut ctx, [document], vectorstores.StoreOptions{
		namespace: 'tenant-a'
	}) or { panic(err) }
	assert ids.len == 1
	assert state.requests.len == 1
	request := state.requests[0]
	assert request.method == .post
	assert request.url.ends_with('/v1/batch/objects')
	assert (request.headers['Authorization'] or { '' }) == 'Bearer fixture-key'
	assert request.body.contains('stored text')
	assert request.body.contains('tenant-a')
	assert request.body.contains('[0.4,0.6]')
}

fn test_weaviate_similarity_search_maps_certainty_and_metadata() {
	mut state := &WeaviateFixtureState{
		responses: [weaviate_response('{"data":{"Get":{"Guide":[{"text":"answer","category":"guide","nameSpace":"default","_additional":{"certainty":0.9}}]}}}')]
	}
	mut store := weaviate_fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	mut options := vectorstores.SearchOptions{}
	options.filter['category'] = 'guide'
	documents := store.similarity_search(mut ctx, 'query', 3, options) or { panic(err) }
	assert documents.len == 1
	assert documents[0].page_content == 'answer'
	assert documents[0].score > f32(0.89) && documents[0].score < f32(0.91)
	assert (documents[0].metadata['category'] or { json2.Any('') }) == json2.Any('guide')
	request := state.requests[0]
	assert request.url.ends_with('/v1/graphql')
	assert request.body.contains('nearVector')
	assert request.body.contains('operator: Equal')
	assert request.body.contains('nameSpace')
}

fn test_weaviate_similarity_search_returns_vector_when_requested() {
	mut state := &WeaviateFixtureState{
		responses: [weaviate_response('{"data":{"Get":{"Guide":[{"text":"answer","nameSpace":"default","_additional":{"certainty":0.9,"vector":[0.4,0.6]}}]}}}')]
	}
	mut store := weaviate_fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	documents := store.similarity_search(mut ctx, 'query', 1, vectorstores.SearchOptions{
		include_vectors: true
	}) or { panic(err) }
	assert documents.len == 1
	assert documents[0].embedding == [f32(0.4), f32(0.6)]
	assert state.requests[0].body.contains('_additional { certainty vector }')
}

fn test_weaviate_rejects_non_numeric_returned_vector_values() {
	mut state := &WeaviateFixtureState{
		responses: [weaviate_response('{"data":{"Get":{"Guide":[{"text":"answer","nameSpace":"default","_additional":{"certainty":0.9,"vector":[0.4,"bad"]}}]}}}')]
	}
	mut store := weaviate_fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.similarity_search(mut ctx, 'query', 1, vectorstores.SearchOptions{
		include_vectors: true
	}) or {
		assert err.msg().contains('finite numbers')
		return
	}
	assert false, 'expected malformed Weaviate vector to fail'
}

fn test_weaviate_metadata_search_and_delete() {
	mut state := &WeaviateFixtureState{
		responses: [
			weaviate_response('{"data":{"Get":{"Guide":[{"text":"found","nameSpace":"default","_additional":{"certainty":0.0}}]}}}'),
			weaviate_response('{}'),
		]
	}
	mut store := weaviate_fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	documents := store.metadata_search(mut ctx, 2, vectorstores.SearchOptions{}) or { panic(err) }
	assert documents.len == 1
	assert documents[0].score == 0
	store.delete(mut ctx, ['11111111-1111-4111-8111-111111111111'], vectorstores.StoreOptions{}) or {
		panic(err)
	}
	assert state.requests[1].method == .delete
	assert state.requests[1].url.ends_with('/v1/objects/Guide/11111111-1111-4111-8111-111111111111')
}

fn test_weaviate_rejects_http_200_batch_object_errors() {
	mut state := &WeaviateFixtureState{
		responses: [weaviate_response('[{"result":{"errors":{"error":[{"message":"bad object"}]}}}]')]
	}
	mut store := weaviate_fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.add_documents(mut ctx, [schema.new_document('bad')], vectorstores.StoreOptions{}) or {
		assert err.msg().contains('object error')
		return
	}
	assert false, 'expected object-level batch failure to be reported'
}

fn test_weaviate_rejects_remote_http_and_reserved_metadata() {
	new_store(WeaviateFixtureEmbedder{}, Options{
		base_url:   'http://remote.example.test'
		class_name: 'Guide'
	}) or {
		assert err.msg().contains('HTTPS')
		return
	}
	assert false, 'expected remote HTTP endpoint to fail'
	mut state := &WeaviateFixtureState{}
	mut store := weaviate_fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	mut document := schema.new_document('reserved')
	document.metadata['text'] = 'conflict'
	store.add_documents(mut ctx, [document], vectorstores.StoreOptions{}) or {
		assert err.msg().contains('reserved')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected reserved metadata to fail'
}
