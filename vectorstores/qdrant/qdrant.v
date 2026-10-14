// Package qdrant implements a bounded REST client for Qdrant collections.
module qdrant

import context
import json2
import math
import net.http
import rand
import net.urllib
import ulises_jeremias.langchainv.embeddings
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.vectorstores

const max_documents_per_write = 64
const max_payload_bytes = 4 * 1024 * 1024
const max_search_limit = 1000
const max_embedding_values = 65536

// Store writes embeddings and payloads to one Qdrant collection.
pub struct Store {
pub:
	base_url    string = 'http://127.0.0.1:6333'
	collection  string
	api_key     string
	vector_size int
pub mut:
	embedder    embeddings.Embedder
	http_client httputil.HTTPClient
}

// new_store creates a Qdrant adapter. The collection must already exist and
// must use a vector size and distance metric compatible with the embedder.
pub fn new_store(collection string, embedder embeddings.Embedder, options StoreOptions) !Store {
	if !valid_collection(collection) {
		return error('Qdrant collection name is invalid')
	}
	base_url := if options.base_url.trim_space() == '' {
		'http://127.0.0.1:6333'
	} else {
		options.base_url.trim_space()
	}
	httputil.validate_url(base_url, '')!
	if base_url.ends_with('/') || base_url.len > 2048 {
		return error('Qdrant base URL must not end with a slash and must be at most 2048 bytes')
	}
	if options.api_key.len > 4096 || options.api_key.contains('\n') || options.api_key.contains('\r') {
		return error('Qdrant API key is invalid or exceeds 4096 bytes')
	}
	parsed_url := urllib.parse(base_url) or { return error('Qdrant base URL is invalid') }
	if parsed_url.scheme.to_lower() == 'http' && parsed_url.host.to_lower() !in [
		'localhost',
		'127.0.0.1',
		'::1',
	] {
		return error('Qdrant remote endpoints must use HTTPS')
	}
	return Store{
		base_url:    base_url
		collection:  collection
		api_key:     options.api_key
		embedder:    embedder
		http_client: httputil.DefaultClient{
			max_request_bytes:  max_payload_bytes
			max_response_bytes: max_payload_bytes
		}
	}
}

// new_store_with_collection creates a single-vector cosine collection and
// returns a store bound to it. The embedder's output dimension must equal
// vector_size.
pub fn new_store_with_collection(mut ctx context.Context, collection string, vector_size int, embedder embeddings.Embedder, options StoreOptions) !Store {
	client := httputil.HTTPClient(httputil.DefaultClient{
		max_request_bytes:  max_payload_bytes
		max_response_bytes: max_payload_bytes
	})
	return new_store_with_collection_and_client(mut ctx, collection, vector_size, embedder,
		options, client)
}

// new_store_with_collection_and_client creates a collection with the supplied
// HTTP transport. It supports custom transports and deterministic offline tests.
pub fn new_store_with_collection_and_client(mut ctx context.Context, collection string, vector_size int, embedder embeddings.Embedder, options StoreOptions, http_client httputil.HTTPClient) !Store {
	if vector_size <= 0 || vector_size > 65536 {
		return error('Qdrant vector size must be between 1 and 65536')
	}
	mut store := new_store(collection, embedder, options)!
	store.http_client = http_client
	body := json2.encode(map[string]json2.Any{
		'vectors': json2.Any({
			'size':     json2.Any(vector_size)
			'distance': json2.Any('Cosine')
		})
	}, json2.EncoderOptions{})
	store.request_to(mut ctx, .put, '${store.base_url}/collections/${store.collection}', body)!
	return Store{
		base_url:    store.base_url
		collection:  store.collection
		api_key:     store.api_key
		vector_size: vector_size
		embedder:    store.embedder
		http_client: store.http_client
	}
}

// delete_collection deletes the collection bound to this store and its points.
pub fn (store Store) delete_collection(mut ctx context.Context) ! {
	store.request_to(mut ctx, .delete, '${store.base_url}/collections/${store.collection}', '')!
}

// StoreOptions configures endpoint, collection auth, and the embedder.
pub struct StoreOptions {
pub:
	base_url string
	api_key  string
}

