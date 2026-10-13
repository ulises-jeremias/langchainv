// Package redis implements a bounded Redis Stack vector-store adapter.
module redis

import context
import json2
import math
import math.bits
import rand
import strconv
import ulises_jeremias.langchainv.embeddings
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.vectorstores
import db.redis as redis_client

const max_documents_per_write = 64
const max_payload_bytes = 4 * 1024 * 1024
const max_search_limit = 30
const max_embedding_values = 2000
const max_document_field_bytes = 65536
const max_hnsw_connections = 64
const max_hnsw_ef_construction = 4096
const max_hnsw_ef_runtime = 4096
const source_field = 'lcg_source'
const source_marker = 'langchainv'

// RedisClient abstracts Redis commands for offline tests.
pub interface RedisClient {
	cmd(command ...string) !redis_client.RedisValue
}

// StandardRedisClient adapts the V standard-library DB to RedisClient.
pub struct StandardRedisClient {
pub mut:
	db &redis_client.DB
}

// cmd sends a Redis command through the wrapped standard-library connection.
pub fn (client StandardRedisClient) cmd(command ...string) !redis_client.RedisValue {
	mut db := client.db
	return db.cmd(...command)
}

// Store uses a Redis Stack HASH index and does not close the client.
pub struct Store {
pub:
	index           string
	key_prefix      string
	content_field   string
	metadata_field  string
	namespace_field string
	vector_field    string
	dimensions      int
	algorithm       string
	hnsw_ef_runtime int
pub mut:
	embedder embeddings.Embedder
	client   RedisClient
}

// Options configures a Redis Stack RediSearch HASH index and its store fields.
pub struct Options {
pub:
	index                string
	key_prefix           string = 'doc:langchainv:'
	content_field        string = 'content'
	metadata_field       string = 'metadata'
	namespace_field      string = 'namespace'
	vector_field         string = 'content_vector'
	dimensions           int
	algorithm            string = 'FLAT'
	hnsw_m               int    = 16
	hnsw_ef_construction int    = 200
	hnsw_ef_runtime      int    = 10
}

// new_store binds an embedder and Redis client to a HASH index. It never
// creates, alters, or drops the index.
pub fn new_store(embedder embeddings.Embedder, client RedisClient, options Options) !Store {
	validate_options(options)!
	algorithm := validate_algorithm_options(options)!
	return Store{
		index:           options.index
		key_prefix:      options.key_prefix
		content_field:   options.content_field
		metadata_field:  options.metadata_field
		namespace_field: options.namespace_field
		vector_field:    options.vector_field
		dimensions:      options.dimensions
		algorithm:       algorithm
		hnsw_ef_runtime: options.hnsw_ef_runtime
		embedder:        embedder
		client:          client
	}
}

// initialize_index explicitly creates a non-destructive RediSearch HASH index.
// algorithm defaults to FLAT; HNSW uses the configured bounded M and
// EF_CONSTRUCTION values. new_store sends the bounded EF_RUNTIME option with
// each HNSW query. metadata_fields names scalar metadata keys to index as TAG
// fields. Redis scans existing keys matching the prefix as part of FT.CREATE,
// so choose a suitable maintenance window and server capacity.
pub fn initialize_index(client RedisClient, options Options, metadata_fields []string) ! {
	validate_options(options)!
	algorithm := validate_algorithm_options(options)!
	if metadata_fields.len > 128 {
		return error('Redis index supports at most 128 metadata TAG fields')
	}
	mut seen_metadata := map[string]bool{}
	mut command := ['FT.CREATE', options.index, 'ON', 'HASH', 'PREFIX', '1', options.key_prefix,
		'SCHEMA', options.content_field, 'TEXT', options.namespace_field, 'TAG', source_field,
		'TAG']
	for field in metadata_fields {
		if !valid_token(field, false) || field in [options.content_field, options.metadata_field,
			options.namespace_field, options.vector_field, source_field] || field in seen_metadata {
			return error('Redis metadata index fields must be unique simple names, separate from store fields')
		}
		seen_metadata[field] = true
		command << 'meta_${field}'
		command << 'TAG'
	}
	command << [options.vector_field, 'VECTOR', algorithm, if algorithm == 'HNSW' {
		'10'
	} else {
		'6'
	}, 'TYPE', 'FLOAT32', 'DIM', options.dimensions.str(), 'DISTANCE_METRIC', 'COSINE']
	if algorithm == 'HNSW' {
		command << ['M', options.hnsw_m.str(), 'EF_CONSTRUCTION', options.hnsw_ef_construction.str()]
	}
	client.cmd(...command) or { return error('could not create Redis Stack index: ${err.msg()}') }
}

