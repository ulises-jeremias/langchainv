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
- `outputparser`: string, boolean, list, regex, structured, combining, and
  typed JSON parsers.
- `chains`: chain contract, memory loading, and input/output validation.
- `callbacks`: lifecycle event contract, ordered dispatch, no-op handler, and
  handler composition.
- `vectorstores`: storage contract and retriever adapter.
- `documentloaders`: size-bounded text-file and CSV content loaders, with row
  filtering and document splitting.
- `textsplitter`: recursive character and tokenizer-injected token chunks, plus
  Markdown-aware heading, paragraph, fenced-code, table-row, and optional
  reference-link splitting.

Provider and component packages use nested import paths such as
`ulises_jeremias.langchainv.llms.openai`.

See [`textsplitter/README.md`](textsplitter/README.md) for chunking options and
the tokenizer interface.

See [`outputparser/README.md`](outputparser/README.md) for parser behavior and
the current V regular-expression compatibility boundary.

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
