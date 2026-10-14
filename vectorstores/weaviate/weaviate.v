// Package weaviate implements a bounded REST adapter for Weaviate collections.
module weaviate

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

const default_namespace = 'default'
const default_text_key = 'text'
const default_namespace_key = 'nameSpace'
const max_documents_per_write = 64
const max_payload_bytes = 4 * 1024 * 1024
const max_search_limit = 1000
const max_embedding_values = 65536

// Store uses one provisioned Weaviate class and an injected embedder.
pub struct Store {
pub:
	base_url      string
	class_name    string
	api_key       string
	text_key      string
	namespace_key string
	namespace     string
	query_attrs   []string
pub mut:
	embedder    embeddings.Embedder
	http_client httputil.HTTPClient
}

// Options configures an existing Weaviate class and its connection.
pub struct Options {
pub:
	base_url      string
	class_name    string
	api_key       string
	text_key      string
	namespace_key string
	namespace     string
	query_attrs   []string
}

// new_store creates an adapter for a provisioned class.
pub fn new_store(embedder embeddings.Embedder, options Options) !Store {
	client := httputil.HTTPClient(httputil.DefaultClient{
		max_request_bytes:  max_payload_bytes
		max_response_bytes: max_payload_bytes
	})
	return new_store_with_client(embedder, options, client)
}

// new_store_with_client creates an adapter that uses the supplied HTTP client.
// The class must already define the configured text, namespace, and metadata properties.
pub fn new_store_with_client(embedder embeddings.Embedder, options Options, http_client httputil.HTTPClient) !Store {
	base_url := if options.base_url.trim_space() == '' {
		'http://127.0.0.1:8080'
	} else {
		options.base_url.trim_space().trim_right('/')
	}
	if base_url.len > 2048 || base_url.contains('?') || base_url.contains('#') {
		return error('Weaviate base URL must be at most 2048 bytes and contain no query or fragment')
	}
	httputil.validate_url(base_url, '')!
	parsed_url := urllib.parse(base_url) or { return error('Weaviate base URL is invalid') }
	if parsed_url.scheme.to_lower() == 'http' && parsed_url.host.to_lower() !in [
		'localhost',
		'127.0.0.1',
		'::1',
	] {
		return error('remote Weaviate endpoints must use HTTPS')
	}
	class_name := options.class_name.trim_space()
	if !valid_class_name(class_name) {
		return error('Weaviate class name must start with an uppercase letter and use only letters or digits')
	}
	api_key := options.api_key.trim_space()
	if api_key.len > 4096 || api_key.contains('\n') || api_key.contains('\r') {
		return error('Weaviate API key is invalid or exceeds 4096 bytes')
	}
	text_key := if options.text_key.trim_space() == '' {
		default_text_key
	} else {
		options.text_key.trim_space()
	}
	namespace_key := if options.namespace_key.trim_space() == '' {
		default_namespace_key
	} else {
		options.namespace_key.trim_space()
	}
	if !valid_property_name(text_key) || !valid_property_name(namespace_key) || text_key == namespace_key {
		return error('Weaviate text and namespace property names must be valid and distinct')
	}
	mut query_attrs := options.query_attrs.clone()
	if query_attrs.len == 0 {
		query_attrs = [text_key, namespace_key]
	}
	for attr in query_attrs {
		if !valid_property_name(attr) || attr == '_additional' {
			return error('Weaviate query attributes must be valid property names')
		}
	}
	if !query_attrs.contains(text_key) {
		query_attrs << text_key
	}
	if !query_attrs.contains(namespace_key) {
		query_attrs << namespace_key
	}
	return Store{
		base_url:      base_url
		class_name:    class_name
		api_key:       api_key
		text_key:      text_key
		namespace_key: namespace_key
		namespace:     if options.namespace == '' { default_namespace } else { options.namespace }
		query_attrs:   query_attrs
		embedder:      embedder
		http_client:   http_client
	}
}

