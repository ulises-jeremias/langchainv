# pgvector store

The `pgvector` package uses an injected PostgreSQL `sqldatabase.Engine` and
`embeddings.Embedder`. It works with the existing `pgx` or `postgresql` engine
returned by `sqldatabase.new_driver_engine`; it does not open or close the
connection. The database must have the pgvector extension installed and the
configured table created in advance.

The default table is `langchainv_documents`, with columns `id` (text primary
key), `page_content` (text), `metadata` (JSONB), `namespace` (text), and
`embedding` (pgvector `vector`). For example:

```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE langchainv_documents (
    id text PRIMARY KEY,
    page_content text NOT NULL,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    namespace text NOT NULL DEFAULT '',
    embedding vector(1536) NOT NULL
);

CREATE INDEX langchainv_documents_embedding_hnsw
    ON langchainv_documents USING hnsw (embedding vector_cosine_ops);
```

## Cloud SQL and AlloyDB

This same adapter can use a PostgreSQL-compatible `sqldatabase.Engine` that
connects to Cloud SQL for PostgreSQL or AlloyDB, provided the database has the
`vector` extension enabled and the table follows the schema above. Google
documents `pgvector` support in [Cloud SQL for PostgreSQL](https://docs.cloud.google.com/sql/docs/postgres/generate-manage-vector-embeddings)
and the [AlloyDB vector extension](https://docs.cloud.google.com/alloydb/docs/ai/store-embeddings).

Connection setup, network configuration, and database/index provisioning remain
the application's responsibility; follow the official [Cloud SQL connection
guide](https://cloud.google.com/sql/docs/postgres/connect-overview) or
[AlloyDB connection overview](https://docs.cloud.google.com/alloydb/docs/connection-overview).
This adapter does not invoke Cloud SQL's
`google_ml_integration` or AlloyDB AI embedding functions; provide an
`embeddings.Embedder` and an already-connected SQL engine. It uses pgvector
cosine operators and does not expose provider-specific indexing or query
features.

Choose the vector dimension to match the embedder. Field and table names are
configurable simple SQL identifiers; they are quoted in generated SQL. Writes
use parameterized multi-row inserts, searches use the pgvector cosine-distance
operator, and deletes use parameterized IDs. Scalar metadata equality uses
JSONB key/value matching; namespace matching is exact. Array metadata, arbitrary
filter expressions, schema creation, and vector return are not implemented.

Writes are limited to 64 documents, deletes to 1,000 IDs, searches to 1,000
candidate rows, vectors to 2,000 finite values, and insert parameters to 4 MiB.
The SQL query keeps its returned rows under a 4 MiB response budget, so large
stored documents can reduce the result count. Cosine queries and documents
reject zero vectors. Returned scores are `1 - cosine distance`; minimum-score
filtering happens after PostgreSQL returns the bounded top-k, so fewer than
`limit` results may be returned. See the official
[pgvector README](https://github.com/pgvector/pgvector#querying) for distance
operators, vector dimension limits, and HNSW/IVFFlat indexing.

Tests use a fake SQL engine and do not require PostgreSQL or a live pgvector
extension. CI compiles and tests the adapter with the pinned V compiler.
