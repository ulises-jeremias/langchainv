---
layout: default
title: Providers and backends
description: Find LangChainV model providers, embedding adapters, and vector store guides.
permalink: /providers/
---

# Providers and backends

This catalog links to the package guide for each implemented adapter. A guide
describes its endpoint, configuration, supported behavior, bounds, and known
gaps. The adapter being listed does not imply full upstream parity; check the
guide and [parity ledger](../reference/) before selecting it.

For the provider-neutral model contract and callbacks that wrap any model, see
the [`llms` guide](https://github.com/ulises-jeremias/langchainv/blob/main/llms/README.md)
and [model callbacks tutorial](../tutorials/model-callbacks/).

## Chat and completion models

| Integration | Package guide | Connection type |
|---|---|---|
| Amazon Bedrock | [Bedrock Converse](https://github.com/ulises-jeremias/langchainv/blob/main/llms/bedrock/README.md) | Managed API with explicit API-key authentication |
| Anthropic | [Anthropic Messages](https://github.com/ulises-jeremias/langchainv/blob/main/llms/anthropic/README.md) | Hosted API |
| Baidu ERNIE / Qianfan | [Qianfan](https://github.com/ulises-jeremias/langchainv/blob/main/llms/ernie/README.md) | Hosted OpenAI-compatible API |
| Cloudflare Workers AI | [Workers AI](https://github.com/ulises-jeremias/langchainv/blob/main/llms/cloudflare/README.md) | Hosted OpenAI-compatible API |
| Cohere | [Cohere Chat](https://github.com/ulises-jeremias/langchainv/blob/main/llms/cohere/README.md) | Hosted API |
| Google AI | [Gemini](https://github.com/ulises-jeremias/langchainv/blob/main/llms/googleai/README.md) | Hosted Gemini API |
| Google Cloud | [Vertex AI](https://github.com/ulises-jeremias/langchainv/blob/main/llms/vertex/README.md) | Vertex AI REST API with an explicit OAuth token |
| Hugging Face | [Inference Providers chat](https://github.com/ulises-jeremias/langchainv/blob/main/llms/huggingface/README.md) | Hosted OpenAI-compatible router |
| IBM | [watsonx.ai](https://github.com/ulises-jeremias/langchainv/blob/main/llms/watsonx/README.md) | Hosted text generation API |
| llamafile | [llamafile](https://github.com/ulises-jeremias/langchainv/blob/main/llms/llamafile/README.md) | Local OpenAI-compatible server |
| Local executable | [Local model process](https://github.com/ulises-jeremias/langchainv/blob/main/llms/local/README.md) | Explicitly configured local process |
| Maritaca | [Maritaca](https://github.com/ulises-jeremias/langchainv/blob/main/llms/maritaca/README.md) | Hosted OpenAI-compatible API |
| Mistral | [Mistral](https://github.com/ulises-jeremias/langchainv/blob/main/llms/mistral/README.md) | Hosted Chat Completions API |
| Ollama | [Ollama](https://github.com/ulises-jeremias/langchainv/blob/main/llms/ollama/README.md) | Local server |
| OpenAI | [Chat Completions](https://github.com/ulises-jeremias/langchainv/blob/main/llms/openai/README.md) | Hosted API or compatible endpoint |

## Embeddings

| Integration | Package guide |
|---|---|
| Amazon Bedrock | [Bedrock embeddings](https://github.com/ulises-jeremias/langchainv/blob/main/embeddings/bedrock/README.md) |
| Google AI | [Google AI embeddings](https://github.com/ulises-jeremias/langchainv/blob/main/embeddings/googleai/README.md) |
| Hugging Face | [Hugging Face feature extraction](https://github.com/ulises-jeremias/langchainv/blob/main/embeddings/huggingface/README.md) |
| Jina AI | [Jina embeddings](https://github.com/ulises-jeremias/langchainv/blob/main/embeddings/jina/README.md) |
| Ollama | [Ollama embeddings](https://github.com/ulises-jeremias/langchainv/blob/main/embeddings/ollama/README.md) |
| OpenAI | [OpenAI embeddings](https://github.com/ulises-jeremias/langchainv/blob/main/embeddings/openai/README.md) |
| Voyage AI | [Voyage AI embeddings](https://github.com/ulises-jeremias/langchainv/blob/main/embeddings/voyageai/README.md) |

## Vector stores

| Backend | Package guide |
|---|---|
| Azure AI Search | [Azure AI Search](https://github.com/ulises-jeremias/langchainv/blob/main/vectorstores/azureaisearch/README.md) |
| Chroma | [Chroma](https://github.com/ulises-jeremias/langchainv/blob/main/vectorstores/chroma/README.md) |
| Milvus | [Milvus](https://github.com/ulises-jeremias/langchainv/blob/main/vectorstores/milvus/README.md) |
| OpenSearch | [OpenSearch](https://github.com/ulises-jeremias/langchainv/blob/main/vectorstores/opensearch/README.md) |
| PostgreSQL with pgvector | [pgvector](https://github.com/ulises-jeremias/langchainv/blob/main/vectorstores/pgvector/README.md) |
| Pinecone | [Pinecone](https://github.com/ulises-jeremias/langchainv/blob/main/vectorstores/pinecone/README.md) |
| Redis Stack | [Redis](https://github.com/ulises-jeremias/langchainv/blob/main/vectorstores/redis/README.md) |
| Qdrant | [Qdrant](https://github.com/ulises-jeremias/langchainv/blob/main/vectorstores/qdrant/README.md) |
| Weaviate | [Weaviate](https://github.com/ulises-jeremias/langchainv/blob/main/vectorstores/weaviate/README.md) |

## Before connecting a service

1. Read the adapter guide and check whether its required service, credentials,
   model, index, or collection already exists.
2. Confirm that the exact options you need are listed as supported. Unsupported
   options can return errors rather than being ignored.
3. Keep credentials out of source control and follow the provider's current
   pricing and data-handling terms.
4. Use injected transports and deterministic fixtures for application tests.
   The repository's CI does not call billable providers or remote databases.

The [component map](../components/) covers framework packages. The
[tutorial track](../tutorials/) starts with offline examples before introducing
provider configuration.
