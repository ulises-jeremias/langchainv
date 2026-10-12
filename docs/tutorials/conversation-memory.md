---
layout: default
title: Keep conversation history
permalink: /tutorials/conversation-memory/
---

# Keep conversation history

A conversation chain loads prior turns before each model call and saves the
current input and answer afterward. This tutorial uses an in-memory buffer and
a deterministic completion model, so it runs without a provider, credentials,
or network access.

## Run the example

From the repository root:

```sh
v run examples/conversation_memory/main.v
```

The first turn tells the assistant a name. The second asks for it, and the fake
model answers only when the earlier turn appears in the prompt. This shows that
the chain supplied history; it does not claim to measure a live model's recall.

## Connect a model

Replace `DemoModel` with an implementation of `llms.CompletionModel`, or use a
provider adapter that implements the contract. Keep the chain and memory setup
the same, then configure credentials outside source control. Provider behavior
and option support vary, so check that adapter's guide.

## Choose a history policy

- `memory.new_conversation_buffer` retains all turns in process memory. The
  example uses this option for clarity.
- `memory.new_conversation_window_buffer` retains a bounded number of turns;
  its limit is a turn count, not a token budget.
- `memory.new_token_buffer_memory` evicts old turns using an injected token
  counter. No provider tokenizer is bundled.
- `memory/sqlite` persists typed messages and isolates them by session ID.

In-memory history disappears when the process exits. Persistent history needs
session ownership, retention, and data-protection decisions in the application.
Review the [memory package guide](https://github.com/ulises-jeremias/langchainv/blob/main/memory/README.md)
and the [chain guide](https://github.com/ulises-jeremias/langchainv/blob/main/chains/README.md)
for constructor options and limits.

## Next

- Use [retrieval QA](../retrieval-qa/) to ground answers in documents.
- Use [tool calling](../tool-calling-agent/) to dispatch bounded application tools.
