# Chains

The retrieval QA variant queries an injected retriever, joins page content into
the prompt context, and returns a completion. Document count, context bytes,
and formatted prompt bytes have validated caps. Its prompt must include the
configured question and context variables. Set `return_source_documents` to
include the bounded retrieved documents under `source_documents` (or a custom
`source_documents_key`) in the chain outputs.

`new_conversational_retrieval_qa_chain` first rewrites the latest question
against bounded conversation history, then passes that standalone question to
retrieval QA. It requires memory that supplies the configured history key and
uses the same memory lifecycle as other chains. The answer prompt must require
only the question and retrieved context. The condensing prompt must contain
only the history and question variables. History, input questions, generated
questions, retrieved context, and final prompts are bounded.

The chat-model variant accepts a role-tagged prompt, sends its rendered
messages to an llms.Model, and returns the first choice's content. It shares
provider-neutral call options and the chain memory lifecycle.

`new_conversation_chain(model, memory)` creates a completion chain with a
transcript prompt. Its memory must expose `history` and be configured to save
the `input` and `output` keys; use `new_llm_chain` for a custom prompt or keys.

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

`new_transform_chain(fn, input_keys, output_keys)` adapts a caller-supplied V
function. It gives the function a copy of the input map and checks that all
declared outputs exist before returning.

The chain uses default `llms.CallOptions`. Change `options` before execution to
set provider-neutral controls. The broader LangChainGo chain family remains
tracked in the parity ledger.
