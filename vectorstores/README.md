# Vector stores

`new_in_memory_vector_store(embedder, max_documents)` provides a bounded,
process-local implementation for tests and small workloads. It uses cosine
similarity, accepts an injected `embeddings.Embedder`, supports exact metadata
filters and namespaces, and rejects writes that exceed its configured capacity.
It is not persistent. Search results include their cosine score; stored vectors
are omitted by default and copied into `schema.Document.embedding` when
`SearchOptions.include_vectors` is true. Metadata can also be omitted through
`SearchOptions`.

The in-memory implementation currently supports only cosine distance. It
requires non-empty, finite vectors of consistent dimensions and rejects query
dimension mismatches.

## Return stored vectors

Set `SearchOptions.include_vectors` on `similarity_search` to populate
`schema.Document.embedding`. The default is `false`, so ordinary retrieval
does not return vectors. The [offline example](../examples/vector_return/main.v)
shows the option with the in-memory store; remote stores also support it, but
their returned-vector limits and index requirements vary by backend. See the
[vector return tutorial](../docs/tutorials/returning-vectors.md) and the
adapter-specific guides before enabling it remotely.

The `azureaisearch`, `chroma`, `milvus`, `opensearch`, `qdrant`, `pinecone`,
and `weaviate` subpackages provide bounded REST adapters for existing remote
collections or indexes. Each accepts an injected embedder and HTTP client for
offline tests. The `mariadb` and `pgvector` subpackages use an injected SQL
engine. The `redis` subpackage uses the V standard Redis client with an injected
command interface and a preconfigured Redis Stack HASH index. See package
README files for supported filters, limits, authentication, and server setup.
Remote adapters support `include_vectors` only when their package guide says
the backend returns stored vectors; unsupported adapters reject the option.
