// Package documentloaders reads source data into shared document values.
module documentloaders

import context
import json2
import os
import time
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.textsplitter

const default_pdf_max_input_bytes = i64(16 * 1024 * 1024)
const default_pdf_max_output_bytes = i64(16 * 1024 * 1024)
const default_pdf_timeout_ms = 30000
const default_pdf_max_documents = 10_000
const default_pdf_max_split_input_bytes = 16 * 1024
const max_pdf_bytes = i64(64 * 1024 * 1024)
const max_pdf_timeout_ms = 120000
const max_pdf_max_split_input_bytes = 1024 * 1024

// PDFLoaderOptions configures the Poppler executable and resource bounds.
pub struct PDFLoaderOptions {
pub:
	pdftotext_path        string
	max_input_bytes       i64 = default_pdf_max_input_bytes
	max_output_bytes      i64 = default_pdf_max_output_bytes
	timeout_ms            int = default_pdf_timeout_ms
	max_documents         int = default_pdf_max_documents
	max_split_input_bytes int = default_pdf_max_split_input_bytes
}

// PDFLoader extracts text from one PDF using the pdftotext executable.
pub struct PDFLoader {
pub:
	path string
mut:
	executable_path       string
	max_input_bytes       i64
	max_output_bytes      i64
	timeout_ms            int
	max_documents         int
	max_split_input_bytes int
}

struct PDFProcessOutput {
mut:
	text  string
	bytes i64
}

// new_pdf_loader constructs a bounded PDF text loader. Poppler's pdftotext
// executable must be installed and available on PATH unless explicitly set.
pub fn new_pdf_loader(path string, options PDFLoaderOptions) !PDFLoader {
	if path.trim_space() == '' || path.len > 4096 || path.contains('\0') {
		return error('PDF path must be between 1 and 4096 bytes and contain no NUL bytes')
	}
	if options.max_input_bytes < 0 || options.max_input_bytes > max_pdf_bytes {
		return error('PDF input limit must be at most 64 MiB')
	}
	if options.max_output_bytes < 0 || options.max_output_bytes > max_pdf_bytes {
		return error('PDF output limit must be at most 64 MiB')
	}
	if options.timeout_ms < 0 || options.timeout_ms > max_pdf_timeout_ms {
		return error('PDF extraction timeout must be at most 120000 milliseconds')
	}
	if options.max_documents < 0 || options.max_documents > default_pdf_max_documents {
		return error('PDF document limit must be between 1 and ${default_pdf_max_documents}')
	}
	if options.max_split_input_bytes < 0 || options.max_split_input_bytes > max_pdf_max_split_input_bytes {
		return error('PDF split input limit must be at most ${max_pdf_max_split_input_bytes} bytes')
	}
	executable := if options.pdftotext_path.trim_space() == '' {
		'pdftotext'
	} else {
		options.pdftotext_path.trim_space()
	}
	executable_path := os.find_abs_path_of_executable(executable) or {
		return error('pdftotext executable was not found or is not executable')
	}
	if !os.is_file(executable_path) || !os.is_executable(executable_path) {
		return error('pdftotext executable was not found or is not executable')
	}
	return PDFLoader{
		path:                  path
		executable_path:       executable_path
		max_input_bytes:       if options.max_input_bytes == 0 {
			default_pdf_max_input_bytes
		} else {
			options.max_input_bytes
		}
		max_output_bytes:      if options.max_output_bytes == 0 {
			default_pdf_max_output_bytes
		} else {
			options.max_output_bytes
		}
		timeout_ms:            if options.timeout_ms == 0 {
			default_pdf_timeout_ms
		} else {
			options.timeout_ms
		}
		max_documents:         if options.max_documents == 0 {
			default_pdf_max_documents
		} else {
			options.max_documents
		}
		max_split_input_bytes: if options.max_split_input_bytes == 0 {
			default_pdf_max_split_input_bytes
		} else {
			options.max_split_input_bytes
		}
	}
}

