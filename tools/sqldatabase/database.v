// Package sqldatabase provides database inspection and query helpers.
module sqldatabase

import context
import db
import sync

const default_max_result_rows = 256
const max_result_rows_limit = 4096
const default_max_output_bytes = 65536
const max_output_bytes_limit = 1048576
const default_max_query_bytes = 65536
const max_query_bytes_limit = 1048576
const max_tables_limit = 4096
const max_table_name_bytes = 256

// ErrUnknownDialect reports an unsupported database dialect.
pub const err_unknown_dialect = 'unknown SQL database dialect'

// ErrTableNotFound reports a table name not exposed by the database.
pub const err_table_not_found = 'SQL database table not found'

// ErrInvalidResult reports malformed driver output.
pub const err_invalid_result = 'SQL database returned an invalid result'

// QueryResult contains column names and stringified database rows.
pub struct QueryResult {
pub:
	columns []string
	rows    [][]string
}

// Engine abstracts the SQL driver operations required by SQLDatabase.
pub interface Engine {
	dialect() string
	query(mut ctx context.Context, statement string) !QueryResult
	query_params(mut ctx context.Context, statement string, params []string) !QueryResult
	// Return at most max_tables + 1 names so the caller can detect overflow.
	table_names(mut ctx context.Context, max_tables int) ![]string
	table_info(mut ctx context.Context, table string) !string
	close() !
}

// Options bounds result formatting, query input, table inventory, and samples.
pub struct Options {
pub:
	sample_rows      int = 3
	max_result_rows  int = default_max_result_rows
	max_output_bytes int = default_max_output_bytes
	max_query_bytes  int = default_max_query_bytes
	max_tables       int = 256
}

// SQLDatabase wraps an Engine and presents visible schema plus query output.
pub struct SQLDatabase {
	state &SQLDatabaseState
}

@[heap]
struct SQLDatabaseState {
mut:
	mutex   sync.Mutex
	engine  Engine
	dialect string
	tables  []string
	options Options
	closed  bool
}

// DriverEngine adapts V's common db.Driver interface to Engine.
pub struct DriverEngine {
	state &DriverEngineState
}

@[heap]
struct DriverEngineState {
mut:
	mutex   sync.Mutex
	driver  &db.Driver
	dialect string
	closed  bool
}

// new_driver_engine wraps an already-open V database driver.
pub fn new_driver_engine(driver &db.Driver, dialect string) !DriverEngine {
	if dialect !in ['sqlite3', 'sqlite', 'mysql', 'pgx', 'postgresql'] {
		return error(err_unknown_dialect)
	}
	return DriverEngine{
		state: &DriverEngineState{
			driver:  driver
			dialect: dialect
		}
	}
}

// dialect returns the normalized SQL dialect name.
pub fn (engine DriverEngine) dialect() string {
	return engine.state.dialect
}

// query runs one SQL statement and normalizes the driver rows.
pub fn (engine DriverEngine) query(mut ctx context.Context, statement string) !QueryResult {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	mut state := engine.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if state.closed {
		return error('SQL database engine is closed')
	}
	rows := state.driver.exec(statement) or { return error('SQL database query failed') }
	mut result := QueryResult{}
	if rows.len > 0 {
		result = QueryResult{
			columns: rows[0].names.clone()
			rows:    rows.map(it.vals.clone())
		}
	}
	ctx_error_after_query := ctx.err()
	if ctx_error_after_query !is none {
		return ctx_error_after_query
	}
	return result
}

// query_params executes a parameterized SQL statement using string parameters.
pub fn (engine DriverEngine) query_params(mut ctx context.Context, statement string, params []string) !QueryResult {
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	mut state := engine.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if state.closed {
		return error('SQL database engine is closed')
	}
	rows := state.driver.exec_param_many(statement, params) or {
		return error('SQL database parameterized query failed')
	}
	mut result := QueryResult{}
	if rows.len > 0 {
		result = QueryResult{
			columns: rows[0].names.clone()
			rows:    rows.map(it.vals.clone())
		}
	}
	ctx_error_after_query := ctx.err()
	if ctx_error_after_query !is none {
		return ctx_error_after_query
	}
	return result
}

