// Package agents provides initialization helpers for supported agent presets.
module agents

import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.tools

// AgentType selects a built-in agent preset for initialize_agent.
pub enum AgentType {
	react
	conversational_react
}

// initialize_agent creates a ReAct preset and wraps it in a bounded executor.
// Agent-specific prompt and model settings belong in ReactOptions; execution
// limits, memory, callbacks, and request defaults belong in ExecutorOptions.
pub fn initialize_agent(model llms.CompletionModel, agent_tools []tools.Tool, agent_type AgentType, agent_options ReactOptions, executor_options ExecutorOptions) !Executor {
	agent := match agent_type {
		.react { new_react_agent(model, agent_tools, agent_options)! }
		.conversational_react {
			new_conversational_react_agent(model, agent_tools, agent_options)!
		}
	}
	return new_executor(agent, executor_options)
}
