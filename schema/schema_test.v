module schema

fn test_text_message_keeps_role_and_text() {
	message := text_message(.human, 'hello')
	assert message.role == .human
	assert message.text() == 'hello'
}

fn test_message_text_joins_textual_parts_only() {
	message := Message{
		role:  .ai
		parts: [
			ContentPart(TextPart{
				text: 'answer'
			}),
			ContentPart(ImageURLPart{
				url: 'https://example.test/image.png'
			}),
			ContentPart(ThinkingPart{
				text: 'reasoning'
			}),
		]
	}
	assert message.text() == 'answerreasoning'
}

fn test_new_document_initializes_metadata() {
	doc := new_document('page')
	assert doc.page_content == 'page'
	assert doc.metadata.len == 0
}
