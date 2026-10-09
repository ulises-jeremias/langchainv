# OpenAI chat completions

This package currently implements text and image chat completions through the shared
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

Chat requests support text parts and user image URL parts, including data URLs,
with optional `auto`, `low`, or `high` detail, following the
[Chat Completions message content format](https://platform.openai.com/docs/api-reference/chat/object).
The adapter passes image URLs through to OpenAI and does not download or inspect
the referenced images. Raw binary, audio, and reasoning content parts remain
unsupported. Function tools can be declared with `CallOptions.tools`, including
an optional JSON Schema parameter object, and selected with
`CallOptions.tool_choice`, following the
[Chat Completions API](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create).
Returned calls are available through
`llms.Choice.tool_calls` and can be replayed with `Response.assistant_message()`;
tool results use a `.tool` message with one `schema.ToolResult` part. Streaming
tool calls are not supported. Streaming text is available through
`CallOptions.streaming_func` for one choice; it parses SSE incrementally, caps
each incomplete event at 1 MiB, and returns the accumulated text and usage when
the stream completes. The shared callback contract has no choice index, so
streaming multiple alternatives is rejected. Legacy function calling options,
the legacy completions endpoint, and Azure-specific authentication and URL
behavior are not implemented. V's standard HTTP client does not expose
request-context cancellation while waiting for the next network chunk.
Cancellation is checked as chunks arrive and before and after the request. The
client also retains the complete raw SSE response until the request finishes,
even though callbacks receive parsed text deltas as chunks arrive. Set
`CallOptions.max_tokens` when a bounded
completion size is important.

The adapter rejects options it does not implement instead of silently ignoring
them. It disables redirects on authenticated requests so an API key cannot be
forwarded to a different host. For the pinned `o1`, `o1-mini`, `o1-preview`,
`o3`, `o3-mini`, and `o3-preview` model names, it moves system text into the first user
message and omits temperature; it also omits temperature for `o4`, `gpt-5`,
and search-preview model names.
