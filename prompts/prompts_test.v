module prompts

import json2

fn test_string_template_format_and_variables() {
	template := StringTemplate{
		template: 'Hello, {name}! You have {count} messages.'
	}
	variables := template.input_variables() or { panic(err) }
	assert variables == ['name', 'count']
	formatted := template.format({
		'name':  json2.Any('Ada')
		'count': json2.Any(3)
	}) or { panic(err) }
	assert formatted == 'Hello, Ada! You have 3 messages.'
}

fn test_string_template_escapes_braces() {
	template := StringTemplate{
		template: '{{literal}} {name}'
	}
	formatted := template.format({
		'name': json2.Any('Ada')
	}) or { panic(err) }
	assert formatted == '{literal} Ada'
}

fn test_string_template_reports_missing_value() {
	StringTemplate{
		template: 'Hello, {name}'
	}.format(map[string]json2.Any{}) or {
		assert err.msg().contains('missing prompt value')
		return
	}
	assert false, 'expected missing value to fail'
}

fn test_string_template_rejects_malformed_braces() {
	StringTemplate{
		template: 'Hello, {name'
	}.input_variables() or {
		assert err.msg().contains('unclosed')
		return
	}
	assert false, 'expected malformed template to fail'
}
