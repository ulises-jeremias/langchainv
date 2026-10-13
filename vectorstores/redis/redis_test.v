module redis

import context
import json2
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.vectorstores
import db.redis as redis_client

struct RedisFixtureEmbedder {}

fn (embedder RedisFixtureEmbedder) embed_documents(mut _ctx context.Context, texts []string) ![][]f32 {
	return texts.map([f32(0.25), f32(0.75)])
}

fn (embedder RedisFixtureEmbedder) embed_query(mut _ctx context.Context, _text string) ![]f32 {
	return [f32(0.25), f32(0.75)]
}

@[heap]
struct RedisFixtureState {
mut:
	commands [][]string
	response redis_client.RedisValue = 'OK'
}

struct RedisFixtureClient {
	state &RedisFixtureState
}

fn (client RedisFixtureClient) cmd(command ...string) !redis_client.RedisValue {
	mut state := client.state
	state.commands << command.clone()
	return state.response
}

fn fixture_store(state &RedisFixtureState) !Store {
	return new_store(RedisFixtureEmbedder{}, RedisFixtureClient{
		state: state
	}, Options{
		index:      'langchainv_idx'
		key_prefix: 'doc:langchainv:'
		dimensions: 2
	})
}

fn test_redis_explicitly_initializes_a_non_destructive_hash_index() {
	mut state := &RedisFixtureState{}
	initialize_index(RedisFixtureClient{
		state: state
	}, Options{
		index:      'langchainv_idx'
		key_prefix: 'doc:langchainv:'
		dimensions: 2
	}, ['kind', 'category']) or { panic(err) }
	assert state.commands.len == 1
	command := state.commands[0]
	assert command[0..8] == ['FT.CREATE', 'langchainv_idx', 'ON', 'HASH', 'PREFIX', '1',
		'doc:langchainv:', 'SCHEMA']
	assert command.contains('content')
	assert command.contains('namespace')
	assert command.contains('lcg_source')
	assert command.contains('meta_kind')
	assert command.contains('meta_category')
	assert command[command.len - 10..] == ['content_vector', 'VECTOR', 'FLAT', '6', 'TYPE', 'FLOAT32',
		'DIM', '2', 'DISTANCE_METRIC', 'COSINE']
}

fn test_redis_explicitly_initializes_hnsw_with_bounded_parameters() {
	mut state := &RedisFixtureState{}
	initialize_index(RedisFixtureClient{
		state: state
	}, Options{
		index:                'langchainv_idx'
		key_prefix:           'doc:langchainv:'
		dimensions:           2
		algorithm:            'hnsw'
		hnsw_m:               32
		hnsw_ef_construction: 400
	}, []) or { panic(err) }
	assert state.commands.len == 1
	command := state.commands[0]
	assert command[command.len - 14..] == ['content_vector', 'VECTOR', 'HNSW', '10', 'TYPE', 'FLOAT32',
		'DIM', '2', 'DISTANCE_METRIC', 'COSINE', 'M', '32', 'EF_CONSTRUCTION', '400']
}

fn test_redis_hnsw_index_validation_fails_before_sending_commands() {
	mut state := &RedisFixtureState{}
	initialize_index(RedisFixtureClient{
		state: state
	}, Options{
		index:                'langchainv_idx'
		dimensions:           2
		algorithm:            'HNSW'
		hnsw_m:               64
		hnsw_ef_construction: 16
	}, []) or {
		assert err.msg().contains('EF_CONSTRUCTION')
		assert state.commands.len == 0
		return
	}
	assert false, 'expected invalid HNSW parameters to fail before Redis'
}

fn test_redis_index_initializer_rejects_unknown_algorithm_before_command() {
	mut state := &RedisFixtureState{}
	initialize_index(RedisFixtureClient{
		state: state
	}, Options{
		index:      'langchainv_idx'
		dimensions: 2
		algorithm:  'SVS-VAMANA'
	}, []) or {
		assert err.msg().contains('FLAT or HNSW')
		assert state.commands.len == 0
		return
	}
	assert false, 'expected the unsupported Redis algorithm to fail'
}

fn test_redis_index_initialization_rejects_duplicate_or_reserved_metadata_fields() {
	mut state := &RedisFixtureState{}
	initialize_index(RedisFixtureClient{
		state: state
	}, Options{
		index:      'langchainv_idx'
		dimensions: 2
	}, ['kind', 'kind']) or {
		assert err.msg().contains('unique simple names')
		assert state.commands.len == 0
		return
	}
	assert false, 'expected duplicate metadata fields to fail'
}

