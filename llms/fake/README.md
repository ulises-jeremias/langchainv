# Fake language model

`llms/fake` implements `llms.Model` with a sequence of canned text responses.
It is intended for deterministic examples, tests, and offline application
development.

```v
import context
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.fake
import ulises_jeremias.langchainv.schema

fn main() {
	model := fake.new_fake_llm(['first response', 'second response'])
	mut ctx := context.background()
	response := model.generate_content(mut ctx, [schema.text_message(.human, 'hello')],
		llms.CallOptions{}) or { panic(err) }
	println(response.choices[0].content)
}
```

Responses are consumed in order and the sequence wraps to its beginning. Use
`reset` to restart it and `add_response` to append more entries. The model
checks cancellation before consuming a response and forwards each response to
`CallOptions.streaming_func` when present. It also implements
`llms.CompletionModel` through `complete`.

For tests needing mutable structured responses, configured errors, and call
counts, use `testing/llmtest.MockModel`; this package follows the smaller
upstream canned-response contract.
