module mariadb

import context
import json2
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.tools.sqldatabase
import ulises_jeremias.langchainv.vectorstores

struct MariaDBFixtureEmbedder {}

fn (embedder MariaDBFixtureEmbedder) embed_documents(mut _ctx context.Context, texts []string) ![][]f32 {
	return texts.map([f32(0.25), 0.75])
}

fn (embedder MariaDBFixtureEmbedder) embed_query(mut _ctx context.Context, _text string) ![]f32 {
	return [f32(0.25), 0.75]
}

@[heap]
struct MariaDBFixtureState {
mut:
	statements []string
	parameters [][]string
	result     sqldatabase.QueryResult
}

struct MariaDBFixtureEngine {
	state        &MariaDBFixtureState
	dialect_name string
}

fn (engine MariaDBFixtureEngine) dialect() string {
	return if engine.dialect_name == '' { 'mysql' } else { engine.dialect_name }
}

fn (engine MariaDBFixtureEngine) query(mut _ctx context.Context, _statement string) !sqldatabase.QueryResult {
	return sqldatabase.QueryResult{}
}

fn (engine MariaDBFixtureEngine) query_params(mut _ctx context.Context, statement string, parameters []string) !sqldatabase.QueryResult {
	mut state := engine.state
	state.statements << statement
	state.parameters << parameters.clone()
	return state.result
}

fn (engine MariaDBFixtureEngine) table_names(mut _ctx context.Context, _max_tables int) ![]string {
	return []string{}
}

fn (engine MariaDBFixtureEngine) table_info(mut _ctx context.Context, _table string) !string {
	return ''
}

fn (engine MariaDBFixtureEngine) close() ! {}

fn fixture_store(state &MariaDBFixtureState) !Store {
	return new_store(MariaDBFixtureEmbedder{}, MariaDBFixtureEngine{
		state: state
	}, Options{
		table: 'documents'
	})
}

fn test_mariadb_adds_documents_with_parameterized_bulk_insert() {
	mut state := &MariaDBFixtureState{}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	mut document := schema.new_document('stored text')
	document.metadata['kind'] = json2.Any('guide')
	ids := store.add_documents(mut ctx, [document], vectorstores.StoreOptions{
		namespace: 'tenant-1'
	}) or { panic(err) }
	assert ids.len == 1
	assert state.statements.len == 1
	statement := state.statements[0]
	assert statement.starts_with('INSERT INTO `documents`')
	assert statement.contains('`embedding`) VALUES (?, ?, ?, ?, VEC_FromText(?))')
	assert state.parameters[0][0] == ids[0]
	assert state.parameters[0][1] == 'stored text'
	assert state.parameters[0][2].contains('"kind":"guide"')
	assert state.parameters[0][3] == 'tenant-1'
	assert state.parameters[0][4] == '[0.25,0.75]'
}

fn test_mariadb_search_uses_cosine_order_and_exact_metadata_filters() {
	mut state := &MariaDBFixtureState{
		result: sqldatabase.QueryResult{
			rows: [['id-1', 'answer', '{"kind":"guide"}', '0.91']]
		}
	}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	mut options := vectorstores.SearchOptions{
		namespace: 'tenant-1'
	}
	options.filter['kind'] = json2.Any('guide')
	documents := store.similarity_search(mut ctx, 'query', 4, options) or { panic(err) }
	assert documents.len == 1
	assert documents[0].page_content == 'answer'
	assert documents[0].score == f32(0.91)
	assert (documents[0].metadata['kind'] or { json2.Any('') }) == json2.Any('guide')
	statement := state.statements[0]
	assert statement.starts_with('WITH query_vector AS (SELECT VEC_FromText(?) AS vector)')
	assert statement.contains('VEC_DISTANCE_COSINE(`embedding`, q.vector)')
	assert statement.contains('`namespace` = ?')
	assert statement.contains("JSON_EXTRACT(`metadata`, CONCAT('$.', ?)) = JSON_EXTRACT(?, '$')")
	assert statement.contains('response_bytes <= 4194304')
	assert state.parameters[0] == ['[0.25,0.75]', 'tenant-1', 'kind', '"guide"', '4']
}

fn test_mariadb_delete_uses_parameterized_ids_and_namespace() {
	mut state := &MariaDBFixtureState{}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.delete(mut ctx, ['id-1', 'id-2'], vectorstores.StoreOptions{
		namespace: 'tenant-1'
	}) or { panic(err) }
	assert state.statements[0].starts_with('DELETE FROM `documents`')
	assert state.statements[0].contains('`id` IN (?, ?) AND `namespace` = ?')
	assert state.parameters[0] == ['id-1', 'id-2', 'tenant-1']
}

fn test_mariadb_rejects_unsafe_identifiers_metrics_and_limits() {
	mut state := &MariaDBFixtureState{}
	new_store(MariaDBFixtureEmbedder{}, MariaDBFixtureEngine{
		state: state
	}, Options{
		table: 'documents; DROP TABLE documents'
	}) or {
		assert err.msg().contains('SQL identifiers')
		return
	}
	assert false, 'expected an unsafe table identifier to fail'
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.similarity_search(mut ctx, 'query', 1, vectorstores.SearchOptions{
		distance_strategy: 'euclidean'
	}) or {
		assert err.msg().contains('cosine distance')
		assert state.statements.len == 0
		return
	}
	assert false, 'expected an unsupported distance strategy to fail'
}

fn test_mariadb_rejects_non_mysql_engines() {
	mut state := &MariaDBFixtureState{}
	new_store(MariaDBFixtureEmbedder{}, MariaDBFixtureEngine{
		state:        state
		dialect_name: 'sqlite3'
	}, Options{}) or {
		assert err.msg().contains('MariaDB')
		return
	}
	assert false, 'expected non-MariaDB dialect to fail'
}

fn test_mariadb_rejects_metadata_keys_outside_safe_json_path_subset() {
	mut state := &MariaDBFixtureState{}
	store := fixture_store(state) or { panic(err) }
	mut options := vectorstores.SearchOptions{}
	options.filter['kind` OR 1=1 --'] = json2.Any('guide')
	mut ctx := context.background()
	store.similarity_search(mut ctx, 'query', 4, options) or {
		assert err.msg().contains('scalar metadata equality')
		assert state.statements.len == 0
		return
	}
	assert false, 'expected an unsafe metadata key to fail before SQL execution'
}
