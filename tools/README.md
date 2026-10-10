# Tools

`Tool` defines the shared agent-tool contract. `new_calculator()` returns an
offline calculator that supports numeric literals, parentheses, unary signs,
addition, subtraction, multiplication, division, modulo, and right-associative
exponentiation with `**`. It accepts either an expression string or a JSON
object with a string-valued `expression` field.

The calculator does not execute source code. It caps expressions at 4,096
bytes, 512 parsed values/operators, and 64 levels of nesting. Invalid
expressions are returned as `error from evaluator: ...` strings so an agent can
correct its input. Starlark built-in functions and constants are not included.

`tools/perplexity` provides a search tool backed by Perplexity's
OpenAI-compatible Sonar API. Pass an explicit key and injectable `HTTPClient`
with `new_tool`, or use `new_default_tool` to read `PERPLEXITY_API_KEY` and
the bounded default transport. Queries are capped at 8 KiB; tests use only a
fake transport.
