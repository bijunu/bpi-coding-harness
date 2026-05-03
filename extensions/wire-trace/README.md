# wire-trace

Pi extension that logs every provider request and response to a JSONL file. Closes the wire-level observability gap that `pi --mode json` leaves open.

## Output

Default: `~/.pi/agent/wire-trace.jsonl`. Override with `PI_WIRE_TRACE_PATH`.

Each line is one record:
- `{ ts, type: "request", seq, sessionId, cwd, model, payload }`
- `{ ts, type: "response", seq, sessionId, cwd, model, status, headers, durationMs, body }`

## What gets captured

**Request side:** the literal request body sent to the provider — system prompt, tool schemas, full message history post-`transformContext`, cache control markers. Faithful to the wire.

**Response side:** Pi's normalized reconstruction of the assistant message. Pi-ai unifies provider differences (Anthropic's `tool_use`, OpenAI's `tool_calls`, etc.) into a common shape. You see assembled content, not raw SSE chunks.

For literal HTTP bytes, use an HTTPS proxy (e.g. `mitmproxy` with `ANTHROPIC_BASE_URL` pointing at it). The extension API deliberately doesn't expose raw response bodies.

## Install

Drop into `~/.pi/agent/extensions/wire-trace.ts` (auto-discovered) or load explicitly:

```bash
pi -e ./extensions/wire-trace/index.ts
```

## Per-run isolation

```bash
PI_WIRE_TRACE_PATH=./traces/run-$(date +%s)/wire.jsonl pi "your task"
```