// add_documents embeds and batch-imports up to 64 documents.
pub fn (store Store) add_documents(mut ctx context.Context, documents []schema.Document, options vectorstores.StoreOptions) ![]string {
	if documents.len == 0 {
		return []string{}
	}
	if documents.len > max_documents_per_write {
		return error('Weaviate writes are limited to 64 objects per call')
	}
	mut input_bytes := 0
	for document in documents {
		if store.text_key in document.metadata || store.namespace_key in document.metadata {
			return error('document metadata uses a reserved Weaviate text or namespace property')
		}
		for key, _ in document.metadata {
			if !valid_property_name(key) || key == '_additional' {
				return error('Weaviate metadata keys must be valid property names')
			}
		}
		metadata_bytes := json2.encode(document.metadata, json2.EncoderOptions{}).len
		if document.page_content.len > max_payload_bytes - input_bytes
			|| metadata_bytes > max_payload_bytes - input_bytes - document.page_content.len {
			return error('Weaviate document content and metadata exceed 4 MiB')
		}
		input_bytes += document.page_content.len + metadata_bytes
	}
	texts := documents.map(it.page_content)
	vectors := store.embedder.embed_documents(mut ctx, texts)!
	if vectors.len != documents.len {
		return error('embedder returned ${vectors.len} vectors for ${documents.len} documents')
	}
	mut objects := []json2.Any{cap: documents.len}
	mut ids := []string{cap: documents.len}
	mut dimension := -1
	for index, document in documents {
		vector := vectors[index]
		if vector.len == 0 || vector.len > max_embedding_values || (dimension > 0 && vector.len != dimension) {
			return error('Weaviate embeddings must be non-empty, bounded, and dimensionally consistent')
		}
		dimension = vector.len
		mut wire_vector := []json2.Any{cap: vector.len}
		for value in vector {
			if !math.is_finite(f64(value)) {
				return error('Weaviate embeddings must contain finite values')
			}
			wire_vector << json2.Any(value)
		}
		id := rand.uuid_v4()
		ids << id
		mut properties := document.metadata.clone()
		properties[store.text_key] = json2.Any(document.page_content)
		properties[store.namespace_key] = json2.Any(if options.namespace == '' {
			store.namespace
		} else {
			options.namespace
		})
		objects << json2.Any(map[string]json2.Any{
			'class':      json2.Any(store.class_name)
			'id':         json2.Any(id)
			'properties': json2.Any(properties)
			'vector':     json2.Any(wire_vector)
		})
	}
	body := json2.encode(objects, json2.EncoderOptions{})
	if body.len > max_payload_bytes {
		return error('Weaviate batch payload exceeds 4 MiB')
	}
	response := store.request(mut ctx, .post, '/v1/batch/objects', body)!
	store.validate_batch_response(response.body, documents.len)!
	return ids
}

// similarity_search retrieves the nearest documents using a Weaviate nearVector query.
pub fn (store Store) similarity_search(mut ctx context.Context, query string, limit int, options vectorstores.SearchOptions) ![]schema.Document {
	if limit < 0 || limit > max_search_limit {
		return error('Weaviate search limit must be between zero and 1000')
	}
	if limit == 0 {
		return []schema.Document{}
	}
	if query.len > 65536 {
		return error('Weaviate query exceeds 64 KiB')
	}
	if options.distance_strategy != '' && options.distance_strategy != 'cosine' {
		return error('Weaviate certainty thresholds require cosine distance')
	}
	if options.min_score != none {
		minimum := options.min_score or { f32(0) }
		if !math.is_finite(f64(minimum)) || minimum < 0 || minimum > 1 {
			return error('Weaviate certainty threshold must be between zero and one')
		}
	}
	where := store.where_clause(options.filter, options.namespace)!
	vector := store.embedder.embed_query(mut ctx, query)!
	if vector.len == 0 || vector.len > max_embedding_values {
		return error('Weaviate query embedding must contain between 1 and 65536 values')
	}
	mut vector_values := []json2.Any{cap: vector.len}
	for value in vector {
		if !math.is_finite(f64(value)) {
			return error('Weaviate query embedding must contain finite values')
		}
		vector_values << json2.Any(value)
	}
	near_vector := if options.min_score != none {
		'{ vector: ${json2.encode(vector_values, json2.EncoderOptions{})}, certainty: ${f32_string(options.min_score or { f32(0) })} }'
	} else {
		'{ vector: ${json2.encode(vector_values, json2.EncoderOptions{})} }'
	}
	query_body := '{ Get { ${store.class_name}(nearVector: ${near_vector}, where: ${where}, limit: ${limit}) { ${store.graphql_fields(options.include_vectors)} } } }'
	body := json2.encode(map[string]json2.Any{
		'query': json2.Any(query_body)
	}, json2.EncoderOptions{})
	response := store.request(mut ctx, .post, '/v1/graphql', body)!
	return store.parse_graphql_response(response.body, limit, options.include_metadata, true,
		options.include_vectors)
}

