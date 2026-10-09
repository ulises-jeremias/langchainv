# OpenAI chat completions

This package currently implements text chat completions through the shared
`llms.Model` and `llms.CompletionModel` interfaces. It reads `OPENAI_API_KEY`
when `Config.api_key` is empty and defaults to `gpt-3.5-turbo` and
`https://api.openai.com/v1`.

```v
import context
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.openai
import ulises_jeremias.langchainv.schema

mut client := openai.new(api_key: api_key, model: 'gpt-4o')!
mut ctx := context.background()
response := client.generate_content(mut ctx, [schema.text_message(.human, 'Hello')],
	llms.CallOptions{})!
println(response.choices[0].content)
```

Only text parts are supported in this initial slice. The adapter does not yet
implement streaming, tool calls, embeddings, the legacy completions endpoint,
or Azure-specific authentication and URL behavior. V's standard HTTP client
does not expose request-context cancellation while a request is in flight;
the adapter checks cancellation before and after each request.

The adapter rejects options it does not implement instead of silently ignoring
them. It disables redirects on authenticated requests so an API key cannot be
forwarded to a different host. For the pinned `o1`, `o1-mini`, `o1-preview`,
`o3`, `o3-mini`, and `o3-preview` model names, it moves system text into the first user
message and omits temperature; it also omits temperature for `o4`, `gpt-5`,
and search-preview model names.
