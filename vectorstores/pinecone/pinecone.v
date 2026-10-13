// Package pinecone implements Pinecone's HTTPS vector data-plane API.
module pinecone

import context
import json2
import math
import net.http
import rand
import ulises_jeremias.langchainv.embeddings
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.vectorstores

const api_version = '2025-10'
const max_vectors_per_write = 64
const max_payload_bytes = 4 * 1024 * 1024
const max_top_k = 1000
const max_embedding_values = 65536
const page_content_key = '_langchainv_page_content'

// Store connects to one Pinecone index host and uses an injected embedder.
pub struct Store {
pub:
	host    string
	api_key string
pub mut:
	embedder    embeddings.Embedder
	http_client httputil.HTTPClient
}

// Options configures the index host and API key.
pub struct Options {
pub:
	host    string
	api_key string
}

// new_store creates a Pinecone adapter for a provisioned index host.
pub fn new_store(embedder embeddings.Embedder, options Options) !Store {
	if options.api_key.trim_space() == '' || options.api_key.len > 4096
		|| options.api_key.contains('\n') || options.api_key.contains('\r') {
		return error('Pinecone API key is required and must be at most 4096 bytes')
	}
	host := options.host.trim_space().trim_right('/')
	if host == '' || host.len > 2048 {
		return error('Pinecone index host is required and must be at most 2048 bytes')
	}
	httputil.validate_url(host, 'https')!
	scheme_end := host.index('://') or { return error('Pinecone index host is invalid') }
	authority := host[scheme_end + 3..]
	if authority.contains('/') || authority.contains('?') || authority.contains('#') {
		return error('Pinecone index host must not contain a path, query, or fragment')
	}
	return Store{
		host:        host
		api_key:     options.api_key
		embedder:    embedder
		http_client: httputil.DefaultClient{
			max_request_bytes:  i64(max_payload_bytes)
			max_response_bytes: i64(max_payload_bytes)
		}
	}
}

// add_documents embeds and upserts up to 64 documents in one namespace.
pub fn (store Store) add_documents(mut ctx context.Context, documents []schema.Document, options vectorstores.StoreOptions) ![]string {
	if documents.len == 0 {
		return []string{}
	}
	if documents.len > max_vectors_per_write {
		return error('Pinecone writes are limited to 64 vectors per call')
	}
	mut input_bytes := 0
	for document in documents {
		if page_content_key in document.metadata {
			return error('document metadata contains the reserved Pinecone payload key `${page_content_key}`')
		}
		metadata_bytes := json2.encode(document.metadata, json2.EncoderOptions{}).len
		if document.page_content.len > max_payload_bytes - input_bytes
			|| metadata_bytes > max_payload_bytes - input_bytes - document.page_content.len {
			return error('Pinecone document content and metadata exceed 4 MiB')
		}
		input_bytes += document.page_content.len + metadata_bytes
		for _, value in document.metadata {
			if !valid_metadata_value(value) {
				return error('Pinecone metadata supports scalar values and arrays of strings only')
			}
		}
	}
	vectors := store.embedder.embed_documents(mut ctx, documents.map(it.page_content))!
	if vectors.len != documents.len {
		return error('embedder returned ${vectors.len} vectors for ${documents.len} documents')
	}
	mut wire_vectors := []json2.Any{cap: documents.len}
	mut ids := []string{cap: documents.len}
	mut dimension := -1
	for index, document in documents {
		vector := vectors[index]
		if vector.len == 0 || (dimension > 0 && vector.len != dimension) {
			return error('Pinecone embeddings must be non-empty and have consistent dimensions')
		}
		dimension = vector.len
		mut values := []json2.Any{cap: vector.len}
		for value in vector {
			if !math.is_finite(f64(value)) {
				return error('Pinecone embeddings must contain finite values')
			}
			values << json2.Any(value)
		}
		id := rand.uuid_v4()
		ids << id
		mut metadata := document.metadata.clone()
		metadata[page_content_key] = json2.Any(document.page_content)
		wire_vectors << json2.Any(map[string]json2.Any{
			'id':       json2.Any(id)
			'values':   json2.Any(values)
			'metadata': json2.Any(metadata)
		})
	}
	body := json2.encode(map[string]json2.Any{
		'vectors':   json2.Any(wire_vectors)
		'namespace': json2.Any(options.namespace)
	}, json2.EncoderOptions{})
	store.request(mut ctx, .post, '/vectors/upsert', body)!
	return ids
}

