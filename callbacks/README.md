# Callbacks

`Handler` receives lifecycle events; `SimpleHandler` supplies no-op behavior,
`CombiningHandler` fans out events in registration order, and `LogHandler` writes
events to standard output. `StreamLogHandler` logs only raw streaming chunks.

`new_agent_final_stream_handler(keywords ...string)` scans raw chunks for the
first configured marker. It defaults to `Final Answer:`, `Final:`, and `AI:`.
The egress channel has capacity 64 and each queued chunk is at most 64 KiB;
consumers read it with `get_egress()`. If the consumer falls behind, new chunks
are dropped instead of blocking the model callback, and `dropped_chunks` /
`dropped_bytes` report the loss. The handler keeps at most the longest marker
length minus one bytes while searching. Create one handler per stream and use
it from one producer at a time.
