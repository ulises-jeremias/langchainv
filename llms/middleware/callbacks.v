// Package middleware provides optional model decorators.
module middleware

import context
import ulises_jeremias.langchainv.callbacks
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

// CallbackModel dispatches the shared model lifecycle around another model.
// It is useful for provider adapters that do not expose their own callback
// configuration.
pub struct CallbackModel {
	model llms.Model
pub mut:
	handler callbacks.Handler
}

// with_callbacks wraps a model and dispatches start, end, and error events.
pub fn with_callbacks(model llms.Model, handler callbacks.Handler) CallbackModel {
	return CallbackModel{
		model:   model
		handler: handler
	}
}

// generate_content forwards the request and reports its lifecycle.
pub fn (mut model CallbackModel) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	model.handler.llm_generate_content_start(mut ctx, messages)
	response := model.model.generate_content(mut ctx, messages, options) or {
		model.handler.llm_error(mut ctx, err)
		return err
	}
	model.handler.llm_generate_content_end(mut ctx, response)
	return response
}

// CallbackCompletionModel dispatches the shared lifecycle around a completion model.
pub struct CallbackCompletionModel {
	model llms.CompletionModel
pub mut:
	handler callbacks.Handler
}

// with_completion_callbacks wraps a completion model with lifecycle callbacks.
pub fn with_completion_callbacks(model llms.CompletionModel, handler callbacks.Handler) CallbackCompletionModel {
	return CallbackCompletionModel{
		model:   model
		handler: handler
	}
}

// complete forwards the prompt and reports its lifecycle.
pub fn (mut model CallbackCompletionModel) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	model.handler.llm_start(mut ctx, [prompt])
	response := model.model.complete(mut ctx, prompt, options) or {
		model.handler.llm_error(mut ctx, err)
		return err
	}
	model.handler.llm_complete_end(mut ctx, response)
	return response
}
