// Package agents provides a bounded text-based ReAct agent.
module agents

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.tools

const default_react_output_key = 'output'
const default_react_input_key = 'input'
const default_react_max_prompt_bytes = 65536
const max_react_prompt_bytes = 1048576
const max_react_tools = 64
const max_react_input_keys = 64
const max_react_key_bytes = 128

// ReactOptions configures MRKL-style ReAct prompts and request bounds.
pub struct ReactOptions {
pub:
	input_keys       []string
	output_key       string = default_react_output_key
	max_prompt_bytes int    = default_react_max_prompt_bytes
	call_options     llms.CallOptions
pub mut:
	prompt prompts.StringTemplate
}

// ReactAgent chooses a tool action or returns a final answer from text output.
pub struct ReactAgent {
pub:
	model       llms.CompletionModel
	agent_tools []tools.Tool
	options     ReactOptions
mut:
	keys []string
}

// new_react_agent creates a bounded zero-shot MRKL/ReAct agent.
pub fn new_react_agent(model llms.CompletionModel, agent_tools []tools.Tool, options ReactOptions) !ReactAgent {
	if agent_tools.len == 0 || agent_tools.len > max_react_tools {
		return error('ReAct agent requires between 1 and ${max_react_tools} tools')
	}
	if options.output_key.trim_space() == '' || options.output_key.len > max_react_key_bytes {
		return error('ReAct output key must contain 1..${max_react_key_bytes} bytes')
	}
	max_prompt_bytes := if options.max_prompt_bytes == 0 {
		default_react_max_prompt_bytes
	} else {
		options.max_prompt_bytes
	}
	if max_prompt_bytes < 256 || max_prompt_bytes > max_react_prompt_bytes {
		return error('ReAct prompt byte limit must be between 256 and ${max_react_prompt_bytes}')
	}
	keys := if options.input_keys.len == 0 {
		[default_react_input_key]
	} else {
		options.input_keys.clone()
	}
	if keys.len > max_react_input_keys {
		return error('ReAct agent supports at most ${max_react_input_keys} input keys')
	}
	mut seen_inputs := map[string]bool{}
	for key in keys {
		if key.trim_space() == '' || key.len > max_react_key_bytes || key in seen_inputs || key == 'agent_scratchpad'
			|| key == 'tool_names' || key == 'tools' || key == options.output_key {
			return error('ReAct agent input keys must be distinct, non-empty, and not reserved')
		}
		seen_inputs[key] = true
	}
	mut seen_tools := map[string]bool{}
	mut tool_bytes := 0
	for tool in agent_tools {
		spec := tool.spec()
		name := spec.name.trim_space()
		if name == '' || name.len > 128 || name.contains('\n') || name.contains('\r')
			|| name.to_lower() in seen_tools {
			return error('ReAct tool names must be unique, non-empty, and at most 128 bytes')
		}
		if spec.description.len > 8192 || spec.description.contains('\0') {
			return error('ReAct tool descriptions must be at most 8192 bytes and contain no NUL')
		}
		tool_bytes += name.len + spec.description.len + 5
		if tool_bytes > max_prompt_bytes {
			return error('ReAct tool descriptions exceed the configured prompt limit')
		}
		seen_tools[name.to_lower()] = true
	}
	mut configured := ReactOptions{
		input_keys:       options.input_keys.clone()
		output_key:       options.output_key
		max_prompt_bytes: max_prompt_bytes
		call_options:     options.call_options
		prompt:           options.prompt
	}
	if configured.prompt.template.trim_space() == '' {
		mut question_lines := []string{cap: keys.len}
		for key in keys {
			question_lines << key + ': {' + key + '}'
		}
		configured.prompt = prompts.StringTemplate{
			template: 'Answer the following question as best you can. You have access to these tools:\n{tools}\n\nUse this exact format:\nQuestion:\n${question_lines.join('\n')}\nThought: think about what to do\nAction: one of [{tool_names}]\nAction Input: the tool input\nObservation: the tool result\n... (repeat Thought/Action/Action Input/Observation as needed)\nThought: I now know the final answer\nFinal Answer: the answer\n\nPrevious steps:\n{agent_scratchpad}'
		}
	}
	if configured.prompt.template.len > max_prompt_bytes {
		return error('ReAct prompt template exceeds the configured byte limit')
	}
	prompt_keys := configured.prompt.input_variables()!
	for key in keys {
		if key !in prompt_keys {
			return error('ReAct prompt must include input key `${key}`')
		}
	}
	for key in ['agent_scratchpad', 'tool_names', 'tools'] {
		if key !in prompt_keys {
			return error('ReAct prompt must include `${key}`')
		}
	}
	if options.output_key in prompt_keys {
		return error('ReAct output key cannot also be a prompt input')
	}
	return ReactAgent{
		model:       model
		agent_tools: agent_tools.clone()
		options:     configured
		keys:        keys
	}
}

