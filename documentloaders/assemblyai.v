// Package documentloaders reads source data into shared document values.
module documentloaders

import context
import json2
import net.urllib
import os
import time
import ulises_jeremias.langchainv.httputil
import ulises_jeremias.langchainv.schema

const assemblyai_api_base_url = 'https://api.assemblyai.com/v2'
const default_assemblyai_max_poll_requests = 200
const default_assemblyai_poll_interval_ms = 3000
const default_assemblyai_max_text_bytes = i64(16 * 1024 * 1024)
const max_assemblyai_response_bytes = i64(8 * 1024 * 1024)

// AssemblyAILoaderOptions controls bounded polling and transcript size.
pub struct AssemblyAILoaderOptions {
pub:
	max_poll_requests int
	poll_interval_ms  int
	max_text_bytes    i64
}

// AssemblyAILoader submits an HTTPS media URL for transcription.
pub struct AssemblyAILoader {
pub:
	audio_url string
mut:
	api_key           string
	max_poll_requests int
	poll_interval_ms  int
	max_text_bytes    i64
	http_client       httputil.HTTPClient
}

// new_assemblyai_loader constructs a bounded loader with an explicit API key.
pub fn new_assemblyai_loader(audio_url string, api_key string, http_client httputil.HTTPClient, options AssemblyAILoaderOptions) !AssemblyAILoader {
	if audio_url.trim_space() == '' || audio_url.len > 4096 {
		return error('AssemblyAI audio URL must be between 1 and 4096 bytes')
	}
	httputil.validate_url(audio_url, 'https') or {
		return error('AssemblyAI audio URL must be a valid HTTPS URL')
	}
	if api_key.trim_space() == '' {
		return error('AssemblyAI API key must not be empty')
	}
	max_poll_requests := if options.max_poll_requests == 0 {
		default_assemblyai_max_poll_requests
	} else {
		options.max_poll_requests
	}
	poll_interval_ms := if options.poll_interval_ms == 0 {
		default_assemblyai_poll_interval_ms
	} else {
		options.poll_interval_ms
	}
	max_text_bytes := if options.max_text_bytes == 0 {
		default_assemblyai_max_text_bytes
	} else {
		options.max_text_bytes
	}
	if max_poll_requests < 1 || max_poll_requests > 1000 {
		return error('AssemblyAI maximum poll requests must be between 1 and 1000')
	}
	if poll_interval_ms < 0 || poll_interval_ms > 60000 {
		return error('AssemblyAI poll interval must be between 0 and 60000 milliseconds')
	}
	if max_text_bytes < 1 || max_text_bytes > i64(64 * 1024 * 1024) {
		return error('AssemblyAI maximum transcript size must be between 1 byte and 64 MiB')
	}
	return AssemblyAILoader{
		audio_url:         audio_url.trim_space()
		api_key:           api_key.trim_space()
		max_poll_requests: max_poll_requests
		poll_interval_ms:  poll_interval_ms
		max_text_bytes:    max_text_bytes
		http_client:       http_client
	}
}

// new_default_assemblyai_loader reads ASSEMBLYAI_API_KEY and uses bounded HTTP.
pub fn new_default_assemblyai_loader(audio_url string, options AssemblyAILoaderOptions) !AssemblyAILoader {
	api_key := os.getenv('ASSEMBLYAI_API_KEY')
	if api_key.trim_space() == '' {
		return error('ASSEMBLYAI_API_KEY is not set')
	}
	return new_assemblyai_loader(audio_url, api_key, httputil.HTTPClient(httputil.new_default_client()),
		options)
}