// metadata_search fetches objects by exact scalar metadata filters without vector ranking.
pub fn (store Store) metadata_search(mut ctx context.Context, limit int, options vectorstores.SearchOptions) ![]schema.Document {
	if limit < 0 || limit > max_search_limit {
		return error('Weaviate search limit must be between zero and 1000')
	}
	if limit == 0 {
		return []schema.Document{}
	}
	where := store.where_clause(options.filter, options.namespace)!
	query_body := '{ Get { ${store.class_name}(where: ${where}, limit: ${limit}) { ${store.graphql_fields(options.include_vectors)} } } }'
	body := json2.encode(map[string]json2.Any{
		'query': json2.Any(query_body)
	}, json2.EncoderOptions{})
	response := store.request(mut ctx, .post, '/v1/graphql', body)!
	return store.parse_graphql_response(response.body, limit, options.include_metadata, false,
		options.include_vectors)
}

// delete removes up to 64 UUID objects by ID.
pub fn (store Store) delete(mut ctx context.Context, ids []string, _options vectorstores.StoreOptions) ! {
	if ids.len > max_documents_per_write {
		return error('Weaviate deletes are limited to 64 IDs per call')
	}
	for id in ids {
		if !valid_uuid(id) {
			return error('Weaviate object IDs must be UUIDs')
		}
		store.request(mut ctx, .delete, '/v1/objects/${store.class_name}/${id}', '')!
	}
}

fn (store Store) where_clause(filters map[string]json2.Any, namespace string) !string {
	mut operands := []string{}
	for key, value in filters {
		operands << store.filter_operand(key, value, 0)!
	}
	actual_namespace := if namespace == '' { store.namespace } else { namespace }
	operands << store.equal_filter(store.namespace_key, json2.Any(actual_namespace))!
	if operands.len == 1 {
		return operands[0]
	}
	return '{ operator: And, operands: [${operands.join(', ')}] }'
}

const max_filter_depth = 3
const max_filter_children = 50
const max_filter_list_items = 100

fn (store Store) filter_operand(key string, value json2.Any, depth int) !string {
	if depth > max_filter_depth {
		return error('Weaviate filter nesting exceeds the supported depth')
	}
	if key.starts_with('$') {
		if key !in ['$and', '$or'] {
			return error('Weaviate filter supports only $and and $or logical operators')
		}
		if value !is []json2.Any {
			return error('Weaviate filter ${key} requires an array of filter objects')
		}
		children := value as []json2.Any
		if children.len == 0 || children.len > max_filter_children {
			return error('Weaviate filter ${key} requires between 1 and 50 filter objects')
		}
		mut operands := []string{cap: children.len}
		for child in children {
			if child !is map[string]json2.Any {
				return error('Weaviate filter ${key} requires an array of filter objects')
			}
			child_filters := child as map[string]json2.Any
			mut child_operands := []string{cap: child_filters.len}
			for child_key, child_value in child_filters {
				child_operands << store.filter_operand(child_key, child_value, depth + 1)!
			}
			operands << if child_operands.len == 1 {
				child_operands[0]
			} else {
				'{ operator: And, operands: [${child_operands.join(', ')}] }'
			}
		}
		operator_name := if key == '$and' { 'And' } else { 'Or' }
		return '{ operator: ${operator_name}, operands: [${operands.join(', ')}] }'
	}
	if !valid_property_name(key) || key == '_additional' || key == store.text_key
		|| key == store.namespace_key {
		return error('Weaviate filters require valid non-reserved property names')
	}
	if value is map[string]json2.Any {
		operators := value as map[string]json2.Any
		if operators.len == 0 {
			return error('Weaviate filter operator objects must not be empty')
		}
		mut operands := []string{cap: operators.len}
		for operator, operand in operators {
			operands << store.operator_filter(key, operator, operand)!
		}
		if operands.len == 1 {
			return operands[0]
		}
		return '{ operator: And, operands: [${operands.join(', ')}] }'
	}
	return store.equal_filter(key, value)
}

fn (_store Store) operator_filter(key string, operator string, operand json2.Any) !string {
	operator_names := {
		'$eq':  'Equal'
		'$ne':  'NotEqual'
		'$lt':  'LessThan'
		'$lte': 'LessThanEqual'
		'$gt':  'GreaterThan'
		'$gte': 'GreaterThanEqual'
	}
	if operator == '$exists' {
		if operand !is bool {
			return error('Weaviate filter $exists requires a boolean operand')
		}
		return '{ path: [${graphql_string(key)}], operator: IsNull, valueBoolean: ${!(operand as bool)} }'
	}
	if operator == '$in' {
		if operand !is []json2.Any {
			return error('Weaviate filter $in requires an array operand')
		}
		items := operand as []json2.Any
		if items.len == 0 || items.len > max_filter_list_items {
			return error('Weaviate filter $in requires between 1 and 100 items')
		}
		field := filter_array_field(items)!
		return '{ path: [${graphql_string(key)}], operator: ContainsAny, ${field}: ${json2.encode(operand, json2.EncoderOptions{})} }'
	}
	operator_name := operator_names[operator] or {
		return error('Weaviate filter operator ${operator} is not supported')
	}
	field := filter_scalar_field(operand)!
	return '{ path: [${graphql_string(key)}], operator: ${operator_name}, ${field}: ${json2.encode(operand, json2.EncoderOptions{})} }'
}

