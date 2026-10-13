# Agents

`Agent` plans either one or more `schema.AgentAction` values or a terminal
`schema.AgentFinish`. `Executor` runs those plans through tools until the agent
finishes or its iteration limit is reached. The default limit is 15 and
configuration is capped at 1,000 iterations.

`ToolCallingAgent` connects any `llms.Model` that supports provider tool
calling. It sends configured inputs and prior tool steps, converts model tool
calls into executor actions, and treats assistant text as the final answer.
Grouped tool calls are replayed in one assistant message followed by their
tool results. Single-string calls encoded as `{"__arg1":"..."}` are passed
to the tool as the inner string. Its tests use a fake model and never make
provider requests.

`new_openai_functions_agent` is a preset over the same provider-neutral model
contract. Its default keys are `input` and `output`; configure other keys,
system instructions, fixed extra messages, and model options through
`OpenAIFunctionsAgentOptions`. Tool schemas come from each `ToolSpec`, so the
preset preserves structured parameters instead of reducing every tool to a
single string argument. Provider adapters must support function/tool calls.

`new_react_agent` creates a text-based MRKL/ReAct agent around an
`llms.CompletionModel`. Its prompt lists registered tools and prior
Thought/Action/Observation steps. It parses either an Action/Action Input pair
or a Final Answer and bounds tool count, description bytes, prompt bytes, and
completion output bytes. Output recovery accepts case-insensitive and inline
Action/Action Input or final-answer labels while preserving control-like text
inside the tool input. Labels must start at a word boundary, so prose such as
`Interaction:` is not mistaken for `Action:`. Malformed or incomplete action
output returns an error.
Supply a custom `prompts.StringTemplate` when the default input-key layout does
not fit. Its tests use an offline completion model and fake tools.

`new_conversational_react_agent` adds a `history` input to the ReAct prompt.
Attach a memory implementation through `ExecutorOptions.memory`, then call the
executor with `chains.call` to load prior turns and save the latest question
and answer. The constructor accepts the same prompt, byte-limit, and model-call
options as `new_react_agent`.

`initialize_agent` constructs either preset and its executor in one call. Use
`AgentType.react` or `AgentType.conversational_react`, provide `ReactOptions`
for the prompt and model, then `ExecutorOptions` for iteration limits, memory,
callbacks, and executor call defaults. The V enum keeps supported agent types
explicit at compile time.

Executors implement `chains.Chain`. Pass one to `chains.call` to integrate its
optional memory through the shared chain lifecycle. Inputs must be strings.
Tool lookup is case-insensitive; an unknown tool becomes an observation so the
agent can recover. Cancellation is checked between planning and tool calls.
Callbacks receive agent actions/finishes and tool start/end/error events.

Set `return_intermediate_steps` to add an `intermediate_steps` JSON value to
the result. Agent setup remains explicit; there is no automatic tool
discovery. Tests use deterministic fake agents, models, and tools; no provider
API is called.