// plan formats a prompt with the scratchpad and parses one action or a finish.
pub fn (agent ReactAgent) plan(mut ctx context.Context, steps []schema.AgentStep, inputs map[string]string, request_options llms.CallOptions) !PlanResult {
	for key in agent.keys {
		if key !in inputs {
			return error('missing required ReAct input `${key}`')
		}
	}
	mut values := map[string]json2.Any{}
	for key in agent.keys {
		values[key] = json2.Any(inputs[key])
	}
	values['tools'] = json2.Any(react_tool_descriptions(agent.agent_tools))
	values['tool_names'] = json2.Any(react_tool_names(agent.agent_tools))
	values['agent_scratchpad'] = json2.Any(react_scratchpad(steps,
		agent.options.max_prompt_bytes)!)
	validate_react_prompt_size(agent.options.prompt, values, agent.options.max_prompt_bytes)!
	prompt := agent.options.prompt.format(values)!
	if prompt.len > agent.options.max_prompt_bytes {
		return error('formatted ReAct prompt exceeds the configured byte limit')
	}
	mut call_options := merge_call_options(agent.options.call_options, request_options, [])
	for stop_word in ['\nObservation:', '\n\tObservation:'] {
		if stop_word !in call_options.stop_words {
			call_options.stop_words << stop_word
		}
	}
	call_options.validate()!
	output := agent.model.complete(mut ctx, prompt, call_options) or {
		return error('ReAct model request failed: ${err.msg()}')
	}
	if output.len > agent.options.max_prompt_bytes {
		return error('ReAct model output exceeds the configured byte limit')
	}
	return parse_react_output(output, agent.options.output_key)
}

// input_keys returns required external inputs.
pub fn (agent ReactAgent) input_keys() []string {
	return agent.keys.clone()
}

// output_keys returns the configured final-answer key.
pub fn (agent ReactAgent) output_keys() []string {
	return [agent.options.output_key]
}

// get_tools returns tools exposed to the executor.
pub fn (agent ReactAgent) get_tools() []tools.Tool {
	return agent.agent_tools.clone()
}

fn react_tool_names(agent_tools []tools.Tool) string {
	mut names := []string{cap: agent_tools.len}
	for tool in agent_tools {
		names << tool.spec().name
	}
	return names.join(', ')
}

fn react_tool_descriptions(agent_tools []tools.Tool) string {
	mut descriptions := []string{cap: agent_tools.len}
	for tool in agent_tools {
		spec := tool.spec()
		descriptions << '${spec.name}: ${spec.description}'
	}
	return descriptions.join('\n')
}

