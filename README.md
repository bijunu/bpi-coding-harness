# bpi-coding-harness

Hands-on study of the [Pi coding agent](https://github.com/badlogic/pi-mono) — instrumenting it to make the agent loop visible turn by turn.

## Project: Anatomy of a Coding Agent Turn

A visual walkthrough of what actually happens inside a coding agent harness: context construction, tool calls, compaction, and the extension model.

**Status:** in progress (sprint May 3-4, 2026).

## Components

- `extensions/wire-trace/` — Pi extension that captures provider request payloads and normalized response bodies.
- `skills/` — Skill demonstrating Pi's "extend without forking" model.
- `viewer/` — Single-page HTML viewer for trace data.
- `traces/` — Sample trace outputs (sample only; full traces ignored by .gitignore).

## Why Pi

Minimal, opinionated, multi-model coding harness. Designed to be extended via TypeScript extensions and Skills rather than forked. Source: https://github.com/badlogic/pi-mono.

## Acknowledgements

Built on [Pi](https://github.com/badlogic/pi-mono) by Mario Zechner.
