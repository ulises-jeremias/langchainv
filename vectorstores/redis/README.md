# Redis Stack vector store

This adapter targets a preconfigured Redis Stack HASH index using RediSearch
vector KNN. It uses `db.redis` from the V standard library and accepts an
injected command client for offline tests. The store does not open or close the
connection and does not create or drop indexes.

## Index setup

Create an index whose prefix and field names match the store options. `content`
can be indexed as text or left unindexed; `metadata` is returned as a stored
HASH field. The namespace and ownership fields must be TAG fields. Configure the
vector field for FLOAT32 and COSINE with the exact dimension used by the
embedder. Add each metadata filter field as a TAG using the `meta_` prefix.

```text
FT.CREATE langchainv_idx ON HASH PREFIX 1 doc:langchainv: SCHEMA \
  content TEXT namespace TAG lcg_source TAG meta_kind TAG \
  content_vector VECTOR FLAT 6 TYPE FLOAT32 DIM 1536 DISTANCE_METRIC COSINE
```

## V usage

```v wip
import db.redis as redis_client
import ulises_jeremias.langchainv.vectorstores.redis as redis_vector

mut client := redis_client.connect(redis_client.Config{
	host:     'redis.example.com'
	port:     6379
	tls:      true
	password: '...'
})!
store := redis_vector.new_store(embedder, redis_vector.StandardRedisClient{
	db: &client
}, redis_vector.Options{
	index:      'langchainv_idx'
	dimensions: 1536
})!
```

Records use keys under `doc:langchainv:` and include content, JSON metadata,
namespace, a binary little-endian FLOAT32 vector, a `lcg_source=langchainv`
marker, and JSON-encoded scalar metadata fields named `meta_<key>`. The
`lcg_source` field must be indexed as TAG. The marker keeps KNN search scoped to
records written by this adapter. Returned IDs are Redis keys and can be passed
to `delete`.

## Bounds and supported behavior

- Writes accept at most 64 documents per call. Content, serialized metadata,
  and namespace are each limited to 64 KiB; the combined command batch is
  limited to 4 MiB.
- Search accepts at most 30 results and 128 exact scalar metadata filters, with
  a 64 KiB aggregate filter limit.
  Namespace and metadata values use escaped RediSearch TAG equality queries.
  Scores are `1 - cosine distance`; `min_score` is applied after retrieval and
  can return fewer than the requested count. Set `SearchOptions.include_vectors`
  to return the stored binary vector in `schema.Document.embedding`; it is
  omitted by default and decoded with dimension and finite-value checks.
- Delete accepts at most 1,000 returned Redis keys. Namespace-constrained
  deletion is rejected because read-then-delete would not be atomic.
- The configured index must exist and match the HASH schema. Index management,
  alternate metrics, and advanced RediSearch query syntax are not implemented.
- Redis commands are sequential. If Redis fails partway through a multi-record
  write, earlier HSET commands may already have succeeded. The response cap is
  safe for records written through this adapter and assumes the Redis index is
  not modified by untrusted writers.

CI uses a fake Redis command client; it does not require a Redis service.
