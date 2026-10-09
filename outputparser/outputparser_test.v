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

fn test_regex_parser_returns_named_capture_groups() {
	parser := new_regex_parser(r'Question: (?P<question>.*)\nAnswer: (?P<answer>.*)') or {
		panic(err)
	}
	parsed := parser.parse('Question: why?\nAnswer: because') or { panic(err) }
	assert parsed is map[string]json2.Any
	values := parsed as map[string]json2.Any
	assert (values['question'] or { panic('missing question') }) == json2.Any('why?')
	assert (values['answer'] or { panic('missing answer') }) == json2.Any('because')
}

fn test_regex_dict_omits_no_update_values() {
	parser := new_regex_dict(map[string]string{
		'answer': 'Answer'
		'source': 'Source'
	}, 'UNCHANGED') or { panic(err) }
	parsed := parser.parse('Answer: sky.\nSource: UNCHANGED') or { panic(err) }
	assert parsed is map[string]json2.Any
	values := parsed as map[string]json2.Any
	assert (values['answer'] or { panic('missing answer') }) == json2.Any('sky.')
	assert 'source' !in values
}

fn test_structured_parser_requires_and_returns_schema_fields() {
	parser := new_structured([
		ResponseSchema{
			name:        'answer'
			description: 'The response.'
		},
	])
	parsed := parser.parse('```json\n{"answer":"42"}\n```') or { panic(err) }
	assert parsed is map[string]json2.Any
	values := parsed as map[string]json2.Any
	assert (values['answer'] or { panic('missing answer') }) == json2.Any('42')
}

fn test_combining_parser_merges_string_maps_in_section_order() {
	first := new_regex_parser(r'(?P<first>.+)') or { panic(err) }
	second := new_regex_parser(r'(?P<second>.+)') or { panic(err) }
	parser := new_combining([Parser(first), Parser(second)])
	parsed := parser.parse('one\n\ntwo') or { panic(err) }
	assert parsed is map[string]json2.Any
	values := parsed as map[string]json2.Any
	assert (values['first'] or { panic('missing first') }) == json2.Any('one')
	assert (values['second'] or { panic('missing second') }) == json2.Any('two')
}

struct DefinedExampleChild {
	detail string
}

struct DefinedExample {
	name         string
	display_name string @[json: 'display_name']
	ignored      string @[skip]
	child        DefinedExampleChild
}

fn test_defined_parser_generates_schema_and_decodes_typed_struct() {
	parser := new_defined(DefinedExample{}) or { panic(err) }
	instructions := parser.format_instructions()
	assert instructions.contains('"display_name": string;')
	assert instructions.contains('interface _Root_Child')
	assert !instructions.contains('"ignored"')
	parsed := parser.parse('```json\n{"name":"Ada","display_name":"A.","child":{"detail":"V"}}\n```') or {
		panic(err)
	}
	assert parsed.name == 'Ada'
	assert parsed.display_name == 'A.'
	assert parsed.child.detail == 'V'
}
