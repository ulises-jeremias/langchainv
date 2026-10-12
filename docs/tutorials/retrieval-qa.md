---
layout: default
title: Build a retrieval QA flow
permalink: /tutorials/retrieval-qa/
---

# Build a retrieval QA flow

Retrieval-augmented question answering (RAG) has two distinct steps: retrieve
relevant documents, then give bounded context to a model. This tutorial uses a
small in-memory store and deterministic fakes so the full flow runs offline.

## Run the example

From the repository root:

```sh
v run examples/retrieval_qa/main.v
```

The example creates three documents, embeds them with a tiny keyword-based
fixture, retrieves one document for a question, and passes its text to a fake
completion model through `RetrievalQAChain`. It requires no credentials and
makes no network calls. The fixture embedding function is only for explaining
data flow; use a real embedding model for semantic retrieval.

## Understand the data flow

1. `Embedder` maps both document text and the question into the same vector
   space. A production embedder should use the same provider and model for both.
2. `InMemoryVectorStore` stores documents and vectors up to its configured
   capacity. It is process-local and does not persist data.
3. `to_retriever` adapts the store to the shared retriever contract.
4. `new_retrieval_qa_chain` joins retrieved text into the `{context}` prompt
   variable and sends the bounded prompt to a completion model.

The chain exposes options for retrieval count, document count, context bytes,
prompt bytes, and optional source-document results. Remote vector stores have
their own provisioning and filtering requirements; see the [vector store
guides](https://github.com/ulises-jeremias/langchainv/tree/main/vectorstores).

## Replace the fixtures

Replace `DemoEmbedder` with an adapter that implements
`embeddings.Embedder`, and replace `DemoCompletionModel` with a provider
implementing `llms.CompletionModel`. Keep the prompt explicit about using only
retrieved context, configure the chain's limits for your workload, and test
provider adapters offline with injected HTTP transports.

The in-memory store uses cosine similarity and exact metadata filters. It is a
small local backend, not a substitute for persistent or distributed storage.

## Next

- Test provider-neutral model code with the [offline mock model tutorial](../offline-model-tests/).
- Compare backend limits in the [parity reference]({{ '/reference/' | relative_url }}).
