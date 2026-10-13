---
layout: default
title: Redis Stack vector search
permalink: /tutorials/redis-vector-search/
---

# Redis Stack vector search

The Redis adapter stores documents as HASH records and searches them through a
RediSearch vector index. It accepts an injected command client, so adapter
tests run offline. The application owns the Redis connection and its lifecycle.

## Create the index explicitly

Read the [Redis adapter guide](https://github.com/ulises-jeremias/langchainv/blob/main/vectorstores/redis/README.md)
before connecting. `initialize_index(client, options, metadata_fields)` creates
a FLAT/COSINE index by default. Set `Options.algorithm` to `HNSW` to explicitly
create an approximate HNSW/COSINE index; tune it with bounded `hnsw_m` and
`hnsw_ef_construction` values. Set `hnsw_ef_runtime` when binding the store to
tune each HNSW query's recall/latency tradeoff. Both index algorithms match the
configured prefix, fields, and embedding dimension. List each scalar metadata
key that must be searchable; the adapter indexes it as a TAG field named
`meta_<key>`. See the [official Redis vector search guide](https://redis.io/docs/latest/develop/ai/search-and-query/vectors/)
for query-time `EF_RUNTIME` behavior.

`FT.CREATE` scans existing HASH records matching the prefix and allocates index
memory. HNSW's graph can use substantially more memory than FLAT, and its
construction settings affect indexing time and search quality. Call it
deliberately against the Redis server after considering the dataset size and
server capacity. It does not drop or replace an existing index. `new_store`
only binds an already-created index to an embedder/client.

## Store and retrieve

Insert documents through `add_documents`, then search with
`similarity_search`. Writes are limited to 64 documents per call; search returns
up to 30 matches, and vector return is opt-in through
`SearchOptions.include_vectors`. Metadata filters and namespaces use escaped
TAG equality expressions. The adapter supports cosine only and limits indexed
metadata filters to scalar values. See the package guide for payload bounds,
field naming rules, partial-write behavior, and index command details.
