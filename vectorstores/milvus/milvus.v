// Package milvus implements a bounded REST adapter for Milvus collections.
module milvus

import context
import json2
import math
import net.http
import net.urllib
import rand
import ulises_jeremias.langchainv.embeddings
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.vectorstores

const max_documents_per_write = 64
const max_payload_bytes = 4 * 1024 * 1024
const max_search_limit = 1000
const max_embedding_values = 65536

// Store connects to an existing Milvus collection with string primary keys,
// a float vector field, a text field, a JSON metadata field, and a namespace field.
pub struct Store {
pub:
	base_url        string
	collection      string
	database        string
	token           string
	vector_field    string
	id_field        string
	text_field      string
	metadata_field  string
	namespace_field string
	metric_type     string
pub mut:
	embedder    embeddings.Embedder
	http_client httputil.HTTPClient
}

// Options configures an existing collection and REST endpoint.
pub struct Options {
pub:
	base_url        string
	collection      string
	database        string = '_default'
	token           string
	vector_field    string = 'vector'
	id_field        string = 'id'
	text_field      string = 'page_content'
	metadata_field  string = 'metadata'
	namespace_field string = 'namespace'
	metric_type     string = 'COSINE'
}

// new_store creates a Milvus REST adapter for an existing collection.
pub fn new_store(embedder embeddings.Embedder, options Options) !Store {
	client := httputil.HTTPClient(httputil.DefaultClient{
		max_request_bytes:  i64(max_payload_bytes)
		max_response_bytes: i64(max_payload_bytes)
	})
	return new_store_with_client(embedder, options, client)
}

// new_store_with_client creates an adapter using an injected HTTP client.
pub fn new_store_with_client(embedder embeddings.Embedder, options Options, http_client httputil.HTTPClient) !Store {
	base_url := if options.base_url.trim_space() == '' {
		'http://127.0.0.1:19530'
	} else {
		options.base_url.trim_space().trim_right('/')
	}
	if base_url.len > 2048 || base_url.contains('?') || base_url.contains('#') {
		return error('Milvus base URL must be at most 2048 bytes and contain no query or fragment')
	}
	httputil.validate_url(base_url, '')!
	parsed_url := urllib.parse(base_url) or { return error('Milvus base URL is invalid') }
	if parsed_url.scheme.to_lower() == 'http' && parsed_url.host.to_lower() !in [
		'localhost',
		'127.0.0.1',
		'::1',
	] {
		return error('remote Milvus endpoints must use HTTPS')
	}
	if !valid_identifier(options.collection) || !valid_identifier(options.database) {
		return error('Milvus collection and database names must be valid identifiers')
	}
	if options.token.len > 4096 || options.token.contains('\n') || options.token.contains('\r') {
		return error('Milvus token is invalid or exceeds 4096 bytes')
	}
	fields := [options.vector_field, options.id_field, options.text_field, options.metadata_field,
		options.namespace_field]
	for field in fields {
		if !valid_identifier(field) {
			return error('Milvus field names must be valid identifiers')
		}
	}
	for i, field in fields {
		if field in fields[i + 1..] {
			return error('Milvus configured field names must be distinct')
		}
	}
	metric := options.metric_type.to_upper()
	if metric !in ['COSINE', 'IP', 'L2'] {
		return error('Milvus metric type must be COSINE, IP, or L2')
	}
	return Store{
		base_url:        base_url
		collection:      options.collection
		database:        options.database
		token:           options.token
		vector_field:    options.vector_field
		id_field:        options.id_field
		text_field:      options.text_field
		metadata_field:  options.metadata_field
		namespace_field: options.namespace_field
		metric_type:     metric
		embedder:        embedder
		http_client:     http_client
	}
}

