# JSON Schema definitions

`Definition` represents the small schema subset used to describe tool
parameters: the JSON primitive/container types, descriptions, string enums,
object properties and required names, and array item definitions. `to_any()`
produces a validated `json2.Any` tree, and `encode()` serializes it. Empty
`properties` maps are emitted as `{}` to match the upstream Definition shape.

Validation rejects misplaced `properties`, `required`, or `items` fields,
duplicate enum/required values, missing required property definitions, and
empty names. This package does not validate JSON instances or cover advanced
keywords such as numeric constraints, unions, references, formats,
`additionalProperties`, or composition. Pass a raw `json2.Any` schema to a tool
when those features are needed.