fn filter_scalar_field(value json2.Any) !string {
	return match value {
		string { 'valueText' }
		bool { 'valueBoolean' }
		int, i64, i32, i16, i8, u64, u32, u16, u8 { 'valueInt' }
		f64 {
			if !math.is_finite(value as f64) {
				return error('Weaviate filters must contain finite values')
			}
			'valueNumber'
		}
		f32 {
			if !math.is_finite(f64(value as f32)) {
				return error('Weaviate filters must contain finite values')
			}
			'valueNumber'
		}
		else {
			return error('Weaviate filter operators support string, boolean, and numeric operands')
		}
	}
}

fn filter_array_field(items []json2.Any) !string {
	mut has_string := false
	mut has_int := false
	mut has_float := false
	for item in items {
		match item {
			string { has_string = true }
			int, i64, i32, i16, i8, u64, u32, u16, u8 { has_int = true }
			f64 {
				if !math.is_finite(item as f64) {
					return error('Weaviate filters must contain finite values')
				}
				has_float = true
			}
			f32 {
				if !math.is_finite(f64(item as f32)) {
					return error('Weaviate filters must contain finite values')
				}
				has_float = true
			}
			else { return error('Weaviate filter $in supports string and numeric items') }
		}
	}
	if has_string && (has_int || has_float) {
		return error('Weaviate filter $in items must share one type')
	}
	if has_string {
		return 'valueTextArray'
	}
	return if has_float { 'valueNumberArray' } else { 'valueIntArray' }
}

fn (_store Store) equal_filter(key string, value json2.Any) !string {
	field := match value {
		string { 'valueText' }
		bool { 'valueBoolean' }
		int, i64, i32, i16, i8, u64, u32, u16, u8 { 'valueInt' }
		f64, f32 { 'valueNumber' }
		else {
			return error('Weaviate equality filters support string, boolean, and numeric values')
		}
	}
	if value is f64 && !math.is_finite(value as f64) {
		return error('Weaviate filters must contain finite values')
	}
	if value is f32 && !math.is_finite(f64(value as f32)) {
		return error('Weaviate filters must contain finite values')
	}
	return '{ path: [${graphql_string(key)}], operator: Equal, ${field}: ${json2.encode(value, json2.EncoderOptions{})} }'
}

fn (store Store) graphql_fields(include_vectors bool) string {
	additional := if include_vectors { 'certainty vector' } else { 'certainty' }
	return '${store.query_attrs.join(', ')}, _additional { ${additional} }'
}

fn (store Store) parse_graphql_response(body string, limit int, include_metadata bool, with_scores bool, include_vectors bool) ![]schema.Document {
	decoded := json2.decode[map[string]json2.Any](body, json2.DecoderOptions{}) or {
		return error('Weaviate returned invalid GraphQL JSON')
	}
	if errors_any := decoded['errors'] {
		if graphql_errors_present(errors_any) {
			return error('Weaviate GraphQL query returned errors')
		}
	}
	data_any := decoded['data'] or { return error('Weaviate GraphQL response has no data') }
	if data_any !is map[string]json2.Any {
		return error('Weaviate GraphQL data must be an object')
	}
	get_any := (data_any as map[string]json2.Any)['Get'] or {
		return error('Weaviate GraphQL response has no Get result')
	}
	if get_any !is map[string]json2.Any {
		return error('Weaviate GraphQL Get result must be an object')
	}
	class_any := (get_any as map[string]json2.Any)[store.class_name] or {
		return error('Weaviate GraphQL response has no class result')
	}
	if class_any !is []json2.Any {
		return error('Weaviate class results must be an array')
	}
	items := class_any as []json2.Any
	if items.len > limit {
		return error('Weaviate returned more results than requested')
	}
	mut documents := []schema.Document{cap: items.len}
	for item in items {
		if item !is map[string]json2.Any {
			return error('Weaviate returned a malformed object')
		}
		mut properties := (item as map[string]json2.Any).clone()
		content_any := properties[store.text_key] or {
			return error('Weaviate object is missing its text property')
		}
		if content_any !is string {
			return error('Weaviate text property must be a string')
		}
		properties.delete(store.text_key)
		additional_any := properties['_additional'] or { json2.Any(map[string]json2.Any{}) }
		properties.delete('_additional')
		if additional_any !is map[string]json2.Any {
			return error('Weaviate additional fields must be an object')
		}
		additional := additional_any as map[string]json2.Any
		mut score := f32(0)
		if with_scores {
			score = weaviate_float(additional['certainty'] or {
				return error('Weaviate response is missing certainty')
			})!
		}
		mut embedding := []f32{}
		if include_vectors {
			vector_any := additional['vector'] or { return error('Weaviate response is missing its vector') }
			if vector_any !is []json2.Any {
				return error('Weaviate returned an unsupported vector shape')
			}
			vector_values := vector_any as []json2.Any
			if vector_values.len == 0 || vector_values.len > max_embedding_values {
				return error('Weaviate returned an empty or oversized vector')
			}
			embedding = []f32{cap: vector_values.len}
			for value in vector_values {
				embedding << weaviate_vector_float(value)!
			}
		}
		if !include_metadata {
			properties = map[string]json2.Any{}
		}
		documents << schema.Document{
			page_content: content_any as string
			metadata:     properties
			score:        score
			embedding:    embedding
		}
	}
	return documents
}

