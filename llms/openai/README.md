# OpenAI Chat Completions

`openai.Client` implements `llms.Model` and `llms.CompletionModel` using
`POST /v1/chat/completions`. It supports text, image URL and bounded inline
image messages, tool/function definitions and results, JSON mode, usage, and
provider tool-call responses. `complete` wraps a prompt as a user message.

Use `new_default_client(api_key)` for the shared bounded HTTP transport, or
inject an `httputil.HTTPClient` with `new_client` for offline tests or a custom
transport. Do not put API keys in source control or use live credentials in
tests. Provider error bodies are omitted from returned status errors.

This initial client uses a bounded non-streaming request. It returns an explicit
error if a streaming callback is configured; provider reasoning payload replay,
binary audio, response APIs, and the remaining provider-specific options are
not implemented yet. Unsupported common generation options fail explicitly
instead of being silently ignored.
