---
layout: default
title: Return stored vectors
permalink: /tutorials/returning-vectors/
---

# Return stored vectors

Vector stores omit embeddings from search results by default. This keeps normal
retrieval responses smaller. Set `SearchOptions.include_vectors` to copy each
matched embedding into `schema.Document.embedding` when you need to inspect,
reuse, or compare the vectors.

## Run the offline example

The example uses an in-memory store and a deterministic fake embedder, so it
needs no API key, external service, or network connection:

```sh
v run examples/vector_return/main.v
```

It prints each matching document and its returned vector. Remove
`include_vectors: true` from the search options to see the default behavior:
the result documents have empty `embedding` fields while their text and scores
remain available.

## Remote indexes

Remote adapters also support `include_vectors`, subject to their package
limits. A service must return its vector field; for Azure AI Search, mark the
configured vector field as `retrievable` in the index. Read the relevant
[adapter guide](https://github.com/ulises-jeremias/langchainv/tree/main/vectorstores)
for dimension, payload-size, and response-shape requirements before enabling
the option on a remote backend.

The common options and in-memory store are documented in the
[vector store guide](https://github.com/ulises-jeremias/langchainv/blob/main/vectorstores/README.md).
