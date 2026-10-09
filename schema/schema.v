// Package schema contains the shared data types used by LangChainV components.
module schema

import context
import json2

// Document is a text unit with source metadata and an optional retrieval score.
pub struct Document {
pub mut:
	page_content string
	metadata     map[string]json2.Any
	score        f32
}

// new_document constructs a document with initialized metadata.
pub fn new_document(page_content string) Document {
	return Document{
		page_content: page_content
		metadata:     map[string]json2.Any{}
	}
}

// Role identifies the speaker or source of a chat message.
pub enum Role {
	system
	human
	ai
	tool
	generic
}

// TextPart carries plain text.
pub struct TextPart {
pub:
	text string
}

// ImageURLPart references an image by URL and optional detail hint.
pub struct ImageURLPart {
pub:
	url    string
	detail string
}

// BinaryPart carries binary content and its media type.
pub struct BinaryPart {
pub:
	mime_type string
	data      []u8
}

// FunctionCall describes a model-requested function invocation.
pub struct FunctionCall {
pub:
	name      string
	arguments string
}

// ToolDefinition describes a callable function offered to a model. Parameters
// contains an optional JSON Schema object.
pub struct ToolDefinition {
pub:
	name        string
	description string
	parameters  ?json2.Any
	strict      bool
}

// ToolChoice specifies whether the model may choose a tool or must choose one.
pub struct ToolChoice {
pub:
	mode string
	name string
}

// WebSearchOptions configures web search for providers that support it.
pub struct WebSearchOptions {
pub:
	search_context_size string
	user_location       ?UserLocation
}

// UserLocation carries an approximate location for localized web search.
pub struct UserLocation {
pub:
	location_type string
	approximate   ?ApproximateLocation
}

// ApproximateLocation contains coarse geographic search hints.
pub struct ApproximateLocation {
pub:
	country string
	city    string
	region  string
}

// ToolCall identifies a tool invocation requested by a model.
pub struct ToolCall {
pub:
	id            string
	call_type     string
	function_call FunctionCall
}

// ToolResult is the result associated with a prior tool call.
pub struct ToolResult {
pub:
	call_id string
	name    string
	content string
}

// ThinkingPart carries opaque provider reasoning data that may need replay.
pub struct ThinkingPart {
pub:
	text      string
	signature string
}

// RedactedThinkingPart carries provider-owned opaque reasoning data.
pub struct RedactedThinkingPart {
pub:
	data string
}

// ContentPart is one typed part of a multimodal message.
pub type ContentPart = BinaryPart
	| ImageURLPart
	| RedactedThinkingPart
	| TextPart
	| ThinkingPart
	| ToolCall
	| ToolResult

// Message is a chat message with ordered, typed content parts.
pub struct Message {
pub mut:
	role     Role
	parts    []ContentPart
	metadata map[string]json2.Any
}

// text_message creates a message with a single text part.
pub fn text_message(role Role, text string) Message {
	return Message{
		role:     role
		parts:    [ContentPart(TextPart{
			text: text
		})]
		metadata: map[string]json2.Any{}
	}
}

// text returns the textual parts joined in order. Non-text parts are skipped.
pub fn (message Message) text() string {
	mut out := []string{}
	for part in message.parts {
		match part {
			TextPart {
				out << part.text
			}
			ThinkingPart {
				out << part.text
			}
			else {}
		}
	}
	return out.join('')
}

// Retriever returns documents relevant to a query.
pub interface Retriever {
	get_relevant_documents(mut ctx context.Context, query string, options RetrievalOptions) ![]Document
}

// RetrievalOptions controls a retrieval request.
pub struct RetrievalOptions {
pub mut:
	k           int
	filter      map[string]json2.Any
	search_type string
}

// Memory provides context that a chain loads before a call and saves after it.
pub interface Memory {
	load_memory_variables(mut ctx context.Context, inputs map[string]json2.Any) !map[string]json2.Any
	save_context(mut ctx context.Context, inputs map[string]json2.Any, outputs map[string]json2.Any) !
	memory_keys() []string
}

// ChatMessageHistory stores and retrieves an ordered conversation.
pub interface ChatMessageHistory {
	get_messages(mut ctx context.Context) ![]Message
	add_message(mut ctx context.Context, message Message) !
	clear(mut ctx context.Context) !
}

// AgentAction is the action selected by an agent for a tool to execute.
pub struct AgentAction {
pub:
	tool       string
	tool_input string
	log        string
	tool_id    string
}

// AgentStep pairs an action with the tool's observation.
pub struct AgentStep {
pub:
	action      AgentAction
	observation string
}

// AgentFinish contains the final named values returned by an agent.
pub struct AgentFinish {
pub:
	return_values map[string]json2.Any
	log           string
}
