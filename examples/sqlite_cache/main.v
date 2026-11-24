module main

import context
import os
import time
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.cache
import ulises_jeremias.langchainv.llms.cache.sqlite
import ulises_jeremias.langchainv.llms.fake
import ulises_jeremias.langchainv.schema

fn main() {
	path := os.join_path(os.temp_dir(), 'langchainv-cache-example-${os.getpid()}-${time.now().unix_nano()}.sqlite')
	defer {
		os.rm(path) or {}
	}

	backend := sqlite.new_cache(path, 8, 1024 * 1024) or {
		panic(err)
	}
	defer {
		backend.close() or { panic(err) }
	}

	model := cache.new_cacher(llms.Model(fake.new_fake_llm([
		'This response was generated once and then cached.',
		'This response would prove the cache was bypassed.',
	])),
		backend)
	mut ctx := context.background()
	messages := [schema.text_message(.human, 'Explain response caching in one sentence.')]
	first_response := model.generate_content(mut ctx, messages, llms.CallOptions{}) or {
		panic(err)
	}
	second_response := model.generate_content(mut ctx, messages, llms.CallOptions{}) or {
		panic(err)
	}
	first := first_response.choices[0].content
	second := second_response.choices[0].content

	println('First call:  ${first}')
	println('Second call: ${second}')
	println('Cache hit:   ${first == second}')
	println('Temporary database removed on exit: ${path}')
}