// add_documents embeds and inserts at most 64 documents in one request.
pub fn (store Store) add_documents(mut ctx context.Context, documents []schema.Document, options vectorstores.StoreOptions) ![]string {
	if documents.len == 0 {
		return []string{}
	}
	if documents.len > max_documents_per_write {
		return error('Milvus writes are limited to 64 documents per call')
	}
	if options.namespace.len > 65536 {
		return error('Milvus namespace exceeds 64 KiB')
	}
	mut input_bytes := 0
	for document in documents {
		metadata_bytes := json2.encode(document.metadata, json2.EncoderOptions{}).len
		content_bytes := json2.encode(json2.Any(document.page_content), json2.EncoderOptions{}).len
		if content_bytes > max_payload_bytes - input_bytes
			|| metadata_bytes > max_payload_bytes - input_bytes - content_bytes {
			return error('Milvus document content and metadata exceed 4 MiB')
		}
		input_bytes += content_bytes + metadata_bytes
		for key, _ in document.metadata {
			if key in [store.id_field, store.vector_field, store.text_field, store.metadata_field,
				store.namespace_field] {
				return error('document metadata contains a reserved Milvus field `${key}`')
			}
			if !valid_identifier(key) {
				return error('Milvus metadata keys must be valid identifiers')
			}
		}
	}
	vectors := store.embedder.embed_documents(mut ctx, documents.map(it.page_content))!
	if vectors.len != documents.len {
		return error('embedder returned ${vectors.len} vectors for ${documents.len} documents')
	}
	mut dimension := -1
	field_name_bytes := store.id_field.len + store.vector_field.len + store.text_field.len +
		store.metadata_field.len + store.namespace_field.len
	namespace_bytes := json2.encode(json2.Any(options.namespace), json2.EncoderOptions{}).len
	mut estimated_payload_bytes := input_bytes + documents.len * (field_name_bytes + namespace_bytes + 128) + 128
	for vector in vectors {
		if vector.len == 0 || vector.len > max_embedding_values || (dimension > 0 && vector.len != dimension) {
			return error('Milvus embeddings must be non-empty, bounded, and dimensionally consistent')
		}
		dimension = vector.len
		for value in vector {
			if !math.is_finite(f64(value)) {
				return error('Milvus embeddings must contain finite values')
			}
			estimated_payload_bytes += json2.encode(json2.Any(value), json2.EncoderOptions{}).len + 1
			if estimated_payload_bytes > max_payload_bytes {
				return error('Milvus write payload exceeds 4 MiB')
			}
		}
	}
	mut data := []json2.Any{cap: documents.len}
	mut ids := []string{cap: documents.len}
	for index, document in documents {
		vector := vectors[index]
		mut wire_vector := []json2.Any{cap: vector.len}
		for value in vector {
			wire_vector << json2.Any(value)
		}
		id := rand.uuid_v4()
		ids << id
		data << json2.Any(map[string]json2.Any{
			store.id_field:        json2.Any(id)
			store.vector_field:    json2.Any(wire_vector)
			store.text_field:      json2.Any(document.page_content)
			store.metadata_field:  json2.Any(document.metadata.clone())
			store.namespace_field: json2.Any(options.namespace)
		})
	}
	body := json2.encode(map[string]json2.Any{
		'dbName':         json2.Any(store.database)
		'collectionName': json2.Any(store.collection)
		'data':           json2.Any(data)
	}, json2.EncoderOptions{})
	response := store.request(mut ctx, .post, '/v2/vectordb/entities/insert', body)!
	decoded := json2.decode[map[string]json2.Any](response.body, json2.DecoderOptions{}) or {
		return error('Milvus returned invalid insert JSON')
	}
	data_any := decoded['data'] or { return error('Milvus insert response has no data') }
	if data_any !is map[string]json2.Any {
		return error('Milvus insert response data must be an object')
	}
	data_fields := data_any as map[string]json2.Any
	insert_count := milvus_int(data_fields['insertCount'] or {
		return error('Milvus insert response has no insertCount')
	})!
	if insert_count != documents.len {
		return error('Milvus inserted ${insert_count} of ${documents.len} requested documents')
	}
	insert_ids_any := data_fields['insertIds'] or { return error('Milvus insert response has no insertIds') }
	if insert_ids_any !is []json2.Any {
		return error('Milvus insertIds must be an array')
	}
	insert_ids_values := insert_ids_any as []json2.Any
	if insert_ids_values.len != ids.len {
		return error('Milvus returned an unexpected number of inserted IDs')
	}
	mut inserted_ids := []string{cap: insert_ids_values.len}
	for index, inserted_id_any in insert_ids_values {
		if inserted_id_any !is string || (inserted_id_any as string) != ids[index] {
			return error('Milvus returned an unexpected inserted ID')
		}
		inserted_ids << inserted_id_any as string
	}
	return inserted_ids
}

