# Ollama chat and completion

`ollama.Client` implements `llms.Model` through `POST /api/chat` and
`llms.CompletionModel` through the prompt-oriented `POST /api/generate` endpoint.
`complete` sends the prompt directly to generate; call `generate_content` when
you want chat semantics. The chat API supports text and bounded inline image
messages, client tool definitions and tool-call responses, JSON mode and
JSON-Schema-constrained output, generation options, thinking replay, and
prompt/completion usage counts. Streaming requests
consume bounded newline-delimited JSON and invoke text or reasoning callbacks
as chunks arrive.

`new_default_client(model)` targets `http://127.0.0.1:11434`. Use
`new_client(http_client, options)` for an alternate endpoint or deterministic
tests. The client does not download or pull models automatically unless the
application explicitly calls a model-management method. Streaming requires a
transport that implements the streaming HTTP contract. Unsupported common
options return errors rather than being silently ignored.

Ollama runner options can be supplied per call through
`llms.CallOptions.provider_options`. Supported keys are `num_ctx`, `num_batch`,
`num_gpu`, `main_gpu`, `num_thread`, `repeat_last_n`, `seed`, `top_k`,
`num_keep`, `num_predict`, `draft_num_predict`, `top_logprobs`, `typical_p`,
`repeat_penalty`, `presence_penalty`, `frequency_penalty`, `top_p`, `min_p`,
`temperature`, `use_mmap`, `logprobs`, `truncate`, `shift`, and `think`.
`think`, `logprobs`, `top_logprobs`, `truncate`, and `shift` are sent as top-level
chat request fields; generation controls are sent under `options`.
Unknown keys and values with the wrong type fail before the request. Use the
common `CallOptions.stop_words` field for stop sequences. Provider options are
included in both streaming and non-streaming chat requests and take precedence
over matching common generation fields when both are set.

For `/api/generate`, `system`, `suffix`, `template`, and `raw` are also accepted
as typed provider options and sent as top-level prompt-generation fields;
`truncate` and `shift` are rejected because that endpoint does not support them.

The option allowlist follows the current Ollama API. Legacy LangChainGo adapter
fields removed from current Ollama (`num_gqa` and Mirostat controls) are not
sent, because the current server does not define them.

Set `Options.format_schema` to a JSON object string to send a schema as Ollama's
`format` value. The schema is decoded and validated at client construction,
cannot be combined with `Options.format`, and is limited by the 8 MiB request
bound. When configured, it takes precedence over per-call JSON mode. Otherwise,
`Options.format: 'json'` or `CallOptions.json_mode` selects ordinary JSON mode.

```v
module main

import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms.ollama

fn main() {
	client := ollama.new_client(httputil.HTTPClient(httputil.new_default_client()),
		ollama.Options{
			model:         'gemma4'
			format_schema: '{"type":"object","properties":{"answer":{"type":"string"}},"required":["answer"]}'
		}) or { panic(err) }
	println(client.model)
}
```

Inline image data is limited to 5 MiB per chat request; chat histories are capped at
1,024 messages and 128 tools. HTTP request and response bodies are capped at
8 MiB and 16 MiB. Image URLs are rejected because Ollama's chat endpoint
accepts base64 image data. See the [Ollama chat API](https://docs.ollama.com/api/chat)
for the wire contract.

Set `Options.callbacks` at construction, or assign the client's `callbacks`
field. Chat calls emit generate-content start/end or error events. Completion
calls emit completion start/end or error events. Both paths use the same
callback behavior for streaming and non-streaming requests.

Generate completion prompts and request bodies are capped at 8 MiB. Streaming
`/api/generate` responses use bounded NDJSON parsing and require a final
`done: true` record; callbacks receive response and reasoning deltas as they
arrive. `CallOptions.provider_options` accepts validated generate fields,
including `system`, `suffix`, `template`, and `raw`. Tool calls remain a chat
API feature. See the [Ollama generate API](https://docs.ollama.com/api/generate).

Model management uses the server endpoints directly: `list_models` reads
`/api/tags`, `show_model` reads `/api/show`, `pull_model` downloads through
`/api/pull` with streaming progress disabled, and `delete_model` removes a
model through `/api/delete`. Names are validated (1 to 256 bytes, no control
characters) before any request, and responses share the 16 MiB cap. Pulling a
large model can take a long time; the transport timeout and context bound
the call.
