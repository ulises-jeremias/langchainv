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

fn test_redis_add_documents_writes_bounded_hash_records() {
	mut state := &RedisFixtureState{}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	mut document := schema.new_document('stored text')
	document.metadata['kind'] = json2.Any('guide')
	ids := store.add_documents(mut ctx, [document], vectorstores.StoreOptions{
		namespace: 'ténant-1'
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
		namespace: 'tenant-1'
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

fn test_redis_rejects_namespace_constrained_delete() {
	mut state := &RedisFixtureState{}
	store := fixture_store(state) or { panic(err) }
	mut ctx := context.background()
	store.delete(mut ctx, ['doc:langchainv:id'], vectorstores.StoreOptions{
		namespace: 'tenant-1'
	}) or {
		assert err.msg().contains('namespace constraints')
		return
	}
	assert false
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