// add_documents embeds and upserts documents in bounded batches.
pub fn (store Store) add_documents(mut ctx context.Context, documents []schema.Document, options vectorstores.StoreOptions) ![]string {
	if documents.len == 0 {
		return []string{}
	}
	if documents.len > max_documents_per_write {
		return error('Qdrant writes are limited to 64 documents per call')
	}
	mut input_bytes := 0
	for document in documents {
		metadata_bytes := json2.encode(document.metadata, json2.EncoderOptions{}).len
		if document.page_content.len > max_payload_bytes - input_bytes
			|| metadata_bytes > max_payload_bytes - input_bytes - document.page_content.len {
			return error('Qdrant document content and metadata exceed 4 MiB')
		}
		input_bytes += document.page_content.len + metadata_bytes
	}
	mut caller_ids := []string{cap: documents.len}
	for document in documents {
		if id_value := document.metadata['id'] {
			if id_value !is string || !valid_uuid(id_value as string) {
				return error('Qdrant document id metadata must be a UUID string')
			}
			caller_id := id_value as string
			if caller_id in caller_ids {
				return error('Qdrant document id metadata must be unique within one write')
			}
			caller_ids << caller_id
		} else {
			caller_ids << ''
		}
	}
	texts := documents.map(it.page_content)
	vectors := store.embedder.embed_documents(mut ctx, texts)!
	if vectors.len != documents.len {
		return error('embedder returned ${vectors.len} vectors for ${documents.len} documents')
	}
	mut points := []json2.Any{cap: documents.len}
	mut ids := []string{cap: documents.len}
	mut dimension := -1
	for index, document in documents {
		vector := vectors[index]
		if vector.len == 0 || (dimension > 0 && vector.len != dimension) {
			return error('Qdrant embeddings must be non-empty and have consistent dimensions')
		}
		if store.vector_size > 0 && vector.len != store.vector_size {
			return error('Qdrant embedding dimension does not match the collection vector size')
		}
		dimension = vector.len
		mut wire_vector := []json2.Any{cap: vector.len}
		for value in vector {
			if !math.is_finite(f64(value)) {
				return error('Qdrant embeddings must contain finite values')
			}
			wire_vector << json2.Any(value)
		}
		id := if caller_ids[index] != '' { caller_ids[index] } else { rand.uuid_v4() }
		ids << id
		mut stored_metadata := document.metadata.clone()
		stored_metadata.delete('id')
		mut payload := map[string]json2.Any{
			'page_content': json2.Any(document.page_content)
			'metadata':     json2.Any(stored_metadata)
		}
		if options.namespace != '' {
			payload['namespace'] = json2.Any(options.namespace)
		}
		points << json2.Any(map[string]json2.Any{
			'id':      json2.Any(id)
			'vector':  json2.Any(wire_vector)
			'payload': json2.Any(payload)
		})
	}
	body := json2.encode(map[string]json2.Any{
		'points': json2.Any(points)
	}, json2.EncoderOptions{})
	if body.len > max_payload_bytes {
		return error('Qdrant write payload exceeds 4 MiB')
	}
	store.request(mut ctx, .put, '/points?wait=true', body)!
	return ids
}

