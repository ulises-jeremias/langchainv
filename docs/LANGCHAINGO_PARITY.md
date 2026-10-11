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
| `agents` | agent contract, planning, MRKL, conversational agents, OpenAI functions/tools, executor, initialization, options, errors | partial: Plan/Finish contract, bounded textual MRKL/ReAct agent with configurable prompts, tool descriptions/names, iterative scratchpad, streaming-capable completion options, case-insensitive final/action parsing, and output byte limits; generic model tool-calling agent; and bounded iterative executor with typed string inputs, case-insensitive tool dispatch, cancellation checks, callbacks, chain memory integration, and optional intermediate-step output; conversational variants, specialized OpenAI-functions agent, advanced parser recovery, and full initialization remain outstanding |
| `callbacks` | callback interfaces, simple/logging/streaming handlers, composition, agent-final stream | partial: lifecycle contract, no-op base handler, ordered fan-out composition, standard-output event logging and raw streaming log handlers, and a bounded agent-final stream with per-instance keywords; see V-native queue behavior in package docs |
| `chains` | base chain API/options, LLM, conversation, sequential, transform, stuff/map-reduce/map-rerank/refine, retrieval and conversational retrieval QA, question answering, summarization, SQL database, constitutional chains | partial: chain contract, input/output validation, prompt-backed completion and chat-model chains, a fixed-prompt completion conversation chain with history memory, bounded document-stuffing into completion prompts, sequential bounded map-reduce with metadata preservation and optional intermediate steps, bounded sequential map-rerank with answer/score parsing, descending rank selection and optional sorted steps, bounded sequential refine with metadata-aware document formatting, running-answer updates and pre-call limits, bounded sequential constitutional critique and revision with validated principles/prompts, byte limits, cancellation checks, and optional intermediate steps, bounded retrieval QA with optional source-document return, bounded history-based standalone-question rewriting for conversational retrieval QA, built-in stuff/refine/map-reduce/map-rerank QA presets, question-condensing prompt chain, stuff/refine/map-reduce summarization presets, validated sequential composition, simple sequential key adaptation, function-backed transform chain, and bounded SQLDatabase schema/sample/query APIs; database calls materialize rows before output caps and cannot be interrupted mid-query through `context.Context`. Map-reduce, map-rerank, and refine currently process documents sequentially rather than using LangChainGo's concurrent mapping |
| `documentloaders` | text, directory, CSV, HTML, PDF, Notion, AssemblyAI | partial: bounded HTML text, text-file, CSV, Poppler-backed PDF extraction, paginated recursive Notion blocks, and AssemblyAI transcription loaders; bounded recursive directory traversal for `.txt`, `.md`, `.csv`, `.html`, `.htm`, and `.pdf` files with extension filters, CSV columns, source metadata, and bounded splitting; PDF extraction uses literal `pdftotext` arguments without a shell, regular-file checks, input/output/time limits, cancellation, and process-group cleanup; Poppler is an external runtime dependency |
| `embeddings` | common embedding contract/options, vector math, Bedrock, Cybertron, Google AI, Hugging Face, Jina, OpenAI, Ollama, VoyageAI | partial: contracts, client adapter, newline preprocessing, bounded sequential batching, weighted vector combination, dot product, cosine similarity, OpenAI, Jina, and Voyage `/v1/embeddings`, Hugging Face feature extraction, Ollama `/api/embed`, Gemini `batchEmbedContents`, and Amazon Bedrock Titan/Cohere `InvokeModel` clients with injectable transport; Cybertron remains outstanding |
| `jsonschema` | schema generation and validation helpers | partial: recursive object/array definitions, single or union primitive/container types, descriptions, string enums, properties, required names, item schemas, inclusive/exclusive numeric bounds, string minLength/maxLength, array minItems/maxItems, boolean additionalProperties, definition consistency validation, and recursive instance validation with path-aware errors and 10,000-node/1 MiB/64-level bounds for the supported subset; references, formats, schema-valued additionalProperties, composition, and advanced keywords remain outstanding |
| `llms` | model/chat contracts, generation, options, errors/mappers, prompt caching, reasoning, token counting/utilization, marshaling, compliance, fake/cache; providers below | partial: generation/completion/reasoning contracts, response types, common options, OpenAI Chat Completions text/reasoning/tool streaming, non-streaming OpenAI Chat Completions, llamafile's current OpenAI-compatible Chat Completions endpoint, Bedrock Converse chat, Anthropic Messages, Cohere Chat API v2, current Baidu Qianfan v2 OpenAI-compatible chat, Maritaca Chat Completions, Mistral Chat Completions, Hugging Face Inference Providers chat, Cloudflare Workers AI chat, and Ollama chat with text, bounded images, client tool calls, usage accounting, and offline transport tests |
| `memory` | buffer, window buffer, token buffer, simple/chat memory, message history, AlloyDB, Cloud SQL, MongoDB, SQLite, Zep | partial: no-op and fixed-value simple memory, in-memory and bounded session-isolated SQLite chat history, conversation buffer with injectable history, typed message snapshots, configurable prefixes, and single-key input/output inference, bounded conversation window buffer, and injected-token-counter memory that evicts complete oldest turns; AlloyDB, Cloud SQL, MongoDB, and Zep backends remain outstanding |
| `outputparser` | simple, boolean, comma-separated list, regex, regex dictionary, defined/structured, combining | partial: simple, boolean, comma-separated list, regex, regex dictionary, structured string fields, combining string maps, and typed `Defined[T]` for strings, booleans, numbers, primitive options, scalar slices/fixed arrays/string-key maps, nullable scalar slices/fixed arrays/maps, enums in fields/slices/fixed arrays/string-key maps, nested structs, and slices/fixed arrays/string-key maps of nested structs; other field types still need coverage |
| `prompts` | prompt values, string/chat/message templates, template formats/rendering, validation, example selectors, few-shot | partial: validated string placeholders and escaping; role-tagged text chat templates, static few-shot examples, and the injected `ExampleSelector` contract; alternate formats and typed multimodal templates remain outstanding. LangChainGo exposes only the selector interface in `prompts/example_selector.go`, so concrete selector implementations are outside this parity inventory |
| `schema` | documents, messages, agent actions/steps, memory and retriever contracts, output parser contracts | partial: documents, typed multimodal messages, memory/history/retriever contracts |
| `textsplitter` | recursive character, token, Markdown, document splitting and options | partial: recursive character and document splitting; token windows via injected tokenizer; Markdown heading/paragraph/fence/table boundaries, heading hierarchy, and optional source-scanned reference-link rewriting; package tests and example compilation pass in PR #1 CI (2026-10-09); full CommonMark block fidelity, built-in token encodings, and complete option parity remain outstanding |
| `tools` | tool contract/calculator plus integrations below | partial: provider-neutral tool contract, bounded arithmetic calculator for `+`, `-`, `*`, `/`, `%`, `**`, parentheses, and the Starlark math module's functions/constants, bounded Perplexity Sonar search through the OpenAI-compatible chat API, bounded DuckDuckGo HTML search, bounded Wikipedia MediaWiki REST search, bounded SerpApi Google search, bounded Exa (Metaphor successor) semantic search, bounded sequential same-origin HTML crawling, Zapier MCP Streamable HTTP tool discovery/calls, and SQLDatabase table inventory/schema/sample/query APIs over V's SQLite driver with optional PostgreSQL/MySQL drivers; SQL tests use in-memory SQLite, while database driver calls materialize rows before output caps and cannot be interrupted mid-query through `context.Context` |
| `vectorstores` | vector store contract/options, query/add/delete/search, metadata filters, distance strategies, all stores below | partial: add/search/delete contract, options, retriever adapter, bounded process-local cosine-similarity store, and bounded Chroma/Qdrant/Pinecone REST adapters with injected embeddings, namespaces, and metadata filters; persistent stores beyond these and full filter/distance parity remain outstanding |
| `httputil` | shared HTTP client/transport, user-agent, logging transport | partial: injectable default transport with composed user-agent, TLS validation, URL checks, disabled redirects/retries, request/response byte and timeout limits, bounded incremental response callbacks, a chunk-independent SSE decoder, and redacted logging decorators for streaming and non-streaming clients |
| `util` | AlloyDB and Cloud SQL helpers | not started |
| `testing/llmtest` | LLM provider compliance and test helpers | partial: opt-in core generation and canceled-context checks, with capability checks for multiturn history, streaming chunks/error propagation, tool-call JSON/replay, and typed token usage; CI tests use deterministic offline model doubles, and calling `test_model` against a live provider is explicit |
| `exp` | experimental public API surface present upstream | not started |

