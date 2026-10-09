// Package jsonschema models the subset of JSON Schema used by LangChainGo
// tool and function definitions.
module jsonschema

import json2

// DataType names the JSON value type described by a definition.
pub type DataType = string

pub const object_type = DataType('object')
pub const number_type = DataType('number')
pub const integer_type = DataType('integer')
pub const string_type = DataType('string')
pub const array_type = DataType('array')
pub const null_type = DataType('null')
pub const boolean_type = DataType('boolean')

// Definition describes a JSON Schema value. `schema_type` is serialized as the
// JSON key `type`; `enum_values` is serialized as `enum`.
pub struct Definition {
pub mut:
	// schema_type identifies the value type described by this definition.
	schema_type DataType
	// description explains the value to a model or caller.
	description string
	// enum_values restricts the value to one of these strings.
	enum_values []string
	// properties describes object fields. It is always serialized, including
	// when empty, to match LangChainGo's Definition marshaler.
	properties map[string]Definition
	// required lists object properties that must be present.
	required []string
	// items describes array elements when this definition has type `array`.
	items ?&Definition
}

// to_any converts this definition recursively to a JSON-compatible value.
pub fn (definition Definition) to_any() json2.Any {
	mut value := map[string]json2.Any{}
	if definition.schema_type != '' {
		value['type'] = json2.Any(string(definition.schema_type))
	}
	if definition.description != '' {
		value['description'] = json2.Any(definition.description)
	}
	if definition.enum_values.len > 0 {
		mut values := []json2.Any{}
		for enum_value in definition.enum_values {
			values << json2.Any(enum_value)
		}
		value['enum'] = json2.Any(values)
	}
	mut properties := map[string]json2.Any{}
	for name, property in definition.properties {
		properties[name] = property.to_any()
	}
	value['properties'] = json2.Any(properties)
	if definition.required.len > 0 {
		mut required := []json2.Any{}
		for name in definition.required {
			required << json2.Any(name)
		}
		value['required'] = json2.Any(required)
	}
	if item := definition.items {
		value['items'] = item.to_any()
	}
	return json2.Any(value)
}

// to_json implements json2's custom encoder and preserves the package's
// always-present `properties` object, including in nested definitions.
pub fn (definition Definition) to_json() string {
	return json2.encode(definition.to_any(), json2.EncoderOptions{})
}
