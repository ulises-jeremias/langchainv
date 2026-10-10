# Ollama embeddings

`ollama.Client` implements `embeddings.EmbedderClient` with `POST /api/embed`.
It accepts a batch of non-empty strings and returns the vectors in input order.
The response must contain exactly one finite, non-empty vector per input, all
with the same dimension. Inputs are limited to 1,024 strings and request and
response bodies are capped at 8 MiB and 16 MiB.

Use `new_default_client(model)` for the shared bounded HTTP transport and the
local Ollama endpoint at `127.0.0.1:11434`, or inject an
`httputil.HTTPClient` with `new_client` for a controlled transport or offline
tests. The client does not download models or connect to the server until an
embedding request is made. Wrap it with `default_embedder()` or
`embedder(embeddings.Options{...})` for common newline preprocessing and
sequential batch handling.
