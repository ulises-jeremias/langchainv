# Tools

`Tool` defines the shared agent-tool contract. `new_calculator()` returns an
offline calculator that supports numeric literals, parentheses, unary signs,
addition, subtraction, multiplication, division, modulo, and right-associative
exponentiation with `**`.

The calculator does not execute source code. It caps expressions at 4,096
bytes, 512 parsed values/operators, and 64 levels of nesting. Invalid
expressions are returned as `error from evaluator: ...` strings so an agent can
correct its input. Starlark built-in functions and constants are not included.
