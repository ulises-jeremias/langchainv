// Package vectorstores defines provider-neutral vector database contracts.
module vectorstores

import context
import json2
import ulises_jeremias.langchainv.schema

// SearchOptions configures similarity queries.
pub struct SearchOptions {
pub mut:
	filter            map[string]json2.Any
	include_metadata  bool = true
	include_vectors   bool
	min_score         ?f32
	distance_strategy string
}

// StoreOptions configures document insertion and search behavior.
pub struct StoreOptions {
pub mut:
	namespace string
	search    SearchOptions
}

// VectorStore stores documents and retrieves the nearest matches.
pub interface VectorStore {
	add_documents(mut ctx context.Context, documents []schema.Document, options StoreOptions) ![]string
	similarity_search(mut ctx context.Context, query string, limit int, options SearchOptions) ![]schema.Document
	delete(mut ctx context.Context, ids []string, options StoreOptions) !
}

// Retriever adapts a vector store to the shared retriever interface.
pub struct Retriever {
pub:
	store VectorStore
pub mut:
	num_documents int = 4
	options       SearchOptions
}

// get_relevant_documents searches the configured store for a query.
pub fn (retriever Retriever) get_relevant_documents(mut ctx context.Context, query string, options schema.RetrievalOptions) ![]schema.Document {
	limit := if options.k > 0 { options.k } else { retriever.num_documents }
	mut search := retriever.options
	if options.filter.len > 0 {
		search.filter = options.filter.clone()
	}
	return retriever.store.similarity_search(mut ctx, query, limit, search)
}

// to_retriever creates a retriever backed by a vector store.
pub fn to_retriever(store VectorStore, num_documents int, options SearchOptions) !Retriever {
	if num_documents < 0 {
		return error('number of documents cannot be negative')
	}
	return Retriever{
		store:         store
		num_documents: if num_documents == 0 { 4 } else { num_documents }
		options:       options
	}
}
