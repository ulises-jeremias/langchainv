# SQLite response cache

`llms/cache/sqlite` implements the shared response-cache backend with bounded
SQLite persistence. Entries survive process restarts. Configure both an entry
limit and a maximum total of JSON-encoded response payload bytes; writes evict
the oldest entries until both limits hold.

Responses larger than the byte limit are skipped without replacing an existing
entry for the same key. The byte limit measures serialized response payloads,
not SQLite pages, indexes, or filesystem allocation. The SQLite database
contains response data in plaintext, so protect the file with appropriate
permissions and encryption-at-rest controls.

```v
import context
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.cache
import ulises_jeremias.langchainv.llms.cache.sqlite
import ulises_jeremias.langchainv.llms.fake

fn main() {
	backend := sqlite.new_cache('responses.sqlite', 1000, 64 * 1024 * 1024) or {
		panic(err)
	}
	defer {
		backend.close() or { panic(err) }
	}
	model := cache.new_cacher(llms.Model(fake.new_fake_llm(['cached response'])), backend)
	mut ctx := context.background()
	_ = model
	_ = ctx
}
```
