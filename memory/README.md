# Memory

`new_simple_memory()` implements the memory interface without storing values.
`new_simple_memory_with_values(values)` snapshots fixed key/value pairs and
provides a fresh snapshot on every load; saved outputs do not change them.
`new_conversation_buffer(memory_key, input_key, output_key)` stores the full
conversation in process memory. `new_conversation_window_buffer(window_size,
memory_key, input_key, output_key)` stores only the latest `window_size` turns.
Each turn is one human and one assistant message. A non-positive window size
uses the default of five turns; sizes above 10,000 return an error. This window
limits message count, not tokens.

The token buffer constructor accepts an injected llms.TokenCounter, model,
token limit, and memory/input/output keys. It evicts oldest complete
human/assistant turns after each save until the retained messages fit the
positive token limit. If the newest turn alone exceeds the limit, history is
cleared. A counter error leaves the previous history unchanged. No provider
tokenizer is bundled.

All memory implementations expose `clear(mut ctx)` through the `schema.Memory`
interface; it removes stored state or succeeds without changing state for
no-op memory.

`memory/sqlite` stores typed chat messages in SQLite, isolated by session. The
constructor accepts a database path, session ID, and optional message-count and
message-size limits. An empty session ID selects `default`. Defaults cap
history reads at 1024 messages and 16 KiB per message, with a combined read
bound of 16 MiB. Oversized messages and unsupported bound combinations return errors.
The adapter uses V's `db.sqlite` module and needs SQLite development files on
Linux when the compiler cannot find its bundled amalgamation. Tests use an
in-memory database.
