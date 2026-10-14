# Amazon Bedrock Converse

`bedrock.Client` calls the Bedrock Runtime Converse API with an explicit Amazon
Bedrock API key. Configure `Options` for the AWS region and model ID, or use
`new_default_client` with the default region and Claude 3.5 Haiku model. Tests
use an injected fake transport and never call AWS.

The client supports text messages, bounded inline JPEG/PNG images, client-side
tool use and replay, max tokens, temperature, top-p, stop sequences, stop
reasons, and token usage. ConverseStream supports text and reasoning deltas,
tool calls with fragmented JSON inputs, and usage metadata when the injected
transport supports incremental responses. EventStream frames are CRC checked
and capped at 1 MiB each. Requests are capped at 5 MiB, responses at 8 MiB, and
inline image data at 3 MiB. Provider error bodies are omitted from status errors.

Authentication uses `Authorization: Bearer ...` with a Bedrock API key. AWS
credential discovery and SigV4 signing are not implemented. The adapter uses
the current Converse API; reasoning replay, non-Converse InvokeModel providers,
custom model ARNs, and remaining provider-specific options are not implemented.
Bedrock API keys are not included in tests or source code.

Set `Options.callbacks` to receive one generate-content start event before each request and then either an end event with the response or an error event.

Reasoning content round-trips. Responses keep the reasoning text, its
signature, and any redacted content in the parsed parts, and sending those
parts on a later turn emits the original `reasoningContent` blocks. Replay
requires the signature from the original response, and each piece is capped
at 1 MiB.
