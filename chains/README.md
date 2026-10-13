# Chains

`new_stuff_documents_chain` accepts an array created by
`documents_value(documents)` under `input_documents` by default, joins each
document's `page_content`, and inserts the result into the configured prompt
variable (default `context`). Additional prompt variables pass through to the
inner `LLMChain`. Configure the separator, input/variable names, and document
count and byte limits with `StuffDocumentsOptions`. Invalid document objects
and oversized contexts fail before the model call.

`new_map_reduce_documents_chain` maps each bounded input document through an
`LLMChain`, retains its metadata, and passes the mapped documents to a reducer
chain. Set `MapReduceDocumentsOptions.max_concurrency` from 1 to 5 to map
documents concurrently; it defaults to 1. The returned documents and optional
`intermediate_steps` stay in input order. Models, callbacks, and context values
used by concurrent calls must support concurrent access. If a worker fails, the
chain waits for the current bounded batch to finish and returns the error from
the earliest document in input order. Parent cancellation is checked before
each batch and after its workers finish. The chain validates mapped output only
after the batch finishes, so calls already started in a batch may complete
before an invalid or oversized result is reported. It starts no later batch
after an error. The options also set the document key, map and reduce prompt
variables, document count and byte caps, optional memory, and intermediate-step
output. The default caps are 16 documents and 64 KiB of source and combined
mapped text; configured caps are limited to 128 documents and 1 MiB. The
reducer determines the final outputs.

`new_map_rerank_documents_chain` runs an `LLMChain` once per document and
expects each completion to contain an answer followed by `Score: <integer>`.
It sorts results by descending score, returns the best answer under the LLM
chain's output key, and can include sorted `{answer, score}` intermediate
steps. Set `MapRerankDocumentsOptions.max_concurrency` from 1 to 5 to map
documents concurrently; it defaults to 1. Tied scores keep their input order.
Models, callbacks, and context values used by concurrent calls must support
concurrent access. The chain waits for each current batch before parsing its
results, so other started calls may finish before invalid output or a
non-integer score fails the call. It starts no later batch after an error. It
uses the same default and maximum document count and byte caps as map-reduce.

`new_refine_documents_chain` formats the first document, creates an initial
answer, then calls a second `LLMChain` with the previous answer and each later
document. Its document prompt can use `page_content` and document metadata.
Caller-supplied inputs needed by either prompt pass through to both chains. It
requires at least one document and bounds document count, source
bytes, and formatted document bytes before calling either model.

Question answering presets are available through `load_stuff_qa`,
`load_refine_qa`, `load_map_reduce_qa`, and `load_map_rerank_qa`. Each takes a
completion model and returns the corresponding bounded document chain.
`load_condense_question_generator` creates a prompt chain for rewriting a
follow-up question using `chat_history` and `question`.

Summarization presets are available through `load_stuff_summarization`,
`load_refine_summarization`, and `load_map_reduce_summarization`. They use the
same document-count and byte bounds as the underlying document chains.

The retrieval QA variant queries an injected retriever, joins page content into
the prompt context, and returns a completion. Document count, context bytes,
and formatted prompt bytes have validated caps. Its prompt must include the
configured question and context variables. Set `return_source_documents` to
include the bounded retrieved documents under `source_documents` (or a custom
`source_documents_key`) in the chain outputs.

`new_conversational_retrieval_qa_chain` rewrites follow-up questions against
bounded conversation history and skips rewriting when history is empty. The
standalone question always drives retrieval. Set `rephrase_question: false` to
send the original question to the answer prompt, and
`return_generated_question: true` to include `generated_question` in the
outputs. It requires memory that supplies the configured history key and uses
the same memory lifecycle as other chains. The answer prompt must require only
the question and retrieved context. The condensing prompt must contain only
the history and question variables. History, input questions, generated
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

`new_constitutional_chain(chain, principles, options)` wraps an `LLMChain` with
sequential critique and revision passes. Each principle has a unique name and
non-empty critique and revision requests. The default prompts can be replaced
with templates containing `critique_request`, `revision_request`,
`input_prompt`, `response`, and `critique` as appropriate. The chain bounds the
principle count and each formatted prompt/response size, checks cancellation
between model calls, and can return `initial_output` plus
`critiques_and_revisions` when `return_intermediate` is enabled. Conversation
memory remains owned by the wrapped chain.

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

`new_sql_database_chain(database, model, options)` answers a question in
three bounded steps. It reads the schema of the configured tables from a
`sqldatabase.SQLDatabase`, asks the model for one SQL query, runs it, and
asks the model to write the final answer from the tab-separated result. The
chain only runs a single read-only `SELECT` or `WITH` statement. Anything
else the model returns is rejected before it reaches the database, and
fenced replies and `SQLQuery:` prefixes are accepted. Question and formatted
prompt sizes have validated caps, the SQL and answer prompts can be replaced
when they keep the required variables, and `return_intermediate_steps` adds
the executed query and its result to the outputs. Writes, schema changes,
and multi-statement SQL belong in the `tools/sqldatabase` API used directly,
not in this chain.

The chain uses default `llms.CallOptions`. Change `options` before execution to
set provider-neutral controls. The broader LangChainGo chain family remains
tracked in the parity ledger.
