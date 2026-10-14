module mongodb

import context
import json2
import ulises_jeremias.langchainv.schema

@[heap]
struct FakeMongoState {
mut:
	documents []map[string]json2.Any
	next_id   int
}

struct FakeMongoCollection {
	state &FakeMongoState
}

fn (collection FakeMongoCollection) insert_one(mut _ctx context.Context, document map[string]json2.Any) !string {
	mut state := collection.state
	state.next_id++
	mut stored := document.clone()
	stored['_id'] = json2.Any('id-${state.next_id}')
	state.documents << stored
	return 'id-${state.next_id}'
}

fn (collection FakeMongoCollection) find_sorted(mut _ctx context.Context, filter map[string]json2.Any, sort_field string, ascending bool, limit int) ![]map[string]json2.Any {
	mut matched := []map[string]json2.Any{}
	for document in collection.state.documents {
		if fake_matches(document, filter) {
			matched << document.clone()
		}
	}
	for i := 1; i < matched.len; i++ {
		for j := i; j > 0; j-- {
			left := (matched[j - 1]['seq'] or { json2.Any(0) }).int()
			right := (matched[j]['seq'] or { json2.Any(0) }).int()
			if left <= right {
				break
			}
			matched[j - 1], matched[j] = matched[j], matched[j - 1]
		}
	}
	if !ascending {
		matched = matched.reverse()
	}
	if limit > 0 && matched.len > limit {
		matched = matched[..limit].clone()
	}
	return matched
}

fn (collection FakeMongoCollection) delete_many(mut _ctx context.Context, filter map[string]json2.Any) !int {
	mut state := collection.state
	mut kept := []map[string]json2.Any{}
	mut deleted := 0
	for document in state.documents {
		if fake_matches(document, filter) {
			deleted++
		} else {
			kept << document
		}
	}
	state.documents = kept
	return deleted
}

fn fake_matches(document map[string]json2.Any, filter map[string]json2.Any) bool {
	for key, expected in filter {
		actual := document[key] or { return false }
		if expected is map[string]json2.Any {
			conditions := expected as map[string]json2.Any
			if threshold := conditions['$lt'] {
				if actual.int() >= threshold.int() {
					return false
				}
				continue
			}
		}
		if actual.str() != expected.str() {
			return false
		}
	}
	return true
}

fn test_mongo_history_stores_and_returns_messages_in_order() {
	mut state := &FakeMongoState{}
	mut ctx := context.background()
	mut history := new_mongo_chat_message_history(mut ctx, FakeMongoCollection{
		state: state
	}, 'session-1', 10, 4096) or { panic(err) }
	history.add_message(mut ctx, schema.text_message(.human, 'hello')) or { panic(err) }
	history.add_message(mut ctx, schema.text_message(.ai, 'hi there')) or { panic(err) }
	messages := history.get_messages(mut ctx) or { panic(err) }
	assert messages.len == 2
	assert messages[0].text() == 'hello'
	assert messages[1].text() == 'hi there'
	mut history_interface := schema.ChatMessageHistory(history)
	via_interface := history_interface.get_messages(mut ctx) or { panic(err) }
	assert via_interface.len == 2
}

fn test_mongo_history_isolates_sessions_and_clears() {
	mut state := &FakeMongoState{}
	mut ctx := context.background()
	mut first := new_mongo_chat_message_history(mut ctx, FakeMongoCollection{
		state: state
	}, 'first', 10, 4096) or { panic(err) }
	mut second := new_mongo_chat_message_history(mut ctx, FakeMongoCollection{
		state: state
	}, 'second', 10, 4096) or { panic(err) }
	first.add_message(mut ctx, schema.text_message(.human, 'one')) or { panic(err) }
	second.add_message(mut ctx, schema.text_message(.human, 'two')) or { panic(err) }
	assert (first.get_messages(mut ctx) or { panic(err) }).len == 1
	assert (second.get_messages(mut ctx) or { panic(err) })[0].text() == 'two'
	first.clear(mut ctx) or { panic(err) }
	assert (first.get_messages(mut ctx) or { panic(err) }).len == 0
	assert (second.get_messages(mut ctx) or { panic(err) }).len == 1
}

fn test_mongo_history_trims_to_recent_messages() {
	mut state := &FakeMongoState{}
	mut ctx := context.background()
	mut history := new_mongo_chat_message_history(mut ctx, FakeMongoCollection{
		state: state
	}, 'trim', 2, 4096) or { panic(err) }
	for text in ['one', 'two', 'three'] {
		history.add_message(mut ctx, schema.text_message(.human, text)) or { panic(err) }
	}
	messages := history.get_messages(mut ctx) or { panic(err) }
	assert messages.len == 2
	assert messages[0].text() == 'two'
	assert messages[1].text() == 'three'
	assert state.documents.len == 2
}

fn test_mongo_history_rejects_oversized_messages_and_closed_use() {
	mut state := &FakeMongoState{}
	mut ctx := context.background()
	mut history := new_mongo_chat_message_history(mut ctx, FakeMongoCollection{
		state: state
	}, 'small', 10, 32) or { panic(err) }
	history.add_message(mut ctx, schema.text_message(.human, 'this message is far too large')) or {
		assert err.msg().contains('exceeds')
		history.close()
		history.get_messages(mut ctx) or {
			assert err.msg().contains('closed')
			return
		}
		assert false, 'expected closed history to fail'
	}
	assert false, 'expected oversized message to fail'
}
