# IBM watsonx.ai

`watsonx.Client` implements the upstream LangChainGo adapter's text-generation
contract using the watsonx.ai versioned REST API. It accepts exactly one human
text message and maps temperature, top-p, top-k, repetition penalty, seed,
maximum new tokens, and stop sequences. Responses include generated text, stop
reason, and available input/output token counts.

Supply either `Options.api_key` or an existing IAM token with
`Options.access_token`, along with a project ID and foundation model ID. The
API key and project ID fall back to `WATSONX_API_KEY` and `WATSONX_PROJECT_ID`.
When configured with an API key, the adapter exchanges it at IBM IAM and caches
the returned token until 60 seconds before its expiry. `Options.iam_url` and
`Options.base_url` can select alternate HTTPS endpoints; `Options.api_version`
defaults to the version used by upstream `watsonx-go` v1.0.0. Tests use injected
fake HTTP for both IAM and generation and do not call IBM Cloud.

Multimodal/chat history, streaming, multiple candidates, and unsupported common
generation options are rejected before an API request. Prompts default to a
256 KiB bound; requests and decoded responses are capped at 512 KiB and 4 MiB.
