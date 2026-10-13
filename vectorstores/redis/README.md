# Redis Stack vector store

This adapter targets a Redis Stack HASH index using RediSearch vector KNN. It
uses `db.redis` from the V standard library and accepts an injected command
client for offline tests. The store does not open or close the connection.
`new_store` never manages indexes; `initialize_index` is an explicit,
non-destructive `FT.CREATE` helper.

## Index setup

Call `initialize_index(client, options, metadata_fields)` and pass the metadata
keys your application filters. The default `Options.algorithm` is `FLAT` for
exact search; set it to `HNSW` to explicitly build an approximate index. For
HNSW, `hnsw_m` defaults to 16 (adapter accepts 2..64) and
`hnsw_ef_construction` defaults to 200 (adapter accepts `M`..4096). Higher
values can cost more time and memory; see the [Redis vector index
guide](https://redis.io/docs/latest/develop/ai/search-and-query/vectors/).
When binding a store, `hnsw_ef_runtime` defaults to 10 (adapter accepts
1..4096) and is sent as a query-time parameter. Higher values can improve
recall at the cost of latency.
The helper creates an index whose prefix and field names match the options,
scans existing matching HASH records, indexes content as TEXT, and adds the
namespace/ownership and selected metadata keys as TAG fields. Existing indexes
are never dropped or reconfigured; Redis returns an error if the name already
exists. The vector field uses FLOAT32, COSINE, and the configured dimension.
Explicitly plan for the initial scan and index memory on the Redis server
before calling it.

To manage index lifecycle outside the adapter, the equivalent command is:

```text
FT.CREATE langchainv_idx ON HASH PREFIX 1 doc:langchainv: SCHEMA \
  content TEXT namespace TAG lcg_source TAG meta_kind TAG \
  content_vector VECTOR HNSW 10 TYPE FLOAT32 DIM 1536 DISTANCE_METRIC COSINE \
  M 16 EF_CONSTRUCTION 200
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

commands := redis_vector.StandardRedisClient{
	db: &client
}
options := redis_vector.Options{
	index:      'langchainv_idx'
	dimensions: 1536
	algorithm:  'HNSW'
	hnsw_ef_runtime: 150
}
redis_vector.initialize_index(commands, options, ['kind'])!
store := redis_vector.new_store(embedder, commands, options)!
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
- `initialize_index` creates a FLAT/COSINE index by default or an explicitly
  configured HNSW/COSINE index. Index deletion/reconfiguration, alternate
  metrics, and advanced RediSearch query syntax are not implemented.
- Redis commands are sequential. If Redis fails partway through a multi-record
  write, earlier HSET commands may already have succeeded. The response cap is
  safe for records written through this adapter and assumes the Redis index is
  not modified by untrusted writers.

CI uses a fake Redis command client; it does not require a Redis service.