// load submits the media URL, polls bounded transcript status, and returns text.
pub fn (loader AssemblyAILoader) load(mut ctx context.Context) ![]schema.Document {
	mut submission_body := map[string]json2.Any{}
	submission_body['audio_url'] = json2.Any(loader.audio_url)
	mut response := loader.http_client.do(mut ctx, httputil.Request{
		method:  .post
		url:     '${assemblyai_api_base_url}/transcript'
		headers: {
			'Authorization': loader.api_key
			'Content-Type':  'application/json'
			'Accept':        'application/json'
		}
		body:    json2.encode(submission_body, json2.EncoderOptions{})
	})!
	check_assemblyai_status(response.status_code, 'submission')!
	mut transcript := decode_assemblyai_response(response.body)!
	transcript_id := assemblyai_string(transcript, 'id') or {
		return error('AssemblyAI submission response is missing a transcript ID')
	}
	if !valid_assemblyai_id(transcript_id) {
		return error('AssemblyAI returned an invalid transcript ID')
	}
	mut transcript_text := ''
	mut status := assemblyai_string(transcript, 'status') or { '' }
	if status == 'completed' {
		transcript_text = assemblyai_text(transcript)!
	} else if status == 'error' {
		return error('AssemblyAI transcription failed')
	} else if status !in ['queued', 'processing'] {
		return error('AssemblyAI returned an unsupported transcript status')
	} else {
		mut completed := false
		for _ in 0 .. loader.max_poll_requests {
			if loader.poll_interval_ms > 0 {
				time.sleep(time.Duration(loader.poll_interval_ms) * time.millisecond)
			}
			ctx_error := ctx.err()
			if ctx_error !is none {
				return ctx_error
			}
			response = loader.http_client.do(mut ctx, httputil.Request{
				url:     '${assemblyai_api_base_url}/transcript/${urllib.query_escape(transcript_id)}'
				headers: {
					'Authorization': loader.api_key
					'Accept':        'application/json'
				}
			})!
			check_assemblyai_status(response.status_code, 'poll')!
			transcript = decode_assemblyai_response(response.body)!
			status = assemblyai_string(transcript, 'status') or { '' }
			if status == 'completed' {
				transcript_text = assemblyai_text(transcript)!
				completed = true
				break
			}
			if status == 'error' {
				return error('AssemblyAI transcription failed')
			}
			if status !in ['queued', 'processing'] {
				return error('AssemblyAI returned an unsupported transcript status')
			}
		}
		if !completed {
			return error('AssemblyAI transcription did not complete within the poll limit')
		}
	}
	if i64(transcript_text.len) > loader.max_text_bytes {
		return error('AssemblyAI transcript exceeds the configured text limit')
	}
	mut metadata := map[string]json2.Any{}
	metadata['source'] = json2.Any(loader.audio_url)
	metadata['transcript_id'] = json2.Any(transcript_id)
	return [schema.Document{
		page_content: transcript_text
		metadata:     metadata
	}]
}

fn check_assemblyai_status(status_code int, operation string) ! {
	if status_code < 200 || status_code >= 300 {
		return error('AssemblyAI ${operation} returned HTTP ${status_code}')
	}
}

fn decode_assemblyai_response(body string) !map[string]json2.Any {
	if i64(body.len) > max_assemblyai_response_bytes {
		return error('AssemblyAI response exceeds the 8 MiB limit')
	}
	return json2.decode[map[string]json2.Any](body, json2.DecoderOptions{}) or {
		error('AssemblyAI returned an invalid transcript response')
	}
}

fn assemblyai_string(response map[string]json2.Any, key string) ?string {
	value := response[key] or { return none }
	if value is string {
		return value as string
	}
	return none
}

fn assemblyai_text(response map[string]json2.Any) !string {
	value := response['text'] or { return error('AssemblyAI completed response is missing transcript text') }
	if value is string {
		return value as string
	}
	return error('AssemblyAI completed response has invalid transcript text')
}

fn valid_assemblyai_id(transcript_id string) bool {
	compact := transcript_id.replace('-', '')
	if compact.len != 32 || (transcript_id.len != 32 && transcript_id.len != 36) {
		return false
	}
	for ch in compact {
		if !ch.is_hex_digit() {
			return false
		}
	}
	return true
}
