// Package agents provides the OpenAI-compatible function-calling preset.
module agents

import context
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.tools

// OpenAIFunctionsAgentOptions configures the function-calling preset.
pub struct OpenAIFunctionsAgentOptions {
pub:
	input_keys     []string = ['input']
	output_key     string   = 'output'
	system_prompt  string
	extra_messages []schema.Message
	call_options   llms.CallOptions
}

// OpenAIFunctionsAgent selects function calls through a provider-neutral model.
// Tool execution, replay, iteration bounds, memory, and executor callbacks are
// shared with ToolCallingAgent and Executor.
pub struct OpenAIFunctionsAgent {
	implementation ToolCallingAgent
}

// new_openai_functions_agent creates a function-calling preset with the
// conventional `input` and `output` keys. Tool parameter schemas come from each
// registered tool's ToolSpec. Extra messages are inserted after the system
// instructions and before the current input.
pub fn new_openai_functions_agent(model llms.Model, agent_tools []tools.Tool, options OpenAIFunctionsAgentOptions) !OpenAIFunctionsAgent {
	implementation := new_tool_calling_agent(model, agent_tools, ToolCallingAgentOptions{
		input_keys:     options.input_keys.clone()
		output_key:     options.output_key
		system_prompt:  options.system_prompt
		extra_messages: options.extra_messages.clone()
		call_options:   options.call_options
	})!
	return OpenAIFunctionsAgent{
		implementation: implementation
	}
}

// plan delegates function selection and grouped call replay to ToolCallingAgent.
pub fn (agent OpenAIFunctionsAgent) plan(mut ctx context.Context, steps []schema.AgentStep, inputs map[string]string, options llms.CallOptions) !PlanResult {
	return agent.implementation.plan(mut ctx, steps, inputs, options)
}

// input_keys returns the configured model input fields.
pub fn (agent OpenAIFunctionsAgent) input_keys() []string {
	return agent.implementation.input_keys()
}

// output_keys returns the configured final answer field.
pub fn (agent OpenAIFunctionsAgent) output_keys() []string {
	return agent.implementation.output_keys()
}

// get_tools returns the functions exposed to the model and executor.
pub fn (agent OpenAIFunctionsAgent) get_tools() []tools.Tool {
	return agent.implementation.get_tools()
}
