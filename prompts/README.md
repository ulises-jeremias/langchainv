# Prompts

StringTemplate formats {name} placeholders and supports doubled braces for
literal braces. It validates malformed templates and reports missing values.

`Template` adds a format choice on top of the same named values. The
`.f_string` format is the StringTemplate syntax. The `.go_template` format
accepts `{{ .name }}` actions, including `{{-` and `-}}` whitespace-trim
markers. The `.jinja2` format accepts `{{ name }}` variable actions.
Pipelines, filters, control statements, and field access are rejected in
both alternate formats; there are no loops or conditionals. Missing values
and malformed actions fail with an error.

ChatPromptTemplate combines ordered role-tagged text templates, reports their
unique input variables in first-seen order, and renders schema.Message values.
Chat templates use the f-string syntax. `ChatPromptTemplate` stays
text-only; `MultimodalPromptTemplate` renders text and image URL part
templates into typed message parts. Binary parts are built directly as
`schema.BinaryPart` values, not through string templates.

FewShotPromptTemplate formats fixed string examples between an optional prefix
and suffix. It validates example variables when constructed and renders caller
variables in the prefix/suffix. It can also use an injected ExampleSelector;
the package does not include a built-in selector.
