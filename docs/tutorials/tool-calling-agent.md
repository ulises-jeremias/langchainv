---
layout: default
title: Build a tool-calling agent
permalink: /tutorials/tool-calling-agent/
---

# Build a tool-calling agent

A function-calling model proposes a named tool and JSON arguments. The executor
looks up that tool, runs it, sends the result back to the model, and stops when
the model returns text. The example uses the bounded calculator and a staged
fake model with `new_openai_functions_agent`, so it runs offline and never
calls a provider. The preset accepts any `llms.Model` adapter that supports
function/tool calls.

## Run the example

From the repository root:

```sh
v run examples/tool_calling_agent/main.v
```

The fake model first requests `calculator` with the expression `6 * 7`. After
the executor returns `42`, it produces the final answer. The same sequence
uses the public `llms.Model` contract as a provider adapter.

## Understand the boundaries

- `new_openai_functions_agent` supplies the model with the tool name, description,
  parameter schema, input question, and previous tool results. When a model
  requests several tools in one response, the next model request replays the
  grouped calls before their corresponding results.
- `new_executor` limits the number of model planning rounds. It calls only
  tools registered with that agent.
- `tools.new_calculator()` evaluates a bounded arithmetic expression. It does
  not execute V or shell code.
- `return_intermediate_steps` includes the dispatched action and observation
  in the result map, which helps debug application behavior.

The executor checks cancellation between planning and tool calls. Set a small
iteration limit, expose only tools the model needs, and validate any
application-specific input before it reaches a tool. A model response is a
request to your application, not permission to bypass tool checks.

## Connect a provider

Replace `DemoModel` with an adapter implementing `llms.Model`. Provider support
for function calling and tool schemas varies; check the chosen adapter's guide
and test its HTTP behavior with an injected fake transport. The executor and
tools can still be tested offline with a staged model like this example.

See the [agents package guide](https://github.com/ulises-jeremias/langchainv/blob/main/agents/README.md)
for ReAct agents, input/output keys, callbacks, cancellation, and current gaps.

## Next

- Use the [offline mock model tutorial](../offline-model-tests/) for application tests.
- Review the [security guidance](https://github.com/ulises-jeremias/langchainv/blob/main/SECURITY.md)
  before connecting tools that can change external state.
