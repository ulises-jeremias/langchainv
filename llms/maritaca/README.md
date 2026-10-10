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

The adapter inherits the OpenAI package's bounded non-streaming messages, tools,
JSON mode, common options, transport limits, and response mapping. Tests use an
injected fake HTTP transport and do not contact Maritaca. Responses API,
streaming, and Maritaca-specific request options remain outside this adapter.

The provider documents Chat Completions compatibility and the
`https://chat.maritaca.ai/api` base URL in its
[API examples](https://docs.maritaca.ai/pt/examples/csharp-js).
