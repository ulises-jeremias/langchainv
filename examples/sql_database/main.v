module main

import context
import db
import ulises_jeremias.langchainv.tools.sqldatabase

fn main() {
	driver := db.open(db.DriverConfig{
		kind: .sqlite
		path: ':memory:'
	}) or { panic(err) }
	driver.exec('CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT NOT NULL)') or {
		panic(err)
	}
	driver.exec("INSERT INTO customers (name) VALUES ('Ada'), ('Grace')") or { panic(err) }
	driver.exec('CREATE TABLE internal_notes (id INTEGER PRIMARY KEY, note TEXT)') or {
		panic(err)
	}

	engine := sqldatabase.new_driver_engine(driver, 'sqlite3') or { panic(err) }
	mut database := sqldatabase.new_database(engine, ['internal_notes'], sqldatabase.Options{}) or {
		panic(err)
	}
	defer {
		database.close() or { panic(err) }
	}

	mut ctx := context.background()
	println('Visible tables: ${database.table_names()}')
	println(database.table_info(mut ctx, ['customers']) or { panic(err) })
	query := 'SELECT name FROM customers WHERE id = ?'
	params := ['1']
	query_result := database.query_with_params(mut ctx, query, params) or { panic(err) }
	println(query_result)
}
