module chains

import context
import db
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.tools.sqldatabase

struct SQLScriptState {
mut:
	prompts []string
}

struct SQLScriptModel {
	state &SQLScriptState
}

fn (model SQLScriptModel) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	options.validate()!
	mut state := model.state
	state.prompts << prompt
	if prompt.contains('SQL result:') {
		return 'Ada and Grace'
	}
	if prompt.contains('fenced') {
		return '```sql\nSELECT name FROM people ORDER BY id\n```'
	}
	if prompt.contains('delete everyone') {
		return 'DELETE FROM people'
	}
	return 'SELECT name FROM people ORDER BY id'
}

fn new_sql_chain_database() sqldatabase.SQLDatabase {
	driver := db.open(db.DriverConfig{
		kind: .sqlite
		path: ':memory:'
	}) or { panic(err) }
	driver.exec('CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT NOT NULL)') or { panic(err) }
	driver.exec("INSERT INTO people (name) VALUES ('Ada'), ('Grace')") or { panic(err) }
	engine := sqldatabase.new_driver_engine(driver, 'sqlite3') or { panic(err) }
	database := sqldatabase.new_database(engine, [], sqldatabase.Options{
		sample_rows: 0
	}) or { panic(err) }
	return database
}

fn test_sql_database_chain_generates_queries_and_answers() {
	mut database := new_sql_chain_database()
	defer {
		database.close() or {}
	}
	mut state := &SQLScriptState{}
	mut chain := new_sql_database_chain(database, SQLScriptModel{
		state: state
	}, SQLDatabaseChainOptions{
		return_intermediate_steps: true
	}) or { panic(err) }
	mut ctx := context.background()
	outputs := chain.call(mut ctx, {
		'question': json2.Any('Who is in people?')
	}) or { panic(err) }
	assert outputs['result'] or { panic('missing result') }.str() == 'Ada and Grace'
	steps := outputs['intermediate_steps'] or { panic('missing steps') }
	assert steps.str().contains('SELECT name FROM people')
	assert steps.str().contains('Ada')
	assert state.prompts.len == 2
	assert state.prompts[0].contains('CREATE TABLE people')
	assert chain.input_keys() == ['question']
	assert chain.output_keys() == ['result', 'intermediate_steps']
}

fn test_sql_database_chain_accepts_fenced_sql() {
	mut database := new_sql_chain_database()
	defer {
		database.close() or {}
	}
	mut state := &SQLScriptState{}
	mut chain := new_sql_database_chain(database, SQLScriptModel{
		state: state
	}, SQLDatabaseChainOptions{}) or { panic(err) }
	mut ctx := context.background()
	outputs := chain.call(mut ctx, {
		'question': json2.Any('fenced please')
	}) or { panic(err) }
	assert outputs['result'] or { panic('missing result') }.str() == 'Ada and Grace'
}

fn test_sql_database_chain_rejects_non_read_only_sql_without_executing() {
	mut database := new_sql_chain_database()
	defer {
		database.close() or {}
	}
	mut state := &SQLScriptState{}
	mut chain := new_sql_database_chain(database, SQLScriptModel{
		state: state
	}, SQLDatabaseChainOptions{}) or { panic(err) }
	mut ctx := context.background()
	chain.call(mut ctx, {
		'question': json2.Any('delete everyone')
	}) or {
		assert err.msg().contains('read-only')
		rows := database.query(mut ctx, 'SELECT COUNT(*) FROM people') or { panic(err) }
		assert rows.contains('2')
		return
	}
	assert false, 'expected non read-only SQL to fail'
}

fn test_sql_database_chain_validates_question_and_keys() {
	mut database := new_sql_chain_database()
	defer {
		database.close() or {}
	}
	mut state := &SQLScriptState{}
	new_sql_database_chain(database, SQLScriptModel{
		state: state
	}, SQLDatabaseChainOptions{
		question_key: 'result'
		output_key:   'result'
	}) or {
		assert err.msg().contains('distinct')
		return
	}
	assert false, 'expected duplicate keys to fail'
}
