// Package outputparser converts model text into structured values.
module outputparser

import json2

// Parser transforms generated text into a provider-neutral JSON value.
pub interface Parser {
	parse(text string) !json2.Any
	format_instructions() string
	type_name() string
}

// Simple trims model output and returns it as a string.
pub struct Simple {}

// parse returns trimmed text.
pub fn (_ Simple) parse(text string) !json2.Any {
	return json2.Any(text.trim_space())
}

// format_instructions returns no additional formatting instructions.
pub fn (_ Simple) format_instructions() string {
	return ''
}

// type_name identifies this parser.
pub fn (_ Simple) type_name() string {
	return 'simple_parser'
}

// BooleanParser parses affirmative or negative model output.
pub struct BooleanParser {
pub mut:
	true_strings  []string = ['YES', 'TRUE']
	false_strings []string = ['NO', 'FALSE']
}

// parse accepts configured true and false tokens, case-insensitively.
pub fn (parser BooleanParser) parse(text string) !json2.Any {
	normalized := normalize_boolean(text)
	for value in parser.true_strings {
		if normalized == value.to_upper() {
			return json2.Any(true)
		}
	}
	for value in parser.false_strings {
		if normalized == value.to_upper() {
			return json2.Any(false)
		}
	}
	return error('expected one of ${parser.true_strings} or ${parser.false_strings}, received `${normalized}`')
}

// format_instructions describes the expected boolean response.
pub fn (_ BooleanParser) format_instructions() string {
	return 'Your output should be a boolean, for example `true` or `false`.'
}

// type_name identifies this parser.
pub fn (_ BooleanParser) type_name() string {
	return 'boolean_parser'
}

fn normalize_boolean(text string) string {
	mut value := text.trim_space()
	value = value.trim('"\'`')
	return value.to_upper()
}

// CommaSeparatedList parses a comma-delimited response into trimmed items.
pub struct CommaSeparatedList {}

// parse splits the response on commas and trims surrounding whitespace.
pub fn (_ CommaSeparatedList) parse(text string) !json2.Any {
	values := text.trim_space().split(',')
	mut result := []json2.Any{}
	for value in values {
		result << json2.Any(value.trim_space())
	}
	return json2.Any(result)
}

// format_instructions describes the expected comma-delimited response.
pub fn (_ CommaSeparatedList) format_instructions() string {
	return 'Your response should be a comma-separated list, for example `foo, bar, baz`.'
}

// type_name identifies this parser.
pub fn (_ CommaSeparatedList) type_name() string {
	return 'comma_separated_list_parser'
}
