# Google AI / Gemini

`googleai.Client` implements non-streaming Gemini `generateContent` for text
messages, system instructions, bounded inline images, and function tools. It
maps text candidates, function calls, finish reasons, and usage counts into the
shared LLM response types, and supports maximum output tokens, temperature,
top-p, top-k, stop sequences, candidate count, seed, and JSON MIME output. The
API key is sent in the `x-goog-api-key` header and is not placed in the URL.

Use `new_default_client(api_key)` with the shared bounded HTTP transport, or
inject an `httputil.HTTPClient` using `new_client` and `new_client_with_options`
for custom endpoints and offline tests. Endpoints must use HTTPS. The current
client explicitly rejects streaming, remote image URLs, JSON schema output,
strict tool mode, and unsupported generation options; no API request is sent
for unsupported options. Inline images are capped at 5 MiB per image, requests
at 8 MiB, and responses at 16 MiB. Candidate count is capped at 8.