// table_names lists visible base tables for the selected SQL dialect.
pub fn (engine DriverEngine) table_names(mut ctx context.Context, max_tables int) ![]string {
	if max_tables <= 0 || max_tables > max_tables_limit {
		return error('SQL table inventory limit must be between 1 and ${max_tables_limit}')
	}
	query_limit := max_tables + 1
	statement := match engine.state.dialect {
		'sqlite', 'sqlite3' {
			"SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name LIMIT ${query_limit}"
		}
		'pgx', 'postgresql' {
			"SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name LIMIT ${query_limit}"
		}
		'mysql' {
			'SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE() ORDER BY table_name LIMIT ${query_limit}'
		}
		else { return error(err_unknown_dialect) }
	}
	result := engine.query(mut ctx, statement)!
	mut names := []string{cap: result.rows.len}
	for row in result.rows {
		if row.len == 0 {
			return error(err_invalid_result)
		}
		names << row[0]
	}
	return names
}

// table_info returns a dialect-specific schema description for a table.
pub fn (engine DriverEngine) table_info(mut ctx context.Context, table string) !string {
	validate_table_name(table)!
	mut state := engine.state
	if state.dialect == 'mysql' {
		identifier := quote_identifier(state.dialect, table)!
		result := engine.query(mut ctx, 'SHOW CREATE TABLE ${identifier}')!
		if result.rows.len == 0 || result.rows[0].len < 2 {
			return error(err_table_not_found)
		}
		return result.rows[0][1]
	}
	statement, parameter := match state.dialect {
		'sqlite', 'sqlite3' {
			('SELECT sql FROM sqlite_master WHERE type = ? AND name = ?'), 'table'
		}
		'pgx', 'postgresql' {
			("SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1 ORDER BY ordinal_position"), ''
		}
		else { return error(err_unknown_dialect) }
	}
	mut result := QueryResult{}
	if state.dialect in ['sqlite', 'sqlite3'] {
		ctx_error := ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
		state.mutex.lock()
		defer {
			state.mutex.unlock()
		}
		if state.closed {
			return error('SQL database engine is closed')
		}
		rows := state.driver.exec_param_many(statement, [parameter, table]) or {
			return error('SQL database schema lookup failed')
		}
		if rows.len > 0 {
			result = QueryResult{
				columns: rows[0].names.clone()
				rows:    rows.map(it.vals.clone())
			}
		}
	} else {
		result = engine.query_params(mut ctx, statement, [table])!
	}
	if result.rows.len == 0 || result.rows[0].len == 0 {
		return error(err_table_not_found)
	}
	if state.dialect in ['sqlite', 'sqlite3'] {
		return result.rows[0][0]
	}
	if result.rows.len > 512 {
		return error('SQL table schema exceeds the 512-column limit')
	}
	mut lines := ['table ${table}']
	for row in result.rows {
		if row.len < 2 {
			return error(err_invalid_result)
		}
		nullable := if row.len > 2 { row[2] } else { 'unknown' }
		lines << '${row[0]} ${row[1]} nullable=${nullable}'
	}
	return lines.join('\n')
}

// close closes the wrapped driver once. Repeated calls are safe.
pub fn (engine DriverEngine) close() ! {
	mut state := engine.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if !state.closed {
		state.driver.close() or { return error('could not close SQL database engine') }
		state.closed = true
	}
}

