# Cloudflare Workers AI

This package calls Workers AI through its OpenAI-compatible Chat Completions
route. Configure the 32-character Cloudflare account ID, API token, and model
ID; models use names such as `@cf/meta/llama-3.1-8b-instruct`.

```v
import context
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.llms.cloudflare

mut ctx := context.background()
client := cloudflare.new_default_client('your-api-token', '0123456789abcdef0123456789abcdef',
	'@cf/meta/llama-3.1-8b-instruct')!
response := client.generate_content(mut ctx, [schema.text_message(.human, 'Hello')],
	llms.CallOptions{})!
println(response.choices[0].content)
```

The adapter reuses the shared OpenAI-compatible chat implementation, including
supported text/image messages, tools, usage mapping, and bounded transport. It
translates `max_completion_tokens` to Workers AI's `max_tokens`. Available
options vary by model; Workers AI-specific `rejectIfBusy`, streaming, and
provider-only controls remain outstanding. Tests use an injected fake
transport and never contact Cloudflare.

See Cloudflare's [OpenAI-compatible API documentation](https://developers.cloudflare.com/workers-ai/configuration/open-ai-compatibility/)
for supported routes and models.
