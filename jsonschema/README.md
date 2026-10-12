# JSON Schema definitions

`Definition` represents the schema subset used to describe tool parameters:
one JSON type or a list of accepted types, descriptions, string enums, object
properties and required names, array item definitions, inclusive and exclusive
numeric bounds, string minLength/maxLength, array minItems/maxItems, and the
boolean form of `additionalProperties`. `to_any()` produces a validated `json2.Any` tree, and
`encode()` serializes it. Empty `properties` maps are emitted as `{}` to match
the upstream Definition shape.

Definition validation rejects misplaced type-specific fields, invalid or
inverted constraint ranges, duplicate enum/required values, missing required
property definitions, and empty names. `validate_instance(json2.Any)` checks
the supported definition subset recursively and includes the failing instance
path in errors. It covers type checks, string enums, object properties and
required names, the boolean form of `additionalProperties`, array items,
inclusive/exclusive numeric bounds, string minLength/maxLength, and array
minItems/maxItems.
Instances are capped at 10,000 nodes, 1 MiB of aggregate scalar/key bytes, and
64 levels of nesting before schema evaluation.

References, formats, schema-valued `additionalProperties`, and schema
composition (`allOf`, `anyOf`, `oneOf`, and `not`) remain unsupported. Pass a
raw schema to a tool when those features are needed.
