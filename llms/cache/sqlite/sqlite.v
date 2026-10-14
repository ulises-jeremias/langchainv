// Package sqlite provides a bounded, persistent SQLite response-cache backend.
module sqlite

import context
import db.sqlite
import json2
import sync
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.llms.cache as responsecache

const max_cache_entries = 100000
const max_cache_bytes = i64(1024 * 1024 * 1024)
const max_cache_key_bytes = 1024

@[heap]
struct State {
mut:
	mutex       sync.Mutex
	db          sqlite.DB
	max_entries int
	max_bytes   i64
	closed      bool
}

// Cache stores serialized model responses in SQLite and implements
// responsecache.Backend. The JSON payload bound applies to retained response
// data; SQLite page/index overhead is outside that bound.
pub struct Cache {
	state &State
}

// new_cache opens a SQLite database and trims existing entries to the supplied
// FIFO entry and serialized-response byte limits. A path of `:memory:` is
// useful for tests but does not persist across connections.
pub fn new_cache(database_path string, max_entries int, max_bytes i64) !&Cache {
	if database_path.trim_space() == '' || database_path.len > 4096 || database_path.contains('\0') {
		return error('SQLite cache path must contain between 1 and 4096 bytes and no NUL')
	}
	if max_entries < 1 || max_entries > max_cache_entries {
		return error('SQLite cache entry limit must be between 1 and ${max_cache_entries}')
	}
	if max_bytes < 1 || max_bytes > max_cache_bytes {
		return error('SQLite cache byte limit must be between 1 byte and 1 GiB')
	}
	mut db := sqlite.connect(database_path) or {
		return error('could not open SQLite response cache: ${err.msg()}')
	}
	db.exec('CREATE TABLE IF NOT EXISTS langchain_response_cache (id INTEGER PRIMARY KEY, cache_key TEXT NOT NULL UNIQUE, payload TEXT NOT NULL, payload_bytes INTEGER NOT NULL)') or {
		db.close() or {}
		return error('could not initialize SQLite response cache')
	}
	trim_entries(mut db, max_entries, max_bytes) or {
		db.close() or {}
		return error('could not apply SQLite response cache limits')
	}
	return &Cache{
		state: &State{
			db:          db
			max_entries: max_entries
			max_bytes:   max_bytes
		}
	}
}

fn trim_entries(mut db sqlite.DB, max_entries int, max_bytes i64) ! {
	// Both numeric bounds are validated when the Cache is constructed, so they
	// can be embedded as decimal literals without creating an injection path.
	db.exec('DELETE FROM langchain_response_cache WHERE id NOT IN (SELECT id FROM (SELECT id, SUM(payload_bytes) OVER (ORDER BY id DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS retained_bytes, ROW_NUMBER() OVER (ORDER BY id DESC) AS retained_count FROM langchain_response_cache) WHERE retained_bytes <= ${max_bytes} AND retained_count <= ${max_entries})')!
}

fn validate_key(key string) ! {
	if key.trim_space() == '' || key.len > max_cache_key_bytes || key.contains('\0') {
		return error('SQLite cache key must contain between 1 and ${max_cache_key_bytes} bytes and no NUL')
	}
}

// get returns a newly decoded response snapshot, if the key exists.
pub fn (cache Cache) get(mut ctx context.Context, key string) !responsecache.Lookup {
	validate_key(key)!
	err := ctx.err()
	if err !is none {
		return err
	}
	mut state := cache.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if state.closed {
		return error('SQLite response cache is closed')
	}
	err_locked := ctx.err()
	if err_locked !is none {
		return err_locked
	}
	rows := state.db.exec_param_many('SELECT CAST(substr(CAST(payload AS BLOB), 1, ${state.max_bytes + 1}) AS TEXT), payload_bytes FROM langchain_response_cache WHERE cache_key = ? LIMIT 1', [
		key,
	]) or {
		return error('could not read SQLite response cache')
	}
	err_after_query := ctx.err()
	if err_after_query !is none {
		return err_after_query
	}
	if rows.len == 0 {
		return responsecache.Lookup{}
	}
	if rows[0].vals.len != 2 || i64(rows[0].vals[0].len) > state.max_bytes
		|| rows[0].vals[1].i64() != i64(rows[0].vals[0].len) {
		return error('SQLite response cache contains an oversized or invalid response')
	}
	response := json2.decode[llms.Response](rows[0].vals[0], json2.DecoderOptions{}) or {
		return error('SQLite response cache contains an invalid response')
	}
	err_after := ctx.err()
	if err_after !is none {
		return err_after
	}
	return responsecache.Lookup{ found: true, response: response }
}

// put stores a serialized response and evicts the oldest entries until both
// configured bounds hold. Responses larger than max_bytes are skipped; an
// existing value for that key is left unchanged.
pub fn (cache Cache) put(mut ctx context.Context, key string, response llms.Response) ! {
	validate_key(key)!
	mut err := ctx.err()
	if err !is none {
		return err
	}
	payload := json2.encode(response, json2.EncoderOptions{})
	mut state := cache.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if state.closed {
		return error('SQLite response cache is closed')
	}
	err = ctx.err()
	if err !is none {
		return err
	}
	if i64(payload.len) > state.max_bytes {
		return
	}
	state.db.begin() or { return error('could not start SQLite response cache transaction') }
	mut committed := false
	defer {
		if !committed {
			state.db.rollback() or {}
		}
	}
	state.db.exec_param_many('INSERT INTO langchain_response_cache (cache_key, payload, payload_bytes) VALUES (?, ?, ?) ON CONFLICT(cache_key) DO UPDATE SET payload = excluded.payload, payload_bytes = excluded.payload_bytes', [
		key,
		payload,
		payload.len.str(),
	]) or {
		return error('could not store SQLite response cache entry')
	}
	trim_entries(mut state.db, state.max_entries, state.max_bytes) or {
		return error('could not enforce SQLite response cache limits')
	}
	err = ctx.err()
	if err !is none {
		return err
	}
	state.db.commit() or { return error('could not commit SQLite response cache entry') }
	committed = true
}

// close closes the database connection. The database file remains available
// for a later Cache instance to reopen.
pub fn (cache Cache) close() ! {
	mut state := cache.state
	state.mutex.lock()
	defer {
		state.mutex.unlock()
	}
	if !state.closed {
		state.db.close() or { return error('could not close SQLite response cache') }
		state.closed = true
	}
}
