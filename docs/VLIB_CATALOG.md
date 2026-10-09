# V standard-library catalog for LangChainV

This catalog was checked against V commit
`5bd67093f97f3574b36bc1a9f19f56a9c0a4ad07` (V 0.5.2), the compiler currently
installed on the workstation. The upstream `vlib` tree at that commit has 67
top-level entries and 62 module README files. This is an inventory for the
framework, not a promise that every V platform has identical support. Check the
module's platform guards and tests before relying on a particular backend.

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

V 0.5.2's `x.markdown` includes a CommonMark/GFM block and inline parser, HTML
and plaintext renderers, and an AST whose link nodes expose resolved reference
destinations and titles. The current Markdown splitter instead scans a
supported subset of reference definitions in source lines; it does not import
`x.markdown` or require that experimental module at compile time. Keep `x.*`
optional for future full CommonMark block and inline fidelity, and verify its
actual AST behavior against the pinned compiler before adopting it.

## Generic field inspection and typed JSON

V 0.5.2 does not provide Go-style runtime `reflect` as the route for struct
schemas. Generic functions can inspect fields at compile time with `$for field
in T.fields`, branch on `field.typ` with `$if`, and read field names and
attributes. The standard library uses this pattern in `json2`, `toml`, and
`flag`. `json2.decode[T]` then decodes JSON directly into a concrete V type.

For LangChainGo's `Defined[T]` output parser, this means schema generation
should be a generic, compile-time field walk and parsing should call
`json2.decode[T]`. Its typed `parse(text) !T` cannot implement the common
`Parser.parse(text) !json2.Any` interface without erasing the result type, so
it should remain a separate typed API. Field tags also differ: V uses
attributes such as `@[json: fieldName]`; document any mapping from Go `json`
and `describe` struct tags to these V attributes.

## Full top-level inventory

The 67 entries in the inspected `vlib` tree are:

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

Inventoried the README summaries and package structure in the exact V source
archive above, and inspected full documentation for the directly relevant
packages. The installed binary's `v where` command could not be
used because it attempted to create a cache in a read-only compiler checkout;
the archive and V source tree were read directly without invoking compilation.
