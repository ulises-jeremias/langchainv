// Package httputil provides bounded, injectable HTTP transport for providers.
module httputil

import context
import net.http
import net.urllib
import time

// HTTPClient is the provider-facing HTTP request contract.
pub interface HTTPClient {
	do(mut ctx context.Context, request Request) !Response
}

// Request describes one HTTP exchange without exposing credentials in logs.
pub struct Request {
pub:
	method  http.Method = .get
	url     string
	headers map[string]string
	body    string
}

// Response contains the status, headers, and bounded response body.
pub struct Response {
pub:
	status_code int
	headers     http.Header
	body        string
}

// DefaultClient sends HTTP requests with explicit timeouts and byte limits.
pub struct DefaultClient {
pub:
	timeout_ms         int    = 30000
	max_request_bytes  i64    = 8 * 1024 * 1024
	max_response_bytes i64    = 16 * 1024 * 1024
	user_agent         string = 'langchainv/0.1.0'
}

// new_default_client returns the safe defaults for provider HTTP calls.
pub fn new_default_client() DefaultClient {
	return DefaultClient{}
}

// validate_url accepts HTTP(S) URLs, optionally requiring one exact scheme,
// and rejects URL user information before credentials can enter a request.
pub fn validate_url(raw_url string, required_scheme string) ! {
	parsed_url := urllib.parse(raw_url) or { return error('invalid HTTP URL') }
	scheme := parsed_url.scheme.to_lower()
	if scheme !in ['http', 'https'] || parsed_url.host == '' {
		return error('HTTP URL must use http or https and include a host')
	}
	if required_scheme != '' && scheme != required_scheme.to_lower() {
		return error('HTTP URL must use ${required_scheme}')
	}
	scheme_end := raw_url.index('://') or { return error('invalid HTTP URL') }
	authority := raw_url[scheme_end + 3..].split('/')[0].split('?')[0].split('#')[0]
	if authority.contains('@') {
		return error('HTTP URL user information is not allowed')
	}
}

// do executes one request. Context cancellation is checked before and after
// net.http.fetch; an in-flight request is bounded by timeout_ms.
pub fn (client DefaultClient) do(mut ctx context.Context, request Request) !Response {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	if client.timeout_ms <= 0 {
		return error('HTTP timeout must be greater than zero')
	}
	if client.max_request_bytes <= 0 || client.max_request_bytes > i64(64 * 1024 * 1024) {
		return error('maximum HTTP request size must be between 1 byte and 64 MiB')
	}
	if client.max_response_bytes <= 0 || client.max_response_bytes > i64(1024 * 1024 * 1024) {
		return error('maximum HTTP response size must be between 1 byte and 1 GiB')
	}
	if i64(request.body.len) > client.max_request_bytes {
		return error('HTTP request body exceeds the configured byte limit')
	}
	if request.headers.len > 32 {
		return error('HTTP request has more than 32 custom headers')
	}
	validate_url(request.url, '')!
	mut headers := http.Header{}
	mut user_agent := client.user_agent
	for key, value in request.headers {
		if key.to_lower() == 'user-agent' {
			user_agent = '${value} ${client.user_agent}'
			continue
		}
		headers.set_custom(key, value)!
	}
	timeout := i64(client.timeout_ms) * time.millisecond
	read_limit := client.max_response_bytes + 1
	response := http.fetch(
		method:               request.method
		url:                  request.url
		header:               headers
		data:                 request.body
		user_agent:           user_agent
		validate:             true
		allow_redirect:       false
		max_retries:          0
		read_timeout:         timeout
		write_timeout:        timeout
		stop_copying_limit:   read_limit
		stop_receiving_limit: read_limit
	)!
	if i64(response.body.len) > client.max_response_bytes {
		return error('HTTP response body exceeds the configured byte limit')
	}
	ctx_error_after := ctx.err()
	if ctx_error_after !is none {
		return ctx_error_after
	}
	return Response{
		status_code: response.status_code
		headers:     response.header
		body:        response.body
	}
}