fn validate_algorithm_options(options Options) !string {
	algorithm := options.algorithm.to_upper()
	if algorithm !in ['FLAT', 'HNSW'] {
		return error('Redis vector index algorithm must be FLAT or HNSW')
	}
	if algorithm == 'HNSW' {
		if options.hnsw_m < 2 || options.hnsw_m > max_hnsw_connections
			|| options.hnsw_ef_construction < options.hnsw_m
			|| options.hnsw_ef_construction > max_hnsw_ef_construction {
			return error('Redis HNSW M must be 2..${max_hnsw_connections} and EF_CONSTRUCTION must be M..${max_hnsw_ef_construction}')
		}
		if options.hnsw_ef_runtime < 1 || options.hnsw_ef_runtime > max_hnsw_ef_runtime {
			return error('Redis HNSW EF_RUNTIME must be between 1 and ${max_hnsw_ef_runtime}')
		}
	}
	return algorithm
}

fn validate_options(options Options) ! {
	if !valid_token(options.index, false) || !valid_token(options.key_prefix, true) {
		return error('Redis index and key prefix must contain only letters, digits, underscore, colon, or hyphen')
	}
	fields := [options.content_field, options.metadata_field, options.namespace_field,
		options.vector_field]
	for field in fields {
		if !valid_token(field, false) {
			return error('Redis field names must be simple identifiers')
		}
	}
	for i, field in fields {
		if field == source_field || field in fields[i + 1..] {
			return error('Redis field names must be distinct and cannot use the reserved source field')
		}
	}
	if options.dimensions <= 0 || options.dimensions > max_embedding_values {
		return error('Redis vector dimensions must be between 1 and 2000')
	}
}

// add_documents embeds and writes at most 64 documents as Redis HASH records.
pub fn (store Store) add_documents(mut ctx context.Context, documents []schema.Document, options vectorstores.StoreOptions) ![]string {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	if documents.len == 0 {
		return []string{}
	}
	if documents.len > max_documents_per_write {
		return error('Redis writes are limited to 64 documents per call')
	}
	if options.namespace.len > max_document_field_bytes {
		return error('Redis namespace exceeds 64 KiB')
	}
	for document in documents {
		metadata := encode_metadata(document.metadata)
		if metadata.len > max_document_field_bytes || document.page_content.len > max_document_field_bytes {
			return error('Redis content and metadata fields are limited to 64 KiB each')
		}
		for key, value in document.metadata {
			if !valid_token(key, false) || key in [store.content_field, store.metadata_field,
				store.namespace_field, store.vector_field] || !valid_scalar(value) {
				return error('Redis metadata keys must be simple and values must be scalar')
			}
		}
	}
	vectors := store.embedder.embed_documents(mut ctx, documents.map(it.page_content))!
	if vectors.len != documents.len {
		return error('embedder returned ${vectors.len} vectors for ${documents.len} documents')
	}
	mut ids := []string{cap: documents.len}
	mut commands := [][]string{cap: documents.len}
	mut written_bytes := 0
	for index, document in documents {
		write_ctx_error := ctx.err()
		if write_ctx_error !is none {
			return write_ctx_error
		}
		vector := vectors[index]
		validate_vector(vector, store.dimensions)!
		metadata := encode_metadata(document.metadata)
		vector_bytes := binary_vector(vector)
		id := store.key_prefix + rand.uuid_v4()
		mut command := ['HSET', id, store.content_field, document.page_content, store.metadata_field,
			metadata, store.namespace_field, options.namespace, store.vector_field, vector_bytes,
			source_field, source_marker]
		for key, value in document.metadata {
			command << 'meta_${key}'
			command << scalar_string(value)
		}
		for arg in command {
			written_bytes += arg.len
		}
		written_bytes += command.len * 24
		if written_bytes > max_payload_bytes {
			return error('Redis write payload exceeds 4 MiB')
		}
		ids << id
		commands << command
	}
	for command in commands {
		command_ctx_error := ctx.err()
		if command_ctx_error !is none {
			return command_ctx_error
		}
		store.client.cmd(...command) or { return error('Redis HSET failed: ${err.msg()}') }
	}
	return ids
}

