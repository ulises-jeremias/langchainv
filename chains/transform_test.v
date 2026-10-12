module chains

import context
import json2

fn double_transform(mut _ctx context.Context, inputs map[string]json2.Any) !map[string]json2.Any {
	value := inputs['value'] or { return error('missing value') }
	return {
		'double': json2.Any(value.int() * 2)
	}
}

fn empty_transform(mut _ctx context.Context, _inputs map[string]json2.Any) !map[string]json2.Any {
	return map[string]json2.Any{}
}

fn test_transform_chain_adapts_function_to_chain_contract() {
	mut chain := new_transform_chain(double_transform, ['value'], ['double']) or { panic(err) }
	mut ctx := context.background()
	mut inputs := map[string]json2.Any{}
	inputs['value'] = json2.Any(21)
	outputs := call(mut ctx, chain, inputs) or { panic(err) }
	assert (outputs['double'] or { panic('missing double') }).int() == 42
	assert chain.input_keys() == ['value']
	assert chain.output_keys() == ['double']
}

fn test_transform_chain_rejects_duplicate_keys() {
	new_transform_chain(double_transform, ['value', 'value'], ['double']) or {
		assert err.msg().contains('unique')
		return
	}
	assert false, 'expected duplicate input key to fail'
}

fn test_transform_chain_rejects_missing_declared_outputs() {
	mut chain := new_transform_chain(empty_transform, ['value'], ['result']) or { panic(err) }
	mut ctx := context.background()
	chain.call(mut ctx, map[string]json2.Any{}) or {
		assert err.msg().contains('did not produce declared output')
		return
	}
	assert false, 'expected missing declared output to fail'
}
