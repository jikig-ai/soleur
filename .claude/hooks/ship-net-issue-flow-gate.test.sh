#!/usr/bin/env bash
# Test: .claude/hooks/ship-net-issue-flow-gate.sh
#
# Mutation-proof discipline (#6727). The hook delegates all counting to
# net-issue-flow.sh, so this suite pins the HOOK's own contract: which commands
# it fires on, which it ignores, and that a deny is well-formed JSON.
#
# The delegated script is stubbed via a fake PROJECT_DIR whose gate script exits
# with a controlled code — the seam is the delegation boundary, which is exactly
# what this hook owns.

set -uo pipefail
export LC_ALL=C

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ship-net-issue-flow-gate.sh"

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

[[ -x "$HOOK" ]] || { printf 'FAIL: hook missing/not executable: %s\n' "$HOOK" >&2; exit 1; }

WORK="$(mktemp -d -t net-flow-hook.XXXXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# Fake project dir holding a stub gate script whose exit code we control.
mk_project() {
  # NOTE: split declarations. `local a=$1 b=$a` marks BOTH names local (and
  # unset) before evaluating b's RHS, so `$a` reads as unset under `set -u`.
  local rc="$1"
  local d="$WORK/proj-$rc"
  mkdir -p "$d/plugins/soleur/skills/ship/scripts"
  cat > "$d/plugins/soleur/skills/ship/scripts/net-issue-flow.sh" <<STUB
#!/usr/bin/env bash
echo "PR #999 net-issue-flow:"
echo "  Net:     +3  (positive = backlog growth)"
exit $rc
STUB
  chmod +x "$d/plugins/soleur/skills/ship/scripts/net-issue-flow.sh"
  printf '%s' "$d"
}
PROJ_DENY="$(mk_project 1)"
PROJ_PASS="$(mk_project 0)"

run_hook() { # $1=project dir, $2=command, [$3=extra env assignment]
  local proj="$1" cmd="$2" extra="${3:-}"
  printf '{"tool_input":{"command":%s},"cwd":"/tmp"}\n' "$(jq -Rn --arg c "$cmd" '$c')" \
    | ( export CLAUDE_PROJECT_DIR="$proj"; [[ -n "$extra" ]] && export "${extra?}"; bash "$HOOK" ) \
      > "$WORK/out" 2>"$WORK/err"
  HOOK_RC=$?
}

is_deny() { jq -e '.hookSpecificOutput.permissionDecision == "deny"' < "$WORK/out" >/dev/null 2>&1; }

# --- Commands that MUST be gated -------------------------------------------
for cmd in \
  "gh pr ready" \
  "gh pr ready 123" \
  "gh pr merge --auto --squash" \
  "gh pr merge 123 --squash" \
  "gh pr merge --admin" \
  "git push && gh pr ready"
do
  run_hook "$PROJ_DENY" "$cmd"
  if is_deny; then pass "DENY on: $cmd"
  else fail "should deny: $cmd (rc=$HOOK_RC out=$(tr -d '\n' < "$WORK/out"))"; fi
done

# --squash / --admin are the two the soak gate's `merge .*--auto` regex misses.
# If someone narrows the regex back, the two cases above go red.

# --- Commands that MUST NOT be gated ---------------------------------------
for cmd in \
  "gh pr view 123" \
  "gh pr list" \
  "gh pr create --draft" \
  "gh issue create --title x" \
  "echo gh pr merge"
do
  run_hook "$PROJ_DENY" "$cmd"
  if is_deny; then fail "should NOT deny: $cmd"
  else pass "ignores: $cmd"; fi
done

# --- Delegation contract ----------------------------------------------------
run_hook "$PROJ_PASS" "gh pr ready"
if is_deny; then fail "must not deny when delegated script exits 0"
else pass "delegated exit 0 -> no deny"; fi

run_hook "$PROJ_DENY" "gh pr ready" "SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1"
if is_deny; then fail "env skip must bypass the gate"
else pass "SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1 bypasses"; fi

# Missing gate script -> fail open (infrastructure gap is not a policy verdict).
mkdir -p "$WORK/proj-empty"
run_hook "$WORK/proj-empty" "gh pr ready"
if is_deny; then fail "missing gate script must fail open"
else pass "missing gate script fails open"; fi

# --- Deny payload shape -----------------------------------------------------
run_hook "$PROJ_DENY" "gh pr ready"
if [[ "$HOOK_RC" -eq 0 ]]; then pass "deny still exits 0 (hook protocol)"
else fail "hook must exit 0 even when denying; got $HOOK_RC"; fi
if jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' < "$WORK/out" >/dev/null 2>&1; then
  pass "deny payload carries hookEventName=PreToolUse"
else fail "deny payload missing hookEventName"; fi
reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' < "$WORK/out")"
for needle in "Fix inline" "Close something" "Override" "gate-override: net-issue-flow"; do
  if [[ "$reason" == *"$needle"* ]]; then pass "deny reason offers remedy: $needle"
  else fail "deny reason missing remedy: $needle"; fi
