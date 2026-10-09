// Package outputparser contains parsers for structured model responses.
module outputparser

import json2

// ResponseSchema describes a required string field in a structured response.
pub struct ResponseSchema {
pub:
	name        string
	description string
}

// Structured parses a fenced JSON object and checks its required fields.
pub struct Structured {
pub:
	response_schemas []ResponseSchema
}

// new_structured creates a parser for the supplied response schema.
pub fn new_structured(response_schemas []ResponseSchema) Structured {
	return Structured{
		response_schemas: response_schemas.clone()
	}
}

// parse decodes the first fenced JSON object as string-valued fields and
// requires every configured schema field to be present.
pub fn (parser Structured) parse(text string) !json2.Any {
	opening := '```json'
	opening_index := text.index(opening) or {
		return error('no ```json at start of output')
	}
	json_start := opening_index + opening.len
	after_opening := text[json_start..]
	closing_index := after_opening.index('```') or {
		return error('no ``` at end of output')
	}
	json_text := after_opening[..closing_index]
	decoded := json2.decode[map[string]string](json_text, json2.DecoderOptions{}) or {
		return error('could not decode structured output: ${err}')
	}
	for field in parser.response_schemas {
		if field.name !in decoded {
			return error('output is missing required field `${field.name}`')
		}
	}
	mut result := map[string]json2.Any{}
	for key, value in decoded {
		result[key] = json2.Any(value)
	}
	return json2.Any(result)
}

// format_instructions returns the JSON schema prompt for the model.
pub fn (parser Structured) format_instructions() string {
	mut lines := []string{}
	for field in parser.response_schemas {
		lines << '\t"${field.name}": string // ${field.description}\n'
	}
	body := lines.join('')
	return 'The output should be a markdown code snippet formatted in the following schema: \n```json\n{\n${body}}\n```'
}

// type_name identifies this parser.
pub fn (_ Structured) type_name() string {
	return 'structured_parser'
}
