# JSON Schema definitions

`Definition` represents the schema subset used to describe tool parameters:
the JSON primitive/container types, descriptions, string enums, object
properties and required names, array item definitions, numeric minimum/maximum,
string minLength/maxLength, array minItems/maxItems, and the boolean form of
`additionalProperties`. `to_any()` produces a validated `json2.Any` tree, and
`encode()` serializes it. Empty `properties` maps are emitted as `{}` to match
the upstream Definition shape.

Validation rejects misplaced type-specific fields, invalid or inverted
constraint ranges, duplicate enum/required values, missing required property
definitions, and empty names. This package does not validate JSON instances or
cover unions, references, formats, schema-valued `additionalProperties`, or
composition. Pass a raw `json2.Any` schema to a tool when those features are
needed.
