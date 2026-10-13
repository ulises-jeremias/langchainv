# SQL database tool

`SQLDatabase` exposes a bounded table inventory, schema and sample view, and
query methods over an injected SQL engine or V's standard database driver. It
is useful for trusted application workflows and agents whose SQL access is
limited separately by the database account.

## Choose a connection

Use `new_sql_database` to let this package open and own a SQLite, PostgreSQL,
or MySQL driver:

```v
import db
import ulises_jeremias.langchainv.tools.sqldatabase

fn main() {
	mut database := sqldatabase.new_sql_database(db.DriverConfig{
		kind: .sqlite
		path: ':memory:'
	}, ['internal_jobs'], sqldatabase.Options{}) or { panic(err) }
	defer {
		database.close() or {}
	}
	println(database.table_names())
}
```

PostgreSQL and MySQL use V's compile-time database drivers; build flags and
driver availability depend on the compiler and platform. `new_database` accepts
an implementation of `Engine`, which lets an application supply its own
connection pool or a deterministic test double. It takes ownership of the
engine and closes it if initialization fails. Call `database.close()` when the
database object is no longer needed; repeated calls are safe.

## Inspect tables and run queries

`table_names()` returns the inventory after `ignored_tables` are filtered out.
`table_info(mut ctx, tables)` returns schemas and bounded sample rows. An empty
table list selects all visible tables. Set `Options.sample_rows` to `0` to omit
sample data.

`query(mut ctx, statement)` runs a statement and formats its result as
tab-separated text. `query_with_params(mut ctx, statement, params)` passes
values separately to the driver. Use the parameterized method for values; do
not construct SQL by interpolating untrusted values. Placeholder syntax is
dialect-specific (`?` for SQLite/MySQL and `$1`, `$2`, etc. for PostgreSQL).

The query method can execute any statement accepted by the engine. It does not
parse SQL into read-only operations or enforce row-level authorization. Give it
a dedicated least-privilege account. If user input can influence a query,
validate the operation and permitted tables in the application before calling
this package. Ignoring a table hides it from the schema inventory but does not
prevent a caller from querying it by name.

## Configure limits

`Options` bounds work exposed in formatted results:

| Option | Default | Maximum |
|---|---:|---:|
| `sample_rows` | 3 | 32 |
| `max_result_rows` | 256 | 4,096 |
| `max_output_bytes` | 65,536 | 1 MiB |
| `max_query_bytes` | 65,536 | 1 MiB |
| `max_tables` | 256 | 4,096 |

Set limits explicitly for the data and workload. The driver materializes query
rows before the output row and byte limits are checked; those limits do not
bound database execution time or peak driver memory. Context cancellation is
checked before and after driver calls but cannot interrupt a call already in
progress. Apply database-side statement timeouts, quotas, and read-only roles
when required.

## Test without a server

CI uses SQLite in-memory fixtures and an injected engine fake. Tests do not
require production credentials or contact a hosted database. See
[`database_test.v`](database_test.v) for query, parameter, schema, table
filtering, and limit examples.
