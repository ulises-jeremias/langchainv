# JSON Schema definitions

`Definition` represents the schema subset used to describe tool parameters:
one JSON type or a list of accepted types, descriptions, string enums, object
properties and required names, array item definitions, inclusive and exclusive
numeric bounds, string minLength/maxLength, array minItems/maxItems, and the
boolean form of `additionalProperties`, a string `format` name, and schema
composition through `all_of`, `any_of`, `one_of`, and `not`. `to_any()`
produces a validated `json2.Any` tree, and `encode()` serializes it. Empty `properties` maps are emitted as `{}` to match
the upstream Definition shape.

Definition validation rejects misplaced type-specific fields, invalid or
inverted constraint ranges, duplicate enum/required values, missing required
property definitions, and empty names. `validate_instance(json2.Any)` checks
the supported definition subset recursively and includes the failing instance
path in errors. It covers type checks, string enums, object properties and
required names, the boolean form of `additionalProperties`, array items,
inclusive/exclusive numeric bounds, string minLength/maxLength, array
minItems/maxItems, and composition: every `allOf` member must match, at
least one `anyOf` member must match, exactly one `oneOf` member must match,
and a `not` member must not match. `format` is emitted as an annotation and
checked for placement on string definitions; instance validation does not
assert format semantics such as email or URI syntax.
Instances are capped at 10,000 nodes, 1 MiB of aggregate scalar/key bytes, and
64 levels of nesting before schema evaluation.

The upstream [LangChainGo `Definition` helper](https://github.com/tmc/langchaingo/blob/6351d0d03286ba1f8be78b572d88c9b43ed6b869/jsonschema/json.go)
does not model references, formats, schema-valued `additionalProperties`, or
schema composition, so those parts of this package are V-native extensions
beyond upstream. Local `#/$defs/` references (`ref` plus the `defs` map) and schema-valued
`additionalProperties` are part of the typed API and are enforced during
instance validation. External references remain outside it. Pass a raw schema to a tool when the
provider supports those features.
