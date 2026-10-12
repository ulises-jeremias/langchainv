---
layout: default
title: Build LLM applications in V
layout_class: home
---

<section class="hero">
  <div class="eyebrow">Composable · V-native · Explicit</div>
  <h1>Build language model applications with V.</h1>
  <p>Compose models, prompts, tools, memory, retrieval and vector stores with bounded I/O, injectable transports and clear capability limits.</p>
  <div class="actions"><a class="button primary" href="{{ '/getting-started/' | relative_url }}">Start building</a><a class="button" href="{{ '/tutorials/' | relative_url }}">Explore tutorials</a></div>
</section>

## Choose a path

<div class="grid">
  <article class="card"><h3>New to LangChainV</h3><p>Install the module and run a dependency-free text splitting example.</p><a href="{{ '/getting-started/' | relative_url }}">Quick start →</a></article>
  <article class="card"><h3>Learn by building</h3><p>Follow the tutorials from prompts and models to retrieval and production checks.</p><a href="{{ '/tutorials/' | relative_url }}">Tutorial track →</a></article>
  <article class="card"><h3>Find a component</h3><p>Browse package responsibilities and their focused reference documentation.</p><a href="{{ '/components/' | relative_url }}">Component map →</a></article>
  <article class="card"><h3>Check compatibility</h3><p>See what is implemented, partial, verified, or still outstanding.</p><a href="{{ '/reference/' | relative_url }}">Parity and project status →</a></article>
</div>

## Design principles

- **Explicit boundaries:** unsupported provider options return errors instead of being silently ignored.
- **Bounded work:** network payloads, outputs, batches and iterative agents expose limits.
- **Offline-first tests:** provider clients accept injectable transports; CI uses deterministic fixtures rather than live credentials.
- **Honest compatibility:** the [parity ledger]({{ '/reference/' | relative_url }}) tracks scope and remaining gaps.

## Current project status

LangChainV is under active development. Provider integrations and framework components have different capability levels; check the parity ledger and each component guide before relying on a feature in production.
