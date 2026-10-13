---
layout: default
title: Dolt vector search
permalink: /tutorials/dolt-vector-search/
---

# Dolt vector search

Use the Dolt adapter when the application already has a Dolt database and a
configured MySQL-compatible `sqldatabase.Engine`. The adapter does not create
connections or run DDL in its constructor. Its tests use a fake engine, so they
do not require a Dolt server.

## Provision deliberately

The [adapter guide](https://github.com/ulises-jeremias/langchainv/blob/main/vectorstores/dolt/README.md)
shows the setup calls. `initialize_tables` creates two tables if absent and
does not migrate existing schemas. `create_vector_index` is a separate call:
Dolt's JSON vector index is alpha, and building it may consume significant
time and resources. Plan index creation against a suitable database rather
than doing it automatically during application startup.

The index expects JSON arrays with consistent dimensions. Dolt uses the
approximate vector index when `VEC_DISTANCE` is directly in `ORDER BY`; the
adapter keeps that query shape. Approximate search can omit some nearest
neighbors, so validate recall with the data and Dolt version you deploy.

## Retrieve and scope data

Create a store with your application embedder and injected engine, then call
`similarity_search(mut ctx, query, limit, options)`. `StoreOptions.namespace`
selects the collection for writes and deletes; `SearchOptions.namespace` scopes
queries. Search accepts scalar JSON metadata equality filters and uses squared
Euclidean distance. Its score is `1 - distance`. Build the vector index for
approximate indexed retrieval and verify exact-scan behavior on your Dolt
version before deciding to run without one.

Writes accept at most 32 documents and 4 MiB per call. Search and delete each
cap their requested rows/IDs at 1,000. See the guide for field-size and vector
dimension limits. The caller owns the engine and must configure database TLS,
credentials, query timeouts, and resource constraints.
