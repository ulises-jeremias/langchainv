# Agents

`Agent` plans either one or more `schema.AgentAction` values or a terminal
`schema.AgentFinish`. `Executor` runs those plans through tools until the agent
finishes or its iteration limit is reached. The default limit is 15 and
configuration is capped at 1,000 iterations.

`ToolCallingAgent` connects any `llms.Model` that supports provider tool
calling. It sends configured inputs and prior tool steps, converts model tool
calls into executor actions, and treats assistant text as the final answer.
Its tests use a fake model and never make provider requests.

`new_react_agent` creates a text-based MRKL/ReAct agent around an
`llms.CompletionModel`. Its prompt lists registered tools and prior
Thought/Action/Observation steps. It parses either an Action/Action Input pair
or a Final Answer and bounds tool count, description bytes, prompt bytes, and
completion output bytes. Supply a custom `prompts.StringTemplate` when the
default input-key layout does not fit. Its tests use an offline completion
model and fake tools.

Executors implement `chains.Chain`. Pass one to `chains.call` to integrate its
optional memory through the shared chain lifecycle. Inputs must be strings.
Tool lookup is case-insensitive; an unknown tool becomes an observation so the
agent can recover. Cancellation is checked between planning and tool calls.
Callbacks receive agent actions/finishes and tool start/end/error events.

Set `return_intermediate_steps` to add an `intermediate_steps` JSON value to
the result. Conversational agents, specialized OpenAI-functions agents,
advanced parser repair, and full agent initialization are not implemented yet.
Tests use deterministic fake agents, models, and tools; no provider API is
called.
