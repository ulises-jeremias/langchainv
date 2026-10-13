// Package mariadb implements a bounded MariaDB vector-store adapter.
module mariadb

import context
import json2
import math
import rand
import strconv
import ulises_jeremias.langchainv.embeddings
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.tools.sqldatabase
import ulises_jeremias.langchainv.vectorstores

const max_documents_per_write = 64
const max_payload_bytes = 4 * 1024 * 1024
const max_search_limit = 1000
const max_embedding_values = 2000
const max_index_dimensions = 2000

// Store uses a MariaDB table with a VECTOR column.
pub struct Store {
pub:
	table            string
	id_column        string
	text_column      string
	metadata_column  string
	namespace_column string
	vector_column    string
pub mut:
	embedder embeddings.Embedder
	engine   sqldatabase.Engine
}

// Options configures a MariaDB table, vector index, and document columns.
pub struct Options {
pub:
	table            string = 'langchainv_documents'
	vector_index     string = 'langchainv_embedding_idx'
	id_column        string = 'id'
	text_column      string = 'page_content'
	metadata_column  string = 'metadata'
	namespace_column string = 'namespace'
	vector_column    string = 'embedding'
}

// initialize_table explicitly creates a table if missing, without adding an
// index or changing an existing table. dimensions must match the embedder.
pub fn initialize_table(mut ctx context.Context, engine sqldatabase.Engine, options Options, dimensions int) ! {
	validate_options(options, dimensions)!
	validate_engine(engine)!
	statement := 'CREATE TABLE IF NOT EXISTS ${quote(options.table)} (${quote(options.id_column)} VARCHAR(36) NOT NULL PRIMARY KEY, ${quote(options.text_column)} LONGTEXT NOT NULL, ${quote(options.metadata_column)} JSON NOT NULL, ${quote(options.namespace_column)} TEXT NOT NULL, ${quote(options.vector_column)} VECTOR(${dimensions}) NOT NULL)'
	engine.query(mut ctx, statement) or {
		return error('could not initialize MariaDB vector table')
	}
}

// create_vector_index explicitly adds an approximate cosine vector index.
// Index builds may consume substantial server memory and scan existing rows.
// Repeated calls are idempotent when information_schema reports this index.
pub fn create_vector_index(mut ctx context.Context, engine sqldatabase.Engine, options Options) ! {
	validate_options(options, 1)!
	validate_engine(engine)!
	result := engine.query_params(mut ctx, 'SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = ? AND index_name = ?', [
		options.table,
		options.vector_index,
	]) or { return error('could not inspect the MariaDB vector index') }
	if result.rows.len != 1 || result.rows[0].len != 1 {
		return error('MariaDB returned an invalid vector index inventory')
	}
	count := strconv.atoi(result.rows[0][0]) or {
		return error('MariaDB returned an invalid vector index count')
	}
	if count > 0 {
		return
	}
	statement := 'ALTER TABLE ${quote(options.table)} ADD VECTOR INDEX ${quote(options.vector_index)} (${quote(options.vector_column)}) M=8 DISTANCE=cosine'
	engine.query(mut ctx, statement) or {
		return error('could not create the MariaDB cosine vector index')
	}
}

// new_store binds an embedder to an existing MariaDB SQL engine.
pub fn new_store(embedder embeddings.Embedder, engine sqldatabase.Engine, options Options) !Store {
	validate_options(options, 1)!
	validate_engine(engine)!
	return Store{
		table:            options.table
		id_column:        options.id_column
		text_column:      options.text_column
		metadata_column:  options.metadata_column
		namespace_column: options.namespace_column
		vector_column:    options.vector_column
		embedder:         embedder
		engine:           engine
	}
}

