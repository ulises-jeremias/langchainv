// Package dolt implements a bounded vector store over Dolt's MySQL interface.
module dolt

import context
import json2
import math
import rand
import strconv
import ulises_jeremias.langchainv.embeddings
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.tools.sqldatabase
import ulises_jeremias.langchainv.vectorstores

const default_database_name = 'langchain'
const default_embedding_table = 'langchain_dolt_embedding'
const default_collection_table = 'langchain_dolt_collection'
const default_vector_index = 'langchain_dolt_embedding_idx'
const max_payload_bytes = 4 * 1024 * 1024
const max_documents_per_write = 32
const max_search_limit = 1000
const max_embedding_values = 2000

// Options names the two tables and the optional Dolt vector index. The index
// is never built by a constructor or table initializer.
pub struct Options {
pub:
	database_name    string = default_database_name
	embedding_table  string = default_embedding_table
	collection_table string = default_collection_table
	vector_index     string = default_vector_index
}

// Store uses existing Dolt tables through a caller-owned MySQL-compatible SQL
// engine. Vector search requires an explicit Dolt VECTOR INDEX.
pub struct Store {
pub:
	database_name    string
	embedding_table  string
	collection_table string
pub mut:
	embedder embeddings.Embedder
	engine   sqldatabase.Engine
}

// initialize_tables creates the collection and embedding tables if missing.
// It does not delete data or build the potentially expensive approximate index.
pub fn initialize_tables(mut ctx context.Context, engine sqldatabase.Engine, options Options) ! {
	validate_options(options)!
	if engine.dialect() != 'mysql' {
		return error('Dolt vector store requires a MySQL-compatible engine')
	}
	collection_sql := 'CREATE TABLE IF NOT EXISTS ${quote(options.collection_table)} (name varchar(720) NOT NULL, cmetadata json NOT NULL, `uuid` varchar(36) NOT NULL, UNIQUE KEY uq_langchain_dolt_collection_name (name), PRIMARY KEY (`uuid`))'
	engine.query(mut ctx, collection_sql) or {
		return error('could not initialize Dolt collection table')
	}
	embedding_sql := 'CREATE TABLE IF NOT EXISTS ${quote(options.embedding_table)} (collection_id varchar(36) NOT NULL, embedding json NOT NULL, document longtext NOT NULL, cmetadata json NOT NULL, `uuid` varchar(36) NOT NULL, CONSTRAINT fk_langchain_dolt_collection FOREIGN KEY (collection_id) REFERENCES ${quote(options.collection_table)} (`uuid`) ON DELETE CASCADE, PRIMARY KEY (`uuid`))'
	engine.query(mut ctx, embedding_sql) or {
		return error('could not initialize Dolt embedding table')
	}
}

// create_vector_index explicitly builds Dolt's approximate vector index. Dolt
// documents JSON vector-index builds as alpha and potentially expensive, so
// callers invoke this only after deciding the database can absorb that work.
// Repeated calls are idempotent when information_schema reports the index.
pub fn create_vector_index(mut ctx context.Context, engine sqldatabase.Engine, options Options) ! {
	validate_options(options)!
	if engine.dialect() != 'mysql' {
		return error('Dolt vector store requires a MySQL-compatible engine')
	}
	result := engine.query_params(mut ctx, 'SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = ? AND index_name = ?', [
		options.embedding_table,
		options.vector_index,
	]) or { return error('could not inspect the Dolt vector index') }
	if result.rows.len != 1 || result.rows[0].len != 1 {
		return error('Dolt returned an invalid vector index inventory')
	}
	count := strconv.atoi(result.rows[0][0]) or {
		return error('Dolt returned an invalid vector index count')
	}
	if count > 0 {
		return
	}
	statement := 'ALTER TABLE ${quote(options.embedding_table)} ADD VECTOR INDEX ${quote(options.vector_index)} (${quote('embedding')})'
	engine.query(mut ctx, statement) or {
		return error('could not create the Dolt vector index')
	}
}

