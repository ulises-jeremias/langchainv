# LangChainV implementation plan

## Objective

Implement the public functionality exposed by `tmc/langchaingo` in idiomatic V,
published as `ulises-jeremias/langchainv` and installable with
`v install ulises-jeremias.langchainv`. The upstream source is the behavioral
reference; this project will use an original V implementation and will not
copy Go source. The parity matrix records every upstream package family and
integration so completion can be audited.

## Design rules

1. Define stable, small core contracts before provider implementations.
2. Keep each provider, database, vector store, and external service in its own
   adapter package. Importing core must not pull provider SDKs or optional
   VSL/VTL dependencies.
3. Use V `!` result propagation and explicit domain errors; do not hide errors
   behind default values.
4. Propagate cancellation and deadlines through network, chain, agent, and
   streaming operations. Use `context`/`sync` primitives available in the
   pinned V standard library where their contracts fit.
5. Centralize HTTP defaults, headers, timeout policy, safe error rendering,
   retries, and streaming/SSE parsing. Never log credentials or raw secret
   request fields.
6. Keep network interactions reproducible through local HTTP fixtures and
   provider compliance contracts. Separate offline checks from tests requiring
   credentials, databases, containers, or network access.
7. Document V 0.5.x generic limitations and provide explicit free functions
   when methods cannot introduce type parameters.
8. Keep the package import prefix consistent with VPM normalization:
   `ulises_jeremias.langchainv`.

## Delivery phases and completion gates

### Phase 0 — Source inventory and architecture

- Record the exact upstream commit and enumerate public package families,
  providers, stores, loaders, and APIs.
- Inventory usable V standard-library modules at the compiler's matching V
  commit.
- Define core contracts, package boundaries, compatibility rules, and a
  feature-level parity ledger.

**Gate:** every public upstream package and integration appears in the ledger;
no implementation status is inferred from package existence.

### Phase 1 — Core contracts and developer experience

- Implement documents, messages, model and embedding contracts, prompt values,
  chain inputs/outputs, memory, retrievers, vector-store contracts, tools,
  callbacks, errors, and shared options.
- Add deterministic fakes, provider compliance helpers, test fixtures, and
  runnable minimal examples.
- Establish module metadata, formatting, docs checks, and bounded CI.

**Gate:** core workflows compose without a network provider; public APIs have
clear ownership, error behavior, and examples.

### Phase 2 — Framework primitives

- Implement prompt templates and selectors, output parsers, text splitters,
  chains, callbacks, memories, agents/executors, and JSON schema support.
- Preserve each upstream component's input/output semantics and edge cases.

**Gate:** per-component behavior is checked against upstream contracts and
fixtures, including invalid inputs, streaming, cancellation, and errors.

### Phase 3 — Model and embedding integrations

- Implement every provider listed in the parity ledger behind common interfaces.
- Cover chat and completion APIs, tool/function calling, structured output,
  token usage, reasoning, caching, streaming, provider options, and errors as
  supported by each upstream package.

**Gate:** every provider has compliance coverage, deterministic request/response
fixtures, redacted secrets, and a documented capabilities table.

### Phase 4 — Retrieval and data integrations

- Implement document loaders, tools, vector stores, persistent memories, SQL
  database access, and optional VSL/VTL adapters.
- Cover metadata filters, distance strategies, batching, pagination, retries,
  and cleanup semantics for each backend.

**Gate:** offline tests cover common contracts; service-backed suites are
isolated and have reproducible container/service setup.

### Phase 5 — Parity audit and release readiness

- Compare all public upstream symbols, options, edge cases, examples, and
  integrations against the parity ledger.
- Finish API docs, migration guide, security policy, release automation, package
  installation validation, and platform CI.

**Gate:** every ledger entry has implementation evidence and validation; CI
passes on the supported platform matrix; a clean VPM install and import works.

## Work tracking

This is intentionally a multi-stage project. Update
[`LANGCHAINGO_PARITY.md`](LANGCHAINGO_PARITY.md) alongside every implementation
change, and keep completed, partial, and unavailable behavior distinct.

## Evidence snapshot

- LangChainGo source tree inspected at commit
  `039fbb6c6469a8ffcdae615ec7bdc465c83abadc` (`main`, GitHub tree returned on
  2026-10-09; 1,500 entries in the tree).
- Workstation V standard library inspected at commit
  `407c52edddca9715fb57e6571afeef0d193f2465` (V 0.5.2), then compared with
  upstream `master` at `a6826c4db0e28d306160fcc9e96baca90ea78f40` on
  2026-10-09. Both trees have 65 module directories, 62 module-level READMEs,
  and 182 recursive READMEs. The intervening three commits changed 15 paths
  under `vlib/`, limited to a built-in implementation and compiler internals,
  tests, and help files; module coverage is unchanged.
- Source references: <https://github.com/tmc/langchaingo> and
  <https://github.com/vlang/v/tree/master/vlib>.
