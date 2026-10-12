# OpenAI embeddings

`openai.Client` implements the common `embeddings.EmbedderClient` contract for
`POST /v1/embeddings`. It requests JSON float output, restores the provider's
input ordering using response indices, and rejects HTTP errors, missing or
duplicate indices, and empty vectors. Provider error bodies are not included
in returned errors.

Use `new_default_client(api_key)` for the shared bounded HTTP transport, or
inject an `httputil.HTTPClient` with `new_client` for a controlled transport or
offline tests. Configure a model, endpoint, or output dimension through
`new_client_with_options`. Wrap the client with `default_embedder()` or
`embedder(embeddings.Options{...})` to get common newline preprocessing and
sequential batch handling. Keep API keys out of source control and do not use
live credentials in tests.