// new_store binds an embedder to a caller-owned MySQL-compatible Dolt engine.
// The collection name and tables are selected at request time, and no DDL runs.
pub fn new_store(embedder embeddings.Embedder, engine sqldatabase.Engine, options Options) !Store {
	validate_options(options)!
	if engine.dialect() != 'mysql' {
		return error('Dolt vector store requires a MySQL-compatible engine')
	}
	return Store{
		database_name:    options.database_name
		embedding_table:  options.embedding_table
		collection_table: options.collection_table
		embedder:         embedder
		engine:           engine
	}
}

fn validate_options(options Options) ! {
	identifiers := [options.database_name, options.embedding_table, options.collection_table,
		options.vector_index]
	for identifier in identifiers {
		if !valid_identifier(identifier) {
			return error('Dolt table, collection, and index names must be simple SQL identifiers')
		}
	}
	if options.embedding_table == options.collection_table {
		return error('Dolt collection and embedding tables must have distinct names')
	}
}

// add_documents embeds and inserts at most 32 documents, returning their IDs.
// A missing collection row is created with INSERT IGNORE before document rows.
pub fn (store Store) add_documents(mut ctx context.Context, documents []schema.Document, options vectorstores.StoreOptions) ![]string {
	if documents.len == 0 {
		return []string{}
	}
	if documents.len > max_documents_per_write {
		return error('Dolt writes are limited to ${max_documents_per_write} documents per call')
	}
	collection := if options.namespace == '' { store.database_name } else { options.namespace }
	if collection.len > 720 || collection.contains('\0') {
		return error('Dolt collection name must be at most 720 bytes and contain no NUL')
	}
	mut payload_bytes := 0
	for document in documents {
		metadata_json := json2.encode(document.metadata, json2.EncoderOptions{})
		if document.page_content.len > 65536 || metadata_json.len > 65536 {
			return error('Dolt document content and metadata are limited to 64 KiB each')
		}
		payload_bytes += document.page_content.len + metadata_json.len + 128
		if payload_bytes > max_payload_bytes {
			return error('Dolt write payload exceeds 4 MiB')
		}
	}
	vectors := store.embedder.embed_documents(mut ctx, documents.map(it.page_content))!
	if vectors.len != documents.len {
		return error('embedder returned ${vectors.len} vectors for ${documents.len} documents')
	}
	mut dimension := 0
	mut encoded_vectors := []string{cap: vectors.len}
	for vector in vectors {
		if vector.len == 0 || vector.len > max_embedding_values || (dimension > 0 && vector.len != dimension) {
			return error('Dolt embeddings must be non-empty, bounded, and dimensionally consistent')
		}
		dimension = vector.len
		mut squared_norm := f64(0)
		for value in vector {
			if !math.is_finite(f64(value)) {
				return error('Dolt embeddings must contain finite values')
			}
			squared_norm += f64(value) * f64(value)
		}
		if squared_norm == 0 {
			return error('Dolt embeddings must not be zero vectors')
		}
		encoded := json2.encode(vector, json2.EncoderOptions{})
		payload_bytes += encoded.len + 16
		if payload_bytes > max_payload_bytes {
			return error('Dolt write payload exceeds 4 MiB')
		}
		encoded_vectors << encoded
	}
	collection_id := rand.uuid_v4()
	collection_metadata := '{}'
	store.engine.query_params(mut ctx, 'INSERT IGNORE INTO ${quote(store.collection_table)} (`uuid`, name, cmetadata) VALUES (?, ?, CAST(? AS JSON))', [
		collection_id,
		collection,
		collection_metadata,
	]) or { return error('could not select the Dolt collection') }
	mut ids := []string{cap: documents.len}
	mut tuples := []string{cap: documents.len}
	mut parameters := []string{cap: documents.len * 5}
	for index, document in documents {
		id := rand.uuid_v4()
		ids << id
		tuples << '(?, ?, CAST(? AS JSON), CAST(? AS JSON), (SELECT `uuid` FROM ${quote(store.collection_table)} WHERE name = ?))'
		parameters << id
		parameters << document.page_content
		parameters << encoded_vectors[index]
		parameters << json2.encode(document.metadata, json2.EncoderOptions{})
		parameters << collection
	}
	statement := 'INSERT INTO ${quote(store.embedding_table)} (`uuid`, document, embedding, cmetadata, collection_id) VALUES ${tuples.join(', ')}'
	if statement.len + parameter_bytes(parameters) > max_payload_bytes {
		return error('Dolt write payload exceeds 4 MiB')
	}
	store.engine.query_params(mut ctx, statement, parameters) or {
		return error('could not insert Dolt documents')
	}
	return ids
}

