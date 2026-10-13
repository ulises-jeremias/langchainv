# Zep chat history

`ulises_jeremias.langchainv.memory.zep` implements the Zep chat-history
adapter over the API v2 session-memory endpoints used by LangChainGo.

```v
import context
import os
import ulises_jeremias.langchainv.memory.zep

mut history := zep.new_chat_message_history(zep.Options{
	api_key:    os.getenv('ZEP_API_KEY')
	session_id: 'conversation-42'
})!
defer {
	history.close()
}
mut ctx := context.background()
messages := history.get_messages(mut ctx)!
println('Loaded ${messages.len} messages')
```

An empty session ID selects `default`. The default endpoint is
`https://api.getzep.com/api/v2`; a custom base URL must also use HTTPS and
must not contain query or fragment components. The API key can be passed in
`Options.api_key` or read from `ZEP_API_KEY`. Requests use the `Authorization:
Api-Key ...` header. Errors do not include response bodies or credentials.

The default read requests the most recent 1,024 messages with `memoryType` set
to `perpetual`. `Options.max_messages` accepts 1 through 4,096. The adapter
rejects responses larger than 4 MiB and individual messages, summaries, or
combined fact/summary context larger than 64 KiB. Zep facts and its latest
summary are returned as one leading system message. Unknown remote roles are
skipped; user, assistant, tool, and function roles map to the shared V message
types.

Writes support human, assistant, and tool messages, with optional human and AI
role prefixes. System and generic writes return an error. `clear` deletes the
selected session's Zep memory, so call it only when that session should be
removed. `close` prevents future calls but does not own or close an injected
HTTP client.

For offline tests, inject an `httputil.HTTPClient` with
`new_chat_message_history_with_client`. The [runnable walkthrough](../../docs/tutorials/zep-chat-history.md)
reads a session by default and requires a second opt-in before appending data.
