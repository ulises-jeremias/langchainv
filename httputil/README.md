# HTTP utilities

`httputil.fetch` uses V's `net.http.fetch` and adds the LangChainV user agent.
An application identifier already in `FetchConfig.user_agent` is preserved.
`add_api_key` adds a `key` query parameter only when none is supplied.

V's `net.http` API does not expose Go's pluggable `RoundTripper` interface, so
this package provides config and URL helpers instead of a transport wrapper.
Diagnostics must use `request_summary` or `safe_url` and `redact_headers`;
request and response bodies are deliberately excluded. Credentials in URL
user info and common credential query parameters are masked. `fetch` also
redacts V HTTP error details because those can include the original URL; its
error is intentionally generic when a request fails.

```v
import net.http
import ulises_jeremias.langchainv.httputil

url := httputil.add_api_key('https://api.example.test/v1', api_key)!
response := httputil.fetch(http.FetchConfig{
	url:    url
	method: .get
})!
println(response.status_code)
```

The API-key query helper necessarily places a credential in the URL. Prefer an
authorization header when the remote API supports one, because URLs can be
captured by remote access logs and intermediaries.
