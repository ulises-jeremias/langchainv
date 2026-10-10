# HTTP transport

Provider code depends on the injectable `HTTPClient` interface. `DefaultClient`
uses V's `net.http`, allows only HTTP and HTTPS URLs without URL userinfo,
disables redirects and automatic retries, validates TLS certificates, and
limits request and response bytes. Its defaults are 30 seconds, 8 MiB per
request, and 16 MiB per response.

`validate_url(url, required_scheme)` exposes the same URL policy to provider
constructors and URL-valued message parts. Pass an empty scheme to allow HTTP or
HTTPS, or `https` to require TLS. It validates URL syntax and authority only; it
does not connect to the host.

`net.http.fetch` does not accept V's context directly. The default client checks
cancellation before and after a call and bounds an in-flight call with read and
write timeouts. Provider tests should inject a deterministic `HTTPClient` and
must not use live credentials or billable endpoints.
