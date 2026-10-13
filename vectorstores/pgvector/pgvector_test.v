module pgvector

import context
import json2
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.tools.sqldatabase
import ulises_jeremias.langchainv.vectorstores

struct PgvectorFixtureEmbedder {}

fn (embedder PgvectorFixtureEmbedder) embed_documents(mut _ctx context.Context, texts []string) ![][]f32 {
	return texts.map([f32(0.25), 0.75])
}

fn (embedder PgvectorFixtureEmbedder) embed_query(mut _ctx context.Context, _text string) ![]f32 {
	return [f32(0.25), 0.75]
}

@[heap]
struct PgvectorFixtureState {
mut:
	statements []string
	parameters [][]string
	result     sqldatabase.QueryResult
}

struct PgvectorFixtureEngine {
	state        &PgvectorFixtureState
	dialect_name string
}

fn (engine PgvectorFixtureEngine) dialect() string {
	return if engine.dialect_name == '' { 'pgx' } else { engine.dialect_name }
}

fn (engine PgvectorFixtureEngine) query(mut _ctx context.Context, statement string) !sqldatabase.QueryResult {
	mut state := engine.state
	state.statements << statement
	return sqldatabase.QueryResult{}
}

fn (engine PgvectorFixtureEngine) query_params(mut _ctx context.Context, statement string, parameters []string) !sqldatabase.QueryResult {
	mut state := engine.state
	state.statements << statement
	state.parameters << parameters.clone()
	return state.result
}

fn (engine PgvectorFixtureEngine) table_names(mut _ctx context.Context, _max_tables int) ![]string {
	return []string{}
}

fn (engine PgvectorFixtureEngine) table_info(mut _ctx context.Context, _table string) !string {
	return ''
}

fn (engine PgvectorFixtureEngine) close() ! {}

fn fixture_store(state &PgvectorFixtureState) !Store {
	return new_store(PgvectorFixtureEmbedder{}, PgvectorFixtureEngine{
		state: state
	}, Options{
		table: 'documents'
	})
}

fn test_pgvector_initializes_a_missing_table_without_overwrite() {
	mut state := &PgvectorFixtureState{}
	engine := PgvectorFixtureEngine{
		state: state
	}
	mut ctx := context.background()
	initialize_table(mut ctx, engine, Options{
		table: 'documents'
	}, 1536) or { panic(err) }
	assert state.statements == ['CREATE TABLE IF NOT EXISTS "documents" ("id" text PRIMARY KEY, "page_content" text NOT NULL, "metadata" jsonb NOT NULL DEFAULT \'{}\'::jsonb, "namespace" text NOT NULL DEFAULT \'\', "embedding" vector(1536) NOT NULL)']
}

fn test_pgvector_explicitly_builds_cosine_hnsw_index() {
	mut state := &PgvectorFixtureState{
		result: sqldatabase.QueryResult{}
	}
	engine := PgvectorFixtureEngine{ state: state }
	mut ctx := context.background()
	create_vector_index(mut ctx, engine, Options{ table: 'documents' }) or { panic(err) }
	assert state.statements.len == 2
	assert state.statements[0].contains('FROM pg_indexes')
	assert state.parameters[0] == ['documents', 'langchainv_documents_embedding_hnsw']
	assert state.statements[1] == 'CREATE INDEX "langchainv_documents_embedding_hnsw" ON "documents" USING hnsw ("embedding" vector_cosine_ops)'
}

fn test_pgvector_index_initializer_is_idempotent_for_matching_definition() {
	mut state := &PgvectorFixtureState{
		result: sqldatabase.QueryResult{
			rows: [['CREATE INDEX name ON documents USING hnsw (embedding vector_cosine_ops)']]
		}
	}
	engine := PgvectorFixtureEngine{ state: state }
	mut ctx := context.background()
	create_vector_index(mut ctx, engine, Options{ table: 'documents' }) or { panic(err) }
	assert state.statements.len == 1
}

fn test_pgvector_index_initializer_rejects_same_name_with_other_definition() {
	mut state := &PgvectorFixtureState{
		result: sqldatabase.QueryResult{
			rows: [['CREATE INDEX name ON documents USING btree (embedding)']]
		}
	}
	engine := PgvectorFixtureEngine{ state: state }
	mut ctx := context.background()
	create_vector_index(mut ctx, engine, Options{ table: 'documents' }) or {
		assert err.msg().contains('different definition')
		assert state.statements.len == 1
		return
	}
	assert false, 'expected an existing incompatible index to fail'
}

fn test_pgvector_table_initialization_rejects_unsafe_identifiers() {
	mut state := &PgvectorFixtureState{}
	engine := PgvectorFixtureEngine{
		state: state
	}
	mut ctx := context.background()
	initialize_table(mut ctx, engine, Options{
		table: 'documents; DROP TABLE users'
	}, 1536) or {
		assert err.msg().contains('simple SQL identifiers')
		assert state.statements.len == 0
		return
	}
	assert false, 'expected an unsafe table identifier to fail'
}

