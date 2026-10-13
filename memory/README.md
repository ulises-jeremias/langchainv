# Memory

`new_simple_memory()` implements the memory interface without storing values.
`new_simple_memory_with_values(values)` snapshots fixed key/value pairs and
provides a fresh snapshot on every load; saved outputs do not change them.
`new_conversation_buffer(memory_key, input_key, output_key)` stores the full
conversation in process memory. `new_conversation_buffer_with_options` also
supports custom human/AI transcript prefixes and infers an input or output key
when its key option is blank and the corresponding map has exactly one string
value. It rejects ambiguous maps and non-string values. The original constructor
continues to require all three keys. Use `new_conversation_buffer_with_history`
to supply any `schema.ChatMessageHistory` implementation, including persistent
backends. `new_conversation_window_buffer(window_size, memory_key, input_key,
output_key)` stores only the latest `window_size` turns.
Each turn is one human and one assistant message. A non-positive window size
uses the default of five turns; sizes above 10,000 return an error. This window
limits message count, not tokens.
`ConversationBuffer.load_messages` and `ConversationWindowBuffer.load_messages`
return typed message snapshots for callers that need roles, metadata, or
multimodal content. The `schema.Memory` contract continues to expose the
role-labeled transcript string for use by existing chains.

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

`memory/sqlhistory` implements the same typed history contract over an
injected PostgreSQL `sqldatabase.Engine` with the `pgx` or `postgresql` dialect.
It creates a shared `langchain_chat_messages` table and session index when they
are missing, stores JSON-encoded messages, and keeps a bounded number of recent
messages per session. A blank session uses `default`. Existing tables are not
altered or validated. Zero limits use 1024 messages and 16 KiB per message; the
combined read bound cannot exceed 16 MiB. A caller can use a compatible engine
connected to Cloud SQL for PostgreSQL or AlloyDB, but connection setup,
authentication, and engine lifetime remain the caller's responsibility. The
history object never closes the injected engine. Inserts and trimming are
separate statements because `sqldatabase.Engine` does not expose transactions;
an insert may remain stored if trimming fails. CI tests use a deterministic
fake engine and do not require a PostgreSQL service.
