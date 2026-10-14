module prompts

import json2
import ulises_jeremias.langchainv.schema

fn test_multimodal_prompt_renders_text_and_image_parts() {
	prompt := MultimodalPromptTemplate{
		messages: [
			MultimodalMessageTemplate{
				role:  .human
				parts: [
					PartTemplate{
						kind:     .text
						template: StringTemplate{
							template: 'Describe {subject} in this image.'
						}
					},
					PartTemplate{
						kind:     .image_url
						template: StringTemplate{
							template: '{image_url}'
						}
					},
				]
			},
		]
	}
	assert prompt.input_variables() or { panic(err) } == ['subject', 'image_url']
	messages := prompt.format_messages({
		'subject':   json2.Any('a lighthouse')
		'image_url': json2.Any('https://images.test/lighthouse.png')
	}) or { panic(err) }
	assert messages.len == 1
	assert messages[0].parts.len == 2
	text := messages[0].parts[0]
	if text is schema.TextPart {
		assert text.text == 'Describe a lighthouse in this image.'
	} else {
		assert false, 'expected a text part'
	}
	image := messages[0].parts[1]
	if image is schema.ImageURLPart {
		assert image.url == 'https://images.test/lighthouse.png'
	} else {
		assert false, 'expected an image URL part'
	}
}

fn test_multimodal_prompt_rejects_empty_parts_and_urls() {
	prompt := MultimodalPromptTemplate{
		messages: [
			MultimodalMessageTemplate{
				role: .human
			},
		]
	}
	prompt.format_messages({}) or {
		assert err.msg().contains('at least one part')
		bad_url := MultimodalPromptTemplate{
			messages: [
				MultimodalMessageTemplate{
					role:  .human
					parts: [
						PartTemplate{
							kind:     .image_url
							template: StringTemplate{
								template: '{image_url}'
							}
						},
					]
				},
			]
		}
		bad_url.format_messages({
			'image_url': json2.Any('')
		}) or {
			assert err.msg().contains('image URL')
			return
		}
		assert false, 'expected an empty image URL to fail'
	}
	assert false, 'expected an empty part list to fail'
}
