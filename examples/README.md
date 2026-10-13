# Examples

Examples are standalone V programs. CI compiles and runs every example with the pinned V compiler. Examples marked offline do not require credentials or external services.

| Example | What it demonstrates | Runtime requirements |
|---|---|---|
| [Text splitter](text_splitter/main.v) | Recursive character chunks and Markdown-aware chunking | Offline; no credentials |
| [Prompt templates](prompts/main.v) | Named variables, template validation, and prompt formatting | Offline; no credentials |
| [Mock model](mock_model/main.v) | Provider-neutral model calls with a deterministic, concurrency-safe test double | Offline; no credentials |
| [Retrieval QA](retrieval_qa/main.v) | In-memory retrieval and a bounded question-answering chain with deterministic fakes | Offline; no credentials |
| [Return stored vectors](vector_return/main.v) | Opt-in embedding vectors in in-memory search results | Offline; no credentials |
| [SQL database](sql_database/main.v) | In-memory SQLite schema inspection, table filtering, and bound parameters | Offline; no credentials |
| [Azure AI Search retrieval](azure_retrieval/main.v) | Persistent vector search with Azure AI Search and OpenAI embeddings | Live opt-in; Azure admin key, OpenAI API key, network access, and usage charges |
| [Conversation memory](conversation_memory/main.v) | Conversation chain with process-local history and a deterministic completion fake | Offline; no credentials |
| [Tool-calling agent](tool_calling_agent/main.v) | Bounded executor, calculator tool, and staged fake model | Offline; no credentials |
| [Zep chat history](zep_history/main.v) | Read bounded session memory and optionally append a message | Live opt-in; Zep API key, session ID, and network access; appending persists data |

Run it from the repository root:

```sh
v run examples/text_splitter/main.v
```

To see prompt formatting:

```sh
v run examples/prompts/main.v
```

To see a model call without configuring a provider:

```sh
v run examples/mock_model/main.v
```

To run the retrieval and question-answering flow:

```sh
v run examples/retrieval_qa/main.v
```

To see a conversation chain carry history between turns:

```sh
v run examples/conversation_memory/main.v
```

To run the tool-calling agent without configuring a model provider:

```sh
v run examples/tool_calling_agent/main.v
```

To opt in to the Azure AI Search retrieval walkthrough, configure the variables
listed in [the tutorial](../docs/tutorials/azure-ai-search-retrieval.md), then
set `LANGCHAINV_ALLOW_LIVE_EXAMPLES=1` and run:

```sh
v run examples/azure_retrieval/main.v
```

To opt in to the Zep history walkthrough, set `ZEP_API_KEY` and
`LANGCHAINV_ZEP_SESSION_ID`, then set `LANGCHAINV_ALLOW_LIVE_EXAMPLES=1` and
run:

```sh
v run examples/zep_history/main.v
```

The example only reads by default. Set `LANGCHAINV_ZEP_APPEND_MESSAGE=1` as a
second explicit opt-in to append its sample message to that session.

Every `examples/*/main.v` must complete offline without credentials. CI compiles and runs these programs after removing `LANGCHAINV_ALLOW_LIVE_EXAMPLES`. A live provider demo must require `LANGCHAINV_ALLOW_LIVE_EXAMPLES=1` and valid credentials before sending a request. Document required environment variables, external services, expected cost, and network behavior. CI must never set the opt-in.
