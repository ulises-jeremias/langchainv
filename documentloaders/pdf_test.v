module documentloaders

import context
import os

fn create_pdf_loader_fixture(contents string) !string {
	path := os.join_path(os.temp_dir(), 'langchainv-pdf-loader-${os.getpid()}.pdf')
	stream := 'BT /F1 12 Tf 72 720 Td (${contents}) Tj ET\n'
	objects := [
		'<< /Type /Catalog /Pages 2 0 R >>',
		'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
		'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
		'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
		'<< /Length ${stream.len} >>\nstream\n${stream}endstream',
	]
	mut pdf := '%PDF-1.4\n'
	mut offsets := []int{}
	for i, object in objects {
		offsets << pdf.len
		pdf += '${i + 1} 0 obj\n${object}\nendobj\n'
	}
	xref_offset := pdf.len
	pdf += 'xref\n0 6\n0000000000 65535 f \n'
	for offset in offsets {
		pdf += '${pdf_offset(offset)} 00000 n \n'
	}
	pdf += 'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n${xref_offset}\n%%EOF\n'
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

fn test_pdf_loader_extracts_text_and_source_metadata() {
	path := create_pdf_loader_fixture('PDF loader works') or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	loader := new_pdf_loader(path, PDFLoaderOptions{}) or { panic(err) }
	mut ctx := context.background()
	documents := loader.load(mut ctx) or { panic(err) }
	assert documents.len == 1
	assert documents[0].page_content.contains('PDF loader works')
	assert (documents[0].metadata['source'] or { panic('missing source metadata') }).str() == path
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
	path := create_pdf_loader_fixture('bounded text') or { panic(err) }
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

fn test_pdf_loader_rejects_unavailable_executable() {
	new_pdf_loader('/tmp/input.pdf', PDFLoaderOptions{
		pdftotext_path: '/path/that/does/not/exist'
	}) or {
		assert err.msg().contains('pdftotext executable')
		return
	}
	assert false, 'expected a missing pdftotext executable to fail'
}
