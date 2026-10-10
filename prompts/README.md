# Prompts

StringTemplate formats {name} placeholders and supports doubled braces for
literal braces. It validates malformed templates and reports missing values.

ChatPromptTemplate combines ordered role-tagged text templates, reports their
unique input variables in first-seen order, and renders schema.Message values.
Chat templates are text-only; multimodal templates, alternate template
languages, and dynamic example selectors remain unimplemented.

FewShotPromptTemplate formats fixed string examples between an optional prefix
and suffix. It validates example variables when constructed and renders caller
variables in the prefix/suffix. Dynamic example selectors are not implemented.
