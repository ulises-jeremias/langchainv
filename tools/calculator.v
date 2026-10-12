// Package tools provides a bounded math-expression calculator and integrations.
module tools

import context
import json2
import math
import strconv

const calculator_max_input_bytes = 4096
const calculator_max_operations = 512
const calculator_max_nesting = 64

// Calculator evaluates bounded arithmetic and Starlark math expressions without executing user code.
pub struct Calculator {}

// new_calculator creates a bounded math-expression calculator tool.
pub fn new_calculator() Calculator {
	return Calculator{}
}

// spec describes the expression accepted by this tool.
pub fn (calculator Calculator) spec() ToolSpec {
	mut expression_schema := map[string]json2.Any{}
	expression_schema['type'] = json2.Any('string')
	expression_schema['description'] = json2.Any('Bounded arithmetic expressions with Starlark math functions and constants.')
	mut properties := map[string]json2.Any{}
	properties['expression'] = json2.Any(expression_schema)
	mut parameters := map[string]json2.Any{}
	parameters['type'] = json2.Any('object')
	parameters['properties'] = json2.Any(properties)
	parameters['required'] = json2.Any([json2.Any('expression')])
	return ToolSpec{
		name:        'calculator'
		description: 'Evaluate a bounded arithmetic or math-function expression.'
		parameters:  json2.Any(parameters)
	}
}

// call evaluates an arithmetic expression. Invalid expressions return a
// readable result so an agent can revise its input, matching LangChainGo's tool behavior.
pub fn (calculator Calculator) call(mut ctx context.Context, input string) !string {
	if input.len > calculator_max_input_bytes {
		return 'error from evaluator: expression exceeds ${calculator_max_input_bytes} bytes'
	}
	expression := calculator_expression(input) or {
		return 'error from evaluator: ${err.msg()}'
	}
	mut parser := ArithmeticParser{
		source: expression
	}
	value := parser.parse() or {
		return 'error from evaluator: ${err.msg()}'
	}
	if !math.is_finite(value) {
		return 'error from evaluator: result is not finite'
	}
	if math.floor(value) == value && value >= -9007199254740991.0 && value <= 9007199254740991.0 {
		return i64(value).str()
	}
	return value.str()
}

fn calculator_expression(input string) !string {
	trimmed := input.trim_space()
	if !trimmed.starts_with('{') {
		return input
	}
	values := json2.decode[map[string]json2.Any](input) or {
		return error('invalid JSON tool input')
	}
	expression := values['expression'] or { return error('missing `expression` input') }
	if expression is string {
		return expression
	}
	return error('`expression` input must be a string')
}

struct ArithmeticParser {
	source string
mut:
	index      int
	operations int
}

fn (mut parser ArithmeticParser) parse() !f64 {
	value := parser.parse_sum(0) or { return err }
	parser.skip_spaces()
	if parser.index != parser.source.len {
		return error('unexpected character at byte ${parser.index}')
	}
	return value
}

fn (mut parser ArithmeticParser) parse_sum(depth int) !f64 {
	mut value := parser.parse_product(depth + 1) or { return err }
	for {
		parser.skip_spaces()
		if parser.consume(`+`) {
			parser.count_operation() or { return err }
			value += parser.parse_product(depth + 1) or { return err }
		} else if parser.consume(`-`) {
			parser.count_operation() or { return err }
			value -= parser.parse_product(depth + 1) or { return err }
		} else {
			break
		}
	}
	return value
}

fn (mut parser ArithmeticParser) parse_product(depth int) !f64 {
	mut value := parser.parse_unary(depth + 1) or { return err }
	for {
		parser.skip_spaces()
		if parser.index + 1 < parser.source.len && parser.source[parser.index] == `*`
			&& parser.source[parser.index + 1] == `*` {
			break
		} else if parser.consume(`*`) {
			parser.count_operation() or { return err }
			value *= parser.parse_unary(depth + 1) or { return err }
		} else if parser.consume(`/`) {
			parser.count_operation() or { return err }
			divisor := parser.parse_unary(depth + 1) or { return err }
			if divisor == 0 {
				return error('division by zero')
			}
			value /= divisor
		} else if parser.consume(`%`) {
			parser.count_operation() or { return err }
			divisor := parser.parse_unary(depth + 1) or { return err }
			if divisor == 0 {
				return error('modulo by zero')
			}
			value -= math.floor(value / divisor) * divisor
		} else {
			break
		}
	}
	return value
}

