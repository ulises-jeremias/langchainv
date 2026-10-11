// Package jsonschema represents the limited JSON Schema definitions used by tools.
module jsonschema

import json2
import math

const max_schema_depth = 64

// DataType identifies the JSON primitive or container type.
pub enum DataType {
	object
	number
	integer
	string
	array
	null_value
	boolean
}

// str returns the JSON Schema spelling for a data type.
pub fn (data_type DataType) str() string {
	return match data_type {
		.object { 'object' }
		.number { 'number' }
		.integer { 'integer' }
		.string { 'string' }
		.array { 'array' }
		.null_value { 'null' }
		.boolean { 'boolean' }
	}
}

// Definition describes the JSON Schema subset supported by LangChainGo tools.
pub struct Definition {
pub:
	type_                 ?DataType
	description           string
	enum_values           []string
	properties            map[string]Definition
	required              []string
	items                 ?&Definition
	minimum               ?f64
	maximum               ?f64
	min_length            ?int
	max_length            ?int
	min_items             ?int
	max_items             ?int
	additional_properties ?bool
}

// to_any validates the definition and converts it to a JSON value.
pub fn (definition Definition) to_any() !json2.Any {
	definition.validate()!
	return definition.to_any_depth(0)
}

fn (definition Definition) to_any_depth(depth int) !json2.Any {
	if depth > max_schema_depth {
		return error('JSON Schema nesting exceeds the 64-level limit')
	}
	mut result := map[string]json2.Any{
		'properties': json2.Any(map[string]json2.Any{})
	}
	if data_type := definition.type_ {
		result['type'] = json2.Any(data_type.str())
	}
	if definition.description != '' {
		result['description'] = json2.Any(definition.description)
	}
	if minimum := definition.minimum {
		result['minimum'] = json2.Any(minimum)
	}
	if maximum := definition.maximum {
		result['maximum'] = json2.Any(maximum)
	}
	if min_length := definition.min_length {
		result['minLength'] = json2.Any(min_length)
	}
	if max_length := definition.max_length {
		result['maxLength'] = json2.Any(max_length)
	}
	if min_items := definition.min_items {
		result['minItems'] = json2.Any(min_items)
	}
	if max_items := definition.max_items {
		result['maxItems'] = json2.Any(max_items)
	}
	if additional_properties := definition.additional_properties {
		result['additionalProperties'] = json2.Any(additional_properties)
	}
	if definition.enum_values.len > 0 {
		mut values := []json2.Any{cap: definition.enum_values.len}
		for value in definition.enum_values {
			values << json2.Any(value)
		}
		result['enum'] = json2.Any(values)
	}
	if definition.properties.len > 0 {
		mut properties := map[string]json2.Any{}
		for name, property in definition.properties {
			properties[name] = property.to_any_depth(depth + 1)!
		}
		result['properties'] = json2.Any(properties)
	}
	if definition.required.len > 0 {
		mut required := []json2.Any{cap: definition.required.len}
		for name in definition.required {
			required << json2.Any(name)
		}
		result['required'] = json2.Any(required)
	}
	if items := definition.items {
		result['items'] = items.to_any_depth(depth + 1)!
	}
	return json2.Any(result)
}

// encode validates and serializes the definition as JSON.
pub fn (definition Definition) encode() !string {
	return json2.encode(definition.to_any()!, json2.EncoderOptions{})
}

// validate checks the supported schema invariants recursively.
pub fn (definition Definition) validate() ! {
	definition.validate_depth(0)!
}

fn (definition Definition) validate_depth(depth int) ! {
	if depth > max_schema_depth {
		return error('JSON Schema nesting exceeds the 64-level limit')
	}
	if data_type := definition.type_ {
		if data_type == .array && definition.properties.len > 0 {
			return error('JSON Schema array definitions cannot declare object properties')
		}
		if data_type != .array && definition.items != none {
			return error('JSON Schema items is only valid for array definitions')
		}
		if data_type != .object && definition.required.len > 0 {
			return error('JSON Schema required is only valid for object definitions')
		}
		if data_type != .object && definition.properties.len > 0 {
			return error('JSON Schema properties is only valid for object definitions')
		}
		if data_type !in [.number, .integer] && (definition.minimum != none || definition.maximum != none) {
			return error('JSON Schema minimum and maximum are only valid for number or integer definitions')
		}
		if data_type != .string && (definition.min_length != none || definition.max_length != none) {
			return error('JSON Schema minLength and maxLength are only valid for string definitions')
		}
		if data_type != .array && (definition.min_items != none || definition.max_items != none) {
			return error('JSON Schema minItems and maxItems are only valid for array definitions')
		}
		if data_type != .object && definition.additional_properties != none {
			return error('JSON Schema additionalProperties is only valid for object definitions')
		}
	}
	if minimum := definition.minimum {
		if !math.is_finite(minimum) {
			return error('JSON Schema minimum must be finite')
		}
	}
	if maximum := definition.maximum {
		if !math.is_finite(maximum) {
			return error('JSON Schema maximum must be finite')
		}
	}
	if minimum := definition.minimum {
		if maximum := definition.maximum {
			if minimum > maximum {
				return error('JSON Schema minimum must not exceed maximum')
			}
		}
	}
	if min_length := definition.min_length {
		if min_length < 0 {
			return error('JSON Schema minLength must not be negative')
		}
	}
	if max_length := definition.max_length {
		if max_length < 0 {
			return error('JSON Schema maxLength must not be negative')
		}
	}
	if min_length := definition.min_length {
		if max_length := definition.max_length {
			if min_length > max_length {
				return error('JSON Schema minLength must not exceed maxLength')
			}
		}
	}
	if min_items := definition.min_items {
		if min_items < 0 {
			return error('JSON Schema minItems must not be negative')
		}
	}
	if max_items := definition.max_items {
		if max_items < 0 {
			return error('JSON Schema maxItems must not be negative')
		}
	}
	if min_items := definition.min_items {
		if max_items := definition.max_items {
			if min_items > max_items {
				return error('JSON Schema minItems must not exceed maxItems')
			}
		}
	}
	mut enum_values := map[string]bool{}
	for value in definition.enum_values {
		if value in enum_values {
			return error('JSON Schema enum values must be unique')
		}
		enum_values[value] = true
	}
	mut required_names := map[string]bool{}
	for name in definition.required {
		if name.trim_space() == '' {
			return error('JSON Schema required names must not be empty')
		}
		if name in required_names {
			return error('JSON Schema required names must be unique')
		}
		if name !in definition.properties {
			return error('JSON Schema required name `${name}` has no property definition')
		}
		required_names[name] = true
	}
	for name, property in definition.properties {
		if name.trim_space() == '' {
			return error('JSON Schema property names must not be empty')
		}
		property.validate_depth(depth + 1)!
	}
	if items := definition.items {
		items.validate_depth(depth + 1)!
	}
}
