module main

import json2
import ulises_jeremias.langchainv.prompts

fn main() {
	template := prompts.StringTemplate{
		template: 'Explain {topic} for a {audience} audience in {style}.'
	}
	variables := template.input_variables() or { panic(err) }
	println('Inputs: ${variables.join(", ")}')

	prompt := template.format({
		'topic':    json2.Any('V modules')
		'audience': json2.Any('new developer')
		'style':    json2.Any('three short steps')
	}) or { panic(err) }
	println(prompt)
}
