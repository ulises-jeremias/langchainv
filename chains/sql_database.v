// Package chains provides a bounded question-to-SQL-to-answer chain.
module chains

import context
import json2
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.prompts
import ulises_jeremias.langchainv.schema
import ulises_jeremias.langchainv.tools.sqldatabase

const max_sql_question_bytes = 16384
const max_sql_prompt_bytes_limit = 2097152
const default_sql_prompt = 'You are a {dialect} expert. Given a question, create a syntactically correct {dialect} query to run.\nUse only these tables:\n{table_info}\nQuestion: {question}\nRespond with a single read-only SQL query and nothing else.'
const default_sql_answer_prompt = 'Given a question, the SQL query that was run, and its result, write the final answer.\nQuestion: {question}\nSQL query: {sql_query}\nSQL result: {sql_result}\nFinal answer:'

// SQLDatabaseChainOptions configures keys, prompts, tables, and limits.
pub struct SQLDatabaseChainOptions {
pub:
	question_key              string = 'question'
	output_key                string = 'result'
	intermediate_steps_key    string = 'intermediate_steps'
	return_intermediate_steps bool
	tables                    []string
	max_question_bytes        int = 4096
	max_prompt_bytes          int = 131072
	call_options              llms.CallOptions
	sql_prompt                ?prompts.StringTemplate
	answer_prompt             ?prompts.StringTemplate
}

// SQLDatabaseChain asks a model for one read-only query, runs it, and asks for the answer.
pub struct SQLDatabaseChain {
	database                  sqldatabase.SQLDatabase
	model                     llms.CompletionModel
	question_key              string
	output_key                string
	intermediate_steps_key    string
	return_intermediate_steps bool
	tables                    []string
	max_question_bytes        int
	max_prompt_bytes          int
	call_options              llms.CallOptions
	sql_prompt                prompts.StringTemplate
	answer_prompt             prompts.StringTemplate
	memory_store              ?schema.Memory
}

// new_sql_database_chain constructs a chain over an existing SQLDatabase.
// Model-generated SQL is restricted to a single read-only SELECT or WITH
// statement, because the chain executes it without further review.
pub fn new_sql_database_chain(database sqldatabase.SQLDatabase, model llms.CompletionModel, options SQLDatabaseChainOptions) !SQLDatabaseChain {
	if options.question_key.trim_space() == '' || options.output_key.trim_space() == ''
		|| options.question_key == options.output_key {
		return error('SQL database chain question and output keys must be non-empty and distinct')
	}
	if options.return_intermediate_steps
		&& (options.intermediate_steps_key.trim_space() == ''
		|| options.intermediate_steps_key in [options.question_key, options.output_key]) {
		return error('SQL database chain intermediate steps key must be non-empty and distinct')
	}
	if options.max_question_bytes <= 0 || options.max_question_bytes > max_sql_question_bytes {
		return error('SQL database chain max_question_bytes is outside the supported range 1..16384')
	}
	if options.max_prompt_bytes <= 0 || options.max_prompt_bytes > max_sql_prompt_bytes_limit {
		return error('SQL database chain max_prompt_bytes is outside the supported range 1..2097152')
	}
	sql_prompt := options.sql_prompt or {
		prompts.StringTemplate{
			template: default_sql_prompt
		}
	}
	answer_prompt := options.answer_prompt or {
		prompts.StringTemplate{
			template: default_sql_answer_prompt
		}
	}
	sql_variables := sql_prompt.input_variables()!
	if 'question' !in sql_variables || 'table_info' !in sql_variables {
		return error('SQL database chain SQL prompt must include question and table_info variables')
	}
	answer_variables := answer_prompt.input_variables()!
	if 'question' !in answer_variables || 'sql_query' !in answer_variables
		|| 'sql_result' !in answer_variables {
		return error('SQL database chain answer prompt must include question, sql_query, and sql_result variables')
	}
	return SQLDatabaseChain{
		database:                  database
		model:                     model
		question_key:              options.question_key
		output_key:                options.output_key
		intermediate_steps_key:    options.intermediate_steps_key
		return_intermediate_steps: options.return_intermediate_steps
		tables:                    options.tables.clone()
		max_question_bytes:        options.max_question_bytes
		max_prompt_bytes:          options.max_prompt_bytes
		call_options:              options.call_options
		sql_prompt:                sql_prompt
		answer_prompt:             answer_prompt
	}
}

