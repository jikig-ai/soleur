#!/usr/bin/env bash
# Contract tests for the PreToolUse hook input boundary (issue #7164).
#
# ADR-155 — hook stdin is model-controlled and untrusted; a hook must not depend
#           on an upstream invariant it cannot verify.
# ADR-156 — a hook that cannot fully parse its input ASKS. It never continues
#           silently and it never denies.
#
# A1 and A2 were authored and observed RED against the unmodified tree BEFORE
# the helper existed (plan Phase 2). A2 is the one that rejects a
# coerce-and-continue fix: coercing a non-string with `tojson` closes the RCE
# and leaves every anchored guard evaded, because ["git","stash"] matches no
# guard regex. Authoring it after the migration is the failure mode the hooks
# README documents for stub-argv-fidelity — a test that could never be seen
# fail.
#
# Pure bash + jq. The test-scripts CI shard has no bun and no node.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0
TOTAL=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }

ok()  { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); echo "FAIL: $1"; shift; local l; for l in "$@"; do echo "  $l"; done; }
want(){ if [[ "$2" == "$3" ]]; then ok "$1 → $3"; else bad "$1" "want: $2" "got:  $3"; fi; }

EVAL10=(
  cla-signed-author-gate context-reviewed-gate follow-through-directive-gate
  guardrails prod-write-defer-gate ship-net-issue-flow-gate
  ship-operator-step-gate ship-runbook-ssh-gate ship-soak-followthrough-gate
  ship-unpushed-commits-gate
)
SIBLING8=(
  background-poll-prefer-monitor brand-hex-commit-gate
  doppler-secrets-delete-redirect git-commit-secret-scan
  kb-domain-allowlist-guard no-memory-write
  pre-merge-auto-close-scan pre-merge-rebase
)
WRITE2=( worktree-write-guard iac-plan-write-guard )
INSCOPE20=( "${EVAL10[@]}" "${SIBLING8[@]}" "${WRITE2[@]}" )

# Run a hook from a NON-GIT temp CWD so the orthogonal, branch-dependent
# block-commit-on-main gate resolves an empty branch and no-ops. Without this
# these fixtures pass on a feature worktree and fail on main-CI (#5192).
# Echoes "<permissionDecision>" or "<none>" when the hook allows.
decision_for() { # <hook> <payload> [extra-env...]
  local hook="$1" payload="$2"; shift 2
  local tmp out
  tmp="$(mktemp -d -t hic.XXXXXXXX)"
  out="$(cd "$tmp" && printf '%s' "$payload" \
        | env INCIDENTS_REPO_ROOT="$tmp" "$@" bash "$SCRIPT_DIR/$hook.sh" 2>/dev/null)"
  rm -rf "$tmp"
  [[ -z "${out//[[:space:]]/}" ]] && { echo "<none>"; return; }
  echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "<none>"' 2>/dev/null || echo "<jq-fail>"
}

ARRAY_STASH="$(jq -nc '{tool_name:"Bash", tool_input:{command:["git","stash"]}}')"

# ===========================================================================
# A1 — idiom ban: ANY eval, not one spelling.
# ===========================================================================
# `eval "$(` misses `eval $(…)`, `eval "$V"` and `eval "${x}"`. Full-line
# comments are stripped first: hook headers legitimately discuss the word
# "eval" in prose and a body-grep sees comments too (cq-assert-anchor-not-
# bare-token). Allow-list is BY EXACT STRING — `eval "exec ${fd}>&-"` is the
# only portable way to close a dynamic fd in bash.
EVAL_ALLOW='eval "exec ${fd}>&-" 2>/dev/null || true'

