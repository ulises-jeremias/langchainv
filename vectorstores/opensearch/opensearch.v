// Package opensearch implements a bounded OpenSearch k-NN REST adapter.
module opensearch

import context
import encoding.base64
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
const max_embedding_values = 16000
const max_index_dimensions = 16000

// Store connects to an OpenSearch index with a k-NN vector mapping.
pub struct Store {
pub:
	base_url        string
	index           string
	api_key         string
	username        string
	password        string
	vector_field    string
	text_field      string
	metadata_field  string
	namespace_field string
pub mut:
	embedder    embeddings.Embedder
	http_client httputil.HTTPClient
}

// Options configures the endpoint, authentication, index, and source fields.
pub struct Options {
pub:
	base_url        string
	index           string
	api_key         string
	username        string
	password        string
	vector_field    string = 'vector'
	text_field      string = 'page_content'
	metadata_field  string = 'metadata'
	namespace_field string = 'namespace'
}

// new_store creates an adapter for an existing index.
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
		'http://127.0.0.1:9200'
	} else {
		options.base_url.trim_space().trim_right('/')
	}
	if base_url.len > 2048 || base_url.contains('?') || base_url.contains('#') {
		return error('OpenSearch base URL must be at most 2048 bytes and contain no query or fragment')
	}
	httputil.validate_url(base_url, '')!
	parsed_url := urllib.parse(base_url) or { return error('OpenSearch base URL is invalid') }
	if parsed_url.scheme.to_lower() == 'http' && parsed_url.host.to_lower() !in [
		'localhost',
		'127.0.0.1',
		'::1',
	] {
		return error('remote OpenSearch endpoints must use HTTPS')
	}
	if !valid_index(options.index) {
		return error('OpenSearch index name is invalid')
	}
	if options.api_key.len > 4096 || options.api_key.contains('\n') || options.api_key.contains('\r') {
		return error('OpenSearch API key is invalid or exceeds 4096 bytes')
	}
	if options.username.len > 1024 || options.password.len > 4096
		|| options.username.contains('\n') || options.username.contains('\r')
		|| options.password.contains('\n') || options.password.contains('\r') {
		return error('OpenSearch username or password is invalid')
	}
	if options.api_key != '' && (options.username != '' || options.password != '') {
		return error('OpenSearch API key and basic authentication cannot be configured together')
	}
	if (options.username == '') != (options.password == '') {
		return error('OpenSearch basic authentication requires both username and password')
	}
	fields := [options.vector_field, options.text_field, options.metadata_field,
		options.namespace_field]
	for field in fields {
		if !valid_field_name(field) {
			return error('OpenSearch field names must be valid simple field names')
		}
	}
	for i, field in fields {
		if field in fields[i + 1..] {
			return error('OpenSearch configured field names must be distinct')
		}
	}
	return Store{
		base_url:        base_url
		index:           options.index
		api_key:         options.api_key
		username:        options.username
		password:        options.password
		vector_field:    options.vector_field
		text_field:      options.text_field
		metadata_field:  options.metadata_field
		namespace_field: options.namespace_field
		embedder:        embedder
		http_client:     http_client
	}
}

// initialize_index explicitly creates a non-destructive cosine k-NN index.
// dimensions must match every vector produced by the configured embedder.
// OpenSearch returns an error when the index already exists; this method never
// deletes or replaces an existing index or mapping.
pub fn (store Store) initialize_index(mut ctx context.Context, dimensions int) ! {
	if dimensions <= 0 || dimensions > max_index_dimensions {
		return error('OpenSearch index dimensions must be between 1 and ${max_index_dimensions}')
	}
	body := '{"settings":{"index":{"knn":true}},"mappings":{"properties":{"${store.vector_field}":{"type":"knn_vector","dimension":${dimensions},"method":{"name":"hnsw","engine":"lucene","space_type":"cosinesimil"}},"${store.text_field}":{"type":"text"},"${store.metadata_field}":{"type":"object","enabled":true},"${store.namespace_field}":{"type":"keyword"}}}}'
	store.request(mut ctx, http.Method.put, '/${store.index}', body, 'application/json')!
}

