// Package agents defines tool-using agent contracts and an iterative executor.
module agents

import context
import json2
import ulises_jeremias.langchainv.callbacks
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.tools

const default_max_iterations = 15
const hard_max_iterations = 1000
const intermediate_steps_key = 'intermediate_steps'

// Agent plans one or more tool actions or completes with return values.
pub interface Agent {
	plan(mut ctx context.Context, steps []schema.AgentStep, inputs map[string]string, options llms.CallOptions) !PlanResult
	input_keys() []string
	output_keys() []string
	get_tools() []tools.Tool
}

// PlanResult contains the next action batch or a terminal result.
pub struct PlanResult {
pub:
	actions []schema.AgentAction
	finish  ?schema.AgentFinish
}

// ExecutorOptions configures iteration bounds and optional executor behavior.
pub struct ExecutorOptions {
pub:
	max_iterations            int = default_max_iterations
	return_intermediate_steps bool
	call_options              llms.CallOptions
	memory                    ?schema.Memory
	callbacks_handler         ?callbacks.Handler
}

// Executor runs an agent until it finishes or reaches its iteration bound.
pub struct Executor {
	// These fields stay private so callers cannot bypass constructor validation.
	max_iterations            int = default_max_iterations
	return_intermediate_steps bool
	call_options              llms.CallOptions
	memory_store              ?schema.Memory
	callbacks_handler         ?callbacks.Handler
pub:
	agent Agent
}

// new_executor validates and creates an agent executor.
pub fn new_executor(agent Agent, options ExecutorOptions) !Executor {
	if options.max_iterations <= 0 || options.max_iterations > hard_max_iterations {
		return error('agent max_iterations must be between 1 and ${hard_max_iterations}')
	}
	return Executor{
		agent:                     agent
		max_iterations:            options.max_iterations
		return_intermediate_steps: options.return_intermediate_steps
		call_options:              options.call_options
		memory_store:              options.memory
		callbacks_handler:         options.callbacks_handler
	}
}

// new_default_executor creates an executor with default limits and no addons.
pub fn new_default_executor(agent Agent) !Executor {
	return new_executor(agent, ExecutorOptions{})
}

// call implements chains.Chain and expects string-valued agent inputs.
pub fn (executor Executor) call(mut ctx context.Context, values map[string]json2.Any) !map[string]json2.Any {
	mut inputs := map[string]string{}
	for key, value in values {
		match value {
			string {
				inputs[key] = value
			}
			else {
				return error('agent input `${key}` must be a string')
			}
		}
	}
	for key in executor.agent.input_keys() {
		if key !in inputs {
			return error('missing required agent input `${key}`')
		}
	}
	mut tools_by_name := map[string]tools.Tool{}
	for tool in executor.agent.get_tools() {
		name := tool.spec().name.trim_space()
		if name == '' {
			return error('agent tool names must not be empty')
		}
		key := name.to_lower()
		if key in tools_by_name {
			return error('duplicate agent tool name `${name}`')
		}
		tools_by_name[key] = tool
	}
	mut steps := []schema.AgentStep{}
	for _ in 0 .. executor.max_iterations {
		ctx_error := ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
		result := executor.agent.plan(mut ctx, steps, inputs, executor.call_options) or {
			return error('agent planning failed: ${err.msg()}')
		}
		if finish := result.finish {
			if result.actions.len > 0 {
				return error('agent plan cannot return actions and a finish together')
			}
			return executor.finish(mut ctx, finish, steps)
		}
		if result.actions.len == 0 {
			return error('agent plan returned neither actions nor a finish')
		}
		for action in result.actions {
			if mut active_handler := executor.callbacks_handler {
				active_handler.agent_action(mut ctx, action)
			}
			ctx_error_before_tool := ctx.err()
			if ctx_error_before_tool !is none {
				return ctx_error_before_tool
			}
			key := action.tool.trim_space().to_lower()
			if key !in tools_by_name {
				steps << schema.AgentStep{
					action:      action
					observation: '${action.tool} is not a valid tool, try another one'
				}
				continue
			}
			tool := tools_by_name[key]
			if mut active_handler := executor.callbacks_handler {
				active_handler.tool_start(mut ctx, action.tool_input)
			}
			tool_input := action.tool_input.trim_string_right('\nObservation:')
			observation := tool.call(mut ctx, tool_input) or {
				if mut active_handler := executor.callbacks_handler {
					active_handler.tool_error(mut ctx, err)
				}
				return error('agent tool `${action.tool}` failed: ${err.msg()}')
			}
			if mut active_handler := executor.callbacks_handler {
				active_handler.tool_end(mut ctx, observation)
			}
			steps << schema.AgentStep{
				action:      action
				observation: observation
			}
		}
	}
	return error('agent did not finish within ${executor.max_iterations} iterations')
}

fn (executor Executor) finish(mut ctx context.Context, finish schema.AgentFinish, steps []schema.AgentStep) !map[string]json2.Any {
	mut outputs := finish.return_values.clone()
	for key in executor.agent.output_keys() {
		if key !in outputs {
			return error('agent finish did not return declared output `${key}`')
		}
	}
	if executor.return_intermediate_steps {
		mut encoded_steps := []json2.Any{cap: steps.len}
		for step in steps {
			mut encoded_action := map[string]json2.Any{}
			encoded_action['tool'] = json2.Any(step.action.tool)
			encoded_action['tool_input'] = json2.Any(step.action.tool_input)
			encoded_action['log'] = json2.Any(step.action.log)
			encoded_action['tool_id'] = json2.Any(step.action.tool_id)
			mut encoded_step := map[string]json2.Any{}
			encoded_step['action'] = json2.Any(encoded_action)
			encoded_step['observation'] = json2.Any(step.observation)
			encoded_steps << json2.Any(encoded_step)
		}
		outputs[intermediate_steps_key] = json2.Any(encoded_steps)
	}
	if mut active_handler := executor.callbacks_handler {
		active_handler.agent_finish(mut ctx, finish)
	}
	return outputs
}

// memory returns the optional memory integrated by chains.call.
pub fn (executor Executor) memory() ?schema.Memory {
	return executor.memory_store
}

// input_keys returns the agent's declared inputs.
pub fn (executor Executor) input_keys() []string {
	return executor.agent.input_keys()
}

// output_keys returns declared outputs, including optional intermediate steps.
pub fn (executor Executor) output_keys() []string {
	mut keys := executor.agent.output_keys().clone()
	if executor.return_intermediate_steps && intermediate_steps_key !in keys {
		keys << intermediate_steps_key
	}
	return keys
}

// get_callback_handler returns the optional lifecycle handler.
pub fn (executor Executor) get_callback_handler() ?callbacks.Handler {
	return executor.callbacks_handler
}
