module jsonschema

import json2

fn test_definition_encodes_nested_properties_and_items() {
	definition := Definition{
		type_:      .object
		properties: {
			'name':   Definition{
				type_:       .string
				description: 'A name'
			}
			'scores': Definition{
				type_: .array
				items: &Definition{
					type_: .number
				}
			}
		}
		required:   ['name']
	}
	encoded := definition.encode() or { panic(err) }
	assert encoded.contains('"type":"object"')
	assert encoded.contains('"description":"A name"')
	assert encoded.contains('"required":["name"]')
	assert encoded.contains('"items":')
	assert encoded.contains('"properties":{}')
	assert encoded.contains('"type":"number"')
}

fn test_definition_encodes_all_json_data_types() {
	assert DataType.object.str() == 'object'
	assert DataType.number.str() == 'number'
	assert DataType.integer.str() == 'integer'
	assert DataType.string.str() == 'string'
	assert DataType.array.str() == 'array'
	assert DataType.null_value.str() == 'null'
	assert DataType.boolean.str() == 'boolean'
}

fn test_definition_encodes_standard_constraints() {
	definition := Definition{
		type_:                 .object
		additional_properties: false
		properties:            {
			'count': Definition{
				type_:   .integer
				minimum: 1
				maximum: 10
			}
			'name':  Definition{
				type_:      .string
				min_length: 2
				max_length: 40
			}
			'tags':  Definition{
				type_:     .array
				min_items: 1
				max_items: 5
				items:     &Definition{
					type_: .string
				}
			}
		}
	}
	encoded := definition.encode() or { panic(err) }
	assert encoded.contains('"minimum":1')
	assert encoded.contains('"maximum":10')
	assert encoded.contains('"minLength":2')
	assert encoded.contains('"maxLength":40')
	assert encoded.contains('"minItems":1')
	assert encoded.contains('"maxItems":5')
	assert encoded.contains('"additionalProperties":false')
}

fn test_definition_rejects_invalid_constraint_types_and_ranges() {
	invalid_definitions := [
		Definition{
			type_:   .string
			minimum: 1
		},
		Definition{
			type_:      .number
			min_length: 1
		},
		Definition{
			type_:     .object
			min_items: 1
		},
		Definition{
			type_:      .string
			min_length: 3
			max_length: 2
		},
		Definition{
			type_:     .array
			min_items: 3
			max_items: 2
		},
		Definition{
			type_:   .number
			minimum: 3
			maximum: 2
		},
	]
	for definition in invalid_definitions {
		definition.validate() or { continue }
		assert false, 'expected invalid JSON Schema constraints to fail'
	}
}

fn test_definition_rejects_required_properties_that_are_missing() {
	Definition{
		type_:    .object
		required: ['missing']
	}.validate() or {
		assert err.msg().contains('has no property definition')
		return
	}
	assert false, 'expected a missing property definition to fail'
}

fn test_definition_rejects_duplicate_enum_values() {
	Definition{
		type_:       .string
		enum_values: ['a', 'a']
	}.validate() or {
		assert err.msg().contains('must be unique')
		return
	}
	assert false, 'expected duplicate enum values to fail'
}

fn test_definition_rejects_misplaced_array_items() {
	Definition{
		type_: .string
		items: &Definition{
			type_: .string
		}
	}.validate() or {
		assert err.msg().contains('only valid for array')
		return
	}
	assert false, 'expected invalid items placement to fail'
}

fn test_definition_rejects_excessive_nesting() {
	mut definition := Definition{
		type_: .string
	}
	for _ in 0 .. 66 {
		definition = Definition{
			type_:      .object
			properties: {
				'nested': definition
			}
		}
	}
	definition.validate() or {
		assert err.msg().contains('64-level limit')
		return
	}
	assert false, 'expected excessive schema nesting to fail'
}

fn test_instance_validation_checks_nested_objects_arrays_and_required_values() {
	definition := Definition{
		type_:      .object
		required:   ['name', 'scores']
		properties: {
			'name':   Definition{
				type_:       .string
				enum_values: ['Ada', 'Lin']
			}
			'scores': Definition{
				type_:     .array
				min_items: 1
				items:     &Definition{
					type_:   .integer
					minimum: 0
					maximum: 100
				}
			}
		}
	}
	instance := json2.Any(map[string]json2.Any{
		'name':   json2.Any('Ada')
		'scores': json2.Any([json2.Any(90), json2.Any(100.0)])
	})
	definition.validate_instance(instance) or { panic(err) }
}

fn test_instance_validation_reports_type_enum_and_constraint_paths() {
	definition := Definition{
		type_:      .object
		properties: {
			'age':  Definition{
				type_:   .integer
				minimum: 18
			}
			'name': Definition{
				type_:       .string
				enum_values: ['Ada', 'Lin']
			}
		}
	}
	invalid_instances := [
		json2.Any(map[string]json2.Any{
			'age': json2.Any('18')
		}),
		json2.Any(map[string]json2.Any{
			'age': json2.Any(17)
		}),
		json2.Any(map[string]json2.Any{
			'age':  json2.Any(18)
			'name': json2.Any('Grace')
		}),
	]
	expected_paths := ['$.age', '$.age', '$.name']
	for index, instance in invalid_instances {
		definition.validate_instance(instance) or {
			assert err.msg().contains(expected_paths[index])
			continue
		}
		assert false, 'expected invalid JSON instance to fail'
	}
}

fn test_instance_validation_applies_string_length_and_disallows_extra_properties() {
	definition := Definition{
		type_:                 .object
		additional_properties: false
		properties:            {
			'code': Definition{
				type_:      .string
				min_length: 2
				max_length: 4
			}
		}
	}
	for instance in [
		json2.Any(map[string]json2.Any{
			'code': json2.Any('x')
		}),
		json2.Any(map[string]json2.Any{
			'code':  json2.Any('abc')
			'extra': json2.Any(true)
		}),
	] {
		definition.validate_instance(instance) or { continue }
		assert false, 'expected string length or additional property validation to fail'
	}
}

fn test_instance_validation_checks_missing_required_properties() {
	definition := Definition{
		type_:      .object
		required:   ['name']
		properties: {
			'name': Definition{
				type_: .string
			}
		}
	}
	definition.validate_instance(json2.Any(map[string]json2.Any{})) or {
		assert err.msg().contains('required property')
		assert err.msg().contains('$')
		return
	}
	assert false, 'expected missing required property to fail'
}

fn test_instance_validation_bounds_node_count() {
	mut values := []json2.Any{cap: 10001}
	for _ in 0 .. 10001 {
		values << json2.Any(0)
	}
	Definition{
		type_: .array
		items:  &Definition{}
	}.validate_instance(json2.Any(values)) or {
		assert err.msg().contains('10000-node limit')
		return
	}
	assert false, 'expected too many JSON instance nodes to fail'
}

fn test_instance_validation_bounds_bytes() {
	Definition{
		type_: .string
	}.validate_instance(json2.Any('x'.repeat(1048577))) or {
		assert err.msg().contains('1048576-byte limit')
		return
	}
	assert false, 'expected oversized JSON instance to fail'
}
