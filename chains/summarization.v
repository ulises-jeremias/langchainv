// Package chains provides prompt presets for document summarization.
module chains

import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts

const default_stuff_summarization_template = 'Write a concise summary of the following:\n\n"{context}"\n\nConcise summary:'
const default_refine_summarization_template = 'Write a concise final summary. Existing summary:\n"{existing_answer}"\n\nNew context:\n"{context}"\n\nRefine the summary using the new context. If it is not useful, return the existing summary.'

// load_stuff_summarization creates a bounded chain that summarizes combined documents.
pub fn load_stuff_summarization(model llms.CompletionModel) !StuffDocumentsChain {
	llm_chain := new_llm_chain(model, prompts.StringTemplate{
		template: default_stuff_summarization_template
	}, 'output')!
	return new_stuff_documents_chain(llm_chain, StuffDocumentsOptions{})
}

// load_refine_summarization creates a bounded chain that refines a running summary.
pub fn load_refine_summarization(model llms.CompletionModel) !RefineDocumentsChain {
	initial_chain := new_llm_chain(model, prompts.StringTemplate{
		template: default_stuff_summarization_template
	}, 'output')!
	refine_chain := new_llm_chain(model, prompts.StringTemplate{
		template: default_refine_summarization_template
	}, 'output')!
	return new_refine_documents_chain(initial_chain, refine_chain, RefineDocumentsOptions{})
}

// load_map_reduce_summarization creates a bounded sequential map/reduce summarizer.
pub fn load_map_reduce_summarization(model llms.CompletionModel) !MapReduceDocumentsChain {
	map_chain := new_llm_chain(model, prompts.StringTemplate{
		template: default_stuff_summarization_template
	}, 'output')!
	reduce_chain := load_stuff_summarization(model)!
	return new_map_reduce_documents_chain(map_chain, reduce_chain, MapReduceDocumentsOptions{})
}
