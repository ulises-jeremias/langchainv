// Package callbacks provides a logger for raw streaming payloads.
module callbacks

import context

// StreamLogHandler ignores lifecycle events and prints streaming chunks.
pub struct StreamLogHandler {
	SimpleHandler
}

// streaming_chunk prints one payload as text on standard output.
pub fn (handler StreamLogHandler) streaming_chunk(mut ctx context.Context, chunk []u8) {
	println(chunk.bytestr())
}
