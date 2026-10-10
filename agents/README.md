# Agents

`Agent` plans either one or more `schema.AgentAction` values or a terminal
`schema.AgentFinish`. `Executor` runs those plans through tools until the agent
finishes or its iteration limit is reached. The default limit is 15 and
configuration is capped at 1,000 iterations.

Executors implement `chains.Chain`. Pass one to `chains.call` to integrate its
optional memory through the shared chain lifecycle. Inputs must be strings.
Tool lookup is case-insensitive; an unknown tool becomes an observation so the
agent can recover. Cancellation is checked between planning and tool calls.
Callbacks receive agent actions/finishes and tool start/end/error events.

Set `return_intermediate_steps` to add an `intermediate_steps` JSON value to
the result. Provider-backed planning agents, MRKL/conversational variants,
parser error recovery, and agent initialization helpers are not implemented
yet. Tests use deterministic fake agents and tools; no provider API is called.
