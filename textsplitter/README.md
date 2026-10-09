# Text splitters

`textsplitter` provides the common `TextSplitter` interface, a recursive
character splitter, a token-window splitter, and helpers that turn text or
documents into smaller `schema.Document` values.

## Recursive character splitting

The recursive splitter tries paragraph, line, and word separators in that
order, then falls back to Unicode code points. Its defaults match the common
LangChainGo splitter options: a 512-unit chunk and 100-unit overlap. The
default length function counts Unicode code points. A custom `length_fn` can
measure another unit; it must be deterministic and monotonic as text grows.

See [`examples/text_splitter/main.v`](../examples/text_splitter/main.v) for a
complete runnable example.

The last separator must be empty so the splitter can always make progress down
to individual Unicode code points. Chunk limits are measured with `length_fn`;
when one code point alone exceeds the limit, splitting returns an error.
The Unicode fallback inspects at most 4096 code points per window by default;
`max_fallback_runes` changes that bound when custom length units need larger
windows, up to a hard limit of 1,000,000. This keeps working storage bounded
for very large unbroken inputs. Text that reaches the fallback must be valid
UTF-8.

## Token windows

`TokenSplitter` receives a `Tokenizer` implementation instead of bundling a
provider-specific encoding package. Its `encode` method runs once per input;
chunks are decoded from overlapping token windows. Implementations may wrap a
local tokenizer library or a provider tokenizer. This package does not make
network calls to download tokenizer data.

## Markdown splitting

`MarkdownTextSplitter` keeps source Markdown lines and uses ATX/Setext headings,
paragraphs, fenced code blocks, and GFM table rows as structural boundaries. It
can prepend the current heading or the full heading hierarchy to content chunks,
include fenced code blocks, and group table rows up to the configured limit.
Fenced code blocks are omitted by default. Set `reference_links: true` to
resolve recognized CommonMark reference links using V's `x/markdown` parser
and render them as inline destinations, including titles. The package imports
`x/markdown` at compile time even when this option is false, so consumers of
`textsplitter` need a compiler that provides that experimental module. Code
fences, indented code, and inline code are kept unchanged. It uses the same
length callback and chunk overlap rules as the recursive splitter.

The splitter still uses a line-oriented block pass and does not preserve every
CommonMark AST construct; see the parity ledger for the remaining gaps.

## Documents

`split_documents` copies each source document's metadata and score to every
chunk. `create_documents` accepts a metadata map per text, or an empty metadata
slice to create documents without metadata. Metadata maps are copied so edits to
one output chunk do not mutate the input map.

Provider-specific tokenizer adapters and full CommonMark block handling remain
outstanding; see the
[parity ledger](../docs/LANGCHAINGO_PARITY.md).
