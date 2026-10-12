---
layout: default
title: Build a conversational ReAct agent with memory
permalink: /tutorials/conversational-agent-memory/
---

# Build a conversational ReAct agent with memory

`initialize_agent` can construct the conversational ReAct preset and its
`Executor` together. Choose `.conversational_react` and provide a memory
implementation through `ExecutorOptions`; `chains.call` then loads prior turns
before planning and saves the new input and answer afterward. Use `.react` for
the stateless preset.

This complete example uses an offline model and an in-memory conversation
buffer. It needs no API key or network connection.

{% highlight v %}
{% include tutorials/conversational_react_agent.v %}
{% endhighlight %}

It prints:

```text
I will remember your name.
Your name is Ada.
```

The fake model returns the second answer only when the prior turn appears in its
prompt. Replace `ConversationDemoModel` with a provider-backed
`llms.CompletionModel` to use a live model. Keep provider credentials outside
source control and check the provider's rate and cost limits before enabling
tool calls.

The constructor accepts a custom `ReactOptions.prompt` and additional input
keys. Include `{history}` in a custom prompt. If an `ExecutorOptions.memory`
implementation uses different input or output keys, configure it to match the
keys passed to `chains.call`.

## Next

- Review [memory policies](../conversation-memory/) before keeping conversation
  history beyond one process.
- Read the [agent guide](https://github.com/ulises-jeremias/langchainv/blob/main/agents/README.md)
  for action limits, tool behavior, callbacks, and executor options.
