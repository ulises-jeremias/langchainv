module httputil

import context
import net.urllib

// HTTPLogEvent contains safe request metadata and deliberately omits URL paths,
// query strings, headers, bodies, and error text.
pub struct HTTPLogEvent {
pub:
	method         string
	host           string
	request_bytes  int
	status_code    int
	response_bytes int
	failed         bool
}

// HTTPLogger receives one redacted event after each completed exchange.
pub interface HTTPLogger {
	log_http(event HTTPLogEvent)
}

// LoggingClient decorates a non-streaming HTTP client with redacted events.
pub struct LoggingClient {
pub:
	next   HTTPClient
	logger HTTPLogger
}

// new_logging_client wraps a client without changing its request behavior.
pub fn new_logging_client(next HTTPClient, logger HTTPLogger) LoggingClient {
	return LoggingClient{
		next:   next
		logger: logger
	}
}

// do delegates a request and emits one event without exposing credentials.
pub fn (client LoggingClient) do(mut ctx context.Context, request Request) !Response {
	response := client.next.do(mut ctx, request) or {
		client.logger.log_http(log_event(request, Response{}, true))
		return err
	}
	client.logger.log_http(log_event(request, response, false))
	return response
}

// LoggingStreamingClient decorates a streaming client without logging chunks.
pub struct LoggingStreamingClient {
pub:
	next   StreamingHTTPClient
	logger HTTPLogger
}

// new_logging_streaming_client wraps a streaming client with redacted events.
pub fn new_logging_streaming_client(next StreamingHTTPClient, logger HTTPLogger) LoggingStreamingClient {
	return LoggingStreamingClient{
		next:   next
		logger: logger
	}
}

// do_stream delegates chunks unchanged and emits one redacted completion event.
pub fn (client LoggingStreamingClient) do_stream(mut ctx context.Context, request Request, handler StreamHandler) !Response {
	response := client.next.do_stream(mut ctx, request, handler) or {
		client.logger.log_http(log_event(request, Response{}, true))
		return err
	}
	client.logger.log_http(log_event(request, response, false))
	return response
}

fn log_event(request Request, response Response, failed bool) HTTPLogEvent {
	parsed_url := urllib.parse(request.url) or {
		return HTTPLogEvent{
			method:        request.method.str()
			request_bytes: request.body.len
			failed:        failed
		}
	}
	return HTTPLogEvent{
		method:         request.method.str()
		host:           parsed_url.host
		request_bytes:  request.body.len
		status_code:    response.status_code
		response_bytes: response.body.len
		failed:         failed
	}
}
