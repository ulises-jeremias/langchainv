module prompts

import json2
import ulises_jeremias.langchainv.schema

struct FixtureExampleSelectorState {
mut:
	examples        []map[string]string
	selected_inputs map[string]string
}

struct FixtureExampleSelector {
	state &FixtureExampleSelectorState
}

fn (selector FixtureExampleSelector) add_example(example map[string]string) string {
	mut state := selector.state
	state.examples << example.clone()
	return 'fixture-' + state.examples.len.str()
}

fn (selector FixtureExampleSelector) select_examples(input_variables map[string]string) []map[string]string {
	mut state := selector.state
	state.selected_inputs = input_variables.clone()
	return state.examples.clone()
}

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

fn test_few_shot_prompt_formats_fixed_examples_and_caller_values() {
	prompt := new_few_shot_prompt(StringTemplate{
		template: '{word} -> {translation}'
	}, [
		{
			'word':        'hola'
			'translation': 'hello'
		},
		{
			'word':        'adios'
			'translation': 'goodbye'
		},
	], 'Translate these words:', 'Translate {word}:', '') or { panic(err) }
	variables := prompt.input_variables() or { panic(err) }
	assert variables == ['word']
	formatted := prompt.format({
		'word': json2.Any('gracias')
	}) or { panic(err) }
	assert formatted == 'Translate these words:\n\nhola -> hello\n\nadios -> goodbye\n\nTranslate gracias:'
}

fn test_few_shot_prompt_rejects_missing_example_variables() {
	new_few_shot_prompt(StringTemplate{
		template: '{word} -> {translation}'
	}, [
		{
			'word': 'hola'
		},
	], '', '{word}', '') or {
		assert err.msg().contains('missing variable')
		return
	}
	assert false, 'expected incomplete example to fail'
}

fn test_few_shot_prompt_requires_at_least_one_example() {
	new_few_shot_prompt(StringTemplate{
		template: '{word}'
	}, []map[string]string{}, '', '{word}', '') or {
		assert err.msg().contains('at least one example')
		return
	}
	assert false, 'expected empty examples to fail'
}

fn test_selected_few_shot_prompt_passes_inputs_to_selector() {
	mut selector_state := &FixtureExampleSelectorState{
		examples: [
			{
				'word':        'hola'
				'translation': 'hello'
			},
		]
	}
	selector := FixtureExampleSelector{
		state: selector_state
	}
	prompt := new_selected_few_shot_prompt(StringTemplate{
		template: '{word} -> {translation}'
	}, selector, '', 'Translate {word}:', ' / ') or { panic(err) }
	formatted := prompt.format({
		'word': json2.Any('gracias')
	}) or { panic(err) }
	assert formatted == 'hola -> hello / Translate gracias:'
	assert selector_state.selected_inputs.len == 1
	assert selector_state.selected_inputs['word'] == 'gracias'
}
