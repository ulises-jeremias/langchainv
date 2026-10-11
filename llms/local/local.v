// Package local runs an explicitly configured local language-model executable.
module local

import context
import os
import strconv
import time
import ulises_jeremias.langchainv.callbacks
import ulises_jeremias.langchainv.llms
import ulises_jeremias.langchainv.schema

const env_bin = 'LOCAL_LLM_BIN'
const env_args = 'LOCAL_LLM_ARGS'
const default_max_prompt_bytes = 64 * 1024
const default_max_argument_bytes = 64 * 1024
const default_max_output_bytes = 1024 * 1024
const hard_max_argument_bytes = 1024 * 1024
const hard_max_output_bytes = 4 * 1024 * 1024
const max_fixed_arguments = 256
const max_command_arguments = 264

// Options configures the executable, fixed arguments, and bounded input/output sizes.
pub struct Options {
pub:
	bin_path           string
	args               []string
	global_as_args     bool
	max_prompt_bytes   int = default_max_prompt_bytes
	max_argument_bytes int = default_max_argument_bytes
	max_output_bytes   int = default_max_output_bytes
}

// Client implements completion and chat-model contracts using a local process.
pub struct Client {
	bin_path       string
	args           []string
	global_as_args bool
	max_prompt     int
	max_argument   int
	max_output     int
pub mut:
	callbacks ?callbacks.Handler
}

// new_client validates the executable and bounded process settings.
pub fn new_client(options Options) !Client {
	configured_bin := if options.bin_path.trim_space() == '' {
		os.getenv(env_bin)
	} else {
		options.bin_path.trim_space()
	}
	if configured_bin == '' {
		return error('local LLM binary is required; set Options.bin_path or ${env_bin}')
	}
	if configured_bin.len > 4096 {
		return error('local LLM binary path exceeds 4096 bytes')
	}
	if options.max_prompt_bytes < 1 || options.max_prompt_bytes > default_max_argument_bytes {
		return error('local LLM prompt limit must be between 1 byte and 64 KiB')
	}
	if options.max_argument_bytes < 1 || options.max_argument_bytes > hard_max_argument_bytes {
		return error('local LLM argument limit must be between 1 byte and 1 MiB')
	}
	if options.max_output_bytes < 1 || options.max_output_bytes > hard_max_output_bytes {
		return error('local LLM output limit must be between 1 byte and 4 MiB')
	}
	bin_path := os.find_abs_path_of_executable(configured_bin) or {
		return error('local LLM binary was not found or is not executable')
	}
	mut args := options.args.clone()
	if args.len == 0 {
		args = os.getenv(env_args).split(' ').filter(it != '')
	}
	mut argument_bytes := 0
	for argument in args {
		if argument.contains('\0') {
			return error('local LLM arguments must not contain NUL bytes')
		}
		argument_bytes += argument.len
	}
	if args.len > max_fixed_arguments || argument_bytes > options.max_argument_bytes {
		return error('local LLM arguments exceed the configured limit')
	}
	return Client{
		bin_path:       bin_path
		args:           args
		global_as_args: options.global_as_args
		max_prompt:     options.max_prompt_bytes
		max_argument:   options.max_argument_bytes
		max_output:     options.max_output_bytes
	}
}

// new_default_client loads the executable and fixed arguments from the upstream-compatible environment variables.
pub fn new_default_client() !Client {
	return new_client(Options{})
}

// complete runs the executable with a prompt as its final literal argument.
pub fn (mut client Client) complete(mut ctx context.Context, prompt string, options llms.CallOptions) !string {
	response := client.generate_content(mut ctx, [schema.text_message(.human, prompt)], options)!
	if response.choices.len == 0 {
		return error('local LLM returned no completion choices')
	}
	return response.choices[0].content
}

// generate_content runs the configured binary for the first text message.
pub fn (mut client Client) generate_content(mut ctx context.Context, messages []schema.Message, options llms.CallOptions) !llms.Response {
	options.validate()!
	llms.validate_messages(messages)!
	ctx_error := ctx.err()
	if ctx_error !is none {
		return ctx_error
	}
	message := messages[0]
	if message.parts.len != 1 {
		return error('local LLM accepts exactly one text content part in the first message')
	}
	part := message.parts[0]
	prompt := match part {
		schema.TextPart { part.text }
		else {
			return error('local LLM accepts exactly one text content part in the first message')
		}
	}
	return client.generate_prompt(mut ctx, prompt, messages, options)
}

