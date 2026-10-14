# Anthropic Messages

`anthropic.Client` implements `llms.Model` and `llms.CompletionModel` with the
Messages API. It supports streaming and non-streaming text and system messages, HTTPS image
URLs, inline JPEG/PNG/GIF/WebP images up to 5 MiB each, client tool
definitions/results, tool-use responses, generation stop sequences, and usage
accounting. Streaming uses bounded SSE parsing and supports text, thinking, and
client tool-use deltas. `complete` wraps a prompt as a user message.

Use `new_default_client(api_key)` for the shared bounded HTTP transport, or
inject an `httputil.HTTPClient` with `new_client` for offline tests and custom
transports. The client uses the `x-api-key` and `anthropic-version` headers,
omits provider error bodies from status errors, and never uses live credentials
in the test suite.

Reasoning replay and server tools are not implemented. The supported
`CallOptions.provider_options` keys include `thinking` (`adaptive`, `enabled`
with a bounded token budget, or `disabled`) and `output_config.effort` (`low`,
`medium`, `high`, `xhigh`, or `max`). Anthropic validates these values and
passes them through to the Messages API; model-specific compatibility remains
the caller's responsibility. See Anthropic's [extended thinking guide](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/prompt-templates-and-variables)
for current model support. Streaming requires a transport implementing the streaming HTTP
contract. HTTPS image URLs are limited to 8192 bytes and may not include user
information; image detail hints are rejected. Unsupported common options return
errors instead of being silently ignored.

Set `Options.callbacks` at construction, or assign the client's `callbacks`
field, to receive one generate-content start event before each request and
then either an end event with the response or an error event, for streaming
and non-streaming calls alike.

Reasoning blocks round-trip. Thinking parts parsed from responses keep
their signature, and redacted thinking parts keep their opaque data; sending
those parts back on a later turn emits the original blocks. Thinking replay
requires the signature from the original response, and thinking text,
signatures, and redacted data are each capped at 1 MiB.
