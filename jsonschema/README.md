# JSON Schema definitions

The `jsonschema` package provides the same lightweight schema model as
LangChainGo's `jsonschema.Definition`. It supports JSON Schema type names,
descriptions, string enums, object properties, required property names, and
array item definitions.

```v
import ulises_jeremias.langchainv.jsonschema
import json2

parameters := jsonschema.Definition{
	schema_type: jsonschema.object_type
	properties: {
		'query': jsonschema.Definition{
			schema_type: jsonschema.string_type
			description: 'Search query'
		}
	}
	required: ['query']
}

// Embed as a JSON value in a provider's tool definition.
tool_parameters := parameters.to_any()
wire_json := json2.encode(tool_parameters, json2.EncoderOptions{})
```

`json2.encode(definition, ...)` also works directly. The encoder always emits
`properties`, including as `{}` on empty or nested definitions, to preserve
LangChainGo's JSON wire shape. Optional fields with empty values are omitted.
This is a small data model, not a full JSON Schema validator.
