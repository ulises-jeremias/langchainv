// Chat prompt templates with typed multimodal parts.
module prompts

import json2
import ulises_jeremias.langchainv.schema

const max_image_url_bytes = 8192

// PartKind selects how a rendered PartTemplate enters a message.
pub enum PartKind {
	text
	image_url
}

// PartTemplate renders one content part. The text kind becomes a text part;
// the image_url kind becomes an image URL part whose rendered value must be
// a non-empty bounded string. Binary parts are built directly as
// schema.BinaryPart values, not through string templates.
pub struct PartTemplate {
pub:
	kind     PartKind = .text
	template StringTemplate
}

// MultimodalMessageTemplate renders one message from ordered part templates.
pub struct MultimodalMessageTemplate {
pub:
	role  schema.Role
	parts []PartTemplate
}

// MultimodalPromptTemplate renders ordered multimodal chat messages.
pub struct MultimodalPromptTemplate {
pub:
	messages []MultimodalMessageTemplate
}

// input_variables returns unique placeholders in first-seen order.
pub fn (prompt MultimodalPromptTemplate) input_variables() ![]string {
	mut variables := []string{}
	for message in prompt.messages {
		for part in message.parts {
			for variable in part.template.input_variables()! {
				if variable !in variables {
					variables << variable
				}
			}
		}
	}
	return variables
}

// format_messages renders every message with text and image URL parts.
pub fn (prompt MultimodalPromptTemplate) format_messages(values map[string]json2.Any) ![]schema.Message {
	mut messages := []schema.Message{cap: prompt.messages.len}
	for message in prompt.messages {
		if message.parts.len == 0 {
			return error('multimodal message templates require at least one part')
		}
		mut parts := []schema.ContentPart{cap: message.parts.len}
		for part in message.parts {
			rendered := part.template.format(values)!
			match part.kind {
				.text {
					parts << schema.ContentPart(schema.TextPart{
						text: rendered
					})
				}
				.image_url {
					if rendered.trim_space() == '' || rendered.len > max_image_url_bytes {
						return error('multimodal image URL parts must contain 1..8192 bytes')
					}
					parts << schema.ContentPart(schema.ImageURLPart{
						url: rendered
					})
				}
			}
		}
		messages << schema.Message{
			role:  message.role
			parts: parts
		}
	}
	return messages
}