## LLM providers

| Provider package | Status |
|---|---|
| Anthropic | partial: streaming and non-streaming Messages API client with text/system and bounded image messages, text/thinking deltas, fragmented tool-use JSON, client tool definitions and tool-use responses, stop sequences, usage mapping, injectable bounded HTTP transport, and offline fixtures; reasoning replay and provider-specific options remain outstanding |
| AWS Bedrock | partial: streaming and non-streaming Bedrock Runtime Converse with text, bounded inline JPEG/PNG, client tool definitions/calls/results, fragmented streamed tool input, reasoning deltas, inference controls, token usage, EventStream CRC validation, bearer API-key authentication, injected bounded transport, and offline fixtures; AWS credential-chain/SigV4 signing, reasoning replay, and broader model-specific options remain outstanding |
| Cloudflare | partial: Workers AI OpenAI-compatible Chat Completions route, required account/model configuration, `max_tokens` translation, common message/tool behavior, bounded injectable transport, and offline tests; chat streaming passes through streaming-capable transports, while Workers AI-specific options and provider-only controls remain outstanding |
| Cohere | partial: bounded streaming and non-streaming Chat API v2 text generation, streamed function tool calls, sampling and stop controls, function tool calls and replay, JSON object mode, usage accounting, and injectable offline transport; image input, reasoning replay, provider extensions, and named tool selection remain outstanding. This uses the current `/v2/chat` API because Cohere marks the upstream adapter's `/v1/generate` endpoint deprecated. |
| ERNIE | partial: current Baidu Qianfan v2 OpenAI-compatible chat with configurable model/base URL, shared message/tool/JSON/options support, streaming-capable transport, bounded transport, and fake-transport tests; legacy AK/SK token exchange, legacy routes, embeddings, and provider-specific controls remain outstanding |
| Google AI / Gemini | partial: bounded streaming and non-streaming `generateContent` / `streamGenerateContent` SSE for text and function calls, system instructions, inline images, function declarations/calls/results, generation controls, candidate count, seed, JSON MIME output, finish reasons, usage mapping, Gemini `batchEmbedContents`, and injectable HTTPS transports; remote image URLs, JSON schema output, and token counting remain outstanding |
| Google Vertex AI | partial: Gemini text/image/tool generation and streaming behavior reused from the shared Google AI client through a Vertex REST route and explicit OAuth bearer-token transport; automatic Application Default Credentials discovery/refresh and Vertex-specific features remain outstanding |
| Hugging Face | partial: current OpenAI-compatible Inference Providers chat router with required model/provider selection, common message/tool behavior, `max_tokens` translation, bounded injectable HTTP transport, and offline tests; chat streaming passes through streaming-capable transports, while the legacy inference route and provider-specific options remain outstanding |
| llamafile | partial: current OpenAI-compatible Chat Completions endpoint, loopback default, HTTPS custom endpoints, shared OpenAI request/response, streaming, and tool handling, bounded injectable transport, and offline fixtures; upstream legacy `/completion` and `/embedding` APIs and llama.cpp-specific options remain outstanding |
| local | partial: executable-backed completion/chat client using `LOCAL_LLM_BIN` / `LOCAL_LLM_ARGS` or explicit options, literal argument passing without a shell, bounded prompt/arguments/output, common generation flags, callbacks, and context cancellation that kills the process group; tests use only small local system utilities, not model binaries |
| Maritaca | partial: current OpenAI-compatible Chat Completions using the shared message/tool/JSON/options and streaming implementation, configurable endpoint/model, bounded transport, and fake-transport tests; Responses API and provider-specific options remain outstanding |
| Mistral | partial: OpenAI-compatible Chat Completions using the shared request/response implementation, with translation for Mistral's `max_tokens` and `random_seed` fields in regular and streamed requests, regional base URL/model configuration, and fake-transport tests; native Mistral options and provider-specific behavior beyond those field mappings remain outstanding |
| Ollama | partial: streaming and non-streaming `/api/chat` with bounded NDJSON, text/reasoning callbacks, text and bounded inline images, tool definitions/results, JSON mode, common generation options, thinking replay, usage accounting, `/api/embed` client, and injectable offline-tested transports; pull/model management, schema-valued format, and provider options remain outstanding |
| OpenAI | partial: Chat Completions streaming and non-streaming, completion adapter, text and image messages, function tools, usage, and reasoning fields; streaming requires a streaming-capable transport, while richer reasoning replay, response APIs and broader option parity remain outstanding |
| IBM watsonx | partial: bounded text generation with IAM bearer-token auth, explicit tokens or API-key exchange and cached renewal, API-key/project environment fallbacks, project/model selection, supported sampling and stop options, token usage mapping, and offline tests; streaming and chat-generation APIs remain outstanding |

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
validation, and injected HTTP transport. Hugging Face — partial: bounded
feature-extraction requests through the current inference router with
configurable model/task/base URL and injected transport. Bedrock — partial:
Titan V1/V2 and Cohere V3 requests via bearer-key Runtime API, including Cohere
query/document modes and injected transport; AWS credential-chain signing and
broader model support remain outstanding. Cybertron remains not started: its
upstream contract runs pretrained Transformer embedding models locally, while
the available VTL model checkpoint format targets VTL `Sequential` networks
and does not provide a compatible pretrained-model loader. VSL's tokenizer is
not a substitute for that inference runtime. Revisit this adapter when a
compatible V-native pretrained encoder/runtime exists; do not imply parity by
wrapping training layers or downloading weights during ordinary checks.