fn react_scratchpad(steps []schema.AgentStep, max_bytes int) !string {
	if steps.len > hard_max_iterations {
		return error('ReAct scratchpad exceeds the ${hard_max_iterations}-step limit')
	}
	mut parts := []string{cap: steps.len * 2}
	mut size := 0
	for step in steps {
		if step.action.log.len + 1 > max_bytes - size {
			return error('ReAct scratchpad exceeds the configured prompt byte limit')
		}
		size += step.action.log.len + 1
		parts << step.action.log
		observation_prefix := 'Observation: '
		observation_len := observation_prefix.len + step.observation.len
		if observation_len + 1 > max_bytes - size {
			return error('ReAct scratchpad exceeds the configured prompt byte limit')
		}
		size += observation_len + 1
		parts << observation_prefix + step.observation
	}
	if parts.len > 0 {
		parts << 'Thought:'
		size += 'Thought:'.len + 1
	}
	if size > max_bytes {
		return error('ReAct scratchpad exceeds the configured prompt byte limit')
	}
	return parts.join('\n')
}

fn validate_react_prompt_size(template prompts.StringTemplate, values map[string]json2.Any, max_bytes int) ! {
	mut size := 0
	mut index := 0
	for index < template.template.len {
		if template.template[index] == `{` {
			if index + 1 < template.template.len && template.template[index + 1] == `{` {
				if size >= max_bytes {
					return error('formatted ReAct prompt exceeds the configured byte limit')
				}
				size++
				index += 2
				continue
			}
			end_after := template.template.index_after('}', index + 1) or {
				return error('unclosed ReAct prompt variable')
			}
			end := end_after - 1
			name := template.template[index + 1..end].trim_space()
			value := values[name] or { return error('missing prompt value `${name}`') }
			value_bytes := value.str().len
			if value_bytes > max_bytes - size {
				return error('formatted ReAct prompt exceeds the configured byte limit')
			}
			size += value_bytes
			index = end + 1
			continue
		}
		if template.template[index] == `}` && index + 1 < template.template.len
			&& template.template[index + 1] == `}` {
			if size >= max_bytes {
				return error('formatted ReAct prompt exceeds the configured byte limit')
			}
			size++
			index += 2
			continue
		}
		if size >= max_bytes {
			return error('formatted ReAct prompt exceeds the configured byte limit')
		}
		size++
		index++
	}
}

fn parse_react_output(output string, output_key string) !PlanResult {
	lines := output.split_into_lines()
	for index, line in lines {
		trimmed := line.trim_space()
		if !trimmed.to_lower().starts_with('action:') {
			continue
		}
		action_name := trimmed['Action:'.len..].trim_space()
		if action_name == '' {
			return error('ReAct output has an empty Action field')
		}
		for input_index in index + 1 .. lines.len {
			input_line := lines[input_index].trim_space()
			lower_input_line := input_line.to_lower()
			if lower_input_line.starts_with('action:') {
				return error('ReAct output has Action but no Action Input field')
			}
			if !lower_input_line.starts_with('action input:') {
				continue
			}
			mut action_input := input_line['action input:'.len..].trim_space()
			if input_index + 1 < lines.len {
				action_input += '\n' + lines[input_index + 1..].join('\n')
			}
			action_input = action_input.trim_space()
			if action_input == '' {
				return error('ReAct output has an empty Action Input field')
			}
			return PlanResult{
				actions: [schema.AgentAction{
					tool:       action_name
					tool_input: action_input
					log:        output
				}]
			}
		}
		return error('ReAct output has Action but no Action Input field')
	}
	if answer := parse_react_final_answer(output) {
		if answer == '' {
			return error('ReAct output has an empty Final Answer field')
		}
		mut return_values := map[string]json2.Any{}
		return_values[output_key] = json2.Any(answer)
		return PlanResult{
			finish: schema.AgentFinish{
				return_values: return_values
			}
		}
	}
	return error('ReAct output contains neither a final answer nor an action')
}

fn parse_react_final_answer(output string) ?string {
	for marker in ['final answer:', 'final answer :', 'the final answer is:', 'the answer is:'] {
		for line in output.split_into_lines() {
			trimmed := line.trim_space()
			if trimmed.to_lower().starts_with(marker) {
				return trimmed[marker.len..].trim_space()
			}
		}
	}
	return none
}