fn validate_options(options Options, dimensions int) ! {
	if dimensions <= 0 || dimensions > max_index_dimensions {
		return error('MariaDB vector dimensions must be between 1 and ${max_index_dimensions}')
	}
	identifiers := [options.table, options.vector_index, options.id_column, options.text_column,
		options.metadata_column, options.namespace_column, options.vector_column]
	for field in identifiers {
		if !valid_identifier(field) {
			return error('mariadb table, index, and column names must be simple SQL identifiers')
		}
	}
	columns := identifiers[2..]
	for i, column in columns {
		if column in columns[i + 1..] {
			return error('mariadb table and column names must be distinct')
		}
	}
}

fn validate_engine(engine sqldatabase.Engine) ! {
	if engine.dialect() != 'mysql' {
		return error('mariadb requires a MariaDB engine')
	}
}

// add_documents embeds and inserts at most 64 documents into the existing table.
pub fn (store Store) add_documents(mut ctx context.Context, documents []schema.Document, options vectorstores.StoreOptions) ![]string {
	if documents.len == 0 {
		return []string{}
	}
	if documents.len > max_documents_per_write {
		return error('mariadb writes are limited to 64 documents per call')
	}
	if options.namespace.len > 65536 {
		return error('mariadb namespace exceeds 64 KiB')
	}
	mut estimated_bytes := documents.len * 256
	for document in documents {
		metadata_bytes := json2.encode(document.metadata, json2.EncoderOptions{}).len
		content_bytes := json2.encode(json2.Any(document.page_content), json2.EncoderOptions{}).len
		if content_bytes > max_payload_bytes - estimated_bytes
			|| metadata_bytes > max_payload_bytes - estimated_bytes - content_bytes {
			return error('mariadb document content and metadata exceed 4 MiB')
		}
		estimated_bytes += content_bytes + metadata_bytes
	}
	namespace_bytes := json2.encode(json2.Any(options.namespace), json2.EncoderOptions{}).len
	if namespace_bytes + 64 > (max_payload_bytes - estimated_bytes) / documents.len {
		return error('mariadb insert payload exceeds 4 MiB')
	}
	estimated_bytes += documents.len * (namespace_bytes + 64)
	vectors := store.embedder.embed_documents(mut ctx, documents.map(it.page_content))!
	if vectors.len != documents.len {
		return error('embedder returned ${vectors.len} vectors for ${documents.len} documents')
	}
	mut dimension := -1
	for vector in vectors {
		if vector.len == 0 || vector.len > max_embedding_values || (dimension > 0 && vector.len != dimension) {
			return error('mariadb embeddings must be non-empty, bounded, and dimensionally consistent')
		}
		dimension = vector.len
		mut squared_norm := f64(0)
		for value in vector {
			if !math.is_finite(f64(value)) {
				return error('mariadb embeddings must contain finite values')
			}
			estimated_bytes += value.str().len + 3
			squared_norm += f64(value) * f64(value)
			if estimated_bytes > max_payload_bytes {
				return error('mariadb insert payload exceeds 4 MiB')
			}
		}
		if squared_norm == 0 {
			return error('mariadb cosine embeddings must not be zero vectors')
		}
	}
	mut parameters := []string{cap: documents.len * 5}
	mut tuples := []string{cap: documents.len}
	mut ids := []string{cap: documents.len}
	for index, document in documents {
		id := rand.uuid_v4()
		ids << id
		vector_literal := vector_literal(vectors[index])
		tuples << '(?, ?, ?, ?, VEC_FromText(?))'
		parameters << id
		parameters << document.page_content
		parameters << json2.encode(document.metadata, json2.EncoderOptions{})
		parameters << options.namespace
		parameters << vector_literal
	}
	sql := 'INSERT INTO ${quote(store.table)} (${quote(store.id_column)}, ${quote(store.text_column)}, ${quote(store.metadata_column)}, ${quote(store.namespace_column)}, ${quote(store.vector_column)}) VALUES ${tuples.join(', ')}'
	if sql.len + parameters_bytes(parameters) > max_payload_bytes {
		return error('mariadb insert payload exceeds 4 MiB')
	}
	store.engine.query_params(mut ctx, sql, parameters)!
	return ids
}

