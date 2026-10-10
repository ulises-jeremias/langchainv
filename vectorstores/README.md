# Vector stores

`new_in_memory_vector_store(embedder, max_documents)` provides a bounded,
process-local implementation for tests and small workloads. It uses cosine
similarity, accepts an injected `embeddings.Embedder`, supports exact metadata
filters and namespaces, and rejects writes that exceed its configured capacity.
It is not persistent and does not return stored vectors. Returned documents
include their cosine score; metadata can be omitted through `SearchOptions`.

The in-memory implementation currently supports only cosine distance. It
requires non-empty, finite vectors of consistent dimensions and rejects query
dimension mismatches.
