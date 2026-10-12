// Package azureaisearch implements a bounded Azure AI Search REST adapter.
module azureaisearch

import context
import json2
import math
import net.http
import rand
import ulises_jeremias.langchainv.embeddings
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.vectorstores

const api_version = '2026-04-01'
const max_documents_per_write = 64
const max_payload_bytes = 4 * 1024 * 1024
const max_search_limit = 1000
const max_embedding_values = 65536

// Store uses an existing Azure AI Search index with a key, content, vector,
// metadata string, and optional filterable namespace field.
pub struct Store {
pub:
	endpoint        string
	index_name      string
	api_key         string
	key_field       string
	content_field   string
	vector_field    string
	metadata_field  string
	namespace_field string
pub mut:
	embedder    embeddings.Embedder
	http_client httputil.HTTPClient
}

// Options configures the endpoint, index, authentication, and index field names.
pub struct Options {
pub:
	endpoint        string
	index_name      string
	api_key         string
	key_field       string = 'id'
	content_field   string = 'content'
	vector_field    string = 'contentVector'
	metadata_field  string = 'metadata'
	namespace_field string = 'namespace'
}

// new_store creates an adapter for an existing index and an injected embedder.
pub fn new_store(embedder embeddings.Embedder, options Options) !Store {
	return new_store_with_client(embedder, options, httputil.DefaultClient{
		max_request_bytes:  max_payload_bytes
		max_response_bytes: max_payload_bytes
	})
}

// new_store_with_client creates an adapter using a caller-supplied HTTP client.
// The index schema must match the configured field names and vector dimensions.
pub fn new_store_with_client(embedder embeddings.Embedder, options Options, http_client httputil.HTTPClient) !Store {
	endpoint := options.endpoint.trim_space().trim_right('/')
	if endpoint.len == 0 || endpoint.len > 2048 || endpoint.contains('?') || endpoint.contains('#') {
		return error('Azure AI Search endpoint must be a URL of at most 2048 bytes without query or fragment')
	}
	httputil.validate_url(endpoint, 'https')!
	if !valid_index_name(options.index_name) {
		return error('Azure AI Search index name is invalid')
	}
	if options.api_key.len == 0 || options.api_key.len > 4096 || options.api_key.contains('\n') || options.api_key.contains('\r') {
		return error('Azure AI Search API key is required and must be at most 4096 bytes')
	}
	fields := [options.key_field, options.content_field, options.vector_field, options.metadata_field,
		options.namespace_field]
	for field in fields {
		if !valid_field_name(field) {
			return error('Azure AI Search field names must be valid identifiers')
		}
	}
	for i, field in fields {
		if field in fields[i + 1..] {
			return error('Azure AI Search field names must be distinct')
		}
	}
	return Store{
		endpoint:        endpoint
		index_name:      options.index_name
		api_key:         options.api_key
		key_field:       options.key_field
		content_field:   options.content_field
		vector_field:    options.vector_field
		metadata_field:  options.metadata_field
		namespace_field: options.namespace_field
		embedder:        embedder
		http_client:     http_client
	}
}

// add_documents embeds and uploads up to 64 documents in one indexing request.
pub fn (store Store) add_documents(mut ctx context.Context, documents []schema.Document, options vectorstores.StoreOptions) ![]string {
	if documents.len == 0 {
		return []string{}
	}
	if documents.len > max_documents_per_write {
		return error('Azure AI Search writes are limited to 64 documents per call')
	}
	if options.namespace.len > 65536 {
		return error('Azure AI Search namespace exceeds 64 KiB')
	}
	mut input_bytes := 0
	for document in documents {
		metadata := json2.encode(document.metadata, json2.EncoderOptions{})
		if document.page_content.len > max_payload_bytes - input_bytes || metadata.len > max_payload_bytes - input_bytes - document.page_content.len {
			return error('Azure AI Search document content and metadata exceed 4 MiB')
		}
		input_bytes += document.page_content.len + metadata.len
	}
	vectors := store.embedder.embed_documents(mut ctx, documents.map(it.page_content))!
	if vectors.len != documents.len {
		return error('embedder returned ${vectors.len} vectors for ${documents.len} documents')
	}
	mut actions := []json2.Any{cap: documents.len}
	mut ids := []string{cap: documents.len}
	mut dimension := -1
	for index, document in documents {
		vector := vectors[index]
		if vector.len == 0 || vector.len > max_embedding_values || (dimension > 0 && vector.len != dimension) {
			return error('Azure AI Search embeddings must be non-empty, bounded, and dimensionally consistent')
		}
		dimension = vector.len
		mut wire_vector := []json2.Any{cap: vector.len}
		for value in vector {
			if !math.is_finite(f64(value)) {
				return error('Azure AI Search embeddings must contain finite values')
			}
			wire_vector << json2.Any(value)
		}
		id := rand.uuid_v4()
		ids << id
		actions << json2.Any(map[string]json2.Any{
			'@search.action':      json2.Any('upload')
			store.key_field:       json2.Any(id)
			store.content_field:   json2.Any(document.page_content)
			store.vector_field:    json2.Any(wire_vector)
			store.metadata_field:  json2.Any(json2.encode(document.metadata, json2.EncoderOptions{}))
			store.namespace_field: json2.Any(options.namespace)
		})
	}
	body := json2.encode(map[string]json2.Any{
		'value': json2.Any(actions)
	}, json2.EncoderOptions{})
	if body.len > max_payload_bytes {
		return error('Azure AI Search indexing payload exceeds 4 MiB')
	}
	response := store.request(mut ctx, .post, '/docs/search.index', body)!
	store.check_index_results(response.body, documents.len)!
	return ids
}

