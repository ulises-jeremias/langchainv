// Package ollama provides bounded local model management endpoints.
module ollama

import context
import json2
import net.http
import ulises_jeremias.langchainv.httputil

const max_model_name_bytes = 256

// ModelInfo describes one locally available Ollama model.
pub struct ModelInfo {
pub:
	name               string
	size               i64
	digest             string
	modified_at        string
	family             string
	parameter_size     string
	quantization_level string
}

struct ModelDetails {
	family             string
	parameter_size     string @[json: 'parameter_size']
	quantization_level string @[json: 'quantization_level']
}

struct TagsModel {
	name        string
	size        i64
	digest      string
	modified_at string @[json: 'modified_at']
	details     ModelDetails
}

struct TagsResponse {
	models []TagsModel
}

struct ShowResponse {
	size    i64
	details ModelDetails
}

struct StatusResponse {
	status string
}

// list_models returns the models available on the server through GET /api/tags.
pub fn (client Client) list_models(mut ctx context.Context) ![]ModelInfo {
	body := client.do_model_request(mut ctx, http.Method.get, '/api/tags', '')!
	decoded := json2.decode[TagsResponse](body, json2.DecoderOptions{}) or {
		return error('could not decode Ollama tags response: ${err.msg()}')
	}
	mut models := []ModelInfo{cap: decoded.models.len}
	for model in decoded.models {
		models << ModelInfo{
			name:               model.name
			size:               model.size
			digest:             model.digest
			modified_at:        model.modified_at
			family:             model.details.family
			parameter_size:     model.details.parameter_size
			quantization_level: model.details.quantization_level
		}
	}
	return models
}

// show_model returns details for one model through POST /api/show.
pub fn (client Client) show_model(mut ctx context.Context, name string) !ModelInfo {
	validate_model_name(name)!
	body := client.do_model_request(mut ctx, http.Method.post, '/api/show',
		encode_model_name(name))!
	decoded := json2.decode[ShowResponse](body, json2.DecoderOptions{}) or {
		return error('could not decode Ollama show response: ${err.msg()}')
	}
	return ModelInfo{
		name:               name
		size:               decoded.size
		family:             decoded.details.family
		parameter_size:     decoded.details.parameter_size
		quantization_level: decoded.details.quantization_level
	}
}

// pull_model downloads one model through POST /api/pull without streaming
// progress. Large downloads can take a long time; the transport timeout and
// context bound the call.
pub fn (client Client) pull_model(mut ctx context.Context, name string) ! {
	validate_model_name(name)!
	body := json2.encode({
		'name':   json2.Any(name)
		'stream': json2.Any(false)
	}, json2.EncoderOptions{})
	response_body := client.do_model_request(mut ctx, http.Method.post, '/api/pull', body)!
	if response_body.trim_space() == '' {
		return
	}
	decoded := json2.decode[StatusResponse](response_body, json2.DecoderOptions{}) or {
		return error('could not decode Ollama pull response: ${err.msg()}')
	}
	if decoded.status != 'success' {
		return error('Ollama pull did not report success')
	}
}

// delete_model removes one local model through DELETE /api/delete.
pub fn (client Client) delete_model(mut ctx context.Context, name string) ! {
	validate_model_name(name)!
	client.do_model_request(mut ctx, http.Method.delete, '/api/delete', encode_model_name(name))!
}

fn encode_model_name(name string) string {
	return json2.encode({
		'name': json2.Any(name)
	}, json2.EncoderOptions{})
}

fn validate_model_name(name string) ! {
	if name.trim_space() == '' || name.len > max_model_name_bytes {
		return error('Ollama model name must contain 1..256 bytes')
	}
	for character in name.bytes() {
		if character < ` ` || character == 0x7f {
			return error('Ollama model name must not contain control characters')
		}
	}
}

fn (client Client) do_model_request(mut ctx context.Context, method http.Method, path string, body string) !string {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	response := client.http_client.do(mut ctx, httputil.Request{
		method:  method
		url:     '${client.base_url}${path}'
		headers: {
			'Content-Type': 'application/json'
			'Accept':       'application/json'
		}
		body:    body
	}) or { return error('Ollama model request failed: ${err.msg()}') }
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Ollama model request returned HTTP ${response.status_code}')
	}
	if response.body.len > max_response_bytes {
		return error('Ollama model response exceeds 16 MiB')
	}
	return response.body
}
