// Package prompts provides string templates in f-string, Go, and Jinja formats.
module prompts

import json2

// TemplateFormat selects the placeholder syntax a Template uses. The f-string
// format is the `{name}` syntax of StringTemplate. The Go format accepts
// `{{ .name }}` actions with optional whitespace-trim markers. The Jinja
// format accepts `{{ name }}` variable actions only.
pub enum TemplateFormat {
	f_string
	go_template
	jinja2
}

// Template renders named values using the syntax chosen by its format.
// Pipelines, filters, control statements, and field access are not part of
// any supported format; templates that use them fail with an error.
pub struct Template {
pub:
	template string
	format   TemplateFormat = .f_string
}

// input_variables lists placeholders in first-seen order without duplicates.
pub fn (template Template) input_variables() ![]string {
	if template.format == .f_string {
		return StringTemplate{
			template: template.template
		}.input_variables()
	}
	segments := parse_template_actions(template.template, template.format)!
	mut variables := []string{}
	for segment in segments {
		if segment.is_variable && segment.text !in variables {
			variables << segment.text
		}
	}
	return variables
}

// format renders the template and fails if a required value is missing.
pub fn (template Template) format(values map[string]json2.Any) !string {
	if template.format == .f_string {
		return StringTemplate{
			template: template.template
		}.format(values)
	}
	segments := parse_template_actions(template.template, template.format)!
	mut out := ''
	for segment_index, segment in segments {
		if !segment.is_variable {
			mut text := segment.text
			if segment_index + 1 < segments.len && segments[segment_index + 1].trim_left {
				text = trim_trailing_whitespace(text)
			}
			out += text
			continue
		}
		value := values[segment.text] or {
			return error('missing prompt value `${segment.text}`')
		}
		out += value.str()
	}
	return out
}

struct TemplateSegment {
	is_variable bool
	text        string
	trim_left   bool
	trim_right  bool
}

fn parse_template_actions(template string, format TemplateFormat) ![]TemplateSegment {
	mut segments := []TemplateSegment{}
	mut index := 0
	mut text_start := 0
	for index < template.len {
		if format == .jinja2 && template[index..].starts_with('{%') {
			return error('Jinja statements are not supported; use variable actions only')
		}
		if !template[index..].starts_with('{{') {
			index++
			continue
		}
		rest := template[index + 2..]
		relative_close := rest.index('}}') or { return error('unclosed template action') }
		inner_end := index + 2 + relative_close
		raw_inner := template[index + 2..inner_end]
		mut name := raw_inner.trim_space()
		mut trim_left := false
		mut trim_right := false
		if format == .go_template {
			if name.starts_with('-') {
				trim_left = true
				name = name[1..].trim_space()
			}
			if name.ends_with('-') {
				trim_right = true
				name = name[..name.len - 1].trim_space()
			}
			if !name.starts_with('.') {
				return error('Go template actions must name a variable like {{ .name }}')
			}
			name = name[1..]
		}
		validate_variable(name)!
		if index > text_start {
			segments << TemplateSegment{
				text: template[text_start..index]
			}
		}
		segments << TemplateSegment{
			is_variable: true
			text:        name
			trim_left:   trim_left
			trim_right:  trim_right
		}
		index = inner_end + 2
		if trim_right {
			for index < template.len && template[index] in [` `, `\t`, `\r`, `\n`] {
				index++
			}
		}
		text_start = index
	}
	if text_start < template.len {
		segments << TemplateSegment{
			text: template[text_start..]
		}
	}
	return segments
}

fn trim_trailing_whitespace(text string) string {
	mut end := text.len
	for end > 0 && text[end - 1] in [` `, `\t`, `\r`, `\n`] {
		end--
	}
	return text[..end]
}
