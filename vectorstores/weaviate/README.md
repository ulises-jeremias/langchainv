# Weaviate vector store

`weaviate.new_store(embedder, options)` implements the shared vector store
contract against an existing Weaviate class. The class must already contain
the configured text, namespace, and metadata properties. The adapter does not
create or alter schemas.

The adapter supports batch upserts and deletes of up to 64 objects, GraphQL
near-vector and metadata searches, namespace isolation, exact equality filters
for scalar metadata, and optional certainty thresholds. It uses an injected
embedder and HTTP client for offline tests. Remote endpoints require HTTPS;
plain HTTP is allowed only on loopback. Requests and responses are capped at
4 MiB, search limits at 1000, and embedding vectors at 65,536 values.

```v wip
mut store := weaviate.new_store(embedder, weaviate.Options{
	base_url: 'https://weaviate.example.com'
	class_name: 'Guide'
	api_key: weaviate_api_key
})!
```

Schema management, filters beyond scalar equality, and returning vector values
remain unsupported. Since namespace is stored in a class property, configure
that property as a filterable scalar in the existing schema.