// similarity_search queries the index and returns stored documents by score.
pub fn (store Store) similarity_search(mut ctx context.Context, query string, limit int, options vectorstores.SearchOptions) ![]schema.Document {
	if limit < 0 || limit > max_top_k {
		return error('Pinecone search limit must be between zero and 1000')
	}
	if limit == 0 {
		return []schema.Document{}
	}
	if query.len > 65536 {
		return error('Pinecone query exceeds 64 KiB')
	}
	if options.distance_strategy != '' && options.distance_strategy !in ['cosine', 'dotproduct',
		'euclidean'] {
		return error('Pinecone distance strategy must be cosine, dotproduct, or euclidean')
	}
	if options.min_score != none && !math.is_finite(f64(options.min_score or { f32(0) })) {
		return error('Pinecone minimum score must be finite')
	}
	validate_filter(options.filter, 0)!
	vector := store.embedder.embed_query(mut ctx, query)!
	if vector.len == 0 {
		return error('Pinecone query embedding must not be empty')
	}
	mut values := []json2.Any{cap: vector.len}
	for value in vector {
		if !math.is_finite(f64(value)) {
			return error('Pinecone query embedding must contain finite values')
		}
		values << json2.Any(value)
	}
	mut request := map[string]json2.Any{
		'vector':          json2.Any(values)
		'namespace':       json2.Any(options.namespace)
		'topK':            json2.Any(limit)
		'includeMetadata': json2.Any(true)
	}
	if options.include_vectors {
		request['includeValues'] = json2.Any(true)
	}
	if options.filter.len > 0 {
		request['filter'] = json2.Any(make_filter(options.filter))
	}
	body := json2.encode(request, json2.EncoderOptions{})
	response := store.request(mut ctx, .post, '/query', body)!
	decoded := json2.decode[map[string]json2.Any](response.body, json2.DecoderOptions{}) or {
		return error('Pinecone returned invalid query JSON')
	}
	matches_any := decoded['matches'] or { return error('Pinecone query response has no matches') }
	if matches_any !is []json2.Any {
		return error('Pinecone matches must be an array')
	}
	matches := matches_any as []json2.Any
	if matches.len > limit {
		return error('Pinecone returned more matches than requested')
	}
	mut documents := []schema.Document{cap: matches.len}
	for match_any in matches {
		if match_any !is map[string]json2.Any {
			return error('Pinecone returned a malformed match')
		}
		match_fields := match_any as map[string]json2.Any
		metadata_any := match_fields['metadata'] or { return error('Pinecone match has no metadata') }
		if metadata_any !is map[string]json2.Any {
			return error('Pinecone match metadata must be an object')
		}
		mut metadata := (metadata_any as map[string]json2.Any).clone()
		content_any := metadata[page_content_key] or {
			return error('Pinecone match is missing the stored page content')
		}
		if content_any !is string {
			return error('Pinecone page content metadata must be a string')
		}
		metadata.delete(page_content_key)
		score := pinecone_float(match_fields['score'] or { return error('Pinecone match has no score') })!
		if options.min_score != none && score < (options.min_score or { f32(0) }) {
			continue
		}
		if !options.include_metadata {
			metadata = map[string]json2.Any{}
		}
		mut embedding := []f32{}
		if options.include_vectors {
			values_any := match_fields['values'] or { return error('Pinecone match has no vector values') }
			if values_any !is []json2.Any {
				return error('Pinecone match values must be an array')
			}
			match_values := values_any as []json2.Any
			if match_values.len == 0 || match_values.len > max_embedding_values {
				return error('Pinecone returned an empty or oversized vector')
			}
			embedding = []f32{cap: match_values.len}
			for value in match_values {
				embedding << pinecone_vector_float(value)!
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

// delete removes the supplied vector IDs from one namespace.
pub fn (store Store) delete(mut ctx context.Context, ids []string, options vectorstores.StoreOptions) ! {
	if ids.len == 0 {
		return
	}
	if ids.len > 1000 {
		return error('Pinecone delete is limited to 1000 IDs per call')
	}
	mut wire_ids := []json2.Any{cap: ids.len}
	for id in ids {
		if id.trim_space() == '' || id.len > 512 {
			return error('Pinecone vector IDs must be non-empty and at most 512 bytes')
		}
		wire_ids << json2.Any(id)
	}
	body := json2.encode(map[string]json2.Any{
		'ids':       json2.Any(wire_ids)
		'namespace': json2.Any(options.namespace)
	}, json2.EncoderOptions{})
	store.request(mut ctx, .post, '/vectors/delete', body)!
}

fn (store Store) request(mut ctx context.Context, method http.Method, path string, body string) !httputil.Response {
	if body.len > max_payload_bytes {
		return error('Pinecone request exceeds 4 MiB')
	}
	response := store.http_client.do(mut ctx, httputil.Request{
		method:  method
		url:     '${store.host}${path}'
		headers: {
			'Api-Key':                store.api_key
			'Content-Type':           'application/json'
			'Accept':                 'application/json'
			'X-Pinecone-Api-Version': api_version
		}
		body:    body
	}) or {
		return error('Pinecone request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Pinecone request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_payload_bytes {
		return error('Pinecone response exceeds 4 MiB')
	}
	return response
}

fn make_filter(metadata map[string]json2.Any) map[string]json2.Any {
	mut filter := map[string]json2.Any{}
	for key, value in metadata {
		if key.starts_with('$') {
			children := value as []json2.Any
			mut child_filters := []json2.Any{cap: children.len}
			for child in children {
				child_filters << json2.Any(make_filter(child as map[string]json2.Any))
			}
			filter[key] = json2.Any(child_filters)
			continue
		}
		if value is map[string]json2.Any {
			filter[key] = value
			continue
		}
		filter[key] = json2.Any({
			'\$eq': value
		})
	}
	return filter
}

const max_filter_depth = 3
const max_filter_children = 50
const max_filter_list_items = 100

fn validate_filter(filter map[string]json2.Any, depth int) ! {
	if depth > max_filter_depth {
		return error('Pinecone filter nesting exceeds the supported depth')
	}
	for key, value in filter {
		if key.starts_with('$') {
			if key !in ['$and', '$or'] {
				return error('Pinecone filter supports only $and and $or logical operators')
			}
			if value !is []json2.Any {
				return error('Pinecone filter ${key} requires an array of filter objects')
			}
			children := value as []json2.Any
			if children.len == 0 || children.len > max_filter_children {
				return error('Pinecone filter ${key} requires between 1 and 50 filter objects')
			}
			for child in children {
				if child !is map[string]json2.Any {
					return error('Pinecone filter ${key} requires an array of filter objects')
				}
				validate_filter(child as map[string]json2.Any, depth + 1)!
			}
			continue
		}
		if key.trim_space() == '' || key == page_content_key {
			return error('Pinecone filters require non-empty metadata keys')
		}
		if value is map[string]json2.Any {
			validate_operator_object(value as map[string]json2.Any)!
		} else if !valid_metadata_value(value) {
			return error('Pinecone filters require scalar or string-array values')
		}
	}
}

fn validate_operator_object(operators map[string]json2.Any) ! {
	if operators.len == 0 {
		return error('Pinecone filter operator objects must not be empty')
	}
	for operator, operand in operators {
		if operator !in ['$eq', '$ne', '$gt', '$gte', '$lt', '$lte', '$in', '$nin', '$exists'] {
			return error('Pinecone filter operator ${operator} is not supported')
		}
		if operator in ['$in', '$nin'] {
			if operand !is []json2.Any {
				return error('Pinecone filter ${operator} requires an array operand')
			}
			items := operand as []json2.Any
			if items.len == 0 || items.len > max_filter_list_items {
				return error('Pinecone filter ${operator} requires between 1 and 100 items')
			}
			for item in items {
				if !valid_filter_scalar(item) {
					return error('Pinecone filter ${operator} requires scalar items')
				}
			}
		} else if operator == '$exists' {
			if operand !is bool {
				return error('Pinecone filter $exists requires a boolean operand')
			}
		} else if !valid_filter_scalar(operand) {
			return error('Pinecone filter ${operator} requires a scalar operand')
		}
	}
}

fn valid_filter_scalar(value json2.Any) bool {
	return match value {
		string, bool, int, i64, i32, i16, i8, u64, u32, u16, u8 { true }
		f64 { math.is_finite(value as f64) }
		f32 { math.is_finite(f64(value as f32)) }
		else { false }
	}
}

fn valid_metadata_value(value json2.Any) bool {
	return match value {
		string, bool, int, i64, i32, i16, i8, u64, u32, u16, u8 { true }
		f64 { math.is_finite(value as f64) }
		f32 { math.is_finite(f64(value as f32)) }
		[]json2.Any {
			for item in value {
				if item !is string {
					return false
				}
			}
			true
		}
		else { false }
	}
}

fn pinecone_float(value json2.Any) !f32 {
	if value is f64 {
		number := value as f64
		if math.is_finite(number) {
			return f32(number)
		}
	}
	if value is int {
		return f32(value as int)
	}
	return error('Pinecone score must be a finite number')
}

fn pinecone_vector_float(value json2.Any) !f32 {
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
	return error('Pinecone vector values must be finite numbers')
}
