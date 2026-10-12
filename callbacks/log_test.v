module callbacks

import context

fn test_log_handlers_implement_handler_interface() {
	mut ctx := context.background()
	mut handlers := Handlers{}
	handlers.add(LogHandler{})
	handlers.add(StreamLogHandler{})
	handlers.dispatch_text(mut ctx, 'callback')
	handlers.dispatch_streaming_chunk(mut ctx, 'chunk'.bytes())
}
