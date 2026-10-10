# ERNIE / Qianfan

This package calls Baidu Qianfan's current OpenAI-compatible v2 Chat
Completions API. Supply a Qianfan v2 Bearer API key and, when needed, choose a
model with `new_client_with_options`:

```v
import context
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.ernie
import ulises_jeremias.langchainv.schema

mut ctx := context.background()
client := ernie.new_default_client('your-qianfan-api-key')!
response := client.generate_content(mut ctx, [schema.text_message(.human, 'Hello')],
	llms.CallOptions{})!
println(response.choices[0].content)
```

The adapter inherits the OpenAI package's bounded non-streaming messages, tools,
JSON mode, common options, transport limits, and response mapping. Tests use an
injected fake HTTP transport and do not contact Baidu. The legacy upstream
adapter's AK/SK token exchange, legacy model routes, embeddings, streaming, and
Qianfan-specific behavior are not implemented here.

Qianfan's current endpoint and Bearer authentication are documented in its
[v2 chat API guide](https://ai.baidu.com/ai-doc/WENXINWORKSHOP/0m2vwrjws).
