# Security policy

Do not publish API keys, tokens, private prompts, personal data, or provider
responses containing secrets in issues, pull requests, fixtures, logs, or
examples. Report suspected vulnerabilities privately to the repository owner
through GitHub's private vulnerability reporting feature when enabled.

Security-sensitive code includes HTTP transport, URL/document loaders, SQL
tools, shell or filesystem tools, prompt rendering, serialization, provider
error handling, and credential storage. Changes in these areas should consider
SSRF, path traversal, injection, unbounded resource use, secret leakage, and
unsafe tool execution.

Routine tests must use fake credentials and deterministic fixtures. A test must
not contact a billable provider unless it is explicitly opt-in.
