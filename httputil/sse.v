module httputil

// SSEDecoder parses Server-Sent Events independently of transport chunking.
pub struct SSEDecoder {
mut:
	buffer          string
	data_lines      []string
	event_data_size int
	max_event_bytes int
}

// new_sse_decoder creates a parser with a positive event-size limit.
pub fn new_sse_decoder(max_event_bytes int) !SSEDecoder {
	if max_event_bytes <= 0 {
		return error('SSE event limit must be greater than zero')
	}
	return SSEDecoder{
		max_event_bytes: max_event_bytes
	}
}

// push parses any complete events in a received byte chunk.
pub fn (mut decoder SSEDecoder) push(chunk []u8) ![][]u8 {
	decoder.buffer += chunk.bytestr()
	mut events := [][]u8{}
	for {
		line_end := decoder.buffer.index('\n') or {
			if decoder.buffer.len > decoder.max_event_bytes {
				return error('SSE line exceeds the configured event limit')
			}
			break
		}
		mut line := decoder.buffer[..line_end]
		decoder.buffer = decoder.buffer[line_end + 1..]
		if line.ends_with('\r') {
			line = line[..line.len - 1]
		}
		decoder.consume_line(line, mut events)!
	}
	return events
}

// finish dispatches a final event when EOF arrives without a trailing blank line.
pub fn (mut decoder SSEDecoder) finish() ![][]u8 {
	mut events := [][]u8{}
	if decoder.buffer.len > 0 {
		line := decoder.buffer.clone()
		decoder.buffer = ''
		decoder.consume_line(line, mut events)!
	}
	if decoder.data_lines.len > 0 {
		decoder.dispatch(mut events)
	}
	return events
}

fn (mut decoder SSEDecoder) consume_line(line string, mut events [][]u8) ! {
	if line == '' {
		decoder.dispatch(mut events)
		return
	}
	if line.starts_with(':') {
		return
	}
	colon := line.index(':') or { return }
	if line[..colon] != 'data' {
		return
	}
	mut data := line[colon + 1..]
	if data.starts_with(' ') {
		data = data[1..]
	}
	if data.len > decoder.max_event_bytes - decoder.event_data_size {
		return error('SSE event exceeds the configured event limit')
	}
	decoder.event_data_size += data.len
	decoder.data_lines << data
}

fn (mut decoder SSEDecoder) dispatch(mut events [][]u8) {
	if decoder.data_lines.len > 0 {
		events << decoder.data_lines.join('\n').bytes()
		decoder.data_lines = []string{}
	}
	decoder.event_data_size = 0
}
