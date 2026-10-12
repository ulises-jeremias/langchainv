---
layout: default
title: Observe model calls with callbacks
permalink: /tutorials/model-callbacks/
---

# Observe model calls with callbacks

Wrap an `llms.Model` or `llms.CompletionModel` in the corresponding middleware
type to observe a model request, response, or error, even when its provider
adapter does not have a callback option. Each wrapper emits the lifecycle start
event before dispatch, then exactly one end or error event. It forwards the
original response or error. Streaming chunks remain controlled by the
provider's stream callbacks.

## Wrap a provider

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

Set `OPENAI_API_KEY` in the environment before running this program. It sends a
real request and may incur charges. `LogHandler` writes message text and model
output to standard output; use a custom handler when prompts or responses are

## Wrap a completion model

Completion APIs emit `llm_start` with the prompt and then
`llm_complete_end` with the returned text. Failures dispatch `llm_error` and
propagate unchanged.

```v
fn completion_example() {
	client := openai.new_default_client(os.getenv('OPENAI_API_KEY')) or { panic(err) }
	mut completion_model := middleware.with_completion_callbacks(llms.CompletionModel(client),
		callbacks.Handler(callbacks.LogHandler{}))
	mut ctx := context.background()
	response := completion_model.complete(mut ctx, 'Say hello.', llms.CallOptions{}) or { panic(err) }
	println(response)
}
```

## Keep application tests offline

Application logic can accept `llms.Model` and use the deterministic mock from
[`testing/llmtest`](https://github.com/ulises-jeremias/langchainv/tree/main/testing/llmtest)
to test without credentials. Provider request encoding and parsing should be
tested separately with the adapter's injected fake HTTP transport. Examples in
this repository must remain offline; CI removes the live-example opt-in before
running them.

See the [`llms` package guide](https://github.com/ulises-jeremias/langchainv/blob/main/llms/README.md)
and the [`callbacks` contract](https://github.com/ulises-jeremias/langchainv/blob/main/callbacks/README.md)
for lifecycle semantics and handler behavior.