// load extracts each page into a document with source, page, and page-count metadata.
pub fn (loader PDFLoader) load(mut ctx context.Context) ![]schema.Document {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	if !os.is_file(loader.path) || os.is_link(loader.path) {
		return error('PDF path must be a regular file and must not be a symbolic link')
	}
	input_size := os.file_size(loader.path)
	if loader.max_input_bytes <= 0 || i64(input_size) > loader.max_input_bytes {
		return error('PDF input exceeds the configured ${loader.max_input_bytes}-byte limit')
	}
	if loader.max_output_bytes <= 0 || loader.timeout_ms <= 0 {
		return error('PDF output and timeout limits must be greater than zero')
	}
	mut process := os.new_process(loader.executable_path)
	process.set_args(['-enc', 'UTF-8', loader.path, '-'])
	process.use_pgroup = true
	process.set_redirect_stdio()
	process.run()
	if process.err != '' {
		process.close()
		return error('could not start pdftotext process')
	}
	mut output := PDFProcessOutput{}
	started_at := time.now().unix_nano()
	for process.is_alive() {
		ctx_error_during := ctx.err()
		if ctx_error_during !is none {
			process.signal_pgkill()
			process.wait()
			process.close()
			return ctx_error_during
		}
		elapsed_ms := (time.now().unix_nano() - started_at) / 1_000_000
		if elapsed_ms > i64(loader.timeout_ms) {
			process.signal_pgkill()
			process.wait()
			process.close()
			return error('PDF extraction timed out after ${loader.timeout_ms} milliseconds')
		}
		read_pdf_process_output(mut process, mut output, loader.max_output_bytes) or {
			process.signal_pgkill()
			process.wait()
			process.close()
			return err
		}
		time.sleep(10 * time.millisecond)
	}
	process.wait()
	for {
		previous_output_bytes := output.bytes
		read_pdf_process_output(mut process, mut output, loader.max_output_bytes) or {
			process.close()
			return err
		}
		if output.bytes == previous_output_bytes {
			break
		}
	}
	status := process.code
	process.close()
	if status != 0 {
		return error('pdftotext failed with exit status ${status}')
	}
	ctx_error_after := ctx.err()
	if ctx_error_after !is none {
		return ctx_error_after
	}
	mut form_feed_count := 0
	for i := 0; i < output.text.len; i++ {
		if output.text[i] == 12 {
			form_feed_count++
		}
	}
	page_count := if output.text.ends_with('\x0c') {
		form_feed_count
	} else {
		form_feed_count + 1
	}
	if page_count > loader.max_documents {
		return error('PDF page count exceeds the ${loader.max_documents}-document limit')
	}
	mut pages := output.text.split('\x0c')
	if pages.len > 1 && pages[pages.len - 1] == '' {
		pages.delete_last()
	}
	if pages.len != page_count {
		return error('pdftotext returned an inconsistent page count')
	}
	mut documents := []schema.Document{cap: pages.len}
	for index, page in pages {
		mut metadata := map[string]json2.Any{}
		metadata['source'] = json2.Any(loader.path)
		metadata['page'] = json2.Any(index + 1)
		metadata['total_pages'] = json2.Any(page_count)
		documents << schema.Document{
			page_content: page
			metadata:     metadata
		}
	}
	return documents
}

// load_and_split splits each extracted page and preserves its metadata.
pub fn (loader PDFLoader) load_and_split(mut ctx context.Context, splitter textsplitter.BoundedTextSplitter) ![]schema.Document {
	documents := loader.load(mut ctx)!
	mut results := []schema.Document{}
	mut output_bytes := i64(0)
	for document in documents {
		ctx_error := ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
		remaining_documents := loader.max_documents - results.len
		remaining_output_bytes := loader.max_output_bytes - output_bytes
		chunks := splitter.split_text_bounded(document.page_content, remaining_documents,
			loader.max_split_input_bytes, remaining_output_bytes)!
		for chunk in chunks {
			if results.len >= loader.max_documents {
				return error('PDF split documents exceed the ${loader.max_documents}-document limit')
			}
			if output_bytes + i64(chunk.len) > loader.max_output_bytes {
				return error('split PDF output exceeds the ${loader.max_output_bytes}-byte limit')
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

fn read_pdf_process_output(mut process os.Process, mut output PDFProcessOutput, max_output_bytes i64) ! {
	for {
		mut read_any := false
		if chunk := process.pipe_read(.stdout) {
			read_any = true
			if i64(chunk.len) > max_output_bytes - output.bytes {
				return error('PDF extracted output exceeds the ${max_output_bytes}-byte limit')
			}
			output.bytes += chunk.len
			output.text += chunk
		}
		if chunk := process.pipe_read(.stderr) {
			read_any = true
			if i64(chunk.len) > max_output_bytes - output.bytes {
				return error('PDF extractor output exceeds the ${max_output_bytes}-byte limit')
			}
			output.bytes += chunk.len
		}
		if !read_any {
			break
		}
	}
}
