# LangChainGo parity ledger

Status values: `not started`, `partial`, `implemented`, `verified`, and
`not applicable` when the pinned upstream snapshot exposes no implementation
surface to port. A package must not be called implemented until its public
behavior and supported options are accounted for. `verified` requires behavior
evidence at the same scope as the claim.

The inventory is based on upstream commit
[`6351d0d03286ba1f8be78b572d88c9b43ed6b869`](https://github.com/tmc/langchaingo/commit/6351d0d03286ba1f8be78b572d88c9b43ed6b869)
(`main`, 1,501 tree entries) inspected on 2026-10-12 and rechecked on
2026-10-13. GitHub still reports this SHA as the `main` head, so the upstream
inventory has not changed since the previous scan. This snapshot is 16 commits
ahead of the 2026-10-09 scan. Upstream can change; refresh this inventory before
a release.

## Changes since the previous upstream scan

- CI now runs `govulncheck`, upgrades its Go lint tool, and uses an explicit
  Bash shell for piped test output so test failures propagate through `tee`.
  LangChainV has no mandatory third-party modules; its hosted CI pins V, runs
  `v fmt -verify .`, tests configured packages, and compiles every standalone
  example.
- `ConversationalRetrievalQA.GetOutputKeys()` now reports
  `generated_question` when that output is enabled. LangChainV already includes
  that key in its conversational retrieval chain output contract.
- Anthropic now emits its generation-end callback on successful legacy and
  Messages API responses. LangChainV has lifecycle event contracts and
  streaming callbacks. Its provider adapters do not all expose lifecycle
  callbacks, but `llms/middleware.CallbackModel` and
  `CallbackCompletionModel` dispatch start/end/error events around any
  `llms.Model` or `llms.CompletionModel` implementation.
- Mistral now returns distinct empty/multiple-choice errors, invokes the
  configured callback handler, and exposes usage through the same token-count
  keys as other providers. LangChainV normalizes token usage into
  `llms.Usage`; its generic model and completion middleware provide lifecycle
  events when an adapter does not expose its own callback configuration.
- The upstream compliance helper recognizes more provider usage key spellings
  and integer types; its reusable `MockLLM` is now concurrency-safe. LangChainV
  has opt-in live model contract checks and `testing/llmtest.MockModel`, a
  reusable, concurrency-safe fake that snapshots responses and can supply
  deterministic errors and streaming output.
- The remaining changes in this range are mainly dependency/example refreshes,
  replay-fixture adjustments, and test robustness fixes; they do not add a new
  upstream framework package.
- The upstream `exp` directory contains only its README and package comment at
  this snapshot; it exposes no experimental API surface to port.

## Framework packages

| Upstream package | Scope to account for | Status |
|---|---|---|
| `agents` | agent contract, planning, MRKL, conversational agents, OpenAI functions/tools, executor, initialization, options, errors | partial: Plan/Finish contract, bounded textual MRKL/ReAct agent with configurable prompts, tool descriptions/names, iterative scratchpad, streaming-capable completion options, case-insensitive and inline action/final-answer label recovery with word-boundary checks, malformed-output errors, and output byte limits; conversational ReAct prompt with executor-managed history; provider-neutral tool-calling and OpenAI-compatible functions presets with configurable system instructions, extra messages, and model options; schema-backed function parameters; ordered replay of grouped tool calls; `__arg1` compatibility for legacy single-string tools; explicit initialization of ReAct and conversational ReAct presets into a bounded executor; typed string inputs, case-insensitive tool dispatch, cancellation checks, callbacks, chain memory integration, optional intermediate-step output, and opt-in executor parsing-error recovery that feeds a bounded invalid-output step back to the agent instead of failing the run; broader parser recovery and upstream agent types beyond these presets remain outstanding |
| `callbacks` | callback interfaces, simple/logging/streaming handlers, composition, agent-final stream | partial: lifecycle contract for completion and chat models, no-op base handler, ordered fan-out composition, standard-output event logging and raw streaming log handlers, bounded agent-final stream with per-instance keywords, and `llms/middleware` wrappers to dispatch start/end/error lifecycle around any `llms.Model` or `llms.CompletionModel`; every built-in provider adapter now exposes generate-content lifecycle callbacks directly: local, Vertex, and watsonx through client fields, OpenAI, Anthropic, Cohere, Google AI, Ollama, and Bedrock through Options or the client field, and the OpenAI-compatible wrappers (Mistral, ERNIE, Maritaca, Hugging Face, Cloudflare, llamafile) by forwarding a handler from their own Options to the shared OpenAI client; see V-native queue behavior in package docs |
| `chains` | base chain API/options, LLM, conversation, sequential, transform, stuff/map-reduce/map-rerank/refine, retrieval and conversational retrieval QA, question answering, summarization, SQL database, constitutional chains | partial: chain contract, input/output validation, prompt-backed completion and chat-model chains, a fixed-prompt completion conversation chain with history memory, bounded document-stuffing into completion prompts, bounded map-reduce with metadata preservation and optional intermediate steps, bounded map-rerank with answer/score parsing, descending rank selection and optional sorted steps, both with opt-in ordered mapping concurrency (1-5 workers, sequential by default), bounded sequential refine with metadata-aware document formatting, running-answer updates and pre-call limits, bounded sequential constitutional critique and revision with validated principles/prompts, byte limits, cancellation checks, and optional intermediate steps, bounded retrieval QA with optional source-document return, bounded history-based standalone-question rewriting for conversational retrieval QA with original-question rephrasing control and optional generated-question output, built-in stuff/refine/map-reduce/map-rerank QA presets, question-condensing prompt chain, stuff/refine/map-reduce summarization presets, validated sequential composition, simple sequential key adaptation, function-backed transform chain, bounded SQLDatabase schema/sample/query APIs, and a bounded SQL database chain that generates one read-only SELECT/WITH query, executes it, and answers from the result with optional intermediate steps; database calls materialize rows before output caps and cannot be interrupted mid-query through `context.Context`. Refine remains sequential because each step uses the prior answer |
| `documentloaders` | text, directory, CSV, HTML, PDF, Notion, AssemblyAI | partial: bounded HTML text, text-file, CSV, page-scoped Poppler PDF extraction with page metadata and bounded splitting, paginated recursive Notion blocks, and AssemblyAI transcription loaders; bounded recursive directory traversal for `.txt`, `.md`, `.csv`, `.html`, `.htm`, and `.pdf` files with extension filters, CSV columns, source metadata, and bounded splitting; PDF extraction uses literal `pdftotext` arguments without a shell, regular-file checks, input/output/time/page-count limits, cancellation, and process-group cleanup; encrypted PDFs remain unsupported because Poppler exposes passwords through process arguments; safe support is tracked in [#161](https://github.com/ulises-jeremias/langchainv/issues/161); Poppler is an external runtime dependency |
| `embeddings` | common embedding contract/options, vector math, Bedrock, Cloudflare, Cybertron, Google AI, Hugging Face, Jina, Mistral, OpenAI, Ollama, VoyageAI | partial: contracts, client adapter, newline preprocessing, bounded sequential batching, weighted vector combination, dot product, cosine similarity, OpenAI, Mistral, and Cloudflare Workers AI `/v1/embeddings`, Jina and Voyage `/v1/embeddings`, Hugging Face feature extraction, Ollama `/api/embed` with opt-in model pull and context deadline, Gemini `batchEmbedContents`, and Amazon Bedrock Titan/Cohere `InvokeModel` clients with injectable transport; Cybertron remains outstanding |
| `jsonschema` | schema generation helpers for type, description, enum, properties, required names, and array items | partial: upstream Definition fields plus V-native union types, inclusive/exclusive numeric bounds, string and array size bounds, boolean additionalProperties, definition consistency validation, and recursive instance validation with path-aware errors and 10,000-node/1 MiB/64-level bounds. As V-native extensions beyond that helper, the Definition API also models format names (annotation only, with string-placement checks) and allOf/anyOf/oneOf/not composition with instance enforcement. Local `#/$defs/` references and schema-valued additionalProperties are also supported; external references remain unsupported, while tools can receive raw schemas |
| `llms` | model/chat contracts, generation, options, errors/mappers, prompt caching, reasoning, token counting/utilization, marshaling, compliance, fake/cache; providers below | partial: generation/completion/reasoning contracts, response types, common options, callback lifecycle middleware for any `Model` or `CompletionModel`, concurrency-safe canned-response model in `llms/fake`, pluggable response cache with deterministic SHA-256 keys over typed messages and generation options, streaming text replay, reasoning-stream bypass, byte-budgeted in-memory FIFO and persistent SQLite backends; OpenAI Chat Completions text/reasoning/tool streaming, non-streaming OpenAI Chat Completions, llamafile's current OpenAI-compatible Chat Completions endpoint, Bedrock Converse chat, Anthropic Messages, Cohere Chat API v2, current Baidu Qianfan v2 OpenAI-compatible chat, Maritaca Chat Completions, Mistral Chat Completions, Hugging Face Inference Providers chat, Cloudflare Workers AI chat, and Ollama chat with text, bounded images, client tool calls, usage accounting, opt-in model pulling with caller-context timeout, and offline transport tests |
| `memory` | buffer, window buffer, token buffer, simple/chat memory, message history, AlloyDB, Cloud SQL, MongoDB, SQLite, Zep | partial: no-op and fixed-value simple memory, in-memory and bounded session-isolated SQLite and PostgreSQL chat history, PostgreSQL storage through an injected `sqldatabase.Engine` usable with compatible Cloud SQL/AlloyDB connections, bounded Zep API v2 chat history with message-window limits, summary/fact system context, API-key auth, and injectable HTTPS transport, conversation buffer with injectable history, typed message snapshots, configurable prefixes, and single-key input/output inference, bounded conversation window buffer, and injected-token-counter memory that evicts complete oldest turns; MongoDB storage is implemented in `memory/mongodb` over an injected collection interface without a bundled driver; Cloud-specific connection/auth helpers remain outstanding |
| `outputparser` | simple, boolean, comma-separated list, regex, regex dictionary, defined/structured, combining | partial: simple, boolean, comma-separated list, regex, regex dictionary, structured string fields, combining string maps, and typed `Defined[T]` for strings, booleans, numbers, primitive options, scalar slices/fixed arrays/string-key maps, nullable scalar slices/fixed arrays/maps, optional scalar slices and string-key maps, nested scalar slices, slices of scalar maps, string-key maps of scalar slices, enums in fields/slices/fixed arrays/string-key maps, nested structs, and slices/fixed arrays/string-key maps of nested structs; optional nested structs and deeper container nesting still need coverage |
| `prompts` | prompt values, string/chat/message templates, template formats/rendering, validation, example selectors, few-shot | partial: validated string placeholders and escaping; role-tagged text chat templates, static few-shot examples, and the injected `ExampleSelector` contract; Go-template (`{{ .name }}` with trim markers) and Jinja variable (`{{ name }}`) string formats are implemented through `prompts.Template` without pipelines, filters, or statements; typed multimodal templates are implemented through `MultimodalPromptTemplate` with text and image URL parts; binary parts are built directly as schema values. LangChainGo exposes only the selector interface in `prompts/example_selector.go`, so concrete selector implementations are outside this parity inventory |
| `schema` | documents, messages, agent actions/steps, memory and retriever contracts, output parser contracts | partial: documents with optional retrieval scores and embeddings, typed multimodal messages, memory/history/retriever contracts |
| `textsplitter` | recursive character, token, Markdown, document splitting and options | partial: recursive character and document splitting; token windows via injected tokenizer; Markdown heading/paragraph/fence/table boundaries, heading hierarchy, and optional source-scanned reference-link rewriting; full CommonMark block fidelity and complete option parity remain outstanding; a built-in dictionary tokenizer (SimpleTokenizer) covers offline token splitting without matching provider encodings |
| `tools` | tool contract/calculator plus integrations below | partial: provider-neutral tool contract, bounded arithmetic calculator for `+`, `-`, `*`, `/`, `%`, `**`, parentheses, and the Starlark math module's functions/constants, bounded Perplexity Sonar search through the OpenAI-compatible chat API, bounded DuckDuckGo HTML search, bounded Wikipedia MediaWiki REST search, bounded SerpApi Google search, bounded Exa (Metaphor successor) semantic search, bounded sequential same-origin HTML crawling, Zapier MCP Streamable HTTP tool discovery/calls, and SQLDatabase table inventory/schema/sample/query APIs over V's SQLite driver with optional PostgreSQL/MySQL drivers; SQL tests use in-memory SQLite, while database driver calls materialize rows before output caps and cannot be interrupted mid-query through `context.Context` |
| `vectorstores` | vector store contract/options, query/add/delete/search, metadata filters, distance strategies, all stores below | partial: add/search/delete contract, options, retriever adapter, bounded process-local cosine-similarity store with optional embedding return, bounded Azure AI Search/Chroma/Dolt/MariaDB/Milvus/OpenSearch/pgvector/Qdrant/Pinecone/Weaviate adapters, and bounded Redis Stack adapter with explicit non-destructive FLAT/HNSW cosine-index creation; Azure AI Search has create-only schema provisioning, Dolt has non-destructive table setup and opt-in approximate index creation, MariaDB has explicit table setup and separately invoked idempotent cosine-index creation, and pgvector has dimensioned-table setup plus separately invoked idempotent HNSW-index creation; persistent stores beyond these and full filter/distance parity remain outstanding |
| `httputil` | shared HTTP client/transport, user-agent, logging transport | partial: injectable default transport with composed user-agent, TLS validation, URL checks, disabled redirects/retries, request/response byte and timeout limits, bounded incremental response callbacks, a chunk-independent SSE decoder, and redacted logging decorators for streaming and non-streaming clients |
| `util` | AlloyDB and Cloud SQL helpers | partial: validated instance connection names and percent-encoded PostgreSQL DSNs through caller supplied hosts in `util/alloydbutil` and `util/cloudsqlutil`; Google connector dialing and IAM token exchange remain the caller's responsibility |
| `testing/llmtest` | LLM provider compliance and test helpers | partial: opt-in core generation and canceled-context checks, with capability checks for multiturn history, streaming chunks/error propagation, tool-call JSON/replay, and typed token usage; includes a configurable concurrency-safe `MockModel` with copied response snapshots; calling `test_model` against a live provider is explicit |
| `exp` | experimental public API surface | not applicable at the pinned snapshot: upstream contains only [`README.md`](https://github.com/tmc/langchaingo/blob/6351d0d03286ba1f8be78b572d88c9b43ed6b869/exp/README.md) and [`doc.go`](https://github.com/tmc/langchaingo/blob/6351d0d03286ba1f8be78b572d88c9b43ed6b869/exp/doc.go), with no Go implementation files |

## LLM providers

| Provider package | Status |
|---|---|
| Anthropic | partial: streaming and non-streaming Messages API client with text/system and bounded image messages, text/thinking deltas, fragmented tool-use JSON, client tool definitions and tool-use responses, stop sequences, adaptive/manual thinking and output-effort provider options, usage mapping, lifecycle callbacks, injectable bounded HTTP transport, and offline fixtures; server tools remain outstanding; reasoning blocks round-trip in both directions with signatures and redacted data, including streamed signature deltas |
| AWS Bedrock | partial: streaming and non-streaming Bedrock Runtime Converse with text, bounded inline JPEG/PNG, client tool definitions/calls/results, fragmented streamed tool input, reasoning deltas, inference controls, token usage, EventStream CRC validation, bearer API-key authentication, lifecycle callbacks, injected bounded transport, and offline fixtures; AWS credential-chain/SigV4 signing and broader model-specific options remain outstanding; reasoning content round-trips with text, signatures, and redacted data in both directions |
| Cloudflare | partial: Workers AI OpenAI-compatible Chat Completions and embeddings routes, required account/model configuration, `max_tokens` translation, synchronous `options.rejectIfBusy`, common message/tool behavior, bounded injectable transport, and offline tests; chat streaming passes through streaming-capable transports |
| Cohere | partial: bounded streaming and non-streaming Chat API v2 text generation, streamed function tool calls, sampling and stop controls, function tool calls and replay, JSON object mode, usage accounting, lifecycle callbacks, and injectable offline transport; image input, reasoning replay, provider extensions, and named tool selection remain outstanding. This uses the current `/v2/chat` API because Cohere marks the upstream adapter's `/v1/generate` endpoint deprecated. |
| ERNIE | partial: current Baidu Qianfan v2 OpenAI-compatible chat with configurable model/base URL, shared message/tool/JSON/options support, streaming-capable transport, bounded transport, and fake-transport tests; legacy AK/SK token exchange, legacy routes, embeddings, and provider-specific controls remain outstanding |
| Google AI / Gemini | partial: bounded streaming and non-streaming `generateContent` / `streamGenerateContent` SSE for text and function calls, system instructions, inline images, function declarations/calls/results, generation controls, candidate count, seed, JSON MIME and JSON-Schema structured output, finish reasons, usage mapping, lifecycle callbacks, `countTokens` through the shared `llms.TokenCounter` interface, remote image URLs as validated HTTPS or gs:// `fileData` parts, Gemini `batchEmbedContents`, and injectable HTTPS transports |
| Google Vertex AI | partial: Gemini text/image/tool generation, JSON-Schema structured output, streaming, and `countTokens` behavior reused from the shared Google AI client through a Vertex REST route and explicit OAuth bearer-token transport; automatic Application Default Credentials discovery/refresh and Vertex-specific features remain outstanding |
| Hugging Face | partial: current OpenAI-compatible Inference Providers chat router with required model/provider selection, common message/tool behavior, `max_tokens` translation, bounded injectable HTTP transport, and offline tests; chat streaming passes through streaming-capable transports, while the legacy inference route and provider-specific options remain outstanding |
| llamafile | partial: current OpenAI-compatible Chat Completions endpoint, loopback default, HTTPS custom endpoints, shared OpenAI request/response, streaming, and tool handling, bounded injectable transport, and offline fixtures; upstream legacy `/completion` and `/embedding` APIs and llama.cpp-specific options remain outstanding |
| local | partial: executable-backed completion/chat client using `LOCAL_LLM_BIN` / `LOCAL_LLM_ARGS` or explicit options, literal argument passing without a shell, bounded prompt/arguments/output, common generation flags, callbacks, and context cancellation that kills the process group; tests use only small local system utilities, not model binaries |
| Maritaca | partial: current OpenAI-compatible Chat Completions using the shared message/tool/JSON/options and streaming implementation, configurable endpoint/model, bounded transport, and fake-transport tests; Responses API and provider-specific options remain outstanding |
| Mistral | partial: OpenAI-compatible Chat Completions using the shared request/response implementation, with translation for Mistral's `max_tokens` and `random_seed` fields in regular and streamed requests, regional base URL/model configuration, and fake-transport tests; native Mistral options and provider-specific behavior beyond those field mappings remain outstanding |
| Ollama | partial: streaming and non-streaming `/api/chat` with bounded NDJSON, text/reasoning callbacks, text and bounded inline images, tool definitions/results, JSON mode and JSON-Schema-valued `format`, common generation options, typed and validated current API runner/chat options through `CallOptions.provider_options`, thinking replay, usage accounting, lifecycle callbacks, `/api/embed` client, and injectable offline-tested transports; bounded model management (list, show, pull without streaming progress, and delete through local management endpoints) is implemented; legacy runner fields are version-gated and sent only after an exact `/api/version` match for verified versions 0.1.34+ (`num_gqa` before 0.1.39, `numa` before 0.4.0, `tfs_z` and `penalize_newline` before 0.5.12, and Mirostat/runner switches before 0.7.0); a live check against a matching historical server remains outstanding in [#145](https://github.com/ulises-jeremias/langchainv/issues/145); opt-in model pulling with caller-context timeout is implemented; `llms.CompletionModel` uses prompt-oriented `/api/generate` with bounded NDJSON, text/reasoning callbacks, validated generation options, usage and stop mapping, JSON mode, and offline transport tests |
| OpenAI | partial: Chat Completions streaming and non-streaming, completion adapter, text and image messages, function tools, JSON object mode and typed JSON Schema response formats, usage, reasoning fields, and lifecycle callbacks; streaming requires a streaming-capable transport; typed provider options (user, parallel_tool_calls, service_tier, logprobs, top_logprobs) are validated and sent, while richer reasoning replay and the Responses API remain outstanding |
| IBM watsonx | partial: bounded streaming and non-streaming text generation over the current versioned REST endpoints, SSE text chunks and stop/usage mapping, IAM bearer-token auth, explicit tokens or API-key exchange and cached renewal, API-key/project environment fallbacks, project/model selection, supported sampling and stop options, bounded injectable transport, and offline tests; multimodal/chat history, reasoning streams, and multiple candidates remain outstanding |

## Embedding providers

OpenAI — partial: JSON float requests, configurable model/base URL/dimensions,
input-order restoration, and injected HTTP transport. Mistral — partial:
bounded JSON float requests to `/v1/embeddings`, default `mistral-embed` model,
configurable model/base URL/output dimension, response-index restoration,
vector validation, and injected transport. Jina — partial: bounded
JSON float requests, configurable model/base URL, task, dimensions, and
late-chunking options, response-order restoration, and injected HTTP
transport; asynchronous batches remain outstanding. VoyageAI — partial: bounded JSON float requests, configurable
model/base URL, query/document input modes, output dimensions, truncation
control, and injected HTTP transport. Ollama — partial: batched
`/api/embed`, configurable model/base URL, input and response limits, vector
shape validation, injected HTTP transport, and opt-in model pull with a
caller-context timeout. Google AI — partial: batched
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

Dedicated AlloyDB and Cloud SQL adapters, Bedrock Knowledge Bases, and MongoDB
vector search is implemented in `vectorstores/mongodb` over an injected collection interface with a bounded in-process cosine scan (not Atlas $vectorSearch). The generic pgvector adapter can
connect to Cloud SQL for PostgreSQL or AlloyDB when the application supplies a
compatible PostgreSQL engine and matching `vector` schema; it does not provide
Cloud-specific connection/authentication, embedding, indexing, or query APIs.
Dolt is partial: bounded parameterized inserts/search/deletes through an
injected MySQL-compatible engine, scalar JSON metadata equality, collection
namespaces, squared-Euclidean score mapping, and opt-in vector return. Its
non-destructive table initializer and separately invoked approximate JSON
vector-index creation do not migrate existing schemas; Dolt's vector index is
version-dependent and may trade recall for speed. MariaDB is partial: bounded parameterized inserts through
`VEC_FromText`, cosine search through `VEC_DISTANCE_COSINE`, parameterized ID
deletion, namespace and scalar JSON equality filters, injected embeddings/SQL
engine, optional validated vector return through `VEC_ToText`, and bounded
payloads against MariaDB 11.7.1+ vector tables; explicit non-destructive table
initialization and a separately invoked, idempotent cosine vector-index build
are supported. Schema migration, index replacement, non-scalar or advanced
filters, and alternate distance strategies remain outstanding. Azure AI Search is partial: bounded document upload,
vector search and key deletion against an existing index, with injected
embeddings/HTTP transport, API-key authentication, namespace filtering and
indexing-result validation. It requires configured key/content/vector/metadata/
namespace fields; metadata is stored as JSON text, and `SearchOptions.include_vectors`
returns dimension-checked finite vectors when the index vector field is
retrievable. Explicit create-only provisioning of the configured cosine HNSW
schema is supported; the existing index is never updated by this helper.
Metadata predicates, arbitrary index schemas, index updates/deletion, and
broader query/filter parity remain unsupported.
Chroma — partial: v2 REST create/get-or-create and
delete collection management, upsert/query/delete, injected embeddings and
HTTP transport, loopback HTTP or remote HTTPS, token authentication, scalar
equality filters, namespaces, score thresholds, and bounded payloads; custom
collection configuration, array metadata, advanced filters, and custom IDs
remain outstanding; `SearchOptions.include_vectors` returns validated stored
embeddings on similarity queries. Qdrant — partial: REST
create/delete and upsert/query/delete for single-vector cosine collections,
API-key or HTTPS authentication, payload metadata filters, namespaces, injected
embeddings/transport, and bounded requests with preflight embedding-dimension
validation for newly created collections; `SearchOptions.include_vectors`
returns validated vectors from single-vector collections. Named or multi-vector
search remains outstanding; caller point IDs are accepted as UUID strings in
the `id` metadata entry and consumed instead of echoed as metadata; filters support equality,
range, membership, existence, and bounded $and/$or/$not condition groups.
Pinecone — partial: HTTPS upsert/query/delete against
provisioned index hosts, API-key auth, namespaces, metadata filters with equality,
comparison, membership, existence, and bounded $and/$or operator objects,
injected embeddings/transport, and bounded requests; index management,
sparse/hybrid vectors, and integrated text inference remain outstanding; `SearchOptions.include_vectors` returns validated values
when requested.
Milvus — partial: REST v2 insert/search/delete against an existing collection,
bearer-token auth, scalar metadata equality filters, namespaces, COSINE/IP/L2
metric selection, injected embeddings/transport, and bounded requests; schema
management, collection administration, advanced filters remain outstanding; minimum-score
filtering applies to every metric, as a maximum-distance threshold for L2; `SearchOptions.include_vectors` returns
validated vectors when requested.
OpenSearch — partial: bulk index/search/delete against an existing k-NN index,
API-key or basic authentication, metadata filters with term, terms, range,
exists, and bounded logical operator objects, namespaces, cosine scores,
injected embeddings/transport, and bounded requests; index
replacement/migration and alternate metrics remain outstanding; `SearchOptions.include_vectors` returns validated vectors when
requested. Explicit initialization creates a cosine k-NN mapping but does not
manage, replace, or migrate existing indexes.
pgvector — partial: parameterized insert/search/delete against an existing
PostgreSQL table, cosine distance and scores, scalar JSONB equality filters,
namespaces, injected embeddings/SQL engine, and bounded requests; schema/index
initialization for a dimensioned table and a separately invoked idempotent
cosine HNSW index creation are supported; table migration, index replacement,
alternate distance strategies, and advanced filters remain outstanding.
`SearchOptions.include_vectors` returns validated vectors when requested.
Redis — partial: HSET document writes and RediSearch KNN over a HASH index,
explicit non-destructive FLAT or HNSW/COSINE index creation, bounded HNSW
construction parameters, cosine scores, exact scalar TAG filters, namespaces,
namespace-constrained per-key deletion, injected embeddings and Redis command
client, and bounded requests; index
deletion/reconfiguration, alternate distance strategies, and advanced filter
syntax remain outstanding;
`SearchOptions.include_vectors` returns validated stored vectors when requested.
Weaviate — partial: batch object upsert and delete against a provisioned class,
GraphQL near-vector and metadata searches, namespaces, scalar equality filters,
certainty thresholds, injected embeddings/transport, and bounded requests;
class/schema management remains outstanding; filters support equality, comparison, ContainsAny membership, IsNull existence, and bounded $and/$or operator objects;
`SearchOptions.include_vectors` returns validated vectors when requested.

## Document loaders and tools

- PDF loading extracts one document per page with page metadata and bounded splitting through Poppler `pdftotext`; input/output/page-count limits, timeout, cancellation, and recursive-directory integration are covered. Encrypted PDFs requiring passwords remain unsupported because the CLI exposes passwords in process arguments. CI installs `poppler-utils`; consumers need `pdftotext` on `PATH` or may configure its executable path. AssemblyAI provides bounded HTTPS URL submission and status polling with injectable HTTP and offline tests. HTML uses V's standard-library parser; full browser-style parsing and network fetching are outside its scope.
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
