module inmemory

import context
import json2
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

fn test_cache_byte_limit_evicts_oldest_response() {
	first_response := llms.Response{ choices: [llms.Choice{ content: 'a'.repeat(128) }] }
	second_response := llms.Response{ choices: [llms.Choice{ content: 'b'.repeat(128) }] }
	response_bytes := i64(json2.encode(first_response, json2.EncoderOptions{}).len)
	assert i64(json2.encode(second_response, json2.EncoderOptions{}).len) == response_bytes
	cache := new_cache_with_limits(4, response_bytes + 1) or { panic(err) }
	mut ctx := context.background()
	cache.put(mut ctx, 'first', first_response)!
	cache.put(mut ctx, 'second', second_response)!
	assert !cache.get(mut ctx, 'first')!.found
	second := cache.get(mut ctx, 'second')!
	assert second.found
	assert second.response.choices[0].content == second_response.choices[0].content
}

fn test_oversized_response_is_not_cached_and_does_not_evict_existing_entry() {
	small := llms.Response{ choices: [llms.Choice{ content: 'kept' }] }
	max_bytes := i64(json2.encode(small, json2.EncoderOptions{}).len + 8)
	cache := new_cache_with_limits(4, max_bytes) or { panic(err) }
	mut ctx := context.background()
	cache.put(mut ctx, 'small', small)!
	cache.put(mut ctx, 'large', llms.Response{ choices: [llms.Choice{ content: 'x'.repeat(1024) }] })!
	assert cache.get(mut ctx, 'small')!.found
	assert !cache.get(mut ctx, 'large')!.found
}

fn test_cache_replacing_entry_updates_byte_accounting_without_refreshing_fifo_age() {
	small_response := llms.Response{ choices: [llms.Choice{ content: 'a'.repeat(64) }] }
	large_response := llms.Response{ choices: [llms.Choice{ content: 'b'.repeat(160) }] }
	small_bytes := i64(json2.encode(small_response, json2.EncoderOptions{}).len)
	large_bytes := i64(json2.encode(large_response, json2.EncoderOptions{}).len)
	max_bytes := large_bytes + small_bytes - 1
	cache := new_cache_with_limits(4, max_bytes) or { panic(err) }
	mut ctx := context.background()
	cache.put(mut ctx, 'first', small_response)!
	cache.put(mut ctx, 'second', small_response)!
	cache.put(mut ctx, 'first', large_response)!
	assert !cache.get(mut ctx, 'first')!.found
	assert cache.get(mut ctx, 'second')!.found
}
