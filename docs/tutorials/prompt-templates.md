---
layout: default
title: Build prompts from templates
permalink: /tutorials/prompt-templates/
---

# Build prompts from templates

String templates make required model inputs explicit. `input_variables()` validates and lists placeholders, while `format()` returns an error if a value is missing or the template is malformed.

## Complete offline example

```v
module main

import json2
import ulises_jeremias.langchainv.prompts

fn main() {
	template := prompts.StringTemplate{
		template: 'Explain {topic} for a {audience} audience in {style}.'
	}
	variables := template.input_variables() or { panic(err) }
	println('Inputs: ${variables.join(', ')}')

	prompt := template.format({
		'topic':    json2.Any('V modules')
		'audience': json2.Any('new developer')
		'style':    json2.Any('three short steps')
	}) or { panic(err) }
	println(prompt)
}
```

Run it from the repository root:

```sh
v run examples/prompts/main.v
```

This example formats text only. It does not call a model or require an API key. CI compiles every standalone example with the repository's pinned V compiler.

## Chat prompts

Use `ChatPromptTemplate` when a provider call needs role-tagged messages. Each `ChatMessageTemplate` pairs a `schema.Role` with a `StringTemplate`; `format_messages()` returns validated `schema.Message` values. See the [prompts package guide](https://github.com/ulises-jeremias/langchainv/blob/main/prompts/README.md) for few-shot examples, selectors, brace escaping, and current limits.

## Next

- [Call a model](https://github.com/ulises-jeremias/langchainv/blob/main/llms/openai/README.md) using an explicit provider adapter and keep keys out of source control.
- Continue through the [tutorial learning path](../).
