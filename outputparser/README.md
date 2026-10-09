# Output parsers

`ulises_jeremias.langchainv.outputparser` converts generated text into values
from `json2.Any`. The package currently provides `Simple`, `BooleanParser`,
`CommaSeparatedList`, `RegexParser`, `RegexDict`, `Structured`, and `Combining`.

```v
import ulises_jeremias.langchainv.outputparser

pattern := 'Question: (?P<question>.*)' + '\n' + 'Answer: (?P<answer>.*)'
parser := outputparser.new_regex_parser(pattern)!
parsed := parser.parse('Question: why?\nAnswer: because')!
println(parsed)
```

`RegexParser` returns the first match's capture groups in a string map. Named
groups become map keys; unnamed groups use the empty key, following
LangChainGo's behavior. `RegexDict` accepts output-key to regular-expression
fragment mappings, uses the first matching value for each fragment, and omits
values equal to its configured `no_update_value`. It searches each input line
separately. As in LangChainGo, each format must add exactly one capture group
to the parser's value capture.

Patterns use V's `regex` module. Its syntax and behavior are not a drop-in
replacement for Go's `regexp` package, so Go-specific expressions must be
checked against V's regex documentation. Constructors validate patterns and
return errors rather than deferring invalid-pattern failures to parsing.

`Structured` reads the first fenced `json` block, decodes string-valued fields,
and verifies all configured response schema names are present. Generic
`Defined[T]` uses V's compile-time field walk to create an interface-like
schema and decodes fenced JSON into the concrete struct type. It currently
supports strings, booleans, numeric fields, their optional forms, slices and
string-keyed maps of those primitives, enums, and nested structs. Unsupported
V field types (including fixed arrays and containers of nested structs) return
an error. V field attributes
`@[json: fieldName]` and `@[describe: "..."]` supply JSON names and prompt
descriptions.

`Combining` splits on two consecutive newlines, applies one parser per
section, and merges only string-valued maps. See the
[parity ledger](../docs/LANGCHAINGO_PARITY.md) for remaining gaps.