// new_database filters ignored tables and validates database operation bounds.
pub fn new_database(engine Engine, ignored_tables []string, options Options) !SQLDatabase {
	configured := normalized_options(options) or {
		engine.close() or {}
		return err
	}
	mut ctx := context.background()
	table_names := engine.table_names(mut ctx, configured.max_tables) or {
		engine.close() or {}
		return error('could not list SQL database tables')
	}
	if table_names.len > configured.max_tables {
		engine.close() or {}
		return error('SQL database table count exceeds the configured limit')
	}
	mut ignored := map[string]bool{}
	for name in ignored_tables {
		ignored[name] = true
	}
	mut visible := []string{cap: table_names.len}
	mut unique := map[string]bool{}
	for table in table_names {
		validate_table_name(table) or {
			engine.close() or {}
			return error('SQL database returned an invalid table name')
		}
		if table in unique {
			engine.close() or {}
			return error('SQL database returned duplicate table names')
		}
		unique[table] = true
		if table !in ignored {
			visible << table
		}
	}
	return SQLDatabase{
		state: &SQLDatabaseState{
			engine:  engine
			dialect: engine.dialect()
			tables:  visible
			options: configured
		}
	}
}

// new_sql_database opens a database with V's standard database driver.
// PostgreSQL and MySQL require the corresponding V compile-time driver flags.
pub fn new_sql_database(config db.DriverConfig, ignored_tables []string, options Options) !SQLDatabase {
	if config.kind == .mssql {
		return error('SQL database adapter does not support MSSQL')
	}
	driver := db.open(config) or { return error('could not open SQL database driver') }
	dialect := match config.kind {
		.sqlite { 'sqlite3' }
		.mysql { 'mysql' }
		.pg { 'pgx' }
		.mssql { return error('SQL database adapter does not support MSSQL') }
	}
	engine := new_driver_engine(driver, dialect) or {
		driver.close() or {}
		return err
	}
	return new_database(engine, ignored_tables, options)
}

// dialect returns the engine dialect.
pub fn (database SQLDatabase) dialect() string {
	return database.state.dialect
}

// table_names returns the filtered table inventory.
pub fn (database SQLDatabase) table_names() []string {
	mut state := database.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	return state.tables.clone()
}

// table_info returns schemas and a bounded sample of rows for requested tables.
// An empty table list selects every non-ignored table.
pub fn (database SQLDatabase) table_info(mut ctx context.Context, tables []string) !string {
	mut state := database.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if state.closed {
		return error('SQL database is closed')
	}
	selected := if tables.len == 0 { state.tables } else { tables }
	if selected.len > state.options.max_tables {
		return error('SQL table info request exceeds the configured table limit')
	}
	mut seen := map[string]bool{}
	mut output := ''
	for table in selected {
		if table !in state.tables {
			return error(err_table_not_found)
		}
		if table in seen {
			return error('SQL table info request contains duplicate tables')
		}
		seen[table] = true
		ctx_error := ctx.err()
		if ctx_error !is none {
			return ctx_error
		}
		schema_text := state.engine.table_info(mut ctx, table) or {
			return error('could not read SQL table schema')
		}
		output = append_bounded(output, schema_text + '\n\n', state.options.max_output_bytes)!
		if state.options.sample_rows > 0 {
			identifier := quote_identifier(state.dialect, table)!
			result := state.engine.query(mut ctx,
				'SELECT * FROM ${identifier} LIMIT ${state.options.sample_rows}') or {
				return error('could not read SQL table sample rows')
			}
			output = append_bounded(output, '/*\n${format_query_result(result, state.options)!}*/\n\n',
				state.options.max_output_bytes)!
		}
	}
	return output
}

// query runs SQL and returns tab-separated, bounded query results.
pub fn (database SQLDatabase) query(mut ctx context.Context, statement string) !string {
	mut state := database.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if state.closed {
		return error('SQL database is closed')
	}
	if statement.trim_space() == '' || statement.len > state.options.max_query_bytes {
		return error('SQL query must contain 1..${state.options.max_query_bytes} bytes')
	}
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	result := state.engine.query(mut ctx, statement) or { return err }
	output := format_query_result(result, state.options)!
	ctx_error_after_query := ctx.err()
	if ctx_error_after_query !is none {
		return ctx_error_after_query
	}
	return output
}

