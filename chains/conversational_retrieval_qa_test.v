module chains

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.memory as chat_memory
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema

struct ConversationalRetrieverState {
mut:
	queries   []string
	documents []schema.Document
}

struct ConversationalRetrieverFixture {
	state &ConversationalRetrieverState
}

fn (retriever ConversationalRetrieverFixture) get_relevant_documents(mut _ctx context.Context, query string, _options schema.RetrievalOptions) ![]schema.Document {
	mut state := retriever.state
	state.queries << query
	return state.documents.clone()
}

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
	mut retriever_state := &ConversationalRetrieverState{
		documents: [schema.new_document('The city is Paris.')]
	}
	mut model_state := &ConversationalCompletionState{
		responses: ['The museum is in Paris.', 'When was it founded?', 'It was founded in 1793.']
	}
	conversation := chat_memory.new_conversation_buffer('history', 'question', 'answer') or {
		panic(err)
	}
	chain := new_conversational_retrieval_qa_chain(ConversationalRetrieverFixture{
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
	assert retriever_state.queries == ['Where is it?']
	second := call(mut ctx, chain, {
		'question': json2.Any('When was it founded?')
	}) or { panic(err) }
	assert (second['answer'] or { panic('missing answer') }).str() == 'It was founded in 1793.'
	assert retriever_state.queries == ['Where is it?', 'When was it founded?']
	assert model_state.prompts[1].contains('Human: Where is it?')
	assert model_state.prompts[1].contains('AI: The museum is in Paris.')
	assert model_state.prompts.len == 3
}

fn test_conversational_retrieval_qa_can_return_generated_question_without_rephrasing_answer() {
	mut retriever_state := &ConversationalRetrieverState{
		documents: [schema.new_document('source')]
	}
	mut model_state := &ConversationalCompletionState{
		responses: ['rewritten standalone question', 'answer using original question']
	}
	mut conversation := chat_memory.new_conversation_buffer('history', 'question', 'answer') or {
		panic(err)
	}
	mut ctx := context.background()
	conversation.save_context(mut ctx, {
		'question': json2.Any('earlier question')
	}, {
		'answer': json2.Any('earlier answer')
	}) or { panic(err) }
	chain := new_conversational_retrieval_qa_chain(ConversationalRetrieverFixture{
		state: retriever_state
	}, ConversationalCompletionFixture{
		state: model_state
	}, prompts.StringTemplate{
		template: 'History: {history}; Question: {question}'
	}, prompts.StringTemplate{
		template: '{context}; Final question: {question}'
	}, ConversationalRetrievalQAOptions{
		retrieval_qa:              RetrievalQAOptions{
			memory: conversation
		}
		rephrase_question:         false
		return_generated_question: true
	}) or { panic(err) }
	outputs := call(mut ctx, chain, {
		'question': json2.Any('original follow-up')
	}) or { panic(err) }
	assert chain.output_keys() == ['answer', 'generated_question']
	assert retriever_state.queries == ['rewritten standalone question']
	assert model_state.prompts[1].contains('Final question: original follow-up')
	assert (outputs['generated_question'] or { json2.Any('') }) == json2.Any('rewritten standalone question')
}

fn test_conversational_retrieval_qa_requires_memory() {
	model := ConversationalCompletionFixture{
		state: &ConversationalCompletionState{}
	}
	new_conversational_retrieval_qa_chain(ConversationalRetrieverFixture{
		state: &ConversationalRetrieverState{}
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
	mut retriever_state := &ConversationalRetrieverState{}
	model := ConversationalCompletionFixture{
		state: &ConversationalCompletionState{
			responses: ['rewritten question is too long']
		}
	}
	mut conversation := chat_memory.new_conversation_buffer('history', 'question', 'answer') or {
		panic(err)
	}
	mut ctx := context.background()
	conversation.save_context(mut ctx, {
		'question': json2.Any('earlier question')
	}, {
		'answer': json2.Any('earlier answer')
	}) or { panic(err) }
	chain := new_conversational_retrieval_qa_chain(ConversationalRetrieverFixture{
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
	call(mut ctx, chain, {
		'question': json2.Any('follow-up')
	}) or {
		assert err.msg().contains('configured byte limit')
		assert retriever_state.queries.len == 0
		return
	}
	assert false, 'expected an oversized condensed question to fail'
}
