# Language models

`llms.Model` is the provider-neutral chat interface. It accepts ordered
multimodal messages and common generation options, and returns choices and
usage. Provider adapters live in isolated subpackages; inspect their guides for
supported options, streaming behavior, limits, authentication, and errors.

## Lifecycle callbacks

Adapters that do not expose a callback field can be wrapped with
`llms/middleware.CallbackModel` or `CallbackCompletionModel`. The chat wrapper
dispatches `llm_generate_content_start` before the call, then either
`llm_generate_content_end` or `llm_error`. The completion wrapper dispatches
`llm_start` and then either `llm_complete_end` or `llm_error`. Both wrappers
return the model response or error unchanged. Streaming chunks still come from
the provider's `CallOptions.streaming_func` or `streaming_reasoning_func`
callbacks.

```v
import context
import os
import ulises_jeremias.langchainv.callbacks
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.middleware
import ulises_jeremias.langchainv.llms.openai
import ulises_jeremias.langchainv.schema

fn main() {
	client := openai.new_default_client(os.getenv('OPENAI_API_KEY')) or { panic(err) }
	mut model := middleware.with_callbacks(llms.Model(client), callbacks.Handler(callbacks.LogHandler{}))
	mut ctx := context.background()
	response := model.generate_content(mut ctx, [schema.text_message(.human, 'Say hello.')], llms.CallOptions{}) or {
		panic(err)
	}
	println(response.choices[0].content)
}
```

The example makes a billable network request. Keep the API key in the
environment, never source control. The logger prints prompts and model output;
use a custom `callbacks.Handler` if those values are sensitive.

## Provider guides

- [OpenAI Chat Completions](openai/README.md)
- [Anthropic Messages](anthropic/README.md)
- [Amazon Bedrock Converse](bedrock/README.md)
- [Cohere Chat API v2](cohere/README.md)
- [Google AI](googleai/README.md)
- [Ollama](ollama/README.md)
- [Vertex AI](vertex/README.md)
- [Watsonx](watsonx/README.md)
- [Other adapters and current capability matrix](../docs/providers.md)

The [parity ledger](../docs/LANGCHAINGO_PARITY.md) records behavior that is
partial or still outstanding.
