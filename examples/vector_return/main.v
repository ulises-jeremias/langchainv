module main

import context
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.vectorstores

struct DemoEmbedder {}

fn (_ DemoEmbedder) embed_documents(mut _ctx context.Context, texts []string) ![][]f32 {
	return texts.map([f32(it.len), f32(1)])
}

fn (_ DemoEmbedder) embed_query(mut _ctx context.Context, text string) ![]f32 {
	return [f32(text.len), f32(1)]
}

fn main() {
	mut ctx := context.background()
	mut store := vectorstores.new_in_memory_vector_store(DemoEmbedder{}, 4) or { panic(err) }
	store.add_documents(mut ctx, [
		schema.new_document('vector stores keep embeddings'),
		schema.new_document('search results omit embeddings by default'),
	], vectorstores.StoreOptions{}) or { panic(err) }
	results := store.similarity_search(mut ctx, 'retrieve embeddings', 2, vectorstores.SearchOptions{
		include_vectors: true
	}) or { panic(err) }
	for document in results {
		println('${document.page_content}: ${document.embedding}')
	}
}
