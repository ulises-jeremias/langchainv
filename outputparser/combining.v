// Package outputparser combines multiple parsers over delimited sections.
module outputparser

import json2

// Combining runs one parser for each section separated by a blank line and
// merges their string-valued maps.
pub struct Combining {
pub:
	parsers []Parser
}

// new_combining creates a parser that applies each supplied parser in order.
pub fn new_combining(parsers []Parser) Combining {
	return Combining{
		parsers: parsers.clone()
	}
}

// parse splits text on two consecutive newlines, parses each section, and
// merges maps containing only string values.
pub fn (combining Combining) parse(text string) !json2.Any {
	if combining.parsers.len < 2 {
		return error('combining parser requires at least two parsers, got ${combining.parsers.len}')
	}
	sections := text.split('\n\n')
	if sections.len != combining.parsers.len {
		return error('text section count (${sections.len}) does not match parser count (${combining.parsers.len})')
	}
	mut output := map[string]json2.Any{}
	for i, section in sections {
		parsed := combining.parsers[i].parse(section.trim_space())!
		match parsed {
			map[string]json2.Any {
				for key, value in parsed {
					match value {
						string {
							output[key] = json2.Any(value)
						}
						else {
							return error('parser ${i} returned a map with a non-string value')
						}
					}
				}
			}
			else {
				return error('parser ${i} did not return a map of strings')
			}
		}
	}
	return json2.Any(output)
}

// format_instructions describes how the input is divided among child parsers.
pub fn (combining Combining) format_instructions() string {
	mut instructions := 'Your response will be a map of strings combining the output of parsers\n'
	instructions += 'using text delimited by two successive newline characters, to the respective parser.\n\n'
	instructions += 'The output parser instructions are:'
	for parser in combining.parsers {
		instructions += '\n- ${parser.format_instructions()}'
	}
	return instructions
}

// type_name identifies this parser.
pub fn (_ Combining) type_name() string {
	return 'combining_parser'
}
