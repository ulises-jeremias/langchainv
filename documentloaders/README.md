# Document loaders

The package currently provides a bounded text-file loader and a CSV content
loader. Both return `schema.Document` values and check request cancellation
while loading.

`CSVLoader` creates one document per data row. It reads the first record as
column names, formats selected values as `column: value` lines, and stores the
one-based data-row number in `metadata['row']`. By default it includes every
column, accepts up to 16 MiB of CSV text, limits the formatted documents to
16 MiB, emits up to 10,000 documents, limits records to 1,024 columns, and
passes at most 16 KiB of each row to the splitter by default. Specify
`columns`, `max_bytes`, `max_output_bytes`, `max_documents`,
`max_split_input_bytes`, or `max_columns` to change those bounds:

```v
import context
import ulises_jeremias.langchainv.documentloaders

csv_text := 'question,answer\nWhy?,Because.'
mut ctx := context.background()
loader := documentloaders.new_csv_loader(csv_text, columns: ['question', 'answer'])!
documents := loader.load(mut ctx)!
```

`load_and_split` requires a `textsplitter.BoundedTextSplitter`, copies the row
metadata to every chunk, and passes explicit chunk-count, input-byte, and
output-byte limits to the splitter. Built-in splitters check these limits
before retaining their result lists. Raise `max_split_input_bytes` and
`max_documents` when splitting larger CSV content. CSV input is provided as a
string, which matches V's current `encoding.csv` reader API. Uneven row widths
are rejected. See the [parity ledger](../docs/LANGCHAINGO_PARITY.md) for
loaders that remain to be implemented.