done
if [[ "$reason" == *"Net:     +3"* ]]; then pass "deny reason embeds the delegated script's output"
else fail "deny reason must embed delegated output"; fi

# --- .cwd is honored (review finding: real bypass) --------------------------
# The delegated script resolves the PR from the process cwd via `gh pr view`.
# If the hook ignores payload .cwd, a session whose cwd is the main checkout
# resolves NO PR for a feature-branch merge, fails open, and never blocks --
# the exact bypass class this gate exists to close.
#
# Seam: a stub gate that records its own $PWD. The assertion is that the
# recorded cwd equals the payload .cwd, not the hook's inherited cwd.
CWD_PROBE="$WORK/cwd-probe"
mkdir -p "$CWD_PROBE/plugins/soleur/skills/ship/scripts"
PAYLOAD_CWD="$WORK/payload-cwd"; mkdir -p "$PAYLOAD_CWD"
cat > "$CWD_PROBE/plugins/soleur/skills/ship/scripts/net-issue-flow.sh" <<PROBE
#!/usr/bin/env bash
pwd > "$WORK/recorded-cwd"
exit 0
PROBE
chmod +x "$CWD_PROBE/plugins/soleur/skills/ship/scripts/net-issue-flow.sh"

rm -f "$WORK/recorded-cwd"
printf '{"tool_input":{"command":"gh pr ready"},"cwd":"%s"}\n' "$PAYLOAD_CWD" \
  | ( export CLAUDE_PROJECT_DIR="$CWD_PROBE"; cd /; bash "$HOOK" ) >/dev/null 2>&1
recorded="$(cat "$WORK/recorded-cwd" 2>/dev/null || echo MISSING)"
if [[ "$recorded" == "$PAYLOAD_CWD" ]]; then
  pass "hook cds into payload .cwd before delegating"
else
  fail "hook must cd into payload .cwd; delegated ran in '$recorded' (expected '$PAYLOAD_CWD')"
fi

# A non-absolute / nonexistent .cwd must not wedge the hook (fail-open).
rm -f "$WORK/recorded-cwd"
printf '{"tool_input":{"command":"gh pr ready"},"cwd":"/nonexistent-%s"}\n' "$$" \
  | ( export CLAUDE_PROJECT_DIR="$CWD_PROBE"; bash "$HOOK" ) >"$WORK/out" 2>&1
if is_deny; then fail "bad .cwd must not produce a deny"
else pass "nonexistent .cwd falls back without denying"; fi

# ---------------------------------------------------------------------------
# FR0 — the timeout budget. Measured on the unmodified gate: 5.7-8.1 s wall
# clock against a `timeout 8` ceiling, with 1 of 3 plan-phase runs returning
# rc=124. Because the hook translates any RC != 1 to `exit 0`, a timeout is a
# SILENT always-pass: no deny, no telemetry, indistinguishable from a real
# pass. All three cases below are BEHAVIORAL — they drive the hook and read
# its decision, never grep its source — so each one names a mutation that
# satisfies a source-grep while violating the property.
# ---------------------------------------------------------------------------

# Stub project whose gate sleeps, so the hook's own ceiling is what decides.
mk_slow_project() { # $1=sleep seconds, $2=exit code
  local secs="$1" rc="$2"
  local d="$WORK/proj-slow-$secs-$rc"
  mkdir -p "$d/plugins/soleur/skills/ship/scripts"
  cat > "$d/plugins/soleur/skills/ship/scripts/net-issue-flow.sh" <<STUB
#!/usr/bin/env bash
sleep $secs
echo "  Net:     +3  (positive = backlog growth)"
exit $rc
STUB
  chmod +x "$d/plugins/soleur/skills/ship/scripts/net-issue-flow.sh"
  printf '%s' "$d"
}

# --- FR0b: a timed-out delegation must EMIT TELEMETRY, not vanish -----------
# Seam: a stub exiting 124 is indistinguishable at the hook's decision point
# from `timeout` killing a real gate — timeout propagates its own 124, and the
# hook branches on `$?` either way.
# Mutation that satisfies a source-grep but violates the property: emitting the
# row AFTER `[[ "$RC" -eq 1 ]] || exit 0` — the line is present in the file and
# never reached. This case reads the incident file, so it reds on that mutation.
PROJ_124="$(mk_project 124)"
INC_ROOT="$WORK/inc-124"; mkdir -p "$INC_ROOT"
printf '{"tool_input":{"command":"gh pr ready"},"cwd":"/tmp"}\n' \
  | ( export CLAUDE_PROJECT_DIR="$PROJ_124" INCIDENTS_REPO_ROOT="$INC_ROOT"; bash "$HOOK" ) \
    > "$WORK/out" 2>/dev/null
if is_deny; then fail "RC=124 must fail OPEN (a timeout is not a policy verdict)"
else pass "RC=124 fails open (no deny)"; fi

inc_file="$INC_ROOT/.claude/.rule-incidents.jsonl"
warn_rows=0
if [[ -r "$inc_file" ]]; then
  warn_rows="$(jq -sr '[.[] | select(.rule_id == "net-issue-flow" and .event_type == "warn")] | length' \
    < "$inc_file" 2>/dev/null || echo 0)"
