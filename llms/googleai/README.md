# Google AI / Gemini

`googleai.Client` implements non-streaming Gemini `generateContent` for text
messages and system instructions. It maps text candidates, finish reasons, and
usage counts into the shared LLM response types. It supports maximum output
tokens, temperature, top-p, top-k, and stop sequences. The API key is sent in
the `x-goog-api-key` header and is not placed in the URL.

Use `new_default_client(api_key)` with the shared bounded HTTP transport, or
inject an `httputil.HTTPClient` using `new_client` and `new_client_with_options`
for custom endpoints and offline tests. Endpoints must use HTTPS. The current
client supports text only and explicitly rejects streaming, tools, structured
output, and multimodal parts; no API request is sent for unsupported options.
