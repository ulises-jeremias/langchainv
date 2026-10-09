// Package prompts contains provider-neutral text prompt templates.
module prompts

import json2
import strings

// StringTemplate formats named values into a template using `{variable}`
// placeholders. Double braces escape a literal brace.
pub struct StringTemplate {
pub:
	template string
}

// input_variables lists placeholders in first-seen order without duplicates.
pub fn (template StringTemplate) input_variables() ![]string {
	mut variables := []string{}
	mut i := 0
	for i < template.template.len {
		if template.template[i] == `{` {
			if i + 1 < template.template.len && template.template[i + 1] == `{` {
				i += 2
				continue
			}
			end := find_close(template.template, i + 1, `}`)!
			name := template.template[i + 1..end].trim_space()
			validate_variable(name)!
			if name !in variables {
				variables << name
			}
			i = end + 1
			continue
		}
		if template.template[i] == `}` {
			if i + 1 < template.template.len && template.template[i + 1] == `}` {
				i += 2
				continue
			}
			return error('unmatched closing brace in prompt template')
		}
		i++
	}
	return variables
}

// format renders a prompt and fails if a required value is missing.
pub fn (template StringTemplate) format(values map[string]json2.Any) !string {
	mut out := strings.new_builder(template.template.len)
	mut i := 0
	for i < template.template.len {
		if template.template[i] == `{` {
			if i + 1 < template.template.len && template.template[i + 1] == `{` {
				out.write_string('{')
				i += 2
				continue
			}
			end := find_close(template.template, i + 1, `}`)!
			name := template.template[i + 1..end].trim_space()
			validate_variable(name)!
			if name !in values {
				return error('missing prompt value `${name}`')
			}
			out.write_string(values[name].str())
			i = end + 1
			continue
		}
		if template.template[i] == `}` {
			if i + 1 < template.template.len && template.template[i + 1] == `}` {
				out.write_string('}')
				i += 2
				continue
			}
			return error('unmatched closing brace in prompt template')
		}
		out.write_u8(template.template[i])
		i++
	}
	return out.str()
}

fn find_close(template string, start int, closing u8) !int {
	mut i := start
	for i < template.len {
		if template[i] == closing {
			return i
		}
		if template[i] == `{` {
			return error('nested opening brace in prompt variable')
		}
		i++
	}
	return error('unclosed prompt variable')
}

fn validate_variable(name string) ! {
	if name.len == 0 {
		return error('prompt variable name cannot be empty')
	}
	for c in name.bytes() {
		if !(c.is_letter() || c.is_digit() || c == `_`) {
			return error('invalid prompt variable `${name}`; use letters, digits, and underscores')
		}
	}
}
