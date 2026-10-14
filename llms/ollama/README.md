# Ollama Chat

`ollama.Client` implements `llms.Model` and `llms.CompletionModel` using
Ollama's `POST /api/chat` endpoint. It supports text and bounded inline image
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
`num_gqa`, `num_gpu`, `main_gpu`, `num_thread`, `repeat_last_n`, `seed`,
`top_k`, `num_keep`, `mirostat`, `num_predict`, `rope_frequency_base`,
`rope_frequency_scale`, `typical_p`, `repeat_penalty`, `presence_penalty`,
`frequency_penalty`, `tfs_z`, `mirostat_tau`, `mirostat_eta`, `top_p`,
`temperature`, `numa`, `logits_all`, `vocab_only`, `use_mmap`, `use_mlock`,
`embedding_only`, `f16_kv`, `low_vram`, `penalize_newline`, and `think`.
Unknown keys and values with the wrong type fail before the request. Use the
common `CallOptions.stop_words` field for stop sequences. Provider options are
included in both streaming and non-streaming chat requests and take precedence
over matching common generation fields when both are set.

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

Inline image data is limited to 5 MiB per request; chat histories are capped at
1,024 messages and 128 tools. HTTP request and response bodies are capped at
8 MiB and 16 MiB. Image URLs are rejected because Ollama's chat endpoint
accepts base64 image data. See the [Ollama chat API](https://docs.ollama.com/api/chat)
for the wire contract.

Set `Options.callbacks` at construction, or assign the client's `callbacks`
field, to receive one generate-content start event before each request and
then either an end event with the response or an error event, for streaming
and non-streaming calls alike.

Model management uses the server endpoints directly: `list_models` reads
`/api/tags`, `show_model` reads `/api/show`, `pull_model` downloads through
`/api/pull` with streaming progress disabled, and `delete_model` removes a
model through `/api/delete`. Names are validated (1 to 256 bytes, no control
characters) before any request, and responses share the 16 MiB cap. Pulling a
large model can take a long time; the transport timeout and context bound
the call.
