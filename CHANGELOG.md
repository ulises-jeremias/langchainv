# Changelog

All notable changes to LangChainV are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
uses conventional commit prefixes in its history.

## [Unreleased]

### Added

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
