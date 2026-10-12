// Package pgvector implements a bounded PostgreSQL pgvector adapter.
module pgvector

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

// Store uses an existing PostgreSQL table with a pgvector `vector` column.
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

// Options configures an existing table and its document/vector columns.
pub struct Options {
pub:
	table            string = 'langchainv_documents'
	id_column        string = 'id'
	text_column      string = 'page_content'
	metadata_column  string = 'metadata'
	namespace_column string = 'namespace'
	vector_column    string = 'embedding'
}

// new_store binds an embedder to an existing PostgreSQL pgvector engine.
pub fn new_store(embedder embeddings.Embedder, engine sqldatabase.Engine, options Options) !Store {
	if engine.dialect() !in ['pgx', 'postgresql'] {
		return error('pgvector requires a PostgreSQL engine')
	}
	if !valid_identifier(options.table) {
		return error('pgvector table and column names must be simple SQL identifiers')
	}
	columns := [options.id_column, options.text_column, options.metadata_column,
		options.namespace_column, options.vector_column]
	for field in columns {
		if !valid_identifier(field) {
			return error('pgvector table and column names must be simple SQL identifiers')
		}
	}
	for i, column in columns {
		if column in columns[i + 1..] {
			return error('pgvector table and column names must be distinct')
		}
	}
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

// add_documents embeds and inserts at most 64 documents into the existing table.
pub fn (store Store) add_documents(mut ctx context.Context, documents []schema.Document, options vectorstores.StoreOptions) ![]string {
	if documents.len == 0 {
		return []string{}
	}
	if documents.len > max_documents_per_write {
		return error('pgvector writes are limited to 64 documents per call')
	}
	if options.namespace.len > 65536 {
		return error('pgvector namespace exceeds 64 KiB')
	}
	mut estimated_bytes := documents.len * 256
	for document in documents {
		metadata_bytes := json2.encode(document.metadata, json2.EncoderOptions{}).len
		content_bytes := json2.encode(json2.Any(document.page_content), json2.EncoderOptions{}).len
		if content_bytes > max_payload_bytes - estimated_bytes
			|| metadata_bytes > max_payload_bytes - estimated_bytes - content_bytes {
			return error('pgvector document content and metadata exceed 4 MiB')
		}
		estimated_bytes += content_bytes + metadata_bytes
	}
	namespace_bytes := json2.encode(json2.Any(options.namespace), json2.EncoderOptions{}).len
	if namespace_bytes + 64 > (max_payload_bytes - estimated_bytes) / documents.len {
		return error('pgvector insert payload exceeds 4 MiB')
	}
	estimated_bytes += documents.len * (namespace_bytes + 64)
	vectors := store.embedder.embed_documents(mut ctx, documents.map(it.page_content))!
	if vectors.len != documents.len {
		return error('embedder returned ${vectors.len} vectors for ${documents.len} documents')
	}
	mut dimension := -1
	for vector in vectors {
		if vector.len == 0 || vector.len > max_embedding_values || (dimension > 0 && vector.len != dimension) {
			return error('pgvector embeddings must be non-empty, bounded, and dimensionally consistent')
		}
		dimension = vector.len
		mut squared_norm := f64(0)
		for value in vector {
			if !math.is_finite(f64(value)) {
				return error('pgvector embeddings must contain finite values')
			}
			estimated_bytes += value.str().len + 3
			squared_norm += f64(value) * f64(value)
			if estimated_bytes > max_payload_bytes {
				return error('pgvector insert payload exceeds 4 MiB')
			}
		}
		if squared_norm == 0 {
			return error('pgvector cosine embeddings must not be zero vectors')
		}
	}
	mut parameters := []string{cap: documents.len * 5}
	mut tuples := []string{cap: documents.len}
	mut ids := []string{cap: documents.len}
	for index, document in documents {
		id := rand.uuid_v4()
		ids << id
		vector_literal := vector_literal(vectors[index])
		start := index * 5 + 1
		tuples << '($${start}, $${start + 1}, $${start + 2}::jsonb, $${start + 3}, $${start + 4}::vector)'
		parameters << id
		parameters << document.page_content
		parameters << json2.encode(document.metadata, json2.EncoderOptions{})
		parameters << options.namespace
		parameters << vector_literal
	}
	sql := 'INSERT INTO ${quote(store.table)} (${quote(store.id_column)}, ${quote(store.text_column)}, ${quote(store.metadata_column)}, ${quote(store.namespace_column)}, ${quote(store.vector_column)}) VALUES ${tuples.join(', ')}'
	if sql.len + parameters_bytes(parameters) > max_payload_bytes {
		return error('pgvector insert payload exceeds 4 MiB')
	}
	store.engine.query_params(mut ctx, sql, parameters)!
	return ids
}

// similarity_search returns cosine-nearest rows from the existing table.
pub fn (store Store) similarity_search(mut ctx context.Context, query string, limit int, options vectorstores.SearchOptions) ![]schema.Document {
	if limit < 0 || limit > max_search_limit {
		return error('pgvector search limit must be between zero and 1000')
	}
	if limit == 0 {
		return []schema.Document{}
	}
	if query.len > 65536 {
		return error('pgvector query exceeds 64 KiB')
	}
	if options.distance_strategy != '' && options.distance_strategy.to_lower() != 'cosine' {
		return error('pgvector adapter supports cosine distance only')
	}
	if options.min_score != none && !math.is_finite(f64(options.min_score or { f32(0) })) {
		return error('pgvector minimum score must be finite')
	}
	if options.namespace.len > 65536 || options.filter.len > 128 {
		return error('pgvector namespace or filter count exceeds configured limits')
	}
	for key, value in options.filter {
		if !valid_identifier(key) || !valid_scalar(value) {
			return error('pgvector filters support scalar metadata equality with simple keys')
		}
		if value is string && (value as string).len > 4096 {
			return error('pgvector filter values are limited to 4 KiB')
		}
	}
	vector := store.embedder.embed_query(mut ctx, query)!
	if vector.len == 0 || vector.len > max_embedding_values {
		return error('pgvector query embedding must contain between 1 and 2000 values')
	}
	mut query_squared_norm := f64(0)
	for value in vector {
		if !math.is_finite(f64(value)) {
			return error('pgvector query embedding must contain finite values')
		}
		query_squared_norm += f64(value) * f64(value)
	}
	if query_squared_norm == 0 {
		return error('pgvector cosine query embedding must not be a zero vector')
	}
	vector_param := vector_literal(vector)
	mut parameters := [vector_param]
	mut predicates := []string{}
	if options.namespace != '' {
		parameters << options.namespace
		predicates << '${quote(store.namespace_column)} = $${parameters.len}'
	}
	for key, value in options.filter {
		parameters << key
		parameters << json2.encode(value, json2.EncoderOptions{})
		key_param := parameters.len - 1
		value_param := parameters.len
		predicates << '${quote(store.metadata_column)} -> $${key_param}::text = $${value_param}::jsonb'
	}
	where_clause := if predicates.len == 0 { 'TRUE' } else { predicates.join(' AND ') }
	parameters << limit.str()
	limit_param := parameters.len
	distance := '${quote(store.vector_column)} <=> $1::vector'
	vector_selection := if options.include_vectors {
		', ${quote(store.vector_column)}::text AS embedding_text'
	} else {
		''
	}
	vector_size := if options.include_vectors {
		' + octet_length(${quote(store.vector_column)}::text)'
	} else {
		''
	}
	vector_result := if options.include_vectors { ', embedding_text' } else { '' }
	statement := 'WITH matches AS MATERIALIZED (SELECT ${quote(store.id_column)}::text AS id, ${quote(store.text_column)} AS page_content, ${quote(store.metadata_column)}::text AS metadata_json, 1 - (${distance}) AS score, ${distance} AS distance${vector_selection}, sum(octet_length(${quote(store.id_column)}::text) + octet_length(${quote(store.text_column)}) + octet_length(${quote(store.metadata_column)}::text) + 256${vector_size}) OVER (ORDER BY ${distance} ASC ROWS UNBOUNDED PRECEDING) AS response_bytes FROM ${quote(store.table)} WHERE ${where_clause} ORDER BY ${distance} ASC LIMIT $${limit_param}::int) SELECT id, page_content, metadata_json, score${vector_result} FROM matches WHERE response_bytes <= ${max_payload_bytes} ORDER BY distance ASC'
	result := store.engine.query_params(mut ctx, statement, parameters)!
	if result.rows.len > limit {
		return error('pgvector returned more rows than requested')
	}
	mut documents := []schema.Document{cap: result.rows.len}
	mut response_bytes := 0
	required_columns := if options.include_vectors { 5 } else { 4 }
	for row in result.rows {
		if row.len < required_columns {
			return error('pgvector returned a malformed search row')
		}
		response_bytes += row[0].len + row[1].len + row[2].len + row[3].len + 256
		if options.include_vectors {
			response_bytes += row[4].len
		}
		if response_bytes > max_payload_bytes {
			return error('pgvector search response exceeds 4 MiB')
		}
		metadata := json2.decode[map[string]json2.Any](row[2], json2.DecoderOptions{}) or {
			return error('pgvector returned invalid metadata JSON')
		}
		score := strconv.atof64(row[3]) or { return error('pgvector returned a non-numeric score') }
		if !math.is_finite(score) || !math.is_finite(f64(f32(score))) {
			return error('pgvector returned a non-finite score')
		}
		if options.min_score != none && score < f64(options.min_score or { f32(0) }) {
			continue
		}
		mut embedding := []f32{}
		if options.include_vectors {
			embedding = parse_vector_text(row[4])!
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
		return error('pgvector delete is limited to 1000 IDs per call')
	}
	if options.namespace.len > 65536 {
		return error('pgvector namespace exceeds 64 KiB')
	}
	mut parameters := []string{cap: ids.len + 1}
	mut placeholders := []string{cap: ids.len}
	for index, id in ids {
		if id.trim_space() == '' || id.len > 512 {
			return error('pgvector IDs must be non-empty and at most 512 bytes')
		}
		parameters << id
		placeholders << '$${index + 1}'
	}
	mut predicates := ['${quote(store.id_column)} IN (${placeholders.join(', ')})']
	if options.namespace != '' {
		parameters << options.namespace
		predicates << '${quote(store.namespace_column)} = $${parameters.len}'
	}
	statement := 'DELETE FROM ${quote(store.table)} WHERE ${predicates.join(' AND ')}'
	store.engine.query_params(mut ctx, statement, parameters)!
}

fn valid_identifier(value string) bool {
	if value.len == 0 || value.len > 63 {
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
	return '"${identifier}"'
}

fn parse_vector_text(value string) ![]f32 {
	text := value.trim_space()
	if !text.starts_with('[') || !text.ends_with(']') {
		return error('pgvector returned a malformed vector literal')
	}
	contents := text[1..text.len - 1].trim_space()
	if contents == '' {
		return error('pgvector returned an empty vector')
	}
	parts := contents.split(',')
	if parts.len > max_embedding_values {
		return error('pgvector returned an oversized vector')
	}
	mut vector := []f32{cap: parts.len}
	for part in parts {
		number := strconv.atof64(part.trim_space()) or {
			return error('pgvector returned a non-numeric vector value')
		}
		converted := f32(number)
		if !math.is_finite(number) || !math.is_finite(f64(converted)) {
			return error('pgvector returned a non-finite vector value')
		}
		vector << converted
	}
	return vector
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