// call generates one read-only query, executes it, and formats the final answer.
pub fn (chain SQLDatabaseChain) call(mut ctx context.Context, inputs map[string]json2.Any) !map[string]json2.Any {
	chain.call_options.validate()!
	question_value := inputs[chain.question_key] or {
		return error('missing SQL database chain question')
	}
	question := match question_value {
		string { question_value }
		else { return error('SQL database chain question must be a string') }
	}
	if question.trim_space() == '' || question.len > chain.max_question_bytes {
		return error('SQL database chain question is empty or exceeds the configured byte limit')
	}
	table_info := chain.database.table_info(mut ctx, chain.tables)!
	sql_prompt_text := chain.sql_prompt.format({
		'dialect':    json2.Any(chain.database.dialect())
		'table_info': json2.Any(table_info)
		'question':   json2.Any(question)
	})!
	if sql_prompt_text.len > chain.max_prompt_bytes {
		return error('SQL database chain SQL prompt exceeds the configured byte limit')
	}
	sql_response := chain.model.complete(mut ctx, sql_prompt_text, chain.call_options)!
	sql_query := extract_read_only_sql(sql_response)!
	sql_result := chain.database.query(mut ctx, sql_query)!
	answer_prompt_text := chain.answer_prompt.format({
		'question':   json2.Any(question)
		'sql_query':  json2.Any(sql_query)
		'sql_result': json2.Any(sql_result)
	})!
	if answer_prompt_text.len > chain.max_prompt_bytes {
		return error('SQL database chain answer prompt exceeds the configured byte limit')
	}
	answer := chain.model.complete(mut ctx, answer_prompt_text, chain.call_options)!
	mut outputs := {
		chain.output_key: json2.Any(answer)
	}
	if chain.return_intermediate_steps {
		outputs[chain.intermediate_steps_key] = json2.Any([json2.Any({
			'sql_query':  json2.Any(sql_query)
			'sql_result': json2.Any(sql_result)
		})])
	}
	return outputs
}

// memory returns no memory; this chain is stateless.
pub fn (chain SQLDatabaseChain) memory() ?schema.Memory {
	return chain.memory_store
}

// input_keys returns the single question key.
pub fn (chain SQLDatabaseChain) input_keys() []string {
	return [chain.question_key]
}

// output_keys returns the answer key and, when enabled, the steps key.
pub fn (chain SQLDatabaseChain) output_keys() []string {
	if chain.return_intermediate_steps {
		return [chain.output_key, chain.intermediate_steps_key]
	}
	return [chain.output_key]
}

fn extract_read_only_sql(response string) !string {
	mut text := response.trim_space()
	if text.starts_with('```') {
		lines := text.split('\n')
		if lines.len < 3 || !lines.last().trim_space().starts_with('```') {
			return error('SQL database chain model returned a malformed fenced SQL response')
		}
		text = lines[1..lines.len - 1].join('\n').trim_space()
	}
	if query_index := text.index('SQLQuery:') {
		text = text[query_index + 'SQLQuery:'.len..].trim_space()
	}
	text = text.trim_right(';').trim_space()
	if text == '' || text.contains(';') {
		return error('SQL database chain requires exactly one read-only SQL statement')
	}
	first_word := text.split_any(' \t\n')[0].to_lower()
	if first_word !in ['select', 'with'] {
		return error('SQL database chain only executes read-only SELECT or WITH queries')
	}
	return text
}
