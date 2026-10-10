# Chains

`new_llm_chain(model, prompt, output_key)` creates a completion chain from a
`llms.CompletionModel` and a `prompts.StringTemplate`. Its `input_keys()` come
from the template. Set `memory_store` before calling the chain to load and save
conversation state through `chains.call`.

`new_sequential_chain(children, input_keys, output_keys)` validates the key flow
between ordered child chains. Each child receives the original inputs and all
values produced by earlier children. The result contains only the selected
output keys.

`new_simple_sequential_chain(children)` handles chains that each have one
input and one output. It passes the value through using the standard `input`
and `output` keys, regardless of each child's internal key names.

The chain uses default `llms.CallOptions`. Change `options` before execution to
set provider-neutral controls. The broader LangChainGo chain family remains
tracked in the parity ledger.
