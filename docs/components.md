---
layout: default
title: Component map
permalink: /components/
---

# Component map

Use this map to find the package guide. Package READMEs describe constructors, supported options, resource limits, and known gaps.

| Area | Packages | Purpose |
|---|---|---|
| Contracts and schemas | [`schema`](https://github.com/ulises-jeremias/langchainv/blob/main/schema/README.md), [`jsonschema`](https://github.com/ulises-jeremias/langchainv/blob/main/jsonschema/README.md) | Shared documents/messages and bounded JSON schema validation. |
| Model calls | [`llms`](https://github.com/ulises-jeremias/langchainv/blob/main/llms/README.md) and provider guides | Common model contracts with isolated provider adapters. |
| Embeddings | [`embeddings`](https://github.com/ulises-jeremias/langchainv/tree/main/embeddings) and provider guides | Vectorization, batching, and vector math. |
| Prompts and parsing | [`prompts`](https://github.com/ulises-jeremias/langchainv/blob/main/prompts/README.md), [`outputparser`](https://github.com/ulises-jeremias/langchainv/blob/main/outputparser/README.md) | Prompt construction and typed response parsing. |
| Composition | [`chains`](https://github.com/ulises-jeremias/langchainv/blob/main/chains/README.md), [`agents`](https://github.com/ulises-jeremias/langchainv/blob/main/agents/README.md) | Multi-step calls, retrieval QA, tool dispatch, and bounded agent loops. |
| State | [`memory`](https://github.com/ulises-jeremias/langchainv/blob/main/memory/README.md) | Conversation history and bounded buffers. |
| Tools | [`tools`](https://github.com/ulises-jeremias/langchainv/tree/main/tools) | Search, SQL, and external tool adapters. |
| Retrieval | [`textsplitter`](https://github.com/ulises-jeremias/langchainv/blob/main/textsplitter/README.md), [`vectorstores`](https://github.com/ulises-jeremias/langchainv/tree/main/vectorstores) | Document chunking, storage, and retriever adapters. |
| Input and transport | [`documentloaders`](https://github.com/ulises-jeremias/langchainv/blob/main/documentloaders/README.md), [`httputil`](https://github.com/ulises-jeremias/langchainv/blob/main/httputil/README.md) | Bounded file loading and HTTP transport behavior. |
| Observability and testing | [`callbacks`](https://github.com/ulises-jeremias/langchainv/blob/main/callbacks/README.md), [`testing/llmtest`](https://github.com/ulises-jeremias/langchainv/tree/main/testing/llmtest) | Lifecycle events, streaming helpers, and opt-in model checks. |

## Provider and backend catalog

- [LLM providers](https://github.com/ulises-jeremias/langchainv/tree/main/llms) · [Embedding providers](https://github.com/ulises-jeremias/langchainv/tree/main/embeddings) · [Vector stores](https://github.com/ulises-jeremias/langchainv/tree/main/vectorstores)
- [Complete API and parity status](../reference/)
