---
layout: default
title: PostgreSQL pgvector search
permalink: /tutorials/pgvector-vector-search/
---

# PostgreSQL pgvector search

The pgvector adapter uses a caller-owned PostgreSQL engine and embedder. It
does not run DDL from `new_store`. Install the `vector` extension first; then
choose the embedder's dimension and explicitly create the table and index.
See the upstream [pgvector indexing guide](https://github.com/pgvector/pgvector#hnsw)
for supported operators and index build tradeoffs.

## Create a table

Use `initialize_table(mut ctx, engine, options, dimensions)` to issue a
non-destructive `CREATE TABLE IF NOT EXISTS`. The helper validates simple SQL
identifiers and accepts dimensions from 1 to 2,000. It does not inspect or
change an existing table, and it does not install extensions.

## Build the approximate index when ready

The adapter searches with cosine distance. Call
`create_vector_index(mut ctx, engine, options)` separately to create a matching
HNSW index with `vector_cosine_ops`. HNSW can improve query speed at the cost of
approximate recall, longer index builds, and higher memory use. Plan the build
with the database operator before invoking it on a large table.

The helper inspects `pg_indexes`: it returns when the configured name already
has an HNSW cosine definition for the vector column, and reports an error when
the name exists with a different definition. It does not drop or replace any
index. If you need another index method or operator class, provision it with
SQL under your own migration process and choose matching query behavior.

## Use the adapter

After provisioning, call `new_store` with the same table options and embedder.
Writes use parameterized inserts and are limited to 64 documents. Search
supports exact scalar JSONB equality and an optional namespace. Stored vectors
are returned only when `SearchOptions.include_vectors` is enabled.

The package's fake-engine tests make no database calls. For Cloud SQL or
AlloyDB, connection setup and `vector` extension provisioning remain the
application's responsibility; details are in the
[package guide](https://github.com/ulises-jeremias/langchainv/blob/main/vectorstores/pgvector/README.md#cloud-sql-and-alloydb).