// similarity_search embeds a query and returns the nearest matching documents.
pub fn (store Store) similarity_search(mut ctx context.Context, query string, limit int, options vectorstores.SearchOptions) ![]schema.Document {
	if limit < 0 || limit > max_search_limit {
		return error('Milvus search limit must be between zero and 1000')
	}
	if limit == 0 {
		return []schema.Document{}
	}
	if query.len > 65536 {
		return error('Milvus query exceeds 64 KiB')
	}
	if options.distance_strategy != '' && metric_for_strategy(options.distance_strategy) != store.metric_type {
		return error('Milvus search distance strategy must match the configured collection metric')
	}
	if options.min_score != none {
		minimum := options.min_score or { f32(0) }
		if !math.is_finite(f64(minimum)) {
			return error('Milvus minimum score must be finite')
		}
		if store.metric_type == 'L2' {
			return error('Milvus minimum score filtering is not supported for L2 distance')
		}
	}
	if options.filter.len > 128 || options.namespace.len > 65536 {
		return error('Milvus search filters or namespace exceed configured limits')
	}
	for key, value in options.filter {
		if !valid_identifier(key) || key in [store.id_field, store.vector_field, store.text_field,
			store.metadata_field, store.namespace_field] || !valid_filter_value(value)
			|| filter_value_is_oversized(value) {
			return error('Milvus filters support scalar metadata equality on valid non-reserved keys')
		}
	}
	filter := store.make_filter(options.filter, options.namespace)
	if filter.len > max_payload_bytes {
		return error('Milvus search filter exceeds 4 MiB')
	}
	vector := store.embedder.embed_query(mut ctx, query)!
	if vector.len == 0 || vector.len > max_embedding_values {
		return error('Milvus query embedding must contain between 1 and 65536 values')
	}
	mut wire_vector := []json2.Any{cap: vector.len}
	for value in vector {
		if !math.is_finite(f64(value)) {
			return error('Milvus query embedding must contain finite values')
		}
		wire_vector << json2.Any(value)
	}
	mut output_fields := [json2.Any(store.text_field), json2.Any(store.metadata_field),
		json2.Any(store.namespace_field)]
	if options.include_vectors {
		output_fields << json2.Any(store.vector_field)
	}
	mut request := map[string]json2.Any{
		'dbName':         json2.Any(store.database)
		'collectionName': json2.Any(store.collection)
		'data':           json2.Any([json2.Any(wire_vector)])
		'annsField':      json2.Any(store.vector_field)
		'limit':          json2.Any(limit)
		'outputFields':   json2.Any(output_fields)
		'searchParams':   json2.Any({
			'metricType': json2.Any(store.metric_type)
			'params':     json2.Any(map[string]json2.Any{})
		})
	}
	if filter != '' {
		request['filter'] = json2.Any(filter)
	}
	response := store.request(mut ctx, .post, '/v2/vectordb/entities/search', json2.encode(request,
		json2.EncoderOptions{}))!
	decoded := json2.decode[map[string]json2.Any](response.body, json2.DecoderOptions{}) or {
		return error('Milvus returned invalid search JSON')
	}
	items := decoded['data'] or { return error('Milvus search response has no data') }
	if items !is []json2.Any {
		return error('Milvus search data must be an array')
	}
	matches := items as []json2.Any
	if matches.len > limit {
		return error('Milvus returned more matches than requested')
	}
	mut documents := []schema.Document{cap: matches.len}
	for item in matches {
		if item !is map[string]json2.Any {
			return error('Milvus returned a malformed match')
		}
		fields := item as map[string]json2.Any
		content_any := fields[store.text_field] or { return error('Milvus match is missing page content') }
		if content_any !is string {
			return error('Milvus page content field must be a string')
		}
		metadata_any := fields[store.metadata_field] or { json2.Any(map[string]json2.Any{}) }
		if metadata_any !is map[string]json2.Any {
			return error('Milvus metadata field must be an object')
		}
		mut metadata := (metadata_any as map[string]json2.Any).clone()
		namespace_any := fields[store.namespace_field] or { json2.Any('') }
		if namespace_any !is string {
			return error('Milvus namespace field must be a string')
		}
		score := milvus_float(fields['distance'] or { return error('Milvus match has no distance') })!
		if options.min_score != none && score < (options.min_score or { f32(0) }) {
			continue
		}
		if !options.include_metadata {
			metadata = map[string]json2.Any{}
		}
		mut embedding := []f32{}
		if options.include_vectors {
			vector_any := fields[store.vector_field] or {
				return error('Milvus search match is missing its vector field')
			}
			if vector_any !is []json2.Any {
				return error('Milvus returned an unsupported vector shape')
			}
			vector_values := vector_any as []json2.Any
			if vector_values.len == 0 || vector_values.len > max_embedding_values {
				return error('Milvus returned an empty or oversized vector')
			}
			embedding = []f32{cap: vector_values.len}
			for value in vector_values {
				embedding << milvus_float(value)!
			}
		}
		documents << schema.Document{
			page_content: content_any as string
			metadata:     metadata
			score:        score
			embedding:    embedding
		}
	}
	return documents
}

