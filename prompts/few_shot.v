// FewShotPromptTemplate renders fixed or selected examples between prompt sections.
module prompts

import json2

// ExampleSelector supplies examples dynamically from the caller's input values.
pub interface ExampleSelector {
	add_example(example map[string]string) string
	select_examples(input_variables map[string]string) []map[string]string
}

pub struct FewShotPromptTemplate {
	example_prompt StringTemplate
	examples       []map[string]string
	selector       ?ExampleSelector
	prefix         ?StringTemplate
	suffix         ?StringTemplate
	separator      string
}

// new_few_shot_prompt constructs a static-example prompt with an optional separator.
// An empty separator uses two newlines. Examples are copied and validated at construction.
pub fn new_few_shot_prompt(example_prompt StringTemplate, examples []map[string]string, prefix string, suffix string, separator string) !FewShotPromptTemplate {
	return new_few_shot_prompt_parts(example_prompt, examples, none, prefix, suffix, separator)
}

// new_selected_few_shot_prompt constructs a prompt whose selector chooses examples at format time.
pub fn new_selected_few_shot_prompt(example_prompt StringTemplate, selector ExampleSelector, prefix string, suffix string, separator string) !FewShotPromptTemplate {
	return new_few_shot_prompt_parts(example_prompt, []map[string]string{}, selector, prefix, suffix,
		separator)
}

fn new_few_shot_prompt_parts(example_prompt StringTemplate, examples []map[string]string, selector ?ExampleSelector, prefix string, suffix string, separator string) !FewShotPromptTemplate {
	if examples.len == 0 && selector == none {
		return error('few-shot prompt requires at least one example')
	}
	example_variables := example_prompt.input_variables()!
	mut copied_examples := []map[string]string{cap: examples.len}
	for index, example in examples {
		mut copied_example := map[string]string{}
		for key, value in example {
			copied_example[key] = value
		}
		for variable in example_variables {
			if variable !in copied_example {
				return error('few-shot example ${index} is missing variable ${variable}')
			}
		}
		copied_examples << copied_example
	}
	mut prefix_template := ?StringTemplate(none)
	if prefix != '' {
		template := StringTemplate{
			template: prefix
		}
		template.input_variables()!
		prefix_template = template
	}
	mut suffix_template := ?StringTemplate(none)
	if suffix != '' {
		template := StringTemplate{
			template: suffix
		}
		template.input_variables()!
		suffix_template = template
	}
	return FewShotPromptTemplate{
		example_prompt: example_prompt
		examples:       copied_examples
		selector:       selector
		prefix:         prefix_template
		suffix:         suffix_template
		separator:      if separator == '' { '\n\n' } else { separator }
	}
}

// input_variables returns variables required by the prefix and suffix.
pub fn (few_shot FewShotPromptTemplate) input_variables() ![]string {
	mut variables := []string{}
	if prefix := few_shot.prefix {
		for variable in prefix.input_variables()! {
			variables << variable
		}
	}
	if suffix := few_shot.suffix {
		for variable in suffix.input_variables()! {
			if variable !in variables {
				variables << variable
			}
		}
	}
	return variables
}

// format renders the prefix, selected examples, and suffix in order.
pub fn (few_shot FewShotPromptTemplate) format(values map[string]json2.Any) !string {
	mut pieces := []string{cap: few_shot.examples.len + 2}
	mut examples := few_shot.examples.clone()
	if selector := few_shot.selector {
		mut input_variables := map[string]string{}
		for key, value in values {
			input_variables[key] = value.str()
		}
		examples = selector.select_examples(input_variables)
	}
	if prefix := few_shot.prefix {
		rendered := prefix.format(values)!
		if rendered != '' {
			pieces << rendered
		}
	}
	for index, example in examples {
		mut example_values := map[string]json2.Any{}
		for key, value in example {
			example_values[key] = json2.Any(value)
		}
		rendered := few_shot.example_prompt.format(example_values) or {
			return error('formatting few-shot example ${index} failed: ${err.msg()}')
		}
		if rendered != '' {
			pieces << rendered
		}
	}
	if suffix := few_shot.suffix {
		rendered := suffix.format(values)!
		if rendered != '' {
			pieces << rendered
		}
	}
	return pieces.join(few_shot.separator)
}