// similarity_search returns up to limit documents ranked by Dolt's
// squared-Euclidean VECTOR INDEX distance (score is 1 - distance).
pub fn (store Store) similarity_search(mut ctx context.Context, query string, limit int, options vectorstores.SearchOptions) ![]schema.Document {
	if limit < 0 || limit > max_search_limit {
		return error('Dolt search limit must be between zero and ${max_search_limit}')
	}
	if limit == 0 {
		return []schema.Document{}
	}
	if query.len > 65536 || options.namespace.len > 720 || options.filter.len > 64 {
		return error('Dolt query, collection, or filter count exceeds configured limits')
	}
	if options.distance_strategy != '' && options.distance_strategy.to_lower() !in [
		'euclidean',
		'euclidean_squared',
	] {
		return error('Dolt vector index supports squared Euclidean distance only')
	}
	if options.min_score != none {
		threshold := options.min_score or { f32(0) }
		if !math.is_finite(f64(threshold)) || threshold < 0 || threshold > 1 {
			return error('Dolt minimum score must be finite and between zero and one')
		}
	}
	for key, value in options.filter {
		if !valid_identifier(key) || !valid_scalar(value) {
			return error('Dolt filters support scalar metadata equality with simple keys')
		}
		if value is string && (value as string).len > 4096 {
			return error('Dolt filter values are limited to 4 KiB')
		}
	}
	vector := store.embedder.embed_query(mut ctx, query)!
	if vector.len == 0 || vector.len > max_embedding_values {
		return error('Dolt query embedding must contain between 1 and ${max_embedding_values} values')
	}
	mut squared_norm := f64(0)
	for value in vector {
		if !math.is_finite(f64(value)) {
			return error('Dolt query embedding must contain finite values')
		}
		squared_norm += f64(value) * f64(value)
	}
	if squared_norm == 0 {
		return error('Dolt query embedding must not be a zero vector')
	}
	collection := if options.namespace == '' { store.database_name } else { options.namespace }
	vector_json := json2.encode(vector, json2.EncoderOptions{})
	mut parameters := [vector_json, collection]
	mut predicates := []string{}
	for key, value in options.filter {
		parameters << '$.${key}'
		parameters << json2.encode(value, json2.EncoderOptions{})
		predicates << 'JSON_EXTRACT(e.cmetadata, ?) = CAST(? AS JSON)'
	}
	if threshold := options.min_score {
		if threshold > 0 {
			parameters << vector_json
			parameters << (1.0 - f64(threshold)).str()
			predicates << 'VEC_DISTANCE(e.embedding, CAST(? AS JSON)) <= ?'
		}
	}
	where_clause := if predicates.len == 0 { 'TRUE' } else { predicates.join(' AND ') }
	parameters << vector_json
	parameters << limit.str()
	vector_select := if options.include_vectors { ', e.embedding' } else { '' }
	statement := 'SELECT e.document, e.cmetadata, 1 - VEC_DISTANCE(e.embedding, CAST(? AS JSON)) AS score${vector_select} FROM ${quote(store.embedding_table)} AS e INNER JOIN ${quote(store.collection_table)} AS c ON e.collection_id = c.`uuid` WHERE c.name = ? AND ${where_clause} ORDER BY VEC_DISTANCE(e.embedding, CAST(? AS JSON)) ASC LIMIT ?'
	if statement.len + parameter_bytes(parameters) > max_payload_bytes {
		return error('Dolt search request exceeds 4 MiB')
	}
	result := store.engine.query_params(mut ctx, statement, parameters) or {
		return error('Dolt similarity search failed; verify the vector index and Dolt version')
	}
	if result.rows.len > limit {
		return error('Dolt returned more documents than requested')
	}
	mut documents := []schema.Document{cap: result.rows.len}
	mut response_bytes := 0
	columns := if options.include_vectors { 4 } else { 3 }
	for row in result.rows {
		if row.len != columns {
			return error('Dolt returned a malformed search row')
		}
		response_bytes += row[0].len + row[1].len + row[2].len + 128
		if options.include_vectors {
			response_bytes += row[3].len
		}
		if response_bytes > max_payload_bytes {
			return error('Dolt search response exceeds 4 MiB')
		}
		metadata := json2.decode[map[string]json2.Any](row[1], json2.DecoderOptions{}) or {
			return error('Dolt returned invalid metadata JSON')
		}
		score := strconv.atof64(row[2]) or { return error('Dolt returned a non-numeric score') }
		if !math.is_finite(score) || !math.is_finite(f64(f32(score))) {
			return error('Dolt returned a non-finite score')
		}
		mut embedding := []f32{}
		if options.include_vectors {
			embedding = json2.decode[[]f32](row[3], json2.DecoderOptions{}) or {
				return error('Dolt returned invalid embedding JSON')
			}
			if embedding.len == 0 || embedding.len > max_embedding_values {
				return error('Dolt returned an invalid embedding dimension')
			}
			for value in embedding {
				if !math.is_finite(f64(value)) {
					return error('Dolt returned a non-finite embedding value')
				}
			}
		}
		documents << schema.Document{
			page_content: row[0]
			metadata:     if options.include_metadata { metadata } else { map[string]json2.Any{} }
			score:        f32(score)
			embedding:    embedding
		}
	}
	return documents
}

