---
layout: default
title: Get started
permalink: /getting-started/
---

# Get started

## Requirements

- V 0.5.2 or newer.
- Git and network access for installing the module.

## Install the module

```sh
v install ulises-jeremias.langchainv
```

V imports the module using underscores:

```v
import ulises_jeremias.langchainv.textsplitter
```

## Run your first example

Clone the repository, then compile and run the offline text-splitting example:

```sh
git clone https://github.com/ulises-jeremias/langchainv.git
cd langchainv
v run examples/text_splitter/main.v
```

The example needs no API key and makes no network calls. It shows recursive character splitting and Markdown-aware chunking. Chunk boundaries prefer paragraphs, lines and words, with a Unicode-aware fallback.

## Create your own splitter

```v
module main

import ulises_jeremias.langchainv.textsplitter

fn main() {
	text := 'First paragraph.\n\nSecond paragraph with more detail.'
	splitter := textsplitter.new_recursive_character_text_splitter(
		chunk_size:    32
		chunk_overlap: 6
	) or { panic(err) }
	for chunk in splitter.split_text(text) or { panic(err) } {
		println(chunk)
	}
}
```

## Where to go next

- [Tutorials](../tutorials/) for the learning sequence and component recipes.
- [Component map](../components/) to select a package.
- [Text splitter reference](https://github.com/ulises-jeremias/langchainv/blob/main/textsplitter/README.md) for limits, tokenizer injection and Markdown behavior.
- [Safe development and CI](https://github.com/ulises-jeremias/langchainv/blob/main/CONTRIBUTING.md) for validation rules. V commands in this workstation should use the repository's safe-command instructions; hosted CI runs V directly with bounded parallelism.
