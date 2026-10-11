# Ollama Chat

`ollama.Client` implements `llms.Model` and `llms.CompletionModel` using
Ollama's non-streaming `POST /api/chat` endpoint. It supports text and bounded
inline image messages, client tool definitions and tool-call responses, JSON
mode, generation options, thinking replay, and prompt/completion usage counts.

`new_default_client(model)` targets `http://127.0.0.1:11434`. Use
`new_client(http_client, options)` for an alternate endpoint or deterministic
tests. The client does not download or pull models automatically. Streaming,
model management, embedding endpoints, schema-valued output formats, and
provider-specific generation options are not implemented. Unsupported common
options return errors rather than being silently ignored.

Inline image data is limited to 5 MiB per request; chat histories are capped at
1,024 messages and 128 tools. HTTP request and response bodies are capped at
8 MiB and 16 MiB. Image URLs are rejected because Ollama's chat endpoint
accepts base64 image data. See the [Ollama chat API](https://docs.ollama.com/api/chat)
for the wire contract.
