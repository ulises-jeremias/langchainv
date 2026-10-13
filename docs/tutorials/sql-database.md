---
layout: default
title: Query a SQL database safely
permalink: /tutorials/sql-database/
---

# Query a SQL database safely

This offline example creates an in-memory SQLite database, exposes its schema,
and binds a query value separately from the SQL text. It needs no credentials,
network access, or database server.

## Run the example

From the repository root:

```sh
v run examples/sql_database/main.v
```

The program lists the visible `customers` table, prints its schema and bounded
sample, then queries one customer with a bound parameter. The `internal_notes`
table is hidden from `table_names()` and `table_info()`, but this is a schema
display filter, not an access control: SQL passed to `query()` can still name
it. Use database permissions and application authorization to control access.

## Apply the pattern

Create tables before constructing `SQLDatabase`; its visible table inventory is
captured at initialization. `query_with_params()` accepts string parameters and
uses the driver’s dialect-specific placeholders (`?` for SQLite/MySQL and
`$1`, `$2`, etc. for PostgreSQL). Bind values instead of interpolating them
into SQL. The query helper can execute any statement accepted by the database,
so use a least-privilege account when connecting to a persistent database.

Read the [SQL database package guide](https://github.com/ulises-jeremias/langchainv/blob/main/tools/sqldatabase/README.md)
for driver setup, ownership, result limits, and cancellation boundaries. See
the [production guide](../../production/) for tool authorization and deployment
considerations.
