# MongoDB chat message history

`MongoChatMessageHistory` stores chat messages as documents in a MongoDB
collection and implements the shared `schema.ChatMessageHistory` interface.

The package does not bundle a MongoDB driver. The caller adapts a driver
collection to the narrow `MongoCollection` interface (insert one document,
find sorted documents, delete many documents). Documents carry three fields:
`session_id`, a per-session sequence number in `seq`, and the JSON-encoded
message in `payload`.

History is bounded: at most 4,096 messages and 64 KiB per message, with a
combined read bound of 16 MiB. Zero limits select 1,024 messages and 16 KiB
per message. Adding a message trims older documents for the session. One
history instance should own a session at a time, because sequence numbers
are assigned in memory and resumed from the latest stored document at
construction. Tests use an in-memory fake collection and make no network
calls.
