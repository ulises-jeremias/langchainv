# OpenAI Chat Completions

`openai.Client` implements `llms.Model` and `llms.CompletionModel` using
`POST /v1/chat/completions`. It supports text, image URL and bounded inline
image messages, tool/function definitions and results, JSON mode, usage, and
provider tool-call responses. It also supports JSON Schema constrained output
through the client's typed `Options.response_format` configuration. `complete`
wraps a prompt as a user message.

Use `new_default_client(api_key)` for the shared bounded HTTP transport, or
inject an `httputil.HTTPClient` with `new_client` for offline tests or a custom
transport. Do not put API keys in source control or use live credentials in
tests. Provider error bodies are omitted from returned status errors.

Configure a JSON Schema response format once when constructing a client. The
schema must be a non-empty JSON object, and its name must contain 1–64 ASCII
letters, digits, underscores, or hyphens. A configured response format takes
precedence over per-call JSON mode. Request bodies, including streaming
requests, are limited to 8 MiB.

```v
module main

import json2
import ulises_jeremias.langchainv.llms.openai

fn main() {
	schema_definition := json2.decode[map[string]json2.Any]('{"type":"object","properties":{"answer":{"type":"string"}},"required":["answer"],"additionalProperties":false}', json2.DecoderOptions{}) or {
		panic(err)
	}
	options := openai.Options{
		response_format: openai.ResponseFormat{
			kind:        'json_schema'
			json_schema: openai.JSONSchemaResponseFormat{
				name:        'answer'
				description: 'A short answer'
				schema:      schema_definition
				strict:      true
			}
		}
	}
	println(options.model)
}
```

Requests and responses are size-bounded. Streaming requires a transport that
implements `httputil.StreamingHTTPClient`; streamed text, reasoning deltas,
tool-call assembly, and usage are supported. Provider reasoning replay, binary
audio, the Responses API, and remaining provider-specific options are not
implemented yet. Unsupported common generation options fail explicitly instead
of being silently ignored.