// add_documents embeds and bulk-indexes up to 64 documents.
pub fn (store Store) add_documents(mut ctx context.Context, documents []schema.Document, options vectorstores.StoreOptions) ![]string {
	if documents.len == 0 {
		return []string{}
	}
	if documents.len > max_documents_per_write {
		return error('OpenSearch writes are limited to 64 documents per call')
	}
	if options.namespace.len > 65536 {
		return error('OpenSearch namespace exceeds 64 KiB')
	}
	mut input_bytes := documents.len * (store.vector_field.len + store.text_field.len + store.metadata_field.len + store.namespace_field.len + 128)
	if input_bytes > max_payload_bytes {
		return error('OpenSearch bulk payload exceeds 4 MiB')
	}
	for document in documents {
		metadata_bytes := json2.encode(document.metadata, json2.EncoderOptions{}).len
		content_bytes := json2.encode(json2.Any(document.page_content), json2.EncoderOptions{}).len
		if content_bytes > max_payload_bytes - input_bytes
			|| metadata_bytes > max_payload_bytes - input_bytes - content_bytes {
			return error('OpenSearch document content and metadata exceed 4 MiB')
		}
		input_bytes += content_bytes + metadata_bytes
		for key, _ in document.metadata {
			if !valid_field_name(key) || key == store.vector_field || key == store.text_field
				|| key == store.metadata_field || key == store.namespace_field {
				return error('OpenSearch document metadata has an invalid or reserved field `${key}`')
			}
		}
	}
	vectors := store.embedder.embed_documents(mut ctx, documents.map(it.page_content))!
	if vectors.len != documents.len {
		return error('embedder returned ${vectors.len} vectors for ${documents.len} documents')
	}
	mut dimension := -1
	namespace_bytes := json2.encode(json2.Any(options.namespace), json2.EncoderOptions{}).len
	if namespace_bytes + 128 > (max_payload_bytes - input_bytes) / documents.len {
		return error('OpenSearch bulk payload exceeds 4 MiB')
	}
	mut estimated_bytes := input_bytes + documents.len * (namespace_bytes + 128)
	for vector in vectors {
		if vector.len == 0 || vector.len > max_embedding_values || (dimension > 0 && vector.len != dimension) {
			return error('OpenSearch embeddings must be non-empty, bounded, and dimensionally consistent')
		}
		dimension = vector.len
		for value in vector {
			if !math.is_finite(f64(value)) {
				return error('OpenSearch embeddings must contain finite values')
			}
			estimated_bytes += value.str().len + 2
			if estimated_bytes > max_payload_bytes {
				return error('OpenSearch bulk payload exceeds 4 MiB')
			}
		}
	}
	mut ids := []string{cap: documents.len}
	mut lines := []string{cap: documents.len * 2}
	for index, document in documents {
		id := rand.uuid_v4()
		ids << id
		mut vector_values := []json2.Any{cap: vectors[index].len}
		for value in vectors[index] {
			vector_values << json2.Any(value)
		}
		source := map[string]json2.Any{
			store.vector_field:    json2.Any(vector_values)
			store.text_field:      json2.Any(document.page_content)
			store.metadata_field:  json2.Any(document.metadata.clone())
			store.namespace_field: json2.Any(options.namespace)
		}
		lines << json2.encode(map[string]json2.Any{
			'index': json2.Any({
				'_index': json2.Any(store.index)
				'_id':    json2.Any(id)
			})
		}, json2.EncoderOptions{})
		lines << json2.encode(source, json2.EncoderOptions{})
	}
	body := lines.join('\n') + '\n'
	response := store.request(mut ctx, .post, '/_bulk?refresh=true', body,
		'application/x-ndjson')!
	store.validate_bulk_response(response.body, documents.len)!
	return ids
}

