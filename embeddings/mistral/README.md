# Mistral embeddings

`mistral.Client` implements `embeddings.EmbedderClient` using Mistral's
`POST /v1/embeddings` endpoint. The default model is `mistral-embed`, matching
LangChainGo. Batches are limited to 512 inputs, aggregate input to 1 MiB, JSON
requests to 8 MiB, and responses to 16 MiB. Result indices restore input order;
empty, duplicate, missing, out-of-range, non-finite, and inconsistent vectors
are rejected.

```v
module main

import context
import ulises_jeremias.langchainv.embeddings.mistral

fn main() {
	mut ctx := context.background()
	client := mistral.new_default_client('your-api-key') or { panic(err) }
	vectors := client.create_embedding(mut ctx, ['A short example.']) or { panic(err) }
	println(vectors[0])
}
```

Use `new_client_with_options` to configure the endpoint, model, or optional
`output_dimension`. Use `new_client` with an injected `httputil.HTTPClient` for
offline tests. The common `default_embedder()` and `embedder(...)` wrappers add
newline preprocessing and sequential batching. Tests use only a fake transport;
no Mistral credentials or billable requests are required.

See the [Mistral embeddings API](https://docs.mistral.ai/api/endpoint/embeddings)
for current model and request details.
