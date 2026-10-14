# Response cache

`llms/cache` wraps any `llms.Model` with a pluggable response cache. The
request key is a SHA-256 digest of canonical JSON containing ordered messages,
typed multimodal parts, metadata, and every `CallOptions` field except callback
functions. Prompt and response content is never written to logs by this package.

`llms/cache/inmemory` provides a concurrency-safe FIFO cache with a fixed entry
limit. Choose a capacity based on response sizes: the bound limits entry count,
not total bytes. Use a persistent backend when entries must survive process
restarts.

```v
import context
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.cache
import ulises_jeremias.langchainv.llms.cache.inmemory
import ulises_jeremias.langchainv.llms.openai
import os

fn main() {
	client := openai.new_default_client(os.getenv('OPENAI_API_KEY')) or { panic(err) }
	backend := inmemory.new_cache(256) or { panic(err) }
	model := cache.new_cacher(llms.Model(client), backend)
	mut ctx := context.background()
	_ = model
	_ = ctx
}
```

Streaming callbacks run for both misses and hits; a hit replays the first
choice's text as one chunk. Reasoning-stream requests bypass caching because
the response contract does not preserve reasoning chunk boundaries. Custom
backends must honor context cancellation, avoid logging keys or payloads, and
return an independent response snapshot from `get`.
