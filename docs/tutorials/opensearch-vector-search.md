---
layout: default
title: OpenSearch vector search
permalink: /tutorials/opensearch-vector-search/
---

# OpenSearch vector search

This guide provisions the index explicitly, then binds the LangChainV adapter
to it. Index creation requires cluster permissions and allocates OpenSearch
resources. Choose an embedding model first; its output dimension must match the
index mapping. OpenSearch documents the [`knn_vector` mapping](https://docs.opensearch.org/latest/mappings/supported-field-types/knn-vector/)
and [vector index creation](https://docs.opensearch.org/latest/vector-search/creating-vector-index/).

## Create the index

Construct the store with your embedder and endpoint configuration, then call
`initialize_index` once with the embedder's known dimension. This is an explicit
`PUT /<index>` operation. It fails if the index already exists; it never drops,
replaces, or migrates an index.

```text
mut store := opensearch.new_store(embedder, opensearch.Options{
    base_url: 'https://search.example.com'
    index: 'knowledge'
    api_key: os.getenv('OPENSEARCH_API_KEY')
})!
mut ctx := context.background()
store.initialize_index(mut ctx, 1536)!
```

The created mapping uses Lucene HNSW with cosine similarity, a `knn_vector`
field, text content, object metadata, and a keyword namespace. Custom field
names in `Options` are used in the mapping. Remote endpoints require HTTPS;
loopback HTTP is available for local development.

## Index and search

After provisioning, use `add_documents` and `similarity_search` as described in
[`vectorstores/opensearch`](https://github.com/ulises-jeremias/langchainv/tree/main/vectorstores/opensearch).
Writes use the Bulk API and are bounded to 64 documents per call. Search
supports namespace and exact scalar metadata filters. The vector source field
is omitted by default; set `SearchOptions.include_vectors` to return stored
vectors.

## Operational notes

- Use the same embedder and dimension for every write and query.
- `new_store` does not make network requests or manage cluster state.
- The helper creates an approximate cosine k-NN mapping; recall and resource
  usage depend on OpenSearch version and index configuration.
- Authentication supports an API key or HTTP basic credentials. Keep secrets
  outside source control.
- Tests use an injected fake HTTP client and do not require an OpenSearch
  service.
