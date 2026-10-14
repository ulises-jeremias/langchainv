module mongodb

import context
import json2
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.vectorstores

struct FixtureEmbedder {}

fn (embedder FixtureEmbedder) embed_documents(mut _ctx context.Context, texts []string) ![][]f32 {
	return texts.map([f32(0.4), 0.6])
}

fn (embedder FixtureEmbedder) embed_query(mut _ctx context.Context, _text string) ![]f32 {
	return [f32(0.4), 0.6]
}

@[heap]
struct FakeState {
mut:
	documents []map[string]json2.Any
}

struct FakeCollection {
	state &FakeState
}

fn (collection FakeCollection) insert_documents(mut _ctx context.Context, documents []map[string]json2.Any) ![]string {
	mut state := collection.state
	mut ids := []string{}
	for document in documents {
		state.documents << document.clone()
		ids << (document['id'] or { json2.Any('') }).str()
	}
	return ids
}

fn (collection FakeCollection) find_documents(mut _ctx context.Context, filter map[string]json2.Any, limit int) ![]map[string]json2.Any {
	mut matched := []map[string]json2.Any{}
	for document in collection.state.documents {
		if fake_matches(document, filter) {
			matched << document.clone()
		}
	}
	if limit > 0 && matched.len > limit {
		matched = matched[..limit].clone()
	}
	return matched
}

fn (collection FakeCollection) delete_documents(mut _ctx context.Context, filter map[string]json2.Any) !int {
	mut state := collection.state
	mut kept := []map[string]json2.Any{}
	mut deleted := 0
	for document in state.documents {
		if fake_matches(document, filter) {
			deleted++
		} else {
			kept << document
		}
	}
	state.documents = kept
	return deleted
}

fn fake_matches(document map[string]json2.Any, filter map[string]json2.Any) bool {
	for key, expected in filter {
		actual := document[key] or { return false }
		if expected is map[string]json2.Any {
			conditions := expected as map[string]json2.Any
			if items := conditions['$in'] {
				mut found := false
				for item in items as []json2.Any {
					if item.str() == actual.str() {
						found = true
					}
				}
				if !found {
					return false
				}
				continue
			}
		}
		if actual.str() != expected.str() {
			return false
		}
	}
	return true
}

fn new_fixture_store(state &FakeState) Store {
	return new_store(FixtureEmbedder{}, FakeCollection{
		state: state
	}, Options{}) or { panic(err) }
}

fn test_mongo_store_adds_searches_and_deletes() {
	mut state := &FakeState{}
	mut store := new_fixture_store(state)
	mut ctx := context.background()
	mut first := schema.new_document('first text')
	second := schema.new_document('second text')
	first.metadata['kind'] = json2.Any('guide')
	ids := store.add_documents(mut ctx, [first, second], vectorstores.StoreOptions{
		namespace: 'tenant-1'
	}) or { panic(err) }
	assert ids.len == 2
	assert ids[0] != ids[1]

	results := store.similarity_search(mut ctx, 'first', 1, vectorstores.SearchOptions{
		namespace: 'tenant-1'
	}) or { panic(err) }
	assert results.len == 1
	assert results[0].score > f32(0.99)

	mut filter_options := vectorstores.SearchOptions{
		namespace: 'tenant-1'
	}
	filter_options.filter['kind'] = json2.Any('guide')
	filtered := store.similarity_search(mut ctx, 'first', 5, filter_options) or { panic(err) }
	assert filtered.len == 1
	assert filtered[0].page_content == 'first text'

	other_namespace := store.similarity_search(mut ctx, 'first', 5, vectorstores.SearchOptions{
		namespace: 'other'
	}) or { panic(err) }
	assert other_namespace.len == 0

	store.delete(mut ctx, ids, vectorstores.StoreOptions{
		namespace: 'tenant-1'
	}) or { panic(err) }
	assert state.documents.len == 0
	_ = vectorstores.VectorStore(store)
}

fn test_mongo_store_validates_limits_and_options() {
	mut state := &FakeState{}
	mut store := new_fixture_store(state)
	mut ctx := context.background()
	store.similarity_search(mut ctx, 'query', 1001, vectorstores.SearchOptions{}) or {
		assert err.msg().contains('limit')
		store.delete(mut ctx, []string{}, vectorstores.StoreOptions{}) or { panic(err) }
		return
	}
	assert false, 'expected an oversized limit to fail'
}

fn test_new_store_rejects_invalid_scan_limit() {
	mut state := &FakeState{}
	new_store(FixtureEmbedder{}, FakeCollection{
		state: state
	}, Options{
		max_scan_documents: -1
	}) or {
		assert err.msg().contains('max_scan_documents')
		return
	}
	assert false, 'expected an invalid scan limit to fail'
}
