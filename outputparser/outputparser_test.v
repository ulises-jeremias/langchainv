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
	pattern := 'Question: (?P<question>.*)' + '\n' + 'Answer: (?P<answer>.*)'
	parser := new_regex_parser(pattern) or {
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
	parsed := parser.parse('Answer: sky. Extra words\nSource: UNCHANGED') or { panic(err) }
	assert parsed is map[string]json2.Any
	values := parsed as map[string]json2.Any
	answer := values['answer'] or { panic('missing answer') }
	assert answer == json2.Any('sky.'), 'unexpected parsed answer: ${answer}'
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
	children     []DefinedExampleChild
	fixed        [2]DefinedExampleChild
	by_name      map[string]DefinedExampleChild
	metadata     map[string]string
	optional_map map[string]?string
	flags_map    map[string]?bool
	numbers_map  map[string]?i32
	labels       [2]string
	active       [2]bool
	scores       [3]int
	optional     []?string
	flags        [2]?bool
	nullable     []?i32
}

fn test_defined_parser_generates_schema_and_decodes_typed_struct() {
	parser := new_defined(DefinedExample{}) or { panic(err) }
	instructions := parser.format_instructions()
	assert instructions.contains('"display_name": string;')
	assert instructions.contains('"labels": string[];')
	assert instructions.contains('"active": boolean[];')
	assert instructions.contains('"scores": number[];')
	assert instructions.contains('"optional": (string | null)[];')
	assert instructions.contains('"flags": (boolean | null)[];')
	assert instructions.contains('"nullable": (number | null)[];')
	assert instructions.contains('interface _Root_Child')
	assert instructions.contains('"children": _Root_Children[];')
	assert instructions.contains('"fixed": _Root_Fixed[];')
	assert instructions.contains('"by_name": Record<string, _Root_By_name>;')
	assert instructions.contains('"metadata": Record<string, string>;')
	assert instructions.contains('"optional_map": Record<string, string | null>;')
	assert instructions.contains('"flags_map": Record<string, boolean | null>;')
	assert instructions.contains('"numbers_map": Record<string, number | null>;')
	assert !instructions.contains('"ignored"')
	parsed := parser.parse('```json\n{"name":"Ada","display_name":"A.","child":{"detail":"V"},"children":[{"detail":"nested"}],"fixed":[{"detail":"fixed-a"},{"detail":"fixed-b"}],"by_name":{"primary":{"detail":"mapped"}},"metadata":{"source":"test"},"optional_map":{"present":"value","missing":null},"flags_map":{"enabled":true,"unset":null},"numbers_map":{"count":7,"unset":null},"labels":["first","second"],"active":[true,false],"scores":[1,2,3],"optional":["set",null],"flags":[true,null],"nullable":[7,null]}\n```') or {
		panic(err)
	}
	assert parsed.name == 'Ada'
	assert parsed.display_name == 'A.'
	assert parsed.child.detail == 'V'
	assert parsed.children.len == 1
	assert parsed.children[0].detail == 'nested'
	assert parsed.fixed[1].detail == 'fixed-b'
	assert parsed.by_name['primary'].detail == 'mapped'
	assert parsed.metadata['source'] == 'test'
	map_value := parsed.optional_map['present'] or { panic('expected optional map value') }
	assert map_value == 'value'
	assert parsed.optional_map['missing'] == none
	flag_map_value := parsed.flags_map['enabled'] or { panic('expected optional boolean map value') }
	assert flag_map_value
	assert parsed.flags_map['unset'] == none
	number_map_value := parsed.numbers_map['count'] or { panic('expected optional number map value') }
	assert number_map_value == 7
	assert parsed.numbers_map['unset'] == none
	assert parsed.labels == ['first', 'second']
	assert parsed.active == [true, false]!
	assert parsed.scores == [1, 2, 3]!
	optional_value := parsed.optional[0] or { panic('expected optional string value') }
	assert optional_value == 'set'
	assert parsed.optional[1] == none
	flag_value := parsed.flags[0] or { panic('expected optional boolean value') }
	assert flag_value
	assert parsed.flags[1] == none
	numeric_value := parsed.nullable[0] or { panic('expected optional number value') }
	assert numeric_value == 7
	assert parsed.nullable[1] == none
}