fn (mut parser ArithmeticParser) parse_unary(depth int) !f64 {
	parser.check_depth(depth) or { return err }
	parser.skip_spaces()
	if parser.consume(`+`) {
		return parser.parse_unary(depth + 1)
	}
	if parser.consume(`-`) {
		return -(parser.parse_unary(depth + 1) or { return err })
	}
	value := parser.parse_primary(depth + 1) or { return err }
	parser.skip_spaces()
	if parser.index + 1 < parser.source.len && parser.source[parser.index] == `*`
		&& parser.source[parser.index + 1] == `*` {
		parser.index += 2
		parser.count_operation() or { return err }
		exponent := parser.parse_unary(depth + 1) or { return err }
		return math.pow(value, exponent)
	}
	return value
}

fn (mut parser ArithmeticParser) parse_primary(depth int) !f64 {
	parser.check_depth(depth) or { return err }
	parser.skip_spaces()
	if parser.consume(`(`) {
		value := parser.parse_sum(depth + 1) or { return err }
		parser.skip_spaces()
		if !parser.consume(`)`) {
			return error('expected closing parenthesis')
		}
		return value
	}
	if parser.index < parser.source.len && (parser.source[parser.index].is_letter()
		|| parser.source[parser.index] == `_`) {
		return parser.parse_identifier(depth + 1)
	}
	start := parser.index
	mut has_digit := false
	for parser.index < parser.source.len && parser.source[parser.index].is_digit() {
		parser.index++
		has_digit = true
	}
	if parser.index < parser.source.len && parser.source[parser.index] == `.` {
		parser.index++
		for parser.index < parser.source.len && parser.source[parser.index].is_digit() {
			parser.index++
			has_digit = true
		}
	}
	if !has_digit {
		return error('expected a number, constant, or math function at byte ${parser.index}')
	}
	if parser.index < parser.source.len && (parser.source[parser.index] == `e`
		|| parser.source[parser.index] == `E`) {
		parser.index++
		if parser.index < parser.source.len && (parser.source[parser.index] == `+`
			|| parser.source[parser.index] == `-`) {
			parser.index++
		}
		exponent_start := parser.index
		for parser.index < parser.source.len && parser.source[parser.index].is_digit() {
			parser.index++
		}
		if parser.index == exponent_start {
			return error('expected exponent digits')
		}
	}
	parser.count_operation() or { return err }
	return strconv.atof64(parser.source[start..parser.index]) or {
		return error('invalid number')
	}
}

fn (mut parser ArithmeticParser) parse_identifier(depth int) !f64 {
	start := parser.index
	for parser.index < parser.source.len
		&& (parser.source[parser.index].is_letter() || parser.source[parser.index].is_digit()
			|| parser.source[parser.index] == `_`) {
		parser.index++
	}
	name := parser.source[start..parser.index]
	parser.skip_spaces()
	if name == 'pi' && (parser.index >= parser.source.len || parser.source[parser.index] != `(`) {
		return math.pi
	}
	if name == 'e' && (parser.index >= parser.source.len || parser.source[parser.index] != `(`) {
		return math.exp(1.0)
	}
	if parser.index >= parser.source.len || parser.source[parser.index] != `(` {
		return error('unknown math constant `${name}`')
	}
	parser.index++
	parser.skip_spaces()
	mut positional := []f64{}
	mut keywords := map[string]f64{}
	mut saw_keyword := false
	if !parser.consume(`)`) {
		for {
			parser.skip_spaces()
			argument_start := parser.index
			if parser.index < parser.source.len
				&& (parser.source[parser.index].is_letter() || parser.source[parser.index] == `_`) {
				for parser.index < parser.source.len
					&& (parser.source[parser.index].is_letter() || parser.source[parser.index].is_digit()
						|| parser.source[parser.index] == `_`) {
					parser.index++
				}
				argument_name := parser.source[argument_start..parser.index]
				parser.skip_spaces()
				if parser.consume(`=`) {
					saw_keyword = true
					if argument_name in keywords {
						return error('duplicate argument `${argument_name}` for math function `${name}`')
					}
					keywords[argument_name] = parser.parse_sum(depth + 1) or { return err }
				} else {
					parser.index = argument_start
					if saw_keyword {
						return error('positional argument follows keyword argument in `${name}`')
					}
					positional << parser.parse_sum(depth + 1) or { return err }
				}
			} else {
				if saw_keyword {
					return error('positional argument follows keyword argument in `${name}`')
				}
				positional << parser.parse_sum(depth + 1) or { return err }
			}
			parser.skip_spaces()
			if parser.consume(`)`) {
				break
			}
			if !parser.consume(`,`) {
				return error('expected comma or closing parenthesis in `${name}`')
			}
			parser.skip_spaces()
			if parser.consume(`)`) {
				break
			}
		}
	}
	parser.count_operation() or { return err }
	return evaluate_math_function(name, positional, keywords)
}

