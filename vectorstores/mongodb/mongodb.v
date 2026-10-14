// Package mongodb implements a bounded MongoDB-backed vector store.
module mongodb

import context
import json2
import math
import rand
import ulises_jeremias.langchainv.embeddings
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.vectorstores

const default_max_scan_documents = 10000
const max_scan_documents_limit = 100000
const max_add_documents = 1000
const max_search_limit = 1000
const max_delete_ids = 1000

// MongoCollection is the narrow set of collection operations the store
// needs. A caller adapts a real MongoDB driver collection to this interface.
// Filters use equality matches and `$in` lists only.
pub interface MongoCollection {
	insert_documents(mut ctx context.Context, documents []map[string]json2.Any) ![]string
	find_documents(mut ctx context.Context, filter map[string]json2.Any, limit int) ![]map[string]json2.Any
	delete_documents(mut ctx context.Context, filter map[string]json2.Any) !int
}

// Options configures how many stored documents a search may scan.
pub struct Options {
pub:
	max_scan_documents int = default_max_scan_documents
}

// Store stores documents in an injected MongoDB collection and searches them
// with bounded in-process cosine scoring over at most max_scan_documents
// documents per query. It does not use Atlas $vectorSearch; collections
// larger than the scan bound need a server-side search adapter instead.
pub struct Store {
	embedder           embeddings.Embedder
	collection         MongoCollection
	max_scan_documents int
}

// new_store constructs a store over an injected embedder and collection.
pub fn new_store(embedder embeddings.Embedder, collection MongoCollection, options Options) !Store {
	if options.max_scan_documents < 1 || options.max_scan_documents > max_scan_documents_limit {
		return error('MongoDB max_scan_documents must be between 1 and ${max_scan_documents_limit}')
	}
	return Store{
		embedder:           embedder
		collection:         collection
		max_scan_documents: options.max_scan_documents
	}
}

// add_documents embeds documents and stores them with generated UUIDs.
pub fn (store Store) add_documents(mut ctx context.Context, documents []schema.Document, options vectorstores.StoreOptions) ![]string {
	if documents.len == 0 {
		return []string{}
	}
	if documents.len > max_add_documents {
		return error('MongoDB add_documents is limited to ${max_add_documents} documents per call')
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
	mut stored := []map[string]json2.Any{cap: documents.len}
	mut ids := []string{cap: documents.len}
	for index, document in documents {
		id := rand.uuid_v4()
		ids << id
		mut embedding := []json2.Any{cap: vectors[index].len}
		for value in vectors[index] {
			embedding << json2.Any(f64(value))
		}
		stored << {
			'id':           json2.Any(id)
			'namespace':    json2.Any(options.namespace)
			'page_content': json2.Any(document.page_content)
			'metadata':     json2.Any(document.metadata.clone())
			'embedding':    json2.Any(embedding)
		}
	}
	inserted := store.collection.insert_documents(mut ctx, stored)!
	if inserted.len != documents.len {
		return error('MongoDB inserted ${inserted.len} documents for ${documents.len} inputs')
	}
	return inserted
}

// similarity_search scans up to the configured document bound in the
// namespace, filters by scalar metadata equality, and ranks by cosine score.
pub fn (store Store) similarity_search(mut ctx context.Context, query string, limit int, options vectorstores.SearchOptions) ![]schema.Document {
	if limit < 0 || limit > max_search_limit {
		return error('MongoDB search limit must be between zero and ${max_search_limit}')
	}
	if limit == 0 {
		return []schema.Document{}
	}
	if options.distance_strategy != '' && options.distance_strategy != 'cosine' {
		return error('MongoDB vector store supports only cosine distance')
	}
	query_vector := store.embedder.embed_query(mut ctx, query)!
	if query_vector.len == 0 {
		return error('MongoDB query embedding must not be empty')
	}
	for value in query_vector {
		if !math.is_finite(f64(value)) {
			return error('MongoDB query embedding must contain finite values')
		}
	}
	mut filter := map[string]json2.Any{}
	if options.namespace != '' {
		filter['namespace'] = json2.Any(options.namespace)
	}
	documents := store.collection.find_documents(mut ctx, filter, store.max_scan_documents)!
	mut matches := []ScoredDocument{}
	for document in documents {
		content_any := document['page_content'] or {
			return error('MongoDB stored document has no page_content')
		}
		if content_any !is string {
			return error('MongoDB stored page_content must be a string')
		}
		metadata_any := document['metadata'] or { json2.Any(map[string]json2.Any{}) }
		if metadata_any !is map[string]json2.Any {
			return error('MongoDB stored metadata must be an object')
		}
		metadata := metadata_any as map[string]json2.Any
		if !metadata_matches(metadata, options.filter) {
			continue
		}
		embedding := stored_embedding(document)!
		if embedding.len != query_vector.len {
			return error('MongoDB stored and query embedding dimensions differ')
		}
		score := embeddings.cosine_similarity(query_vector, embedding)!
		minimum := options.min_score or { f32(-1) }
		if score < minimum {
			continue
		}
		matches << ScoredDocument{
			content:   content_any as string
			metadata:  metadata.clone()
			embedding: embedding
			score:     score
		}
	}
	matches.sort(a.score > b.score)
	mut results := []schema.Document{cap: if limit < matches.len { limit } else { matches.len }}
	for index, matched in matches {
		if index >= limit {
			break
		}
		results << schema.Document{
			page_content: matched.content
			metadata:     if options.include_metadata {
				matched.metadata.clone()
			} else {
				map[string]json2.Any{}
			}
			score:        matched.score
			embedding:    if options.include_vectors { matched.embedding.clone() } else { []f32{} }
		}
	}
	return results
}

// delete removes documents by generated ID, optionally within one namespace.
pub fn (store Store) delete(mut ctx context.Context, ids []string, options vectorstores.StoreOptions) ! {
	if ids.len == 0 {
		return
	}
	if ids.len > max_delete_ids {
		return error('MongoDB delete is limited to ${max_delete_ids} IDs per call')
	}
	mut id_values := []json2.Any{cap: ids.len}
	for id in ids {
		if id.trim_space() == '' {
			return error('MongoDB delete IDs must not be empty')
		}
		id_values << json2.Any(id)
	}
	mut filter := map[string]json2.Any{}
	filter['id'] = json2.Any({
		'$in': json2.Any(id_values)
	})
	if options.namespace != '' {
		filter['namespace'] = json2.Any(options.namespace)
	}
	store.collection.delete_documents(mut ctx, filter)!
}

struct ScoredDocument {
	content   string
	metadata  map[string]json2.Any
	embedding []f32
	score     f32
}

fn stored_embedding(document map[string]json2.Any) ![]f32 {
	embedding_any := document['embedding'] or {
		return error('MongoDB stored document has no embedding')
	}
	if embedding_any !is []json2.Any {
		return error('MongoDB stored embedding must be an array')
	}
	values := embedding_any as []json2.Any
	if values.len == 0 {
		return error('MongoDB stored embedding must not be empty')
	}
	mut embedding := []f32{cap: values.len}
	for value in values {
		match value {
			f64 {
				if !math.is_finite(value as f64) {
					return error('MongoDB stored embedding must contain finite values')
				}
				embedding << f32(value as f64)
			}
			int {
				embedding << f32(value as int)
			}
			else {
				return error('MongoDB stored embedding must contain numbers')
			}
		}
	}
	return embedding
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
