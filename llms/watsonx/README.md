# IBM watsonx.ai

`watsonx.Client` implements the upstream LangChainGo adapter's text-generation
contract using the watsonx.ai versioned REST API. It accepts exactly one human
text message and maps temperature, top-p, top-k, repetition penalty, seed,
maximum new tokens, and stop sequences. Responses include generated text, stop
reason, and available input/output token counts.

Supply an IAM access token explicitly with `Options.access_token`, along with a
project ID and foundation model ID. The adapter does not exchange an IBM Cloud
API key for a token or refresh expiring tokens. `Options.base_url` may select a
regional HTTPS endpoint, and `Options.api_version` defaults to the version used
by upstream `watsonx-go` v1.0.0. Tests use injected fake HTTP and do not call IBM
Cloud.

Multimodal/chat history, streaming, multiple candidates, and unsupported common
generation options are rejected before an API request. Prompts default to a
256 KiB bound; requests and decoded responses are capped at 512 KiB and 4 MiB.
