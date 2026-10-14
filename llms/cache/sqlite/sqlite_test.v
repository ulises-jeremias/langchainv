module sqlite

import context
import json2
import os
import time
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.cache

fn test_sqlite_cache_persists_response_across_reopen() {
	path := os.join_path(os.temp_dir(), 'langchainv-cache-${os.getpid()}-${time.now().unix_nano()}.sqlite')
	defer {
		os.rm(path) or {}
	}
	mut ctx := context.background()
	first := new_cache(path, 10, 1024 * 1024) or { panic(err) }
	first.put(mut ctx, 'key', llms.Response{ choices: [llms.Choice{ content: 'persisted' }] }) or {
		panic(err)
	}
	first.close() or { panic(err) }

	reopened := new_cache(path, 10, 1024 * 1024) or { panic(err) }
	lookup := cache.Backend(reopened).get(mut ctx, 'key') or { panic(err) }
	assert lookup.found
	assert lookup.response.choices[0].content == 'persisted'
	reopened.close() or { panic(err) }
}

fn test_sqlite_cache_enforces_fifo_entry_and_byte_limits() {
	path := ':memory:'
	response := llms.Response{ choices: [llms.Choice{ content: 'x'.repeat(96) }] }
	response_bytes := i64(json2.encode(response, json2.EncoderOptions{}).len)
	mut ctx := context.background()
	backend := new_cache(path, 3, response_bytes + 1) or { panic(err) }
	backend.put(mut ctx, 'first', response) or { panic(err) }
	backend.put(mut ctx, 'second', response) or { panic(err) }
	assert !backend.get(mut ctx, 'first')!.found
	assert backend.get(mut ctx, 'second')!.found
	backend.put(mut ctx, 'third', response) or { panic(err) }
	assert !backend.get(mut ctx, 'second')!.found
	assert backend.get(mut ctx, 'third')!.found
	backend.close() or { panic(err) }
}

fn test_sqlite_cache_enforces_entry_limit_independently() {
	backend := new_cache(':memory:', 1, 1024 * 1024) or { panic(err) }
	mut ctx := context.background()
	backend.put(mut ctx, 'first', llms.Response{ choices: [llms.Choice{ content: 'first' }] }) or {
		panic(err)
	}
	backend.put(mut ctx, 'second', llms.Response{ choices: [llms.Choice{ content: 'second' }] }) or {
		panic(err)
	}
	assert !backend.get(mut ctx, 'first')!.found
	assert backend.get(mut ctx, 'second')!.found
	backend.close() or { panic(err) }
}

fn test_sqlite_cache_skips_oversized_entry_without_evicting_existing() {
	path := ':memory:'
	small := llms.Response{ choices: [llms.Choice{ content: 'kept' }] }
	max_bytes := i64(json2.encode(small, json2.EncoderOptions{}).len + 8)
	mut ctx := context.background()
	backend := new_cache(path, 4, max_bytes) or { panic(err) }
	backend.put(mut ctx, 'small', small) or { panic(err) }
	backend.put(mut ctx, 'large', llms.Response{ choices: [llms.Choice{ content: 'x'.repeat(1024) }] }) or {
		panic(err)
	}
	assert backend.get(mut ctx, 'small')!.found
	assert !backend.get(mut ctx, 'large')!.found
	backend.close() or { panic(err) }
}

fn test_sqlite_cache_rejects_invalid_limits_and_closed_access() {
	new_cache(':memory:', 0, 1024) or {
		assert err.msg().contains('entry limit')
		return
	}
	assert false, 'expected invalid entry limit to fail'

	backend := new_cache(':memory:', 1, 0) or {
		assert err.msg().contains('byte limit')
		return
	}
	assert false, 'expected invalid byte limit to fail'
	backend.close() or { panic(err) }
	mut ctx := context.background()
	backend.get(mut ctx, 'key') or {
		assert err.msg().contains('closed')
		return
	}
	assert false, 'expected closed backend access to fail'
}

fn test_sqlite_cache_get_honors_cancellation_before_missing_key_return() {
	backend := new_cache(':memory:', 1, 1024) or { panic(err) }
	mut parent := context.background()
	mut ctx, cancel := context.with_cancel(mut parent)
	cancel()
	backend.get(mut ctx, 'missing') or {
		assert err.msg().contains('cancel')
		backend.close() or { panic(err) }
		return
	}
	assert false, 'expected canceled lookup to fail instead of returning a cache miss'
}
