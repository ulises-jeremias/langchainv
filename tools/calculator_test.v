module tools

import context

fn test_calculator_evaluates_bounded_arithmetic() {
	mut calculator := new_calculator()
	mut ctx := context.background()
	assert calculator.call(mut ctx, '1 + 2 * 3') or { panic(err) } == '7'
	assert calculator.call(mut ctx, '(1 + 2) * 3') or { panic(err) } == '9'
	assert calculator.call(mut ctx, '2 ** 3 ** 2') or { panic(err) } == '512'
	assert calculator.call(mut ctx, '-2 ** 2') or { panic(err) } == '-4'
	assert calculator.call(mut ctx, '-7 % 3') or { panic(err) } == '2'
	assert calculator.call(mut ctx, '3.5 / 2') or { panic(err) } == '1.75'
	assert calculator.call(mut ctx, '{"expression":"6 * 7"}') or { panic(err) } == '42'
}

fn test_calculator_evaluates_starlark_math_functions_and_constants() {
	mut calculator := new_calculator()
	mut ctx := context.background()
	assert calculator.call(mut ctx, 'sqrt(81) + fabs(-2)') or { panic(err) } == '11'
	assert calculator.call(mut ctx, 'sin(pi / 2)') or { panic(err) } == '1'
	assert calculator.call(mut ctx, 'log(100, 10)') or { panic(err) } == '2'
	assert calculator.call(mut ctx, 'round(-1.5)') or { panic(err) } == '-2'
	assert calculator.call(mut ctx, 'floor(2.9) + ceil(2.1)') or { panic(err) } == '5'
	assert calculator.call(mut ctx, 'gamma(5)') or { panic(err) } == '24'
	assert calculator.call(mut ctx, 'pow(2, 3) + round(e)') or { panic(err) } == '11'
	assert calculator.call(mut ctx, 'hypot(x=3, y=4)') or { panic(err) } == '5'
	assert calculator.call(mut ctx, 'sqrt(16,)') or { panic(err) } == '4'
	assert calculator.call(mut ctx, 'log(x=100, base=10)') or { panic(err) } == '2'
	assert calculator.call(mut ctx, 'cosh(0) + sinh(0) + tanh(0) + atan2(0, 1)') or {
		panic(err)
	} == '1'
	assert calculator.call(mut ctx, 'remainder(5, 2) + degrees(pi) - 180') or { panic(err) } == '1'
	assert calculator.call(mut ctx, 'acos(1) + acosh(1) + asin(0) + asinh(0) + atan(0) + atanh(0) + cos(0)') or {
		panic(err)
	} == '1'
	assert calculator.call(mut ctx, 'copysign(-2, 3) + mod(-7, 3) + pow(2, 3) + hypot(3, 4)') or {
		panic(err)
	} == '14'
	assert calculator.call(mut ctx, 'tan(0) + sinh(0) + sin(0) + exp(0) + degrees(radians(180)) / 180') or {
		panic(err)
	} == '2'
	assert calculator.call(mut ctx, 'remainder(7, 2) + remainder(-7, 2)') or { panic(err) } == '0'
}

fn test_calculator_rejects_unknown_math_names_and_invalid_arity() {
	mut calculator := new_calculator()
	mut ctx := context.background()
	assert (calculator.call(mut ctx, 'unknown(2)') or { panic(err) }).contains('unknown math function')
	assert (calculator.call(mut ctx, 'sqrt(1, 2)') or { panic(err) }).contains('expects one argument')
	assert (calculator.call(mut ctx, 'hypot(3)') or { panic(err) }).contains('expects two arguments')
	assert (calculator.call(mut ctx, 'sqrt(-1)') or { panic(err) }).contains('not finite')
	assert (calculator.call(mut ctx, 'sqrt(x=4, 2)') or { panic(err) }).contains('positional argument follows')
	assert (calculator.call(mut ctx, 'sqrt(x=4, x=9)') or { panic(err) }).contains('duplicate argument')
	assert (calculator.call(mut ctx, 'sqrt(y=4)') or { panic(err) }).contains('unknown argument')
}

fn test_calculator_reports_invalid_and_non_finite_expressions() {
	mut calculator := new_calculator()
	mut ctx := context.background()
	assert (calculator.call(mut ctx, '1 / 0') or { panic(err) }).contains('division by zero')
	assert (calculator.call(mut ctx, '1 +') or { panic(err) }).contains('expected a number')
	assert (calculator.call(mut ctx, '2 ** 1024') or { panic(err) }).contains('not finite')
	assert (calculator.call(mut ctx, '{"other":"2 + 2"}') or { panic(err) }).contains('missing')
	assert (calculator.call(mut ctx, '{"expression":4}') or { panic(err) }).contains('must be a string')
}

fn test_calculator_enforces_input_and_operation_limits() {
	mut calculator := new_calculator()
	mut ctx := context.background()
	large_input := '1'.repeat(calculator_max_input_bytes + 1)
	assert (calculator.call(mut ctx, large_input) or { panic(err) }).contains('exceeds')
	too_many_operations := []string{len: calculator_max_operations + 1, init: '1'}.join('+')
	assert (calculator.call(mut ctx, too_many_operations) or { panic(err) }).contains('operation limit')
	deep_input := '('.repeat(calculator_max_nesting + 1) + '1' + ')'.repeat(calculator_max_nesting + 1)
	assert (calculator.call(mut ctx, deep_input) or { panic(err) }).contains('nesting limit')
}

fn test_calculator_tool_spec_names_expression_input() {
	spec := new_calculator().spec()
	assert spec.name == 'calculator'
	parameters := spec.parameters.as_map()
	required := parameters['required'] or { panic('missing required parameters') }
	assert required.as_array()[0].str() == 'expression'
	mut tool := Tool(new_calculator())
	mut ctx := context.background()
	assert tool.call(mut ctx, '2 + 2') or { panic(err) } == '4'
}
