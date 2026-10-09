# Repository instructions

## Project contract

- Implement and track parity with the upstream package inventory in
  [`docs/LANGCHAINGO_PARITY.md`](docs/LANGCHAINGO_PARITY.md).
- Update the ledger and relevant docs with every public API change.
- Keep provider, model, database, loader, tool, and vector-store integrations in
  isolated packages. Core imports must not require optional native libraries.
- Use V 0.5.x-compatible syntax and document compiler limitations when they
  affect API shape. Public names use `snake_case`.
- Do not copy Go implementation source. Use upstream behavior and API contracts
  as references, then implement them in V.
- Never commit without a code review.

## Safe V commands

V compilation can create many compiler processes and use substantial memory.
Run one V command at a time. Do not run full `v test .` suites on the
workstation; full-suite coverage belongs in bounded CI jobs.

For local checks, use a focused file or package and a systemd memory scope, for
example:

```sh
systemd-run --user --scope --property=MemoryMax=2G \
  --property=MemorySwapMax=0 --setenv=VJOBS=1 -- \
  v -shared -check schema
```

Choose a limit based on measured needs, keep `VJOBS` low, and stop if memory
pressure rises. An OOM kill or signal is not a passing check; reduce the scope
or run it in CI. Do not retry the same memory-heavy command unchanged.

Before a local V invocation, confirm no other V compiler is active with
`pgrep -a -x v`. Never terminate unrelated compiler processes. Keep temporary
build and generated files inside the repository or an explicitly bounded temp
directory.

## Validation and review

- Read the package-specific docs and adjacent implementation before editing.
- Prefer the smallest relevant formatter, checker, and test target.
- Keep tests isolated from live credentials and third-party services; use
  deterministic HTTP fixtures for provider behavior.
- Do not claim parity or green CI based on a partial package check.
- Do not run provider tests against live billable APIs by default.
