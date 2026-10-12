// Package chroma implements a bounded Chroma REST API v2 vector store.
module chroma

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
const namespace_metadata_key = '_langchainv_namespace'

// Store uses one provisioned Chroma collection and an injected embedder.
pub struct Store {
pub:
	base_url      string
	tenant        string
	database      string
	collection_id string
	api_key       string
	namespace     string
pub mut:
	embedder    embeddings.Embedder
	http_client httputil.HTTPClient
}

// Options identifies a Chroma server, tenant, database, optional collection ID,
// and token. Leave collection_id blank only with new_store_with_collection.
pub struct Options {
pub:
	base_url      string
	tenant        string
	database      string
	collection_id string
	api_key       string
	namespace     string
}

// new_store creates an adapter for an existing collection by ID. Use
// new_store_with_collection to create or get a collection by name.
pub fn new_store(embedder embeddings.Embedder, options Options) !Store {
	return new_store_config(embedder, options, true)
}

fn new_store_config(embedder embeddings.Embedder, options Options, require_collection bool) !Store {
	base_url := if options.base_url.trim_space() == '' {
		'http://127.0.0.1:8000'
	} else {
		options.base_url.trim_space().trim_right('/')
	}
	if base_url.len > 2048 {
		return error('Chroma base URL must be at most 2048 bytes')
	}
	httputil.validate_url(base_url, '')!
	parsed_url := urllib.parse(base_url) or { return error('Chroma base URL is invalid') }
	if parsed_url.scheme.to_lower() == 'http' && parsed_url.host.to_lower() !in [
		'localhost',
		'127.0.0.1',
		'::1',
	] {
		return error('remote Chroma endpoints must use HTTPS')
	}
	if base_url.contains('?') || base_url.contains('#') {
		return error('Chroma base URL must not contain a query or fragment')
	}
	tenant := if options.tenant.trim_space() == '' { 'default_tenant' } else { options.tenant }
	database := if options.database.trim_space() == '' {
		'default_database'
	} else {
		options.database
	}
	namespace := if options.namespace == '' { 'langchain' } else { options.namespace }
	if !valid_path_segment(tenant) || !valid_path_segment(database) {
		return error('Chroma tenant and database must be safe path segments')
	}
	if options.collection_id != '' && !valid_path_segment(options.collection_id) {
		return error('Chroma collection ID must be a safe path segment')
	}
	if require_collection && options.collection_id == '' {
		return error('Chroma collection ID is required for an existing collection')
	}
	if options.api_key.len > 4096 || options.api_key.contains('\n') || options.api_key.contains('\r') {
		return error('Chroma API key is invalid or exceeds 4096 bytes')
	}
	return Store{
		base_url:      base_url
		tenant:        tenant
		database:      database
		collection_id: options.collection_id
		api_key:       options.api_key
		namespace:     namespace
		embedder:      embedder
		http_client:   httputil.DefaultClient{
			max_request_bytes:  max_payload_bytes
			max_response_bytes: max_payload_bytes
		}
	}
}

// new_store_with_collection creates or gets a named collection and returns a
// store bound to its server-assigned ID. Chroma's default L2 configuration is
// used; callers can still provision collections independently with new_store.
pub fn new_store_with_collection(mut ctx context.Context, embedder embeddings.Embedder, options Options, collection_name string, get_or_create bool) !Store {
	client := httputil.HTTPClient(httputil.DefaultClient{
		max_request_bytes:  max_payload_bytes
		max_response_bytes: max_payload_bytes
	})
	return new_store_with_collection_and_client(mut ctx, embedder, options, collection_name,
		get_or_create, client)
}

// new_store_with_collection_and_client creates or gets a named collection
// using the supplied transport. It is useful for custom clients and offline tests.
pub fn new_store_with_collection_and_client(mut ctx context.Context, embedder embeddings.Embedder, options Options, collection_name string, get_or_create bool, http_client httputil.HTTPClient) !Store {
	if collection_name.trim_space() == '' || collection_name.len > 512
		|| collection_name.contains('\n') || collection_name.contains('\r')
		|| collection_name.contains('\0') {
		return error('Chroma collection name must be non-empty, at most 512 bytes, and contain no line breaks')
	}
	if options.collection_id != '' {
		return error('collection_id must be empty when creating a named Chroma collection')
	}
	mut base := new_store_config(embedder, options, false)!
	base.http_client = http_client
	body := json2.encode(map[string]json2.Any{
		'name':          json2.Any(collection_name)
		'get_or_create': json2.Any(get_or_create)
	}, json2.EncoderOptions{})
	url := '${base.base_url}/api/v2/tenants/${base.tenant}/databases/${base.database}/collections'
	response := base.request_to(mut ctx, .post, url, body)!
	decoded := json2.decode[map[string]json2.Any](response.body, json2.DecoderOptions{}) or {
		return error('Chroma returned invalid collection JSON')
	}
	id_value := decoded['id'] or { return error('Chroma collection response is missing its ID') }
	if id_value !is string || !valid_path_segment(id_value as string) {
		return error('Chroma returned an invalid collection ID')
	}
	return Store{
		base_url:      base.base_url
		tenant:        base.tenant
		database:      base.database
		collection_id: id_value as string
		api_key:       base.api_key
		namespace:     base.namespace
		embedder:      base.embedder
		http_client:   base.http_client
	}
}

