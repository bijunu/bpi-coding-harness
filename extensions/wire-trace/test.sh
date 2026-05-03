#!/usr/bin/env bash
#
# Smoke test for the wire-trace extension.
#
# Runs pi against its real provider (so it consumes API tokens — pennies for
# these prompts) with PI_WIRE_TRACE_PATH pointed at a tempfile so the suite
# never touches your real ~/.pi/agent/wire-trace.jsonl.
#
# Exits 0 if all checks pass, non-zero on the first failure. Prints a clear
# pass/fail line per check.

set -euo pipefail

# Where this test lives, so we can `cd` to the repo root reliably.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

TRACE="$(mktemp -t wt-trace.XXXXXX.jsonl)"
ERR="$(mktemp -t wt-err.XXXXXX)"
JSON_OUT="$(mktemp -t wt-json.XXXXXX)"
trap 'rm -f "$TRACE" "$ERR" "$JSON_OUT"' EXIT

export PI_WIRE_TRACE_PATH="$TRACE"

pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n  %s\n" "$1" "$2"; exit 1; }

echo "== wire-trace smoke test =="
echo "    repo:  $REPO_ROOT"
echo "    trace: $TRACE"
echo

# ---- 1. Basic load + single-turn run ------------------------------------
echo "1) extension loads and writes a paired record"
: > "$TRACE"
pi -p "say hi" --no-session > /dev/null 2> "$ERR" \
    || fail "1.0 pi exited non-zero" "$(cat "$ERR")"

grep -q "\[wire-trace\] enabled, logging to $TRACE" "$ERR" \
    || fail "1.1 missing enabled line" "$(cat "$ERR")"
pass "1.1 enabled line on stderr"

grep -q "\[wire-trace\] session .* turn 1 →" "$ERR" \
    || fail "1.2 missing session line" "$(cat "$ERR")"
pass "1.2 session announcement line"

REQ_COUNT=$(jq -c 'select(.type=="request")'  "$TRACE" | wc -l | tr -d ' ')
RES_COUNT=$(jq -c 'select(.type=="response")' "$TRACE" | wc -l | tr -d ' ')
[ "$REQ_COUNT" -ge 1 ] && [ "$REQ_COUNT" = "$RES_COUNT" ] \
    || fail "1.3 request/response counts mismatch" "req=$REQ_COUNT res=$RES_COUNT"
pass "1.3 request/response paired (req=$REQ_COUNT res=$RES_COUNT)"

# ---- 2. Pairing invariant: every seq has exactly one req and one res -----
echo
echo "2) pairing invariant"
jq -se '
  (group_by(.seq)
   | all(.[]; (map(.type) | sort) == ["request","response"]))
' "$TRACE" | grep -qx "true" \
    || fail "2.1 unpaired seq groups" "$(jq -s 'group_by(.seq)' "$TRACE")"
pass "2.1 every seq has exactly one request and one response"

# ---- 3. Payload + body shape --------------------------------------------
echo
echo "3) record shape"
# Slurp + all() so the check evaluates over every request record at once.
# Plain `jq -e 'select(...) | ...'` is unreliable here: jq -e looks at the
# last produced value, and `select` skips records (producing no output for
# them) which jq -e then treats as a failure.
jq -se '
  [.[] | select(.type=="request")]
  | length > 0
  and all(.[]; .payload | type == "object")
' "$TRACE" | grep -qx "true" \
    || fail "3.1 request.payload missing or not an object" \
             "$(jq -c 'select(.type=="request") | {payload_type: (.payload | type)}' "$TRACE")"
pass "3.1 every request has an object payload"

LAST_RES=$(jq -c 'select(.type=="response")' "$TRACE" | tail -1)
echo "$LAST_RES" | jq -e '
  .body.role == "assistant"
  and (.body.content | type == "array")
  and (.body.stopReason | type == "string")
  and (.body.usage | type == "object")
  and (.status | type == "number")
  and (.durationMs | type == "number")
' >/dev/null || fail "3.2 response shape" "$LAST_RES"
pass "3.2 response has body{role,content,stopReason,usage} + status + durationMs"

# ---- 4. Multi-turn: session line fires once, but multiple req/res pairs --
echo
echo "4) multi-turn session announces once"
: > "$TRACE"
pi -p "list files in this directory using bash, then count them" --no-session \
    > /dev/null 2> "$ERR" || fail "4.0 pi exited non-zero" "$(cat "$ERR")"

SESSION_LINES=$(grep -c "turn 1" "$ERR" || true)
[ "$SESSION_LINES" = "1" ] \
    || fail "4.1 expected 1 session line, got $SESSION_LINES" "$(grep wire-trace "$ERR")"
pass "4.1 session line fired exactly once"

TURNS=$(jq -c 'select(.type=="request")' "$TRACE" | wc -l | tr -d ' ')
[ "$TURNS" -ge 2 ] || fail "4.2 expected >=2 turns, got $TURNS" \
    "Prompt didn't trigger a multi-turn run; rerun or adjust prompt."
pass "4.2 multi-turn run produced $TURNS requests"

UNIQ_SESSIONS=$(jq -r '.sessionId // "<no-session>"' "$TRACE" | sort -u | wc -l | tr -d ' ')
[ "$UNIQ_SESSIONS" = "1" ] \
    || fail "4.3 expected 1 distinct sessionId, got $UNIQ_SESSIONS" ""
pass "4.3 all turns share one sessionId"

# ---- 5. PI_WIRE_TRACE_PATH override -------------------------------------
echo
echo "5) env override"
ALT="$(mktemp -t wt-alt.XXXXXX.jsonl)"
PI_WIRE_TRACE_PATH="$ALT" pi -p "hi" --no-session > /dev/null 2> "$ERR" \
    || fail "5.0 pi exited non-zero" "$(cat "$ERR")"
grep -q "logging to $ALT" "$ERR" \
    || fail "5.1 stderr did not reflect override path" "$(cat "$ERR")"
[ -s "$ALT" ] || fail "5.2 override path file is empty" ""
rm -f "$ALT"
pass "5.1 override path honored on stderr and on disk"

# ---- 6. JSON mode stdout stays clean ------------------------------------
echo
echo "6) --mode json stdout is clean"
pi --mode json -p "hi" --no-session 2>/dev/null > "$JSON_OUT" \
    || fail "6.0 pi exited non-zero" ""
head -1 "$JSON_OUT" | jq -e '.type == "session"' >/dev/null \
    || fail "6.1 first stdout line is not the session header" "$(head -1 "$JSON_OUT")"
pass "6.1 first line of --mode json stdout is the session event"

echo
echo "ALL PASS"
