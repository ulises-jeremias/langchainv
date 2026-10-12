module main

import context
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.testing.llmtest

fn main() {
	model := llmtest.new_mock_model(llms.Response{
		choices: [llms.Choice{
			content: 'A mock keeps this example deterministic and offline.'
		}]
	})
	mut ctx := context.background()
	response := model.generate_content(mut ctx, [schema.text_message(.human, 'Why use a mock?')], llms.CallOptions{}) or {
		panic(err)
	}
	println(response.choices[0].content)
	println('Model calls: ${model.call_count()}')
}
