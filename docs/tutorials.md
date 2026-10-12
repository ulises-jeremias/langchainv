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
4. Add [model lifecycle callbacks](model-callbacks/) through a provider-neutral middleware wrapper.
5. Call a live model through an explicit adapter such as [OpenAI Chat Completions](https://github.com/ulises-jeremias/langchainv/blob/main/llms/openai/README.md). Keep credentials outside source control.
6. Review the [embedding guides](https://github.com/ulises-jeremias/langchainv/tree/main/embeddings) and [vector store adapters](https://github.com/ulises-jeremias/langchainv/tree/main/vectorstores) before choosing a retrieval backend.
7. Run the [offline retrieval QA tutorial](retrieval-qa/) before configuring a remote vector store.
8. Compose model operations with [chains](https://github.com/ulises-jeremias/langchainv/blob/main/chains/README.md), add [memory](https://github.com/ulises-jeremias/langchainv/blob/main/memory/README.md), and expose selected [tools](https://github.com/ulises-jeremias/langchainv/tree/main/tools).
9. Run the [offline conversation memory tutorial](conversation-memory/) to see how a chain carries history between turns.
10. Run the [offline tool-calling tutorial](tool-calling-agent/) before connecting live services.
11. Read [security guidance](https://github.com/ulises-jeremias/langchainv/blob/main/SECURITY.md), [contribution and validation](https://github.com/ulises-jeremias/langchainv/blob/main/CONTRIBUTING.md), and the [parity ledger](../reference/) before production use.

## Recipes by task

| Task | Start here | Notes |
|---|---|---|
| Test model-dependent code offline | [Mock model tutorial](offline-model-tests/) | No API key or network calls; adapter HTTP behavior should use an injected fake transport. |
| Build retrieval QA | [Retrieval tutorial](retrieval-qa/) | Uses in-memory storage and deliberately simple fakes; no semantic embeddings or external services. |
| Carry conversation history | [Conversation memory](conversation-memory/) | Uses an in-memory buffer and a deterministic completion fake; history is process-local. |
| Dispatch model tool calls | [Tool-calling agent](tool-calling-agent/) | Uses the bounded calculator and a staged fake model; no provider requests. |
| Split plain text or Markdown | [textsplitter](https://github.com/ulises-jeremias/langchainv/blob/main/textsplitter/README.md) | Token chunking uses an injected tokenizer; no tokenizer data downloads. |
| Generate chat completions | [OpenAI](https://github.com/ulises-jeremias/langchainv/blob/main/llms/openai/README.md), [Ollama](https://github.com/ulises-jeremias/langchainv/blob/main/llms/ollama/README.md), or another provider README | Provider options and streaming support differ. |
| Embed documents | [embeddings](https://github.com/ulises-jeremias/langchainv/tree/main/embeddings) | Select a provider and inspect its batch and input limits. |
| Retrieve from a vector database | [vectorstores](https://github.com/ulises-jeremias/langchainv/tree/main/vectorstores) | Several adapters require an existing index or collection. |
| Load files | [documentloaders](https://github.com/ulises-jeremias/langchainv/blob/main/documentloaders/README.md) | Limits and external runtime requirements are documented per loader. |
| Add SQL tools | [SQL database tools](https://github.com/ulises-jeremias/langchainv/blob/main/tools/sqldatabase/README.md) | Use parameterized queries and least-privilege credentials. |

Tutorials are being expanded alongside API coverage. A package marked partial in the parity ledger may have important unsupported behavior; treat its README as the precise contract.
