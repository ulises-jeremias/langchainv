# Changelog

All notable changes to LangChainV are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
uses conventional commit prefixes in its history.

## [Unreleased]

### Added

- More `Defined` field types in `outputparser`: optional scalar slices and
  maps, nested scalar slices, slices of scalar maps, and maps of scalar
  slices, in generated schemas and typed decoding.

- Lifecycle callbacks on the Bedrock client, and on the six OpenAI-compatible
  wrappers (Mistral, ERNIE, Maritaca, Hugging Face, Cloudflare, llamafile),
  which forward a handler from their own Options to the shared OpenAI client.
  Every built-in provider adapter now exposes generate-content callbacks.
- Lifecycle callbacks on the Google AI and Ollama clients, following the
  same pattern. Vertex keeps its own handler and does not double-dispatch.
- Lifecycle callbacks on the Anthropic and Cohere clients, following the
  OpenAI pattern: start, end, and error events around `generate_content`.
- Lifecycle callbacks on the OpenAI client: a `callbacks.Handler` set
  through `Options` or the client field receives generate-content start,
  end, and error events.

- JSON Schema composition in `jsonschema`: `all_of`, `any_of`, `one_of`, and
  `not` on `Definition`, plus string `format` names, all encoded and
  enforced during instance validation.

- Alternate string template formats in `prompts`: `prompts.Template` renders
  Go-template and Jinja variable syntax alongside the existing f-string
  format, with strict rejection of filters and statements.

- Agent executor parsing-error recovery: with `handle_parsing_errors`, a
  failed plan becomes a bounded `_invalid_output` step and the agent retries
  within the iteration limit instead of failing the run.
- SQL database chain in `chains`: generates one read-only query, runs it,
  and answers from the result, with optional intermediate steps.
- Gemini `countTokens` support in the Google AI and Vertex clients through
  the shared `llms.TokenCounter` interface.
- OpenAI JSON Schema response formats, Gemini JSON-Schema structured
  output, and Ollama JSON-Schema output format.

### Changed

- README rebuilt with workflow badges, an offline quick start, and
  capability, provider, and documentation tables.

## [0.1.0]

First tracked state of the module: framework packages for chains, agents,
prompts, output parsing, memory, document loaders, text splitting, tools,
and vector stores, with 15 chat providers, 7 embedding providers, and 12
vector store adapters, all tested offline with fake transports.