// delete_collection deletes the collection bound to this store and its records.
pub fn (store Store) delete_collection(mut ctx context.Context) ! {
	if !valid_path_segment(store.collection_id) {
		return error('Chroma collection ID is required for collection deletion')
	}
	url := '${store.base_url}/api/v2/tenants/${store.tenant}/databases/${store.database}/collections/${store.collection_id}'
	store.request_to(mut ctx, .delete, url, '')!
}

// add_documents embeds and upserts at most 64 documents to Chroma.
pub fn (store Store) add_documents(mut ctx context.Context, documents []schema.Document, options vectorstores.StoreOptions) ![]string {
	if documents.len == 0 {
		return []string{}
	}
	if documents.len > max_documents_per_write {
		return error('Chroma writes are limited to 64 documents per call')
	}
	mut input_bytes := 0
	for document in documents {
		if namespace_metadata_key in document.metadata {
			return error('document metadata uses the reserved Chroma namespace key `${namespace_metadata_key}`')
		}
		metadata_bytes := json2.encode(document.metadata, json2.EncoderOptions{}).len
		if document.page_content.len > max_payload_bytes - input_bytes
			|| metadata_bytes > max_payload_bytes - input_bytes - document.page_content.len {
			return error('Chroma documents and metadata exceed 4 MiB')
		}
		input_bytes += document.page_content.len + metadata_bytes
		for _, value in document.metadata {
			if !valid_metadata_value(value) {
				return error('Chroma metadata supports scalar values only')
			}
		}
	}
	vectors := store.embedder.embed_documents(mut ctx, documents.map(it.page_content))!
	if vectors.len != documents.len {
		return error('embedder returned ${vectors.len} vectors for ${documents.len} documents')
	}
	mut ids := []string{cap: documents.len}
	mut wire_ids := []json2.Any{cap: documents.len}
	mut wire_documents := []json2.Any{cap: documents.len}
	mut metadatas := []json2.Any{cap: documents.len}
	mut embeddings_values := []json2.Any{cap: documents.len}
	mut dimension := -1
	mut embedding_value_count := 0
	for index, document in documents {
		vector := vectors[index]
		if vector.len == 0 || (dimension > 0 && vector.len != dimension) {
			return error('Chroma embeddings must be non-empty and have consistent dimensions')
		}
		if vector.len > max_embedding_values - embedding_value_count {
			return error('Chroma write has too many embedding values')
		}
		embedding_value_count += vector.len
		dimension = vector.len
		mut wire_vector := []json2.Any{cap: vector.len}
		for value in vector {
			if !math.is_finite(f64(value)) {
				return error('Chroma embeddings must contain finite values')
			}
			wire_vector << json2.Any(value)
		}
		id := rand.uuid_v4()
		ids << id
		wire_ids << json2.Any(id)
		mut metadata := document.metadata.clone()
		namespace := if options.namespace == '' { store.namespace } else { options.namespace }
		metadata[namespace_metadata_key] = json2.Any(namespace)
		wire_documents << json2.Any(document.page_content)
		metadatas << json2.Any(metadata)
		embeddings_values << json2.Any(wire_vector)
	}
	body := json2.encode(map[string]json2.Any{
		'ids':        json2.Any(wire_ids)
		'documents':  json2.Any(wire_documents)
		'metadatas':  json2.Any(metadatas)
		'embeddings': json2.Any(embeddings_values)
	}, json2.EncoderOptions{})
	store.request(mut ctx, .post, 'upsert', body)!
	return ids
}

