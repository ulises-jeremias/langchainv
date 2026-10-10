# Memory

`new_simple_memory()` implements the memory interface without storing values.
`new_conversation_buffer(memory_key, input_key, output_key)` stores the full
conversation in process memory. `new_conversation_window_buffer(window_size,
memory_key, input_key, output_key)` stores only the latest `window_size` turns.
Each turn is one human and one assistant message. A non-positive window size
uses the default of five turns; sizes above 10,000 return an error. This window
limits message count, not tokens.

The token buffer constructor accepts an injected llms.TokenCounter, model,
token limit, and memory/input/output keys. It evicts oldest complete
human/assistant turns after each save until the retained messages fit the
positive token limit. If the newest turn alone exceeds the limit, history is
cleared. A counter error leaves the previous history unchanged. No provider
tokenizer is bundled.

All memory implementations expose `clear(mut ctx)` through the `schema.Memory`
interface; it removes stored state or succeeds without changing state for
no-op memory.
