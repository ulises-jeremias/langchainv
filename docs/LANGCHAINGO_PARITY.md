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
| `agents` | agent contract, planning, MRKL, conversational agents, OpenAI functions/tools, executor, initialization, options, errors | partial: Plan/Finish contract, generic model tool-calling agent, and bounded iterative executor with typed string inputs, case-insensitive tool dispatch, cancellation checks, callbacks, chain memory integration, and optional intermediate-step output; MRKL/conversational variants, specialized OpenAI-functions agent, parser recovery, and full initialization remain outstanding |
| `callbacks` | callback interfaces, simple/logging/streaming handlers, composition, agent-final stream | partial: lifecycle contract, no-op base handler, ordered fan-out composition, standard-output event logging and raw streaming log handlers, and a bounded agent-final stream with per-instance keywords; see V-native queue behavior in package docs |
| `chains` | base chain API/options, LLM, conversation, sequential, transform, stuff/map-reduce/map-rerank/refine, retrieval and conversational retrieval QA, question answering, summarization, SQL database, constitutional chains | partial: chain contract, input/output validation, prompt-backed completion and chat-model chains, a fixed-prompt completion conversation chain with history memory, bounded retrieval QA with optional source-document return, bounded history-based standalone-question rewriting for conversational retrieval QA, validated sequential composition, simple sequential key adaptation, and function-backed transform chain; other chain types remain outstanding |
| `documentloaders` | text, directory, CSV, HTML, PDF, Notion, AssemblyAI | partial: bounded HTML text, text-file, and CSV loaders; bounded recursive directory traversal for `.txt`, `.md`, `.csv`, `.html`, and `.htm` files with extension filters, CSV columns, source metadata, and bounded splitting; PDF, Notion, and AssemblyAI remain outstanding |
| `embeddings` | common embedding contract/options, vector math, Bedrock, Cybertron, Google AI, Hugging Face, Jina, OpenAI, Ollama, VoyageAI | partial: contracts, client adapter, newline preprocessing, bounded sequential batching, weighted vector combination, dot product, cosine similarity, OpenAI, Jina, and Voyage `/v1/embeddings`, Ollama `/api/embed`, and Gemini `batchEmbedContents` clients with injectable transport; Bedrock, Cybertron, and Hugging Face remain outstanding |
| `jsonschema` | schema generation and validation helpers | partial: recursive object/array definitions, primitive types, descriptions, string enums, properties, required names, and item schemas with consistency validation; advanced JSON Schema keywords and validation against instance values remain outstanding |
| `llms` | model/chat contracts, generation, options, errors/mappers, prompt caching, reasoning, token counting/utilization, marshaling, compliance, fake/cache; providers below | partial: generation/completion/reasoning contracts, response types, common options, token-counter contract, non-streaming OpenAI Chat Completions, Anthropic Messages, and Ollama chat with text, bounded images, client tool calls, usage accounting, and offline transport tests |
| `memory` | buffer, window buffer, token buffer, simple/chat memory, message history, AlloyDB, Cloud SQL, MongoDB, SQLite, Zep | partial: no-op and fixed-value simple memory, in-memory chat history, conversation buffer, bounded conversation window buffer, and injected-token-counter memory that evicts complete oldest turns; other memory forms and persistent backends remain outstanding |
| `outputparser` | simple, boolean, comma-separated list, regex, regex dictionary, defined/structured, combining | partial: simple, boolean, comma-separated list, regex, regex dictionary, structured string fields, combining string maps, and typed `Defined[T]` for strings, booleans, numbers, primitive options, scalar slices/string-key maps, enums, and nested structs; package compilation/tests pass in PR #1 CI (2026-10-09); fixed arrays, containers of nested structs, and other field types still need coverage |
| `prompts` | prompt values, string/chat/message templates, template formats/rendering, validation, example selectors, few-shot | partial: validated string placeholders and escaping; role-tagged text chat templates, static few-shot examples, and injected ExampleSelector support; alternate formats, typed multimodal templates, and built-in example selectors remain outstanding |
| `schema` | documents, messages, agent actions/steps, memory and retriever contracts, output parser contracts | partial: documents, typed multimodal messages, memory/history/retriever contracts |
| `textsplitter` | recursive character, token, Markdown, document splitting and options | partial: recursive character and document splitting; token windows via injected tokenizer; Markdown heading/paragraph/fence/table boundaries, heading hierarchy, and optional source-scanned reference-link rewriting; package tests and example compilation pass in PR #1 CI (2026-10-09); full CommonMark block fidelity, built-in token encodings, and complete option parity remain outstanding |
| `tools` | tool contract/calculator plus integrations below | partial: provider-neutral tool contract and bounded arithmetic calculator for `+`, `-`, `*`, `/`, `%`, `**`, and parentheses; expression length, operation count, and nesting are limited; Starlark math builtins and the remaining integrations are outstanding |
| `vectorstores` | vector store contract/options, query/add/delete/search, metadata filters, distance strategies, all stores below | partial: add/search/delete contract, options, retriever adapter, and bounded process-local cosine-similarity store with an injected embedder; persistent stores and full filter/distance parity remain outstanding |
| `httputil` | shared HTTP client/transport, user-agent, logging transport | partial: injectable default transport with composed user-agent, TLS validation, URL checks, disabled redirects/retries, and request/response byte and timeout limits; redacted debug logging remains outstanding |
| `util` | AlloyDB and Cloud SQL helpers | not started |
| `testing/llmtest` | LLM provider compliance and test helpers | not started |
| `exp` | experimental public API surface present upstream | not started |

