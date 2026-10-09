module outputparser

import json2

fn test_simple_parser_trims_text() {
	parser := Simple{}
	parsed := parser.parse('  answer\n') or { panic(err) }
	assert parsed is string
	assert (parsed as string) == 'answer'
}

fn test_boolean_parser() {
	parser := BooleanParser{}
	assert (parser.parse(' "Yes" ') or { panic(err) }) == json2.Any(true)
	assert (parser.parse('false') or { panic(err) }) == json2.Any(false)
}

fn test_boolean_parser_rejects_unknown_value() {
	parser := BooleanParser{}
	parser.parse('maybe') or {
		assert err.msg().contains('expected one of')
		return
	}
	assert false, 'expected an unknown token to fail'
}

fn test_comma_separated_list() {
	parser := CommaSeparatedList{}
	parsed := parser.parse('red, green, blue') or { panic(err) }
	assert parsed is []json2.Any
	values := parsed as []json2.Any
	assert values.len == 3
	assert (values[0] as string) == 'red'
	assert (values[2] as string) == 'blue'
}