a1_idiom_ban() {
  local offenders=() f line n stripped trimmed
  while IFS= read -r f; do
    [[ "$f" == *.test.sh ]] && continue
    stripped="$(sed 's/^[[:space:]]*#.*$//' "$f")"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      n="${line%%:*}"; line="${line#*:}"
      trimmed="${line#"${line%%[![:space:]]*}"}"
      [[ "$trimmed" == "$EVAL_ALLOW" && "$f" == */lib/session-state.sh ]] && continue
      offenders+=("${f#"$REPO_ROOT/"}:$n: $trimmed")
    done < <(printf '%s\n' "$stripped" | grep -nE '(^|[^[:alnum:]_])eval([[:space:]]|$)' || true)
  done < <(find "$REPO_ROOT/.claude/hooks" "$REPO_ROOT/.openhands/hooks" -name '*.sh' -type f 2>/dev/null | sort)

  if (( ${#offenders[@]} == 0 )); then
    ok "A1 no eval under .claude/hooks/** or .openhands/hooks/** (2 fd-close lines allow-listed)"
  else
    bad "A1 eval found in ${#offenders[@]} place(s) — hook stdin is untrusted (ADR-155)" "${offenders[@]}"
  fi
}

# ===========================================================================
# A2 — guard-still-armed. RED on main before the fix.
# ===========================================================================
a2_guard_still_armed() {
  want "A2 guardrails: array-encoded 'git stash' asks (never allow)" "ask" \
    "$(decision_for guardrails "$ARRAY_STASH")"
  # Positive control in the same run: proves the guard is intact and A2 is not
  # passing because the hook broke outright.
  want "A2 control: string 'git stash' still denies" "deny" \
    "$(decision_for guardrails "$(jq -nc '{tool_name:"Bash", tool_input:{command:"git stash"}}')")"
}

# ===========================================================================
# A3 — RCE regression across all 10, WITH A POSITIVE CONTROL.
# ===========================================================================
# A bare absence assertion passes if the payload was malformed, the path wrong,
# or stdin never arrived. The control pins a deliberately vulnerable stub
# carrying the ORIGINAL idiom and proves the harness can observe a marker.
a3_rce_regression() {
  local run stub marker hook payload pwned=()
  run="$(mktemp -d -t hicrce.XXXXXXXX)"

  # --- positive control: the harness CAN observe a marker -------------------
  stub="$run/vulnerable-stub.sh"
  cat > "$stub" <<'STUB'
#!/usr/bin/env bash
set -eo pipefail
INPUT=$(cat)
eval "$(echo "$INPUT" | jq -r '@sh "COMMAND=\(.tool_input.command // "")"' 2>/dev/null || echo 'COMMAND=""')"
: "${COMMAND:=}"
exit 0
STUB
  marker="$run/CONTROL-MARKER"
  payload="$(jq -nc --arg m "$marker" '{tool_name:"Bash",tool_input:{command:["x","touch",$m]}}')"
  ( cd "$run" && printf '%s' "$payload" | bash "$stub" >/dev/null 2>&1 )
  if [[ -e "$marker" ]]; then
    ok "A3 positive control: the pinned vulnerable stub DOES create the marker"
  else
    bad "A3 positive control FAILED — the harness cannot observe a marker" \
        "every absence assertion below is therefore vacuous"
  fi

  # --- the real assertion, all 10 ------------------------------------------
  for hook in "${EVAL10[@]}"; do
    marker="$run/PWNED-$hook"
    payload="$(jq -nc --arg m "$marker" '{tool_name:"Bash",tool_input:{command:["x","touch",$m]}}')"
    ( cd "$run" && printf '%s' "$payload" \
        | INCIDENTS_REPO_ROOT="$run" bash "$SCRIPT_DIR/$hook.sh" >/dev/null 2>&1 )
    [[ -e "$marker" ]] && pwned+=("$hook")
  done
  if (( ${#pwned[@]} == 0 )); then
    ok "A3 no attacker-named command executed by any of the ${#EVAL10[@]} migrated hooks"
  else
    bad "A3 RCE still reachable in ${#pwned[@]} hook(s)" "${pwned[@]}"
  fi

  # --- A12 stray artifacts: the trailing words must reach nothing -----------
  local strays
  strays="$(cd "$run" && ls -A1 | grep -vE '^(vulnerable-stub\.sh|CONTROL-MARKER|\.claude)$' || true)"
  if [[ -z "$strays" ]]; then
    ok "A12 no stray artifacts (no TOOL_NAME=/WORK_DIR=/FILE_PATH= files created)"
  else
    bad "A12 stray artifacts created by the payload's trailing words" $strays
  fi
  rm -rf "$run"
}

# ===========================================================================
# A4 — the cheap variants also ask.
# ===========================================================================
# A cheaper payload must not get a weaker posture.
a4_cheap_variants() {
  local py
  want "A4 non-object tool_input (string) asks" "ask" \
    "$(decision_for guardrails "$(jq -nc '{tool_name:"Bash", tool_input:"git stash"}')")"
  want "A4 non-object tool_input (array) asks" "ask" \
    "$(decision_for guardrails "$(jq -nc '{tool_input:["a"]}')")"
  want "A4 non-object root (array) asks" "ask" \
    "$(decision_for guardrails "$(jq -nc '["a"]')")"
  want "A4 non-object root (string) asks" "ask" \
    "$(decision_for guardrails "$(jq -nc '"oops"')")"
  want "A4 non-string cwd asks" "ask" \
    "$(decision_for guardrails "$(jq -nc '{tool_input:{command:"a"}, cwd:["/w"]}')")"
  want "A4 malformed document asks" "ask" \
    "$(decision_for guardrails 'garbage {{')"
  want "A4 empty stdin asks" "ask" \
    "$(decision_for guardrails '')"

  # Separator smuggled INTO a value: the program emits exactly 6 records, so a
  # forge raises the count and trips the mismatch. Desync is unreachable.
  if command -v python3 >/dev/null 2>&1; then
    py="$(python3 -c 'import json,sys; sys.stdout.write(json.dumps({"tool_input":{"command":"a\u001eb"},"cwd":"/w"}))')"
    want "A4 separator smuggled into a value asks" "ask" "$(decision_for guardrails "$py")"
    # Lone high surrogate, carrying a VALID escaped pair too: the emoji must not
    # be what makes it fail. Asserted to ask, NOT to be scrubbed-and-armed — a
    # scrubbed value no longer matches the guards (measured).
    py="$(python3 -c 'import sys; sys.stdout.write("{\"tool_input\":{\"command\":\"git \\ud800 stash \\ud83d\\udd25\"}}")')"
    want "A4 lone surrogate asks (not scrubbed-and-armed)" "ask" "$(decision_for guardrails "$py")"
  else
    echo "SKIP: python3 missing — separator/surrogate fixtures"
  fi
}

# ===========================================================================
# A5 — unusable jq: ask, built by printf, with NO jq fork.
# ===========================================================================
# Shim a NON-EXECUTABLE jq at the front of PATH, leaving the rest intact.
# PATH=/nonexistent would also remove grep, git, mktemp and flock, so the hook
# could not meaningfully run and the assertion would prove nothing.
a5_jq_unusable() {
  # `chmod 000 jq` does NOT work: `command -v` skips a non-executable file and
  # finds the real jq further along PATH, so the helper parses normally and the
  # test silently exercises the WRONG path (it reported `ask` for reason
  # `nonstring`, not `jq_missing`).
  #
  # Instead build a PATH that genuinely lacks jq but keeps everything else the
  # hook needs. PATH=/nonexistent would also remove grep, git, mktemp and flock,
  # so the hook could not run at all and the assertion would prove nothing.
  local shim tmp out dec reason b
  shim="$(mktemp -d -t hicjq.XXXXXXXX)"
  for b in bash sh env grep sed awk tr cat cut head tail sort uniq wc date \
           mkdir rm ln ls mktemp dirname basename realpath xargs flock \
           git perl python3 touch chmod find printf; do
    local src; src="$(command -v "$b" 2>/dev/null)" || continue
    [[ -n "$src" ]] && ln -sf "$src" "$shim/$b" 2>/dev/null
  done
  if [[ -e "$shim/jq" ]]; then rm -f "$shim/jq"; fi

  # Precondition self-check: if jq is still reachable the fixture is broken and
  # a pass below would be meaningless.
  if PATH="$shim" command -v jq >/dev/null 2>&1; then
    bad "A5 FIXTURE BROKEN — jq still reachable on the shim PATH" "assertion would be vacuous"
    rm -rf "$shim"; return
  fi

  tmp="$(mktemp -d -t hicjq2.XXXXXXXX)"
  out="$(cd "$tmp" && printf '%s' "$ARRAY_STASH" \
        | PATH="$shim" INCIDENTS_REPO_ROOT="$tmp" bash "$SCRIPT_DIR/guardrails.sh" 2>/dev/null)"
  # Parsed WITHOUT jq, deliberately: the envelope is a printf of a constant
  # template, which is the whole point — emit_incident builds its row with
  # `jq -nc`, so on this path the ask reason string is the only channel left.
  dec="$(printf '%s' "$out" | sed -n 's/.*"permissionDecision":"\([a-z]*\)".*/\1/p')"
  reason="$(printf '%s' "$out" | grep -c 'jq_missing' || true)"
  want "A5 unusable jq still asks (envelope built by printf, not jq -n)" "ask" "${dec:-<none>}"
  want "A5 the reason names jq_missing" "1" "$reason"
  rm -rf "$shim" "$tmp"
}

# ===========================================================================
# A6 — loud disarm, end to end. A5 of the plan.
# ===========================================================================
# Asserting a line landed in a file tests that a WRITE happened, not that anyone
# is told. This walks the row all the way to the aggregate counter.
a6_loud_disarm_end_to_end() {
  local root out
  root="$(mktemp -d -t hicld.XXXXXXXX)"
  mkdir -p "$root/.claude"
  cat > "$root/AGENTS.md" <<'EOF'
# Agent Instructions

## Hard Rules

- Synthetic fixture bullet for the hook-input contract test [id: hr-rule-a-synthetic-test].
EOF
  ( cd "$root" && printf '%s' "$ARRAY_STASH" \
      | INCIDENTS_REPO_ROOT="$root" bash "$SCRIPT_DIR/guardrails.sh" >/dev/null 2>&1 )

  local jsonl="$root/.claude/.rule-incidents.jsonl"
  if [[ -f "$jsonl" ]]; then
    ok "A6 incident row written under INCIDENTS_REPO_ROOT"
    want "A6 rule_id carries the reason" "hook-input-nonstring" \
      "$(jq -r 'select(.kind=="hook_self_fault") | .rule_id' < "$jsonl" | head -1)"
    want "A6 kind is hook_self_fault" "hook_self_fault" \
      "$(jq -r '.kind' < "$jsonl" | head -1)"
    # A7 — no payload content anywhere in the row.
    local snip leaked=no
    snip="$(jq -r '.command_snippet' < "$jsonl" | head -1)"
    [[ "$snip" == *stash* || "$snip" == *git* ]] && leaked=yes
    want "A7 no payload content in command_snippet" "no" "$leaked"
  else
    bad "A6 no incident row written — the disarm is silent (defect 2)"
  fi

  # The worktree ledger must be untouched.
  if [[ -f "$REPO_ROOT/.claude/.rule-incidents.jsonl" ]]; then
    local before after
    before="$(wc -c < "$REPO_ROOT/.claude/.rule-incidents.jsonl")"
    ( cd "$root" && printf '%s' "$ARRAY_STASH" | INCIDENTS_REPO_ROOT="$root" bash "$SCRIPT_DIR/guardrails.sh" >/dev/null 2>&1 )
    after="$(wc -c < "$REPO_ROOT/.claude/.rule-incidents.jsonl")"
    want "A6 INCIDENTS_REPO_ROOT honoured (worktree ledger unchanged)" "$before" "$after"
  fi

  # …and all the way to the surface a human reads.
  local agg="$REPO_ROOT/scripts/rule-metrics-aggregate.sh"
  if [[ -x "$agg" || -f "$agg" ]]; then
    out="$(INCIDENTS_REPO_ROOT="$root" bash "$agg" --dry-run 2>/dev/null || true)"
    local n; n="$(printf '%s' "$out" | jq -r '.summary.hook_input_fault_count // 0' 2>/dev/null || echo 0)"
    if [[ "${n:-0}" -gt 0 ]]; then
      ok "A6 aggregator surfaces summary.hook_input_fault_count=$n"
    else
      bad "A6 aggregator reports 0 faults — the row reached no surface" "counter is the replacement for orphan_rule_ids"
    fi
  fi
  rm -rf "$root"
}

# ===========================================================================
# A8 — envelope pairing, asserted PER ENVELOPE.
# ===========================================================================
# Without hookEventName in the SAME object, CC silently ignores the envelope and
# the tool RUNS. hookeventname-coverage.test.sh is a per-file COUNT and cannot
# catch a decision emitted without its pairing.
a8_envelope_pairing() {
  local tmp out unpaired=0 hook
  for hook in guardrails; do
    tmp="$(mktemp -d -t hicep.XXXXXXXX)"
    out="$(cd "$tmp" && printf '%s' "$ARRAY_STASH" \
          | INCIDENTS_REPO_ROOT="$tmp" bash "$SCRIPT_DIR/$hook.sh" 2>/dev/null)"
    rm -rf "$tmp"
    # Every object carrying a permissionDecision must carry hookEventName too.
    local paired
    paired="$(printf '%s' "$out" | jq '[.. | objects | select(has("permissionDecision")) | has("hookEventName")] | all' 2>/dev/null || echo false)"
    [[ "$paired" == "true" ]] || unpaired=$((unpaired + 1))
  done
  want "A8 every permissionDecision carries hookEventName in the same object" "0" "$unpaired"
}

# ===========================================================================
# A9 — designated-responder invariant over .claude/settings.json.
# ===========================================================================
# guardrails.sh is load-bearing for the other 19: they report and exit 0, it
# emits the ask. Checked at the TOOL level, not by matcher-string equality —
# `Write|Edit` and `Write|Edit|MultiEdit|NotebookEdit` are different strings
# that both fire on a Write.
a9_designated_responder() {
  local settings="$REPO_ROOT/.claude/settings.json"
  if [[ ! -f "$settings" ]]; then bad "A9 .claude/settings.json not found"; return; fi
  local uncovered
  uncovered="$(jq -r --args '
    [ .hooks.PreToolUse[]
      | . as $e
      | ($e.matcher // "") as $m
      | ($e.hooks[].command | sub(".*/";"")) as $c
      | select($ARGS.positional | index(($c | sub("\\.sh$";""))))
      | ($m | split("|"))[]
    ] | unique as $needed
    | [ .hooks.PreToolUse[]
        | select([.hooks[].command | sub(".*/";"")] | index("guardrails.sh"))
        | (.matcher // "" | split("|"))[]
      ] | unique as $covered
    | ($needed - $covered) | join(",")
  ' "$settings" "${INSCOPE20[@]}" 2>/dev/null || echo "<jq-fail>")"
  want "A9 every tool triggering a migrated hook also triggers guardrails.sh" "" "$uncovered"
}

# ===========================================================================
# A10 — kill switch suppresses ESCALATION ONLY.
# ===========================================================================
a10_kill_switch() {
  want "A10 kill switch suppresses the ask" "<none>" \
    "$(decision_for guardrails "$ARRAY_STASH" SOLEUR_DISABLE_HOOK_INPUT_ASK=1)"
  # …but parsing and telemetry still run: the fault is still recorded.
  local root
  root="$(mktemp -d -t hicks.XXXXXXXX)"
  ( cd "$root" && printf '%s' "$ARRAY_STASH" \
      | SOLEUR_DISABLE_HOOK_INPUT_ASK=1 INCIDENTS_REPO_ROOT="$root" bash "$SCRIPT_DIR/guardrails.sh" >/dev/null 2>&1 )
  if [[ -f "$root/.claude/.rule-incidents.jsonl" ]]; then
    ok "A10 kill switch does NOT suppress telemetry (escalation only)"
  else
    bad "A10 kill switch also killed telemetry — it must gate escalation only"
  fi
  rm -rf "$root"
}

# ===========================================================================
# A11 — mechanism ban + structural properties of the helper.
# ===========================================================================
# Replaces a comparative wall-clock assertion: deterministic, milliseconds, and
# it names the banned construct on failure. A 14% timing margin does not belong
# in CI — the measured table lives in the PR body.
a11_mechanism_ban() {
  local helper="$SCRIPT_DIR/lib/hook-input.sh" code
  code="$(sed 's/^[[:space:]]*#.*$//' "$helper")"
  local m
  for m in explode 'read -d' 'mapfile'; do
    local n; n="$(printf '%s\n' "$code" | grep -cE -- "$m" || true)"
    want "A11 helper contains no '$m'" "0" "$n"
  done
  # `command -v jq` + exactly one invocation.
  want "A11 helper forks jq exactly once" "1" \
    "$(printf '%s\n' "$code" | grep -cE '\| jq ' || true)"
  # No `$` in the jq program text: nothing is interpolated into it.
  local prog
  prog="$(sed -n "/^_HOOK_INPUT_JQ='/,/^'$/p" "$helper")"
  want "A11 the jq program interpolates nothing (no \$ in program text)" "0" \
    "$(printf '%s\n' "$prog" | grep -cF '$' || true)"
  # The response functions must never call exit — a sourced library that exits
  # terminates its caller invisibly and silently no-ops inside $( ) or a pipe.
  want "A11 no response function calls exit" "0" \
    "$(printf '%s\n' "$code" | sed -n '/^hook_input_report()/,$p' | grep -cE '^\s*exit ' || true)"
}

# ===========================================================================
# A13 — per-file source hygiene across all 20 in-scope hooks.
# ===========================================================================
a13_source_hygiene() {
  local hook f n bad_src=() missing=()
  for hook in "${INSCOPE20[@]}"; do
    f="$SCRIPT_DIR/$hook.sh"
    n="$(grep -cE 'source .*lib/hook-input\.sh' "$f" || true)"
    [[ "$n" == "1" ]] || missing+=("$hook (found $n)")
    # Fail-soft source is defect 2 one line above where every test points.
    grep -E 'source .*lib/hook-input\.sh' "$f" | grep -qE '\|\|[[:space:]]*(true|:)|2>/dev/null' \
      && bad_src+=("$hook")
  done
  if (( ${#missing[@]} == 0 )); then
    ok "A13 all ${#INSCOPE20[@]} in-scope hooks source the helper exactly once"
  else
    bad "A13 helper source count wrong" "${missing[@]}"
  fi
  if (( ${#bad_src[@]} == 0 )); then
    ok "A13 every helper source is FAIL-HARD (no '|| true', '|| :', '2>/dev/null')"
  else
    bad "A13 fail-soft source found — leaves hook_parse_input undefined" "${bad_src[@]}"
  fi
}

# ===========================================================================
# A14 — guard-still-armed for the hooks that can decide from a bare payload.
# ===========================================================================
# Honest coverage: only a subset of the 20 can produce a decision from stdin
# alone; the rest need a git fixture or a `gh` stub. Those are NOT silently
# degraded to "fail-open, as expected" — they are listed.
a14_bare_payload_coverage() {
  # The designated-responder design means only guardrails.sh EMITS the ask; the
  # other 19 report and exit 0, so the operator sees ONE prompt per tool call
  # rather than 18. An earlier draft of this assertion expected every hook to
  # ask and was simply wrong about the contract.
  #
  # What must hold for a NON-responder is therefore: it does not proceed to a
  # guard decision on an unparseable envelope, and it RECORDS the fault. Exiting
  # 0 with no record is defect 2 — that is the thing being tested.
  local hook silent=() unrecorded=() root d
  for hook in kb-domain-allowlist-guard no-memory-write worktree-write-guard iac-plan-write-guard; do
    d="$(decision_for "$hook" "$ARRAY_STASH")"
    [[ "$d" == "<none>" ]] || silent+=("$hook emitted '$d' (only the responder should)")
    root="$(mktemp -d -t hica14.XXXXXXXX)"
    ( cd "$root" && printf '%s' "$ARRAY_STASH" \
        | INCIDENTS_REPO_ROOT="$root" bash "$SCRIPT_DIR/$hook.sh" >/dev/null 2>&1 )
    if [[ -f "$root/.claude/.rule-incidents.jsonl" ]] \
       && grep -q 'hook-input-' "$root/.claude/.rule-incidents.jsonl" 2>/dev/null; then :
    else unrecorded+=("$hook"); fi
    rm -rf "$root"
  done

  if (( ${#silent[@]} == 0 )); then
    ok "A14 non-responder hooks stay silent on stdout (one prompt per call, not 18)"
  else
    bad "A14 a non-responder emitted a decision" "${silent[@]}"
  fi
  if (( ${#unrecorded[@]} == 0 )); then
    ok "A14 every non-responder RECORDS the fault (a silent exit 0 is defect 2)"
  else
    bad "A14 hook(s) disarmed with no record" "${unrecorded[@]}"
  fi
  # …and the responder is the one that actually prompts, on the same payload.
  want "A14 the designated responder emits the ask" "ask" \
    "$(decision_for guardrails "$ARRAY_STASH")"
}

# ===========================================================================
# A15 — shell-state hygiene. ADDED because the mutation battery caught nothing.
# ===========================================================================
# M6 (${IFS-} -> $IFS) and M9 (set -f removed) both SURVIVED the suite as first
# written: the in-scope hooks run `set -eo pipefail` without `-u`, and no
# assertion used a whole-value glob, so neither protection was observable. Both
# are exercised here directly against the helper, which is where they live.
a15_shell_state_hygiene() {
  local helper="$SCRIPT_DIR/lib/hook-input.sh"

  # M6: with IFS UNSET under `set -u`, `local o=$IFS` kills the shell — silently,
  # exiting non-zero, so the tool proceeds. The whole point of the ${IFS-} form.
  if bash -c '
      set -u
      unset IFS
      source "'"$helper"'"
      hook_parse_input "{\"tool_input\":{\"command\":\"x\"}}" || exit 9
      [[ "$HOOK_CMD" == "x" ]] || exit 8
      [[ -z "${IFS+set}" ]] || exit 7      # must be left UNSET, not set to ""
      exit 0' >/dev/null 2>&1; then
    ok "A15 IFS unset under set -u: survives, parses, and leaves IFS unset"
  else
    bad "A15 IFS unset under set -u killed the shell or restored IFS wrongly" \
        "this is the \${IFS-} vs \$IFS trap — a silent fail-open in the safety line"
  fi

  # M9: only a value that is ENTIRELY a glob can expand during the split.
  # `rm *` cannot catch a missing `set -f`; a bare `*` can.
  local g out
  g="$(mktemp -d -t hicglob.XXXXXXXX)"
  : > "$g/decoy-a"; : > "$g/decoy-b"; : > "$g/decoy-c"
  out="$(cd "$g" && bash -c '
      source "'"$helper"'"
      hook_parse_input "{\"tool_input\":{\"command\":\"*\"}}" || exit 1
      printf "%s" "$HOOK_CMD"' 2>/dev/null)"
  want "A15 a whole-value glob is not expanded during the split" "*" "${out:-<empty>}"
  rm -rf "$g"

  # …and the caller's shell state is byte-identical afterwards, on every rc path.
  local drift=0 pay before_ifs before_dash
  for pay in '{"tool_input":{"command":"x"}}' 'garbage {{' '{"tool_input":{"command":["a"]}}' ''; do
    before_ifs="${IFS-}"; before_dash="$-"
    ( source "$helper"; hook_parse_input "$pay" ) >/dev/null 2>&1 || true
    [[ "${IFS-}" == "$before_ifs" && "$-" == "$before_dash" ]] || drift=$((drift + 1))
  done
  want "A15 IFS and \$- unchanged across every rc path" "0" "$drift"
}

a1_idiom_ban
a2_guard_still_armed
a3_rce_regression
a4_cheap_variants
a5_jq_unusable
a6_loud_disarm_end_to_end
a8_envelope_pairing
a9_designated_responder
a10_kill_switch
a11_mechanism_ban
a13_source_hygiene
a14_bare_payload_coverage
a15_shell_state_hygiene

echo
echo "=== hook-input-contract: $PASS/$TOTAL pass ==="
[[ "$FAIL" -eq 0 ]] || exit 1