fn test_redis_add_documents_writes_bounded_hash_records() {
	mut state := &RedisFixtureState{}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	mut document := schema.new_document('stored text')
	document.metadata['kind'] = json2.Any('guide')
	ids := store.add_documents(mut ctx, [document], vectorstores.StoreOptions{
		namespace: 'tenant-1'
	}) or { panic(err) }
	assert ids.len == 1
	assert ids[0].starts_with('doc:langchainv:')
	assert state.commands.len == 1
	command := state.commands[0]
	assert command[0] == 'HSET'
	assert command[1] == ids[0]
	assert command[2] == 'content'
	assert command[4] == 'metadata'
	assert command[6] == 'namespace'
	assert command[7] == 'tenant-1'
	assert command[8] == 'content_vector'
	assert command[9].len == 8
	assert command[10] == 'lcg_source'
	assert command[11] == 'langchainv'
	assert command[12] == 'meta_kind'
	assert command[13] == '"guide"'
}

fn test_redis_search_parses_score_metadata_and_escapes_filter_values() {
	mut response := []redis_client.RedisValue{}
	response << redis_client.RedisValue(i64(1))
	response << redis_client.RedisValue('doc:langchainv:fixed-id')
	response << redis_client.RedisValue([
		redis_client.RedisValue('content'),
		redis_client.RedisValue('answer'),
		redis_client.RedisValue('metadata'),
		redis_client.RedisValue('{"kind":"guide"}'),
		redis_client.RedisValue('distance'),
		redis_client.RedisValue('0.09'),
	])
	mut state := &RedisFixtureState{
		response: redis_client.RedisValue(response)
	}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	mut options := vectorstores.SearchOptions{
		namespace: 'ténant-1'
	}
	options.filter['kind'] = json2.Any('guide / *')
	documents := store.similarity_search(mut ctx, 'question', 4, options) or { panic(err) }
	assert documents.len == 1
	assert documents[0].page_content == 'answer'
	assert documents[0].score == f32(0.91)
	assert (documents[0].metadata['kind'] or { json2.Any('') }) == json2.Any('guide')
	command := state.commands[0]
	assert command[0] == 'FT.SEARCH'
	assert command[1] == 'langchainv_idx'
	assert command[2].contains('@lcg_source:{langchainv}')
	assert command[2].contains('@namespace:{ténant\\-1}')
	assert command[2].contains('@meta_kind:{' + escape_tag('"guide / *"') + '}')
	assert command.contains('DIALECT')
	assert command[17].len == 8
}

fn test_redis_hnsw_search_passes_bounded_runtime_ef() {
	mut response := []redis_client.RedisValue{}
	response << redis_client.RedisValue(i64(1))
	response << redis_client.RedisValue('doc:langchainv:fixed-id')
	response << redis_client.RedisValue([
		redis_client.RedisValue('content'),
		redis_client.RedisValue('answer'),
		redis_client.RedisValue('metadata'),
		redis_client.RedisValue('{}'),
		redis_client.RedisValue('distance'),
		redis_client.RedisValue('0.09'),
	])
	mut state := &RedisFixtureState{
		response: redis_client.RedisValue(response)
	}
	store := new_store(RedisFixtureEmbedder{}, RedisFixtureClient{
		state: state
	}, Options{
		index:                'langchainv_idx'
		dimensions:           2
		algorithm:            'HNSW'
		hnsw_ef_construction: 200
		hnsw_ef_runtime:      150
	}) or { panic(err) }
	mut ctx := context.background()
	documents := store.similarity_search(mut ctx, 'question', 4, vectorstores.SearchOptions{}) or {
		panic(err)
	}
	assert documents.len == 1
	command := state.commands[0]
	assert command[2].contains('EF_RUNTIME $ef_runtime AS distance')
	assert command[14] == 'PARAMS'
	assert command[15] == '4'
	assert command[18] == 'ef_runtime'
	assert command[19] == '150'
}

fn test_redis_hnsw_store_rejects_invalid_runtime_ef() {
	mut state := &RedisFixtureState{}
	new_store(RedisFixtureEmbedder{}, RedisFixtureClient{
		state: state
	}, Options{
		index:                'langchainv_idx'
		dimensions:           2
		algorithm:            'HNSW'
		hnsw_ef_construction: 200
		hnsw_ef_runtime:      0
	}) or {
		assert err.msg().contains('EF_RUNTIME')
		assert state.commands.len == 0
		return
	}
	assert false, 'expected an invalid HNSW runtime setting to fail'
}

