// Package tools defines the common contract for executable agent tools.
module tools

import context
import json2

// ToolSpec is the provider-neutral description exposed to a model.
pub struct ToolSpec {
pub:
	name        string
	description string
	parameters  json2.Any
}

// Tool is an action an agent can invoke by name with JSON input.
pub interface Tool {
	spec() ToolSpec
	call(mut ctx context.Context, input string) !string
}
