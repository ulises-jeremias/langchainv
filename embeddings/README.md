# Embeddings

`EmbedderClient` represents a provider that creates one vector per input.
`new_default_embedder(client)` adapts it to `Embedder`, removing newlines and
processing texts sequentially in batches of 512 by default. Use `new_embedder`
with `Options` to set another positive batch size or preserve newlines.

The adapter verifies that providers return one finite, non-empty, same-sized
vector for every input across all batches. `combine_vectors` computes a
weighted mean and normalizes it; mismatched dimensions, a zero weight sum, or a
zero result direction return errors.
