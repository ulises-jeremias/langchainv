module milvus

import context
import json2
import net.http
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.vectorstores

struct MilvusFixtureEmbedder {}

fn (embedder MilvusFixtureEmbedder) embed_documents(mut _ctx context.Context, texts []string) ![][]f32 {
	return texts.map([f32(0.25), 0.75])
}

fn (embedder MilvusFixtureEmbedder) embed_query(mut _ctx context.Context, _text string) ![]f32 {
	return [f32(0.25), 0.75]
}

@[heap]
struct MilvusFixtureState {
mut:
	requests  []httputil.Request
	responses []httputil.Response
}

struct MilvusFixtureHTTP {
	state &MilvusFixtureState
}

fn (client MilvusFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	if state.responses.len == 0 {
		return error('unexpected Milvus request')
	}
	mut response := state.responses[0]
	state.responses.delete(0)
	if response.body.contains('__generated_id__') {
		payload := json2.decode[map[string]json2.Any](request.body, json2.DecoderOptions{}) or {
			return error('fixture received invalid insert JSON')
		}
		data_any := payload['data'] or { return error('fixture insert has no data') }
		if data_any !is []json2.Any || (data_any as []json2.Any).len == 0 {
			return error('fixture insert data must be a non-empty array')
		}
		first := (data_any as []json2.Any)[0]
		if first !is map[string]json2.Any {
			return error('fixture first insert row must be an object')
		}
		id_any := (first as map[string]json2.Any)['id'] or { return error('fixture insert row has no id') }
		if id_any !is string {
			return error('fixture insert ID must be a string')
		}
		response = httputil.Response{
			status_code: response.status_code
			headers:     response.headers
			body:        response.body.replace('__generated_id__', id_any as string)
		}
	}
	return response
}

fn fixture_store(state &MilvusFixtureState) !Store {
	mut store := new_store(MilvusFixtureEmbedder{}, Options{
		base_url:   'https://milvus.example.test'
		collection: 'docs'
		token:      'root:fixture'
	})!
	store.http_client = httputil.HTTPClient(MilvusFixtureHTTP{
		state: state
	})
	return store
}

fn test_milvus_inserts_documents_with_metadata_and_namespace() {
	mut state := &MilvusFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"code":0,"data":{"insertCount":1,"insertIds":["__generated_id__"]}}'
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
	assert request.method == .post
	assert request.url == 'https://milvus.example.test/v2/vectordb/entities/insert'
	assert (request.headers['Authorization'] or { '' }) == 'Bearer root:fixture'
	assert request.body.contains('tenant-1')
	assert request.body.contains('stored text')
	assert request.body.contains('[0.25,0.75]')
	assert request.body.contains('"kind":"guide"')
}

fn test_milvus_search_restores_document_and_applies_filter() {
	mut state := &MilvusFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"code":0,"data":[{"id":"vec-1","distance":0.91,"page_content":"answer","metadata":{"kind":"guide"},"namespace":"tenant-1"}]}'
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
	assert request.url.ends_with('/v2/vectordb/entities/search')
	assert request.body.contains('annsField')
	assert request.body.contains('metadata[\\"kind\\"]')
	assert request.body.contains('tenant-1')
}

fn test_milvus_deletes_ids_with_namespace_scope() {
	mut state := &MilvusFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"code":0,"data":{"deleteCount":1}}'
		}]
	}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.delete(mut ctx, ['vec-1'], vectorstores.StoreOptions{
		namespace: 'tenant-1'
	}) or { panic(err) }
	request := state.requests[0]
	assert request.url.ends_with('/v2/vectordb/entities/delete')
	assert request.body.contains('vec-1')
	assert request.body.contains('tenant-1')
}

fn test_milvus_rejects_invalid_urls_and_search_limits() {
	new_store(MilvusFixtureEmbedder{}, Options{
		base_url:   'http://milvus.example.test'
		collection: 'docs'
	}) or {
		assert err.msg().contains('HTTPS')
		return
	}
	assert false, 'expected a remote HTTP endpoint to fail'
	mut state := &MilvusFixtureState{}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.similarity_search(mut ctx, 'query', 1001, vectorstores.SearchOptions{}) or {
		assert err.msg().contains('between zero and 1000')
		assert state.requests.len == 0
		return
	}
	assert false, 'expected an over-limit search to fail'
}

fn test_milvus_rejects_nonzero_server_error_code() {
	mut state := &MilvusFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"code":1,"message":"failed"}'
		}]
	}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.add_documents(mut ctx, [schema.new_document('text')], vectorstores.StoreOptions{}) or {
		assert err.msg().contains('unsuccessful response')
		return
	}
	assert false, 'expected a nonzero Milvus response code to fail'
}

fn test_milvus_rejects_partial_insert_counts() {
	mut state := &MilvusFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"code":0,"data":{"insertCount":0,"insertIds":[]}}'
		}]
	}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.add_documents(mut ctx, [schema.new_document('text')], vectorstores.StoreOptions{}) or {
		assert err.msg().contains('inserted 0 of 1')
		return
	}
	assert false, 'expected a partial insert count to fail'
}
