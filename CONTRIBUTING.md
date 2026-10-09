# Contributing

LangChainV is built in the open. Contributions should preserve idiomatic V
APIs and move a documented item in the parity ledger toward completion.

## Before changing code

1. Read the root `README.md`, `AGENTS.md`, and the relevant `docs/` pages.
2. Pick a focused package or feature and identify its upstream behavior in
   `docs/LANGCHAINGO_PARITY.md`.
3. Keep the public API small, use `snake_case`, return errors explicitly, and
   propagate cancellation/deadlines through network or long-running work.
4. Keep optional integrations isolated. Core packages must build without
   credentials, databases, external C libraries, VSL, or VTL.

## V coding conventions

- Run `v fmt -w` on changed V source before review; CI checks formatting.
- Add clear doc comments to public functions and types.
- Keep functions focused and validate invalid inputs at API boundaries.
- Use the nearest established V patterns for `!` results, mutability,
  ownership, and cleanup.
- Do not add `unsafe` or native dependencies without a documented reason.

## Safe local validation

Run one V process at a time, with a memory cap and low `VJOBS`. Example shape:

```sh
systemd-run --user --scope --property=MemoryMax=2G \
  --property=MemorySwapMax=0 --setenv=VJOBS=1 -- \
  v -shared -check schema
```

Use focused checks for the changed package. Do not run a full local suite;
CI runs the full matrix in bounded jobs. If a command is killed by memory
limits, record it as unverified and reduce the workload before trying again.
Do not run live provider calls or incur API charges in routine validation.

## Provider and backend integrations

- Implement the common contract first, then isolate each provider adapter.
- Share a bounded HTTP transport with explicit timeout and user-agent policy.
- Test chunked streaming parsers across arbitrary chunk boundaries.
- Redact credentials from errors, logs, and committed fixtures.
- Use deterministic HTTP fixtures; integration tests that need credentials or
  services must be opt-in and documented.
- Keep VSL/VTL numerical adapters optional and isolated.

## Pull requests

- Make one logical change per commit and use an imperative subject such as
  `llms: add OpenAI chat streaming` or `docs: record provider parity`.
- Include implementation, scoped validation evidence, user docs/examples, and
  parity ledger updates together.
- Request human review before merge. A local compile or partial check does not
  establish full upstream parity.