// delete removes at most 1,000 documents by ID from the selected collection.
pub fn (store Store) delete(mut ctx context.Context, ids []string, options vectorstores.StoreOptions) ! {
	if ids.len == 0 {
		return
	}
	if ids.len > 1000 {
		return error('Dolt delete is limited to 1,000 IDs per call')
	}
	collection := if options.namespace == '' { store.database_name } else { options.namespace }
	if collection.len > 720 || collection.contains('\0') {
		return error('Dolt collection name must be at most 720 bytes and contain no NUL')
	}
	mut placeholders := []string{cap: ids.len}
	mut parameters := [collection]
	for id in ids {
		if id.trim_space() == '' || id.len > 512 {
			return error('Dolt document IDs must be non-empty and at most 512 bytes')
		}
		placeholders << '?'
		parameters << id
	}
	statement := 'DELETE e FROM ${quote(store.embedding_table)} AS e INNER JOIN ${quote(store.collection_table)} AS c ON e.collection_id = c.`uuid` WHERE c.name = ? AND e.`uuid` IN (${placeholders.join(', ')})'
	store.engine.query_params(mut ctx, statement, parameters) or {
		return error('could not delete Dolt documents')
	}
}

fn valid_identifier(value string) bool {
	if value.len == 0 || value.len > 64 {
		return false
	}
	for index, ch in value.bytes() {
		if !((ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || ch == `_`
			|| (index > 0 && ch >= `0` && ch <= `9`)) {
			return false
		}
	}
	return true
}

fn valid_scalar(value json2.Any) bool {
	match value {
		string, bool, int, i64, f64 {
			if value is f64 && !math.is_finite(value as f64) {
				return false
			}
			return true
		}
		else {
			return false
		}
	}
}

fn quote(identifier string) string {
	return '`${identifier}`'
}

fn parameter_bytes(parameters []string) int {
	mut result := 0
	for parameter in parameters {
		result += parameter.len
	}
	return result
}
