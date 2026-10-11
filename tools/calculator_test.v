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
