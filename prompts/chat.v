// ChatMessageTemplate formats one text message for a chat prompt.
module prompts

import json2
import ulises_jeremias.langchainv.schema

pub struct ChatMessageTemplate {
pub:
	role     schema.Role
	template StringTemplate
}

// ChatPromptTemplate renders ordered role-tagged text messages.
pub struct ChatPromptTemplate {
pub:
	messages []ChatMessageTemplate
}

// input_variables returns unique placeholders in first-seen message order.
pub fn (prompt ChatPromptTemplate) input_variables() ![]string {
	mut variables := []string{}
	for message in prompt.messages {
		for variable in message.template.input_variables()! {
			if variable !in variables {
				variables << variable
			}
		}
	}
	return variables
}

// format_messages renders each template as a text-only chat message.
pub fn (prompt ChatPromptTemplate) format_messages(values map[string]json2.Any) ![]schema.Message {
	mut messages := []schema.Message{cap: prompt.messages.len}
	for message in prompt.messages {
		rendered := message.template.format(values)!
		messages << schema.text_message(message.role, rendered)
	}
	return messages
}