fn evaluate_math_function(name string, positional []f64, keywords map[string]f64) !f64 {
	if name !in ['acos', 'acosh', 'asin', 'asinh', 'atan', 'atan2', 'atanh', 'ceil', 'copysign',
		'cos', 'cosh', 'degrees', 'exp', 'fabs', 'floor', 'gamma', 'hypot', 'log', 'mod', 'pow',
		'radians', 'remainder', 'round', 'sin', 'sinh', 'sqrt', 'tan', 'tanh'] {
		return error('unknown math function `${name}`')
	}
	is_binary := name in ['atan2', 'copysign', 'hypot', 'mod', 'pow', 'remainder']
	allowed_keywords := if name == 'log' {
		['x', 'base']
	} else if is_binary {
		['x', 'y']
	} else {
		['x']
	}
	for argument_name, _ in keywords {
		if argument_name !in allowed_keywords {
			return error('unknown argument `${argument_name}` for math function `${name}`')
		}
	}
	max_positional := if is_binary || name == 'log' { 2 } else { 1 }
	expected_arguments := if is_binary {
		'two'
	} else if name == 'log' {
		'one or two'
	} else {
		'one'
	}
	if positional.len > max_positional {
		return error('math function `${name}` expects ${expected_arguments} arguments')
	}
	mut resolved := map[string]f64{}
	if positional.len > 0 {
		resolved['x'] = positional[0]
	}
	if positional.len > 1 {
		if name == 'log' {
			resolved['base'] = positional[1]
		} else {
			resolved['y'] = positional[1]
		}
	}
	for argument_name, value in keywords {
		if argument_name in resolved {
			return error('multiple values for argument `${argument_name}` in math function `${name}`')
		}
		resolved[argument_name] = value
	}
	if 'x' !in resolved {
		return error('math function `${name}` expects at least one argument')
	}
	x := resolved['x']
	mut y := 0.0
	if is_binary {
		if 'y' !in resolved {
			return error('math function `${name}` expects two arguments')
		}
		y = resolved['y']
	}
	return match name {
		'acos' { math.acos(x) }
		'acosh' { math.acosh(x) }
		'asin' { math.asin(x) }
		'asinh' { math.asinh(x) }
		'atan' { math.atan(x) }
		'atan2' { math.atan2(x, y) }
		'atanh' { math.atanh(x) }
		'ceil' { math.ceil(x) }
		'copysign' { math.copysign(x, y) }
		'cos' { math.cos(x) }
		'cosh' { math.cosh(x) }
		'degrees' { math.degrees(x) }
		'exp' { math.exp(x) }
		'fabs' {
			if x < 0 { -x } else { x }
		}
		'floor' { math.floor(x) }
		'gamma' { math.gamma(x) }
		'hypot' { math.hypot(x, y) }
		'log' {
			base := if 'base' in resolved { resolved['base'] } else { math.exp(1.0) }
			if base == 1 {
				return error('division by zero')
			}
			math.log(x) / math.log(base)
		}
		'mod' { math.mod(x, y) }
		'pow' { math.pow(x, y) }
		'radians' { math.radians(x) }
		'remainder' { starlark_remainder(x, y) }
		'round' {
			if x < 0 { math.ceil(x - 0.5) } else { math.floor(x + 0.5) }
		}
		'sin' { math.sin(x) }
		'sinh' { math.sinh(x) }
		'sqrt' { math.sqrt(x) }
		'tan' { math.tan(x) }
		'tanh' { math.tanh(x) }
		else { return error('unknown math function `${name}`') }
	}
}

fn starlark_remainder(x f64, y f64) f64 {
	mut remainder := math.mod(x, y)
	if remainder == 0 {
		return remainder
	}
	ratio := x / y
	if !math.is_finite(ratio) {
		return remainder
	}
	integer_quotient, fractional_quotient := math.modf(ratio)
	abs_fraction := if fractional_quotient < 0 { -fractional_quotient } else { fractional_quotient }
	quotient_is_odd := math.mod(if integer_quotient < 0 {
		-integer_quotient
	} else {
		integer_quotient
	},
		2.0) != 0
	if abs_fraction > 0.5 || (abs_fraction == 0.5 && quotient_is_odd) {
		remainder -= math.copysign(if y < 0 { -y } else { y }, x)
	}
	return remainder
}

fn (mut parser ArithmeticParser) skip_spaces() {
	for parser.index < parser.source.len && parser.source[parser.index].is_space() {
		parser.index++
	}
}

fn (mut parser ArithmeticParser) consume(expected u8) bool {
	if parser.index < parser.source.len && parser.source[parser.index] == expected {
		parser.index++
		return true
	}
	return false
}

fn (mut parser ArithmeticParser) check_depth(depth int) ! {
	if depth > calculator_max_nesting {
		return error('expression exceeds nesting limit')
	}
}

fn (mut parser ArithmeticParser) count_operation() ! {
	parser.operations++
	if parser.operations > calculator_max_operations {
		return error('expression exceeds operation limit')
	}
}