## Vector stores

AlloyDB, Azure AI Search, Bedrock Knowledge Bases, Cloud SQL, Dolt, MariaDB,
Milvus (including v2), MongoDB vector search, OpenSearch, pgvector, Redis, and
Weaviate remain not started. Chroma — partial: v2 REST create/get-or-create and
delete collection management, upsert/query/delete, injected embeddings and
HTTP transport, loopback HTTP or remote HTTPS, token authentication, scalar
equality filters, namespaces, score thresholds, and bounded payloads; custom
collection configuration, array metadata, advanced filters, custom IDs, and
returned vectors remain outstanding. Qdrant — partial: REST
create/delete and upsert/query/delete for single-vector cosine collections,
API-key or HTTPS authentication, payload metadata filters, namespaces, injected
embeddings/transport, and bounded requests with preflight embedding-dimension
validation for newly created collections; named or multi-vector search, the
full filter DSL, custom point IDs, and vector return remain outstanding.
Pinecone — partial: HTTPS upsert/query/delete against
provisioned index hosts, API-key auth, namespaces, scalar metadata equality
filters, injected embeddings/transport, and bounded requests; index management,
sparse/hybrid vectors, full filter operators, integrated text inference, and
vector return remain outstanding.

## Document loaders and tools

- PDF loading is implemented with Poppler `pdftotext`, bounded input/output and timeout settings, cancellation, and recursive-directory integration. CI installs `poppler-utils`; consumers need `pdftotext` on `PATH` or may configure its executable path. AssemblyAI provides bounded HTTPS URL submission and status polling with injectable HTTP and offline tests. HTML uses V's standard-library parser; full browser-style parsing and network fetching are outside its scope.
- SQLDatabase exposes SQLite by default and PostgreSQL/MySQL through V's
  compile-time database drivers; test environments verify the SQLite backend
  with in-memory fixtures. Zapier's retired NLA API is replaced by the current
  MCP Streamable HTTP integration.

## Cross-cutting parity requirements

Track per applicable provider/component: streaming and cancellation; structured
output and tool calls; usage/token accounting; options/defaults; retry and
timeout behavior; typed errors; request metadata; secret redaction; batching;
pagination; filters; serialization; cleanup; examples; and platform/service
constraints. A feature absent upstream is not required for parity, but may be
added as a separately documented V-native extension.
