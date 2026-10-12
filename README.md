# LangChainV

LangChainV is a composable framework for building applications with language
models in V. Its target is feature parity with the public LangChainGo API, with
V-native interfaces, errors, options, and resource handling.

The shared core contracts are the first implementation slice. The parity
matrix in [`docs/LANGCHAINGO_PARITY.md`](docs/LANGCHAINGO_PARITY.md) is the
source of truth for supported and outstanding features. A package is supported
only when its implementation and documented validation are complete.

## Documentation

Visit the [LangChainV documentation site](https://ulises-jeremias.github.io/langchainv/)
for the quick start, tutorials, component map, searchable generated
[API reference](https://ulises-jeremias.github.io/langchainv/api/), and
compatibility reference.
The [`examples/`](examples/) directory contains standalone programs; the
[example catalog](examples/README.md) lists their requirements.

## Install

```sh
v install ulises-jeremias.langchainv
```

V normalizes the import prefix to `ulises_jeremias.langchainv`:

```v
import ulises_jeremias.langchainv
```

The current core packages include:

- `schema`: documents, multimodal messages, and shared interfaces.
- `llms`: model contracts, provider-neutral lifecycle middleware, provider-neutral generation results, OpenAI Chat Completions, llamafile's OpenAI-compatible local API, an explicitly configured local executable adapter, Amazon Bedrock Converse, Anthropic Messages, Cohere Chat, Baidu Qianfan v2, Maritaca Chat Completions, Mistral Chat Completions, Hugging Face Inference Providers chat, Cloudflare Workers AI chat, Ollama chat, Gemini text/image/function-tool generation, Vertex AI Gemini generation with explicit OAuth access tokens, and watsonx.ai text generation with IBM API-key exchange or explicit IAM tokens.
- `embeddings`: provider client adapter, bounded batching, vector aggregation, vector math, and OpenAI, Ollama, Google AI, Jina, Voyage AI, Hugging Face, and Bedrock embeddings.
- `httputil`: injectable provider HTTP transport with timeouts, TLS validation, and body limits.
- `tools`: agent tool contract, bounded arithmetic calculator, search and web tools, Zapier MCP, and SQL database inspection/query helpers.
- `testing/llmtest`: opt-in model contract checks for generation, cancellation, multiturn, streaming, tool calls, and usage, plus a concurrency-safe mock model.
- `memory`: no-op memory, in-memory and bounded session-specific SQLite chat history, conversation buffer, bounded window buffer, and token-bounded buffer with an injected counter.
- `prompts`: validated string templates, role-tagged chat templates, and fixed- or selector-backed few-shot prompts.
- `outputparser`: string, boolean, list, regex, structured, combining, and
  typed JSON parsers.
- `jsonschema`: a validated, recursive subset for tool parameter schemas.
- `chains`: prompt-backed completion and chat-model chains, document stuffing,
  sequential map-reduce, map-rerank and refine, constitutional critique and
  revision, retrieval QA, sequential composition, memory loading, bounded
  conversational retrieval QA, and input/output validation.
- `agents`: text-based MRKL/ReAct, conversational ReAct, and model tool-calling
  agents, plus a bounded executor with tool dispatch, callbacks, memory
  integration, and optional intermediate-step output.
- `callbacks`: chat/completion lifecycle event contract, ordered dispatch, no-op and standard
  output logging handlers, final-answer streaming, and handler composition.
- `vectorstores`: storage contract, retriever adapter, bounded in-memory cosine store, and Chroma, Milvus, OpenSearch, pgvector, Redis Stack, Qdrant, Pinecone, and Weaviate integrations.
- `documentloaders`: size-bounded PDF, HTML, text-file, and CSV content loaders
  plus a bounded recursive directory loader for those file types. PDF extraction
  requires Poppler's `pdftotext` executable.
- `textsplitter`: recursive character and tokenizer-injected token chunks, plus
  Markdown-aware heading, paragraph, fenced-code, table-row, and optional
  reference-link splitting.

Provider and component packages use nested import paths such as
`ulises_jeremias.langchainv.llms.openai`.

The shared [`llms` guide](llms/README.md) documents the model contract and
provider-neutral callback middleware. The [provider catalog](docs/providers.md)
lists adapter setup guides and current capabilities.

See [`textsplitter/README.md`](textsplitter/README.md) for chunking options and
the tokenizer interface.

See [`outputparser/README.md`](outputparser/README.md) for parser behavior and
the current V regular-expression compatibility boundary.

See [`callbacks/README.md`](callbacks/README.md) for lifecycle logging and
bounded final-answer streaming.

See [`memory/README.md`](memory/README.md) for full and windowed conversation memory.

See [`chains/README.md`](chains/README.md) for the completion-model chain API.

See [`embeddings/openai/README.md`](embeddings/openai/README.md) for the
OpenAI embeddings client and its injectable HTTP transport.

See [`embeddings/ollama/README.md`](embeddings/ollama/README.md) for the
Ollama embeddings client and its injectable HTTP transport.

See [`embeddings/googleai/README.md`](embeddings/googleai/README.md) for the
Gemini batch embeddings client and its injectable HTTP transport.

See [`embeddings/jina/README.md`](embeddings/jina/README.md) for the Jina text
embeddings client and its injectable HTTP transport.

See [`embeddings/voyageai/README.md`](embeddings/voyageai/README.md) for the
Voyage AI client and its query/document-specific input modes.

See [`embeddings/huggingface/README.md`](embeddings/huggingface/README.md) for
the Hugging Face feature-extraction client and its injectable transport.

See [`embeddings/bedrock/README.md`](embeddings/bedrock/README.md) for Titan and
Cohere embeddings through Bedrock Runtime with API-key authentication.

See [`llms/openai/README.md`](llms/openai/README.md) for OpenAI chat generation,
tool calls, and multimodal image inputs.

See [`llms/llamafile/README.md`](llms/llamafile/README.md) for local llamafile
chat through its OpenAI-compatible API.

See [`llms/local/README.md`](llms/local/README.md) for running an explicitly
configured local executable with bounded arguments/output and context cancellation.

See [`llms/vertex/README.md`](llms/vertex/README.md) for Gemini generation on
Vertex AI using an explicitly supplied OAuth access token.

See [`llms/watsonx/README.md`](llms/watsonx/README.md) for watsonx.ai text
generation using an API key or an explicitly supplied IAM access token.

See [`llms/bedrock/README.md`](llms/bedrock/README.md) for Amazon Bedrock
Converse chat, tool use, images, and API-key authentication details.

See [`llms/anthropic/README.md`](llms/anthropic/README.md) for Anthropic
Messages, tool use, and its supported options.

See [`llms/cohere/README.md`](llms/cohere/README.md) for Cohere Chat API v2,
function tools, and its supported options.

See [`llms/ernie/README.md`](llms/ernie/README.md) for Baidu Qianfan v2 chat.

See [`llms/maritaca/README.md`](llms/maritaca/README.md) for Maritaca Chat
Completions.

See [`llms/mistral/README.md`](llms/mistral/README.md) for Mistral's
OpenAI-compatible Chat Completions adapter.

See [`llms/huggingface/README.md`](llms/huggingface/README.md) for Hugging Face
Inference Providers chat via its OpenAI-compatible router.

See [`llms/cloudflare/README.md`](llms/cloudflare/README.md) for Cloudflare
Workers AI Chat Completions.

See [`llms/ollama/README.md`](llms/ollama/README.md) for local Ollama chat,
multimodal inputs, and its supported options.

See [`llms/googleai/README.md`](llms/googleai/README.md) for Gemini text
generation and its supported options.

See [`vectorstores/qdrant/README.md`](vectorstores/qdrant/README.md) for the
Qdrant REST adapter and its collection requirements.

See [`vectorstores/pinecone/README.md`](vectorstores/pinecone/README.md) for the
Pinecone index host and metadata requirements.

See [`vectorstores/weaviate/README.md`](vectorstores/weaviate/README.md) for
Weaviate class, namespace, and filter requirements.

See [`vectorstores/milvus/README.md`](vectorstores/milvus/README.md) for the
Milvus REST v2 adapter and collection schema requirements.

See [`vectorstores/opensearch/README.md`](vectorstores/opensearch/README.md) for
the OpenSearch k-NN REST adapter and index mapping requirements.

See [`vectorstores/pgvector/README.md`](vectorstores/pgvector/README.md) for the
PostgreSQL pgvector adapter and existing table schema requirements.
See [`vectorstores/redis/README.md`](vectorstores/redis/README.md) for Redis
Stack index setup, HASH fields, and adapter limits.

## Compatibility

- V 0.5.2 or newer, subject to compiler compatibility notes in the docs.
- Core packages are designed to use V's standard library without mandatory
  third-party dependencies.
- Optional integrations may use VSL or VTL when that is the best V-native
  backend; those dependencies will remain isolated to their adapters.

## Project status

LangChainGo has a broad integration surface. This project tracks its APIs and
integrations explicitly rather than implying full compatibility from a small
set of working examples. See [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md)
and [`docs/LANGCHAINGO_PARITY.md`](docs/LANGCHAINGO_PARITY.md).

## License

MIT. See [LICENSE](LICENSE).
