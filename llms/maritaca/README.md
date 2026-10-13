# Maritaca

This package adapts Maritaca's OpenAI-compatible Chat Completions API. Provide
an API key and optionally choose a model or compatible base URL:

```v
import context
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.maritaca
import ulises_jeremias.langchainv.schema

mut ctx := context.background()
client := maritaca.new_default_client('your-api-key')!
response := client.generate_content(mut ctx, [schema.text_message(.human, 'Olá')],
	llms.CallOptions{})!
println(response.choices[0].content)
```

The adapter inherits the OpenAI package's bounded messages, tools, JSON mode,
common options, transport limits, streaming, and response mapping. Streaming
requires a streaming-capable injected HTTP transport. Tests use an injected fake
HTTP transport and do not contact Maritaca. The Responses API and
Maritaca-specific request options remain outside this adapter.

The provider documents Chat Completions compatibility and the
`https://chat.maritaca.ai/api` base URL in its
[API examples](https://docs.maritaca.ai/pt/examples/csharp-js).

Set `Options.callbacks` to receive one generate-content start event before each request and then either an end event with the response or an error event.