// similarity_search embeds the query and retrieves the nearest payloads.
pub fn (store Store) similarity_search(mut ctx context.Context, query string, limit int, options vectorstores.SearchOptions) ![]schema.Document {
	if limit < 0 || limit > max_search_limit {
		return error('Qdrant search limit must be between zero and 1000')
	}
	if limit == 0 {
		return []schema.Document{}
	}
	if query.len > 65536 {
		return error('Qdrant query exceeds 64 KiB')
	}
	if options.distance_strategy != '' && options.distance_strategy != 'cosine' {
		return error('Qdrant score filtering currently supports cosine similarity only')
	}
	if options.min_score != none && !math.is_finite(f64(options.min_score or { f32(0) })) {
		return error('Qdrant minimum score must be finite')
	}
	vector := store.embedder.embed_query(mut ctx, query)!
	if vector.len == 0 {
		return error('Qdrant query embedding must not be empty')
	}
	if store.vector_size > 0 && vector.len != store.vector_size {
		return error('Qdrant query embedding dimension does not match the collection vector size')
	}
	mut query_values := []json2.Any{cap: vector.len}
	for value in vector {
		if !math.is_finite(f64(value)) {
			return error('Qdrant query embedding must contain finite values')
		}
		query_values << json2.Any(value)
	}
	mut request := map[string]json2.Any{
		'query':        json2.Any(query_values)
		'limit':        json2.Any(limit)
		'with_payload': json2.Any(true)
	}
	if options.include_vectors {
		request['with_vector'] = json2.Any(true)
	}
	filter := make_filter(options.filter, options.namespace)!
	if filter.len > 0 {
		request['filter'] = json2.Any(filter)
	}
	response := store.request(mut ctx, .post, '/points/query', json2.encode(request,
		json2.EncoderOptions{}))!
	decoded := json2.decode[map[string]json2.Any](response.body, json2.DecoderOptions{}) or {
		return error('Qdrant returned invalid search JSON')
	}
	root := decoded['result'] or { return error('Qdrant search response has no result') }
	result := root as map[string]json2.Any
	items := result['points'] or { return error('Qdrant search response has no points') }
	points := items as []json2.Any
	if points.len > limit {
		return error('Qdrant returned more points than requested')
	}
	mut documents := []schema.Document{cap: points.len}
	for point in points {
		if point !is map[string]json2.Any {
			return error('Qdrant returned a malformed point')
		}
		fields := point as map[string]json2.Any
		payload_any := fields['payload'] or { json2.Any(map[string]json2.Any{}) }
		if payload_any !is map[string]json2.Any {
			return error('Qdrant returned malformed payload data')
		}
		payload := payload_any as map[string]json2.Any
		content_any := payload['page_content'] or { return error('Qdrant payload is missing page_content') }
		if content_any !is string {
			return error('Qdrant page_content payload must be a string')
		}
		mut metadata := map[string]json2.Any{}
		metadata_any := payload['metadata'] or { json2.Any(map[string]json2.Any{}) }
		if metadata_any !is map[string]json2.Any {
			return error('Qdrant metadata payload must be an object')
		}
		metadata = (metadata_any as map[string]json2.Any).clone()
		score := any_float(fields['score'] or { return error('Qdrant point is missing score') })!
		minimum := options.min_score or { f32(-1) }
		if score < minimum {
			continue
		}
		if !options.include_metadata {
			metadata = map[string]json2.Any{}
		}
		mut embedding := []f32{}
		if options.include_vectors {
			vector_any := fields['vector'] or { return error('Qdrant point is missing vector') }
			if vector_any !is []json2.Any {
				return error('Qdrant returned an unsupported vector shape')
			}
			vector_values := vector_any as []json2.Any
			if vector_values.len == 0 || vector_values.len > max_embedding_values {
				return error('Qdrant returned an empty or oversized vector')
			}
			embedding = []f32{cap: vector_values.len}
			for value in vector_values {
				embedding << qdrant_vector_float(value)!
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

// delete removes points by Qdrant UUID, optionally restricting the operation
// to one namespace.
pub fn (store Store) delete(mut ctx context.Context, ids []string, options vectorstores.StoreOptions) ! {
	if ids.len == 0 {
		return
	}
	if ids.len > 1000 {
		return error('Qdrant delete is limited to 1000 IDs per call')
	}
	mut points := []json2.Any{cap: ids.len}
	for id in ids {
		if !valid_uuid(id) {
			return error('Qdrant delete IDs must be UUIDs')
		}
		points << json2.Any(id)
	}
	mut selector := map[string]json2.Any{
		'points': json2.Any(points)
	}
	if options.namespace != '' {
		filter := map[string]json2.Any{
			'must': json2.Any([
				json2.Any({
					'has_id': json2.Any(points)
				}),
				json2.Any({
					'key':   json2.Any('namespace')
					'match': json2.Any({
						'value': json2.Any(options.namespace)
					})
				}),
			])
		}
		selector = map[string]json2.Any{
			'filter': json2.Any(filter)
		}
	}
	store.request(mut ctx, .post, '/points/delete?wait=true', json2.encode(selector,
		json2.EncoderOptions{}))!
}

fn (store Store) request(mut ctx context.Context, method http.Method, path string, body string) !httputil.Response {
	return store.request_to(mut ctx, method, '${store.base_url}/collections/${store.collection}${path}',
		body)
}

fn (store Store) request_to(mut ctx context.Context, method http.Method, url string, body string) !httputil.Response {
	if body.len > max_payload_bytes {
		return error('Qdrant request exceeds 4 MiB')
	}
	mut headers := {
		'Content-Type': 'application/json'
		'Accept':       'application/json'
	}
	if store.api_key != '' {
		headers['api-key'] = store.api_key
	}
	response := store.http_client.do(mut ctx, httputil.Request{
		method:  method
		url:     url
		headers: headers
		body:    body
	}) or {
		return error('Qdrant request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Qdrant request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_payload_bytes {
		return error('Qdrant response exceeds 4 MiB')
	}
	return response
}

fn make_filter(metadata map[string]json2.Any, namespace string) !map[string]json2.Any {
	mut filter := build_filter(metadata, 0)!
	if namespace != '' {
		condition := json2.Any({
			'key':   json2.Any('namespace')
			'match': json2.Any({
				'value': json2.Any(namespace)
			})
		})
		if must_any := filter['must'] {
			mut must := must_any as []json2.Any
			must << condition
			filter['must'] = json2.Any(must)
		} else {
			filter['must'] = json2.Any([condition])
		}
	}
	return filter
}

const max_filter_depth = 3
const max_filter_children = 50
const max_filter_list_items = 100

fn build_filter(metadata map[string]json2.Any, depth int) !map[string]json2.Any {
	if depth > max_filter_depth {
		return error('Qdrant filter nesting exceeds the supported depth')
	}
	mut must := []json2.Any{}
	mut should := []json2.Any{}
	mut must_not := []json2.Any{}
	for key, value in metadata {
		if key.starts_with('$') {
			match key {
				'$and', '$or' {
					children := filter_children(key, value)!
					for child in children {
						child_filter := build_filter(child, depth + 1)!
						if child_filter.len == 0 {
							continue
						}
						condition := json2.Any({
							'filter': json2.Any(child_filter)
						})
						if key == '$and' {
							must << condition
						} else {
							should << condition
						}
					}
				}
				'$not' {
					if value !is map[string]json2.Any {
						return error('Qdrant filter $not requires a filter object')
					}
					child_filter := build_filter(value as map[string]json2.Any, depth + 1)!
					must_not << json2.Any({
						'filter': json2.Any(child_filter)
					})
				}
				else {
					return error('Qdrant filter supports only $and, $or, and $not logical operators')
				}
			}
			continue
		}
		if key.trim_space() == '' {
			return error('Qdrant filters require non-empty metadata keys')
		}
		if value is map[string]json2.Any {
			operators := value as map[string]json2.Any
			if operators.len == 0 {
				return error('Qdrant filter operator objects must not be empty')
			}
			mut range := map[string]json2.Any{}
			for operator, operand in operators {
				match operator {
					'$eq' {
						must << match_condition(key, operand)!
					}
					'$ne' {
						must_not << match_condition(key, operand)!
					}
					'$in' {
						must << any_condition(key, operand)!
					}
					'$nin' {
						must_not << any_condition(key, operand)!
					}
					'$gt', '$gte', '$lt', '$lte' {
						if !valid_filter_number(operand) {
							return error('Qdrant filter ${operator} requires a numeric operand')
						}
						range[operator[1..]] = operand
					}
					'$exists' {
						if operand !is bool {
							return error('Qdrant filter $exists requires a boolean operand')
						}
						if operand as bool {
							must_not << empty_condition(key)
						} else {
							must << empty_condition(key)
						}
					}
					else {
						return error('Qdrant filter operator ${operator} is not supported')
					}
				}
			}
			if range.len > 0 {
				must << json2.Any({
					'key':   json2.Any('metadata.${key}')
					'range': json2.Any(range)
				})
			}
		} else if value is []json2.Any {
			must << any_condition(key, value)!
		} else {
			must << match_condition(key, value)!
		}
	}
	mut filter := map[string]json2.Any{}
	if must.len > 0 {
		filter['must'] = json2.Any(must)
	}
	if should.len > 0 {
		filter['should'] = json2.Any(should)
	}
	if must_not.len > 0 {
		filter['must_not'] = json2.Any(must_not)
	}
	return filter
}

fn filter_children(operator string, value json2.Any) ![]map[string]json2.Any {
	if value !is []json2.Any {
		return error('Qdrant filter ${operator} requires an array of filter objects')
	}
	items := value as []json2.Any
	if items.len == 0 || items.len > max_filter_children {
		return error('Qdrant filter ${operator} requires between 1 and 50 filter objects')
	}
	mut children := []map[string]json2.Any{cap: items.len}
	for item in items {
		if item !is map[string]json2.Any {
			return error('Qdrant filter ${operator} requires an array of filter objects')
		}
		children << item as map[string]json2.Any
	}
	return children
}

fn match_condition(key string, value json2.Any) !json2.Any {
	if !valid_filter_scalar(value) {
		return error('Qdrant filter values must be scalar')
	}
	return json2.Any({
		'key':   json2.Any('metadata.${key}')
		'match': json2.Any({
			'value': value
		})
	})
}

fn any_condition(key string, value json2.Any) !json2.Any {
	if value !is []json2.Any {
		return error('Qdrant filter $in requires an array operand')
	}
	items := value as []json2.Any
	if items.len == 0 || items.len > max_filter_list_items {
		return error('Qdrant filter $in requires between 1 and 100 items')
	}
	for item in items {
		if !valid_filter_scalar(item) {
			return error('Qdrant filter $in requires scalar items')
		}
	}
	return json2.Any({
		'key':   json2.Any('metadata.${key}')
		'match': json2.Any({
			'any': json2.Any(items)
		})
	})
}

fn empty_condition(key string) json2.Any {
	return json2.Any({
		'is_empty': json2.Any({
			'key': json2.Any('metadata.${key}')
		})
	})
}

fn valid_filter_scalar(value json2.Any) bool {
	return match value {
		string, bool, int, i64, i32, i16, i8, u64, u32, u16, u8 { true }
		f64 { math.is_finite(value as f64) }
		f32 { math.is_finite(f64(value as f32)) }
		else { false }
	}
}

fn valid_filter_number(value json2.Any) bool {
	return match value {
		int, i64, i32, i16, i8, u64, u32, u16, u8 { true }
		f64 { math.is_finite(value as f64) }
		f32 { math.is_finite(f64(value as f32)) }
		else { false }
	}
}

fn valid_collection(collection string) bool {
	if collection.len == 0 || collection.len > 255 || collection.trim_space() != collection {
		return false
	}
	for value in collection.bytes() {
		if !(value >= `a` && value <= `z`) && !(value >= `A` && value <= `Z`)
			&& !(value >= `0` && value <= `9`) && value != `-` && value != `_` && value != `.` {
			return false
		}
	}
	return true
}

fn valid_uuid(value string) bool {
	if value.len != 36 || value[8] != `-` || value[13] != `-` || value[18] != `-` || value[23] != `-` {
		return false
	}
	for byte_value in value.bytes() {
		if byte_value != `-` && !(byte_value >= `0` && byte_value <= `9`)
			&& !(byte_value >= `a` && byte_value <= `f`) && !(byte_value >= `A` && byte_value <= `F`) {
			return false
		}
	}
	return true
}

fn any_float(value json2.Any) !f32 {
	if value is f64 {
		result := value as f64
		if math.is_finite(result) {
			return f32(result)
		}
	}
	if value is int {
		return f32(value as int)
	}
	return error('Qdrant score must be a finite number')
}

fn qdrant_vector_float(value json2.Any) !f32 {
	if value is f64 {
		number := value as f64
		converted := f32(number)
		if math.is_finite(number) && math.is_finite(f64(converted)) {
			return converted
		}
	}
	if value is int {
		converted := f32(value as int)
		if math.is_finite(f64(converted)) {
			return converted
		}
	}
	return error('Qdrant vector values must be finite numbers')
}
