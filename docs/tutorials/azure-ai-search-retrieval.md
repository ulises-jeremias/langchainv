---
layout: default
title: Retrieval QA with Azure AI Search
permalink: /tutorials/azure-ai-search-retrieval/
---

# Retrieval QA with Azure AI Search

This opt-in example connects the retrieval QA chain to a persistent Azure AI
Search index and OpenAI embeddings. It sends sample document text to OpenAI for
embedding and completion, writes temporary records to Azure, then attempts to
delete those records before exit. Both services may incur charges.

## Prepare the index

Follow the [Azure AI Search adapter guide](https://github.com/ulises-jeremias/langchainv/blob/main/vectorstores/azureaisearch/README.md)
to create the `knowledge` index. The example uses the default `id`, `content`,
`contentVector`, `metadata`, and `namespace` fields with 1,536-dimensional
cosine vectors. Use an Azure admin key because the example writes and deletes
documents.

## Configure and run

Set these variables in your shell or secret manager:

- `OPENAI_API_KEY` — used for embeddings and chat completion.
- `AZURE_SEARCH_SERVICE` — Azure AI Search service name, without the domain.
- `AZURE_SEARCH_ADMIN_KEY` — admin key for indexing and cleanup.
- `LANGCHAINV_ALLOW_LIVE_EXAMPLES=1` — explicit opt-in to network calls.

From the repository root, run:

```sh
v run examples/azure_retrieval/main.v
```

Without the opt-in flag the program exits before reading credentials or making
network calls. CI removes that flag, so it only compiles the example and checks
the offline path.

## What the example does

1. Uses the OpenAI `text-embedding-3-small` default embedder for the sample
   documents and the query.
2. Writes three temporary documents to the existing Azure index under a
   dedicated namespace.
3. Adapts the store to the common retriever interface and runs a bounded
   retrieval QA chain with the OpenAI chat model.
4. Deletes the generated IDs on normal function exit. If the process is stopped
   abruptly or Azure is unavailable during cleanup, remove records from the
   `langchainv-live-example` namespace manually.

For an offline walkthrough, use the [retrieval QA tutorial](../retrieval-qa/)
and the [offline example](https://github.com/ulises-jeremias/langchainv/blob/main/examples/retrieval_qa/main.v).