// query_with_params runs bounded parameterized SQL with string values.
pub fn (database SQLDatabase) query_with_params(mut ctx context.Context, statement string, params []string) !string {
	mut state := database.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if state.closed {
		return error('SQL database is closed')
	}
	if params.len > 100 {
		return error('SQL parameter count exceeds the 100-value limit')
	}
	mut input_bytes := statement.len
	for value in params {
		if value.len > state.options.max_query_bytes - input_bytes {
			return error('SQL query and parameters exceed the configured byte limit')
		}
		input_bytes += value.len
	}
	if statement.trim_space() == '' || input_bytes > state.options.max_query_bytes {
		return error('SQL query and parameters exceed configured limits')
	}
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	result := state.engine.query_params(mut ctx, statement, params) or { return err }
	output := format_query_result(result, state.options)!
	ctx_error_after_query := ctx.err()
	if ctx_error_after_query !is none {
		return ctx_error_after_query
	}
	return output
}

// close releases the database engine. Repeated calls are safe.
pub fn (database SQLDatabase) close() ! {
	mut state := database.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if !state.closed {
		state.engine.close() or { return err }
		state.closed = true
	}
}

fn normalized_options(options Options) !Options {
	configured := Options{
		sample_rows:      options.sample_rows
		max_result_rows:  if options.max_result_rows == 0 {
			default_max_result_rows
		} else {
			options.max_result_rows
		}
		max_output_bytes: if options.max_output_bytes == 0 {
			default_max_output_bytes
		} else {
			options.max_output_bytes
		}
		max_query_bytes:  if options.max_query_bytes == 0 {
			default_max_query_bytes
		} else {
			options.max_query_bytes
		}
		max_tables:       if options.max_tables == 0 {
			256
		} else {
			options.max_tables
		}
	}
	if configured.sample_rows < 0 || configured.sample_rows > 32 {
		return error('SQL sample row count must be between 0 and 32')
	}
	if configured.max_result_rows < 1 || configured.max_result_rows > max_result_rows_limit {
		return error('SQL result row limit must be between 1 and ${max_result_rows_limit}')
	}
	if configured.max_output_bytes < 128 || configured.max_output_bytes > max_output_bytes_limit {
		return error('SQL output byte limit must be between 128 and ${max_output_bytes_limit}')
	}
	if configured.max_query_bytes < 1 || configured.max_query_bytes > max_query_bytes_limit {
		return error('SQL query byte limit must be between 1 and ${max_query_bytes_limit}')
	}
	if configured.max_tables < 1 || configured.max_tables > max_tables_limit {
		return error('SQL table limit must be between 1 and ${max_tables_limit}')
	}
	return configured
}

fn format_query_result(result QueryResult, options Options) !string {
	if result.rows.len > options.max_result_rows {
		return error('SQL query result exceeds the ${options.max_result_rows}-row limit')
	}
	if result.columns.len > 256 {
		return error('SQL query result exceeds the 256-column limit')
	}
	mut output := result.columns.join('\t') + '\n'
	if output.len > options.max_output_bytes {
		return error('SQL query output exceeds the configured byte limit')
	}
	for row in result.rows {
		if row.len != result.columns.len {
			return error(err_invalid_result)
		}
		output = append_bounded(output, row.join('\t') + '\n', options.max_output_bytes)!
	}
	return output
}

fn append_bounded(output string, value string, max_bytes int) !string {
	if value.len > max_bytes - output.len {
		return error('SQL output exceeds the configured byte limit')
	}
	return output + value
}

fn validate_table_name(name string) ! {
	if name.trim_space() == '' || name.len > max_table_name_bytes || name.contains('\0') {
		return error('SQL table name must contain 1..${max_table_name_bytes} bytes and no NUL')
	}
}

fn quote_identifier(dialect string, identifier string) !string {
	validate_table_name(identifier)!
	if dialect == 'mysql' {
		escaped := identifier.replace('`', '``')
		return '`' + escaped + '`'
	}
	escaped := identifier.replace('"', '""')
	return '"' + escaped + '"'
}
