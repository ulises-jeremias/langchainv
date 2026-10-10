// Package chains provides prompt presets for question answering.
module chains

import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts

const default_stuff_qa_template = 'Use the following pieces of context to answer the question at the end. If you do not know the answer, say that you do not know. Do not make up an answer.\n\n{context}\n\nQuestion: {question}\nHelpful Answer:'
const default_refine_qa_template = 'The original question is: {question}\nExisting answer: {existing_answer}\nRefine the answer only if the new context helps.\n------------\n{context}\n------------\nIf the context is not useful, return the original answer.'
const default_map_reduce_qa_map_template = 'Return relevant text verbatim from this document passage.\n{context}\nQuestion: {question}\nRelevant text, if any:'
const default_map_reduce_qa_reduce_template = 'Given the extracted passages, answer the question. If the answer is unknown, say so without making it up.\nQuestion: {question}\n=========\n{context}\n=========\nFinal answer:'
const default_map_rerank_qa_template = 'Answer the question from this context. Include a numeric score for completeness using this exact format:\nHelpful Answer: [answer]\nScore: [integer from 0 to 100]\nContext:\n{context}\nQuestion: {question}\nHelpful Answer:'
const default_condense_question_template = 'Given the conversation and a follow-up question, rewrite the follow-up as a standalone question in its original language.\nChat History:\n{chat_history}\nFollow Up Input: {question}\nStandalone question:'

// load_condense_question_generator creates a prompt chain for standalone questions.
pub fn load_condense_question_generator(model llms.CompletionModel) !LLMChain {
	return new_llm_chain(model, prompts.StringTemplate{
		template: default_condense_question_template
	}, 'output')
}

// load_stuff_qa creates a bounded QA chain that combines all input documents.
pub fn load_stuff_qa(model llms.CompletionModel) !StuffDocumentsChain {
	llm_chain := new_llm_chain(model, prompts.StringTemplate{
		template: default_stuff_qa_template
	}, 'output')!
	return new_stuff_documents_chain(llm_chain, StuffDocumentsOptions{})
}

// load_refine_qa creates a bounded QA chain that refines an answer in document order.
pub fn load_refine_qa(model llms.CompletionModel) !RefineDocumentsChain {
	initial_chain := new_llm_chain(model, prompts.StringTemplate{
		template: default_stuff_qa_template
	}, 'output')!
	refine_chain := new_llm_chain(model, prompts.StringTemplate{
		template: default_refine_qa_template
	}, 'output')!
	return new_refine_documents_chain(initial_chain, refine_chain, RefineDocumentsOptions{})
}

// load_map_reduce_qa creates a bounded sequential map/reduce QA chain.
pub fn load_map_reduce_qa(model llms.CompletionModel) !MapReduceDocumentsChain {
	map_chain := new_llm_chain(model, prompts.StringTemplate{
		template: default_map_reduce_qa_map_template
	}, 'output')!
	reduce_llm_chain := new_llm_chain(model, prompts.StringTemplate{
		template: default_map_reduce_qa_reduce_template
	}, 'output')!
	reduce_chain := new_stuff_documents_chain(reduce_llm_chain, StuffDocumentsOptions{})!
	return new_map_reduce_documents_chain(map_chain, reduce_chain, MapReduceDocumentsOptions{})
}

// load_map_rerank_qa creates a bounded QA chain that selects the highest score.
pub fn load_map_rerank_qa(model llms.CompletionModel) !MapRerankDocumentsChain {
	llm_chain := new_llm_chain(model, prompts.StringTemplate{
		template: default_map_rerank_qa_template
	}, 'output')!
	return new_map_rerank_documents_chain(llm_chain, MapRerankDocumentsOptions{})
}
