module chains

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

struct PromptPresetFixtureModel {}

fn (_ PromptPresetFixtureModel) complete(mut _ctx context.Context, prompt string, _options llms.CallOptions) !string {
	return 'completion: ${prompt}'
}

fn test_question_answering_prompt_presets_declare_expected_inputs() {
	condense := load_condense_question_generator(PromptPresetFixtureModel{}) or { panic(err) }
	assert condense.input_keys() == ['chat_history', 'question']
	assert condense.output_keys() == ['output']

	stuff := load_stuff_qa(PromptPresetFixtureModel{}) or { panic(err) }
	assert stuff.input_keys() == ['input_documents', 'question']
	assert stuff.output_keys() == ['output']

	refine := load_refine_qa(PromptPresetFixtureModel{}) or { panic(err) }
	assert refine.input_keys() == ['input_documents', 'question']
	assert refine.output_keys() == ['output']

	map_reduce := load_map_reduce_qa(PromptPresetFixtureModel{}) or { panic(err) }
	assert map_reduce.input_keys() == ['input_documents', 'question']
	assert map_reduce.output_keys() == ['output']

	map_rerank := load_map_rerank_qa(PromptPresetFixtureModel{}) or { panic(err) }
	assert map_rerank.input_keys() == ['input_documents', 'question']
	assert map_rerank.output_keys() == ['output']
}

fn test_summarization_prompt_presets_declare_document_inputs() {
	stuff := load_stuff_summarization(PromptPresetFixtureModel{}) or { panic(err) }
	assert stuff.input_keys() == ['input_documents']
	assert stuff.output_keys() == ['output']

	refine := load_refine_summarization(PromptPresetFixtureModel{}) or { panic(err) }
	assert refine.input_keys() == ['input_documents']
	assert refine.output_keys() == ['output']

	map_reduce := load_map_reduce_summarization(PromptPresetFixtureModel{}) or { panic(err) }
	assert map_reduce.input_keys() == ['input_documents']
	assert map_reduce.output_keys() == ['output']
}

fn test_stuff_qa_preset_passes_question_and_documents_to_model() {
	chain := load_stuff_qa(PromptPresetFixtureModel{}) or { panic(err) }
	mut ctx := context.background()
	result := call(mut ctx, chain, {
		'input_documents': documents_value([schema.new_document('V is a language.')])
		'question':        json2.Any('What is V?')
	}) or { panic(err) }
	answer := result['output'] or { panic('missing output') }
	assert answer.str().contains('V is a language.')
	assert answer.str().contains('Question: What is V?')
}