fn test_pgvector_table_initialization_rejects_invalid_dimensions() {
	mut state := &PgvectorFixtureState{}
	engine := PgvectorFixtureEngine{
		state: state
	}
	mut ctx := context.background()
	initialize_table(mut ctx, engine, Options{}, 0) or {
		assert err.msg().contains('dimension must be between')
		assert state.statements.len == 0
		return
	}
	assert false, 'expected an invalid vector dimension to fail'
}

fn test_pgvector_table_initialization_rejects_non_postgres_dialect() {
	mut state := &PgvectorFixtureState{}
	mut ctx := context.background()
	initialize_table(mut ctx, PgvectorFixtureEngine{
		state:        state
		dialect_name: 'sqlite3'
	}, Options{}, 3) or {
		assert err.msg().contains('PostgreSQL')
		assert state.statements.len == 0
		return
	}
	assert false, 'expected non-PostgreSQL engine to fail'
}

fn test_pgvector_adds_documents_with_parameterized_bulk_insert() {
	mut state := &PgvectorFixtureState{}
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
	assert statement.starts_with('INSERT INTO "documents"')
	assert statement.contains('"embedding") VALUES ($1, $2, $3::jsonb, $4, $5::vector)')
	assert state.parameters[0][0] == ids[0]
	assert state.parameters[0][1] == 'stored text'
	assert state.parameters[0][2].contains('"kind":"guide"')
	assert state.parameters[0][3] == 'tenant-1'
	assert state.parameters[0][4] == '[0.25,0.75]'
}

fn test_pgvector_search_uses_cosine_order_and_exact_metadata_filters() {
	mut state := &PgvectorFixtureState{
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
	assert statement.starts_with('WITH matches AS MATERIALIZED')
	assert statement.contains('"embedding" <=> $1::vector ASC')
	assert statement.contains('"namespace" = $2')
	assert statement.contains('"metadata" -> $3::text = $4::jsonb')
	assert statement.contains('response_bytes <= 4194304')
	assert state.parameters[0][0] == '[0.25,0.75]'
	assert state.parameters[0][1] == 'tenant-1'
	assert state.parameters[0][2] == 'kind'
	assert state.parameters[0][3] == '"guide"'
	assert state.parameters[0][4] == '4'
}

fn test_pgvector_search_returns_vectors_when_requested() {
	mut state := &PgvectorFixtureState{
		result: sqldatabase.QueryResult{
			rows: [['id-1', 'answer', '{"kind":"guide"}', '0.91', '[0.25, 0.75]']]
		}
	}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	documents := store.similarity_search(mut ctx, 'query', 2, vectorstores.SearchOptions{
		include_vectors: true
	}) or { panic(err) }
	assert documents.len == 1
	assert documents[0].embedding == [f32(0.25), f32(0.75)]
	assert state.statements[0].contains('"embedding"::text AS embedding_text')
	assert state.statements[0].contains('SELECT id, page_content, metadata_json, score, embedding_text')
}

fn test_pgvector_rejects_malformed_returned_vector_text() {
	mut state := &PgvectorFixtureState{
		result: sqldatabase.QueryResult{
			rows: [['id-1', 'answer', '{}', '0.91', '[0.25, bad]']]
		}
	}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.similarity_search(mut ctx, 'query', 1, vectorstores.SearchOptions{
		include_vectors: true
	}) or {
		assert err.msg().contains('non-numeric vector')
		return
	}
	assert false, 'expected malformed pgvector value to fail'
}

fn test_pgvector_delete_uses_parameterized_ids_and_namespace() {
	mut state := &PgvectorFixtureState{}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.delete(mut ctx, ['id-1', 'id-2'], vectorstores.StoreOptions{
		namespace: 'tenant-1'
	}) or { panic(err) }
	assert state.statements[0].starts_with('DELETE FROM "documents"')
	assert state.statements[0].contains('"id" IN ($1, $2) AND "namespace" = $3')
	assert state.parameters[0] == ['id-1', 'id-2', 'tenant-1']
}

fn test_pgvector_rejects_unsafe_identifiers_metrics_and_limits() {
	mut state := &PgvectorFixtureState{}
	new_store(PgvectorFixtureEmbedder{}, PgvectorFixtureEngine{
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

fn test_pgvector_rejects_non_postgres_engines() {
	mut state := &PgvectorFixtureState{}
	new_store(PgvectorFixtureEmbedder{}, PgvectorFixtureEngine{
		state:        state
		dialect_name: 'sqlite3'
	}, Options{}) or {
		assert err.msg().contains('PostgreSQL')
		return
	}
	assert false, 'expected non-PostgreSQL dialect to fail'
}
