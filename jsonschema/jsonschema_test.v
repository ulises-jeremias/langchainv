module jsonschema

import json2

fn test_empty_definition_serializes_an_empty_properties_object() {
	definition := Definition{}
	assert json2.encode(definition, json2.EncoderOptions{}) == '{"properties":{}}'
}

fn test_all_data_type_constants_encode_as_json_schema_strings() {
	types := [object_type, number_type, integer_type, string_type, array_type, null_type, boolean_type]
	expected := ['object', 'number', 'integer', 'string', 'array', 'null', 'boolean']
	for i, schema_type in types {
		definition := Definition{
			schema_type: schema_type
		}
		decoded := json2.decode[json2.Any](json2.encode(definition, json2.EncoderOptions{}),
			json2.DecoderOptions{}) or { panic(err) }
		assert (decoded.as_map()['type'] or { json2.Any('') }).str() == expected[i]
	}
}

fn test_definition_serializes_nested_properties_and_optional_fields() {
	definition := Definition{
		schema_type: object_type
		description: 'A "person" record'
		enum_values: ['member', 'guest']
		properties:  {
			'name': Definition{
				schema_type: string_type
				description: 'Display name'
				enum_values: ['Ada', 'Lin']
				required:    ['non_empty']
			}
			'age':  Definition{
				schema_type: integer_type
			}
		}
		required:    ['name', 'age']
		items:       ?Definition(Definition{
			schema_type: string_type
		})
	}
	encoded := json2.encode(definition, json2.EncoderOptions{})
	decoded := json2.decode[json2.Any](encoded, json2.DecoderOptions{}) or { panic(err) }
	root := decoded.as_map()
	assert (root['type'] or { json2.Any('') }).str() == 'object'
	assert (root['description'] or { json2.Any('') }).str() == 'A "person" record'
	required := (root['required'] or { json2.Any([]json2.Any{}) }).as_array()
	assert required.len == 2
	assert required[0].str() == 'name'
	assert required[1].str() == 'age'
	properties := (root['properties'] or { json2.Any(map[string]json2.Any{}) }).as_map()
	assert properties.len == 2
	name := (properties['name'] or { json2.Any(map[string]json2.Any{}) }).as_map()
	assert (name['description'] or { json2.Any('') }).str() == 'Display name'
	name_enum := (name['enum'] or { json2.Any([]json2.Any{}) }).as_array()
	assert name_enum.len == 2
	assert name_enum[0].str() == 'Ada'
	assert name_enum[1].str() == 'Lin'
	assert name['properties'] or { json2.Any(map[string]json2.Any{}) }.as_map().len == 0
	items := (root['items'] or { json2.Any(map[string]json2.Any{}) }).as_map()
	assert (items['type'] or { json2.Any('') }).str() == 'string'
	assert items['properties'] or { json2.Any(map[string]json2.Any{}) }.as_map().len == 0
}

fn test_definition_to_any_can_be_embedded_in_tool_parameters() {
	definition := Definition{
		schema_type: object_type
		properties:  {
			'query': Definition{
				schema_type: string_type
			}
		}
		required:    ['query']
	}
	parameters := definition.to_any()
	encoded := json2.encode(parameters, json2.EncoderOptions{})
	decoded := json2.decode[json2.Any](encoded, json2.DecoderOptions{}) or { panic(err) }
	required := (decoded.as_map()['required'] or { json2.Any([]json2.Any{}) }).as_array()
	assert required.len == 1
	assert required[0].str() == 'query'
}
