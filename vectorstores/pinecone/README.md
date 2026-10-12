# Pinecone vector store

`pinecone.new_store(embedder, options)` implements the shared vector store
contract against a provisioned Pinecone index host. Configure the index's
dimension and metric to match the embedder. The adapter uses Pinecone's
versioned HTTPS data plane and requires an API key; it does not create or
configure indexes.

The adapter supports upserts of up to 64 documents per request, vector query,
namespace isolation, metadata equality filters, minimum-score filtering, and
deletion by ID. Request and response bodies are capped at 4 MiB. Content and
metadata are checked before embedding. Pinecone metadata values are limited to
JSON scalars and string arrays; page content is stored under a reserved key and
removed when documents are returned. Tests use an injected HTTP transport.

```v wip
mut store := pinecone.new_store(embedder, pinecone.Options{
	host:    'https://my-index.example.svc.pinecone.io'
	api_key: pinecone_api_key
})!
```

Index creation and administration, text-search integrated inference, sparse or
hybrid vectors, metadata-filter operators beyond equality, and returning stored
vector values remain unsupported.