// similarity_search embeds a query and returns the nearest Chroma records.
pub fn (store Store) similarity_search(mut ctx context.Context, query string, limit int, options vectorstores.SearchOptions) ![]schema.Document {
	if limit < 0 || limit > max_search_limit {
		return error('Chroma search limit must be between zero and 1000')
	}
	if limit == 0 {
		return []schema.Document{}
	}
	if query.len > 65536 {
		return error('Chroma query exceeds 64 KiB')
	}
	if options.distance_strategy != '' && options.distance_strategy !in ['cosine', 'euclidean'] {
		return error('Chroma supports cosine or euclidean distance strategies')
	}
	if options.min_score != none && !math.is_finite(f64(options.min_score or { f32(0) })) {
		return error('Chroma minimum score must be finite')
	}
	for key, value in options.filter {
		if key.trim_space() == '' || key == namespace_metadata_key || !valid_metadata_value(value) {
			return error('Chroma filters need non-empty keys and scalar values')
		}
	}
	vector := store.embedder.embed_query(mut ctx, query)!
	if vector.len == 0 {
		return error('Chroma query embedding must not be empty')
	}
	if vector.len > max_embedding_values {
		return error('Chroma query embedding exceeds the 65,536-value limit')
	}
	mut values := []json2.Any{cap: vector.len}
	for value in vector {
		if !math.is_finite(f64(value)) {
			return error('Chroma query embedding must contain finite values')
		}
		values << json2.Any(value)
	}
	mut include := [json2.Any('documents'), json2.Any('metadatas'), json2.Any('distances')]
	if options.include_vectors {
		include << json2.Any('embeddings')
	}
	mut request := map[string]json2.Any{
		'query_embeddings': json2.Any([json2.Any(values)])
		'n_results':        json2.Any(limit)
		'include':          json2.Any(include)
	}
	namespace := if options.namespace == '' { store.namespace } else { options.namespace }
	where := make_filter(options.filter, namespace)
	if where.len > 0 {
		request['where'] = json2.Any(where)
	}
	response := store.request(mut ctx, .post, 'query', json2.encode(request, json2.EncoderOptions{}))!
	decoded := json2.decode[map[string]json2.Any](response.body, json2.DecoderOptions{}) or {
		return error('Chroma returned invalid query JSON')
	}
	ids := chroma_nested_array(decoded, 'ids')!
	documents := chroma_nested_array(decoded, 'documents')!
	metadatas := chroma_nested_array(decoded, 'metadatas')!
	distances := chroma_nested_array(decoded, 'distances')!
	mut embeddings_values := [][]json2.Any{}
	if options.include_vectors {
		embeddings_values = chroma_nested_array(decoded, 'embeddings')!
	}
	if ids.len != 1 || documents.len != 1 || metadatas.len != 1 || distances.len != 1
		|| (options.include_vectors && embeddings_values.len != 1) {
		return error('Chroma returned an unexpected number of query result groups')
	}
	if ids[0].len != documents[0].len || ids[0].len != metadatas[0].len
		|| ids[0].len != distances[0].len || ids[0].len > limit
		|| (options.include_vectors && ids[0].len != embeddings_values[0].len) {
		return error('Chroma returned mismatched or excessive query result lengths')
	}
	mut results := []schema.Document{cap: ids[0].len}
	for index, id_any in ids[0] {
		if id_any !is string || documents[0][index] !is string {
			return error('Chroma returned a malformed record ID or document')
		}
		mut metadata := chroma_metadata(metadatas[0][index])!
		metadata.delete(namespace_metadata_key)
		distance := chroma_float(distances[0][index])!
		score := f32(1.0 - distance)
		minimum := options.min_score or { f32(-1.0e30) }
		if score < minimum {
			continue
		}
		if !options.include_metadata {
			metadata = map[string]json2.Any{}
		}
		mut embedding := []f32{}
		if options.include_vectors {
			vector_value := embeddings_values[0][index]
			if vector_value !is []json2.Any {
				return error('Chroma returned a malformed embedding')
			}
			returned_values := vector_value as []json2.Any
			if returned_values.len == 0 || returned_values.len > max_embedding_values {
				return error('Chroma returned an empty or oversized embedding')
			}
			embedding = []f32{cap: returned_values.len}
			for value in returned_values {
				embedding << chroma_float(value)!
			}
		}
		results << schema.Document{
			page_content: documents[0][index] as string
			metadata:     metadata
			score:        score
			embedding:    embedding
		}
	}
	return results
}