// delete removes up to 1000 primary-key IDs from the configured collection.
pub fn (store Store) delete(mut ctx context.Context, ids []string, options vectorstores.StoreOptions) ! {
	if ids.len == 0 {
		return
	}
	if ids.len > 1000 {
		return error('Milvus delete is limited to 1000 IDs per call')
	}
	if options.namespace.len > 65536 {
		return error('Milvus namespace exceeds 64 KiB')
	}
	mut wire_ids := []json2.Any{cap: ids.len}
	for id in ids {
		if id.trim_space() == '' || id.len > 512 {
			return error('Milvus vector IDs must be non-empty and at most 512 bytes')
		}
		wire_ids << json2.Any(id)
	}
	mut filter := '${store.id_field} in ${json2.encode(wire_ids, json2.EncoderOptions{})}'
	if options.namespace != '' {
		filter += ' and ${store.namespace_field} == ${json2.encode(json2.Any(options.namespace), json2.EncoderOptions{})}'
	}
	body := json2.encode(map[string]json2.Any{
		'dbName':         json2.Any(store.database)
		'collectionName': json2.Any(store.collection)
		'filter':         json2.Any(filter)
	}, json2.EncoderOptions{})
	store.request(mut ctx, .post, '/v2/vectordb/entities/delete', body)!
}

fn (store Store) make_filter(filter map[string]json2.Any, namespace string) string {
	mut parts := []string{}
	if namespace != '' {
		parts << '${store.namespace_field} == ${json2.encode(json2.Any(namespace), json2.EncoderOptions{})}'
	}
	for key, value in filter {
		parts << '${store.metadata_field}["${key}"] == ${json2.encode(value, json2.EncoderOptions{})}'
	}
	return parts.join(' and ')
}

fn (store Store) request(mut ctx context.Context, method http.Method, path string, body string) !httputil.Response {
	if body.len > max_payload_bytes {
		return error('Milvus request exceeds 4 MiB')
	}
	mut headers := {
		'Content-Type': 'application/json'
		'Accept':       'application/json'
	}
	if store.token != '' {
		headers['Authorization'] = 'Bearer ${store.token}'
	}
	response := store.http_client.do(mut ctx, httputil.Request{
		method:  method
		url:     '${store.base_url}${path}'
		headers: headers
		body:    body
	}) or {
		return error('Milvus request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Milvus request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_payload_bytes {
		return error('Milvus response exceeds 4 MiB')
	}
	if response.body.len == 0 {
		return error('Milvus returned an empty response')
	}
	decoded := json2.decode[map[string]json2.Any](response.body, json2.DecoderOptions{}) or {
		return error('Milvus returned invalid response JSON')
	}
	code := decoded['code'] or { return error('Milvus response has no status code') }
	if !is_success_code(code) {
		return error('Milvus returned an unsuccessful response')
	}
	return response
}

fn is_success_code(value json2.Any) bool {
	return match value {
		int { value == 0 }
		i64 { value == 0 }
		f32 { value == 0 }
		f64 { value == 0 }
		else { false }
	}
}

fn metric_for_strategy(strategy string) string {
	return match strategy.to_lower() {
		'cosine' { 'COSINE' }
		'dotproduct', 'ip' { 'IP' }
		'euclidean', 'l2' { 'L2' }
		else { '' }
	}
}

fn valid_identifier(value string) bool {
	if value.len == 0 || value.len > 128 {
		return false
	}
	for index, ch in value.bytes() {
		if !((ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
			|| ch == `_` || (index > 0 && ch >= `0` && ch <= `9`)) {
			return false
		}
	}
	return true
}

fn valid_filter_value(value json2.Any) bool {
	return match value {
		string, bool, int, i64, i32, i16, i8, u64, u32, u16, u8 { true }
		f32 { math.is_finite(f64(value)) }
		f64 { math.is_finite(value) }
		else { false }
	}
}

fn filter_value_is_oversized(value json2.Any) bool {
	return match value {
		string { value.len > 4096 }
		else { false }
	}
}

fn milvus_int(value json2.Any) !int {
	return match value {
		int { value }
		i64 {
			if value < 0 || value > 2147483647 {
				return error('Milvus count is outside the supported range')
			}
			int(value)
		}
		f64 {
			if !math.is_finite(value) || value < 0 || value > 2147483647 || value != f64(int(value)) {
				return error('Milvus count is not a valid non-negative integer')
			}
			int(value)
		}
		else { return error('Milvus count must be numeric') }
	}
}

fn milvus_float(value json2.Any) !f32 {
	result := match value {
		f32 { value }
		f64 { f32(value) }
		int { f32(value) }
		i64 { f32(value) }
		else { return error('Milvus distance must be numeric') }
	}
	if !math.is_finite(f64(result)) {
		return error('Milvus distance must be finite')
	}
	return result
}
