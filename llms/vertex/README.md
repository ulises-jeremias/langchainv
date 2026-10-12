# Google Vertex AI

`vertex.Client` sends Gemini generation requests to the Vertex AI publisher
models REST API. It supports the text, inline image, tool, generation option,
usage, and SSE behavior provided by the shared Google AI client, while routing
requests by project and location and using OAuth bearer authentication.

Pass an access token explicitly in `Options.access_token`. This adapter does
not discover or refresh Application Default Credentials; callers are
responsible for obtaining a current token with the `cloud-platform` scope and
refreshing it before expiry. Use `Options.endpoint` to select the regional
Vertex endpoint when needed; it must use HTTPS. Tests inject a fake transport
and make no Google Cloud requests.

Requests use the REST `projects/{project}/locations/{location}/publishers/google/models/{model}:generateContent`
resource path. Model availability and supported generation features depend on
the selected Vertex endpoint/model. Streaming requires a streaming-capable
injected transport.
