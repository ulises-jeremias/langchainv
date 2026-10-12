# LLM model contract tests

`llmtest.test_model` checks the shared `llms.Model` response contract and
canceled-context behavior. Optional capability names check `multiturn`,
`streaming`, `tools`, and `usage` behavior.

The helper invokes the supplied model, including calls with a canceled context.
Use it only when those calls are appropriate for the model under test; live
providers may incur network cost. Package tests use deterministic fake models
and make no provider requests.

`new_mock_model(response)` returns a reusable, concurrency-safe `llms.Model`
test double. Configure a response with `set_response`, configure a failure
with `set_error`, and inspect the number of attempts with `call_count`. It
copies response slices, nested JSON values, and multimodal content at the
configuration and call boundaries. An optional streaming callback receives
the first choice's text as one chunk. The mock makes no network requests.
