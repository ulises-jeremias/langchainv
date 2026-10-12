# Google AI / Gemini embeddings

`googleai.Client` implements `embeddings.EmbedderClient` using Gemini's
`batchEmbedContents` endpoint. The default model is `gemini-embedding-2`.
Clients may set a task type and output dimensionality; each request is limited
to 100 non-empty inputs and 8 MiB, and responses to 16 MiB. Returned vectors
must be finite, non-empty, and have matching dimensions.

Use `new_default_client(api_key)` with the shared bounded HTTP transport, or
inject an `httputil.HTTPClient` using `new_client` and
`new_client_with_options` for custom endpoints and offline tests. Endpoints
must use HTTPS, API keys are sent in the `x-goog-api-key` header, and provider
error bodies are excluded from returned errors. Wrap the client with
`default_embedder()` or `embedder(embeddings.Options{...})` for common newline
preprocessing and sequential batches.
