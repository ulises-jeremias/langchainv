module prompts

import json2
import ulises_jeremias.langchainv.schema

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

fn test_chat_prompt_template_formats_messages_and_collects_variables() {
	prompt := ChatPromptTemplate{
		messages: [
			ChatMessageTemplate{
				role:     .system
				template: StringTemplate{
					template: 'Answer about {topic}.'
				}
			},
			ChatMessageTemplate{
				role:     .human
				template: StringTemplate{
					template: 'Question: {question} ({topic})'
				}
			},
		]
	}
	variables := prompt.input_variables() or { panic(err) }
	assert variables == ['topic', 'question']
	messages := prompt.format_messages({
		'topic':    json2.Any('V')
		'question': json2.Any('How?')
	}) or { panic(err) }
	assert messages.len == 2
	assert messages[0].role == schema.Role.system
	assert messages[0].text() == 'Answer about V.'
	assert messages[1].role == schema.Role.human
	assert messages[1].text() == 'Question: How? (V)'
}
