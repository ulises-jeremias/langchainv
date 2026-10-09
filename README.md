# LangChainV

LangChainV is a composable framework for building applications with language
models in V. Its target is feature parity with the public LangChainGo API, with
V-native interfaces, errors, options, and resource handling.

The shared core contracts are the first implementation slice. The parity
matrix in [`docs/LANGCHAINGO_PARITY.md`](docs/LANGCHAINGO_PARITY.md) is the
source of truth for supported and outstanding features. A package is supported
only when its implementation and documented validation are complete.

## Install

```sh
v install ulises-jeremias.langchainv
```

V normalizes the import prefix to `ulises_jeremias.langchainv`:

```v
import ulises_jeremias.langchainv
```

The current core packages include:

- `schema`: documents, multimodal messages, and shared interfaces.
- `llms`: model contracts and provider-neutral generation results.
- `embeddings`: embedding contracts, batching, and vector math.
- `tools`: agent tool contracts.
- `memory`: in-memory chat history and conversation buffer.
- `prompts`: validated string templates.
- `outputparser`: simple, boolean, and comma-separated list parsers.
- `jsonschema`: the JSON Schema definition model used for tool and function
  parameters. See [`jsonschema/README.md`](jsonschema/README.md).
- `chains`: chain contract, memory loading, and input/output validation.
- `callbacks`: lifecycle event contract.
- `vectorstores`: storage contract and retriever adapter.
- `documentloaders`: size-bounded text-file loader.
- `httputil`: outbound user-agent defaults, API-key query handling, and
  credential-redacted diagnostics. See [`httputil/README.md`](httputil/README.md).

Provider and component packages use nested import paths such as
`ulises_jeremias.langchainv.llms.openai`.

The initial OpenAI adapter provides text chat completions, prompt completion,
and embeddings through `llms.openai`. Its unsupported capabilities are listed
in the parity ledger.

## Compatibility

- V 0.5.2 or newer, subject to compiler compatibility notes in the docs.
- Core packages are designed to use V's standard library without mandatory
  third-party dependencies.
- Optional integrations may use VSL or VTL when that is the best V-native
  backend; those dependencies will remain isolated to their adapters.

## Project status

LangChainGo has a broad integration surface. This project tracks its APIs and
integrations explicitly rather than implying full compatibility from a small
set of working examples. See [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md)
and [`docs/LANGCHAINGO_PARITY.md`](docs/LANGCHAINGO_PARITY.md).

## License

MIT. See [LICENSE](LICENSE).
