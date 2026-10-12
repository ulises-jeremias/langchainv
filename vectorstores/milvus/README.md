# Milvus vector store

The `milvus` package implements the Milvus REST v2 data plane for an existing
collection. It uses an injected `embeddings.Embedder` and `httputil.HTTPClient`,
so tests can exercise the request mapping without a running Milvus server.

The collection schema must have a string primary key (`id` by default), a float
vector field (`vector`), a text field (`page_content`), a JSON metadata field
(`metadata`), and a string namespace field (`namespace`). These field names and
the database, endpoint, token, and metric can be configured with `Options`.
Collection administration is intentionally outside this adapter.

Writes and deletes are limited to 64 and 1,000 records per call. Requests and
responses are capped at 4 MiB, vectors at 65,536 finite values, and searches at
1,000 results. Searches support scalar metadata equality, namespaces, and
COSINE, inner product, or L2 metrics. Minimum-score filtering is available for
COSINE and inner product; L2 distances are not filtered using a minimum score.
The returned score is Milvus's raw metric value: larger is more similar for
COSINE/IP, while smaller is nearer for L2. Set `SearchOptions.include_vectors`
to add each returned float vector to `schema.Document.embedding`; vectors are
omitted by default and validated for shape, size, and finite values. Remote
endpoints must use HTTPS; HTTP is allowed for loopback development instances.

REST endpoints follow Milvus v2: insert, search, and delete entities in an
existing collection. See Milvus's REST references for [insert](https://milvus.io/api-reference/restful/v2.6.x/v2/Vector%20%28v2%29/Insert.md),
[search](https://milvus.io/api-reference/restful/v2.6.x/v2/Vector%20%28v2%29/Search.md),
and [delete](https://milvus.io/api-reference/restful/v2.6.x/v2/Vector%20%28v2%29/Delete.md).
The collection's vector dimension, field types, primary key type, and metric
must match the configured adapter and embedder.

Tests use an offline fake HTTP client and do not contact a Milvus service.
