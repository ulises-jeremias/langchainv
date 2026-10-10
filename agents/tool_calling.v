module agents

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.tools

// ToolCallingAgent turns model tool-call responses into executor actions.
pub struct ToolCallingAgent {
pub:
	model        llms.Model
	agent_tools  []tools.Tool
	keys         []string
	result_key   string
	instructions string
	call_options llms.CallOptions
}

// ToolCallingAgentOptions configures prompts, inputs, output, and model options.
pub struct ToolCallingAgentOptions {
pub:
	input_keys    []string
	output_key    string = 'output'
	system_prompt string
	call_options  llms.CallOptions
}

// new_tool_calling_agent validates and constructs a provider-neutral tool agent.
pub fn new_tool_calling_agent(model llms.Model, agent_tools []tools.Tool, options ToolCallingAgentOptions) !ToolCallingAgent {
	if agent_tools.len == 0 {
		return error('tool-calling agent requires at least one tool')
	}
	if options.input_keys.len == 0 || options.output_key.trim_space() == '' {
		return error('tool-calling agent requires input keys and an output key')
	}
	mut seen_inputs := map[string]bool{}
	for key in options.input_keys {
		if key.trim_space() == '' || key in seen_inputs {
			return error('tool-calling agent input keys must be non-empty and unique')
		}
		seen_inputs[key] = true
	}
	mut seen_tools := map[string]bool{}
	for tool in agent_tools {
		name := tool.spec().name.trim_space()
		if name == '' || name.to_lower() in seen_tools {
			return error('tool-calling agent tool names must be non-empty and unique')
		}
		seen_tools[name.to_lower()] = true
	}
	return ToolCallingAgent{
		model:        model
		agent_tools:  agent_tools.clone()
		keys:         options.input_keys.clone()
		result_key:   options.output_key.trim_space()
		instructions: options.system_prompt
		call_options: options.call_options
	}
}

// plan asks the model for a tool call or treats assistant text as the final answer.
pub fn (agent ToolCallingAgent) plan(mut ctx context.Context, steps []schema.AgentStep, inputs map[string]string, request_options llms.CallOptions) !PlanResult {
	mut messages := []schema.Message{}
	mut instruction := agent.instructions
	if instruction == '' {
		instruction = 'You are a tool-using assistant. Use the provided functions when useful; otherwise return the final answer as text.'
	}
	instruction += '\nAvailable tools:'
	for tool in agent.agent_tools {
		spec := tool.spec()
		instruction += '\n- ${spec.name}: ${spec.description}'
	}
	messages << schema.text_message(.system, instruction)
	mut input_keys := inputs.keys()
	input_keys.sort()
	mut prompt_lines := []string{}
	for key in input_keys {
		prompt_lines << '${key}: ${inputs[key]}'
	}
	messages << schema.text_message(.human, prompt_lines.join('\n'))
	for index, step in steps {
		call_id := if step.action.tool_id == '' {
			'agent-step-${index}'
		} else {
			step.action.tool_id
		}
		messages << schema.Message{
			role:  .ai
			parts: [schema.ContentPart(schema.ToolCall{
				id:            call_id
				call_type:     'function'
				function_call: schema.FunctionCall{
					name:      step.action.tool
					arguments: step.action.tool_input
				}
			})]
		}
		messages << schema.Message{
			role:  .tool
			parts: [schema.ContentPart(schema.ToolResult{
				call_id: call_id
				name:    step.action.tool
				content: step.observation
			})]
		}
	}
	mut definitions := []schema.ToolDefinition{cap: agent.agent_tools.len}
	for tool in agent.agent_tools {
		spec := tool.spec()
		definitions << schema.ToolDefinition{
			name:        spec.name
			description: spec.description
			parameters:  spec.parameters
		}
	}
	options := merge_call_options(agent.call_options, request_options, definitions)
	response := agent.model.generate_content(mut ctx, messages, options) or {
		return error('tool-calling model request failed: ${err.msg()}')
	}
	if response.choices.len == 0 {
		return error('tool-calling model returned no choices')
	}
	choice := response.choices[0]
	if choice.tool_calls.len > 0 {
		mut actions := []schema.AgentAction{cap: choice.tool_calls.len}
		for call in choice.tool_calls {
			if call.function_call.name.trim_space() == '' {
				return error('model returned a tool call without a function name')
			}
			actions << schema.AgentAction{
				tool:       call.function_call.name
				tool_input: call.function_call.arguments
				log:        choice.content
				tool_id:    call.id
			}
		}
		return PlanResult{
			actions: actions
		}
	}
	if function_call := choice.function_call {
		if function_call.name.trim_space() == '' {
			return error('model returned a function call without a function name')
		}
		return PlanResult{
			actions: [schema.AgentAction{
				tool:       function_call.name
				tool_input: function_call.arguments
				log:        choice.content
			}]
		}
	}
	mut return_values := map[string]json2.Any{}
	return_values[agent.result_key] = json2.Any(choice.content)
	return PlanResult{
		finish: schema.AgentFinish{
			return_values: return_values
		}
	}
}

