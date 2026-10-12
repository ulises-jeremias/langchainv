// Package agents provides a conversational text-based ReAct agent preset.
module agents

import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.tools

const default_conversational_react_history_key = 'history'

// new_conversational_react_agent creates a ReAct agent that receives prior
// conversation text through the `history` input key. Use Executor memory with
// chains.call to load and save turns automatically.
pub fn new_conversational_react_agent(model llms.CompletionModel, agent_tools []tools.Tool, options ReactOptions) !ReactAgent {
	mut keys := if options.input_keys.len == 0 {
		['input']
	} else {
		options.input_keys.clone()
	}
	if default_conversational_react_history_key !in keys {
		keys << default_conversational_react_history_key
	}
	if keys.len == 1 {
		return error('conversational ReAct agent requires an input key in addition to history')
	}
	mut configured := ReactOptions{
		input_keys:       keys
		output_key:       options.output_key
		max_prompt_bytes: options.max_prompt_bytes
		call_options:     options.call_options
		prompt:           options.prompt
	}
	if configured.prompt.template.trim_space() == '' {
		mut question_lines := []string{cap: keys.len - 1}
		for key in keys {
			if key != default_conversational_react_history_key {
				question_lines << key + ': {' + key + '}'
			}
		}
		configured.prompt = prompts.StringTemplate{
			template: 'Answer the user as a conversational assistant. Use these tools when they help:
{tools}

Available tool names: {tool_names}

Conversation history:
{history}

Current request:
${question_lines.join('\n')}

Use this format when a tool is needed:
Thought: what to do next
Action: one of [{tool_names}]
Action Input: the tool input
Observation: the tool result
... (repeat Thought/Action/Action Input/Observation as needed)
Thought: I now know the final answer
Final Answer: the answer

Previous steps:
{agent_scratchpad}'
		}
	}
	return new_react_agent(model, agent_tools, configured)
}
