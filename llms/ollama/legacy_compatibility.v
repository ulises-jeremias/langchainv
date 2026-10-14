module ollama

import context
import json2
import strconv
import ulises_jeremias.langchainv.httputil

const num_gqa_removed_version = '0.1.39'
const numa_removed_version = '0.4.0'
const legacy_sampling_removed_version = '0.5.12'
const legacy_runner_removed_version = '0.7.0'
const legacy_runner_minimum_verified_version = '0.1.34'

struct OllamaVersionResponse {
	version string
}

// validate_legacy_server_version checks the configured compatibility contract
// against Ollama before the request can include legacy provider options.
fn (client Client) validate_legacy_server_version(mut ctx context.Context, provider_options map[string]json2.Any) ! {
	mut legacy_options := []string{}
	for key, _ in provider_options {
		if key in ['num_gqa', 'numa', 'tfs_z', 'penalize_newline', 'mirostat', 'mirostat_tau',
			'mirostat_eta', 'low_vram', 'f16_kv', 'logits_all', 'vocab_only', 'use_mlock'] {
			legacy_options << key
		}
	}
	if legacy_options.len == 0 {
		return
	}
	if client.legacy_server_version == '' {
		return error('Ollama legacy provider_options require Options.legacy_server_version')
	}
	declared_version := parse_ollama_version(client.legacy_server_version)!
	if ollama_version_before_parts(declared_version, parse_ollama_version(legacy_runner_minimum_verified_version)!) {
		return error('Ollama legacy runner compatibility is verified only from version ${legacy_runner_minimum_verified_version}')
	}
	for key in legacy_options {
		boundary := match key {
			'num_gqa' { num_gqa_removed_version }
			'numa' { numa_removed_version }
			'tfs_z', 'penalize_newline' { legacy_sampling_removed_version }
			else { legacy_runner_removed_version }
		}
		if !ollama_version_before_parts(declared_version, parse_ollama_version(boundary)!) {
			return error('Ollama provider_options `${key}` is not supported by server version ${client.legacy_server_version}')
		}
	}
	response := client.http_client.do(mut ctx, httputil.Request{
		method:  .get
		url:     '${client.base_url}/api/version'
		headers: {
			'Accept': 'application/json'
		}
	}) or {
		return error('could not verify Ollama legacy server version: ${err.msg()}')
	}
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('could not verify Ollama legacy server version: /api/version returned HTTP ${response.status_code}')
	}
	if response.body.len > 1024 {
		return error('Ollama /api/version response exceeds the 1 KiB limit')
	}
	decoded := json2.decode[OllamaVersionResponse](response.body, json2.DecoderOptions{}) or {
		return error('could not decode Ollama /api/version response')
	}
	parse_ollama_version(decoded.version) or {
		return error('Ollama /api/version returned an unsupported version value')
	}
	if decoded.version.trim_space() != client.legacy_server_version {
		return error('configured Ollama legacy_server_version ${client.legacy_server_version} does not match server version ${decoded.version}')
	}
}

fn parse_ollama_version(version string) ![]int {
	parts := version.trim_space().split('.')
	if parts.len != 3 {
		return error('invalid Ollama server version')
	}
	mut values := []int{cap: 3}
	for part in parts {
		if part.len == 0 {
			return error('invalid Ollama server version')
		}
		value := strconv.atoi(part) or { return error('invalid Ollama server version') }
		if value < 0 {
			return error('invalid Ollama server version')
		}
		values << value
	}
	return values
}

fn ollama_version_before_parts(version []int, boundary []int) bool {
	for index in 0 .. 3 {
		if version[index] < boundary[index] {
			return true
		}
		if version[index] > boundary[index] {
			return false
		}
	}
	return false
}
