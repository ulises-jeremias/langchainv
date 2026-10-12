# LLM model contract tests

`llmtest.test_model` checks the shared `llms.Model` response contract and
canceled-context behavior. Optional capability names check `multiturn`,
`streaming`, `tools`, and `usage` behavior.

The helper invokes the supplied model, including calls with a canceled context.
Use it only when those calls are appropriate for the model under test; live
providers may incur network cost. Package tests use deterministic fake models
and make no provider requests.
