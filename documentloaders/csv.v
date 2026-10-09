// Package documentloaders reads source data into shared document values.
module documentloaders

import context
import encoding.csv as csv_parser
import json2
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.textsplitter

const default_max_csv_bytes = i64(16 * 1024 * 1024)
const default_max_csv_output_bytes = i64(16 * 1024 * 1024)
const default_max_csv_documents = 10_000
const default_max_csv_split_input_bytes = 16 * 1024
const default_max_csv_columns = 1024

// CSVLoaderOptions configures selected columns and input/output resource limits.
@[params]
pub struct CSVLoaderOptions {
pub:
	columns                 []string
	max_bytes               i64 = default_max_csv_bytes
	max_output_bytes        i64 = default_max_csv_output_bytes
	max_documents           int = default_max_csv_documents
	max_split_input_bytes   int = default_max_csv_split_input_bytes
	max_columns             int = default_max_csv_columns
}

// CSVLoader converts CSV rows into one document per data row.
pub struct CSVLoader {
	data                  string
	columns               []string
	max_bytes             i64
	max_output_bytes      i64
	max_documents         int
	max_split_input_bytes int
	max_columns           int
}

// new_csv_loader constructs a loader for CSV text. An empty column list keeps
// all columns. Zero byte limits and max_documents select defaults of 16 MiB
// for input and formatted output, and 10,000 documents.
pub fn new_csv_loader(data string, options CSVLoaderOptions) !CSVLoader {
	if options.max_bytes < 0 {
		return error('maximum CSV size cannot be negative')
	}
	if options.max_documents < 0 {
		return error('maximum CSV document count cannot be negative')
	}
	if options.max_output_bytes < 0 {
		return error('maximum CSV output size cannot be negative')
	}
	if options.max_split_input_bytes < 0 {
		return error('maximum CSV split input size cannot be negative')
	}
	if options.max_columns < 0 {
		return error('maximum CSV column count cannot be negative')
	}
	max_bytes := if options.max_bytes == 0 {
		default_max_csv_bytes
	} else {
		options.max_bytes
	}
	max_documents := if options.max_documents == 0 {
		default_max_csv_documents
	} else {
		options.max_documents
	}
	max_output_bytes := if options.max_output_bytes == 0 {
		default_max_csv_output_bytes
	} else {
		options.max_output_bytes
	}
	max_split_input_bytes := if options.max_split_input_bytes == 0 {
		default_max_csv_split_input_bytes
	} else {
		options.max_split_input_bytes
	}
	max_columns := if options.max_columns == 0 {
		default_max_csv_columns
	} else {
		options.max_columns
	}
	if i64(data.len) > max_bytes {
		return error('CSV data is ${data.len} bytes, above the ${max_bytes}-byte limit')
	}
	return CSVLoader{
		data:                  data
		columns:               options.columns.clone()
		max_bytes:             max_bytes
		max_output_bytes:      max_output_bytes
		max_documents:         max_documents
		max_split_input_bytes: max_split_input_bytes
		max_columns:           max_columns
	}
}

