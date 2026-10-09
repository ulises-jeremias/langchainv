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
| `callbacks` | callback interfaces, simple/logging/streaming handlers, composition, agent-final stream | partial: lifecycle handler contract and ordered text dispatch |
| `chains` | base chain API/options, LLM, conversation, sequential, transform, stuff/map-reduce/map-rerank/refine, retrieval and conversational retrieval QA, question answering, summarization, SQL database, constitutional chains | partial: chain contract and input/output validation |
| `documentloaders` | text, directory, CSV, HTML, PDF, Notion, AssemblyAI | partial: bounded text-file loader |
| `embeddings` | common embedding contract/options, vector math, Bedrock, Cybertron, Hugging Face, Jina, OpenAI, VoyageAI | partial: contracts, `BatchedEmbedder` preprocessing and bounded batching over provider clients, dot product, cosine similarity |
| `jsonschema` | JSON Schema data types, recursive definitions, and JSON serialization | implemented: all upstream definition fields and data-type constants, recursive conversion/encoding, and always-present empty `properties`; covered by package CI |
| `llms` | model/chat contracts, generation, options, errors/mappers, prompt caching, reasoning, token counting/utilization, marshaling, compliance, fake/cache; providers below | partial: generation/completion/reasoning contracts, response types, common options, token-counter contract |
| `memory` | buffer, window buffer, token buffer, simple/chat memory, message history, AlloyDB, Cloud SQL, MongoDB, SQLite, Zep | partial: in-memory chat history and conversation buffer |
| `outputparser` | simple, boolean, comma-separated list, regex, regex dictionary, defined/structured, combining | partial: simple, boolean, comma-separated list |
| `prompts` | prompt values, string/chat/message templates, template formats/rendering, validation, example selectors, few-shot | partial: validated string placeholders and escaping |
| `schema` | documents, messages, agent actions/steps, memory and retriever contracts, output parser contracts | partial: documents, typed multimodal messages, memory/history/retriever contracts |
| `textsplitter` | recursive character, token, Markdown, document splitting and options | not started |
| `tools` | tool contract/calculator plus integrations below | partial: provider-neutral tool contract |
| `vectorstores` | vector store contract/options, query/add/delete/search, metadata filters, distance strategies, all stores below | partial: add/search/delete contract, options, retriever adapter |
| `httputil` | shared HTTP client/transport, user-agent, logging transport | partial: safe V `http.fetch` wrapper, API-key query helper, and redacted body-free request diagnostics; custom Go `RoundTripper` has no direct V `net.http` equivalent |
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
| OpenAI | partial: text, image URL, and WAV/MP3 audio chat input, non-streaming function tool calls, SSE text streaming, text prompt adapter, embeddings, Azure AI Foundry v1 API-key auth, common sampling/token options, JSON mode, usage, and redacted HTTP errors; audio output, streamed tool calls, legacy functions/completions, Azure deployment URLs, and provider-specific options remain |
| IBM watsonx | not started |

## Embedding providers

OpenAI is partial through `llms.openai.Client.create_embedding`; Bedrock,
Cybertron, Hugging Face, Jina, and VoyageAI are not started.

## Vector stores

AlloyDB, Azure AI Search, Bedrock Knowledge Bases, Chroma, Cloud SQL, Dolt,
MariaDB, Milvus (including v2), MongoDB vector search, OpenSearch, pgvector,
Pinecone, Qdrant, Redis, and Weaviate — all not started.

## Document loaders and tools

- Loaders: AssemblyAI, CSV, directory, HTML, Notion, PDF, text.
- Tools: calculator, DuckDuckGo, Metaphor, Perplexity, scraper, SerpAPI, SQL
  database (MySQL/PostgreSQL/SQLite), Wikipedia, Zapier.
- All are not started.

## Cross-cutting parity requirements

Track per applicable provider/component: streaming and cancellation; structured
output and tool calls; usage/token accounting; options/defaults; retry and
timeout behavior; typed errors; request metadata; secret redaction; batching;
pagination; filters; serialization; cleanup; examples; and platform/service
constraints. A feature absent upstream is not required for parity, but may be
added as a separately documented V-native extension.
