module sqldatabase

import context
import db

fn new_seeded_test_engine() !DriverEngine {
	driver := db.open(db.DriverConfig{
		kind: .sqlite
		path: ':memory:'
	})!
	driver.exec('CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT NOT NULL)')!
	driver.exec("INSERT INTO people (name) VALUES ('Ada'), ('Grace')")!
	driver.exec('CREATE TABLE ignored_table (id INTEGER)')!
	return new_driver_engine(driver, 'sqlite3')
}

fn new_test_database(options Options) !SQLDatabase {
	engine := new_seeded_test_engine()!
	return new_database(engine, [], options)
}

fn test_sql_database_queries_and_lists_tables() {
	mut database := new_test_database(Options{}) or { panic(err) }
	mut ctx := context.background()
	assert database.dialect() == 'sqlite3'
	assert database.table_names() == ['ignored_table', 'people']
	query_result := database.query(mut ctx, 'SELECT id, name FROM people ORDER BY id') or {
		panic(err)
	}
	assert query_result.starts_with('id\tname\n')
	assert query_result.contains('1\tAda\n')
	assert query_result.contains('2\tGrace\n')
	parameterized := database.query_with_params(mut ctx, 'SELECT name FROM people WHERE id = ?',
		['2']) or { panic(err) }
	assert parameterized.contains('Grace')
	database.close() or { panic(err) }
}

fn test_sql_database_filters_tables_and_includes_bounded_schema_samples() {
	engine := new_seeded_test_engine() or { panic(err) }
	mut database := new_database(engine, ['ignored_table'], Options{
		sample_rows: 1
	}) or { panic(err) }
	mut ctx := context.background()
	assert database.table_names() == ['people']
	info := database.table_info(mut ctx, []) or { panic(err) }
	assert info.contains('CREATE TABLE people')
	assert info.contains('Ada')
	assert !info.contains('ignored_table')
	database.close() or { panic(err) }
}

fn test_sql_database_rejects_unknown_tables_oversized_results_and_bad_options() {
	mut database := new_test_database(Options{
		max_result_rows: 1
	}) or { panic(err) }
	mut ctx := context.background()
	unknown_table_error := database.table_info(mut ctx, ['missing']) or { err.msg() }
	assert unknown_table_error.contains('table not found')
	result_limit_error := database.query(mut ctx, 'SELECT id FROM people ORDER BY id') or { err.msg() }
	assert result_limit_error.contains('row limit')
	database.close() or { panic(err) }
}

fn test_sql_database_caps_table_inventory_before_materializing_catalog() {
	engine := new_seeded_test_engine() or { panic(err) }
	new_database(engine, [], Options{
		max_tables: 1
	}) or {
		assert err.msg().contains('table count exceeds')
		return
	}
	assert false, 'expected the bounded catalog query to reject too many tables'
}

fn test_sql_database_closes_idempotently_and_rejects_use_after_close() {
	mut database := new_test_database(Options{}) or { panic(err) }
	database.close() or { panic(err) }
	database.close() or { panic(err) }
	mut ctx := context.background()
	database.query(mut ctx, 'SELECT 1') or {
		assert err.msg().contains('closed')
		return
	}
	assert false, 'expected a closed SQL database to reject queries'
}
