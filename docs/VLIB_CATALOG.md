# V standard-library catalog for LangChainV

This catalog was checked against the workstation's V 0.5.2 source commit
`407c52edddca9715fb57e6571afeef0d193f2465` and cross-checked against upstream
`master` at `a6826c4db0e28d306160fcc9e96baca90ea78f40` on 2026-10-09. Both trees
have the same 65 top-level module directories, 62 module-level README files,
and 182 README files recursively. The upstream tree has 67 root entries when
the root `README.md` and `.vdocignore` are included. The three commits between
these snapshots change 15 `vlib` paths, limited to one `builtin` implementation
file and V compiler internals, tests, and help; they add or remove no standard
library module. This inventory does not promise identical support on every V
platform. Check a module's platform guards and tests before relying on a
particular backend.

## Directly useful modules

| Need | V modules available | Use in this project |
|---|---|---|
| HTTP client and network protocols | `net.http`, `net.websocket`, `net.urllib`, `net.mbedtls`, `net.openssl`, `net.ssl` | Shared HTTP transport, provider REST APIs, SSE parsing over HTTP response streams, optional websocket transports, TLS configuration |
| HTTP server | `veb`, `fasthttp`, `net.http` | Test fixtures and optional callback/webhook server helpers; prefer `veb` for a V-native high-level server |
| JSON and structured formats | `json2`, `encoding.cbor`, `encoding.csv`, `encoding.xml`, `encoding.protobuf`, `yaml`, `toml` | Provider request/response types, schemas, documents and local fixture formats |
| SQL and persistence | `db.sqlite`, `db.pg`, `db.mysql`, `db.mssql`, `db.redis`, `orm`, `pool` | SQL tools, chat-history backends, and vector-store adapters; keep each backend optional |
| Cancellation and concurrency | `context`, `sync`, `goroutines`, `coroutines`, `eventbus` | Deadlines/cancellation, bounded worker pools, callback/event delivery; use only concurrency primitives whose shutdown semantics are explicit |
| Files and streaming | `os`, `io`, `io.fs`, `io.string_reader`, `archive`, `compress` | Directory/text/CSV/PDF ingestion, file walking, bounded readers, archives and compressed inputs |
| Text and token processing | `strings`, `strconv`, `regex`, `encoding.utf8`, `encoding.html`, `math` | Template rendering, normalization, regular expressions, HTML cleanup, Unicode-aware splitting and numeric helpers |
| Cryptography and identifiers | `crypto.*`, `hash`, `uuid`, `encoding.base64`, `encoding.hex` | Secure identifiers, request signing where needed, digesting/cache keys, encoding; do not implement crypto primitives locally |
| MCP and tools | `mcp`, `net.http`, `os` | V-native MCP client/server tool adapters and local process/file tools |
| Observability and CLI | `log`, `flag`, `cli`, `term`, `time`, `benchmark` | Logging, command examples, terminal output, timeouts and benchmarks |
| Numerical backend | `math`, `math.vec`, `math.complex`, `arrays`, `simd`, optional `vsl`, optional `vtl` | Similarity calculations and optional tensor/vector acceleration; avoid making VSL/VTL mandatory for core |

`context` is present in V 0.5.2 and carries cancellation/deadline signals. Its
exact semantics should be checked before exposing it as the public framework
contract. V's `json2` has typed encoding/decoding, reusable decode buffers, and
explicit legacy-compatibility differences; use it directly and test wire
compatibility instead of assuming it matches another language's JSON output.

`net.http` has progress callbacks that receive response chunks, which can feed
an incremental SSE parser. Do not assume those callbacks imply uniform
time-to-first-token behavior on every platform: the V source documents a
Windows transport path that may deliver the full response at once. Streaming
parity therefore needs provider and platform checks, with a transport-specific
fallback if callback streaming is unavailable.

## Full top-level inventory

The 65 module directories in the inspected `vlib` tree are:

`archive`, `arena`, `arrays`, `benchmark`, `bitfield`, `build`, `builtin`,
`cli`, `clipboard`, `compress`, `context`, `coroutines`, `crypto`,
`datatypes`, `db`, `dl`, `dlmalloc`, `encoding`, `eventbus`, `fasthttp`,
`flag`, `fontstash`, `gg`, `goroutines`, `gx`, `hash`, `i18n`, `image`, `io`,
`ios`, `js`, `json2`, `log`, `macos`, `maps`, `math`, `mcp`, `ncurses`, `net`,
`orm`, `os`, `pico_http_parser`, `picoev`, `picohttpparser`, `pool`, `rand`,
`readline`, `regex`, `runtime`, `semver`, `simd`, `sokol`, `stbi`, `strconv`,
`strings`, `sync`, `term`, `time`, `toml`, `uuid`, `v`, `veb`, `wasm`, `x`,
`yaml`.

## Important namespaces

- `net`: `http`, `websocket`, `urllib`, `ftp`, `smtp`, `imap`, `s3`,
  `grpc`, `quic`, `unix`, `socks`, `ssl`, `openssl`, `mbedtls`, `html`,
  `jsonrpc`, and protocol helpers.
- `encoding`: `base32`, `base58`, `base64`, `binary`, `cbor`, `cose`, `csv`,
  `cwt`, `hex`, `html`, `iconv`, `leb128`, `protobuf`, `punycode`, `txtar`,
  `utf8`, `vorbis`, and `xml`.
- `crypto`: AES, Argon2, bcrypt, BLAKE2/3, Blowfish, DES, ECDSA, Ed25519, HKDF,
  HMAC, MD5, PBKDF2, PEM, RC4, RIPEMD160, scrypt, SHA families, SCRAM, and
  constant-time helpers.
- `db`: MSSQL, MySQL, PostgreSQL, Redis, and SQLite.
- `math`: big numbers, bit operations, complex numbers, decimal, fractions,
  statistics, unsigned integers, and vectors.
- `x`: extension namespace including `async`, `atomics`, `crypto`, `dataframe`,
  `encoding`, `executor`, `json2`, `json5`, `jsonc`, `markdown`, `progress`,
  `sessions`, and `templating`. Treat these as extension/experimental modules;
  check stability and platform support before making them core dependencies.

## Dependency and portability policy

- Prefer pure V and V standard library packages for core functionality.
- Isolate native-library bindings and database drivers behind adapter packages.
- Use `net.http` for ordinary HTTP interactions; centralize timeouts, headers,
  user-agent, retries, and safe error handling in one shared transport.
- Keep `x.*`, `coroutines`, and platform-specific modules out of core APIs until
  compatibility and lifecycle constraints are proven.
- Prefer mature standard cryptography modules over bespoke implementations.
- Add VSL/VTL only behind optional adapters, with independent installation and
  compile paths.

## Source inventory

Enumerated all 65 top-level module directories and all 182 recursive README
files in the local source tree. Reviewed the module summaries for available
APIs and read the full docs for modules directly relevant to this framework:
`context`, `json2`, `net.http`, `net.urllib`, HTTP/SSE streaming, file and
encoding packages, cryptography and identifiers, optional database drivers,
and V's testing/logging/concurrency helpers. Compared that source snapshot with
upstream `master`; its 15 changed paths add no standard-library package. Read
source files and docs directly rather than invoking `v where` because that
command attempted to write a cache into the compiler checkout.