// delete removes records by ID, optionally restricting deletion to a namespace.
pub fn (store Store) delete(mut ctx context.Context, ids []string, options vectorstores.StoreOptions) ! {
	if ids.len == 0 {
		return
	}
	if ids.len > 1000 {
		return error('Chroma delete is limited to 1000 IDs per call')
	}
	for id in ids {
		if id.trim_space() == '' || id.len > 512 {
			return error('Chroma IDs must be non-empty and at most 512 bytes')
		}
	}
	mut wire_ids := []json2.Any{cap: ids.len}
	for id in ids {
		wire_ids << json2.Any(id)
	}
	mut request := map[string]json2.Any{
		'ids': json2.Any(wire_ids)
	}
	namespace := if options.namespace == '' { store.namespace } else { options.namespace }
	if namespace != '' {
		request['where'] = json2.Any({
			namespace_metadata_key: json2.Any({
				'$eq': json2.Any(namespace)
			})
		})
	}
	store.request(mut ctx, .post, 'delete', json2.encode(request, json2.EncoderOptions{}))!
}

fn (store Store) request(mut ctx context.Context, method http.Method, operation string, body string) !httputil.Response {
	url := '${store.base_url}/api/v2/tenants/${store.tenant}/databases/${store.database}/collections/${store.collection_id}/${operation}'
	return store.request_to(mut ctx, method, url, body)
}

fn (store Store) request_to(mut ctx context.Context, method http.Method, url string, body string) !httputil.Response {
	if body.len > max_payload_bytes {
		return error('Chroma request exceeds 4 MiB')
	}
	mut headers := map[string]string{
		'Content-Type': 'application/json'
		'Accept':       'application/json'
	}
	if store.api_key != '' {
		headers['x-chroma-token'] = store.api_key
	}
	response := store.http_client.do(mut ctx, httputil.Request{
		method:  method
		url:     url
		headers: headers
		body:    body
	}) or {
		return error('Chroma request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Chroma request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_payload_bytes {
		return error('Chroma response exceeds 4 MiB')
	}
	return response
}

fn chroma_nested_array(fields map[string]json2.Any, key string) ![][]json2.Any {
	value := fields[key] or { return error('Chroma response is missing ${key}') }
	if value !is []json2.Any {
		return error('Chroma ${key} must be an array')
	}
	groups := value as []json2.Any
	mut result := [][]json2.Any{cap: groups.len}
	for group in groups {
		if group !is []json2.Any {
			return error('Chroma ${key} groups must be arrays')
		}
		result << (group as []json2.Any)
	}
	return result
}

fn chroma_metadata(value json2.Any) !map[string]json2.Any {
	if value is json2.Null {
		return map[string]json2.Any{}
	}
	if value !is map[string]json2.Any {
		return error('Chroma metadata entries must be objects or null')
	}
	return (value as map[string]json2.Any).clone()
}

fn make_filter(filters map[string]json2.Any, namespace string) map[string]json2.Any {
	mut conditions := []json2.Any{cap: filters.len + 1}
	for key, value in filters {
		conditions << json2.Any({
			key: json2.Any({
				'$eq': value
			})
		})
	}
	if namespace != '' {
		conditions << json2.Any({
			namespace_metadata_key: json2.Any({
				'$eq': json2.Any(namespace)
			})
		})
	}
	if conditions.len == 1 {
		return conditions[0] as map[string]json2.Any
	}
	if conditions.len > 1 {
		return {
			'$and': json2.Any(conditions)
		}
	}
	return map[string]json2.Any{}
}

fn valid_metadata_value(value json2.Any) bool {
	return match value {
		string, bool, int, i64, i32, i16, i8, u64, u32, u16, u8 { true }
		f64 { math.is_finite(value as f64) }
		f32 { math.is_finite(f64(value as f32)) }
		else { false }
	}
}

fn chroma_float(value json2.Any) !f32 {
	if value is f64 {
		number := value as f64
		if math.is_finite(number) {
			converted := f32(number)
			if math.is_finite(f64(converted)) {
				return converted
			}
		}
	}
	if value is i64 {
		converted := f32(value as i64)
		if math.is_finite(f64(converted)) {
			return converted
		}
	}
	if value is int {
		converted := f32(value as int)
		if math.is_finite(f64(converted)) {
			return converted
		}
	}
	return error('Chroma returned a non-numeric distance')
}

fn valid_path_segment(value string) bool {
	if value.trim_space() == '' || value.len > 128 || value in ['.', '..'] {
		return false
	}
	for byte_value in value.bytes() {
		if !((byte_value >= `a` && byte_value <= `z`) || (byte_value >= `A` && byte_value <= `Z`)
			|| (byte_value >= `0` && byte_value <= `9`) || byte_value in [`-`, `_`, `.`]) {
			return false
		}
	}
	return true
}
