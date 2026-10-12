# Examples

Examples are standalone V programs. CI compiles them with the pinned V compiler. Examples marked offline do not require credentials or external services.

| Example | What it demonstrates | Runtime requirements |
|---|---|---|
| [Text splitter](text_splitter/main.v) | Recursive character chunks and Markdown-aware chunking | Offline; no credentials |
| [Prompt templates](prompts/main.v) | Named variables, template validation, and prompt formatting | Offline; no credentials |
| [Mock model](mock_model/main.v) | Provider-neutral model calls with a deterministic, concurrency-safe test double | Offline; no credentials |

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

New examples should document required environment variables, external services, expected cost, and whether compilation or execution makes network calls. Keep examples small enough for CI to compile without credentials.
