# Dolt vector store

The `dolt` package implements `vectorstores.VectorStore` over an injected
MySQL-compatible `sqldatabase.Engine`. It targets an existing Dolt database and
never opens a connection, creates tables, or builds an index by itself. The
engine remains caller-owned.

## Setup

Provision tables explicitly, then decide whether to build a vector index for
approximate indexed retrieval. Dolt announced vector indexes over JSON as an
alpha feature; index construction and approximate search can consume
substantial resources and may trade recall for speed. Review the [Dolt vector index announcement](https://www.dolthub.com/blog/2025-01-16-announcing-vector-indexes/),
the [current vector syntax notes](https://www.dolthub.com/blog/2025-08-08-vector-type/),
and your Dolt version's current docs before enabling it. Dolt uses an index
when `VEC_DISTANCE` appears directly in `ORDER BY`; the retrieval query keeps
that expression in place. Verify exact-scan behavior and index availability
against the Dolt release you deploy.

```text
// Wiring sketch: configured_engine must implement sqldatabase.Engine, and
// my_embedder must implement embeddings.Embedder.
mut ctx := context.background()
options := dolt.Options{}

// Explicit calls: index builds may be resource-intensive.
dolt.initialize_tables(mut ctx, configured_engine, options)!
dolt.create_vector_index(mut ctx, configured_engine, options)!
store := dolt.new_store(my_embedder, configured_engine, options)!
```

`my_embedder` implements `embeddings.Embedder`. Configure the engine with
appropriate TLS, credentials, timeouts, and resource limits. The adapter does
not own or close the injected engine.

## Behavior and limits

- Default tables are `langchain_dolt_collection` and
  `langchain_dolt_embedding`; identifiers are validated. `database_name` is
  the default collection name, not a database selector.
- `StoreOptions.namespace` selects the collection. Writes are capped at 32
  documents and 4 MiB of encoded input; content and metadata are each limited
  to 64 KiB per document.
- Search supports scalar metadata equality filters, optional metadata/vector
  return, and at most 1,000 results. Search uses squared Euclidean distance
  and reports `1 - distance` as `schema.Document.score`.
- Deletion is collection-scoped and capped at 1,000 IDs. Table setup is
  non-destructive; it does not migrate incompatible schemas.
- Vectors must be finite, nonzero, dimensionally consistent within a write,
  and no larger than 2,000 values. Dolt's index also requires consistent
  dimensions across indexed rows.

Adapter tests use a fake engine and do not require Dolt. A live database is
required to test retrieval end to end; an index is needed for indexed
approximate retrieval.
