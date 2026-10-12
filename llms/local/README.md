# Local executable model

`local.new_client` starts an explicitly selected executable with literal
arguments. The binary path comes from `Options.bin_path` or
`LOCAL_LLM_BIN`; fixed arguments come from `Options.args` or
`LOCAL_LLM_ARGS`. Environment arguments are split on spaces and are not parsed
by a shell. The prompt is appended as the final argument. `new_default_client`
uses those environment variables.

The adapter accepts one text part from the first message and implements both
`llms.Model` and `llms.CompletionModel`. When `global_as_args` is enabled, it
translates temperature, top-p, top-k, min/max length, repetition penalty, and a
nonzero seed into command-line flags. Each call starts from the original fixed
arguments, so flags do not accumulate across requests.

Prompt size defaults to 64 KiB, total command arguments to 64 KiB, and combined
stdout/stderr output to 1 MiB. Configurable limits have hard caps of 64 KiB,
1 MiB, and 4 MiB respectively. Arguments never pass through a shell. The
process is launched in its own group; cancellation kills the group and reaps
the process. Supply a context with a deadline when generation must have a time
limit. This adapter does not download models or impose CPU/RAM limits on a
binary; select and configure the executable deliberately. Tests use only small
system utilities such as `echo`, `sh`, and `head`.
