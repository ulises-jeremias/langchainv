# Google AI / Gemini

`googleai.Client` implements Gemini `generateContent` and SSE-based
`streamGenerateContent` for text
messages, system instructions, bounded inline images, and function tools. It
maps text candidates, function calls, finish reasons, and usage counts into the
shared LLM response types, and supports maximum output tokens, temperature,
top-p, top-k, stop sequences, candidate count, seed, and JSON MIME output. The
API key is sent in the `x-goog-api-key` header and is not placed in the URL.

Use `new_default_client(api_key)` with the shared bounded HTTP transport, or
inject an `httputil.HTTPClient` using `new_client` and `new_client_with_options`
for custom endpoints and offline tests. Endpoints must use HTTPS. The current
streaming requires an injected transport that supports incremental responses,
and callback streaming is limited to one candidate because callbacks do not
carry candidate indexes. The client explicitly rejects remote image URLs,
strict tool mode, and unsupported generation options; no API request is sent
for unsupported options. Inline images are capped at 5 MiB
per image, requests at 8 MiB, and responses at 16 MiB. Candidate count is
capped at 8 for non-streaming calls.

Use `llms.CallOptions.provider_options['response_schema']` for Gemini structured
output. Its value must be a non-empty `map[string]json2.Any`; it is sent as
`generationConfig.responseFormat.text.schema` with the `application/json` MIME
type. Other provider options are rejected. `count_tokens` implements the
shared `llms.TokenCounter` interface through the Gemini `countTokens`
endpoint: it sends the same bounded contents and system instruction as a
generation request without generation configuration, returns `totalTokens`,
and accepts an empty model to use the configured model. Gemini supports only a subset of
JSON Schema, and accepted keywords vary by API/model; the service may reject
schemas that it does not support. See Google's [structured output guide](https://ai.google.dev/gemini-api/docs/generate-content/structured-output)
for supported types, fields, models, and limitations. This feature works with
streaming and non-streaming generation.

```v
module main

import json2
import ulises_jeremias.langchainv.llms

fn main() {
	schema_json := '{"type":"object","properties":{"answer":{"type":"string"}},"required":["answer"]}'
	response_schema := json2.decode[map[string]json2.Any](schema_json,
		json2.DecoderOptions{}) or { panic(err) }
	options := llms.CallOptions{
		provider_options: {
			'response_schema': json2.Any(response_schema)
		}
	}
	println(options.provider_options.len)
}
```

Set `Options.callbacks` at construction, or assign the client's `callbacks`
field, to receive one generate-content start event before each request and
then either an end event with the response or an error event. Vertex clients
keep their own handler; events are not dispatched twice.
