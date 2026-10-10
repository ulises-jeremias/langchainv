module chains

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.memory
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema

struct EchoCompletionModel {}

fn (model EchoCompletionModel) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	options.validate()!
	return 'completion: ${prompt}'
}

fn test_llm_chain_formats_prompt_and_validates_contract() {
	mut ctx := context.background()
	mut chain := new_llm_chain(EchoCompletionModel{}, prompts.StringTemplate{
		template: 'Question: {question}'
	}, 'answer') or { panic(err) }
	mut inputs := map[string]json2.Any{}
	inputs['question'] = json2.Any('What is V?')
	outputs := call(mut ctx, chain, inputs) or { panic(err) }
	answer := outputs['answer'] or { panic('missing answer') }
	assert answer.str() == 'completion: Question: What is V?'
	assert chain.input_keys() == ['question']
	assert chain.output_keys() == ['answer']
}

fn test_llm_chain_rejects_empty_output_key_and_missing_input() {
	new_llm_chain(EchoCompletionModel{}, prompts.StringTemplate{
		template: '{question}'
	}, '   ') or {
		assert err.msg().contains('output key')
		return
	}
	assert false, 'expected empty output key to fail'
	mut ctx := context.background()
	mut chain := new_llm_chain(EchoCompletionModel{}, prompts.StringTemplate{
		template: '{question}'
	}, 'answer') or { panic(err) }
	call(mut ctx, chain, map[string]json2.Any{}) or {
		assert err.msg().contains('missing required chain input')
		return
	}
	assert false, 'expected missing prompt input to fail'
}

fn test_llm_chain_loads_and_saves_optional_memory() {
	mut ctx := context.background()
	conversation := memory.new_conversation_buffer('history', 'question', 'answer') or {
		panic(err)
	}
	mut chain := new_llm_chain(EchoCompletionModel{}, prompts.StringTemplate{
		template: '{history}\nQuestion: {question}'
	}, 'answer') or { panic(err) }
	chain.memory_store = schema.Memory(conversation)
	mut first_input := map[string]json2.Any{}
	first_input['question'] = json2.Any('first')
	call(mut ctx, chain, first_input) or { panic(err) }
	mut second_input := map[string]json2.Any{}
	second_input['question'] = json2.Any('second')
	second_output := call(mut ctx, chain, second_input) or { panic(err) }
	answer := second_output['answer'] or { panic('missing answer') }
	assert answer.str().contains('Human: first')
	assert answer.str().ends_with('Question: second')
}
