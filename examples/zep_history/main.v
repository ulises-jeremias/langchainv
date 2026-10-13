module main

import context
import os
import ulises_jeremias.langchainv.memory.zep
import ulises_jeremias.langchainv.schema

fn main() {
	if os.getenv('LANGCHAINV_ALLOW_LIVE_EXAMPLES') != '1' {
		println('Live Zep access is disabled. Read examples/README.md before opting in.')
		return
	}
	api_key := os.getenv('ZEP_API_KEY').trim_space()
	session_id := os.getenv('LANGCHAINV_ZEP_SESSION_ID').trim_space()
	if api_key == '' || session_id == '' {
		eprintln('Set ZEP_API_KEY and LANGCHAINV_ZEP_SESSION_ID.')
		exit(2)
	}
	mut history := zep.new_chat_message_history(zep.Options{
		api_key:    api_key
		session_id: session_id
	}) or { panic(err) }
	defer {
		history.close()
	}
	mut ctx := context.background()
	messages := history.get_messages(mut ctx) or { panic(err) }
	println('Loaded ${messages.len} Zep messages for ${session_id}.')
	if os.getenv('LANGCHAINV_ZEP_APPEND_MESSAGE') == '1' {
		history.add_message(mut ctx, schema.text_message(.human, 'LangChainV Zep history example.')) or {
			panic(err)
		}
		println('Appended the sample message to the selected session.')
	}
}
