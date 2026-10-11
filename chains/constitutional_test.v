module chains

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.memory
import ulises_jeremias.langchainv.prompts

struct ConstitutionalFakeModel {}

fn (model ConstitutionalFakeModel) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	options.validate()!
	if prompt.starts_with('Question:') {
		return 'initial answer'
	}
	if prompt.starts_with('Review the original') {
		return 'The answer lacks a needed detail.'
	}
	if prompt.starts_with('Revise the assistant response') {
		return 'revised answer'
	}
	return error('unexpected constitutional prompt')
}

fn test_constitutional_chain_critiques_revises_and_returns_intermediates() {
	base := new_llm_chain(ConstitutionalFakeModel{}, prompts.StringTemplate{
		template: 'Question: {question}'
	}, 'text') or { panic(err) }
	principles := [ConstitutionalPrinciple{
		name:             'clarity'
		critique_request: 'Check that the answer explains its claim.'
		revision_request: 'Add the missing explanation.'
	}]
	mut constitutional := new_constitutional_chain(base, principles, ConstitutionalOptions{
		return_intermediate: true
	}) or { panic(err) }
	mut ctx := context.background()
	outputs := call(mut ctx, constitutional, {
		'question': json2.Any('What is the result?')
	}) or { panic(err) }
	answer := outputs['output'] or { panic('missing final answer') }
	initial := outputs['initial_output'] or { panic('missing initial answer') }
	pairs := outputs['critiques_and_revisions'] or { panic('missing critique/revision steps') }
	assert answer == json2.Any('revised answer')
	assert initial == json2.Any('initial answer')
	assert pairs.str().contains('The answer lacks a needed detail.')
	assert pairs.str().contains('revised answer')
	assert constitutional.input_keys() == ['question']
	assert constitutional.output_keys() == ['output', 'initial_output', 'critiques_and_revisions']
}

fn test_constitutional_chain_requires_bounded_nonempty_principles() {
	base := new_llm_chain(ConstitutionalFakeModel{}, prompts.StringTemplate{
		template: 'Question: {question}'
	}, 'text') or { panic(err) }
	new_constitutional_chain(base, [], ConstitutionalOptions{}) or {
		assert err.msg().contains('principles')
		return
	}
	assert false, 'expected constitutional chain to require a principle'
}

fn test_constitutional_chain_preserves_wrapped_chain_memory_inputs() {
	conversation := memory.new_conversation_buffer('history', 'question', 'text') or {
		panic(err)
	}
	mut base := new_llm_chain(ConstitutionalFakeModel{}, prompts.StringTemplate{
		template: 'Question: {question}\nHistory: {history}'
	}, 'text') or { panic(err) }
	base.memory_store = conversation
	mut constitutional := new_constitutional_chain(base, [ConstitutionalPrinciple{
		name:             'clarity'
		critique_request: 'Check clarity.'
		revision_request: 'Improve clarity.'
	}], ConstitutionalOptions{}) or { panic(err) }
	assert constitutional.input_keys() == ['question']
	mut ctx := context.background()
	outputs := call(mut ctx, constitutional, {
		'question': json2.Any('Question with history')
	}) or { panic(err) }
	answer := outputs['output'] or { panic('missing constitutional answer') }
	assert answer == json2.Any('revised answer')
}