// similarity_search runs bounded k-NN search with exact metadata filters.
pub fn (store Store) similarity_search(mut ctx context.Context, query string, limit int, options vectorstores.SearchOptions) ![]schema.Document {
	if limit < 0 || limit > max_search_limit {
		return error('OpenSearch search limit must be between zero and 1000')
	}
	if limit == 0 {
		return []schema.Document{}
	}
	if query.len > 65536 {
		return error('OpenSearch query exceeds 64 KiB')
	}
	if options.distance_strategy != '' && options.distance_strategy.to_lower() != 'cosine' {
		return error('OpenSearch adapter supports cosine score filtering only')
	}
	if options.min_score != none && !math.is_finite(f64(options.min_score or { f32(0) })) {
		return error('OpenSearch minimum score must be finite')
	}
	if options.filter.len > 128 || options.namespace.len > 65536 {
		return error('OpenSearch filters or namespace exceed configured limits')
	}
	store.validate_filter(options.filter, 0)!
	vector := store.embedder.embed_query(mut ctx, query)!
	if vector.len == 0 || vector.len > max_embedding_values {
		return error('OpenSearch query embedding must contain between 1 and 16000 values')
	}
	mut vector_values := []json2.Any{cap: vector.len}
	for value in vector {
		if !math.is_finite(f64(value)) {
			return error('OpenSearch query embeddings must contain finite values')
		}
		vector_values << json2.Any(value)
	}
	mut filters := []json2.Any{cap: options.filter.len + 1}
	mut excluded := []json2.Any{}
	if options.namespace != '' {
		filters << json2.Any({
			'term': json2.Any({
				store.namespace_field: json2.Any(options.namespace)
			})
		})
	}
	filter_must, filter_must_not := store.build_filter_clauses(options.filter, 0)!
	for clause in filter_must {
		filters << clause
	}
	for clause in filter_must_not {
		excluded << clause
	}
	mut knn := map[string]json2.Any{
		'vector': json2.Any(vector_values)
		'k':      json2.Any(limit)
	}
	if filters.len > 0 || excluded.len > 0 {
		mut bool_filter := map[string]json2.Any{}
		if filters.len > 0 {
			bool_filter['filter'] = json2.Any(filters)
		}
		if excluded.len > 0 {
			bool_filter['must_not'] = json2.Any(excluded)
		}
		knn['filter'] = json2.Any({
			'bool': json2.Any(bool_filter)
		})
	}
	mut source_fields := [json2.Any(store.text_field), json2.Any(store.metadata_field),
		json2.Any(store.namespace_field)]
	if options.include_vectors {
		source_fields << json2.Any(store.vector_field)
	}
	body := json2.encode(map[string]json2.Any{
		'size':    json2.Any(limit)
		'_source': json2.Any(source_fields)
		'query':   json2.Any({
			'knn': json2.Any({
				store.vector_field: json2.Any(knn)
			})
		})
	}, json2.EncoderOptions{})
	response := store.request(mut ctx, .post, '/${store.index}/_search', body, 'application/json')!
	decoded := json2.decode[map[string]json2.Any](response.body, json2.DecoderOptions{}) or {
		return error('OpenSearch returned invalid search JSON')
	}
	hits_any := decoded['hits'] or { return error('OpenSearch search response has no hits') }
	if hits_any !is map[string]json2.Any {
		return error('OpenSearch hits response must be an object')
	}
	hits_map := hits_any as map[string]json2.Any
	items_any := hits_map['hits'] or { return error('OpenSearch search response has no hit list') }
	if items_any !is []json2.Any {
		return error('OpenSearch hit list must be an array')
	}
	items := items_any as []json2.Any
	if items.len > limit {
		return error('OpenSearch returned more hits than requested')
	}
	mut documents := []schema.Document{cap: items.len}
	for item in items {
		if item !is map[string]json2.Any {
			return error('OpenSearch returned a malformed hit')
		}
		hit := item as map[string]json2.Any
		source_any := hit['_source'] or { return error('OpenSearch hit has no source') }
		if source_any !is map[string]json2.Any {
			return error('OpenSearch hit source must be an object')
		}
		source := source_any as map[string]json2.Any
		content_any := source[store.text_field] or { return error('OpenSearch hit has no page content') }
		if content_any !is string {
			return error('OpenSearch page content must be a string')
		}
		metadata_any := source[store.metadata_field] or { json2.Any(map[string]json2.Any{}) }
		if metadata_any !is map[string]json2.Any {
			return error('OpenSearch metadata must be an object')
		}
		mut metadata := (metadata_any as map[string]json2.Any).clone()
		score := open_search_float(hit['_score'] or { return error('OpenSearch hit has no score') })!
		if options.min_score != none && score < (options.min_score or { f32(0) }) {
			continue
		}
		if !options.include_metadata {
			metadata = map[string]json2.Any{}
		}
		mut embedding := []f32{}
		if options.include_vectors {
			vector_any := source[store.vector_field] or {
				return error('OpenSearch hit source has no vector field')
			}
			if vector_any !is []json2.Any {
				return error('OpenSearch returned an unsupported vector shape')
			}
			returned_vector_values := vector_any as []json2.Any
			if returned_vector_values.len == 0 || returned_vector_values.len > max_embedding_values {
				return error('OpenSearch returned an empty or oversized vector')
			}
			embedding = []f32{cap: returned_vector_values.len}
			for value in returned_vector_values {
				embedding << open_search_float(value)!
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

// delete removes up to 1000 OpenSearch documents by their generated IDs.
pub fn (store Store) delete(mut ctx context.Context, ids []string, _options vectorstores.StoreOptions) ! {
	if ids.len == 0 {
		return
	}
	if ids.len > 1000 {
		return error('OpenSearch delete is limited to 1000 IDs per call')
	}
	mut lines := []string{cap: ids.len}
	for id in ids {
		if id.trim_space() == '' || id.len > 512 {
			return error('OpenSearch vector IDs must be non-empty and at most 512 bytes')
		}
		lines << json2.encode(map[string]json2.Any{
			'delete': json2.Any({
				'_index': json2.Any(store.index)
				'_id':    json2.Any(id)
			})
		}, json2.EncoderOptions{})
	}
	response := store.request(mut ctx, .post, '/_bulk?refresh=true', lines.join('\n') + '\n',
		'application/x-ndjson')!
	store.validate_bulk_response(response.body, ids.len)!
}

fn (store Store) validate_bulk_response(body string, expected_items int) ! {
	decoded := json2.decode[map[string]json2.Any](body, json2.DecoderOptions{}) or {
		return error('OpenSearch returned invalid bulk response JSON')
	}
	errors_any := decoded['errors'] or { return error('OpenSearch bulk response has no errors flag') }
	if errors_any !is bool || (errors_any as bool) {
		return error('OpenSearch bulk operation reported errors')
	}
	items_any := decoded['items'] or { return error('OpenSearch bulk response has no items') }
	if items_any !is []json2.Any {
		return error('OpenSearch bulk items must be an array')
	}
	items := items_any as []json2.Any
	if items.len != expected_items {
		return error('OpenSearch returned an unexpected number of bulk items')
	}
	for item in items {
		if item !is map[string]json2.Any {
			return error('OpenSearch returned a malformed bulk item')
		}
		actions := item as map[string]json2.Any
		if actions.len != 1 {
			return error('OpenSearch bulk item has an unexpected action count')
		}
		for _, result_any in actions {
			if result_any !is map[string]json2.Any {
				return error('OpenSearch bulk action result must be an object')
			}
			result := result_any as map[string]json2.Any
			status := result['status'] or { return error('OpenSearch bulk action has no status') }
			status_code := open_search_int(status)!
			if status_code < 200 || status_code >= 300 {
				return error('OpenSearch bulk action returned HTTP ${status_code}')
			}
		}
	}
}

fn (store Store) request(mut ctx context.Context, method http.Method, path string, body string, content_type string) !httputil.Response {
	if body.len > max_payload_bytes {
		return error('OpenSearch request exceeds 4 MiB')
	}
	mut headers := {
		'Content-Type': content_type
		'Accept':       'application/json'
	}
	if store.api_key != '' {
		headers['Authorization'] = 'ApiKey ${store.api_key}'
	} else if store.username != '' {
		credentials := '${store.username}:${store.password}'
		headers['Authorization'] = 'Basic ${base64.encode(credentials.bytes())}'
	}
	response := store.http_client.do(mut ctx, httputil.Request{
		method:  method
		url:     '${store.base_url}${path}'
		headers: headers
		body:    body
	}) or {
		return error('OpenSearch request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('OpenSearch request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_payload_bytes {
		return error('OpenSearch response exceeds 4 MiB')
	}
	return response
}

fn valid_index(value string) bool {
	if value.len == 0 || value.len > 255 || value in ['.', '..'] || value.ends_with('.')
		|| value.ends_with('_') || value.ends_with('-') || value.contains('..') {
		return false
	}
	for index, ch in value.bytes() {
		if index == 0 && !((ch >= `a` && ch <= `z`) || (ch >= `0` && ch <= `9`)) {
			return false
		}
		if !((ch >= `a` && ch <= `z`) || (ch >= `0` && ch <= `9`) || ch == `_`
			|| ch == `-` || ch == `.`) {
			return false
		}
	}
	return true
}

fn valid_field_name(value string) bool {
	if value.len == 0 || value.len > 128 {
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

const max_filter_depth = 3
const max_filter_children = 50
const max_filter_list_items = 100

fn (store Store) validate_filter(filter map[string]json2.Any, depth int) ! {
	if depth > max_filter_depth {
		return error('OpenSearch filter nesting exceeds the supported depth')
	}
	for key, value in filter {
		if key.starts_with('$') {
			if key !in ['$and', '$or', '$not'] {
				return error('OpenSearch filter supports only $and, $or, and $not logical operators')
			}
			if key == '$not' {
				if value !is map[string]json2.Any {
					return error('OpenSearch filter $not requires a filter object')
				}
				store.validate_filter(value as map[string]json2.Any, depth + 1)!
				continue
			}
			children := filter_children(key, value)!
			for child in children {
				store.validate_filter(child, depth + 1)!
			}
			continue
		}
		if !valid_field_name(key) || key == store.vector_field || key == store.text_field
			|| key == store.metadata_field || key == store.namespace_field {
			return error('OpenSearch filters require valid non-reserved property names')
		}
		if value is map[string]json2.Any {
			operators := value as map[string]json2.Any
			if operators.len == 0 {
				return error('OpenSearch filter operator objects must not be empty')
			}
			for operator, operand in operators {
				validate_filter_operator(operator, operand)!
			}
		} else if value is []json2.Any {
			validate_filter_items(value as []json2.Any)!
		} else if !valid_filter_value(value) {
			return error('OpenSearch filters support scalar metadata values')
		}
		if value is string && (value as string).len > 4096 {
			return error('OpenSearch filter values are limited to 4 KiB')
		}
	}
}

fn filter_children(operator string, value json2.Any) ![]map[string]json2.Any {
	if value !is []json2.Any {
		return error('OpenSearch filter ${operator} requires an array of filter objects')
	}
	items := value as []json2.Any
	if items.len == 0 || items.len > max_filter_children {
		return error('OpenSearch filter ${operator} requires between 1 and 50 filter objects')
	}
	mut children := []map[string]json2.Any{cap: items.len}
	for item in items {
		if item !is map[string]json2.Any {
			return error('OpenSearch filter ${operator} requires an array of filter objects')
		}
		children << item as map[string]json2.Any
	}
	return children
}

fn validate_filter_items(value []json2.Any) ! {
	if value.len == 0 || value.len > max_filter_list_items {
		return error('OpenSearch filter $in requires between 1 and 100 items')
	}
	for item in value {
		if !valid_filter_value(item) {
			return error('OpenSearch filter $in requires scalar items')
		}
	}
}

fn validate_filter_operator(operator string, operand json2.Any) ! {
	match operator {
		'$eq', '$ne' {
			if !valid_filter_value(operand) {
				return error('OpenSearch filter ${operator} requires a scalar operand')
			}
		}
		'$gt', '$gte', '$lt', '$lte' {
			if !valid_filter_number(operand) {
				return error('OpenSearch filter ${operator} requires a numeric operand')
			}
		}
		'$in', '$nin' {
			if operand !is []json2.Any {
				return error('OpenSearch filter ${operator} requires an array operand')
			}
			validate_filter_items(operand as []json2.Any)!
		}
		'$exists' {
			if operand !is bool {
				return error('OpenSearch filter $exists requires a boolean operand')
			}
		}
		else {
			return error('OpenSearch filter operator ${operator} is not supported')
		}
	}
}

fn valid_filter_number(value json2.Any) bool {
	return match value {
		int, i64, i32, i16, i8, u64, u32, u16, u8 { true }
		f32 { math.is_finite(f64(value)) }
		f64 { math.is_finite(value) }
		else { false }
	}
}

fn (store Store) build_filter_clauses(filter map[string]json2.Any, depth int) !([]json2.Any, []json2.Any) {
	mut must := []json2.Any{}
	mut must_not := []json2.Any{}
	for key, value in filter {
		if key.starts_with('$') {
			match key {
				'$and' {
					for child in filter_children(key, value)! {
						child_must, child_must_not := store.build_filter_clauses(child, depth + 1)!
						for clause in child_must {
							must << clause
						}
						for clause in child_must_not {
							must_not << clause
						}
					}
				}
				'$or' {
					mut should := []json2.Any{}
					for child in filter_children(key, value)! {
						child_must, child_must_not := store.build_filter_clauses(child, depth + 1)!
						should << bool_clause(child_must, child_must_not)
					}
					must << json2.Any({
						'bool': json2.Any({
							'should':               json2.Any(should)
							'minimum_should_match': json2.Any(1)
						})
					})
				}
				'$not' {
					child_must, child_must_not := store.build_filter_clauses(value as map[string]json2.Any,
						depth + 1)!
					must_not << bool_clause(child_must, child_must_not)
				}
				else {}
			}
			continue
		}
		field := '${store.metadata_field}.${key}'
		if value is map[string]json2.Any {
			operators := value as map[string]json2.Any
			mut range := map[string]json2.Any{}
			for operator, operand in operators {
				match operator {
					'$eq' {
						must << term_clause(field, operand)
					}
					'$ne' {
						must_not << term_clause(field, operand)
					}
					'$in' {
						must << terms_clause(field, operand)
					}
					'$nin' {
						must_not << terms_clause(field, operand)
					}
					'$gt', '$gte', '$lt', '$lte' {
						range[operator[1..]] = operand
					}
					'$exists' {
						if operand as bool {
							must << exists_clause(field)
						} else {
							must_not << exists_clause(field)
						}
					}
					else {}
				}
			}
			if range.len > 0 {
				mut range_clause := map[string]json2.Any{}
				range_clause[field] = json2.Any(range)
				must << json2.Any({
					'range': json2.Any(range_clause)
				})
			}
		} else if value is []json2.Any {
			must << terms_clause(field, value)
		} else {
			must << term_clause(field, value)
		}
	}
	return must, must_not
}

fn bool_clause(must []json2.Any, must_not []json2.Any) json2.Any {
	mut bool_filter := map[string]json2.Any{}
	if must.len > 0 {
		bool_filter['filter'] = json2.Any(must)
	}
	if must_not.len > 0 {
		bool_filter['must_not'] = json2.Any(must_not)
	}
	return json2.Any({
		'bool': json2.Any(bool_filter)
	})
}

fn term_clause(field string, value json2.Any) json2.Any {
	mut clause := map[string]json2.Any{}
	clause[field] = value
	return json2.Any({
		'term': json2.Any(clause)
	})
}

fn terms_clause(field string, value json2.Any) json2.Any {
	mut clause := map[string]json2.Any{}
	clause[field] = value
	return json2.Any({
		'terms': json2.Any(clause)
	})
}

fn exists_clause(field string) json2.Any {
	return json2.Any({
		'exists': json2.Any({
			'field': json2.Any(field)
		})
	})
}

fn valid_filter_value(value json2.Any) bool {
	return match value {
		string, bool, int, i64, i32, i16, i8, u64, u32, u16, u8 { true }
		f32 { math.is_finite(f64(value)) }
		f64 { math.is_finite(value) }
		else { false }
	}
}

fn open_search_float(value json2.Any) !f32 {
	result := match value {
		f32 { value }
		f64 { f32(value) }
		int { f32(value) }
		i64 { f32(value) }
		else { return error('OpenSearch score must be numeric') }
	}
	if !math.is_finite(f64(result)) {
		return error('OpenSearch score must be finite')
	}
	return result
}

fn open_search_int(value json2.Any) !int {
	return match value {
		int { value }
		i64 {
			if value < 0 || value > 2147483647 {
				return error('OpenSearch status is outside the supported range')
			}
			int(value)
		}
		f64 {
			if !math.is_finite(value) || value < 0 || value > 2147483647 || value != f64(int(value)) {
				return error('OpenSearch status is not a non-negative integer')
			}
			int(value)
		}
		else { return error('OpenSearch status must be numeric') }
	}
}
