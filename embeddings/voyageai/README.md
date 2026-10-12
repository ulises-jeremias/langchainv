# Voyage AI embeddings

`voyageai.Client` implements the provider-facing `EmbedderClient` contract with
`POST /v1/embeddings`. Its `embedder()` adapter implements the common
`embeddings.Embedder` interface and sends documents with `input_type=document`
and queries with `input_type=query`.

Requests contain at most 1,000 non-empty texts and 4 MiB of aggregate input;
encoded JSON is capped at 8 MiB and responses at 16 MiB. Results must contain
one finite, non-empty, same-sized vector per input. The client requests float
vectors and omits provider error bodies from errors.

Use `new_default_client(api_key)` for the shared bounded HTTP transport, or
inject an `httputil.HTTPClient` with `new_client` for offline tests. Custom
endpoints must use HTTPS. The default model matches LangChainGo's
`voyage-2`; set `Options.model` to choose another Voyage model.
