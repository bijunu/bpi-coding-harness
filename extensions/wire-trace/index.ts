/**
 * wire-trace
 *
 * Logs every provider request payload and response (status, headers, body)
 * to a JSONL file at ~/.pi/agent/wire-trace.jsonl. Override location with
 * PI_WIRE_TRACE_PATH.
 *
 * Records:
 *   { ts, type: "request",  seq, sessionId, cwd, model, payload }
 *   { ts, type: "response", seq, sessionId, cwd, model, status, headers,
 *     durationMs, body }
 *
 * `seq` pairs a request with its response. Pairing assumes provider calls
 * do not overlap within a session, which holds for pi's agent loop (one
 * streaming call at a time).
 *
 * `body` is the assistant `AgentMessage` produced by pi's stream parser:
 *   { role, content[], stopReason, usage, model, provider, api, timestamp }
 * Captured at `message_end`, before tool execution and before any
 * transform on the next turn. This is the closest faithful capture
 * available to an extension; the literal HTTP body never reaches a hook.
 */

import { appendFileSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const LOG_PATH = process.env.PI_WIRE_TRACE_PATH ?? join(homedir(), ".pi", "agent", "wire-trace.jsonl");

mkdirSync(dirname(LOG_PATH), { recursive: true });

function append(record: Record<string, unknown>): void {
    try {
        appendFileSync(LOG_PATH, `${JSON.stringify(record)}\n`, "utf8");
    } catch {
        // Never throw from a hook; tracing must not break the agent loop.
    }
}

interface PendingResponse {
    seq: number;
    startedAt: number;
    base?: Record<string, unknown>; // filled by after_provider_response
}

export default function (pi: ExtensionAPI): void {
    let seq = 0;
    let pending: PendingResponse | undefined;
    // Track session IDs we've already announced so the per-session log
    // line fires once per session (not once per turn). Sessions can change
    // within a single process via /new, /resume, /fork, /clone.
    const announcedSessions = new Set<string>();

    // Visible on stderr at extension load. Goes to stderr (not stdout) so
    // it does not pollute --mode json output. Printed once per process.
    console.error(`[wire-trace] enabled, logging to ${LOG_PATH}`);

    const flush = (body: unknown, ctx: { sessionId: string | undefined; cwd: string; model: unknown }): void => {
        if (!pending) return;
        const record = {
            ts: new Date().toISOString(),
            type: "response",
            seq: pending.seq,
            sessionId: ctx.sessionId,
            cwd: ctx.cwd,
            model: ctx.model,
            durationMs: Date.now() - pending.startedAt,
            ...(pending.base ?? { status: undefined, headers: undefined }),
            body,
        };
        append(record);
        pending = undefined;
    };

    pi.on("before_provider_request", (event, ctx) => {
        // If a previous response never reached message_end (e.g. abort),
        // flush whatever we had so logs stay paired.
        if (pending) {
            flush(undefined, {
                sessionId: ctx.sessionManager.getSessionId(),
                cwd: ctx.cwd,
                model: undefined,
            });
        }

        seq += 1;
        pending = { seq, startedAt: Date.now() };

        const sessionId = ctx.sessionManager.getSessionId();
        const modelLabel = ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : "unknown";

        // One line per distinct session, on its first provider request.
        // Helps correlate this trace with the matching session.jsonl when
        // multiple runs share the same wire-trace.jsonl file.
        const sessionKey = sessionId ?? "<no-session>";
        if (!announcedSessions.has(sessionKey)) {
            announcedSessions.add(sessionKey);
            console.error(`[wire-trace] session ${sessionKey} turn 1 → ${modelLabel}`);
        }

        append({
            ts: new Date().toISOString(),
            type: "request",
            seq,
            sessionId,
            cwd: ctx.cwd,
            model: ctx.model
                ? { provider: ctx.model.provider, id: ctx.model.id, api: ctx.model.api }
                : undefined,
            payload: event.payload,
        });
        // Returning undefined => do not modify the payload.
    });

    pi.on("after_provider_response", (event, _ctx) => {
        if (!pending) return; // request hook didn't fire? skip
        pending.base = {
            status: event.status,
            headers: event.headers,
        };
        // Do NOT write yet. Wait for message_end to fill in body.
    });

    pi.on("message_end", (event, ctx) => {
        if (event.message.role !== "assistant") return;
        if (!pending) return; // not a response we're tracking

        flush(event.message, {
            sessionId: ctx.sessionManager.getSessionId(),
            cwd: ctx.cwd,
            model: ctx.model
                ? { provider: ctx.model.provider, id: ctx.model.id, api: ctx.model.api }
                : undefined,
        });
    });
}
