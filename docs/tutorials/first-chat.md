---
layout: default
title: Make your first chat request
permalink: /tutorials/first-chat/
---

# Make your first chat request

This tutorial sends one live request to OpenAI Chat Completions with the
provider-neutral `llms.Model` interface. It uses the adapter's default model,
`gpt-4o-mini`. The provider may charge for requests; review its current pricing
and data-handling terms before sending prompts. For a no-key, no-network start,
use the [offline model tutorial](../offline-model-tests/) instead.

## Set up the module and API key

Install LangChainV with VPM if it is not already available:

```sh
v install ulises-jeremias.langchainv
```

Provide an OpenAI API key through your shell, IDE, or secret manager as the
`OPENAI_API_KEY` environment variable. Keep the key out of source files, shell
history, logs, and version control.

## Write a small chat program

Save this as `first_chat.v`:

```v
import context
import os
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.openai
import ulises_jeremias.langchainv.schema

fn main() {
	api_key := os.getenv('OPENAI_API_KEY').trim_space()
	if api_key == '' {
		panic('Set OPENAI_API_KEY in your environment before running this example.')
	}
	client := openai.new_default_client(api_key) or { panic(err) }
	messages := [schema.text_message(.human, 'Explain what a V module is in one sentence.')]
	mut ctx := context.background()
	response := client.generate_content(mut ctx, messages, llms.CallOptions{}) or { panic(err) }
	if response.choices.len == 0 {
		panic('The model returned no choices.')
	}
	println(response.choices[0].content)
}
```

Run it from the directory where you saved the file:

```sh
v run first_chat.v
```

Each run makes a provider request. The response can vary between runs. The
client uses a bounded HTTP transport and reports status errors without
including the provider's raw error body.

## Understand the call

- `openai.new_default_client` creates the provider adapter using the key from
  the environment.
- `schema.text_message` builds a user message; `llms.Model` lets application
  code depend on the shared chat contract.
- `context.background()` supplies the request context. The default transport
  enforces its own timeout and response-size limits.
- `llms.CallOptions{}` uses the adapter defaults. Unsupported options return an
  error instead of being silently ignored.

## Keep the next step safe

- Test application logic without a key using the
  [offline model tutorial](../offline-model-tests/).
- Add provider-neutral lifecycle events with the
  [model callbacks tutorial](../model-callbacks/).
- Compare provider requirements in the [integration catalog](../../providers/)
  before switching adapters.
- Read the [OpenAI adapter guide](https://github.com/ulises-jeremias/langchainv/blob/main/llms/openai/README.md)
  for supported options and known limitations.