// similarity_search embeds a query and searches the configured vector field.
pub fn (store Store) similarity_search(mut ctx context.Context, query string, limit int, options vectorstores.SearchOptions) ![]schema.Document {
	if limit < 0 || limit > max_search_limit {
		return error('Azure AI Search limit must be between zero and 1000')
	}
	if limit == 0 {
		return []schema.Document{}
	}
	if query.len > 65536 {
		return error('Azure AI Search query exceeds 64 KiB')
	}
	if options.namespace.len > 65536 {
		return error('Azure AI Search namespace exceeds 64 KiB')
	}
	if options.include_vectors {
		return error('Azure AI Search adapter does not expose stored vectors through schema.Document')
	}
	if options.filter.len > 0 {
		return error('Azure AI Search metadata filters are not supported by this adapter')
	}
	if options.distance_strategy != '' && options.distance_strategy != 'cosine' {
		return error('Azure AI Search adapter supports only the configured cosine vector ranking')
	}
	if options.min_score != none && !math.is_finite(f64(options.min_score or { f32(0) })) {
		return error('Azure AI Search minimum score must be finite')
	}
	vector := store.embedder.embed_query(mut ctx, query)!
	if vector.len == 0 || vector.len > max_embedding_values {
		return error('Azure AI Search query embedding must be non-empty and bounded')
	}
	mut wire_vector := []json2.Any{cap: vector.len}
	for value in vector {
		if !math.is_finite(f64(value)) {
			return error('Azure AI Search query embedding must contain finite values')
		}
		wire_vector << json2.Any(value)
	}
	mut request := map[string]json2.Any{
		'vectorQueries': json2.Any([json2.Any(map[string]json2.Any{
			'kind':   json2.Any('vector')
			'vector': json2.Any(wire_vector)
			'fields': json2.Any(store.vector_field)
			'k':      json2.Any(limit)
		})])
		'select':        json2.Any('${store.key_field},${store.content_field},${store.metadata_field},${store.namespace_field}')
		'top':           json2.Any(limit)
	}
	filter := make_namespace_filter(store.namespace_field, options.namespace)
	if filter != '' {
		request['filter'] = json2.Any(filter)
	}
	response := store.request(mut ctx, .post, '/docs/search.post.search', json2.encode(request,
		json2.EncoderOptions{}))!
	decoded := json2.decode[map[string]json2.Any](response.body, json2.DecoderOptions{}) or {
		return error('Azure AI Search returned invalid search JSON')
	}
	items := decoded['value'] or { return error('Azure AI Search response has no value array') }
	if items !is []json2.Any {
		return error('Azure AI Search response value must be an array')
	}
	results := items as []json2.Any
	if results.len > limit {
		return error('Azure AI Search returned more results than requested')
	}
	mut documents := []schema.Document{cap: results.len}
	for item in results {
		if item !is map[string]json2.Any {
			return error('Azure AI Search returned a malformed result')
		}
		fields := item as map[string]json2.Any
		content_any := fields[store.content_field] or { return error('Azure AI Search result is missing content') }
		if content_any !is string {
			return error('Azure AI Search content field must be a string')
		}
		score := finite_number(fields['@search.score'] or { return error('Azure AI Search result is missing score') })!
		minimum := options.min_score or { f32(0) }
		if score < minimum {
			continue
		}
		mut metadata := map[string]json2.Any{}
		if options.include_metadata {
			metadata_any := fields[store.metadata_field] or { json2.Any('{}') }
			if metadata_any is string {
				metadata = json2.decode[map[string]json2.Any](metadata_any as string, json2.DecoderOptions{}) or {
					return error('Azure AI Search metadata field contains invalid JSON')
				}
			} else if metadata_any is map[string]json2.Any {
				metadata = (metadata_any as map[string]json2.Any).clone()
			} else {
				return error('Azure AI Search metadata field must be a JSON object string')
			}
		}
		documents << schema.Document{
			page_content: content_any as string
			metadata:     metadata
			score:        score
		}
	}
	return documents
}

