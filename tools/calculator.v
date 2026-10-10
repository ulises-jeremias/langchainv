// Package tools provides a bounded arithmetic calculator.
module tools

import context
import json2
import math
import strconv

const calculator_max_input_bytes = 4096
const calculator_max_operations = 512
const calculator_max_nesting = 64

// Calculator evaluates arithmetic expressions without executing user code.
pub struct Calculator {}

// new_calculator creates an arithmetic calculator tool.
pub fn new_calculator() Calculator {
	return Calculator{}
}

// spec describes the expression accepted by this tool.
pub fn (calculator Calculator) spec() ToolSpec {
	mut expression_schema := map[string]json2.Any{}
	expression_schema['type'] = json2.Any('string')
	expression_schema['description'] = json2.Any('Arithmetic expression using numbers, parentheses, +, -, *, /, %, and **.')
	mut properties := map[string]json2.Any{}
	properties['expression'] = json2.Any(expression_schema)
	mut parameters := map[string]json2.Any{}
	parameters['type'] = json2.Any('object')
	parameters['properties'] = json2.Any(properties)
	parameters['required'] = json2.Any([json2.Any('expression')])
	return ToolSpec{
		name:        'calculator'
		description: 'Evaluate a bounded arithmetic expression.'
		parameters:  json2.Any(parameters)
	}
}

// call evaluates an arithmetic expression. Invalid expressions return a
// readable result so an agent can revise its input, matching LangChainGo's tool behavior.
pub fn (calculator Calculator) call(mut ctx context.Context, input string) !string {
	if input.len > calculator_max_input_bytes {
		return 'error from evaluator: expression exceeds ${calculator_max_input_bytes} bytes'
	}
	mut parser := ArithmeticParser{
		source: input
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
		return error('expected a number at byte ${parser.index}')
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
