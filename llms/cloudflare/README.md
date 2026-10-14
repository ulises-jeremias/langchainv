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
options vary by model; chat streaming works when the injected HTTP transport
implements the streaming contract. Set `Options.reject_if_busy` to add
Workers AI's `options.rejectIfBusy` request field to synchronous chat calls;
this asks the service to fail with a capacity error instead of waiting in its
queue. It is omitted from streaming requests. Other provider-only controls
are model-dependent and are not forwarded unless explicitly supported by the
adapter. Tests use an injected fake transport and never contact Cloudflare.

See Cloudflare's [OpenAI-compatible API documentation](https://developers.cloudflare.com/workers-ai/configuration/open-ai-compatibility/)
for supported routes and models, and its [reject-busy documentation](https://developers.cloudflare.com/workers-ai/features/reject-if-busy/)
for capacity behavior.

The same client implements `create_embedding` and the common
`embeddings.EmbedderClient` contract. Set `Options.embedding_model` to select a
Workers AI embedding model; it defaults to `@cf/baai/bge-base-en-v1.5`. The
client uses the bounded OpenAI-compatible embeddings route, validates returned
indices and vectors, and restores input order. Wrap it with `default_embedder()`
or `embedder(embeddings.Options{...})` for common batching and preprocessing.
For example, `client.create_embedding(mut ctx, ['a short document'])!` returns
the model vector directly, while `client.default_embedder()!` adds the common
query and document methods.

Embedding-only applications can use `new_default_embedding_client` without
configuring a chat model, or select a custom embedding model with
`new_embedding_client`.

Set `Options.callbacks` to receive one generate-content start event before each request and then either an end event with the response or an error event.
