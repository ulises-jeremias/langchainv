module jsonschema

import json2

fn test_definition_encodes_format_and_composition() {
	definition := Definition{
		type_:      .object
		properties: {
			'contact': Definition{
				any_of: [
					Definition{
						type_:  .string
						format: 'email'
					},
					Definition{
						type_:  .string
						format: 'uri'
					},
				]
			}
			'id':      Definition{
				all_of: [
					Definition{
						type_:      .string
						min_length: 3
					},
				]
				not:    &Definition{
					type_:       .string
					enum_values: ['root']
				}
			}
		}
	}
	encoded := definition.encode() or { panic(err) }
	assert encoded.contains('"format":"email"')
	assert encoded.contains('"anyOf":[')
	assert encoded.contains('"allOf":[')
	assert encoded.contains('"minLength":3')
	assert encoded.contains('"not":{')
}

fn test_definition_validates_instances_through_composition() {
	definition := Definition{
		any_of: [
			Definition{
				type_:      .string
				min_length: 3
			},
			Definition{
				type_: .integer
			},
		]
	}
	definition.validate_instance(json2.Any('abcd')) or { panic(err) }
	definition.validate_instance(json2.Any(7)) or { panic(err) }
	definition.validate_instance(json2.Any('ab')) or {
		assert err.msg().contains('anyOf')
		return
	}
	assert false, 'expected a short string to fail anyOf'
}

fn test_definition_one_of_requires_exactly_one_match() {
	definition := Definition{
		one_of: [
			Definition{
				type_: .string
			},
			Definition{
				type_:      .string
				min_length: 2
			},
		]
	}
	definition.validate_instance(json2.Any('a')) or { panic(err) }
	definition.validate_instance(json2.Any('abc')) or {
		assert err.msg().contains('oneOf')
		return
	}
	assert false, 'expected two matches to fail oneOf'
}

fn test_definition_all_of_and_not_are_enforced() {
	definition := Definition{
		all_of: [
			Definition{
				type_:      .string
				min_length: 2
			},
			Definition{
				type_:      .string
				max_length: 3
			},
		]
		not:    &Definition{
			type_:       .string
			enum_values: ['bad']
		}
	}
	definition.validate_instance(json2.Any('ok')) or { panic(err) }
	definition.validate_instance(json2.Any('toolong')) or {
		assert err.msg().contains('maxLength')
		return
	}
	assert false, 'expected allOf to reject a long string'
}

fn test_definition_not_rejects_matching_instances() {
	definition := Definition{
		type_: .string
		not:   &Definition{
			type_:       .string
			enum_values: ['root']
		}
	}
	definition.validate_instance(json2.Any('guest')) or { panic(err) }
	definition.validate_instance(json2.Any('root')) or {
		assert err.msg().contains('not')
		return
	}
	assert false, 'expected not to reject the excluded value'
}

fn test_definition_rejects_misplaced_format_and_empty_composition_members() {
	Definition{
		type_:  .integer
		format: 'email'
	}.validate() or {
		assert err.msg().contains('format is only valid for string')
		return
	}
	assert false, 'expected format on an integer to fail'
}

fn test_definition_rejects_invalid_format_names() {
	Definition{
		type_:  .string
		format: 'not a format'
	}.validate() or {
		assert err.msg().contains('format must')
		return
	}
	assert false, 'expected an invalid format name to fail'
}
