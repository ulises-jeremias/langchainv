# Hugging Face Chat

This package targets the current OpenAI-compatible Hugging Face Inference
Providers router at `https://router.huggingface.co/v1`. Supply an HF token with
the Inference Providers permission. A model ID is required;
the model and optional provider suffix determine which inference backend serves
the request.

```v
import context
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.llms.huggingface

mut ctx := context.background()
client := huggingface.new_default_client('your-hf-token', 'Qwen/Qwen3-4B-Instruct-2507:fireworks-ai')!
response := client.generate_content(mut ctx, [schema.text_message(.human, 'Hello')],
	llms.CallOptions{})!
println(response.choices[0].content)
```

The client reuses the shared OpenAI-compatible chat implementation and
translates `max_completion_tokens` to the router's `max_tokens` field. It
inherits supported text/image messages, tools, JSON mode, bounded transport,
and error behavior. Model/provider availability and supported options depend
on the selected inference provider. The legacy LangChainGo route and
provider-specific selection options are not implemented. Tests use a fake
transport and do not call Hugging Face.
