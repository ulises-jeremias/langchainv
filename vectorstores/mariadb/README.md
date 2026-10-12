# MariaDB vector store

The `mariadb` package uses an injected MariaDB `sqldatabase.Engine` and
`embeddings.Embedder`. It accepts the `mysql` dialect from
`sqldatabase.new_driver_engine`; it does not open or close the connection.
The server must support vectors (MariaDB Server 11.7.1 or newer) and the
configured table must already exist.

The default table is `langchainv_documents`, with `id` (string primary key),
`page_content` (text), `metadata` (JSON), `namespace` (string), and `embedding`
(`VECTOR`). Choose the vector dimension to match the embedder. For example:

```sql
CREATE TABLE langchainv_documents (
    id VARCHAR(36) PRIMARY KEY,
    page_content LONGTEXT NOT NULL,
    metadata JSON NOT NULL,
    namespace TEXT NOT NULL,
    embedding VECTOR(1536) NOT NULL,
    VECTOR INDEX (embedding) DISTANCE=cosine
);
```

Writes use parameterized multi-row inserts and `VEC_FromText`; searches use
`VEC_DISTANCE_COSINE`; deletes use parameterized IDs. Metadata equality filters
support scalar JSON values and namespaces use exact matching. Field and table
names are configurable simple identifiers and quoted with MariaDB identifier
quotes. Array metadata, arbitrary filter expressions, schema creation, and
vector return are unsupported.

Writes are limited to 64 documents, deletes to 1,000 IDs, searches to 1,000
candidate rows, vectors to 2,000 finite values, and insert parameters to 4 MiB.
The search query limits returned rows to a 4 MiB response budget, so large
stored documents can reduce the result count. Cosine queries and documents
reject zero vectors. Returned scores are `1 - cosine distance`; minimum-score
filtering happens after MariaDB returns the bounded top-k, so fewer than
`limit` results may be returned. The implementation uses the
[MariaDB vector overview](https://mariadb.com/docs/server/reference/sql-structure/vectors/vector-overview),
[VECTOR data type](https://mariadb.com/docs/server/reference/sql-structure/vectors/vector),
and [cosine distance function](https://mariadb.com/docs/server/reference/sql-functions/vector-functions/vec_distance_cosine).

Tests use a fake SQL engine and do not require a MariaDB server. Hosted CI
compiles and tests the adapter with the pinned V compiler.
