module chains

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.memory as chat_memory
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema

struct ConversationalCompletionState {
mut:
	prompts   []string
	responses []string
}

struct ConversationalCompletionFixture {
	state &ConversationalCompletionState
}

fn (model ConversationalCompletionFixture) complete(mut _ctx context.Context, prompt string, _options llms.CallOptions) !string {
	mut state := model.state
	state.prompts << prompt
	if state.responses.len == 0 {
		return error('no fake completion response configured')
	}
	response := state.responses[0]
	state.responses = state.responses[1..].clone()
	return response
}

fn test_conversational_retrieval_qa_condenses_and_saves_original_turns() {
	mut retriever_state := &RetrievalFixtureState{
		documents: [schema.new_document('The city is Paris.')]
	}
	mut model_state := &ConversationalCompletionState{
		responses: ['Where is the museum?', 'The museum is in Paris.', 'When was it founded?',
			'It was founded in 1793.']
	}
	conversation := chat_memory.new_conversation_buffer('history', 'question', 'answer') or {
		panic(err)
	}
	chain := new_conversational_retrieval_qa_chain(RetrievalFixture{
		state: retriever_state
	}, ConversationalCompletionFixture{
		state: model_state
	}, prompts.StringTemplate{
		template: 'History:\n{history}\nFollow-up: {question}\nStandalone:'
	}, prompts.StringTemplate{
		template: 'Context: {context}\nQuestion: {question}'
	}, ConversationalRetrievalQAOptions{
		retrieval_qa: RetrievalQAOptions{
			memory:    conversation
			retrieval: schema.RetrievalOptions{
				k: 1
			}
		}
	}) or { panic(err) }
	mut ctx := context.background()
	first := call(mut ctx, chain, {
		'question': json2.Any('Where is it?')
	}) or { panic(err) }
	assert (first['answer'] or { panic('missing answer') }).str() == 'The museum is in Paris.'
	assert retriever_state.queries == ['Where is the museum?']
	second := call(mut ctx, chain, {
		'question': json2.Any('When was it founded?')
	}) or { panic(err) }
	assert (second['answer'] or { panic('missing answer') }).str() == 'It was founded in 1793.'
	assert retriever_state.queries == ['Where is the museum?', 'When was it founded?']
	assert model_state.prompts[2].contains('Human: Where is it?')
	assert model_state.prompts[2].contains('AI: The museum is in Paris.')
}

fn test_conversational_retrieval_qa_requires_memory() {
	model := RetrievalCompletionFixture{
		state: &RetrievalCompletionState{}
	}
	new_conversational_retrieval_qa_chain(RetrievalFixture{
		state: &RetrievalFixtureState{}
	}, model, prompts.StringTemplate{
		template: '{history} {question}'
	}, prompts.StringTemplate{
		template: '{context} {question}'
	}, ConversationalRetrievalQAOptions{}) or {
		assert err.msg().contains('requires memory')
		return
	}
	assert false, 'expected missing conversation memory to fail'
}

fn test_conversational_retrieval_qa_rejects_oversized_condensed_question_before_retrieval() {
	mut retriever_state := &RetrievalFixtureState{}
	model := ConversationalCompletionFixture{
		state: &ConversationalCompletionState{
			responses: ['rewritten question is too long']
		}
	}
	conversation := chat_memory.new_conversation_buffer('history', 'question', 'answer') or {
		panic(err)
	}
	chain := new_conversational_retrieval_qa_chain(RetrievalFixture{
		state: retriever_state
	}, model, prompts.StringTemplate{
		template: '{history} {question}'
	}, prompts.StringTemplate{
		template: '{context} {question}'
	}, ConversationalRetrievalQAOptions{
		retrieval_qa:       RetrievalQAOptions{
			memory: conversation
		}
		max_question_bytes: 16
	}) or { panic(err) }
	mut ctx := context.background()
	call(mut ctx, chain, {
		'question': json2.Any('follow-up')
	}) or {
		assert err.msg().contains('configured byte limit')
		assert retriever_state.queries.len == 0
		return
	}
	assert false, 'expected an oversized condensed question to fail'
}
