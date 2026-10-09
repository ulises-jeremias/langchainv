# OpenAI chat completions

This package currently implements text chat completions through the shared
`llms.Model` and `llms.CompletionModel` interfaces, plus `create_embedding`
through the shared `embeddings.EmbedderClient` contract. It reads
`OPENAI_API_KEY` when `Config.api_key` is empty and defaults to
`gpt-3.5-turbo`, `text-embedding-ada-002`, and `https://api.openai.com/v1`.

Set `Config.embedding_model` and `Config.embedding_dimensions` to override the
embedding endpoint defaults. The provider returns vectors in the response's
original order; preprocessing and batching are provided by the core embedding
helpers.

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

Only text parts are supported in chat requests. Streaming is available through
`CallOptions.streaming_func` for one choice; it parses SSE incrementally, caps
each incomplete event at 1 MiB, and returns the accumulated text and usage when
the stream completes. The shared callback contract has no choice index, so
streaming multiple alternatives is rejected. Tool calls, the legacy
completions endpoint, and Azure-specific authentication and URL behavior are
not implemented. V's standard HTTP client does not expose request-context
cancellation while waiting for the next network chunk; cancellation is checked
as chunks arrive and before/after the request. It also retains the complete raw
SSE response until the request finishes, even though callbacks receive parsed
text deltas as chunks arrive. Set `CallOptions.max_tokens` when a bounded
completion size is important.

The adapter rejects options it does not implement instead of silently ignoring
them. It disables redirects on authenticated requests so an API key cannot be
forwarded to a different host. For the pinned `o1`, `o1-mini`, `o1-preview`,
`o3`, `o3-mini`, and `o3-preview` model names, it moves system text into the first user
message and omits temperature; it also omits temperature for `o4`, `gpt-5`,
and search-preview model names.
