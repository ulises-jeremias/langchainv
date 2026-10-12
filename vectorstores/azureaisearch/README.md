# Azure AI Search vector store

`azureaisearch.new_store` implements the shared vector-store contract over the
Azure AI Search data-plane REST API. It targets an existing index; it does not
create, update, or delete index schemas. The adapter pins REST API version
`2026-04-01` and uses Azure's `api-key` request header. See Microsoft's guides
for [document indexing](https://learn.microsoft.com/en-us/rest/api/searchservice/documents/?view=rest-searchservice-2026-04-01),
[vector search](https://learn.microsoft.com/en-us/rest/api/searchservice/documents/search-post?view=rest-searchservice-2026-04-01),
and [API key permissions](https://learn.microsoft.com/en-us/azure/search/search-security-api-keys).

## Index requirements

Create fields matching `Options` before connecting. This minimal REST request
creates an index for 1,536-dimensional embeddings; change that dimension to
match the selected embedding model:

- `id`: `Edm.String`, key field.
- `content`: retrievable `Edm.String`.
- `contentVector`: `Collection(Edm.Single)` with the embedding
  model's exact dimensions and a cosine vector-search profile.
- `metadata`: retrievable `Edm.String`; the adapter stores a JSON object in
  this field.
- `namespace`: `Edm.String`, retrievable and filterable.

```sh
curl --fail-with-body --request PUT \
  "https://${AZURE_SEARCH_SERVICE}.search.windows.net/indexes('knowledge')?api-version=2026-04-01" \
  --header "Content-Type: application/json" \
  --header "api-key: ${AZURE_SEARCH_ADMIN_KEY}" \
  --data-binary @- <<'JSON'
{
  "name": "knowledge",
  "fields": [
    { "name": "id", "type": "Edm.String", "key": true },
    { "name": "content", "type": "Edm.String", "searchable": true, "retrievable": true },
    { "name": "contentVector", "type": "Collection(Edm.Single)", "searchable": true, "dimensions": 1536, "vectorSearchProfile": "knowledge-vector-profile" },
    { "name": "metadata", "type": "Edm.String", "retrievable": true },
    { "name": "namespace", "type": "Edm.String", "filterable": true, "retrievable": true }
  ],
  "vectorSearch": {
    "algorithms": [{ "name": "knowledge-hnsw", "kind": "hnsw", "hnswParameters": { "metric": "cosine" } }],
    "profiles": [{ "name": "knowledge-vector-profile", "algorithm": "knowledge-hnsw" }]
  }
}
JSON
```

Index creation and the adapter's upload/delete operations require an admin key.
Search-only clients can use a query key, but this adapter uses one key for all
operations. Entra ID/RBAC authentication is not implemented. The key field
needs filterability only if the application independently queries by key.

All field names can be changed in `Options`. Keep the key and vector fields
configured to match the index. The namespace field must support OData equality
filtering. Metadata predicates are not mapped to index fields by this adapter.

## Usage

```v wip
import os
import ulises_jeremias.langchainv.vectorstores.azureaisearch as azure_search

service_name := os.getenv('AZURE_SEARCH_SERVICE')
store := azure_search.new_store(embedder, azure_search.Options{
	endpoint: 'https://${service_name}.search.windows.net'
	index_name: 'knowledge'
	api_key: os.getenv('AZURE_SEARCH_ADMIN_KEY')
})!
```

The API key and endpoint should come from the deployment environment or a
secret manager. Remote endpoints must use HTTPS. Tests inject an
`httputil.HTTPClient`; they do not require Azure credentials or a live service.

## Behavior and limits

- Upload and delete accept at most 64 actions per request. Every per-document
  indexing result is checked; an HTTP success with a rejected action returns an
  error.
- Search embeds one query and issues a vector query against the configured
  vector field. Namespace equality is escaped as an OData string literal.
- Search limits are 0–1,000; queries are limited to 64 KiB; request and response
  bodies are capped at 4 MiB; vectors are limited to 65,536 finite values.
- Metadata is serialized into one string field and parsed on retrieval. Exact
  metadata filters, hybrid text search, custom index lifecycle, returned
  vectors, and other distance strategies are not implemented. Requests asking
  for metadata filters or vectors fail explicitly.
- Azure indexing can partially accept a batch. The adapter reports any failed
  action but does not roll back actions already accepted by the service.