// load parses the header and converts each data row into a document. Metadata
// contains the one-based row number, matching LangChainGo's CSV loader.
pub fn (loader CSVLoader) load(mut ctx context.Context) ![]schema.Document {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	if loader.max_bytes <= 0 || i64(loader.data.len) > loader.max_bytes {
		return error('CSV data exceeds the configured size limit')
	}
	validate_csv_quotes(loader.data, loader.max_columns)!
	if loader.data.len == 0 {
		return []schema.Document{}
	}
	mut reader := csv_parser.new_reader(loader.data, csv_parser.ReaderConfig{
		comment: 0
	})
	mut header := []string{}
	mut documents := []schema.Document{}
	mut row_number := 0
	mut output_bytes := i64(0)
	for {
		ctx_error := ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
		row := reader.read() or {
			if err.msg() == 'encoding.csv: end of file' {
				break
			}
			return err
		}
		if header.len == 0 {
			header = row
			continue
		}
		if row.len != header.len {
			return error('CSV row ${row_number + 2} has ${row.len} fields; expected ${header.len}')
		}
		if documents.len >= loader.max_documents {
			return error('CSV document count exceeds the ${loader.max_documents}-document limit')
		}
		mut lines := []string{}
		for index, value in row {
			if loader.columns.len > 0 && !loader.columns.contains(header[index]) {
				continue
			}
			lines << '${header[index]}: ${value}'
		}
		page_content := lines.join('\n')
		if output_bytes + i64(page_content.len) > loader.max_output_bytes {
			return error('formatted CSV documents exceed the ${loader.max_output_bytes}-byte output limit')
		}
		output_bytes += i64(page_content.len)
		row_number++
		mut metadata := map[string]json2.Any{}
		metadata['row'] = json2.Any(row_number)
		documents << schema.Document{
			page_content: page_content
			metadata:     metadata
		}
	}
	return documents
}

fn validate_csv_quotes(data string, max_columns int) ! {
	mut in_quotes := false
	mut after_quote := false
	mut at_field_start := true
	mut field_count := 1
	mut index := 0
	for index < data.len {
		character := data[index]
		if in_quotes {
			if character == `"` {
				if index + 1 < data.len && data[index + 1] == `"` {
					index += 2
					continue
				}
				in_quotes = false
				after_quote = true
			}
			index++
			continue
		}
		if after_quote {
			if character == `,` {
				after_quote = false
				at_field_start = true
				field_count++
			} else if character == `\n` {
				after_quote = false
				at_field_start = true
				field_count = 1
			} else if character == `\r` && index + 1 < data.len && data[index + 1] == `\n` {
				after_quote = false
				at_field_start = true
				field_count = 1
				index += 2
				continue
			} else {
				return error('unexpected character after a quoted CSV field')
			}
			index++
			if field_count > max_columns {
				return error('CSV record exceeds the ${max_columns}-column limit')
			}
			continue
		}
		if character == `"` {
			if !at_field_start {
				return error('unexpected quote in an unquoted CSV field')
			}
			in_quotes = true
		} else if character == `,` {
			at_field_start = true
			field_count++
		} else if character == `\n` {
			at_field_start = true
			field_count = 1
		} else if character == `\r` && index + 1 < data.len && data[index + 1] == `\n` {
			at_field_start = true
			field_count = 1
			index += 2
			continue
		} else {
			at_field_start = false
		}
		if field_count > max_columns {
			return error('CSV record exceeds the ${max_columns}-column limit')
		}
		index++
	}
	if in_quotes {
		return error('unexpected end of CSV data inside a quoted field')
	}
}

// load_and_split loads the CSV and splits each row while preserving row
// metadata on every chunk.
pub fn (loader CSVLoader) load_and_split(mut ctx context.Context, splitter textsplitter.BoundedTextSplitter) ![]schema.Document {
	documents := loader.load(mut ctx)!
	mut results := []schema.Document{}
	mut output_bytes := i64(0)
	for document in documents {
		ctx_error := ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
		remaining := loader.max_documents - results.len
		chunks := splitter.split_text_bounded(document.page_content, remaining,
			loader.max_split_input_bytes,
			loader.max_output_bytes - output_bytes)!
		if chunks.len > remaining {
			return error('CSV split document count exceeds the ${loader.max_documents}-document limit')
		}
		for chunk in chunks {
			if output_bytes + i64(chunk.len) > loader.max_output_bytes {
				return error('split CSV documents exceed the ${loader.max_output_bytes}-byte output limit')
			}
			output_bytes += i64(chunk.len)
			mut metadata := map[string]json2.Any{}
			for key, value in document.metadata {
				metadata[key] = value
			}
			results << schema.Document{
				page_content: chunk
				metadata:     metadata
				score:        document.score
			}
		}
	}
	return results
}