// similarity_search runs a cosine KNN query against a preconfigured HASH index.
pub fn (store Store) similarity_search(mut ctx context.Context, query string, limit int, options vectorstores.SearchOptions) ![]schema.Document {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	if limit < 0 || limit > max_search_limit {
		return error('Redis search limit must be between zero and ${max_search_limit}')
	}
	if limit == 0 {
		return []schema.Document{}
	}
	if query.len > 65536 || options.namespace.len > 65536 || options.filter.len > 128 {
		return error('Redis query, namespace, or filter count exceeds configured limits')
	}
	if options.distance_strategy != '' && options.distance_strategy.to_lower() != 'cosine' {
		return error('Redis adapter supports cosine distance only')
	}
	if options.min_score != none && !math.is_finite(f64(options.min_score or { f32(0) })) {
		return error('Redis minimum score must be finite')
	}
	mut filter_parts := ['@${source_field}:{${source_marker}}']
	if options.namespace != '' {
		filter_parts << '@${store.namespace_field}:{${escape_tag(options.namespace)}}'
	}
	mut filter_bytes := 0
	for key, value in options.filter {
		if !valid_token(key, false) || !valid_scalar(value) {
			return error('Redis filters require simple metadata keys and scalar values')
		}
		encoded_value := scalar_string(value)
		filter_bytes += key.len + encoded_value.len
		if encoded_value.len > max_document_field_bytes || filter_bytes > max_document_field_bytes {
			return error('Redis search filters exceed 64 KiB')
		}
		filter_parts << '@meta_${key}:{${escape_tag(encoded_value)}}'
	}
	filter := filter_parts.join(' ')
	vector := store.embedder.embed_query(mut ctx, query)!
	validate_vector(vector, store.dimensions)!
	vector_arg := binary_vector(vector)
	return_count := if options.include_vectors { '4' } else { '3' }
	vector_query := if store.algorithm == 'HNSW' {
		'(${filter})=>[KNN ${limit} @${store.vector_field} $query_vector EF_RUNTIME $ef_runtime AS distance]'
	} else {
		'(${filter})=>[KNN ${limit} @${store.vector_field} $query_vector AS distance]'
	}
	mut command := ['FT.SEARCH', store.index, vector_query, 'RETURN', return_count,
		store.content_field, store.metadata_field, 'distance']
	if options.include_vectors {
		command << store.vector_field
	}
	command << ['SORTBY', 'distance', 'ASC', 'LIMIT', '0', limit.str()]
	if store.algorithm == 'HNSW' {
		command << ['PARAMS', '4', 'query_vector', vector_arg, 'ef_runtime',
			store.hnsw_ef_runtime.str()]
	} else {
		command << ['PARAMS', '2', 'query_vector', vector_arg]
	}
	command << ['DIALECT', '2']
	mut response_bytes := 0
	for arg in command {
		response_bytes += arg.len
	}
	if response_bytes > max_payload_bytes {
		return error('Redis search request exceeds 4 MiB')
	}
	response := store.client.cmd(...command) or { return error('Redis FT.SEARCH failed: ${err.msg()}') }
	return parse_search_response(response, store, limit, options, max_payload_bytes)
}

