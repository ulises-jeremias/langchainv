module inmemory

import context
import ulises_jeremias.langchainv.llms

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
	mut response := llms.Response{ choices: [llms.Choice{ content: 'original' }] }
	cache.put(mut ctx, 'first', response)!
	response.choices[0].content = 'mutated'
	first := cache.get(mut ctx, 'first')!
	first_response := first or { panic('expected cached response') }
	assert first_response.choices[0].content == 'original'
	cache.put(mut ctx, 'second', llms.Response{ choices: [llms.Choice{ content: 'second' }] })!
	assert cache.get(mut ctx, 'first')! == none
	second := cache.get(mut ctx, 'second')!
	second_response := second or { panic('expected second response') }
	assert second_response.choices[0].content == 'second'
}
