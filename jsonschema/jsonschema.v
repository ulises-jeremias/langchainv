// Package jsonschema represents the limited JSON Schema definitions used by tools.
module jsonschema

import json2
import math

const max_schema_depth = 64
const max_instance_nodes = 10000
const max_instance_bytes = 1048576

struct InstanceBudget {
mut:
	nodes int
	bytes int
}

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
	types                 []DataType
	description           string
	enum_values           []string
	properties            map[string]Definition
	required              []string
	items                 ?&Definition
	minimum               ?f64
	maximum               ?f64
	exclusive_minimum     ?f64
	exclusive_maximum     ?f64
	min_length            ?int
	max_length            ?int
	min_items             ?int
	max_items             ?int
	additional_properties ?bool
	format                string
	all_of                []Definition
	any_of                []Definition
	one_of                []Definition
	not                   ?&Definition
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
	if definition.types.len > 0 {
		mut types := []json2.Any{cap: definition.types.len}
		for data_type in definition.types {
			types << json2.Any(data_type.str())
		}
		result['type'] = json2.Any(types)
	} else if data_type := definition.type_ {
		result['type'] = json2.Any(data_type.str())
	}
	if definition.description != '' {
		result['description'] = json2.Any(definition.description)
	}
	if definition.format != '' {
		result['format'] = json2.Any(definition.format)
	}
	if minimum := definition.minimum {
		result['minimum'] = json2.Any(minimum)
	}
	if maximum := definition.maximum {
		result['maximum'] = json2.Any(maximum)
	}
	if exclusive_minimum := definition.exclusive_minimum {
		result['exclusiveMinimum'] = json2.Any(exclusive_minimum)
	}
	if exclusive_maximum := definition.exclusive_maximum {
		result['exclusiveMaximum'] = json2.Any(exclusive_maximum)
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
	if definition.all_of.len > 0 {
		mut schemas := []json2.Any{cap: definition.all_of.len}
		for sub_schema in definition.all_of {
			schemas << sub_schema.to_any_depth(depth + 1)!
		}
		result['allOf'] = json2.Any(schemas)
	}
	if definition.any_of.len > 0 {
		mut schemas := []json2.Any{cap: definition.any_of.len}
		for sub_schema in definition.any_of {
			schemas << sub_schema.to_any_depth(depth + 1)!
		}
		result['anyOf'] = json2.Any(schemas)
	}
	if definition.one_of.len > 0 {
		mut schemas := []json2.Any{cap: definition.one_of.len}
		for sub_schema in definition.one_of {
			schemas << sub_schema.to_any_depth(depth + 1)!
		}
		result['oneOf'] = json2.Any(schemas)
	}
	if not_schema := definition.not {
		result['not'] = not_schema.to_any_depth(depth + 1)!
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

// validate_instance checks a JSON value against this definition's supported
// JSON Schema subset. Errors include the failing instance path.
pub fn (definition Definition) validate_instance(instance json2.Any) ! {
	definition.validate()!
	mut budget := InstanceBudget{}
	inspect_instance(instance, '$', 0, mut budget)!
	definition.validate_instance_at(instance, '$', 0)!
}

fn inspect_instance(instance json2.Any, path string, depth int, mut budget InstanceBudget) ! {
	if depth > max_schema_depth {
		return error('JSON Schema instance nesting exceeds the 64-level limit at ${path}')
	}
	budget.nodes++
	if budget.nodes > max_instance_nodes {
		return error('JSON Schema instance exceeds the ${max_instance_nodes}-node limit at ${path}')
	}
	instance_bytes := match instance {
		string { instance.len }
		f64, f32, i64, int, i32, i16, i8, u64, u32, u16, u8 { 8 }
		bool, json2.Null { 1 }
		else { 0 }
	}
	if instance_bytes > max_instance_bytes - budget.bytes {
		return error('JSON Schema instance exceeds the ${max_instance_bytes}-byte limit at ${path}')
	}
	budget.bytes += instance_bytes
	match instance {
		[]json2.Any {
			for index, item in instance {
				inspect_instance(item, '${path}[${index}]', depth + 1, mut budget)!
			}
		}
		map[string]json2.Any {
			for name, value in instance {
				if name.len > max_instance_bytes - budget.bytes {
					return error('JSON Schema instance exceeds the ${max_instance_bytes}-byte limit at ${path}')
				}
				budget.bytes += name.len
				inspect_instance(value, '${path}.${name}', depth + 1, mut budget)!
			}
		}
		else {}
	}
}

fn (definition Definition) validate_instance_at(instance json2.Any, path string, depth int) ! {
	if depth > max_schema_depth {
		return error('JSON Schema instance nesting exceeds the 64-level limit at ${path}')
	}
	if !instance_matches_definition_type(instance, definition) {
		expected := if definition.types.len > 0 {
			definition.types.map(it.str()).join(', ')
		} else if data_type := definition.type_ {
			data_type.str()
		} else {
			'any'
		}
		return error('JSON Schema type mismatch at ${path}: expected ${expected}')
	}
	if definition.enum_values.len > 0 {
		if instance is string {
			if instance !in definition.enum_values {
				return error('JSON Schema enum mismatch at ${path}')
			}
		} else {
			return error('JSON Schema string enum cannot validate a non-string value at ${path}')
		}
	}
	match instance {
		string {
			if min_length := definition.min_length {
				if instance.runes().len < min_length {
					return error('JSON Schema string is shorter than minLength at ${path}')
				}
			}
			if max_length := definition.max_length {
				if instance.runes().len > max_length {
					return error('JSON Schema string is longer than maxLength at ${path}')
				}
			}
		}
		[]json2.Any {
			if min_items := definition.min_items {
				if instance.len < min_items {
					return error('JSON Schema array has fewer items than minItems at ${path}')
				}
			}
			if max_items := definition.max_items {
				if instance.len > max_items {
					return error('JSON Schema array has more items than maxItems at ${path}')
				}
			}
			if items := definition.items {
				for index, item in instance {
					items.validate_instance_at(item, '${path}[${index}]', depth + 1)!
				}
			}
		}
		map[string]json2.Any {
			for name in definition.required {
				if name !in instance {
					return error('JSON Schema required property `${name}` is missing at ${path}')
				}
			}
			for name, value in instance {
				if property := definition.properties[name] {
					property.validate_instance_at(value, '${path}.${name}', depth + 1)!
				} else if additional_properties := definition.additional_properties {
					if !additional_properties {
						return error('JSON Schema additional property `${name}` is not allowed at ${path}')
					}
				}
			}
		}
		else {}
	}
	if number := instance_number(instance) {
		if minimum := definition.minimum {
			if number < minimum {
				return error('JSON Schema number is below minimum at ${path}')
			}
		}
		if maximum := definition.maximum {
			if number > maximum {
				return error('JSON Schema number is above maximum at ${path}')
			}
		}
		if exclusive_minimum := definition.exclusive_minimum {
			if number <= exclusive_minimum {
				return error('JSON Schema number must be above exclusiveMinimum at ${path}')
			}
		}
		if exclusive_maximum := definition.exclusive_maximum {
			if number >= exclusive_maximum {
				return error('JSON Schema number must be below exclusiveMaximum at ${path}')
			}
		}
	}
	for sub_schema in definition.all_of {
		sub_schema.validate_instance_at(instance, path, depth + 1)!
	}
	if definition.any_of.len > 0 {
		mut matched := false
		for sub_schema in definition.any_of {
			mut failed := false
			sub_schema.validate_instance_at(instance, path, depth + 1) or { failed = true }
			if !failed {
				matched = true
				break
			}
		}
		if !matched {
			return error('JSON Schema instance does not match any anyOf schema at ${path}')
		}
	}
	if definition.one_of.len > 0 {
		mut matches := 0
		for sub_schema in definition.one_of {
			mut failed := false
			sub_schema.validate_instance_at(instance, path, depth + 1) or { failed = true }
			if !failed {
				matches++
			}
		}
		if matches != 1 {
			return error('JSON Schema instance must match exactly one oneOf schema at ${path}')
		}
	}
	if not_schema := definition.not {
		mut failed := false
		not_schema.validate_instance_at(instance, path, depth + 1) or { failed = true }
		if !failed {
			return error('JSON Schema instance must not match the `not` schema at ${path}')
		}
	}
}

fn instance_matches_type(instance json2.Any, data_type DataType) bool {
	return match data_type {
		.object { instance is map[string]json2.Any }
		.array { instance is []json2.Any }
		.string { instance is string }
		.boolean { instance is bool }
		.null_value { instance is json2.Null }
		.number { instance_number(instance) != none }
		.integer {
			if number := instance_number(instance) {
				number == math.floor(number)
			} else {
				false
			}
		}
	}
}

fn instance_matches_definition_type(instance json2.Any, definition Definition) bool {
	if definition.types.len > 0 {
		for data_type in definition.types {
			if instance_matches_type(instance, data_type) {
				return true
			}
		}
		return false
	}
	if data_type := definition.type_ {
		return instance_matches_type(instance, data_type)
	}
	return true
}

fn instance_number(instance json2.Any) ?f64 {
	return match instance {
		f64 { instance }
		f32 { f64(instance) }
		i64 { f64(instance) }
		int { f64(instance) }
		i32 { f64(instance) }
		i16 { f64(instance) }
		i8 { f64(instance) }
		u64 { f64(instance) }
		u32 { f64(instance) }
		u16 { f64(instance) }
		u8 { f64(instance) }
		else { none }
	}
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
		if data_type !in [.number, .integer]
			&& (definition.minimum != none || definition.maximum != none
				|| definition.exclusive_minimum != none || definition.exclusive_maximum != none) {
			return error('JSON Schema numeric bounds are only valid for number or integer definitions')
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
	if definition.type_ != none && definition.types.len > 0 {
		return error('JSON Schema cannot declare both type and types')
	}
	if definition.types.len > 0 {
		mut seen_types := map[DataType]bool{}
		for data_type in definition.types {
			if data_type in seen_types {
				return error('JSON Schema types must be unique')
			}
			seen_types[data_type] = true
		}
		if definition.items != none && DataType.array !in definition.types {
			return error('JSON Schema items requires array in types')
		}
		if (definition.required.len > 0 || definition.properties.len > 0
			|| definition.additional_properties != none) && DataType.object !in definition.types {
			return error('JSON Schema object constraints require object in types')
		}
		if (definition.minimum != none || definition.maximum != none
			|| definition.exclusive_minimum != none || definition.exclusive_maximum != none)
			&& DataType.number !in definition.types && DataType.integer !in definition.types {
			return error('JSON Schema numeric bounds require number or integer in types')
		}
		if (definition.min_length != none || definition.max_length != none)
			&& DataType.string !in definition.types {
			return error('JSON Schema minLength and maxLength require string in types')
		}
		if (definition.min_items != none || definition.max_items != none)
			&& DataType.array !in definition.types {
			return error('JSON Schema minItems and maxItems require array in types')
		}
		if definition.enum_values.len > 0 && DataType.string !in definition.types {
			return error('JSON Schema string enum requires string in types')
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
	if exclusive_minimum := definition.exclusive_minimum {
		if !math.is_finite(exclusive_minimum) {
			return error('JSON Schema exclusiveMinimum must be finite')
		}
	}
	if exclusive_maximum := definition.exclusive_maximum {
		if !math.is_finite(exclusive_maximum) {
			return error('JSON Schema exclusiveMaximum must be finite')
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
	if definition.format != '' {
		if definition.format.len > 64 {
			return error('JSON Schema format must be 1..64 letters, digits, dashes, underscores, or dots')
		}
		for character in definition.format.bytes() {
			if !(character.is_letter() || character.is_digit() || character in [`-`, `_`, `.`]) {
				return error('JSON Schema format must be 1..64 letters, digits, dashes, underscores, or dots')
			}
		}
		if data_type := definition.type_ {
			if data_type != .string {
				return error('JSON Schema format is only valid for string definitions')
			}
		}
		if definition.types.len > 0 && DataType.string !in definition.types {
			return error('JSON Schema format is only valid for string definitions')
		}
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
	for sub_schema in definition.all_of {
		sub_schema.validate_depth(depth + 1)!
	}
	for sub_schema in definition.any_of {
		sub_schema.validate_depth(depth + 1)!
	}
	for sub_schema in definition.one_of {
		sub_schema.validate_depth(depth + 1)!
	}
	if not_schema := definition.not {
		not_schema.validate_depth(depth + 1)!
	}
}