// delete removes up to 1000 documents by their Redis HASH key.
pub fn (store Store) delete(mut _ctx context.Context, ids []string, options vectorstores.StoreOptions) ! {
	if ids.len > 1000 {
		return error('Redis delete is limited to 1000 IDs per call')
	}
	if ids.len == 0 {
		return
	}
	ctx_error := _ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	mut command := ['DEL']
	for id in ids {
		if !id.starts_with(store.key_prefix) || id.len > 512 {
			return error('Redis delete IDs must use this store key prefix and be at most 512 bytes')
		}
		command << id
	}
	if options.namespace != '' {
		return error('Redis deletion does not support namespace constraints')
	}
	store.client.cmd(...command) or { return error('Redis DEL failed: ${err.msg()}') }
}

fn validate_vector(vector []f32, dimensions int) ! {
	if vector.len != dimensions {
		return error('Redis embedding dimension ${vector.len} does not match configured dimension ${dimensions}')
	}
	mut norm := f64(0)
	for value in vector {
		if !math.is_finite(f64(value)) {
			return error('Redis embeddings must contain finite values')
		}
		norm += f64(value) * f64(value)
	}
	if norm == 0 {
		return error('Redis cosine embeddings must not be zero vectors')
	}
}

fn binary_vector(vector []f32) string {
	mut bytes := []u8{cap: vector.len * 4}
	for value in vector {
		raw_bits := bits.f32_bits(value)
		bytes << u8(raw_bits)
		bytes << u8(raw_bits >> 8)
		bytes << u8(raw_bits >> 16)
		bytes << u8(raw_bits >> 24)
	}
	return bytes.bytestr()
}

fn parse_binary_vector(value string, dimensions int) ![]f32 {
	bytes := value.bytes()
	if dimensions <= 0 || bytes.len != dimensions * 4 {
		return error('Redis returned a vector with an invalid byte length')
	}
	mut vector := []f32{cap: dimensions}
	for index := 0; index < bytes.len; index += 4 {
		low_bits := u32(bytes[index])
		middle_bits := u32(bytes[index + 1]) << 8
		high_bits := u32(bytes[index + 2]) << 16
		top_bits := u32(bytes[index + 3]) << 24
		raw_bits := low_bits | middle_bits | high_bits | top_bits
		decoded_value := bits.f32_from_bits(raw_bits)
		if !math.is_finite(f64(decoded_value)) {
			return error('Redis returned a non-finite vector value')
		}
		vector << decoded_value
	}
	return vector
}

fn parse_search_response(response redis_client.RedisValue, store Store, limit int, options vectorstores.SearchOptions, max_bytes int) ![]schema.Document {
	values := match response {
		[]redis_client.RedisValue { response }
		else { return error('Redis FT.SEARCH returned an invalid response') }
	}
	if values.len == 0 {
		return error('Redis FT.SEARCH returned an empty response')
	}
	if (values.len - 1) % 2 != 0 {
		return error('Redis FT.SEARCH returned malformed result pairs')
	}
	total := strconv.parse_int(redis_value_string(values[0])!, 10, 64) or {
		return error('Redis FT.SEARCH returned an invalid result count')
	}
	if total < 0 || values.len > 1 + limit * 2 {
		return error('Redis FT.SEARCH returned too many rows')
	}
	mut documents := []schema.Document{cap: (values.len - 1) / 2}
	mut used_bytes := 0
	mut index := 1
	for index + 1 < values.len {
		id := redis_value_string(values[index])!
		attrs := redis_attributes(values[index + 1])!
		content := attrs[store.content_field] or { return error('Redis result is missing page content') }
		metadata_json := attrs[store.metadata_field] or { return error('Redis result is missing metadata') }
		distance_text := attrs['distance'] or { return error('Redis result is missing vector distance') }
		vector_text := if options.include_vectors {
			attrs[store.vector_field] or { return error('Redis result is missing its vector') }
		} else {
			''
		}
		used_bytes += id.len + content.len + metadata_json.len + distance_text.len
		used_bytes += vector_text.len + 1024
		if used_bytes > max_bytes {
			return error('Redis search response exceeds 4 MiB')
		}
		metadata := json2.decode[map[string]json2.Any](metadata_json, json2.DecoderOptions{}) or {
			return error('Redis result contains invalid metadata JSON')
		}
		distance := strconv.atof64(distance_text) or { return error('Redis result contains an invalid distance') }
		score := 1.0 - distance
		if !math.is_finite(distance) || !math.is_finite(score) || !math.is_finite(f64(f32(score))) {
			return error('Redis result contains a non-finite distance')
		}
		if options.min_score != none && score < f64(options.min_score or { f32(0) }) {
			index += 2
			continue
		}
		mut embedding := []f32{}
		if options.include_vectors {
			embedding = parse_binary_vector(vector_text, store.dimensions)!
		}
		documents << schema.Document{
			page_content: content
			metadata:     if options.include_metadata { metadata } else { map[string]json2.Any{} }
			score:        f32(score)
			embedding:    embedding
		}
		index += 2
	}
	return documents
}

