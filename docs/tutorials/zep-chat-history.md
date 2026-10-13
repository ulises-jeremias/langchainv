---
layout: default
title: Persist chat history with Zep
permalink: /tutorials/zep-chat-history/
---

# Persist chat history with Zep

This walkthrough connects the shared `schema.ChatMessageHistory` contract to a
Zep API v2 session. The adapter requests a bounded history window, adds Zep's
facts and latest summary as system context, and can append human, assistant,
and tool messages. Its HTTP transport can be replaced with a deterministic
fake for offline tests.

## Configure access

Create or select a Zep session and set:

- `ZEP_API_KEY` — Zep API key. The adapter sends it in an `Authorization:
  Api-Key ...` header.
- `LANGCHAINV_ZEP_SESSION_ID` — the session to read. Reads do not modify it.
- `LANGCHAINV_ALLOW_LIVE_EXAMPLES=1` — explicit opt-in to network requests.

The default endpoint is `https://api.getzep.com/api/v2`. Custom endpoints must
use HTTPS. The bounded default HTTP client validates TLS, disables redirects,
uses a timeout, and caps the response body at 16 MiB; the history adapter
applies a stricter 4 MiB response limit and requests at most 1,024 messages by
default.

## Read a session

From the repository root, run:

```sh
v run examples/zep_history/main.v
```

Without `LANGCHAINV_ALLOW_LIVE_EXAMPLES=1`, the program exits before reading
credentials or contacting Zep. CI removes the opt-in variable, so it compiles
and exercises only this offline path. The example reads the configured session
and prints the number of returned messages; it does not clear or otherwise
modify the session by default.

## Explicitly append a message

To also append the example's sample user message, set
`LANGCHAINV_ZEP_APPEND_MESSAGE=1`. This is a second opt-in because the write
persists in the selected session. The example never calls `clear`; remove any
sample message through your normal Zep session-management process if needed.

## Use in an application

Construct `memory.zep.ChatMessageHistory` with `new_chat_message_history` and
pass it to memory or chain components that accept the shared
`schema.ChatMessageHistory` interface. `Options.max_messages` can be set from
1 to 4,096. The adapter rejects an individual message or combined fact/summary
context above 64 KiB, and rejects Zep responses above 4 MiB. Writes support
human, assistant, and tool roles; system and generic messages fail explicitly.
See the [package guide](https://github.com/ulises-jeremias/langchainv/blob/main/memory/zep/README.md)
for API details and `new_chat_message_history_with_client` for offline HTTP
fixtures.
