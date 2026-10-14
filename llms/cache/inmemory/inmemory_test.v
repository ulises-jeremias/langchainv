module inmemory

import context
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

fn test_cache_rejects_invalid_capacity() {
	new_cache(0) or {
		assert err.msg().contains('capacity')
		return
	}
	assert false, 'expected invalid capacity to fail'
}

fn test_cache_evicts_oldest_entry_and_snapshots_responses() {
	cache := new_cache(1) or { panic(err) }
	mut ctx := context.background()
	mut data := [u8(1), 2]
	response := llms.Response{ choices: [llms.Choice{ parts: [schema.ContentPart(schema.BinaryPart{ mime_type: 'application/octet-stream', data: data })] }] }
	cache.put(mut ctx, 'first', response)!
	data[0] = 9
	first := cache.get(mut ctx, 'first')!
	assert first.found
	if part := first.response.choices[0].parts[0] {
		assert part is schema.BinaryPart
		assert (part as schema.BinaryPart).data == [u8(1), 2]
	} else {
		assert false, 'expected cached binary content'
	}
	cache.put(mut ctx, 'second', llms.Response{ choices: [llms.Choice{ content: 'second' }] })!
	assert !cache.get(mut ctx, 'first')!.found
	second := cache.get(mut ctx, 'second')!
	assert second.found
	assert second.response.choices[0].content == 'second'
}
