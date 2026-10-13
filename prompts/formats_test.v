module prompts

import json2

fn test_template_formats_render_and_list_variables() {
	values := {
		'name':  json2.Any('Ada')
		'count': json2.Any(3)
	}
	f_string := Template{
		template: 'Hello {name}, {count} messages. {{literal}}'
		format:   .f_string
	}
	assert f_string.input_variables() or { panic(err) } == ['name', 'count']
	assert f_string.format(values) or { panic(err) } == 'Hello Ada, 3 messages. {literal}'

	go_template := Template{
		template: 'Hello {{ .name }}, {{.count}} messages.'
		format:   .go_template
	}
	assert go_template.input_variables() or { panic(err) } == ['name', 'count']
	assert go_template.format(values) or { panic(err) } == 'Hello Ada, 3 messages.'

	jinja := Template{
		template: 'Hello {{ name }}, {{count}} messages.'
		format:   .jinja2
	}
	assert jinja.input_variables() or { panic(err) } == ['name', 'count']
	assert jinja.format(values) or { panic(err) } == 'Hello Ada, 3 messages.'
}

fn test_template_go_format_supports_trim_markers() {
	template := Template{
		template: 'Hello {{- .name -}} !'
		format:   .go_template
	}
	rendered := template.format({
		'name': json2.Any('Ada')
	}) or { panic(err) }
	assert rendered == 'HelloAda!'
}

fn test_template_formats_report_missing_values() {
	template := Template{
		template: 'Hello {{ name }}'
		format:   .jinja2
	}
	template.format({}) or {
		assert err.msg().contains('missing prompt value `name`')
		return
	}
	assert false, 'expected a missing value to fail'
}

fn test_template_go_format_rejects_non_variable_actions() {
	template := Template{
		template: 'Today is {{ now }}'
		format:   .go_template
	}
	template.input_variables() or {
		assert err.msg().contains('Go template actions must name a variable')
		return
	}
	assert false, 'expected a non-variable action to fail'
}

fn test_template_jinja_format_rejects_statements_and_filters() {
	statement := Template{
		template: '{% if name %}Hi{% endif %}'
		format:   .jinja2
	}
	statement.format({
		'name': json2.Any('Ada')
	}) or {
		assert err.msg().contains('Jinja statements')
		return
	}
	assert false, 'expected a Jinja statement to fail'

	filtered := Template{
		template: 'Hello {{ name | upper }}'
		format:   .jinja2
	}
	filtered.format({
		'name': json2.Any('Ada')
	}) or {
		assert err.msg().contains('invalid prompt variable')
		return
	}
	assert false, 'expected a Jinja filter to fail'
}

fn test_template_rejects_unclosed_actions() {
	template := Template{
		template: 'Hello {{ .name '
		format:   .go_template
	}
	template.format({
		'name': json2.Any('Ada')
	}) or {
		assert err.msg().contains('unclosed')
		return
	}
	assert false, 'expected an unclosed action to fail'
}
