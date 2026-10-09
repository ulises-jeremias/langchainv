// Package httputil provides safe defaults for HTTP calls made by integrations.
module httputil

import net.http
import net.urllib
import os

// user_agent returns the stable LangChainV identifier for outbound requests.
// V does not expose Go-style executable build metadata, so callers that need
// an application identifier can append it through FetchConfig.user_agent.
pub fn user_agent() string {
	return 'langchainv/0.1.0 V (${os.user_os()})'
}

// fetch applies LangChainV's user agent and delegates to V's HTTP client.
// Existing application identifiers are retained. The supplied config is
// passed by value, so applying defaults does not mutate the caller's config.
pub fn fetch(config http.FetchConfig) !http.Response {
	request_config := with_user_agent(config)
	return http.fetch(request_config) or {
		// V's HTTP errors may include the original URL. Avoid passing possible
		// credentials to callers' logs when a request fails.
		return error('HTTP request failed (details redacted)')
	}
}

// with_user_agent returns a copy of a fetch config with LangChainV's identifier
// appended, preserving an existing application identifier.
pub fn with_user_agent(config http.FetchConfig) http.FetchConfig {
	mut request_config := config
	if request_config.user_agent == '' || request_config.user_agent == 'v.http' {
		request_config.user_agent = user_agent()
	} else if !request_config.user_agent.contains(user_agent()) {
		request_config.user_agent += ' ' + user_agent()
	}
	return request_config
}

// add_api_key returns a URL with a `key` query parameter if one is not already
// present. Existing query parameters are preserved and the input is untouched.
pub fn add_api_key(raw_url string, api_key string) !string {
	mut url := urllib.parse(raw_url) or {
		return error('cannot add API key to invalid URL')
	}
	if api_key == '' {
		return url.str()
	}
	mut query := url.query()
	mut has_key := false
	for item in query.data {
		if item.key == 'key' {
			has_key = true
			break
		}
	}
	if !has_key {
		query.set('key', api_key)
		url.raw_query = query.encode()
	}
	return url.str()
}

// redact_headers copies header values and masks those whose names commonly
// carry credentials or session identifiers. It never returns original secrets.
pub fn redact_headers(headers map[string]string) map[string]string {
	mut safe := map[string]string{}
	for name, value in headers {
		if is_sensitive_name(name) {
			safe[name] = '[REDACTED]'
		} else {
			safe[name] = value
		}
	}
	return safe
}

// safe_url removes user info and redacts credential-like query parameters for
// diagnostics. It intentionally retains the path and non-sensitive parameters.
pub fn safe_url(raw_url string) string {
	mut url := urllib.parse(raw_url) or { return '[invalid URL]' }
	url.user = none
	mut query := url.query()
	for mut item in query.data {
		if is_sensitive_name(item.key) {
			item.value = '[REDACTED]'
		}
	}
	url.raw_query = query.encode()
	return url.str()
}

// request_summary formats method and a sanitized URL for diagnostic logs.
// Request and response bodies are deliberately excluded.
pub fn request_summary(method string, raw_url string) string {
	return '${method} ${safe_url(raw_url)}'
}

fn is_sensitive_name(name string) bool {
	lower := name.to_lower()
	for marker in ['authorization', 'auth', 'api_key', 'apikey', 'key', 'token', 'secret', 'cookie',
		'credential', 'password', 'signature'] {
		if lower.contains(marker) {
			return true
		}
	}
	return false
}
