// Package chains provides prompt presets for question answering.
module chains

import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts

const default_stuff_qa_template = 'Use the following pieces of context to answer the question at the end. If you don\'t know the answer, just say that you don\'t know, don\'t try to make up an answer.\n\n{context}\n\nQuestion: {question}\nHelpful Answer:'
const default_refine_qa_template = 'The original question is as follows: {question}\nWe have provided an existing answer: {existing_answer}\nWe have the opportunity to refine the existing answer\n(only if needed) with some more context below.\n------------\n{context}\n------------\nGiven the new context, refine the original answer to better answer the question. \nIf the context isn\'t useful, return the original answer.'
const default_map_reduce_qa_map_template = 'Use the following portion of a long document to see if any of the text is relevant to answer the question. \nReturn any relevant text verbatim.\n{context}\nQuestion: {question}\nRelevant text, if any:'
const default_map_reduce_qa_reduce_template = 'Given the following extracted parts of a long document and a question, create a final answer. \nIf you don\'t know the answer, just say that you don\'t know. Don\'t try to make up an answer.\n\nQUESTION: {question}\n=========\n{context}\n=========\nFINAL ANSWER:'
const default_map_rerank_qa_template = 'Use the following pieces of context to answer the question at the end. If you don\'t know the answer, just say that you don\'t know, don\'t try to make up an answer.\nIn addition to giving an answer, also return a score of how fully it answered the user\'s question. This should be in the following format:\nQuestion: [question here]\nHelpful Answer: [answer here]\nScore: [score between 0 and 100]\nHow to determine the score:\n- Higher is a better answer\n- Better responds fully to the asked question, with sufficient level of detail\n- If you do not know the answer based on the context, that should be a score of 0\n- Don\'t be overconfident!\nExample #1\nContext:\n---------\nApples are red\n---------\nQuestion: what color are apples?\nHelpful Answer: red\nScore: 100\nExample #2\nContext:\n---------\nit was night and the witness forgot his glasses. he was not sure if it was a sports car or an suv\n---------\nQuestion: what type was the car?\nHelpful Answer: a sports car or an suv\nScore: 60\nExample #3\nContext:\n---------\nPears are either red or orange\n---------\nQuestion: what color are apples?\nHelpful Answer: This document does not answer the question\nScore: 0\nBegin!\nContext:\n---------\n{context}\n---------\nQuestion: {question}\nHelpful Answer:'
const default_condense_question_template = 'Given the following conversation and a follow up question, rephrase the follow up question to be a standalone question, in its original language.\n\nChat History:\n{chat_history}\nFollow Up Input: {question}\nStandalone question:'

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
