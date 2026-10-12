# Qdrant vector store

`qdrant.new_store(collection, embedder, options)` implements the shared
`vectorstores.VectorStore` contract over Qdrant's REST query API. The collection must
already exist, and its vector dimensions and distance configuration must match
the injected embedder. `new_store_with_collection` creates a single-vector
collection with an explicit size and cosine distance; the size must match the
embedder output. `new_store_with_collection_and_client` supports custom HTTP
transports. `Store.delete_collection` deletes the bound collection and all its
points.
Collection lifecycle calls follow Qdrant's official [create collection](https://api.qdrant.tech/master/api-reference/collections/create-collection)
and [delete collection](https://api.qdrant.tech/api-reference/collections/delete-collection)
REST endpoints.

The adapter supports document upserts bounded to 64 points per call, similarity
search, metadata equality filters, namespaces, minimum score filtering, and UUID
deletion. Requests and responses are capped at 4 MiB; document content and
metadata are checked before embedding. Writes accept at most 64 documents,
queries at most 64 KiB, and searches/deletes at most 1,000 entries. Local HTTP endpoints are restricted
to loopback; remote endpoints require HTTPS. Tests use an injected
`httputil.HTTPClient` and do not require Qdrant or credentials.

```v wip
mut store := qdrant.new_store('documents', embedder, qdrant.StoreOptions{
	base_url: 'https://qdrant.example.test'
	api_key:  qdrant_api_key
})!
```

Qdrant's wider query DSL, named/multi-vector collections, additional collection
configuration, payload schema management, custom point IDs, and returned
vectors remain unsupported. The adapter stores page content and metadata in a
payload envelope and requires the Qdrant REST API to be reachable at the
configured base URL.