fn test_redis_search_returns_binary_vector_when_requested() {
	mut response := []redis_client.RedisValue{}
	response << redis_client.RedisValue(i64(1))
	response << redis_client.RedisValue('doc:langchainv:fixed-id')
	response << redis_client.RedisValue([
		redis_client.RedisValue('content'),
		redis_client.RedisValue('answer'),
		redis_client.RedisValue('metadata'),
		redis_client.RedisValue('{}'),
		redis_client.RedisValue('distance'),
		redis_client.RedisValue('0.09'),
		redis_client.RedisValue('content_vector'),
		redis_client.RedisValue(binary_vector([f32(0.4), 0.6])),
	])
	mut state := &RedisFixtureState{
		response: redis_client.RedisValue(response)
	}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	documents := store.similarity_search(mut ctx, 'question', 1, vectorstores.SearchOptions{
		include_vectors: true
	}) or { panic(err) }
	assert documents.len == 1
	assert documents[0].embedding == [f32(0.4), f32(0.6)]
	assert state.commands[0][4] == '4'
	assert state.commands[0].contains('content_vector')
}

fn test_redis_rejects_malformed_returned_binary_vector() {
	mut response := []redis_client.RedisValue{}
	response << redis_client.RedisValue(i64(1))
	response << redis_client.RedisValue('doc:langchainv:fixed-id')
	response << redis_client.RedisValue([
		redis_client.RedisValue('content'),
		redis_client.RedisValue('answer'),
		redis_client.RedisValue('metadata'),
		redis_client.RedisValue('{}'),
		redis_client.RedisValue('distance'),
		redis_client.RedisValue('0.09'),
		redis_client.RedisValue('content_vector'),
		redis_client.RedisValue('bad'),
	])
	mut state := &RedisFixtureState{
		response: redis_client.RedisValue(response)
	}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.similarity_search(mut ctx, 'question', 1, vectorstores.SearchOptions{
		include_vectors: true
	}) or {
		assert err.msg().contains('byte length')
		return
	}
	assert false, 'expected malformed Redis vector to fail'
}

fn test_redis_namespace_constrained_delete_uses_atomic_single_key_scripts() {
	mut state := &RedisFixtureState{}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.delete(mut ctx, ['doc:langchainv:id-1', 'doc:langchainv:id-2'], vectorstores.StoreOptions{
		namespace: 'tenant-1'
	}) or { panic(err) }
	assert state.commands.len == 2
	for i, command in state.commands {
		assert command[0] == 'EVAL'
		assert command[1].contains("redis.call('TYPE', KEYS[1])")
		assert command[1].contains("redis.call('HGET', KEYS[1], ARGV[1]) ~= ARGV[2]")
		assert command[1].contains("redis.call('HGET', KEYS[1], ARGV[3]) ~= ARGV[4]")
		assert command[1].contains("redis.call('DEL', KEYS[1])")
		assert command[2] == '1'
		assert command[3] == 'doc:langchainv:id-${i + 1}'
		assert command[4..] == ['lcg_source', 'langchainv', 'namespace', 'tenant-1']
	}
}

fn test_redis_delete_without_namespace_keeps_the_batched_del_path() {
	mut state := &RedisFixtureState{}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.delete(mut ctx, ['doc:langchainv:id-1', 'doc:langchainv:id-2'],
		vectorstores.StoreOptions{}) or { panic(err) }
	assert state.commands == [['DEL', 'doc:langchainv:id-1', 'doc:langchainv:id-2']]
}

fn test_redis_delete_validates_all_ids_before_sending_commands() {
	mut state := &RedisFixtureState{}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.delete(mut ctx, ['doc:langchainv:valid', 'other:invalid'], vectorstores.StoreOptions{
		namespace: 'tenant-1'
	}) or {
		assert err.msg().contains('key prefix')
		assert state.commands.len == 0
		return
	}
	assert false, 'expected an invalid Redis key to fail before deleting records'
}

fn test_redis_namespace_delete_checks_total_payload_before_deleting() {
	mut state := &RedisFixtureState{}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	mut ids := []string{}
	for i in 0 .. 70 {
		ids << 'doc:langchainv:id-${i}'
	}
	store.delete(mut ctx, ids, vectorstores.StoreOptions{
		namespace: 'x'.repeat(65536)
	}) or {
		assert err.msg().contains('4 MiB')
		assert state.commands.len == 0
		return
	}
	assert false, 'expected an oversized Redis delete request to fail before deleting records'
}

fn test_redis_store_requires_a_valid_existing_index_configuration() {
	mut state := &RedisFixtureState{}
	if _ := new_store(RedisFixtureEmbedder{}, RedisFixtureClient{
		state: state
	}, Options{
		index:      'invalid index'
		dimensions: 2
	}) {
		assert false
	} else {
		assert err.msg().contains('index and key prefix')
	}
}
