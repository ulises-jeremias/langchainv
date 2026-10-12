# Jina embeddings

`jina.Client` implements `embeddings.EmbedderClient` with `POST /v1/embeddings`.
It requests float vectors, restores provider results by their input indexes,
and rejects missing or duplicate results, inconsistent dimensions, empty
vectors, and non-finite values. Each request is limited to 512 non-empty inputs,
1 MiB of aggregate text, and 8 MiB of encoded JSON; responses are limited to
16 MiB.

Use `new_default_client(api_key)` for the bounded shared HTTP transport, or
inject an `httputil.HTTPClient` with `new_client` for offline tests. Custom
endpoints must use HTTPS. Wrap the client with `default_embedder()` or
`embedder(embeddings.Options{...})` for common newline preprocessing and
sequential batching.
