---
layout: default
title: API and compatibility reference
permalink: /reference/
---

# API and compatibility reference

LangChainV's API is documented at the package boundary in each README and V source comments. Browse the [component map](../components/) for package guides.

Browse the [generated API reference](../api/) for public symbols, module
navigation, and symbol search. Pages builds regenerate it from the same pinned
V compiler used by CI. This page tracks compatibility and project status; the
generated reference describes the current source API.

## LangChainGo compatibility

The [parity ledger](https://github.com/ulises-jeremias/langchainv/blob/main/docs/LANGCHAINGO_PARITY.md) compares public package scope and records partial or missing behavior. Its upstream snapshot was recorded in that document; upstream changes over time, so the snapshot date matters. Do not interpret a provider or package existing as full compatibility.

## V standard library catalog

The [V library catalog](https://github.com/ulises-jeremias/langchainv/blob/main/docs/VLIB_CATALOG.md) records standard-library options considered for current integrations.

## Development plan

The [implementation plan](https://github.com/ulises-jeremias/langchainv/blob/main/docs/IMPLEMENTATION_PLAN.md) tracks release readiness and cross-cutting work. For machine-safe local checks and CI expectations, see [CONTRIBUTING.md](https://github.com/ulises-jeremias/langchainv/blob/main/CONTRIBUTING.md) and [AGENTS.md](https://github.com/ulises-jeremias/langchainv/blob/main/AGENTS.md).

## Version and support

- Module: `ulises-jeremias.langchainv`
- Import root: `ulises_jeremias.langchainv`
- Minimum documented compiler: V 0.5.2; compiler compatibility notes are tracked in the repository.
- CI pins a V compiler commit and runs deterministic package checks without provider credentials.
