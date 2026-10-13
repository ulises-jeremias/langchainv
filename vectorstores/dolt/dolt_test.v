module dolt

import context
import json2
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.tools.sqldatabase
import ulises_jeremias.langchainv.vectorstores

struct DoltFixtureEmbedder {}

fn (_ DoltFixtureEmbedder) embed_documents(mut _ctx context.Context, texts []string) ![][]f32 {
	return texts.map([f32(0.25), 0.75])
}

fn (_ DoltFixtureEmbedder) embed_query(mut _ctx context.Context, _text string) ![]f32 {
	return [f32(0.25), 0.75]
}

@[heap]
struct DoltFixtureState {
mut:
	statements []string
	parameters [][]string
	result     sqldatabase.QueryResult
}

struct DoltFixtureEngine {
	state        &DoltFixtureState
	dialect_name string
}

fn (engine DoltFixtureEngine) dialect() string {
	return if engine.dialect_name == '' { 'mysql' } else { engine.dialect_name }
}

fn (engine DoltFixtureEngine) query(mut _ctx context.Context, statement string) !sqldatabase.QueryResult {
	mut state := engine.state
	state.statements << statement
	return sqldatabase.QueryResult{}
}

fn (engine DoltFixtureEngine) query_params(mut _ctx context.Context, statement string, parameters []string) !sqldatabase.QueryResult {
	mut state := engine.state
	state.statements << statement
	state.parameters << parameters.clone()
	return state.result
}

fn (_ DoltFixtureEngine) table_names(mut _ctx context.Context, _max_tables int) ![]string {
	return []string{}
}

fn (_ DoltFixtureEngine) table_info(mut _ctx context.Context, _table string) !string {
	return ''
}

fn (_ DoltFixtureEngine) close() ! {}

fn dolt_fixture_store(state &DoltFixtureState) !Store {
	return new_store(DoltFixtureEmbedder{}, DoltFixtureEngine{
		state: state
	}, Options{
		database_name: 'docs'
	})
}

fn test_dolt_initialization_is_explicit_and_does_not_build_index() {
	mut state := &DoltFixtureState{}
	mut ctx := context.background()
	initialize_tables(mut ctx, DoltFixtureEngine{
		state: state
	}, Options{}) or { panic(err) }
	assert state.statements.len == 2
	assert state.statements[0].starts_with('CREATE TABLE IF NOT EXISTS')
	assert state.statements[0].contains('langchain_dolt_collection')
	assert state.statements[1].contains('langchain_dolt_embedding')
	assert !state.statements[0].contains('VECTOR INDEX')
	assert !state.statements[1].contains('VECTOR INDEX')
}

fn test_dolt_vector_index_creation_is_explicit_and_idempotent() {
	mut state := &DoltFixtureState{
		result: sqldatabase.QueryResult{
			rows: [['0']]
		}
	}
	mut ctx := context.background()
	create_vector_index(mut ctx, DoltFixtureEngine{
		state: state
	}, Options{}) or { panic(err) }
	assert state.statements.len == 2
	assert state.statements[1].contains('ADD VECTOR INDEX')
	state.result = sqldatabase.QueryResult{
		rows: [['1']]
	}
	create_vector_index(mut ctx, DoltFixtureEngine{
		state: state
	}, Options{}) or { panic(err) }
	assert state.statements.len == 3
	assert !state.statements[2].contains('ADD VECTOR INDEX')
}

fn test_dolt_rejects_unsafe_identifiers() {
	mut state := &DoltFixtureState{}
	mut ctx := context.background()
	initialize_tables(mut ctx, DoltFixtureEngine{
		state: state
	}, Options{
		embedding_table: 'docs; DROP TABLE users'
	}) or {
		assert err.msg().contains('simple SQL identifiers')
		assert state.statements.len == 0
		return
	}
	assert false, 'expected unsafe identifier to fail'
}

fn test_dolt_rejects_non_mysql_engines() {
	mut state := &DoltFixtureState{}
	new_store(DoltFixtureEmbedder{}, DoltFixtureEngine{
		state:        state
		dialect_name: 'sqlite3'
	}, Options{}) or {
		assert err.msg().contains('MySQL-compatible')
		assert state.statements.len == 0
		return
	}
	assert false, 'expected a non-MySQL engine to fail'
}

fn test_dolt_add_documents_uses_parameterized_bulk_insert() {
	mut state := &DoltFixtureState{}
	store := dolt_fixture_store(state) or { panic(err) }
	mut document := schema.new_document('stored text')
	document.metadata['kind'] = json2.Any('guide')
	mut ctx := context.background()
	ids := store.add_documents(mut ctx, [document], vectorstores.StoreOptions{}) or { panic(err) }
	assert ids.len == 1
	assert state.statements.len == 2
	assert state.statements[0].starts_with('INSERT IGNORE INTO')
	assert state.statements[1].starts_with('INSERT INTO')
	assert state.statements[1].contains('CAST(? AS JSON)')
	assert state.parameters[1][0] == ids[0]
	assert state.parameters[1][1] == 'stored text'
	assert state.parameters[1][2] == '[0.25,0.75]'
	assert state.parameters[1][3].contains('"kind":"guide"')
	assert state.parameters[1][4] == 'docs'
}

fn test_dolt_search_uses_parameterized_metadata_filter_and_optional_vector() {
	mut state := &DoltFixtureState{
		result: sqldatabase.QueryResult{
			rows: [['answer', '{"kind":"guide"}', '0.91', '[0.25,0.75]']]
		}
	}
	store := dolt_fixture_store(state) or { panic(err) }
	mut options := vectorstores.SearchOptions{
		include_vectors: true
	}
	options.filter['kind'] = json2.Any('guide')
	mut ctx := context.background()
	documents := store.similarity_search(mut ctx, 'query', 4, options) or { panic(err) }
	assert documents.len == 1
	assert documents[0].page_content == 'answer'
	assert documents[0].score == f32(0.91)
	assert documents[0].embedding == [f32(0.25), 0.75]
	assert (documents[0].metadata['kind'] or { json2.Any('') }) == json2.Any('guide')
	assert state.statements[0].contains('ORDER BY VEC_DISTANCE(e.embedding, CAST(? AS JSON)) ASC LIMIT ?')
	assert state.statements[0].contains('JSON_EXTRACT(e.cmetadata, ?) = CAST(? AS JSON)')
	assert state.parameters[0] == ['[0.25,0.75]', 'docs', '$.kind', '"guide"', '[0.25,0.75]', '4']
}

fn test_dolt_search_omits_metadata_when_disabled_and_vectors_by_default() {
	mut state := &DoltFixtureState{
		result: sqldatabase.QueryResult{
			rows: [['answer', '{"kind":"guide"}', '0.91']]
		}
	}
	store := dolt_fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	documents := store.similarity_search(mut ctx, 'query', 1, vectorstores.SearchOptions{
		include_metadata: false
	}) or {
		panic(err)
	}
	assert documents[0].metadata.len == 0
	assert documents[0].embedding.len == 0
}

fn test_dolt_delete_scopes_parameterized_ids_to_collection() {
	mut state := &DoltFixtureState{}
	store := dolt_fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.delete(mut ctx, ['id-1', 'id-2'], vectorstores.StoreOptions{}) or { panic(err) }
	assert state.statements[0].starts_with('DELETE e FROM')
	assert state.statements[0].contains('e.`uuid` IN (?, ?)')
	assert state.parameters[0] == ['docs', 'id-1', 'id-2']
}