fn (mut client Client) generate_prompt(mut ctx context.Context, prompt string, messages []schema.Message, options llms.CallOptions) !llms.Response {
	if prompt.len > client.max_prompt {
		return error('local LLM prompt exceeds ${client.max_prompt} bytes')
	}
	if prompt.contains('\0') {
		return error('local LLM prompt must not contain NUL bytes')
	}
	if mut handler := client.callbacks {
		handler.llm_generate_content_start(mut ctx, messages)
	}
	mut args := client.args.clone()
	if client.global_as_args {
		append_global_args(mut args, options)
	}
	args << prompt
	mut argument_bytes := 0
	for argument in args {
		argument_bytes += argument.len
	}
	if args.len > max_command_arguments || argument_bytes > client.max_argument {
		return error('local LLM command arguments exceed ${client.max_argument} bytes')
	}
	output := run_process(mut ctx, client.bin_path, args, client.max_output)!
	response := llms.Response{
		choices: [llms.Choice{
			content: output
		}]
	}
	if mut handler := client.callbacks {
		handler.llm_generate_content_end(mut ctx, response)
	}
	return response
}

fn append_global_args(mut args []string, options llms.CallOptions) {
	if options.temperature != 0 {
		args << '--temperature=${strconv.f64_to_str_lnd1(options.temperature, 6)}'
	}
	if options.top_p != 0 {
		args << '--top_p=${strconv.f64_to_str_lnd1(options.top_p, 6)}'
	}
	if options.top_k != 0 {
		args << '--top_k=${options.top_k}'
	}
	if options.min_length != 0 {
		args << '--min_length=${options.min_length}'
	}
	if options.max_length != 0 {
		args << '--max_length=${options.max_length}'
	}
	if options.repetition_penalty != 0 {
		args << '--repetition_penalty=${strconv.f64_to_str_lnd1(options.repetition_penalty, 6)}'
	}
	if seed := options.seed {
		if seed != 0 {
			args << '--seed=${seed}'
		}
	}
}

fn run_process(mut ctx context.Context, bin_path string, args []string, max_output int) !string {
	mut process := os.new_process(bin_path)
	process.set_args(args)
	process.use_pgroup = true
	process.set_redirect_stdio()
	process.run()
	if process.err != '' {
		process.close()
		return error('could not start local LLM process')
	}
	mut output := &CapturedOutputState{}
	for process.is_alive() {
		ctx_error := ctx.err()
		if ctx_error !is none {
			process.signal_pgkill()
			process.wait()
			process.close()
			return ctx_error
		}
		read_process_output(mut process, mut output, max_output) or {
			process.signal_pgkill()
			process.wait()
			process.close()
			return err
		}
		time.sleep(10 * time.millisecond)
	}
	process.wait()
	for {
		previous_output_bytes := output.output_bytes
		read_process_output(mut process, mut output, max_output) or {
			process.close()
			return err
		}
		if output.output_bytes == previous_output_bytes {
			break
		}
	}
	status := process.code
	process.close()
	if status != 0 {
		return error('local LLM process exited with status ${status}')
	}
	return output.stdout
}

struct CapturedOutputState {
mut:
	stdout       string
	output_bytes int
}

fn read_process_output(mut process os.Process, mut output &CapturedOutputState, max_output int) ! {
	for {
		mut read_any := false
		if chunk := process.pipe_read(.stdout) {
			read_any = true
			output.output_bytes += chunk.len
			if output.output_bytes > max_output {
				return error('local LLM process output exceeds ${max_output} bytes')
			}
			output.stdout += chunk
		}
		if chunk := process.pipe_read(.stderr) {
			read_any = true
			output.output_bytes += chunk.len
			if output.output_bytes > max_output {
				return error('local LLM process output exceeds ${max_output} bytes')
			}
		}
		if !read_any {
			break
		}
	}
}
