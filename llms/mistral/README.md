# Mistral

This package adapts the Mistral Chat Completions endpoint through the existing
OpenAI request and response implementation. The HTTP boundary translates
`max_completion_tokens` to Mistral's `max_tokens` and `seed` to `random_seed`.

```v
import context
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.llms.mistral

mut ctx := context.background()
client := mistral.new_default_client('your-api-key')!
response := client.generate_content(mut ctx, [schema.text_message(.human, 'Hello')],
	llms.CallOptions{})!
println(response.choices[0].content)
```

Configure a regional endpoint or another supported model with
`new_client_with_options`. The adapter inherits the OpenAI package's supported
message, tool, JSON mode, bounded transport, and error behavior. Provider-only
Mistral features and behavior differences beyond the translated token fields
are not covered. Tests use an injected fake transport and never contact Mistral.

The upstream endpoint is documented as OpenAI-compatible at
[`https://api.mistral.ai/v1`](https://docs.mistral.ai/resources/migration-guides).