fi
if [[ "$warn_rows" -ge 1 ]]; then pass "RC=124 emits a counted warn row (not a silent pass)"
else fail "RC=124 must emit rule_id=net-issue-flow event_type=warn; got $warn_rows rows"; fi

# A NON-timeout pass (RC=0) must NOT emit a timeout warn — otherwise the row
# above is vacuous (it would fire on every invocation and prove nothing).
INC_ROOT_OK="$WORK/inc-ok"; mkdir -p "$INC_ROOT_OK"
printf '{"tool_input":{"command":"gh pr ready"},"cwd":"/tmp"}\n' \
  | ( export CLAUDE_PROJECT_DIR="$PROJ_PASS" INCIDENTS_REPO_ROOT="$INC_ROOT_OK"; bash "$HOOK" ) \
    > /dev/null 2>&1
ok_warns=0
if [[ -r "$INC_ROOT_OK/.claude/.rule-incidents.jsonl" ]]; then
  ok_warns="$(jq -sr '[.[] | select(.rule_id == "net-issue-flow" and .event_type == "warn")] | length' \
    < "$INC_ROOT_OK/.claude/.rule-incidents.jsonl" 2>/dev/null || echo 0)"
fi
if [[ "$ok_warns" -eq 0 ]]; then pass "a clean pass emits NO timeout warn (the 124 row is discriminating)"
else fail "RC=0 must not emit a timeout warn; got $ok_warns"; fi

# --- FR0a(i): the ceiling must clear the gate's real cost -------------------
# The unmodified gate measures 5.7-8.1 s. A 9 s stub exceeds the old `timeout 8`
# and clears a 25 s one, so this case alone distinguishes the two ceilings.
# Mutation that a source-grep would miss: reverting the literal to `timeout 8`
# while leaving the TO=() probe shape intact.
PROJ_SLOW="$(mk_slow_project 9 1)"
printf '{"tool_input":{"command":"gh pr ready"},"cwd":"/tmp"}\n' \
  | ( export CLAUDE_PROJECT_DIR="$PROJ_SLOW"; bash "$HOOK" ) > "$WORK/out" 2>/dev/null
if is_deny; then pass "a 9 s gate still DENIES (ceiling clears the measured cost)"
else fail "9 s gate was killed by the ceiling -> silent always-pass (raise the timeout)"; fi

# --- FR0a(ii): `timeout(1)` absent must not become a dark tripwire ----------
# A hardcoded `timeout 25 bash "$GATE"` on a host without timeout(1) yields
# RC=127, which the hook translates to `exit 0` — a blocking gate that never
# blocks, with nothing in the output naming the cause. The repo's precedent
# (supabase-loopback-warn.sh) probes with TO=() instead.
# Mutation that satisfies a `grep -q 'timeout 25'` source assertion while
# violating the property: keeping the hardcoded invocation. This case reds on it.
# NOTE: `b="${f##*/}"`, never `basename "$f"` — the PATH mirror is ~7k entries
# and a per-entry fork turns this case into a multi-minute hang (measured).
NOTO="$WORK/noto-bin"; mkdir -p "$NOTO"
for d in $(printf '%s\n' "${PATH//:/$'\n'}" | sort -u); do
  [[ -d "$d" ]] || continue
  for f in "$d"/*; do
    [[ -e "$f" ]] || continue
    b="${f##*/}"
    [[ "$b" == "timeout" ]] && continue
    [[ -e "$NOTO/$b" ]] || ln -s "$f" "$NOTO/$b" 2>/dev/null || true
  done
done
# Precondition self-check: the fixture is only meaningful if `timeout` is
# genuinely unreachable AND the interpreter is still reachable. A silently
# broken mirror would make the assertion below pass for the wrong reason.
if PATH="$NOTO" command -v timeout >/dev/null 2>&1; then
  fail "FIXTURE BROKEN: timeout still resolvable on the stripped PATH"
elif ! PATH="$NOTO" command -v bash >/dev/null 2>&1; then
  fail "FIXTURE BROKEN: bash not resolvable on the stripped PATH"
else
  pass "fixture: PATH without timeout(1) built (bash reachable, timeout not)"
  printf '{"tool_input":{"command":"gh pr ready"},"cwd":"/tmp"}\n' \
    | ( export CLAUDE_PROJECT_DIR="$PROJ_DENY" PATH="$NOTO"; bash "$HOOK" ) \
      > "$WORK/out" 2>/dev/null
  if is_deny; then pass "no timeout(1) on PATH still DENIES (probe, not hardcode)"
  else fail "missing timeout(1) produced rc=127 -> silent fail-open (use the TO=() probe)"; fi
fi

printf '\n'
if [[ "$fails" -eq 0 ]]; then
  printf 'ship-net-issue-flow-gate.test.sh: ALL PASS\n'; exit 0
fi
printf 'ship-net-issue-flow-gate.test.sh: %d FAILED\n' "$fails"
exit 1
