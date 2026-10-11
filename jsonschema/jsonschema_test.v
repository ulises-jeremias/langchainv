module jsonschema

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
