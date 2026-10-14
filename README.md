<div align="center">

# LangChainV

**Build composable LLM applications in [V](https://vlang.io).** Chains, agents,
retrievers, tools, memory, and vector search behind small, provider-neutral
interfaces with bounded, testable adapters.

[Documentation](https://ulises-jeremias.github.io/langchainv/) |
[Get started](https://ulises-jeremias.github.io/langchainv/getting-started/) |
[Tutorials](https://ulises-jeremias.github.io/langchainv/tutorials/) |
[Providers](docs/providers.md) |
[Parity matrix](docs/LANGCHAINGO_PARITY.md) |
[Examples](examples/) |
[Contributing](CONTRIBUTING.md)

[![CI](https://github.com/ulises-jeremias/langchainv/actions/workflows/ci.yml/badge.svg)](https://github.com/ulises-jeremias/langchainv/actions/workflows/ci.yml)
[![Documentation](https://github.com/ulises-jeremias/langchainv/actions/workflows/pages.yml/badge.svg)](https://github.com/ulises-jeremias/langchainv/actions/workflows/pages.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![V](https://img.shields.io/badge/V-0.5.2%2B-5d87bf?logo=v&logoColor=white)
![Dependencies](https://img.shields.io/badge/core%20dependencies-none-success)

</div>

LangChainV tracks feature parity with the public
[LangChainGo](https://github.com/tmc/langchaingo) API while staying V-native:
sum-type messages, result-based errors, explicit options, context
cancellation, and resource limits on every network, file, and process
boundary. Coverage is tracked honestly in the
[parity matrix](docs/LANGCHAINGO_PARITY.md). An adapter is supported only
within the scope documented there.

## Quick start

Install the module:

```sh
v install ulises-jeremias.langchainv
```

Run an offline example. No API key and no network are needed:

```sh
git clone https://github.com/ulises-jeremias/langchainv.git
cd langchainv
v run examples/text_splitter/main.v
```

Split text in your own program:

```v
module main

import ulises_jeremias.langchainv.textsplitter

fn main() {
	text := 'First paragraph.\n\nSecond paragraph with more detail.'
	splitter := textsplitter.new_recursive_character_text_splitter(
		chunk_size:    32
		chunk_overlap: 6
	) or { panic(err) }
	for chunk in splitter.split_text(text) or { panic(err) } {
		println(chunk)
	}
}
```

Ready for a live model call? Follow the
[first chat tutorial](https://ulises-jeremias.github.io/langchainv/tutorials/first-chat/)
(OpenAI key required), or browse the
[tutorials](https://ulises-jeremias.github.io/langchainv/tutorials/) for
retrieval QA, tool-calling agents, memory, and provider recipes.

## What you get

| Capability | Packages | Highlights |
|---|---|---|
| Model contracts | `llms`, `schema` | Chat/completion/reasoning contracts, multimodal messages, tool calls, usage accounting, lifecycle callbacks and middleware for any model |
| Chains | `chains` | LLM and conversation chains, stuff / map-reduce / map-rerank / refine QA, conversational retrieval, summarization, SQL, constitutional revision, sequential composition |
| Agents | `agents`, `callbacks` | ReAct/MRKL, conversational ReAct, provider-neutral tool-calling and OpenAI-functions presets, bounded executor with memory, callbacks, and intermediate steps |
| Prompts & parsing | `prompts`, `outputparser`, `jsonschema` | Validated string/chat templates, few-shot selectors, typed structured output parsers, recursive JSON-Schema subset |
| Memory | `memory` | Conversation buffer, window and token buffers, SQLite/PostgreSQL chat history, Zep history |
| Retrieval | `vectorstores`, `documentloaders`, `textsplitter` | 13 vector-store adapters, bounded PDF/HTML/CSV/text/directory loaders, recursive, token, and Markdown splitters |
| Tools | `tools` | Calculator, web search (DuckDuckGo, SerpApi, Exa, Perplexity, Wikipedia), page scraping, SQL database, Zapier MCP |
| Testing | `testing/llmtest`, `httputil` | Concurrency-safe mock model, opt-in live contract checks, injectable bounded HTTP transports used by every provider test |

## Providers

Chat and completion models. The [provider catalog](docs/providers.md) lists
setup and per-adapter limits:

OpenAI · Anthropic · Amazon Bedrock · Google AI (Gemini) · Google Vertex AI ·
Ollama · Cohere · Mistral · Hugging Face · Cloudflare Workers AI · Baidu
Qianfan (ERNIE) · Maritaca · IBM watsonx · llamafile · local executables

Embeddings: OpenAI · Cloudflare Workers AI · Google AI · Ollama · Jina ·
Mistral · Voyage AI · Hugging Face · Amazon Bedrock. Every provider accepts an
injectable transport, so provider tests run offline against fake transports,
with no keys required.

Vector stores: in-memory · Azure AI Search · Chroma · Dolt · MariaDB ·
Milvus · MongoDB · OpenSearch · pgvector · Pinecone · Qdrant · Redis Stack · Weaviate.

## Why LangChainV

- **Bounded by default.** Request/response byte caps, message and batch
  limits, timeouts, and context cancellation are built into adapters, not
  left to callers.
- **Offline-testable.** Providers depend on small transport and engine
  interfaces; tests inject fakes and never need credentials or network.
- **No mandatory dependencies.** Core packages use only the V standard
  library; optional backends stay isolated in their adapters.
- **Honest status.** The parity matrix records what is implemented,
  verified, partial, or outstanding for every upstream package, provider,
  embedding, and vector store.

## Documentation

| Guide | What it covers |
|---|---|
| [Documentation site](https://ulises-jeremias.github.io/langchainv/) | Quick start, tutorials, component map, production guide |
| [API reference](https://ulises-jeremias.github.io/langchainv/api/) | Searchable generated reference for every module |
| [Get started](docs/getting-started.md) | Install, first example, first program |
| [Tutorials](docs/tutorials.md) | End-to-end recipes from first chat to vector search |
| [Component map](docs/components.md) | How to choose a package |
| [Provider catalog](docs/providers.md) | Adapter setup, capabilities, and limits |
| [Production guide](docs/production.md) | Data handling, limits, cancellation, retries, tool access |
| [Parity matrix](docs/LANGCHAINGO_PARITY.md) | LangChainGo coverage, package by package |
| [Examples](examples/README.md) | Standalone programs and their requirements |

Each package also carries its own README next to the code. Start with the
[shared `llms` guide](llms/README.md) for the model contract.

## Compatibility

- V 0.5.2 or newer.
- PDF loading shells out to Poppler's `pdftotext` (arguments passed without a
  shell); everything else is pure V.
- Hosted CI runs `v fmt -verify`, compiles every Markdown code block, tests
  all packages, and builds and runs every standalone example.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the safe local V workflow and the
hosted-CI gates every change must pass. Changes land through pull requests
with a green CI matrix; documentation changes update the parity matrix when
behavior changes.

## License

MIT. See [LICENSE](LICENSE).
