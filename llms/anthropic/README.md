# Anthropic Messages

`anthropic.Client` implements `llms.Model` and `llms.CompletionModel` with the
non-streaming Messages API. It supports text and system messages, client tool
definitions/results, tool-use responses, generation stop sequences, and usage
accounting. `complete` wraps a prompt as a user message.

Use `new_default_client(api_key)` for the shared bounded HTTP transport, or
inject an `httputil.HTTPClient` with `new_client` for offline tests and custom
transports. The client uses the `x-api-key` and `anthropic-version` headers,
omits provider error bodies from status errors, and never uses live credentials
in the test suite.

Streaming, image content, reasoning replay, server tools, and provider-specific
options are not implemented. Unsupported common options return errors instead
of being silently ignored.
