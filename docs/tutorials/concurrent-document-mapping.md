---
layout: default
title: Concurrent document mapping
permalink: /tutorials/concurrent-document-mapping/
---

# Concurrent document mapping

Map-reduce and map-rerank evaluate each document independently. Both chains can
run up to five mapping calls at once. They default to one worker so existing
models keep sequential behavior until you opt in.

This offline example uses a stateless completion model. It demonstrates
map/reduce ordering without API keys, a provider, or network calls.

```v
module main

import context
import ulises_jeremias.langchainv.chains
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema

struct EchoCompletionModel {}

fn (EchoCompletionModel) complete(mut _ctx context.Context, prompt string, _options llms.CallOptions) !string {
	return prompt
}

fn main() {
	model := EchoCompletionModel{}
	map_chain := chains.new_llm_chain(model, prompts.StringTemplate{
		template: 'Map: {context}'
	}, 'mapped') or { panic(err) }
	reduce_llm_chain := chains.new_llm_chain(model, prompts.StringTemplate{
		template: '{context}'
	}, 'answer') or { panic(err) }
	reduce_chain := chains.new_stuff_documents_chain(reduce_llm_chain,
		chains.StuffDocumentsOptions{}) or { panic(err) }
	chain := chains.new_map_reduce_documents_chain(map_chain, reduce_chain,
		chains.MapReduceDocumentsOptions{
			max_concurrency: 3
		}) or { panic(err) }
	mut ctx := context.background()
	outputs := chains.call(mut ctx, chain, {
		'input_documents': chains.documents_value([
			schema.new_document('First note.')
			schema.new_document('Second note.'),
		])
	}) or { panic(err) }
	println((outputs['answer'] or { panic('missing answer') }).str())
}
```

The output keeps the source order:

```text
Map: First note.

Map: Second note.
```

## Set a safe worker count

Choose a value from 1 to 5. Each worker calls the same model concurrently, so
the model implementation, callback functions, and any mutable state they use
must be safe for concurrent calls. Use the same setting on
`MapRerankDocumentsOptions` to rank documents concurrently. Tied scores retain
their original document order.

The chain keeps the parent context and checks cancellation between batches and
after each batch completes. Each batch has at most five calls. The chain waits
for that batch before checking model errors, parsing map-rerank output, or
validating map-reduce output size. Calls already started in the batch may
therefore finish even when one result is invalid. The chain returns the first
error in document order and starts no later batch. Refinement stays sequential
because each step needs the answer from the previous step.

Live providers may charge for each request and enforce request-rate limits.
Start with one worker when using a provider, then raise the limit only after
checking its concurrency and quota rules. For option details, see the
[chains guide](https://github.com/ulises-jeremias/langchainv/blob/main/chains/README.md).
