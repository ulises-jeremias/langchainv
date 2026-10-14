module jsonschema

import json2

fn ref_definition() Definition {
	return Definition{
		type_:      .object
		properties: {
			'name':    Definition{
				ref: '#/$defs/name'
			}
			'aliases': Definition{
				type_:                        .object
				additional_properties_schema: &Definition{
					type_: .string
				}
			}
		}
		required:   ['name']
		defs:       {
			'name': Definition{
				type_:      .string
				min_length: 2
			}
		}
	}
}

fn test_definition_encodes_refs_defs_and_schema_additional_properties() {
	encoded := ref_definition().encode() or { panic(err) }
	assert encoded.contains('"$ref":"#/$defs/name"')
	assert encoded.contains('"$defs":{"name":')
	assert encoded.contains('"additionalProperties":{')
}

fn test_definition_validates_instances_through_refs() {
	definition := ref_definition()
	definition.validate_instance(json2.Any({
		'name':    json2.Any('Ada')
		'aliases': json2.Any({
			'short': json2.Any('ada')
		})
	})) or { panic(err) }
	definition.validate_instance(json2.Any({
		'name': json2.Any('A')
	})) or {
		assert err.msg().contains('minLength')
		return
	}
	assert false, 'expected the referenced minLength to fail'
}

fn test_definition_validates_schema_additional_properties() {
	definition := ref_definition()
	definition.validate_instance(json2.Any({
		'name':    json2.Any('Ada')
		'aliases': json2.Any({
			'count': json2.Any(3)
		})
	})) or {
		assert err.msg().contains('type')
		return
	}
	assert false, 'expected a non-string additional property to fail'
}

fn test_definition_rejects_dangling_and_external_refs() {
	Definition{
		properties: {
			'name': Definition{
				ref: '#/$defs/missing'
			}
		}
	}.validate() or {
		assert err.msg().contains('does not resolve')
		Definition{
			properties: {
				'name': Definition{
					ref: 'https://example.com/schema.json'
				}
			}
		}.validate() or {
			assert err.msg().contains('only local')
			return
		}
		assert false, 'expected an external ref to fail'
	}
	assert false, 'expected a dangling ref to fail'
}

fn test_definition_rejects_conflicting_additional_properties() {
	Definition{
		type_:                        .object
		additional_properties:        false
		additional_properties_schema: &Definition{
			type_: .string
		}
	}.validate() or {
		assert err.msg().contains('both')
		return
	}
	assert false, 'expected conflicting additionalProperties to fail'
}
