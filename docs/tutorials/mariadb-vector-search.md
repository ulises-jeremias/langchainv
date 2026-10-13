---
layout: default
title: MariaDB vector search
permalink: /tutorials/mariadb-vector-search/
---

# MariaDB vector search

The MariaDB adapter uses an application-owned SQL engine and embedder. It does
not open connections or create schema from its constructor. MariaDB vector
columns require Server 11.7.1 or newer. Review the official [vector table
syntax](https://mariadb.com/docs/server/reference/sql-structure/vectors/create-table-with-vectors)
and [VECTOR type limits](https://mariadb.com/docs/server/reference/sql-structure/vectors/vector).

## Provision in two deliberate steps

First create the table with the dimension used by your embedder. This operation
uses `CREATE TABLE IF NOT EXISTS`; it will not alter an existing table or
reconcile a mismatched schema.

```text
mut ctx := context.background()
options := mariadb.Options{ table: 'knowledge' }
mariadb.initialize_table(mut ctx, engine, options, 1536)!
```

Then, when database capacity allows building the approximate index, invoke:

```text
mariadb.create_vector_index(mut ctx, engine, options)!
```

The index helper inspects `information_schema` and adds an `M=8` cosine vector
index only when its configured index is absent. Index creation can scan rows
and consume substantial database memory and time. MariaDB documents the `M`
parameter range as 3–200; tune the index in a controlled environment if the
fixed default does not fit your workload. The index creation is separate from
table creation and adapter construction so deployments can schedule it
deliberately.

## Use the store

After setup, bind the store to the same embedder and table options. Writes are
parameterized and bounded to 64 documents; similarity search uses cosine
distance and supports a namespace plus scalar JSON metadata equality filters.
Set `SearchOptions.include_vectors` when returned documents should include the
stored embedding.

The deterministic adapter tests use a fake SQL engine. End-to-end retrieval
requires a live MariaDB service and credentials supplied by the application;
routine tests make no live database calls.
