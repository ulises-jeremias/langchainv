module vectorstores

import context
import json2
import ulises_jeremias.langchainv.schema

struct FixtureEmbedder {}

fn (embedder FixtureEmbedder) embed_documents(mut _ctx context.Context, texts []string) ![][]f32 {
	mut vectors := [][]f32{cap: texts.len}
	for text in texts {
		vectors << embed_fixture_text(text)
	}
	return vectors
}

fn (embedder FixtureEmbedder) embed_query(mut _ctx context.Context, text string) ![]f32 {
	return embed_fixture_text(text)
}

fn embed_fixture_text(text string) []f32 {
	return if text.starts_with('a') { [f32(1), 0] } else { [f32(0), 1] }
}

fn test_memory_vector_store_search_filter_namespace_and_delete() {
	mut ctx := context.background()
	mut store := new_in_memory_vector_store(FixtureEmbedder{}, 3) or { panic(err) }
	mut first := schema.new_document('alpha document')
	first.metadata['kind'] = json2.Any('guide')
	second := schema.new_document('beta document')
	store.add_documents(mut ctx, [first, second], StoreOptions{
		namespace: 'docs'
	}) or { panic(err) }
	third := schema.new_document('another alpha')
	store.add_documents(mut ctx, [third], StoreOptions{
		namespace: 'other'
	}) or { panic(err) }
	mut options := SearchOptions{
		namespace: 'docs'
	}
	results := store.similarity_search(mut ctx, 'alpha query', 2, options) or { panic(err) }
	assert results.len == 2
	assert results[0].page_content == 'alpha document'
	assert results[0].score > results[1].score
	options.filter['kind'] = json2.Any('guide')
	filtered := store.similarity_search(mut ctx, 'alpha query', 2, options) or { panic(err) }
	assert filtered.len == 1
	assert filtered[0].page_content == 'alpha document'
	store.delete(mut ctx, ['memory-1'], StoreOptions{
		namespace: 'docs'
	}) or { panic(err) }
	remaining := store.similarity_search(mut ctx, 'alpha query', 3, options) or { panic(err) }
	assert remaining.len == 0
}

fn test_memory_vector_store_enforces_capacity_and_options() {
	mut ctx := context.background()
	mut store := new_in_memory_vector_store(FixtureEmbedder{}, 1) or { panic(err) }
	store.add_documents(mut ctx, [schema.new_document('alpha')], StoreOptions{}) or { panic(err) }
	store.add_documents(mut ctx, [schema.new_document('beta')], StoreOptions{}) or {
		assert err.msg().contains('exceeds the store limit')
		return
	}
	assert false, 'expected capacity error'
	store.similarity_search(mut ctx, 'alpha', 1, SearchOptions{
		include_vectors: true
	}) or {
		assert err.msg().contains('does not return vectors')
		return
	}
	assert false, 'expected include_vectors option to fail'
}
