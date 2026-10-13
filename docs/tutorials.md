---
layout: default
title: Tutorials
permalink: /tutorials/
---

# Tutorials

Work through these recipes in order. Each section links to the package guide that documents its current API and limits. The repository's [examples directory](https://github.com/ulises-jeremias/langchainv/tree/main/examples) contains complete, compile-checked programs.

## Learning path

1. Start with the runnable [text splitter example](https://github.com/ulises-jeremias/langchainv/blob/main/examples/text_splitter/main.v) and learn [recursive and Markdown chunking](https://github.com/ulises-jeremias/langchainv/blob/main/textsplitter/README.md).
2. Follow the [prompt templates tutorial](prompt-templates/), then parse responses with [output parsers](https://github.com/ulises-jeremias/langchainv/blob/main/outputparser/README.md).
3. Run the [mock model tutorial](offline-model-tests/) to test model-dependent code without a provider.
4. Make one [live chat request](first-chat/) with an explicit provider adapter after reviewing key handling and provider costs.
5. Add [model lifecycle callbacks](model-callbacks/) through a provider-neutral middleware wrapper.
6. Review the [embedding guides](https://github.com/ulises-jeremias/langchainv/tree/main/embeddings) and [vector store adapters](https://github.com/ulises-jeremias/langchainv/tree/main/vectorstores) before choosing a retrieval backend.
7. Run the [offline retrieval QA tutorial](retrieval-qa/) before configuring a remote vector store.
8. Try [retrieval QA with Azure AI Search](azure-ai-search-retrieval/) after reviewing its live-service costs and credentials.
9. Compose model operations with [chains](https://github.com/ulises-jeremias/langchainv/blob/main/chains/README.md), add [memory](https://github.com/ulises-jeremias/langchainv/blob/main/memory/README.md), and expose selected [tools](https://github.com/ulises-jeremias/langchainv/tree/main/tools).
10. Try [bounded concurrent document mapping](concurrent-document-mapping/) with an offline completion model before raising concurrency on a live provider.
11. Run the [offline conversation memory tutorial](conversation-memory/) to see how a chain carries history between turns.
12. Run the [offline tool-calling tutorial](tool-calling-agent/) before connecting live services.
13. Initialize a [conversational ReAct agent with memory](conversational-agent-memory/) and inspect how `chains.call` moves prior turns through the executor.
14. Read [security guidance](https://github.com/ulises-jeremias/langchainv/blob/main/SECURITY.md), [contribution and validation](https://github.com/ulises-jeremias/langchainv/blob/main/CONTRIBUTING.md), and the [parity ledger](../reference/) before production use.
15. [Return stored vectors](returning-vectors/) when you need the original embeddings for inspection or downstream calculations.
16. Persist bounded remote conversation history with the [Zep chat history tutorial](zep-chat-history/); the example reads by default and requires a second opt-in before writing.
17. Connect an existing Dolt database with [Dolt vector search](dolt-vector-search/) after reviewing the explicit index-build cost and approximate-recall behavior.
18. Set up a Redis Stack HASH vector index with the [Redis vector search guide](redis-vector-search/) before binding the adapter to it.
19. Provision a cosine k-NN mapping with the [OpenSearch vector search guide](opensearch-vector-search/) before indexing documents.

## Recipes by task

| Task | Start here | Notes |
|---|---|---|
| Make a first chat request | [First chat tutorial](first-chat/) | Sends a billable live request; keep the API key in the environment. |
| Test model-dependent code offline | [Mock model tutorial](offline-model-tests/) | No API key or network calls; adapter HTTP behavior should use an injected fake transport. |
| Build retrieval QA | [Retrieval tutorial](retrieval-qa/) | Uses in-memory storage and deliberately simple fakes; no semantic embeddings or external services. |
| Inspect search embeddings | [Return stored vectors](returning-vectors/) | Shows opt-in result vectors with an offline in-memory store; remote adapters have backend-specific limits. |
| Run retrieval QA against Azure AI Search | [Azure retrieval tutorial](azure-ai-search-retrieval/) | Explicit live opt-in; sends text to OpenAI and Azure and can incur usage charges. |
| Map documents concurrently | [Concurrent mapping tutorial](concurrent-document-mapping/) | Uses a stateless offline model; the chain defaults to one worker and accepts at most five. |
| Carry conversation history | [Conversation memory](conversation-memory/) | Uses an in-memory buffer and a deterministic completion fake; history is process-local. |
| Persist chat history remotely | [Zep chat history](zep-chat-history/) | Reads one Zep API v2 session by default; appending requires another explicit opt-in. |
| Retrieve from Dolt | [Dolt vector search](dolt-vector-search/) | Requires an injected MySQL-compatible engine; table initialization and alpha vector-index creation are explicit operations. |
| Retrieve from Redis Stack | [Redis vector search](redis-vector-search/) | Explicit FLAT/COSINE index creation scans matching HASH records and consumes Redis server memory. |
| Retrieve from OpenSearch | [OpenSearch vector search](opensearch-vector-search/) | Explicit cosine k-NN index creation; choose a matching embedding dimension before provisioning. |
| Persist conversation history | [Memory backend guide](https://github.com/ulises-jeremias/langchainv/blob/main/memory/README.md) | SQLite and bounded PostgreSQL history are session-isolated; PostgreSQL requires an application-provided engine. |
| Dispatch model tool calls | [Tool-calling agent](tool-calling-agent/) | Uses the bounded calculator and a staged fake model; no provider requests. |
| Keep history in a tool-using conversation | [Conversational ReAct agent](conversational-agent-memory/) | Uses executor memory and an offline model; swap in a provider only after reviewing its limits. |
| Split plain text or Markdown | [textsplitter](https://github.com/ulises-jeremias/langchainv/blob/main/textsplitter/README.md) | Token chunking uses an injected tokenizer; no tokenizer data downloads. |
| Generate chat completions | [OpenAI](https://github.com/ulises-jeremias/langchainv/blob/main/llms/openai/README.md), [Ollama](https://github.com/ulises-jeremias/langchainv/blob/main/llms/ollama/README.md), or another provider README | Provider options and streaming support differ. |
| Embed documents | [embeddings](https://github.com/ulises-jeremias/langchainv/tree/main/embeddings) | Select a provider and inspect its batch and input limits. |
| Retrieve from a vector database | [vectorstores](https://github.com/ulises-jeremias/langchainv/tree/main/vectorstores) | Several adapters require an existing index or collection. |
| Use Cloud SQL for PostgreSQL or AlloyDB for vectors | [pgvector adapter guide](https://github.com/ulises-jeremias/langchainv/blob/main/vectorstores/pgvector/README.md#cloud-sql-and-alloydb) | Supply a compatible PostgreSQL engine and provision the vector schema; Cloud-specific connection, auth, and embedding features are outside the adapter. |
| Load files | [documentloaders](https://github.com/ulises-jeremias/langchainv/blob/main/documentloaders/README.md) | Limits and external runtime requirements are documented per loader. |
| Add SQL tools | [SQL database tools](https://github.com/ulises-jeremias/langchainv/blob/main/tools/sqldatabase/README.md) | Use parameterized queries and least-privilege credentials. |

Tutorials are being expanded alongside API coverage. A package marked partial in the parity ledger may have important unsupported behavior; treat its README as the precise contract.
