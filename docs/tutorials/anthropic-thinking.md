---
layout: default
title: Configure Anthropic thinking
permalink: /tutorials/anthropic-thinking/
---

# Configure Anthropic thinking

Use the Anthropic adapter's allowlisted provider options to request adaptive
thinking and an output effort level. This tutorial sends one live request and
may incur charges. Review Anthropic's current [pricing](https://www.anthropic.com/pricing)
and [thinking guide](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/prompt-templates-and-variables)
before sending prompts. The model must support the requested settings.

## Set up the API key

Set `ANTHROPIC_API_KEY` in your shell, IDE, or secret manager. Do not put the
key in source code or version control.

## Send a request with adaptive thinking

Save this as `anthropic_thinking.v`:

```v
import context
import json2
import os
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.anthropic
import ulises_jeremias.langchainv.schema

fn main() {
	api_key := os.getenv('ANTHROPIC_API_KEY').trim_space()
	if api_key == '' {
		panic('Set ANTHROPIC_API_KEY in your environment before running this example.')
	}
	client := anthropic.new_default_client(api_key) or { panic(err) }
	options := llms.CallOptions{
		max_tokens: 2048
		provider_options: {
			'thinking': json2.Any(map[string]json2.Any{
				'type': json2.Any('adaptive')
			})
			'output_config': json2.Any(map[string]json2.Any{
				'effort': json2.Any('high')
			})
		}
	}
	mut ctx := context.background()
	response := client.generate_content(mut ctx, [schema.text_message(.human,
		'Compare two ways to make V HTTP requests, with one tradeoff for each.')], options) or {
		panic(err)
	}
	if response.choices.len == 0 {
		panic('Anthropic returned no choices.')
	}
	println(response.choices[0].content)
}
```

Run it from the directory where you saved the file:

```sh
v run anthropic_thinking.v
```

## Understand the options

- `thinking.type = adaptive` lets supported Claude models allocate reasoning
  dynamically. Older models may need `thinking.type = enabled` with a
  `budget_tokens` value of at least 1024 and below `max_tokens`.
- `output_config.effort` accepts `low`, `medium`, `high`, `xhigh`, or `max`.
  Model availability and combinations vary; Anthropic validates the model-specific
  rules.
- Unknown provider option keys and malformed values fail locally before a
  request is sent.
- The adapter uses a bounded HTTP transport and does not include the provider's
  raw error body in status errors.

For no-key application tests, use the [offline model tutorial](../offline-model-tests/).
See the [Anthropic adapter guide](https://github.com/ulises-jeremias/langchainv/blob/main/llms/anthropic/README.md)
for streaming support and other limits.