fn (store Store) validate_batch_response(body string, expected_count int) ! {
	decoded := json2.decode[[]json2.Any](body, json2.DecoderOptions{}) or {
		return error('Weaviate returned invalid batch JSON')
	}
	if decoded.len != expected_count {
		return error('Weaviate returned an unexpected batch result count')
	}
	for item in decoded {
		if item !is map[string]json2.Any {
			return error('Weaviate returned a malformed batch result')
		}
		result_any := (item as map[string]json2.Any)['result'] or {
			return error('Weaviate batch result is missing object status')
		}
		if result_any !is map[string]json2.Any {
			return error('Weaviate batch result status must be an object')
		}
		if errors_any := (result_any as map[string]json2.Any)['errors'] {
			if graphql_errors_present(errors_any) {
				return error('Weaviate batch import reported an object error')
			}
		}
	}
}

fn graphql_errors_present(value json2.Any) bool {
	match value {
		json2.Null { return false }
		[]json2.Any { return value.len > 0 }
		map[string]json2.Any { return value.len > 0 }
		string { return value != '' }
		else { return true }
	}
}

fn (store Store) request(mut ctx context.Context, method http.Method, path string, body string) !httputil.Response {
	if body.len > max_payload_bytes {
		return error('Weaviate request exceeds 4 MiB')
	}
	mut headers := map[string]string{
		'Accept':       'application/json'
		'Content-Type': 'application/json'
	}
	if store.api_key != '' {
		headers['Authorization'] = 'Bearer ${store.api_key}'
	}
	response := store.http_client.do(mut ctx, httputil.Request{
		method:  method
		url:     '${store.base_url}${path}'
		headers: headers
		body:    body
	}) or {
		return error('Weaviate request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Weaviate request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_payload_bytes {
		return error('Weaviate response exceeds 4 MiB')
	}
	return response
}

fn valid_class_name(value string) bool {
	if value.len == 0 || value.len > 128 || value[0] < `A` || value[0] > `Z` {
		return false
	}
	for byte_value in value.bytes() {
		if !(byte_value >= `a` && byte_value <= `z`) && !(byte_value >= `A` && byte_value <= `Z`)
			&& !(byte_value >= `0` && byte_value <= `9`) {
			return false
		}
	}
	return true
}

fn valid_property_name(value string) bool {
	if value.len == 0 || value.len > 128 || !((value[0] >= `a` && value[0] <= `z`)
		|| (value[0] >= `A` && value[0] <= `Z`) || value[0] == `_`) {
		return false
	}
	for byte_value in value.bytes() {
		if !(byte_value >= `a` && byte_value <= `z`) && !(byte_value >= `A` && byte_value <= `Z`)
			&& !(byte_value >= `0` && byte_value <= `9`) && byte_value != `_` {
			return false
		}
	}
	return true
}

fn graphql_string(value string) string {
	return json2.encode(json2.Any(value), json2.EncoderOptions{})
}

fn f32_string(value f32) string {
	return json2.encode(json2.Any(value), json2.EncoderOptions{})
}

fn weaviate_float(value json2.Any) !f32 {
	match value {
		f64 {
			if !math.is_finite(value) {
				return error('Weaviate certainty must be finite')
			}
			return f32(value)
		}
		f32 { return value }
		int { return f32(value) }
		else { return error('Weaviate certainty must be numeric') }
	}
}

fn weaviate_vector_float(value json2.Any) !f32 {
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
	return error('Weaviate vector values must be finite numbers')
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
