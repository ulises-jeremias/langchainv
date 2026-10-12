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

The `azureaisearch`, `chroma`, `milvus`, `opensearch`, `qdrant`, `pinecone`,
and `weaviate` subpackages provide bounded REST adapters for existing remote
collections or indexes. Each accepts an injected embedder and HTTP client for
offline tests. The `mariadb` and `pgvector` subpackages use an injected SQL
engine. The `redis` subpackage uses the V standard Redis client with an injected
command interface and a preconfigured Redis Stack HASH index. See package
README files for supported filters, limits, authentication, and server setup.
Remote adapters currently reject `include_vectors`; see each package guide for
the supported result fields.