// similarity_search returns cosine-nearest rows from the existing table.
pub fn (store Store) similarity_search(mut ctx context.Context, query string, limit int, options vectorstores.SearchOptions) ![]schema.Document {
	if limit < 0 || limit > max_search_limit {
		return error('mariadb search limit must be between zero and 1000')
	}
	if limit == 0 {
		return []schema.Document{}
	}
	if query.len > 65536 {
		return error('mariadb query exceeds 64 KiB')
	}
	if options.distance_strategy != '' && options.distance_strategy.to_lower() != 'cosine' {
		return error('MariaDB vector index uses cosine distance only')
	}
	if options.min_score != none && !math.is_finite(f64(options.min_score or { f32(0) })) {
		return error('mariadb minimum score must be finite')
	}
	if options.namespace.len > 65536 || options.filter.len > 128 {
		return error('mariadb namespace or filter count exceeds configured limits')
	}
	for key, value in options.filter {
		if !valid_identifier(key) || !valid_scalar(value) {
			return error('mariadb filters support scalar metadata equality with simple keys')
		}
		if value is string && (value as string).len > 4096 {
			return error('mariadb filter values are limited to 4 KiB')
		}
	}
	vector := store.embedder.embed_query(mut ctx, query)!
	if vector.len == 0 || vector.len > max_embedding_values {
		return error('mariadb query embedding must contain between 1 and 2000 values')
	}
	mut query_squared_norm := f64(0)
	for value in vector {
		if !math.is_finite(f64(value)) {
			return error('mariadb query embedding must contain finite values')
		}
		query_squared_norm += f64(value) * f64(value)
	}
	if query_squared_norm == 0 {
		return error('mariadb cosine query embedding must not be a zero vector')
	}
	vector_param := vector_literal(vector)
	mut parameters := [vector_param]
	mut predicates := []string{}
	if options.namespace != '' {
		parameters << options.namespace
		predicates << '${quote(store.namespace_column)} = ?'
	}
	for key, value in options.filter {
		parameters << key
		parameters << json2.encode(value, json2.EncoderOptions{})
		predicates << "JSON_EXTRACT(${quote(store.metadata_column)}, CONCAT('$.', ?)) = JSON_EXTRACT(?, '$')"
	}
	where_clause := if predicates.len == 0 { 'TRUE' } else { predicates.join(' AND ') }
	distance := 'VEC_DISTANCE_COSINE(${quote(store.vector_column)}, VEC_FromText(?))'
	// MariaDB uses the vector index when the cosine-distance expression is in
	// ORDER BY with LIMIT. Bind the query vector in SELECT and ORDER BY rather
	// than hiding it behind a CTE that could prevent index recognition.
	vector_select := if options.include_vectors {
		', VEC_ToText(${quote(store.vector_column)}) AS vector_text'
	} else {
		''
	}
	vector_column := if options.include_vectors { ', vector_text' } else { '' }
	vector_bytes := if options.include_vectors { ' + OCTET_LENGTH(vector_text)' } else { '' }
	vector_result := if options.include_vectors { ', vector_text' } else { '' }
	statement := 'WITH topk AS (SELECT CAST(${quote(store.id_column)} AS CHAR) AS id, ${quote(store.text_column)} AS page_content, CAST(${quote(store.metadata_column)} AS CHAR) AS metadata_json${vector_select}, ${distance} AS distance FROM ${quote(store.table)} WHERE ${where_clause} ORDER BY ${distance} ASC LIMIT ?), matches AS (SELECT id, page_content, metadata_json${vector_column}, 1 - distance AS score, distance, sum(OCTET_LENGTH(id) + OCTET_LENGTH(page_content) + OCTET_LENGTH(metadata_json)${vector_bytes} + 256) OVER (ORDER BY distance ASC ROWS UNBOUNDED PRECEDING) AS response_bytes FROM topk) SELECT id, page_content, metadata_json, score${vector_result} FROM matches WHERE response_bytes <= ${max_payload_bytes} ORDER BY distance ASC'
	parameters << vector_param
	parameters << limit.str()
	result := store.engine.query_params(mut ctx, statement, parameters)!
	if result.rows.len > limit {
		return error('mariadb returned more rows than requested')
	}
	mut documents := []schema.Document{cap: result.rows.len}
	mut response_bytes := 0
	for row in result.rows {
		if row.len < (if options.include_vectors { 5 } else { 4 }) {
			return error('mariadb returned a malformed search row')
		}
		response_bytes += row[0].len + row[1].len + row[2].len + row[3].len + 256
		if response_bytes > max_payload_bytes {
			return error('mariadb search response exceeds 4 MiB')
		}
		metadata := json2.decode[map[string]json2.Any](row[2], json2.DecoderOptions{}) or {
			return error('mariadb returned invalid metadata JSON')
		}
		score := strconv.atof64(row[3]) or { return error('mariadb returned a non-numeric score') }
		if !math.is_finite(score) || !math.is_finite(f64(f32(score))) {
			return error('mariadb returned a non-finite score')
		}
		if options.min_score != none && score < f64(options.min_score or { f32(0) }) {
			continue
		}
		mut embedding := []f32{}
		if options.include_vectors {
			embedding = json2.decode[[]f32](row[4], json2.DecoderOptions{}) or {
				return error('mariadb returned invalid vector JSON')
			}
			if embedding.len == 0 || embedding.len > max_embedding_values || embedding.len != vector.len {
				return error('mariadb returned a vector with an invalid dimension')
			}
			for value in embedding {
				if !math.is_finite(f64(value)) {
					return error('mariadb returned a non-finite vector value')
				}
			}
			response_bytes += row[4].len
			if response_bytes > max_payload_bytes {
				return error('mariadb search response exceeds 4 MiB')
			}
		}
		documents << schema.Document{
			page_content: row[1]
			metadata:     if options.include_metadata { metadata } else { map[string]json2.Any{} }
			score:        f32(score)
			embedding:    embedding
		}
	}
	return documents
}

