# Document loaders

The package provides bounded HTML, text-file, and CSV content loaders plus a
recursive directory loader. They return `schema.Document` values and check
request cancellation while loading.

`new_html_loader` accepts an HTML string up to 16 MiB by default and returns
one document containing parsed body text, or document text when no body exists.
`load_and_split` uses a bounded splitter and caps output at 10,000 documents
and the input byte limit. It uses V's standard-library HTML parser; network
fetching and full browser-style DOM behavior are outside this loader.

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

`RecursiveDirectoryLoader` walks the root and, by default, its immediate
subdirectories in sorted order. It reads `.txt`, `.md`, `.csv`, `.html`, and
`.htm` files,
skips symlinks and unsupported extensions, and adds each file path as
`metadata['source']`. HTML files use `HTMLLoader`; `allowed_extensions` can
narrow that set. Traversal is
bounded by 10,000 entries and documents, 16 MiB per file, and 64 MiB total
input and document output by default. Raise `max_depth`, `max_entries`,
`max_documents`, `max_file_bytes`, `max_input_bytes`, or `max_output_bytes` to
change those limits. `csv_columns` selects CSV columns. Errors reading or listing a selected path are returned to
the caller. `max_split_input_bytes` bounds each input passed to
`load_and_split`, which requires a `textsplitter.BoundedTextSplitter`.

```v
import context
import ulises_jeremias.langchainv.documentloaders

mut ctx := context.background()
loader := documentloaders.new_recursive_directory_loader(
    root: 'docs'
    allowed_extensions: ['md', 'txt']
)!
documents := loader.load(mut ctx)!
```

V 0.5.2's `os.ls` returns each directory's full entry list before the loader
can apply `max_entries`; the limit caps accepted traversal work and retained
file paths, not that one standard-library listing allocation.
