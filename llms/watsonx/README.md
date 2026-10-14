# IBM watsonx.ai

`watsonx.Client` implements the upstream LangChainGo adapter's text-generation
contract using the watsonx.ai versioned REST API. It accepts exactly one human
text message and maps temperature, top-p, top-k, repetition penalty, seed,
maximum new tokens, and stop sequences. Responses include generated text, stop
reason, and available input/output token counts.

Supply either `Options.api_key` or an existing IAM token with
`Options.access_token`, along with a project ID and foundation model ID. The
API key and project ID fall back to `WATSONX_API_KEY` and `WATSONX_PROJECT_ID`.
When configured with an API key, the adapter exchanges it at IBM IAM and caches
the returned token until 60 seconds before its expiry. `Options.iam_url` and
`Options.base_url` can select alternate HTTPS endpoints; `Options.api_version`
defaults to the version used by upstream `watsonx-go` v1.0.0. Tests use injected
fake HTTP for both IAM and generation and do not call IBM Cloud.

Streaming uses IBM's stable `/ml/v1/text/generation_stream` SSE endpoint and
requires an `httputil.StreamingHTTPClient`. The callback receives incremental
text chunks; the returned choice contains their concatenation and the latest
stop reason and token usage. Non-streaming requests use
`/ml/v1/text/generation`. Both use the configured API version, which defaults
to `2024-05-20`. See IBM's [text streaming tutorial](https://www.ibm.com/docs/en/watsonx/saas?topic=hub-stream-text-tutorial)
for the wire format.

```v
module main

import context
import os
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.watsonx
import ulises_jeremias.langchainv.schema

fn main() {
	mut client := watsonx.new_default_client(watsonx.Options{
		project_id: os.getenv('WATSONX_PROJECT_ID')
		model: 'ibm/granite-3-8b-instruct'
		api_key: os.getenv('WATSONX_API_KEY')
	}) or { panic(err) }
	stream := llms.StreamFunc(fn (mut _ context.Context, chunk []u8) ! {
		print(chunk.bytestr())
	})
	mut ctx := context.background()
	response := client.generate_content(mut ctx, [schema.text_message(.human, 'Say hello.')], llms.CallOptions{
		streaming_func: stream
	}) or { panic(err) }
	println('Tokens: ${response.usage.total_tokens}')
}
```

Multimodal/chat history, reasoning-stream callbacks, multiple candidates, and
unsupported common generation options are rejected before an API request.
Prompts default to a 256 KiB bound; request bodies and decoded or streamed
responses are capped at 512 KiB and 4 MiB.
