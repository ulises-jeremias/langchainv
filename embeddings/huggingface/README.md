# Hugging Face embeddings

`huggingface.Client` implements `embeddings.EmbedderClient` with the hosted
Inference Providers feature-extraction route. It sends model IDs and text
inputs to `POST /hf-inference/models/{owner}/{model}/pipeline/feature-extraction`
with a bearer token, then validates one finite, non-empty, same-sized vector
per input.

Requests are limited to 64 texts, 1 MiB of aggregate input, and 8 MiB of JSON;
responses are limited to 16 MiB. Use `new_default_client(token)` for the
bounded shared HTTP transport, or inject an `httputil.HTTPClient` with
`new_client` for offline tests. Configure a different model, task, or HTTPS
router-compatible base URL with `Options`. Wrap the client with `default_embedder()` or
`embedder(embeddings.Options{...})` for common newline preprocessing and
sequential batching.