// delete removes at most 1000 rows by ID and optional namespace.
pub fn (store Store) delete(mut ctx context.Context, ids []string, options vectorstores.StoreOptions) ! {
	if ids.len == 0 {
		return
	}
	if ids.len > 1000 {
		return error('mariadb delete is limited to 1000 IDs per call')
	}
	if options.namespace.len > 65536 {
		return error('mariadb namespace exceeds 64 KiB')
	}
	mut parameters := []string{cap: ids.len + 1}
	mut placeholders := []string{cap: ids.len}
	for id in ids {
		if id.trim_space() == '' || id.len > 512 {
			return error('mariadb IDs must be non-empty and at most 512 bytes')
		}
		parameters << id
		placeholders << '?'
	}
	mut predicates := ['${quote(store.id_column)} IN (${placeholders.join(', ')})']
	if options.namespace != '' {
		parameters << options.namespace
		predicates << '${quote(store.namespace_column)} = ?'
	}
	statement := 'DELETE FROM ${quote(store.table)} WHERE ${predicates.join(' AND ')}'
	store.engine.query_params(mut ctx, statement, parameters)!
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

fn parameters_bytes(parameters []string) int {
	mut size := 0
	for parameter in parameters {
		size += parameter.len
	}
	return size
}

fn quote(identifier string) string {
	return '`${identifier}`'
}

fn vector_literal(vector []f32) string {
	mut values := []string{cap: vector.len}
	for value in vector {
		values << value.str()
	}
	return '[${values.join(',')}]'
}

fn valid_scalar(value json2.Any) bool {
	return match value {
		string, bool, int, i64, i32, i16, i8, u64, u32, u16, u8 { true }
		f32 { math.is_finite(f64(value)) }
		f64 { math.is_finite(value) }
		else { false }
	}
}