fn merge_call_options(base llms.CallOptions, request llms.CallOptions, tool_definitions []schema.ToolDefinition) llms.CallOptions {
	mut result := base
	if request.model != '' {
		result.model = request.model
	}
	if request.max_tokens > 0 {
		result.max_tokens = request.max_tokens
	}
	if request.candidate_count > 0 {
		result.candidate_count = request.candidate_count
	}
	if request.n > 0 {
		result.n = request.n
	}
	if request.temperature != 0 {
		result.temperature = request.temperature
	}
	if request.top_p != 0 {
		result.top_p = request.top_p
	}
	if request.top_k != 0 {
		result.top_k = request.top_k
	}
	if request.min_length != 0 {
		result.min_length = request.min_length
	}
	if request.max_length != 0 {
		result.max_length = request.max_length
	}
	if request.repetition_penalty != 0 {
		result.repetition_penalty = request.repetition_penalty
	}
	if request.frequency_penalty != 0 {
		result.frequency_penalty = request.frequency_penalty
	}
	if request.presence_penalty != 0 {
		result.presence_penalty = request.presence_penalty
	}
	if request.seed != none {
		result.seed = request.seed
	}
	if request.stop_words.len > 0 {
		result.stop_words = request.stop_words.clone()
	}
	if request.json_mode {
		result.json_mode = true
	}
	if request.response_mime_type != '' {
		result.response_mime_type = request.response_mime_type
	}
	if request.tool_choice != none {
		result.tool_choice = request.tool_choice
	}
	result.tools = tool_definitions.clone()
	result.tools << base.tools
	result.tools << request.tools
	result.functions = base.functions.clone()
	result.functions << request.functions
	if request.function_call_behavior != '' {
		result.function_call_behavior = request.function_call_behavior
	}
	if request.streaming_func != none {
		result.streaming_func = request.streaming_func
	}
	if request.streaming_reasoning_func != none {
		result.streaming_reasoning_func = request.streaming_reasoning_func
	}
	if request.web_search_options != none {
		result.web_search_options = request.web_search_options
	}
	mut metadata := result.metadata.clone()
	for key, value in request.metadata {
		metadata[key] = value
	}
	result.metadata = metadata
	mut provider_options := result.provider_options.clone()
	for key, value in request.provider_options {
		provider_options[key] = value
	}
	result.provider_options = provider_options
	return result
}

// input_keys returns the configured prompt input fields.
pub fn (agent ToolCallingAgent) input_keys() []string {
	return agent.keys.clone()
}

// output_keys returns the configured final answer field.
pub fn (agent ToolCallingAgent) output_keys() []string {
	return [agent.result_key]
}

// get_tools returns the tools made available to the model and executor.
pub fn (agent ToolCallingAgent) get_tools() []tools.Tool {
	return agent.agent_tools.clone()
}