// delete removes documents by their Azure index key.
pub fn (store Store) delete(mut ctx context.Context, ids []string, _options vectorstores.StoreOptions) ! {
	if ids.len == 0 {
		return
	}
	if ids.len > max_documents_per_write {
		return error('Azure AI Search deletes are limited to 64 IDs per call')
	}
	mut actions := []json2.Any{cap: ids.len}
	for id in ids {
		if id.len == 0 || id.len > 1024 {
			return error('Azure AI Search document IDs must be between 1 and 1024 bytes')
		}
		actions << json2.Any(map[string]json2.Any{
			'@search.action': json2.Any('delete')
			store.key_field:  json2.Any(id)
		})
	}
	response := store.request(mut ctx, .post, '/docs/search.index', json2.encode(map[string]json2.Any{
		'value': json2.Any(actions)
	}, json2.EncoderOptions{}))!
	store.check_index_results(response.body, ids.len)!
}

fn (store Store) request(mut ctx context.Context, method http.Method, path string, body string) !httputil.Response {
	if body.len > max_payload_bytes {
		return error('Azure AI Search request exceeds 4 MiB')
	}
	url := "${store.endpoint}/indexes('${store.index_name}')${path}?api-version=${api_version}"
	response := store.http_client.do(mut ctx, httputil.Request{
		method:  method
		url:     url
		headers: {
			'Content-Type': 'application/json'
			'Accept':       'application/json'
			'api-key':      store.api_key
		}
		body:    body
	}) or {
		return error('Azure AI Search request failed: ${err.msg()}')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Azure AI Search request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_payload_bytes {
		return error('Azure AI Search response exceeds 4 MiB')
	}
	return response
}

fn (store Store) check_index_results(body string, expected int) ! {
	decoded := json2.decode[map[string]json2.Any](body, json2.DecoderOptions{}) or {
		return error('Azure AI Search returned invalid indexing JSON')
	}
	items := decoded['value'] or { return error('Azure AI Search indexing response has no value array') }
	if items !is []json2.Any || (items as []json2.Any).len != expected {
		return error('Azure AI Search indexing response does not match the submitted batch')
	}
	for item in items as []json2.Any {
		if item !is map[string]json2.Any {
			return error('Azure AI Search returned a malformed indexing result')
		}
		result := item as map[string]json2.Any
		status := result['status'] or { return error('Azure AI Search indexing result has no status') }
		if status !is bool || !(status as bool) {
			return error('Azure AI Search rejected one or more document actions')
		}
	}
}

fn make_namespace_filter(field string, namespace string) string {
	if namespace == '' {
		return ''
	}
	return "${field} eq '${namespace.replace("'", "''")}'"
}

fn finite_number(value json2.Any) !f32 {
	if value is f64 {
		number := value as f64
		if math.is_finite(number) {
			return f32(number)
		}
	}
	if value is int {
		return f32(value as int)
	}
	return error('Azure AI Search score must be a finite number')
}

fn valid_index_name(name string) bool {
	if name.len == 0 || name.len > 128 || name[0] < `a` || name[0] > `z` || name.ends_with('-') {
		return false
	}
	for value in name.bytes() {
		if !(value >= `a` && value <= `z`) && !(value >= `0` && value <= `9`) && value != `-` {
			return false
		}
	}
	return true
}

fn valid_field_name(name string) bool {
	if name.len == 0 || name.len > 128 || !((name[0] >= `a` && name[0] <= `z`) || (name[0] >= `A` && name[0] <= `Z`) || name[0] == `_`) {
		return false
	}
	for value in name.bytes() {
		if !(value >= `a` && value <= `z`) && !(value >= `A` && value <= `Z`) && !(value >= `0` && value <= `9`) && value != `_` {
			return false
		}
	}
	return true
}
