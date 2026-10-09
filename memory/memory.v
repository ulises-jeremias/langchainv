// Package memory contains chat history and chain memory implementations.
module memory

import context
import json2
import sync
import ulises_jeremias.langchainv.schema

// InMemoryChatMessageHistory is a concurrency-safe, process-local message store.
pub struct InMemoryChatMessageHistory {
	state &InMemoryChatMessageHistoryState
}

struct InMemoryChatMessageHistoryState {
mut:
	mutex    sync.Mutex
	messages []schema.Message
}

// new_in_memory_chat_message_history creates an empty history.
pub fn new_in_memory_chat_message_history() &InMemoryChatMessageHistory {
	return &InMemoryChatMessageHistory{
		state: &InMemoryChatMessageHistoryState{}
	}
}

// get_messages returns a snapshot of the stored messages.
pub fn (history InMemoryChatMessageHistory) get_messages(mut ctx context.Context) ![]schema.Message {
	err := ctx.err()
	if err !is none {
		return err
	}
	mut state := history.state
	state.mutex.lock()
	mut result := []schema.Message{cap: state.messages.len}
	for message in state.messages {
		result << clone_message(message)
	}
	state.mutex.unlock()
	return result
}

// add_message appends a snapshot of a message.
pub fn (history InMemoryChatMessageHistory) add_message(mut ctx context.Context, message schema.Message) ! {
	err := ctx.err()
	if err !is none {
		return err
	}
	mut state := history.state
	state.mutex.lock()
	state.messages << clone_message(message)
	state.mutex.unlock()
}

// clear removes all stored messages.
pub fn (history InMemoryChatMessageHistory) clear(mut ctx context.Context) ! {
	err := ctx.err()
	if err !is none {
		return err
	}
	mut state := history.state
	state.mutex.lock()
	state.messages.clear()
	state.mutex.unlock()
}

fn clone_message(message schema.Message) schema.Message {
	mut parts := []schema.ContentPart{cap: message.parts.len}
	for part in message.parts {
		match part {
			schema.BinaryPart {
				parts << schema.ContentPart(schema.BinaryPart{
					mime_type: part.mime_type
					data:      part.data.clone()
				})
			}
			else {
				parts << part
			}
		}
	}
	return schema.Message{
		role:     message.role
		parts:    parts
		metadata: clone_json_map(message.metadata)
	}
}

fn clone_json_map(values map[string]json2.Any) map[string]json2.Any {
	mut result := map[string]json2.Any{}
	for key, value in values {
		result[key] = clone_json_value(value)
	}
	return result
}

fn clone_json_value(value json2.Any) json2.Any {
	match value {
		[]json2.Any {
			mut result := []json2.Any{cap: value.len}
			for item in value {
				result << clone_json_value(item)
			}
			return json2.Any(result)
		}
		map[string]json2.Any {
			return json2.Any(clone_json_map(value))
		}
		else {
			return value
		}
	}
}

// ConversationBuffer stores input/output turns and exposes their transcript.
pub struct ConversationBuffer {
pub:
	history    schema.ChatMessageHistory
	memory_key string
	input_key  string
	output_key string
}

// new_conversation_buffer creates a buffer with explicit key names.
pub fn new_conversation_buffer(memory_key string, input_key string, output_key string) !ConversationBuffer {
	if memory_key == '' || input_key == '' || output_key == '' {
		return error('memory, input, and output keys must be non-empty')
	}
	return ConversationBuffer{
		history:    new_in_memory_chat_message_history()
		memory_key: memory_key
		input_key:  input_key
		output_key: output_key
	}
}

// memory_keys returns the key populated by this memory.
pub fn (buffer ConversationBuffer) memory_keys() []string {
	return [buffer.memory_key]
}

// load_memory_variables returns prior turns as a role-labeled transcript.
pub fn (buffer ConversationBuffer) load_memory_variables(mut ctx context.Context, inputs map[string]json2.Any) !map[string]json2.Any {
	messages := buffer.history.get_messages(mut ctx)!
	mut lines := []string{cap: messages.len}
	for message in messages {
		role := match message.role {
			.system { 'System' }
			.human { 'Human' }
			.ai { 'AI' }
			.tool { 'Tool' }
			.generic { 'Message' }
		}
		lines << '${role}: ${message.text()}'
	}
	mut result := map[string]json2.Any{}
	result[buffer.memory_key] = json2.Any(lines.join('\n'))
	return result
}

// save_context appends one human and one assistant message to the history.
pub fn (buffer ConversationBuffer) save_context(mut ctx context.Context, inputs map[string]json2.Any, outputs map[string]json2.Any) ! {
	if buffer.input_key !in inputs {
		return error('missing memory input `${buffer.input_key}`')
	}
	if buffer.output_key !in outputs {
		return error('missing memory output `${buffer.output_key}`')
	}
	input := inputs[buffer.input_key] or { return error('missing memory input `${buffer.input_key}`') }
	output := outputs[buffer.output_key] or { return error('missing memory output `${buffer.output_key}`') }
	buffer.history.add_message(mut ctx, schema.text_message(.human, input.str()))!
	buffer.history.add_message(mut ctx, schema.text_message(.ai, output.str()))!
}

// clear removes all conversation history.
pub fn (buffer ConversationBuffer) clear(mut ctx context.Context) ! {
	buffer.history.clear(mut ctx)!
}
