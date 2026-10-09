// Package outputparser contains regular-expression based output parsers.
module outputparser

import json2
import regex

const regex_dict_pattern = '(?:%s):\\s?(?P<value>(?:[^.\\n\\x27]*)\\.?)'

// RegexParser extracts capture groups into a map. Named groups use their
// names as keys; unnamed groups use an empty key, matching LangChainGo.
pub struct RegexParser {
	pattern     string
	output_keys []string
}

// new_regex_parser validates a V regular-expression pattern and records its
// capture-group keys for parsing generated text.
pub fn new_regex_parser(pattern string) !RegexParser {
	mut expression := regex.regex_opt(pattern)!
	mut output_keys := []string{len: expression.group_count}
	for group_index in 0 .. expression.group_count {
		for name, group_id in expression.group_map {
			if group_id == group_index + 1 {
				output_keys[group_index] = name
				break
			}
		}
	}
	return RegexParser{
		pattern:     pattern
		output_keys: output_keys
	}
}

// parse returns all captured groups for the first match.
pub fn (parser RegexParser) parse(text string) !json2.Any {
	mut expression := regex.regex_opt(parser.pattern)!
	start, _ := expression.find(text)
	if start < 0 {
		return error('no match found for expression ${parser.pattern}')
	}
	mut result := map[string]json2.Any{}
	for group_index, key in parser.output_keys {
		result[key] = json2.Any(expression.get_group_by_id(text, group_index))
	}
	return json2.Any(result)
}

// format_instructions describes the map shape returned by this parser.
pub fn (_ RegexParser) format_instructions() string {
	return 'Your output should be a map of strings. e.g.:\nmap[string]string{"key1": "value1", "key2": "value2"}'
}

// type_name identifies this parser.
pub fn (_ RegexParser) type_name() string {
	return 'regex_parser'
}

// RegexDict extracts one formatted value for each configured output key.
pub struct RegexDict {
	output_key_to_format map[string]string
	no_update_value      string
}

// new_regex_dict validates format patterns and creates a regex dictionary
// parser. The format values are regular-expression fragments, as in
// LangChainGo's RegexDict.
pub fn new_regex_dict(output_key_to_format map[string]string, no_update_value string) !RegexDict {
	for _, format in output_key_to_format {
		pattern := regex_dict_pattern.replace('%s', format)
		mut expression := regex.regex_opt(pattern)!
		if expression.group_count != 1 {
			return error('regex dictionary format must produce exactly one capture group: ${pattern}')
		}
	}
	return RegexDict{
		output_key_to_format: output_key_to_format.clone()
		no_update_value:      no_update_value
	}
}

// parse uses the first match for every configured format. Values equal to
// no_update_value are omitted from the returned map.
pub fn (parser RegexDict) parse(text string) !json2.Any {
	mut result := map[string]json2.Any{}
	for key, format in parser.output_key_to_format {
		pattern := regex_dict_pattern.replace('%s', format)
		mut expression := regex.regex_opt(pattern)!
		start, _ := expression.find(text)
		if start < 0 {
			return error('no match found for expression ${pattern}')
		}
		value := expression.get_group_by_name(text, 'value')
		if value != parser.no_update_value {
			result[key] = json2.Any(value)
		}
	}
	return json2.Any(result)
}

// format_instructions describes the map shape returned by this parser.
pub fn (_ RegexDict) format_instructions() string {
	return 'Your output should be a map of strings. e.g.:\nmap[string]string{"key1": "value1", "key2": "value2"}\n'
}

// type_name identifies this parser.
pub fn (_ RegexDict) type_name() string {
	return 'regex_dict_parser'
}
