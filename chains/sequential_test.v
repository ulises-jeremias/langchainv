module chains

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts

struct SequentialEchoModel {}

fn (model SequentialEchoModel) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	options.validate()!
	return 'completion: ${prompt}'
}

fn test_sequential_chain_passes_accumulated_values_between_children() {
	first := new_llm_chain(SequentialEchoModel{}, prompts.StringTemplate{
		template: 'Draft: {question}'
	}, 'draft') or { panic(err) }
	second := new_llm_chain(SequentialEchoModel{}, prompts.StringTemplate{
		template: '{draft}, style: {style}'
	}, 'answer') or { panic(err) }
	mut sequence := new_sequential_chain([Chain(first), Chain(second)], ['question', 'style'],
		['answer']) or {
		panic(err)
	}
	mut ctx := context.background()
	mut inputs := map[string]json2.Any{}
	inputs['question'] = json2.Any('What is V?')
	inputs['style'] = json2.Any('brief')
	outputs := call(mut ctx, sequence, inputs) or { panic(err) }
	answer := outputs['answer'] or { panic('missing final answer') }
	assert answer.str() == 'completion: completion: Draft: What is V?, style: brief'
	assert sequence.input_keys() == ['question', 'style']
	assert sequence.output_keys() == ['answer']
}

fn test_sequential_chain_rejects_invalid_key_flow() {
	child := new_llm_chain(SequentialEchoModel{}, prompts.StringTemplate{
		template: '{missing}'
	}, 'answer') or { panic(err) }
	new_sequential_chain([Chain(child)], ['question'], ['answer']) or {
		assert err.msg().contains('unavailable input')
		return
	}
	assert false, 'expected unavailable child input to fail'
}

fn test_sequential_chain_rejects_duplicate_output_keys() {
	valid_child := new_llm_chain(SequentialEchoModel{}, prompts.StringTemplate{
		template: '{question}'
	}, 'answer') or { panic(err) }
	new_sequential_chain([Chain(valid_child)], ['question'], ['answer', 'answer']) or {
		assert err.msg().contains('unique')
		return
	}
	assert false, 'expected duplicate output key to fail'
}
