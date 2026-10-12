# OpenSearch vector store

The `opensearch` package implements a bounded REST adapter for an existing
OpenSearch index with a `knn_vector` field. It uses an injected
`embeddings.Embedder` and `httputil.HTTPClient`; tests use an offline fake
transport.

Configured field names are simple names without dots. The index mapping must
define the configured vector field (default `vector`) as `knn_vector` with the
embedder's dimension and a k-NN engine that supports
the query's in-filter (for example Lucene or Faiss). The source must store a
string content field (`page_content`), object metadata field (`metadata`), and
string namespace field (`namespace`). The adapter does not create or alter
index mappings. Metadata filters use exact scalar equality against
`metadata.<key>`.

The adapter supports API key or HTTP basic authentication, namespaces, cosine
k-NN scores, and bulk indexing/deletion. Writes are limited to 64 documents,
deletes to 1,000 IDs, searches to 1,000 results, vectors to 16,000 finite
values, and request/response bodies to 4 MiB. Returned scores are OpenSearch
`_score` values; minimum-score filtering happens after the server returns the
requested top-k results, so fewer than `limit` documents may be returned. Set
`SearchOptions.include_vectors` to include the stored vector in
`schema.Document.embedding`; the vector source field is omitted by default.
Returned vectors are validated for shape, finite values, and size. Remote
endpoints must use HTTPS; HTTP is allowed for loopback development instances.

The adapter uses the Bulk API with `refresh=true`, then checks every operation
result. Search uses the k-NN query DSL. See OpenSearch's documentation for
[k-NN vector fields](https://docs.opensearch.org/latest/mappings/supported-field-types/knn-vector/),
[k-NN queries](https://docs.opensearch.org/latest/query-dsl/specialized/k-nn/index/),
[efficient k-NN filters](https://docs.opensearch.org/latest/vector-search/filter-search-knn/efficient-knn-filtering/),
and the [Bulk API](https://docs.opensearch.org/latest/api-reference/document-apis/bulk/).
