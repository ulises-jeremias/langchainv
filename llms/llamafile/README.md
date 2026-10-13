# Llamafile

`llms/llamafile` connects to the current llamafile server's OpenAI-compatible
Chat Completions API at `http://127.0.0.1:8080/v1` by default. It reuses the
shared OpenAI message conversion, tool-call, usage, and bounded transport
behavior. Configure a model and endpoint with `Options`; loopback HTTP and
HTTPS endpoints are accepted, while remote cleartext endpoints are rejected.

The adapter implements `llms.Model` and `llms.CompletionModel` through
`generate_content` and `complete`. It inherits the shared OpenAI streaming
callbacks when the injected HTTP transport supports streaming, and rejects
unsupported generation options explicitly. For embeddings, use
`embeddings/openai` with the llamafile `/v1/embeddings` endpoint.

The pinned LangChainGo llamafile adapter targets its legacy `/completion` and
`/embedding` API and includes llama.cpp-specific options. Current llamafile
documentation recommends its OpenAI-compatible API; those legacy routes and
llama.cpp-only options are not implemented here.

Tests use an injected fake transport and make no local server or model calls.

Set `Options.callbacks` to receive one generate-content start event before each request and then either an end event with the response or an error event.
