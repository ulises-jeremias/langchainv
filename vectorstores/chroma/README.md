# Chroma vector store

`chroma.new_store(embedder, options)` implements the shared vector store
contract over Chroma's REST API v2. It connects to an existing collection by
ID. Its configured dimension and distance metric must match the injected
embedder and requested score semantics. The adapter does not configure
server-managed embedding functions.

`new_store_with_collection` creates a collection by name, or gets it when
`get_or_create` is true, and binds the returned server ID to the store.
`new_store_with_collection_and_client` supports a caller-provided HTTP
transport. Collection creation uses Chroma's default configuration and L2
space. `Store.delete_collection` deletes the bound collection and every record
in it.

The adapter supports upserts of up to 64 documents, similarity queries with
scalar equality filters, namespace filtering, minimum-score filtering, and
deletion by ID. It stores page content in Chroma's document field. Namespaces
use the reserved `_langchainv_namespace` metadata key, which the adapter removes
from returned documents. The default namespace is `langchain`; a per-operation
namespace overrides it. Request and response bodies are capped at 4 MiB;
queries and deletes are limited to 1,000 records, and each write/query accepts
at most 65,536 embedding values. Scores use `1 - distance`,
matching the LangChainGo adapter's score mapping. Collection routes follow the
[Chroma REST collection API](https://docs.trychroma.com/reference/chroma-api/collection/create-collection).

Loopback servers may use HTTP. Remote servers must use HTTPS. Set `api_key` to
send the `x-chroma-token` header. Tests inject an HTTP client and do not need a
Chroma server or credentials. See the [Chroma API reference](https://api.trychroma.com/docs/).

```v
mut store := chroma.new_store(embedder, chroma.Options{
	base_url:      'https://chroma.example.test'
	tenant:        'default_tenant'
	database:      'default_database'
	collection_id: '11111111-1111-4111-8111-111111111111'
	api_key:       chroma_api_key
})!
```

Custom collection configuration, Chroma-managed embedding functions, array
metadata, advanced filter operators, returned vector values, and custom record
IDs remain unsupported.
