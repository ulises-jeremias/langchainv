module documentloaders

import context
import os
import ulises_jeremias.langchainv.textsplitter

fn create_pdf_loader_fixture(contents []string) !string {
	path := os.join_path(os.temp_dir(), 'langchainv-pdf-loader-${os.getpid()}.pdf')
	mut objects := [
		'<< /Type /Catalog /Pages 2 0 R >>',
		'',
		'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
	]
	mut page_refs := []string{}
	for i, contents_text in contents {
		page_number := 4 + i * 2
		content_number := page_number + 1
		stream := 'BT /F1 12 Tf 72 720 Td (${contents_text}) Tj ET\n'
		page_refs << '${page_number} 0 R'
		objects << '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents ${content_number} 0 R >>'
		objects << '<< /Length ${stream.len} >>\nstream\n${stream}endstream'
	}
	objects[1] = '<< /Type /Pages /Kids [${page_refs.join(' ')}] /Count ${contents.len} >>'
	mut pdf := '%PDF-1.4\n'
	mut offsets := []int{}
	for i, object in objects {
		offsets << pdf.len
		pdf += '${i + 1} 0 obj\n${object}\nendobj\n'
	}
	xref_offset := pdf.len
	object_count := offsets.len + 1
	pdf += 'xref\n0 ${object_count}\n0000000000 65535 f \n'
	for offset in offsets {
		pdf += '${pdf_offset(offset)} 00000 n \n'
	}
	pdf += 'trailer\n<< /Size ${object_count} /Root 1 0 R >>\nstartxref\n${xref_offset}\n%%EOF\n'
	os.write_file(path, pdf)!
	return path
}

fn pdf_offset(offset int) string {
	value := offset.str()
	return '0'.repeat(10 - value.len) + value
}

fn pdf_loader_error(loader PDFLoader) string {
	mut ctx := context.background()
	loader.load(mut ctx) or { return err.msg() }
	return ''
}

fn test_pdf_loader_extracts_each_page_and_metadata() {
	path := create_pdf_loader_fixture(['PDF page one', 'PDF page two']) or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	loader := new_pdf_loader(path, PDFLoaderOptions{}) or { panic(err) }
	mut ctx := context.background()
	documents := loader.load(mut ctx) or { panic(err) }
	assert documents.len == 2
	assert documents[0].page_content.contains('PDF page one')
	assert documents[1].page_content.contains('PDF page two')
	assert (documents[0].metadata['source'] or { panic('missing source metadata') }).str() == path
	assert (documents[0].metadata['page'] or { panic('missing page metadata') }).str() == '1'
	assert (documents[1].metadata['page'] or { panic('missing page metadata') }).str() == '2'
	assert (documents[1].metadata['total_pages'] or { panic('missing total_pages metadata') }).str() == '2'
}

fn test_pdf_loader_load_and_split_preserves_page_metadata() {
	path := create_pdf_loader_fixture(['first page contents', 'second page contents']) or {
		panic(err)
	}
	defer {
		os.rm(path) or {}
	}
	loader := new_pdf_loader(path, PDFLoaderOptions{}) or { panic(err) }
	splitter := textsplitter.new_recursive_character_text_splitter(
		chunk_size:    8
		chunk_overlap: 0
		separators:    ['']
	) or { panic(err) }
	mut ctx := context.background()
	documents := loader.load_and_split(mut ctx, splitter) or { panic(err) }
	assert documents.len > 2
	mut found_first_page := false
	mut found_second_page := false
	for document in documents {
		assert (document.metadata['total_pages'] or { panic('missing total pages') }).str() == '2'
		page := (document.metadata['page'] or { panic('missing page') }).str()
		if page == '1' {
			found_first_page = true
		} else if page == '2' {
			found_second_page = true
		}
	}
	assert found_first_page
	assert found_second_page
}

fn test_pdf_loader_rejects_invalid_pdf_without_exposing_extractor_output() {
	path := os.join_path(os.temp_dir(), 'langchainv-invalid-pdf-${os.getpid()}.pdf')
	os.write_file(path, 'not a PDF') or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	loader := new_pdf_loader(path, PDFLoaderOptions{}) or { panic(err) }
	mut ctx := context.background()
	loader.load(mut ctx) or {
		assert !err.msg().contains('Syntax Error')
		assert err.msg().contains('pdftotext failed')
		return
	}
	assert false, 'expected invalid PDF to fail'
}

fn test_pdf_loader_enforces_input_and_output_limits() {
	path := create_pdf_loader_fixture(['bounded text']) or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	input_limited := new_pdf_loader(path, PDFLoaderOptions{
		max_input_bytes: 1
	}) or { panic(err) }
	assert pdf_loader_error(input_limited).contains('input exceeds')
	output_limited := new_pdf_loader(path, PDFLoaderOptions{
		max_output_bytes: 1
	}) or { panic(err) }
	assert pdf_loader_error(output_limited).contains('output exceeds')
}

fn test_pdf_loader_enforces_page_count_limit() {
	path := create_pdf_loader_fixture(['one', 'two']) or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	loader := new_pdf_loader(path, PDFLoaderOptions{
		max_documents: 1
	}) or { panic(err) }
	assert pdf_loader_error(loader).contains('page count exceeds')
}

fn test_pdf_loader_rejects_unavailable_executable() {
	new_pdf_loader('/tmp/input.pdf', PDFLoaderOptions{
		pdftotext_path: '/path/that/does/not/exist'
	}) or {
		assert err.msg().contains('pdftotext executable')
		return
	}
	assert false, 'expected a missing pdftotext executable to fail'
}
