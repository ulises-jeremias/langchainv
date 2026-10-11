# Qdrant vector store

`qdrant.new_store(collection, embedder, options)` implements the shared
`vectorstores.VectorStore` contract over Qdrant's REST query API. The collection must
already exist, and its vector dimensions and distance configuration must match
the injected embedder. The adapter does not create collections or install a
Qdrant server.

The adapter supports document upserts bounded to 64 points per call, similarity
search, metadata equality filters, namespaces, minimum score filtering, and UUID
deletion. Requests and responses are capped at 4 MiB; document content and
metadata are checked before embedding. Writes accept at most 64 documents,
queries at most 64 KiB, and searches/deletes at most 1,000 entries. Local HTTP endpoints are restricted
to loopback; remote endpoints require HTTPS. Tests use an injected
`httputil.HTTPClient` and do not require Qdrant or credentials.

```v
mut store := qdrant.new_store('documents', embedder, qdrant.StoreOptions{
	base_url: 'https://qdrant.example.test'
	api_key:  qdrant_api_key
})!
```

Qdrant's wider query DSL, named/multi-vector collections, payload schema
management, custom IDs, and returned vectors remain unsupported. The adapter
stores page content and metadata in a payload envelope and requires the Qdrant
REST API to be reachable at the configured base URL.
