module callbacks

import context

fn test_agent_final_stream_matches_marker_across_chunks() {
	mut handler := new_agent_final_stream_handler('Final Answer:')
	mut ctx := context.background()
	handler.streaming_chunk(mut ctx, 'prefix Final Ans'.bytes())
	handler.streaming_chunk(mut ctx, 'wer: result'.bytes())
	chunk := <-handler.get_egress()
	assert chunk.bytestr() == ' result'
	assert handler.dropped_chunks == 0
}

fn test_agent_final_stream_bounds_slow_consumer_queue() {
	mut handler := new_agent_final_stream_handler('END')
	mut ctx := context.background()
	for _ in 0 .. final_stream_buffer_capacity + 1 {
		handler.streaming_chunk(mut ctx, 'ENDx'.bytes())
	}
	assert handler.dropped_chunks == 1
	assert handler.dropped_bytes == 4
}

fn test_agent_final_stream_uses_default_markers() {
	mut handler := new_agent_final_stream_handler()
	mut ctx := context.background()
	handler.streaming_chunk(mut ctx, 'AI: hi'.bytes())
	chunk := <-handler.get_egress()
	assert chunk.bytestr() == ' hi'
}
