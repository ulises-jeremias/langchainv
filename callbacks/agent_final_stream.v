// Package callbacks supports bounded streaming of detected agent final answers.
module callbacks

import context

pub const default_final_keywords = ['Final Answer:', 'Final:', 'AI:']
const final_stream_buffer_capacity = 64
const max_final_stream_chunk_bytes = 65536

// AgentFinalStreamHandler forwards bytes after the first configured answer marker.
// The egress queue is bounded; chunks are counted as dropped if its consumer falls behind.
pub struct AgentFinalStreamHandler {
	SimpleHandler
pub:
	keywords []string
pub mut:
	dropped_chunks u64
	dropped_bytes  u64
mut:
	egress          chan []u8
	pending         string
	answer_detected bool
}

// new_agent_final_stream_handler creates a bounded final-answer stream handler.
// With no usable custom keywords, it uses Final Answer:, Final:, and AI:.
pub fn new_agent_final_stream_handler(keywords ...string) AgentFinalStreamHandler {
	mut selected := []string{}
	for keyword in keywords {
		if keyword != '' {
			selected << keyword
		}
	}
	if selected.len == 0 {
		selected = default_final_keywords.clone()
	}
	return AgentFinalStreamHandler{
		keywords: selected
		egress:   chan []u8{cap: final_stream_buffer_capacity}
	}
}

// get_egress returns the bounded queue of final-answer byte chunks.
pub fn (handler &AgentFinalStreamHandler) get_egress() chan []u8 {
	return handler.egress
}

// streaming_chunk scans arbitrary chunk boundaries for the first final-answer marker.
// If the consumer falls behind, the bounded queue drops the new chunk and increments
// dropped_chunks and dropped_bytes rather than blocking the model callback.
pub fn (mut handler AgentFinalStreamHandler) streaming_chunk(mut ctx context.Context, chunk []u8) {
	if handler.answer_detected {
		handler.send_answer_chunk(chunk.bytestr())
		return
	}
	candidate := handler.pending + chunk.bytestr()
	mut match_index := -1
	mut match_length := 0
	for keyword in handler.keywords {
		index := candidate.index(keyword) or { -1 }
		if index >= 0 && (match_index < 0 || index < match_index) {
			match_index = index
			match_length = keyword.len
		}
	}
	if match_index >= 0 {
		handler.pending = ''
		handler.answer_detected = true
		answer_start := match_index + match_length
		if answer_start < candidate.len {
			handler.send_answer_chunk(candidate[answer_start..])
		}
		return
	}
	mut max_keyword_length := 0
	for keyword in handler.keywords {
		if keyword.len > max_keyword_length {
			max_keyword_length = keyword.len
		}
	}
	keep := max_keyword_length - 1
	if keep > 0 && candidate.len > keep {
		handler.pending = candidate[candidate.len - keep..].clone()
	} else {
		handler.pending = candidate
	}
}

fn (mut handler AgentFinalStreamHandler) send_answer_chunk(answer string) {
	mut start := 0
	for start < answer.len {
		end := if start + max_final_stream_chunk_bytes < answer.len {
			start + max_final_stream_chunk_bytes
		} else {
			answer.len
		}
		part := answer[start..end].bytes()
		select {
			handler.egress <- part {
			}
			else {
				handler.dropped_chunks++
				handler.dropped_bytes += u64(part.len)
			}
		}
		start = end
	}
}
