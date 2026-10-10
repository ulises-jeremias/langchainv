# LangChainGo parity ledger

Status values: `not started`, `partial`, `implemented`, `verified`. A package
must not be called implemented until its public behavior and supported options
are accounted for. `verified` requires behavior evidence at the same scope as
the claim.

The inventory is based on upstream commit
`039fbb6c6469a8ffcdae615ec7bdc465c83abadc` (`main`, 1,500 entries) inspected on
2026-10-09. Upstream can change; refresh this inventory before a release.

## Framework packages

| Upstream package | Scope to account for | Status |
|---|---|---|
| `agents` | agent contract, planning, MRKL, conversational agents, OpenAI functions/tools, executor, initialization, options, errors | not started |
| `callbacks` | callback interfaces, simple/logging/streaming handlers, composition, agent-final stream | partial: lifecycle contract, no-op base handler, ordered dispatch, and fan-out composition for every declared event; logging, streaming, and agent-final stream adapters remain outstanding |
| `chains` | base chain API/options, LLM, conversation, sequential, transform, stuff/map-reduce/map-rerank/refine, retrieval and conversational retrieval QA, question answering, summarization, SQL database, constitutional chains | partial: chain contract and input/output validation |
| `documentloaders` | text, directory, CSV, HTML, PDF, Notion, AssemblyAI | partial: bounded text-file and CSV text loaders; bounded recursive directory traversal for `.txt`, `.md`, and `.csv` files with extension filters, CSV columns, source metadata, and bounded splitting; HTML, PDF, Notion, and AssemblyAI remain outstanding |
| `embeddings` | common embedding contract/options, vector math, Bedrock, Cybertron, Hugging Face, Jina, OpenAI, VoyageAI | partial: contracts, newline preprocessing, batching, dot product, cosine similarity |
| `jsonschema` | schema generation and validation helpers | not started |
| `llms` | model/chat contracts, generation, options, errors/mappers, prompt caching, reasoning, token counting/utilization, marshaling, compliance, fake/cache; providers below | partial: generation/completion/reasoning contracts, response types, common options, token-counter contract |
| `memory` | buffer, window buffer, token buffer, simple/chat memory, message history, AlloyDB, Cloud SQL, MongoDB, SQLite, Zep | partial: in-memory chat history and conversation buffer |
| `outputparser` | simple, boolean, comma-separated list, regex, regex dictionary, defined/structured, combining | partial: simple, boolean, comma-separated list, regex, regex dictionary, structured string fields, combining string maps, and typed `Defined[T]` for strings, booleans, numbers, primitive options, scalar slices/string-key maps, enums, and nested structs; package compilation/tests pass in PR #1 CI (2026-10-09); fixed arrays, containers of nested structs, and other field types still need coverage |
| `prompts` | prompt values, string/chat/message templates, template formats/rendering, validation, example selectors, few-shot | partial: validated string placeholders and escaping |
| `schema` | documents, messages, agent actions/steps, memory and retriever contracts, output parser contracts | partial: documents, typed multimodal messages, memory/history/retriever contracts |
| `textsplitter` | recursive character, token, Markdown, document splitting and options | partial: recursive character and document splitting; token windows via injected tokenizer; Markdown heading/paragraph/fence/table boundaries, heading hierarchy, and optional source-scanned reference-link rewriting; package tests and example compilation pass in PR #1 CI (2026-10-09); full CommonMark block fidelity, built-in token encodings, and complete option parity remain outstanding |
| `tools` | tool contract/calculator plus integrations below | partial: provider-neutral tool contract |
| `vectorstores` | vector store contract/options, query/add/delete/search, metadata filters, distance strategies, all stores below | partial: add/search/delete contract, options, retriever adapter |
| `httputil` | shared HTTP client/transport, user-agent, logging transport | not started |
| `util` | AlloyDB and Cloud SQL helpers | not started |
| `testing/llmtest` | LLM provider compliance and test helpers | not started |
| `exp` | experimental public API surface present upstream | not started |

## LLM providers

| Provider package | Status |
|---|---|
| Anthropic | not started |
| AWS Bedrock | not started |
| Cloudflare | not started |
| Cohere | not started |
| ERNIE | not started |
| Google AI / Gemini | not started |
| Google Vertex AI | not started |
| Hugging Face | not started |
| llamafile | not started |
| local | not started |
| Maritaca | not started |
| Mistral | not started |
| Ollama | not started |
| OpenAI | not started |
| IBM watsonx | not started |

## Embedding providers

Bedrock, Cybertron, Hugging Face, Jina, OpenAI, and VoyageAI — all not started.

## Vector stores

AlloyDB, Azure AI Search, Bedrock Knowledge Bases, Chroma, Cloud SQL, Dolt,
MariaDB, Milvus (including v2), MongoDB vector search, OpenSearch, pgvector,
Pinecone, Qdrant, Redis, and Weaviate — all not started.

## Document loaders and tools

- Loaders still outstanding: AssemblyAI, HTML, Notion, and PDF.
- Tools still outstanding: calculator, DuckDuckGo, Metaphor, Perplexity, scraper,
  SerpAPI, SQL database (MySQL/PostgreSQL/SQLite), Wikipedia, and Zapier.

## Cross-cutting parity requirements

Track per applicable provider/component: streaming and cancellation; structured
output and tool calls; usage/token accounting; options/defaults; retry and
timeout behavior; typed errors; request metadata; secret redaction; batching;
pagination; filters; serialization; cleanup; examples; and platform/service
constraints. A feature absent upstream is not required for parity, but may be
added as a separately documented V-native extension.
