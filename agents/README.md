# Agents

`Agent` plans either one or more `schema.AgentAction` values or a terminal
`schema.AgentFinish`. `Executor` runs those plans through tools until the agent
finishes or its iteration limit is reached. The default limit is 15 and
configuration is capped at 1,000 iterations.

`ToolCallingAgent` connects any `llms.Model` that supports provider tool
calling. It sends configured inputs and prior tool steps, converts model tool
calls into executor actions, and treats assistant text as the final answer.
Its tests use a fake model and never make provider requests.

Executors implement `chains.Chain`. Pass one to `chains.call` to integrate its
optional memory through the shared chain lifecycle. Inputs must be strings.
Tool lookup is case-insensitive; an unknown tool becomes an observation so the
agent can recover. Cancellation is checked between planning and tool calls.
Callbacks receive agent actions/finishes and tool start/end/error events.

Set `return_intermediate_steps` to add an `intermediate_steps` JSON value to
the result. MRKL/conversational variants, specialized OpenAI-functions agents,
parser error recovery, and full agent initialization are not implemented yet.
Tests use deterministic fake agents, models, and tools; no provider API is
called.
