---
layout: default
title: Tutorials
permalink: /tutorials/
---

# Tutorials

Work through these recipes in order. Each section links to the package guide that documents its current API and limits. The repository's [examples directory](https://github.com/ulises-jeremias/langchainv/tree/main/examples) contains complete, compile-checked programs.

## Learning path

1. **Split source text** — use the runnable [text splitter example](https://github.com/ulises-jeremias/langchainv/blob/main/examples/text_splitter/main.v) and learn [recursive and Markdown chunking](https://github.com/ulises-jeremias/langchainv/blob/main/textsplitter/README.md).
2. **Shape model input** — follow the complete [prompt templates tutorial](prompt-templates/) to build string and role-tagged prompts; parse responses with [output parsers](https://github.com/ulises-jeremias/langchainv/blob/main/outputparser/README.md).
3. **Test model code offline** — run the [mock model tutorial](offline-model-tests/) before connecting a live provider.
4. **Call a model safely** — start with the [OpenAI Chat Completions adapter](https://github.com/ulises-jeremias/langchainv/blob/main/llms/openai/README.md). It supports injected transports for offline tests; keep credentials outside source control.
5. **Add embeddings and retrieval** — review the [embedding package guides](https://github.com/ulises-jeremias/langchainv/tree/main/embeddings) and [vector store adapters](https://github.com/ulises-jeremias/langchainv/tree/main/vectorstores). Configure and provision external services separately.
6. **Compose application behavior** — combine prompt/model operations with [chains](https://github.com/ulises-jeremias/langchainv/blob/main/chains/README.md), add [memory](https://github.com/ulises-jeremias/langchainv/blob/main/memory/README.md), then expose bounded [tools](https://github.com/ulises-jeremias/langchainv/tree/main/tools).
7. **Build an agent deliberately** — study [agent behavior and executor bounds](https://github.com/ulises-jeremias/langchainv/blob/main/agents/README.md) and use deterministic tool/model fakes before connecting live services.
8. **Prepare for production** — read [security guidance](https://github.com/ulises-jeremias/langchainv/blob/main/SECURITY.md), [contribution and validation](https://github.com/ulises-jeremias/langchainv/blob/main/CONTRIBUTING.md), and the [parity ledger](../reference/).

## Recipes by task

| Task | Start here | Notes |
|---|---|---|
| Test model-dependent code offline | [Mock model tutorial](offline-model-tests/) | No API key or network calls; adapter HTTP behavior should use an injected fake transport. |
| Split plain text or Markdown | [textsplitter](https://github.com/ulises-jeremias/langchainv/blob/main/textsplitter/README.md) | Token chunking uses an injected tokenizer; no tokenizer data downloads. |
| Generate chat completions | [OpenAI](https://github.com/ulises-jeremias/langchainv/blob/main/llms/openai/README.md), [Ollama](https://github.com/ulises-jeremias/langchainv/blob/main/llms/ollama/README.md), or another provider README | Provider options and streaming support differ. |
| Embed documents | [embeddings](https://github.com/ulises-jeremias/langchainv/tree/main/embeddings) | Select a provider and inspect its batch and input limits. |
| Retrieve from a vector database | [vectorstores](https://github.com/ulises-jeremias/langchainv/tree/main/vectorstores) | Several adapters require an existing index or collection. |
| Load files | [documentloaders](https://github.com/ulises-jeremias/langchainv/blob/main/documentloaders/README.md) | Limits and external runtime requirements are documented per loader. |
| Add SQL tools | [SQL database tools](https://github.com/ulises-jeremias/langchainv/blob/main/tools/sqldatabase/README.md) | Use parameterized queries and least-privilege credentials. |

Tutorials are being expanded alongside API coverage. A package marked partial in the parity ledger may have important unsupported behavior; treat its README as the precise contract.
