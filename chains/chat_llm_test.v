module chains

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema

struct ChatChainModelState {
mut:
	messages [][]schema.Message
	options  []llms.CallOptions
	response llms.Response
}

struct ChatChainFixtureModel {
	state &ChatChainModelState
}

fn (model ChatChainFixtureModel) generate_content(mut _ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	mut state := model.state
	state.messages << messages.clone()
	state.options << options
	return state.response
}

fn test_chat_llm_chain_formats_chat_prompt_and_returns_model_content() {
	mut state := &ChatChainModelState{
		response: llms.Response{
			choices: [llms.Choice{
				content: 'answer'
			}]
		}
	}
	prompt := prompts.ChatPromptTemplate{
		messages: [
			prompts.ChatMessageTemplate{
				role:     .system
				template: prompts.StringTemplate{
					template: 'Answer about {topic}.'
				}
			},
			prompts.ChatMessageTemplate{
				role:     .human
				template: prompts.StringTemplate{
					template: 'Question: {question}'
				}
			},
		]
	}
	mut chain := new_chat_llm_chain(ChatChainFixtureModel{
		state: state
	}, prompt, 'answer') or { panic(err) }
	chain.options.max_tokens = 32
	mut ctx := context.background()
	outputs := call(mut ctx, chain, {
		'topic':    json2.Any('V')
		'question': json2.Any('What is V?')
	}) or { panic(err) }
	assert (outputs['answer'] or { panic('missing answer') }).str() == 'answer'
	assert chain.input_keys() == ['topic', 'question']
	assert chain.output_keys() == ['answer']
	assert state.messages.len == 1
	assert state.messages[0].len == 2
	assert state.messages[0][0].role == .system
	assert state.messages[0][0].text() == 'Answer about V.'
	assert state.messages[0][1].role == .human
	assert state.messages[0][1].text() == 'Question: What is V?'
	assert state.options[0].max_tokens == 32
}

fn test_chat_llm_chain_reports_empty_model_response() {
	chain := new_chat_llm_chain(ChatChainFixtureModel{
		state: &ChatChainModelState{}
	}, prompts.ChatPromptTemplate{
		messages: [
			prompts.ChatMessageTemplate{
				role:     .human
				template: prompts.StringTemplate{
					template: '{question}'
				}
			},
		]
	}, 'answer') or { panic(err) }
	mut ctx := context.background()
	call(mut ctx, chain, {
		'question': json2.Any('hello')
	}) or {
		assert err.msg().contains('no choices')
		return
	}
	assert false, 'expected an empty model response to fail'
}
