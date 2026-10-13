module pinecone

import context
import json2
import net.http
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.vectorstores

struct PineconeFixtureEmbedder {}

fn (embedder PineconeFixtureEmbedder) embed_documents(mut _ctx context.Context, texts []string) ![][]f32 {
	return texts.map([f32(0.4), 0.6])
}

fn (embedder PineconeFixtureEmbedder) embed_query(mut _ctx context.Context, _text string) ![]f32 {
	return [f32(0.4), 0.6]
}

@[heap]
struct PineconeFixtureState {
mut:
	requests  []httputil.Request
	responses []httputil.Response
}

struct PineconeFixtureHTTP {
	state &PineconeFixtureState
}

fn (client PineconeFixtureHTTP) do(mut _ctx context.Context, request httputil.Request) !httputil.Response {
	mut state := client.state
	state.requests << request
	if state.responses.len == 0 {
		return error('unexpected Pinecone request')
	}
	response := state.responses[0]
	state.responses.delete(0)
	return response
}

fn fixture_store(state &PineconeFixtureState) !Store {
	mut store := new_store(PineconeFixtureEmbedder{}, Options{
		host:    'https://index.example.test'
		api_key: 'fixture-key'
	})!
	store.http_client = httputil.HTTPClient(PineconeFixtureHTTP{
		state: state
	})
	return store
}

fn test_pinecone_upserts_metadata_and_namespace() {
	mut state := &PineconeFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"upsertedCount":1}'
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
	assert state.requests.len == 1
	request := state.requests[0]
	assert request.method == .post
	assert request.url == 'https://index.example.test/vectors/upsert'
	assert (request.headers['Api-Key'] or { '' }) == 'fixture-key'
	assert (request.headers['X-Pinecone-Api-Version'] or { '' }) == api_version
	assert request.body.contains('tenant-1')
	assert request.body.contains('stored text')
	assert request.body.contains('[0.4,0.6]')
}

fn test_pinecone_query_restores_content_filters_and_score() {
	mut state := &PineconeFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"matches":[{"id":"vec-1","score":0.91,"metadata":{"kind":"guide","_langchainv_page_content":"answer"}}]}'
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
	assert '_langchainv_page_content' !in documents[0].metadata
	assert state.requests[0].url == 'https://index.example.test/query'
	assert state.requests[0].body.contains('topK')
	assert state.requests[0].body.contains('\$eq')
	assert state.requests[0].body.contains('tenant-1')
}

fn test_pinecone_query_returns_vectors_when_requested() {
	mut state := &PineconeFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"matches":[{"id":"vec-1","score":0.91,"metadata":{"_langchainv_page_content":"answer"},"values":[0.4,0.6]}]}'
		}]
	}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	documents := store.similarity_search(mut ctx, 'query', 3, vectorstores.SearchOptions{
		include_vectors: true
	}) or { panic(err) }
	assert documents.len == 1
	assert documents[0].embedding == [f32(0.4), f32(0.6)]
	assert state.requests[0].body.contains('"includeValues":true')
}

fn test_pinecone_rejects_non_numeric_returned_vector_values() {
	mut state := &PineconeFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"matches":[{"id":"vec-1","score":0.91,"metadata":{"_langchainv_page_content":"answer"},"values":[0.4,"bad"]}]}'
		}]
	}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.similarity_search(mut ctx, 'query', 1, vectorstores.SearchOptions{
		include_vectors: true
	}) or {
		assert err.msg().contains('finite numbers')
		return
	}
	assert false, 'expected malformed Pinecone vector to fail'
}

fn test_pinecone_deletes_ids_from_namespace() {
	mut state := &PineconeFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{}'
		}]
	}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.delete(mut ctx, ['vec-1', 'vec-2'], vectorstores.StoreOptions{
		namespace: 'tenant-1'
	}) or { panic(err) }
	assert state.requests[0].url.ends_with('/vectors/delete')
	assert state.requests[0].body.contains('vec-1')
	assert state.requests[0].body.contains('tenant-1')
}

fn test_pinecone_rejects_invalid_hosts_and_limits() {
	new_store(PineconeFixtureEmbedder{}, Options{
		host:    'http://index.example.test'
		api_key: 'fixture-key'
	}) or {
		assert err.msg().contains('https')
		return
	}
	assert false, 'expected insecure host to fail'
	mut state := &PineconeFixtureState{}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.similarity_search(mut ctx, 'query', 1001, vectorstores.SearchOptions{}) or {
		assert err.msg().contains('between zero and 1000')
		return
	}
	assert false, 'expected over-limit search to fail'
}

fn test_pinecone_query_sends_operator_filters() {
	mut state := &PineconeFixtureState{
		responses: [httputil.Response{
			status_code: 200
			headers:     http.Header{}
			body:        '{"matches":[]}'
		}]
	}
	mut store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	documents := store.similarity_search(mut ctx, 'query', 3, vectorstores.SearchOptions{
		filter: {
			'year': json2.Any({
				'$gte': json2.Any(2020)
				'$lt':  json2.Any(2030)
			})
			'kind': json2.Any({
				'$in': json2.Any([json2.Any('guide'), json2.Any('api')])
			})
			'$or':  json2.Any([
				json2.Any({
					'lang': json2.Any('v')
				}),
				json2.Any({
					'lang': json2.Any('go')
				}),
			])
		}
	}) or { panic(err) }
	assert documents.len == 0
	body := state.requests[0].body
	assert body.contains('"$gte":2020')
	assert body.contains('"$in":["guide","api"]')
	assert body.contains('"$or":[{"lang":{"$eq":"v"}},{"lang":{"$eq":"go"}}]')
}

fn test_pinecone_query_rejects_invalid_operator_filters() {
	mut ctx := context.background()
	for filter in [
		{
			'kind': json2.Any({
				'$regex': json2.Any('^g')
			})
		},
		{
			'kind': json2.Any({
				'$in': json2.Any([]json2.Any{})
			})
		},
		{
			'$nor': json2.Any([json2.Any({
				'kind': json2.Any('guide')
			})])
		},
	] {
		mut state := &PineconeFixtureState{}
		mut store := fixture_store(state) or { panic(err) }
		store.similarity_search(mut ctx, 'query', 3, vectorstores.SearchOptions{
			filter: filter
		}) or {
			assert err.msg().contains('Pinecone filter')
			assert state.requests.len == 0
			continue
		}
		assert false, 'expected invalid Pinecone filter to fail'
	}
}
