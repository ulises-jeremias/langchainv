# Cohere Chat

This package implements non-streaming Cohere Chat API v2 through the shared
injectable bounded HTTP transport.

```v
import context
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.llms.cohere

mut ctx := context.background()
client := cohere.new_default_client('your-api-key')!
response := client.generate_content(mut ctx, [schema.text_message(.human, 'Hello')],
	llms.CallOptions{})!
println(response.choices[0].content)
```

The adapter supports text messages, function tool definitions and calls, tool
results, JSON object mode, one candidate, bounded response decoding, stop
sequences, common sampling controls, token usage, and configurable model/base
URL. It sends credentials using bearer authentication. Streaming, image inputs,
reasoning replay, provider extensions, and named tool selection are rejected or
remain unsupported. Tests use a fake transport and never contact Cohere.

The older LangChainGo adapter used Cohere's `/v1/generate` endpoint. Cohere now
marks that endpoint deprecated, so this V adapter targets the supported
[`/v2/chat` API](https://docs.cohere.com/v2/reference/chat) instead of directing
users to the legacy generation route.