## LLM providers

| Provider package | Status |
|---|---|
| Anthropic | partial: non-streaming Messages API client with text/system and bounded image messages, client tool definitions and tool-use responses, stop sequences, usage mapping, injectable bounded HTTP transport, and offline fixtures; streaming, reasoning replay, and provider-specific options remain outstanding |
| AWS Bedrock | not started |
| Cloudflare | not started |
| Cohere | not started |
| ERNIE | not started |
| Google AI / Gemini | partial: bounded non-streaming `generateContent` for text, system instructions, inline images, function declarations/calls/results, generation controls, candidate count, seed, JSON MIME output, finish reasons, usage mapping, Gemini `batchEmbedContents`, and injectable HTTPS transports; remote image URLs, streaming, JSON schema output, and token counting remain outstanding |
| Google Vertex AI | not started |
| Hugging Face | not started |
| llamafile | not started |
| local | not started |
| Maritaca | not started |
| Mistral | not started |
| Ollama | partial: non-streaming `/api/chat`, text and bounded inline images, tool definitions/results, JSON mode, common generation options, thinking replay, usage accounting, `/api/embed` client, and injectable offline-tested transports; streaming, pull/model management, schema-valued format, and provider options remain outstanding |
| OpenAI | partial: non-streaming Chat Completions, completion adapter, text and image messages, function tools, usage, reasoning fields; streaming, richer reasoning replay, response APIs and broader option parity outstanding |
| IBM watsonx | not started |

## Embedding providers

OpenAI — partial: JSON float requests, configurable model/base URL/dimensions,
input-order restoration, and injected HTTP transport. Jina — partial: bounded
JSON float requests, configurable model/base URL, response-order restoration,
and injected HTTP transport; task/dimension options and asynchronous batches
remain outstanding. VoyageAI — partial: bounded JSON float requests, configurable
model/base URL, query/document input modes, and injected HTTP transport;
dimension and task configuration remain outstanding. Ollama — partial: batched
`/api/embed`, configurable model/base URL, input and response limits, vector
shape validation, and injected HTTP transport. Google AI — partial: batched
`batchEmbedContents`, configurable model/base URL/task/dimensions, vector shape
validation, and injected HTTP transport. Bedrock, Cybertron, and Hugging Face
remain not started.

## Vector stores

AlloyDB, Azure AI Search, Bedrock Knowledge Bases, Chroma, Cloud SQL, Dolt,
MariaDB, Milvus (including v2), MongoDB vector search, OpenSearch, pgvector,
Pinecone, Qdrant, Redis, and Weaviate — all not started.

## Document loaders and tools

- Loaders still outstanding: AssemblyAI, Notion, and PDF. HTML uses V's standard-library parser; full browser-style parsing and network fetching are outside its scope.
- Tools still outstanding: DuckDuckGo, Metaphor, Perplexity, scraper,
  SerpAPI, SQL database (MySQL/PostgreSQL/SQLite), Wikipedia, and Zapier.

## Cross-cutting parity requirements

Track per applicable provider/component: streaming and cancellation; structured
output and tool calls; usage/token accounting; options/defaults; retry and
timeout behavior; typed errors; request metadata; secret redaction; batching;
pagination; filters; serialization; cleanup; examples; and platform/service
constraints. A feature absent upstream is not required for parity, but may be
added as a separately documented V-native extension.
