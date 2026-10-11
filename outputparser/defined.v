// Package outputparser defines a typed JSON response parser.
module outputparser

import json2

// Defined creates schema-guided prompts and parses JSON into a concrete V
// struct type. Because its parse result is T, it is intentionally separate
// from the type-erased Parser interface.
pub struct Defined[T] {
	schema string
}

// new_defined derives a prompt schema from a non-empty struct value.
// Primitive fields, primitive options, slices/maps of supported scalars, enums,
// and nested structs are supported. Unsupported field types return an error
// rather than silently producing an inaccurate schema.
pub fn new_defined[T](source T) !Defined[T] {
	$if T !is $struct {
		return error('defined parser expects a struct, got ${T.name}')
	}
	mut field_count := 0
	$for field in T.fields {
		field_count++
	}
	if field_count == 0 {
		return error('defined parser source struct has no fields')
	}
	schema := defined_struct_schema(source, '_Root')!
	return Defined[T]{
		schema: schema
	}
}

// parse requires a JSON code fence and decodes its contents into T.
pub fn (parser Defined[T]) parse(text string) !T {
	opening := '```json'
	closing := '```'
	if !text.starts_with(opening) || !text.ends_with(closing)
		|| text.len < opening.len + closing.len {
		return error('input text should start with ${opening} and end with ${closing}')
	}
	json_text := text[opening.len..text.len - closing.len].trim_space()
	return json2.decode[T](json_text, json2.DecoderOptions{}) or {
		return error('could not parse generated JSON: ${err}')
	}
}

// format_instructions returns the generated interface schema.
pub fn (parser Defined[T]) format_instructions() string {
	return 'Your output should be in JSON, structured according to this schema:\n```json\n${parser.schema}\n```'
}

// type_name identifies this parser.
pub fn (_ Defined[T]) type_name() string {
	return 'defined_parser'
}

fn defined_struct_schema[T](source T, name string) !string {
	$if T !is $struct {
		return error('nested defined parser schema expects a struct, got ${T.name}')
	}
	mut fields := []string{}
	mut nested_schemas := []string{}
	$for field in T.fields {
		mut field_name := field.name
		mut description := ''
		for attribute in field.attrs {
			if key, value := attribute.split_once(':') {
				clean_value := value.trim_space().trim('"\'')
				match key.trim_space() {
					'json' {
						json_name := clean_value.all_before(',').trim_space()
						if json_name == '-' {
							field_name = ''
						} else if json_name != '' {
							field_name = json_name
						}
					}
					'describe' {
						description = clean_value
					}
					else {}
				}
			} else if attribute == 'skip' {
				field_name = ''
			}
		}
		if field_name != '' {
			mut field_type := ''
			$if field.typ is string {
				field_type = 'string'
			} $else $if field.typ is bool {
				field_type = 'boolean'
			} $else $if field.typ is $int || field.typ is $float {
				field_type = 'number'
			} $else $if field.typ is ?string {
				field_type = 'string | null'
			} $else $if field.typ is ?bool {
				field_type = 'boolean | null'
			} $else $if field.typ is ?int || field.typ is ?i64 || field.typ is ?i32 || field.typ is ?i16 || field.typ is ?i8 || field.typ is ?u64 || field.typ is ?u32 || field.typ is ?u16 || field.typ is ?u8 || field.typ is ?f32 || field.typ is ?f64 {
				field_type = 'number | null'
			} $else $if field.typ is []string {
				field_type = 'string[]'
			} $else $if field.typ is []bool {
				field_type = 'boolean[]'
			} $else $if field.typ is []int || field.typ is []i64 || field.typ is []i32 || field.typ is []i16 || field.typ is []i8 || field.typ is []u64 || field.typ is []u32 || field.typ is []u16 || field.typ is []u8 || field.typ is []f32 || field.typ is []f64 {
				field_type = 'number[]'
			} $else $if field.typ is map[string]string {
				field_type = 'Record<string, string>'
			} $else $if field.typ is map[string]bool {
				field_type = 'Record<string, boolean>'
			} $else $if field.typ is map[string]int || field.typ is map[string]i64 || field.typ is map[string]i32 || field.typ is map[string]i16 || field.typ is map[string]i8 || field.typ is map[string]u64 || field.typ is map[string]u32 || field.typ is map[string]u16 || field.typ is map[string]u8 || field.typ is map[string]f32 || field.typ is map[string]f64 {
				field_type = 'Record<string, number>'
			} $else $if field.is_enum {
				field_type = 'number'
			} $else $if field.typ is $struct {
				// Include the parent schema path so identically named fields at
				// different nesting levels cannot emit duplicate interface names.
				field_type = '${name}_${field.name.capitalize()}'
				nested_schemas << defined_struct_schema(source.$(field.name), field_type)!
			} $else {
				return error('unsupported field type on ${T.name}.${field.name}; supported types are strings, booleans, numbers, primitive options, primitive slices and maps, enums, and nested structs')
			}
			mut line := '\t"${field_name}": ${field_type};'
			if description != '' {
				line += ' // ${description}'
			}
			fields << line
		}
	}
	if fields.len == 0 {
		return error('defined parser source struct ${T.name} has no supported fields')
	}
	mut definition := 'interface ${name} {\n${fields.join('\n')}\n}'
	if nested_schemas.len > 0 {
		definition += '\n' + nested_schemas.join('\n')
	}
	return definition
}