fn redis_attributes(value redis_client.RedisValue) !map[string]string {
	mut result := map[string]string{}
	match value {
		[]redis_client.RedisValue {
			if value.len % 2 != 0 {
				return error('Redis FT.SEARCH returned malformed fields')
			}
			for i := 0; i < value.len; i += 2 {
				result[redis_value_string(value[i])!] = redis_value_string(value[i + 1])!
			}
		}
		redis_client.RedisMap {
			if value.pairs.len % 2 != 0 {
				return error('Redis FT.SEARCH returned malformed fields')
			}
			for i := 0; i < value.pairs.len; i += 2 {
				result[redis_value_string(value.pairs[i])!] = redis_value_string(value.pairs[i + 1])!
			}
		}
		map[string]redis_client.RedisValue {
			for key, field in value {
				result[key] = redis_value_string(field)!
			}
		}
		else { return error('Redis FT.SEARCH returned malformed fields') }
	}
	return result
}

fn redis_value_string(value redis_client.RedisValue) !string {
	return match value {
		string { value }
		[]u8 { value.bytestr() }
		i64 { value.str() }
		f64 { value.str() }
		f32 { value.str() }
		else { error('Redis FT.SEARCH returned an unsupported value type') }
	}
}

fn valid_scalar(value json2.Any) bool {
	return match value {
		string, bool, int, i64, i32, i16, i8, u64, u32, u16, u8 { true }
		f32 { math.is_finite(f64(value)) }
		f64 { math.is_finite(value) }
		else { false }
	}
}

fn scalar_string(value json2.Any) string {
	return json2.encode(value, json2.EncoderOptions{})
}

fn encode_metadata(metadata map[string]json2.Any) string {
	if metadata.len == 0 {
		return '{}'
	}
	return json2.encode(metadata, json2.EncoderOptions{})
}

fn valid_token(value string, allow_prefix_chars bool) bool {
	if value.len == 0 || value.len > 256 {
		return false
	}
	for ch in value.bytes() {
		if (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || (ch >= `0` && ch <= `9`)
			|| ch == `_` || ch == `-` || (allow_prefix_chars && ch == `:`) {
			continue
		}
		return false
	}
	return true
}

fn escape_tag(value string) string {
	mut escaped := []u8{cap: value.len}
	for ch in value.bytes() {
		if ch in [`\\`, `,`, `.`, `<`, `>`, `{`, `}`, `[`, `]`, `"`, `'`, `:`, `;`, `!`, `@`, `#`,
			`$`, `%`, `^`, `&`, `*`, `(`, `)`, `-`, `+`, `=`, `~`, `|`, ` `] {
			escaped << `\\`
		}
		escaped << ch
	}
	return escaped.bytestr()
}
