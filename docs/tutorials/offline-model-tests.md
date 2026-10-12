---
layout: default
title: Test model integrations offline
permalink: /tutorials/offline-model-tests/
---

# Test model integrations offline

Use `llmtest.MockModel` to exercise code that accepts the provider-neutral
`llms.Model` interface without API keys, network calls, or variable responses.
The mock is concurrency-safe, counts attempts, and returns copied response
snapshots.

## Run the example

From the repository root:

```sh
v run examples/mock_model/main.v
```

The program prints a deterministic response and a call count. CI compiles this
example with the pinned V compiler.

## Configure responses and failures

```v wip
model := llmtest.new_mock_model(llms.Response{
    choices: [llms.Choice{content: 'fixture answer'}]
})
model.set_error('fixture failure')
model.set_response(llms.Response{
    choices: [llms.Choice{content: 'recovered answer'}]
})
```

`set_response` clears a configured error. `call_count()` counts attempted
calls, including canceled calls and calls that return the configured error.
An optional `llms.CallOptions.streaming_func` receives the first choice as one
chunk; this mock does not model provider chunk boundaries or tool dispatch.

## Keep adapter tests hermetic

Use the mock to test application logic built against `llms.Model`. Test a
provider adapter's request encoding and response parsing separately with its
injectable fake HTTP transport. Keep tests that need real credentials or
services opt-in; see the [model compliance helpers](https://github.com/ulises-jeremias/langchainv/blob/main/testing/llmtest/README.md)
and [OpenAI adapter guide](https://github.com/ulises-jeremias/langchainv/blob/main/llms/openai/README.md).

## Next

- Build prompt inputs with the [prompt template tutorial](../prompt-templates/).
- Review the provider-neutral [model contract](https://github.com/ulises-jeremias/langchainv/blob/main/llms/llms.v).
