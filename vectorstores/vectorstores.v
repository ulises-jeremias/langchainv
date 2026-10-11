// Package vectorstores defines provider-neutral vector database contracts.
module vectorstores

import context
import json2
import math
import sync
import ulises_jeremias.langchainv.embeddings
import ulises_jeremias.langchainv.schema

// SearchOptions configures similarity queries.
pub struct SearchOptions {
pub mut:
	filter            map[string]json2.Any
	namespace         string
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

// InMemoryVectorStore is a bounded process-local vector store for tests and
// small workloads. It uses cosine similarity and a caller-provided embedder.
pub struct InMemoryVectorStore {
	state    &InMemoryVectorStoreState
	embedder embeddings.Embedder
}

struct InMemoryVectorStoreState {
mut:
	mutex         sync.Mutex
	entries       []VectorEntry
	next_id       u64
	max_documents int
}

struct VectorEntry {
	id        string
	namespace string
	document  schema.Document
	vector    []f32
}

// new_in_memory_vector_store creates a store with a required positive entry
// limit. It rejects additions that would exceed the limit rather than evicting
// existing documents.
pub fn new_in_memory_vector_store(embedder embeddings.Embedder, max_documents int) !InMemoryVectorStore {
	if max_documents <= 0 {
		return error('maximum document count must be greater than zero')
	}
	return InMemoryVectorStore{
		state:    &InMemoryVectorStoreState{
			max_documents: max_documents
		}
		embedder: embedder
	}
}

// add_documents embeds and stores documents, returning their generated IDs.
pub fn (store InMemoryVectorStore) add_documents(mut ctx context.Context, documents []schema.Document, options StoreOptions) ![]string {
	if documents.len == 0 {
		return []string{}
	}
	texts := documents.map(it.page_content)
	vectors := store.embedder.embed_documents(mut ctx, texts)!
	if vectors.len != documents.len {
		return error('embedder returned ${vectors.len} vectors for ${documents.len} documents')
	}
	mut dimension := -1
	for vector in vectors {
		if vector.len == 0 {
			return error('embedding vectors must not be empty')
		}
		if dimension < 0 {
			dimension = vector.len
		} else if vector.len != dimension {
			return error('embedding vector dimensions differ')
		}
		for value in vector {
			if !math.is_finite(f64(value)) {
				return error('embedding vectors must contain finite values')
			}
		}
	}
	mut state := store.state
	state.mutex.lock()
	if state.entries.len + documents.len > state.max_documents {
		state.mutex.unlock()
		return error('adding documents exceeds the store limit of ${state.max_documents}')
	}
	if state.entries.len > 0 && state.entries[0].vector.len != dimension {
		state.mutex.unlock()
		return error('embedding vector dimensions differ from vectors already in the store')
	}
	mut ids := []string{cap: documents.len}
	for index, document in documents {
		state.next_id++
		id := 'memory-${state.next_id}'
		ids << id
		state.entries << VectorEntry{
			id:        id
			namespace: options.namespace
			document:  clone_document(document)
			vector:    vectors[index].clone()
		}
	}
	state.mutex.unlock()
	return ids
}

// similarity_search returns up to limit documents ordered by cosine score.
pub fn (store InMemoryVectorStore) similarity_search(mut ctx context.Context, query string, limit int, options SearchOptions) ![]schema.Document {
	if limit < 0 {
		return error('search limit cannot be negative')
	}
	if limit == 0 {
		return []schema.Document{}
	}
	if options.include_vectors {
		return error('in-memory vector store does not return vectors')
	}
	if options.distance_strategy != '' && options.distance_strategy != 'cosine' {
		return error('in-memory vector store supports only cosine distance')
	}
	query_vector := store.embedder.embed_query(mut ctx, query)!
	if query_vector.len == 0 {
		return error('query embedding must not be empty')
	}
	for value in query_vector {
		if !math.is_finite(f64(value)) {
			return error('query embedding must contain finite values')
		}
	}
	mut state := store.state
	state.mutex.lock()
	entries := state.entries.clone()
	state.mutex.unlock()
	mut matches := []ScoredEntry{}
	for entry in entries {
		if entry.vector.len != query_vector.len {
			return error('query and document embedding dimensions differ')
		}
		if (options.namespace != '' && entry.namespace != options.namespace)
			|| !metadata_matches(entry.document.metadata, options.filter) {
			continue
		}
		score := embeddings.cosine_similarity(query_vector, entry.vector)!
		minimum := options.min_score or { f32(-1) }
		if score < minimum {
			continue
		}
		matches << ScoredEntry{
			document: clone_document(entry.document)
			score:    score
			id:       entry.id
		}
	}
	matches.sort(a.score > b.score)
	mut results := []schema.Document{cap: if limit < matches.len { limit } else { matches.len }}
	for index, result in matches {
		if index >= limit {
			break
		}
		mut document := result.document
		document.score = result.score
		if !options.include_metadata {
			document.metadata = map[string]json2.Any{}
		}
		results << document
	}
	return results
}

// delete removes documents matching IDs and optional namespace.
pub fn (store InMemoryVectorStore) delete(mut ctx context.Context, ids []string, options StoreOptions) ! {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	mut wanted := map[string]bool{}
	for id in ids {
		wanted[id] = true
	}
	mut state := store.state
	state.mutex.lock()
	mut retained := []VectorEntry{cap: state.entries.len}
	for entry in state.entries {
		if entry.id in wanted && (options.namespace == '' || entry.namespace == options.namespace) {
			continue
		}
		retained << entry
	}
	state.entries = retained
	state.mutex.unlock()
}

struct ScoredEntry {
	document schema.Document
	score    f32
	id       string
}

fn metadata_matches(metadata map[string]json2.Any, filter map[string]json2.Any) bool {
	for key, expected in filter {
		actual := metadata[key] or { return false }
		if actual.str() != expected.str() {
			return false
		}
	}
	return true
}

fn clone_document(document schema.Document) schema.Document {
	return schema.Document{
		page_content: document.page_content
		metadata:     clone_metadata(document.metadata)
		score:        document.score
	}
}

fn clone_metadata(metadata map[string]json2.Any) map[string]json2.Any {
	mut cloned := map[string]json2.Any{}
	for key, value in metadata {
		cloned[key] = clone_json_value(value)
	}
	return cloned
}

fn clone_json_value(value json2.Any) json2.Any {
	match value {
		[]json2.Any {
			mut cloned := []json2.Any{cap: value.len}
			for item in value {
				cloned << clone_json_value(item)
			}
			return json2.Any(cloned)
		}
		map[string]json2.Any {
			return json2.Any(clone_metadata(value))
		}
		else {
			return value
		}
	}
}
