---
layout: default
title: Production guide
permalink: /production/
---

# Production guide

LangChainV provides bounded adapters and composable primitives, but a package
marked `partial` in the [parity ledger]({{ '/reference/' | relative_url }}) has
known gaps. Treat each adapter's README as its capability contract, then use
this guide to review the application boundaries around it. A green test suite
does not replace workload testing against the database, model, or service you
plan to operate.

## Protect credentials and user data

- Load API keys and database credentials from a secret manager or process
  environment. Do not commit them, include them in prompts, or place them in
  error messages.
- Minimize the personal or confidential data sent to model providers. Check
  provider retention and regional processing terms for the model and account
  you selected.
- The built-in `callbacks.LogHandler` writes prompts, model responses, tool
  inputs and outputs, and chain values to standard output. Use it only when
  those values are safe to retain. `httputil.new_logging_client` records
  request metadata without paths, headers, bodies, or error text; it does not
  replace application-level audit logging.
- Treat tool calls and model output as untrusted input. Validate structured
  output before using it, and put authorization checks in the application
  before a tool can read or change external state.

Read the [security policy](https://github.com/ulises-jeremias/langchainv/blob/main/SECURITY.md)
before deploying a new integration.

## Set resource and spend limits

Bound input size, retrieved context, output size, number of documents, and
agent iterations for each workload. The defaults are starting points; raising
a limit raises the maximum work one request can trigger.

The shared HTTP client defaults to a 30-second timeout, an 8 MiB request limit,
and a 16 MiB response limit. It validates TLS, disallows URL userinfo, and
does not follow redirects or retry requests automatically. Provider adapters
may use additional endpoint-specific limits; see their package guides.

Document chains default to at most 16 documents per call and commonly cap
source or mapped text at 64 KiB. The executor defaults to 15 agent iterations.
SQL tool results default to 256 rows and 64 KiB of formatted output. Review the
relevant `Options` type and choose smaller workload-specific bounds where
possible. These byte and item limits do not estimate token counts, guarantee a
provider's maximum context, or cap provider charges. Use a model-specific token
counter when you need a token-based memory window.

## Design around cancellation and retries

Pass the caller's `context.Context` into each model, chain, retriever, and tool
call. Most long-running loops check it between steps. The standard HTTP client
checks cancellation before and after `net.http.fetch`, but an in-flight fetch
is bounded by its timeout rather than interrupted by the context. SQL driver
calls can likewise finish before cancellation is observed. Add an application
deadline and choose timeout values with these boundaries in mind.

The shared HTTP client does not retry automatically. If the application adds
retries, restrict them to operations that are safe to repeat and use a bounded
attempt count, elapsed-time budget, and backoff. A timeout does not prove the
remote service did no work. Do not blindly retry a request that may have
persisted data or exposed part of a streamed response.

Streaming depends on the provider adapter and a streaming-capable transport.
Check the provider guide before enabling it. Once chunks have reached a client,
the operation is no longer transparently repeatable; report interruption and
let the caller decide whether to restart.

## Keep tools and database access narrow

- Give SQL tools an application-controlled, least-privilege database account.
  The SQL query helper can execute statements on the supplied engine; output
  caps limit returned formatting but do not make a write-capable database
  account read-only. Do not pass raw end-user SQL to it without a separate
  authorization and validation layer.
- Register only tools needed for a workflow. The agent executor bounds its
  iterations, but it does not automatically authorize a tool action or discover
  tools safely on your behalf.
- Keep database schema setup, index creation, and other resource-intensive
  operations in an explicit deployment or maintenance step. Several vector
  store adapters intentionally require an existing index or collection.
- Namespace records by tenant where the store supports it, and verify the
  adapter-specific delete behavior before exposing deletion to users.

## Validate changes without live services

Use deterministic fake models and injected HTTP transports for routine tests.
`testing/llmtest` can call a live model, so only use that mode when the test is
explicitly configured for a provider and the request cost and data transfer are
acceptable. Service-backed checks should use a dedicated test database or
container and must not share production credentials or data.

Before release:

1. Run the [offline examples](https://github.com/ulises-jeremias/langchainv/tree/main/examples)
   and focused tests for the packages you use.
2. Check the [provider catalog]({{ '/providers/' | relative_url }}) for
   streaming support, authentication, provisioning, and request limits.
3. Review the [parity ledger]({{ '/reference/' | relative_url }}) and package
   README for unsupported options or operational caveats.
4. Exercise cancellation, oversized input, malformed provider output, service
   timeouts, and partial failure in an environment with production-like limits.
5. Verify logs and metrics do not retain secrets, prompts, retrieved documents,
   tool arguments, or model output unless that storage is explicitly approved.

## Related guides

- [Security policy](https://github.com/ulises-jeremias/langchainv/blob/main/SECURITY.md)
- [HTTP transport](https://github.com/ulises-jeremias/langchainv/blob/main/httputil/README.md)
- [Model contract and callbacks](https://github.com/ulises-jeremias/langchainv/blob/main/llms/README.md)
- [SQL database tool](https://github.com/ulises-jeremias/langchainv/blob/main/tools/sqldatabase/README.md)
- [Contribution and CI workflow](https://github.com/ulises-jeremias/langchainv/blob/main/CONTRIBUTING.md)
