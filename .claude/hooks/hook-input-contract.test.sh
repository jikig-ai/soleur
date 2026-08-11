#!/usr/bin/env bash
# Contract tests for the PreToolUse hook input boundary (issue #7164).
#
# ADR-156 — hook stdin is model-controlled and untrusted; a hook must not depend
#           on an upstream invariant it cannot verify.
# ADR-157 — a hook that cannot fully parse its input ASKS. It never continues
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
SKIPPED=0

# Printed on EVERY exit path, including the jq precondition below, so a jq-less
# machine cannot exit 0 emitting no line at all.
#
# It is for a HUMAN reading the log. An earlier version of this comment said the
# summary "is the only thing an aggregate runner reads", which is false and was
# load-bearing for the wrong reason: `run_suite` in scripts/test-all.sh branches
# on the EXIT CODE alone and never parses this line. So the aggregate-level half
# of #7190 item 5 is NOT closed by this change — a skipped suite still records
# `ok` upstream. What is closed is legibility: the skip is now counted and
# visible instead of silently shrinking the denominator.
summary() { echo; echo "=== hook-input-contract: $PASS/$TOTAL pass, $SKIPPED skipped ==="; }

# jq absent → SKIP, deliberately retained. #7190 item 5 asked us to consider a
# hard failure here and justify either way. Rejected, four reasons:
#   (a) CI has jq, so a hard-fail is unreachable there — dead code guarding a
#       hypothetical image change;
#   (b) if CI ever lost jq, this suite is struck along with everything else, so
#       the hard-fail buys no earlier signal;
#   (c) it turns a green test-all.sh red on a jq-less dev machine for an
#       environment reason, not a defect;
#   (d) it buys false comfort while 21 SIBLING suites still skip silently in
#       exactly that scenario.
# If aggregate skip-invisibility is the real concern the fix is skip-accounting
# in test-all.sh — one place, all 22 suites — and that is not this change.
# What IS fixed here: the skip is now COUNTED and PRINTED rather than invisible.
command -v jq >/dev/null 2>&1 || {
  SKIPPED=$((SKIPPED + 1)); echo "SKIP: jq missing — whole suite"; summary; exit 0
}

# ADR-129 rule (c): ONE owning trap for every tempfile this suite allocates.
# Per-case sandboxes are children of this root, so a case that dies mid-assertion
# cannot leak — /tmp is a machine-global tmpfs shared with sibling worktrees.
HIC_TMPROOT="$(mktemp -d -t hicroot.XXXXXXXX)"
trap 'rm -rf "$HIC_TMPROOT"' EXIT

# The trap above did NOT own everything this suite allocates, so the claim
# directly above it was false. Every fault-path hook invocation writes a
# PID-named log through `headless_or_stderr` into a session-state root that
# defaults to a machine-global directory no trap owns: measured 81 leaked files
# per run on this branch against 40 on main, i.e. this suite doubled a
# pre-existing leak. Redirecting the root brings them under the trap and makes
# the suite hermetic, which is also what any future parallelisation would need.
export SOLEUR_SESSION_STATE_ROOT="$HIC_TMPROOT/session-state"

ok()  { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); echo "FAIL: $1"; shift; local l; for l in "$@"; do echo "  $l"; done; }
want(){ if [[ "$2" == "$3" ]]; then ok "$1 → $3"; else bad "$1" "want: $2" "got:  $3"; fi; }
# A skip is NOT a pass. It increments neither PASS nor TOTAL — inflating the
# pass count with unrun assertions is the thing being fixed — but it is counted
# and surfaced in the summary so "48 here, 49 there" is legible instead of
# mysterious.
skip(){ SKIPPED=$((SKIPPED + 1)); echo "SKIP: $1"; }

# Size of a ledger in bytes, with ABSENT deliberately equal to 0 rather than an
# error or an empty string. That equivalence is what lets the worktree-ledger
# assertion run unconditionally: a fresh checkout (no file) and a populated
# checkout (a file) are then both comparable across the same run, instead of the
# assertion existing in one environment and silently vanishing in the other.
_ledger_bytes() { [[ -f "$1" ]] && wc -c < "$1" | tr -d '[:space:]' || echo 0; }
# Count of hook_self_fault rows. Robust to unrelated concurrent appenders in a
# way a byte-size comparison is not.
_fault_rows() {
  [[ -f "$1" ]] || { echo 0; return; }
  jq -r 'select(.kind=="hook_self_fault") | .kind' < "$1" 2>/dev/null | grep -c . || echo 0
}

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

# REWRITERS — the THIRD disposition (ADR-162, #7165). These source the same
# helper and are bound by the same trust boundary, but two of the guard
# properties do not apply to them BY CONSTRUCTION, so they are classified
# rather than listed in INSCOPE20:
#
#   * They do not call `hook_input_should_ask`. Asking is the designated
#     responder's job, and a rewriter's failed parse costs a missing
#     OPTIMIZATION, not a missing safety check — escalating would spend an
#     operator prompt on a non-event.
#   * They are NOT silent on stdout. Emitting `updatedInput` is the entire
#     point; A3's property (iv) asserts the opposite for guards.
#
# This is a classification, not an escape hatch. a18b_rewriter_contract below
# holds every member to the parts of the contract that DO apply — fail-hard
# source, a real parse gate, a fault record, and exit 0 on every payload class.
# Adding a name here therefore buys exemption from exactly two properties and
# nothing else; a guard misfiled as a rewriter still fails A18b.
REWRITERS=( grep-rewrite )

# The designated responder as a named constant. NOT a single source of truth —
# an earlier version of this comment claimed that and it is measurably false:
# ~24 hardcoded `guardrails` literals remain in this file, including
# a8_envelope_pairing's own `responders=(guardrails)` array and A9's jq
# `index("guardrails.sh")`. Nothing pins this against lib/hook-input.sh's
# HOOK_INPUT_RESPONDER either. It is a convenience for the assertions that use
# it; the responder-set change tracked by #7219 will still need a sweep.
HOOK_INPUT_RESPONDER_NAME="guardrails"

# A18 — INSCOPE20 IS A CLAIM ABOUT THE FILESYSTEM, SO CHECK IT AGAINST THE
# FILESYSTEM.
#
# Eleven assertions iterate this array, and every one of their messages prints
# its length ("all 20 in-scope hooks …"). Nothing derived it. Measured: setting
# INSCOPE20=( guardrails ) left the suite at 62/62 with an IDENTICAL pass count
# and the messages simply reading "all 1 hooks" — so the cardinality was a
# printf argument, not a measured quantity.
#
# The live regression that opens is the one this whole file exists to stop: a
# NEW hook that sources the helper with `|| true` — defect 2 verbatim — is
# invisible to A3, A13 and A16 because it is not in the literal. A1 already
# quantifies dynamically over the directory; these did not.
#
# So: derive the set that ACTUALLY sources the helper and assert the difference
# is empty in both directions. A new in-scope hook now fails this until it is
# listed, and a listed hook that stops sourcing the helper fails it too.
a18_inscope_closure() {
  local discovered f base
  discovered="$(mktemp -p "$HIC_TMPROOT")"
  while IFS= read -r f; do
    base="$(basename "$f" .sh)"
    printf '%s\n' "$base"
  done < <(grep -rlE '^[[:space:]]*(source|\.)[[:space:]].*lib/hook-input\.sh' \
             "$SCRIPT_DIR"/*.sh 2>/dev/null | grep -v '\.test\.sh$' || true) \
    | sort -u > "$discovered"

  # The claim is about the WHOLE trust boundary, so the listed set is
  # INSCOPE20 ∪ REWRITERS. A new hook that sources the helper still fails this
  # until it is classified into one of the two.
  local listed; listed="$(mktemp -p "$HIC_TMPROOT")"
  printf '%s\n' "${INSCOPE20[@]}" "${REWRITERS[@]}" | sort -u > "$listed"

  # Non-vacuity: an empty discovery would make both differences trivially empty.
  local n; n="$(grep -c . "$discovered" || true)"
  if [[ "${n:-0}" -lt 1 ]]; then
    bad "A18 non-vacuity control failed: zero hooks discovered as sourcing the helper" \
        "the closure check below would pass having compared nothing"
    return
  fi
  ok "A18 non-vacuity control: $n hook(s) discovered sourcing lib/hook-input.sh"
  want "A18 every hook that sources the helper is in INSCOPE20" "" \
    "$(comm -23 "$discovered" "$listed" | tr '\n' ' ' | sed 's/ $//')"
  want "A18 every listed member (INSCOPE20 + REWRITERS) still sources the helper" "" \
    "$(comm -13 "$discovered" "$listed" | tr '\n' ' ' | sed 's/ $//')"
}

# A18b — the exemption is bounded. A rewriter is excused from should_ask and
# from stdout-silence; it is excused from NOTHING else. Without this, REWRITERS
# would be a one-line way to delete a hook from the entire suite — the exact
# vacuity A18 exists to close, reintroduced through the classification.
a18b_rewriter_contract() {
  local hook src fail_soft=() no_gate=() bad_rc=() unrecorded=() no_rewrite=() sandbox rc payload rids src_lines
  for hook in "${REWRITERS[@]}"; do
    src="$SCRIPT_DIR/$hook.sh"
    if [[ ! -f "$src" ]]; then no_gate+=("$hook (file missing)"); continue; fi

    # (i) fail-hard source — a `|| true` here is defect 2 verbatim.
    # Uses A13's two-step form verbatim, and for two reasons. A single fused
    # regex written for this assertion anchored the `||` directly after
    # `hook-input.sh` and so did NOT match the real-world line, which carries a
    # closing quote first (`source "$D/lib/hook-input.sh" || true`) — measured:
    # the mutation landed and this assertion still reported clean. It is also a
    # herestring, not `producer | grep -q`, per the SIGPIPE note at A13.
    src_lines="$(grep -E 'source .*lib/hook-input\.sh' "$src" || true)"
    [[ -n "$src_lines" ]] \
      && grep -qE '\|\|[[:space:]]*(true|:)|2>/dev/null' <<<"$src_lines" \
      && fail_soft+=("$hook")

    # (ii) a real parse gate at the call site (comments stripped, per A13).
    sed 's/[[:space:]]*#.*$//' "$src" | grep -q 'hook_parse_input' \
      || no_gate+=("$hook: no hook_parse_input call")
    sed 's/[[:space:]]*#.*$//' "$src" | grep -q 'hook_input_report' \
      || no_gate+=("$hook: no hook_input_report call")

    # (iii) exit 0 on every payload class — a non-zero exit from a PreToolUse
    # hook BLOCKS the tool call, which for a rewriter is a pure regression.
    for payload in "$MALFORMED_PAYLOAD" "$HAPPY_PAYLOAD"; do
      rc="$(rc_for "$hook" "$payload")"
      [[ "$rc" == 0 ]] || bad_rc+=("$hook rc=$rc")
    done
    rc="$(rc_for "$hook" "$MALFORMED_PAYLOAD" PATH="$(make_jqless_path)")"
    [[ "$rc" == 0 ]] || bad_rc+=("$hook rc=$rc (jq missing)")

    # (iv) the fault is RECORDED — silence plus exit 0 is defect 2.
    sandbox="$(mktemp -d -p "$HIC_TMPROOT")"
    ( cd "$sandbox" && printf '%s' "$MALFORMED_PAYLOAD" \
        | INCIDENTS_REPO_ROOT="$sandbox" bash "$src" >/dev/null 2>&1 )
    rids=""
    [[ -f "$sandbox/.claude/.rule-incidents.jsonl" ]] \
      && rids="$(jq -r '.rule_id' < "$sandbox/.claude/.rule-incidents.jsonl" 2>/dev/null || true)"
    grep -qE '^hook-input-' <<<"$rids" || unrecorded+=("$hook")
    rm -rf "$sandbox"
  done

  # (v) POSITIVE IDENTITY — the member actually rewrites.
  # Properties (i)-(iv) are all satisfied by a well-behaved GUARD too, so on
  # their own they do not bound the classification at all: measured, adding
  # `no-memory-write` to REWRITERS left the suite at a full green. An earlier
  # version of this comment claimed the opposite. What separates the two
  # classes is the third disposition itself — a rewriter emits
  # `hookSpecificOutput.updatedInput`; a guard never does. Assert that, and
  # moving a guard into REWRITERS to silence A18 costs a failure here instead.
  local emitted
  for hook in "${REWRITERS[@]}"; do
    [[ -f "$SCRIPT_DIR/$hook.sh" ]] || continue
    sandbox="$(mktemp -d -p "$HIC_TMPROOT")"
    emitted="$(cd "$sandbox" && printf '%s' "$REWRITE_PROBE_PAYLOAD" \
      | INCIDENTS_REPO_ROOT="$sandbox" bash "$SCRIPT_DIR/$hook.sh" 2>/dev/null || true)"
    rm -rf "$sandbox"
    jq -e '.hookSpecificOutput.updatedInput' <<<"$emitted" >/dev/null 2>&1 \
      || no_rewrite+=("$hook")
  done
  want "A18b every rewriter EMITS updatedInput (a guard listed here fails)" "" "${no_rewrite[*]-}"

  want "A18b rewriters source the helper FAIL-HARD" "" "${fail_soft[*]-}"
  want "A18b rewriters run a real parse gate" "" "${no_gate[*]-}"
  want "A18b rewriters exit 0 on unparseable, happy and jq-missing" "" "${bad_rc[*]-}"
  want "A18b rewriters RECORD the fault (silent exit 0 is defect 2)" "" "${unrecorded[*]-}"
}

# Run a hook from a NON-GIT temp CWD so the orthogonal, branch-dependent
# block-commit-on-main gate resolves an empty branch and no-ops. Without this
# these fixtures pass on a feature worktree and fail on main-CI (#5192).
# Echoes "<permissionDecision>" or "<none>" when the hook allows.
decision_for() { # <hook> <payload> [extra-env...]
  local hook="$1" payload="$2"; shift 2
  local tmp out
  tmp="$(mktemp -d -p "$HIC_TMPROOT")"
  out="$(cd "$tmp" && printf '%s' "$payload" \
        | env INCIDENTS_REPO_ROOT="$tmp" "$@" bash "$SCRIPT_DIR/$hook.sh" 2>/dev/null)"
  rm -rf "$tmp"
  [[ -z "${out//[[:space:]]/}" ]] && { echo "<none>"; return; }
  echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "<none>"' 2>/dev/null || echo "<jq-fail>"
}

# rc_for — the SIBLING of decision_for that reports the hook's EXIT CODE.
#
# It is a SECOND function rather than a `bad` call inside decision_for, because
# decision_for is invoked exclusively inside `$( )` at ~25 sites: a
# FAIL=$((FAIL+1)) there runs in a SUBSHELL and is discarded (measured
# `FAIL_after=0`), so the suite would exit 0 having detected a non-zero rc and
# thrown it away — the A9 dead-gate class, one layer down.
#
# Correction, from review: that argument justifies not touching decision_for. It
# does NOT justify returning the rc through stdout, and an earlier version of
# this comment claimed it did. rc_for makes no ok/bad/want call of its own, so
# `rc_for h p; rc=$?` would work identically. The stdout form is kept only for
# symmetry with decision_for at the call sites; nothing depends on it.
rc_for() { # <hook-basename | /abs/path.sh> <payload> [extra-env...]
  local hook="$1" payload="$2"; shift 2
  local tmp rc=0 target
  # An absolute path is used as-is. That is what lets the control below point at
  # a throwaway probe WITHOUT dropping a stray .sh into .claude/hooks/, which
  # A1 scans by directory and would report as an offender.
  if [[ "$hook" == /* ]]; then target="$hook"; else target="$SCRIPT_DIR/$hook.sh"; fi
  tmp="$(mktemp -d -p "$HIC_TMPROOT")"
  ( cd "$tmp" && printf '%s' "$payload" \
      | env INCIDENTS_REPO_ROOT="$tmp" "$@" bash "$target" >/dev/null 2>&1 )
  rc=$?
  rm -rf "$tmp"
  echo "$rc"
}

# Build a PATH that genuinely lacks jq but keeps everything else a hook needs.
# PATH=/nonexistent would also remove grep, git, mktemp and flock, so the hook
# could not meaningfully run and any assertion over it would prove nothing.
# `chmod 000 jq` does NOT work either: `command -v` skips a non-executable file
# and finds the real jq further along PATH, so the helper parses normally and
# the fixture silently exercises the WRONG path.
# Echoes the shim directory, or "" if jq is still reachable (broken fixture).
make_jqless_path() {
  local shim b src
  shim="$(mktemp -d -p "$HIC_TMPROOT")"
  for b in bash sh env grep sed awk tr cat cut head tail sort uniq wc date \
           mkdir rm ln ls mktemp dirname basename realpath xargs flock \
           git perl python3 touch chmod find printf; do
    src="$(command -v "$b" 2>/dev/null)" || continue
    # `command -v` returns a BARE NAME for a builtin, a function or an alias, not
    # a path — `printf` is the one in this list, and in some shells `grep` is a
    # wrapper function. `ln -sf printf "$shim/printf"` then creates a DANGLING
    # SELF-REFERENTIAL symlink, which falsifies this helper's own claim to keep
    # "everything else a hook needs" and silently broke the fixture when the
    # missing binary was one the hook actually calls. Absolute paths only.
    [[ "$src" == /* ]] || continue
    ln -sf "$src" "$shim/$b" 2>/dev/null
  done
  # Unconditional: `-e` is FALSE for a dangling symlink, so the guarded form
  # could leave a `jq` entry in place that the precondition below would then
  # have to catch.
  rm -f "$shim/jq"
  if PATH="$shim" command -v jq >/dev/null 2>&1; then echo ""; return; fi
  echo "$shim"
}

ARRAY_STASH="$(jq -nc '{tool_name:"Bash", tool_input:{command:["git","stash"]}}')"
# A benign, fully-parseable envelope: every contracted field a string, no guard
# tripped. The HAPPY class for A16.
HAPPY_PAYLOAD="$(jq -nc '{tool_name:"Bash", tool_input:{command:"echo hello"}, cwd:"/w", session_id:"s"}')"
# A document jq rejects outright (n == 0 → reason `unparseable`), distinct from
# the ARRAY_STASH `nonstring` class so A16 and the Phase-2 loop cover disjoint
# ground rather than duplicating one class across 40 invocations.
MALFORMED_PAYLOAD='garbage {{'

# A well-formed envelope carrying a command a rewriter acts on. Used by A18b's
# positive-identity property. The `grep` token is what grep-rewrite gates on;
# a future rewriter with a different trigger needs its own probe here, and the
# A18b failure message names the hook that emitted nothing.
REWRITE_PROBE_PAYLOAD="$(jq -nc '{tool_name:"Bash", tool_input:{command:"grep -rn needle ."}, cwd:"/w", session_id:"s"}')"
# A MIXED payload: a legitimate STRING command (which therefore survives into the
# slots and could be leaked) plus an unrelated NON-STRING field to trip the type
# assertion. ARRAY_STASH cannot serve this purpose — its only notable field is
# the non-string one, which the program emits empty, so nothing exists to leak.
MIXED_LEAK_PAYLOAD="$(jq -nc '{tool_name:"Bash", tool_input:{command:"git stash --include-untracked SENTINELLEAK"}, cwd:["/secret/path"]}')"

# ===========================================================================
# A1 — idiom ban: ANY eval, not one spelling.
# ===========================================================================
# `eval "$(` misses `eval $(…)`, `eval "$V"` and `eval "${x}"`. Full-line
# comments are stripped first: hook headers legitimately discuss the word
# "eval" in prose and a body-grep sees comments too (cq-assert-anchor-not-
# bare-token). Allow-list is BY EXACT STRING — `eval "exec ${fd}>&-"` is the
# only portable way to close a dynamic fd in bash.
# shellcheck disable=SC2016  # a literal to match, never a string to expand
EVAL_ALLOW='eval "exec ${fd}>&-" 2>/dev/null || true'

a1_idiom_ban() {
  local offenders=() scanned=() f line n stripped trimmed root
  # Scoped to `scripts/lib` rather than all of `plugins/soleur/scripts` (#7409).
  # ADR-156's ban exists because a hook's stdin is MODEL-CONTROLLED; the library
  # that moved there is in that trust path (three .claude/hooks/** consumers
  # source it). The rest of plugins/soleur/scripts consumes no hook stdin, so
  # banning eval across it would be an unrecorded expansion of ADR-156's scope,
  # not preservation of it.
  local _a1_roots=(
    "$REPO_ROOT/.claude/hooks"
    "$REPO_ROOT/.openhands/hooks"
    "$REPO_ROOT/plugins/soleur/scripts/lib"
  )
  while IFS= read -r f; do
    scanned+=("$f")
    [[ "$f" == *.test.sh ]] && continue
    stripped="$(sed 's/^[[:space:]]*#.*$//' "$f")"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      n="${line%%:*}"; line="${line#*:}"
      trimmed="${line#"${line%%[![:space:]]*}"}"
      [[ "$trimmed" == "$EVAL_ALLOW" && "$f" == */lib/session-state.sh ]] && continue
      offenders+=("${f#"$REPO_ROOT/"}:$n: $trimmed")
    done < <(printf '%s\n' "$stripped" | grep -nE '(^|[^[:alnum:]_])eval([[:space:]]|$)' || true)
  done < <(find "${_a1_roots[@]}" -name '*.sh' -type f 2>/dev/null | sort)

  # MEMBERSHIP ASSERTION (#7409). Extending the roots above is a one-time patch;
  # this is the tripwire. `find` is invoked with `2>/dev/null`, so deleting a
  # root — or relocating the file out from under one — makes this gate report
  # `ok` while scanning strictly less. A silently-narrowed green gate is the
  # #5454 shape exactly: the assertion keeps passing and stops meaning anything.
  #
  # session-state.sh is the ONLY file in the scan set that needs the allow-listed
  # `eval` fd-close idiom, so its presence is a sound proxy for "the roots still
  # reach the plugin". It moved to plugins/soleur/scripts/lib/ in #7409; the
  # carve-out above is suffix-matched (*/lib/session-state.sh) and needs no edit.
  # Two assertions, because either one alone is defeatable.
  #
  # (1) The REQUIRED set is pinned as literals here, independent of the array the
  #     walk uses. Deriving "expected" from `_a1_roots` would be a tautology —
  #     deleting an entry shrinks both sides and the comparison still holds.
  #     Measured: with only the per-root-contributed check below, dropping
  #     `.openhands/hooks` from the array left this gate GREEN at 83 files.
  # (2) Each root must actually have CONTRIBUTED a file, because `find … 2>/dev/null`
  #     swallows a root that is present in the array but missing on disk.
  local _a1_required=(
    ".claude/hooks"
    ".openhands/hooks"
    "plugins/soleur/scripts/lib"
  )
  local _a1_narrowed="" req present
  for req in "${_a1_required[@]}"; do
    present=false
    for root in "${_a1_roots[@]}"; do
      [[ "$root" == "$REPO_ROOT/$req" ]] && { present=true; break; }
    done
    [[ "$present" == true ]] || _a1_narrowed="${_a1_narrowed} ${req}(dropped-from-roots)"
  done
  for root in "${_a1_roots[@]}"; do
    if [[ ! -d "$root" ]]; then
      _a1_narrowed="${_a1_narrowed} ${root#"$REPO_ROOT/"}(absent)"
    elif ! printf '%s\n' "${scanned[@]}" | grep -q "^$root/"; then
      _a1_narrowed="${_a1_narrowed} ${root#"$REPO_ROOT/"}(0 files)"
    fi
  done
  if [[ -n "$_a1_narrowed" ]]; then
    bad "A1 scan set lost a root — this gate is scanning less than it claims (ADR-156, #7409)" \
      "narrowed:$_a1_narrowed" "scanned ${#scanned[@]} file(s)"
  elif (( ${#offenders[@]} == 0 )); then
    # The message names the ACTUAL scan set. A green assertion naming a narrower
    # surface than it ran is the same evidence-vs-claim gap the membership check
    # above exists to close.
    # Message rendered FROM the root array, so it can never advertise a root the
    # walk no longer uses.
    ok "A1 no eval under$(printf ' %s' "${_a1_roots[@]#"$REPO_ROOT/"}") \
(${#scanned[@]} files; 2 fd-close lines allow-listed)"
  else
    bad "A1 eval found in ${#offenders[@]} place(s) — hook stdin is untrusted (ADR-156)" "${offenders[@]}"
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
a3_a12_a14_fault_path_properties() {
  local run stub marker hook payload
  local pwned=() unrecorded=() nonzero=() noisy=() strays=() entry

  # --- positive control, in its OWN directory ------------------------------
  # It gets a private directory because the per-hook sandboxes below are also
  # per-hook INCIDENTS_REPO_ROOTs; the control must not share a tree whose
  # contents the stray-artifact property is simultaneously asserting over.
  run="$(mktemp -d -p "$HIC_TMPROOT")"
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
  rm -rf "$run"

  # --- one loop, all 20, five properties per hook --------------------------
  # ABSENCE ALONE WAS NOT ENOUGH, and the reason is worth stating plainly.
  # This assertion previously reported "no attacker-named command executed by
  # any of the 10 migrated hooks" while proving only that the DETECTOR works —
  # the positive control validates the harness, not the SUBJECTS. Inserting
  # `exit 0` at line 3 of nine of the ten hooks, so that they never read stdin,
  # never source the helper and never run a guard, left the message unchanged
  # and the suite green. An absence assertion over a subject that was never
  # reached is indistinguishable from an absence assertion over a subject that
  # was reached and behaved.
  #
  # The fix is PAIRING: in the same loop, require positive evidence that each
  # hook actually got as far as the parse gate. Property (ii) is that evidence,
  # and it is why this loop also subsumes the old A14 — which asserted the same
  # thing over a hardcoded FOUR hooks while claiming a property of nineteen.
  #
  # Cardinality note: (ii) and (iv) were each instantiated over 4 hooks against
  # a claimed 19, and (i) over 10. All three now quantify over INSCOPE20, which
  # is the set the properties are actually about. Measured before widening: all
  # 19 non-responders are silent, record the fault, and exit 0 — so the loop is
  # widened to the full set rather than trimmed back to a passing subset.
  for hook in "${INSCOPE20[@]}"; do
    local sandbox rc out
    sandbox="$(mktemp -d -p "$HIC_TMPROOT")"
    marker="$sandbox/PWNED-$hook"
    payload="$(jq -nc --arg m "$marker" '{tool_name:"Bash",tool_input:{command:["x","touch",$m]}}')"

    out="$(cd "$sandbox" && printf '%s' "$payload" \
          | INCIDENTS_REPO_ROOT="$sandbox" bash "$SCRIPT_DIR/$hook.sh" 2>/dev/null)"
    rc=$?

    # (i) no attacker-named command ran.
    [[ -e "$marker" ]] && pwned+=("$hook")

    # (ii) REACHABILITY: the hook got to the parse gate and recorded the fault.
    # Reads rule_id and kind ONLY — never command_snippet. The bad path emits
    # values empty by construction, so there is no payload content in existence
    # to read, and this assertion must not become the thing that starts logging
    # one (A7 asserts the same boundary from the other side).
    #
    # `grep -qE <<<"$rids"` and NOT `jq … | grep -q`: under `set -o pipefail` a
    # `producer | grep -q` returns NON-ZERO when the match is early, because
    # grep closes the pipe and the producer takes SIGPIPE (141). That reads as
    # "no match" and would silently convert this presence check into a
    # permanent false negative — a vacuity bug inside the assertion added to
    # remove vacuity. A herestring has no pipe.
    local jsonl="$sandbox/.claude/.rule-incidents.jsonl" rids=""
    [[ -f "$jsonl" ]] && rids="$(jq -r 'select(.kind=="hook_self_fault") | .rule_id' < "$jsonl" 2>/dev/null || true)"
    if [[ -n "$rids" ]] && grep -qE '^hook-input-' <<<"$rids"; then :
    else unrecorded+=("$hook"); fi

    # (iii) rc 0 on the fault path. A16 covers the unparseable, happy and
    # jq_missing classes; this covers `nonstring` without a 21st invocation.
    [[ "$rc" == "0" ]] || nonzero+=("$hook → rc $rc")

    # (iv) stdout silence unless this hook is the designated responder — one
    # prompt per tool call, not 20. NOTE this is a FAULT-PATH contract: four of
    # these hooks legitimately emit an explicit `allow` on a HAPPY envelope,
    # which is why this loop is driven by the fault class and not the happy one.
    if [[ "$hook" == "$HOOK_INPUT_RESPONDER_NAME" ]]; then
      [[ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)" == "ask" ]] \
        || noisy+=("$hook (responder did NOT ask)")
    else
      [[ -z "${out//[[:space:]]/}" ]] || noisy+=("$hook emitted output (only the responder should)")
    fi

    # (v) A12 stray artifacts, now PER HOOK. This property previously depended
    # on the single shared `$run` that per-hook sandboxes dissolve, so it would
    # have been silently lost in this merge. `.claude` is allow-listed because
    # each sandbox is now also an INCIDENTS_REPO_ROOT.
    # `find -mindepth 1 -maxdepth 1 -print0` rather than `ls | grep`: a filename
    # produced by an attacker-shaped payload is exactly where a non-alphanumeric
    # name shows up, and that is what `ls` output cannot represent unambiguously.
    while IFS= read -r -d '' entry; do
      case "${entry##*/}" in .claude) continue ;; esac
      strays+=("$hook:${entry##*/}")
    done < <(find "$sandbox" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)

    rm -rf "$sandbox"
  done

  if (( ${#pwned[@]} == 0 )); then
    ok "A3 no attacker-named command executed by any of the ${#INSCOPE20[@]} in-scope hooks"
  else
    bad "A3 RCE still reachable in ${#pwned[@]} hook(s)" "${pwned[@]}"
  fi
  if (( ${#unrecorded[@]} == 0 )); then
    ok "A3 REACHABILITY: all ${#INSCOPE20[@]} hooks reached the parse gate and recorded the fault"
  else
    bad "A3 hook(s) never reached the parse gate — the absence assertion above is vacuous for them" \
        "a silent exit 0 with no record IS defect 2" "${unrecorded[@]}"
  fi
  if (( ${#nonzero[@]} == 0 )); then
    ok "A3 all ${#INSCOPE20[@]} hooks exit 0 on a NONSTRING envelope"
  else
    bad "A3 hook(s) exited non-zero on a nonstring envelope — stdout JSON is discarded" "${nonzero[@]}"
  fi
  if (( ${#noisy[@]} == 0 )); then
    ok "A14 exactly one prompt per tool call: only ${HOOK_INPUT_RESPONDER_NAME} emits, all others silent"
  else
    bad "A14 stdout discipline broken on the fault path" "${noisy[@]}"
  fi
  if (( ${#strays[@]} == 0 )); then
    ok "A12 no stray artifacts in any of the ${#INSCOPE20[@]} sandboxes"
  else
    bad "A12 stray artifacts created by the payload's trailing words" "${strays[@]}"
  fi
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

  # BOOLEANS. This corpus originally covered array/string/object only, and a
  # JSON `false` sailed through: jq's `//` is a FALSY-alternative, so
  # `.tool_input.command // ""` rewrote false to "" BEFORE the type check saw
  # it — rc 0, empty value, no incident, no ask. Strictly stealthier than the
  # array this PR was written against, and a violation of ADR-156's own
  # "absence and empty are legitimate; a different JSON type is not".
  # `true` was caught and `false` was not, which is the tell.
  want "A4 boolean false command asks (the // falsy-default hole)" "ask" \
    "$(decision_for guardrails "$(jq -nc '{tool_input:{command:false}}')")"
  want "A4 boolean true command asks" "ask" \
    "$(decision_for guardrails "$(jq -nc '{tool_input:{command:true}}')")"
  want "A4 boolean false cwd asks" "ask" \
    "$(decision_for guardrails "$(jq -nc '{tool_input:{command:"a"}, cwd:false}')")"
  want "A4 boolean false tool_name asks" "ask" \
    "$(decision_for guardrails "$(jq -nc '{tool_input:{command:"a"}, tool_name:false}')")"
  want "A4 boolean false file_path asks" "ask" \
    "$(decision_for guardrails "$(jq -nc '{tool_input:{file_path:false}}')")"

  # The inverse: absence, null and empty are LEGITIMATE and must still pass, or
  # the fix for the above would have broken every ordinary payload.
  want "A4 control: null command still allows (absence is legitimate)" "<none>" \
    "$(decision_for guardrails "$(jq -nc '{tool_input:{command:null}}')")"
  want "A4 control: empty object still allows" "<none>" \
    "$(decision_for guardrails "$(jq -nc '{}')")"

  # The jq program lives in a single-quoted bash string, so one apostrophe in a
  # comment inside it silently terminates the string and the helper stops
  # parsing. Cheap structural guard.
  want "A4 no apostrophe inside the jq program (would break the bash string)" "0" \
    "$(sed -n "/^_HOOK_INPUT_JQ='/,/^'$/p" "$SCRIPT_DIR/lib/hook-input.sh" | grep -c "'" | awk '{print $1-2}')"
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
    skip "python3 missing — separator/surrogate fixtures (2 assertions not run)"
  fi
}

# ===========================================================================
# A5 — unusable jq: ask, built by printf, with NO jq fork.
# ===========================================================================
# Shim a NON-EXECUTABLE jq at the front of PATH, leaving the rest intact.
# PATH=/nonexistent would also remove grep, git, mktemp and flock, so the hook
# could not meaningfully run and the assertion would prove nothing.
a5_jq_unusable() {
  # The shim-PATH construction, its rationale and its precondition self-check
  # now live in make_jqless_path — A16's `jq_missing` class needs the identical
  # fixture, and two copies of a fixture whose failure mode is "silently
  # exercises the wrong path" is exactly the drift this suite polices.
  local shim tmp out dec reason
  shim="$(make_jqless_path)"
  if [[ -z "$shim" ]]; then
    bad "A5 FIXTURE BROKEN — jq still reachable on the shim PATH" "assertion would be vacuous"
    return
  fi

  tmp="$(mktemp -d -p "$HIC_TMPROOT")"
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
  root="$(mktemp -d -p "$HIC_TMPROOT")"
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
    # A7 — no payload content in telemetry.
    #
    # THE FIXTURE USED TO MAKE THIS UNFALSIFIABLE. It ran on ARRAY_STASH, whose
    # only interesting field is the non-string one — and the jq program emits
    # bad-path values EMPTY by construction, so there was no payload content in
    # existence for the assertion to find. Measured: a mutation putting a real
    # field value into HOOK_INPUT_REASON landed `git stash --include-untracked`
    # in the ledger on disk and A7 still reported PASS.
    #
    # Fixed in two ways. (1) A MIXED payload: the command is a legitimate STRING
    # that survives into the slots, and an unrelated field is the non-string one,
    # so a leak has something to leak. (2) Assert over the WHOLE ROW, not just
    # `.command_snippet` — a leak into any other field, present or future, was
    # unguarded.
    local mixed_root mixed_jsonl row leaked=no
    mixed_root="$(mktemp -d -p "$HIC_TMPROOT")"
    ( cd "$mixed_root" && printf '%s' "$MIXED_LEAK_PAYLOAD" \
        | INCIDENTS_REPO_ROOT="$mixed_root" bash "$SCRIPT_DIR/guardrails.sh" >/dev/null 2>&1 )
    mixed_jsonl="$mixed_root/.claude/.rule-incidents.jsonl"
    if [[ -f "$mixed_jsonl" ]]; then
      row="$(jq -c '.' < "$mixed_jsonl" | head -1)"
      # The canary is the command text the mixed payload carries.
      [[ "$row" == *include-untracked* || "$row" == *SENTINELLEAK* ]] && leaked=yes
      want "A7 no payload content anywhere in the incident row (whole row, mixed payload)" "no" "$leaked"
    else
      bad "A7 FIXTURE BROKEN — the mixed payload wrote no incident row" \
          "the leak assertion would be vacuous"
    fi
    rm -rf "$mixed_root"
  else
    bad "A6 no incident row written — the disarm is silent (defect 2)"
  fi

  # --- INCIDENTS_REPO_ROOT is honoured, asserted UNCONDITIONALLY -----------
  # This was gated on `[[ -f $REPO_ROOT/.claude/.rule-incidents.jsonl ]]`. That
  # file is gitignored, so it does NOT exist on a fresh checkout: the assertion
  # ran locally and silently vanished in CI, with no SKIP printed and the pass
  # count differing by one between the two environments for no visible reason.
  # An assertion that disappears based on an untracked file is worse than one
  # that fails — it makes the count itself untrustworthy.
  #
  # It is made unconditional WITHOUT synthesizing a git repo. _incidents_repo_root
  # (lib/incidents.sh:36-42) falls back to `dirname(BASH_SOURCE)/../../..` —
  # HELPER-relative, not cwd- or git-relative — so a synthesized sandbox repo is
  # a location the fallback can never resolve to, and "the synthesized repo's
  # ledger is untouched" could not fail under any mutation. That would have been
  # a vacuous assertion added by the very change removing vacuity. (A `git init`
  # would also re-couple this suite to the branch-dependent gate that the
  # non-git CWD at :56-58 deliberately avoids — #5192.)
  #
  # Instead: assert the PAIR. The sandbox ledger must GROW and the worktree
  # ledger must be BYTE-IDENTICAL, with absent treated as size 0 on both sides.
  # Deleting the INCIDENTS_REPO_ROOT branch from _incidents_repo_root makes both
  # halves RED, and both run on every checkout.
  local wt_ledger="$REPO_ROOT/.claude/.rule-incidents.jsonl"
  local sb_before sb_after wt_fault_rows
  sb_before="$(_ledger_bytes "$jsonl")"
  wt_fault_rows="$(_fault_rows "$wt_ledger")"
  ( cd "$root" && printf '%s' "$ARRAY_STASH" | INCIDENTS_REPO_ROOT="$root" bash "$SCRIPT_DIR/guardrails.sh" >/dev/null 2>&1 )
  sb_after="$(_ledger_bytes "$jsonl")"

  if (( sb_after > sb_before )); then
    ok "A6 INCIDENTS_REPO_ROOT honoured: the sandbox ledger grew ($sb_before → $sb_after bytes)"
  else
    bad "A6 the sandbox ledger did NOT grow ($sb_before → $sb_after bytes)" \
        "the row went somewhere else, or nowhere — the redirect is not being honoured"
  fi
  # NOT byte-identity. The worktree ledger is SHARED MUTABLE STATE — ~18
  # PreToolUse hooks append to it per tool call on a live machine — so a
  # before/after size comparison is the one non-hermetic assertion in this file
  # and it flaked (reproduced deterministically with a concurrent appender).
  # What the assertion is actually about is narrower and robust to unrelated
  # writers: THIS invocation must not have added a hook_self_fault row here.
  local wt_faults_before="$wt_fault_rows" wt_faults_after
  wt_faults_after="$(_fault_rows "$wt_ledger")"
  want "A6 …and no hook_self_fault row reached the worktree ledger" \
    "$wt_faults_before" "$wt_faults_after"

  # --- …and all the way to the surface a human reads -----------------------
  # The `[[ -x $agg || -f $agg ]]` gate is removed. The aggregator is a
  # COMMITTED repo file; its absence is a broken checkout, not a legitimate
  # skip, and silently skipping the end-to-end walk is how the walk stops being
  # end-to-end.
  local agg="$REPO_ROOT/scripts/rule-metrics-aggregate.sh"
  if [[ ! -f "$agg" ]]; then
    bad "A6 rule-metrics-aggregate.sh is MISSING at scripts/rule-metrics-aggregate.sh" \
        "it is a committed repo file — this is a broken checkout, not a skippable condition" \
        "restore it: git checkout -- scripts/rule-metrics-aggregate.sh"
  else
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
  # Only the designated responder emits an envelope, so this list has one entry
  # today. Kept as an array so adding a second responder needs no restructuring.
  local tmp out unpaired=0 hook
  local -a responders=(guardrails)
  for hook in "${responders[@]}"; do
    tmp="$(mktemp -d -p "$HIC_TMPROOT")"
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
  local settings="$SCRIPT_DIR/../settings.json"
  if [[ ! -f "$settings" ]]; then bad "A9 .claude/settings.json not found"; return; fi

  # The first version of this assertion COULD NOT FAIL, and it guarded the
  # invariant the whole designated-responder design rests on.
  #
  # It passed the settings path as `jq -r --args '<prog>' "$settings" "${INSCOPE20[@]}"`.
  # With `--args`, EVERY remaining argument becomes a positional string — the
  # filename included — so jq never opened the file, read empty stdin, emitted
  # nothing and exited 0. `uncovered` was always "" and `want "" ""` always
  # passed. Measured: deleting `.hooks.PreToolUse` outright, and removing
  # guardrails.sh from the Bash matcher (leaving 17 migrated hooks with NO
  # responder), both left the suite fully green.
  #
  # That is the same defect class this file exists to prevent — a check that
  # reports success having asserted nothing — so it gets the same treatment the
  # rest of the suite gets: feed the document on stdin, bind the hook list with
  # --argjson, and prove non-vacuity before trusting the result.
  local in20 out needed uncovered
  in20="$(printf '%s\n' "${INSCOPE20[@]}" | jq -Rsc 'split("\n") - [""]')"
  out="$(jq -r --argjson in20 "$in20" '
    . as $d
    | ([ $d.hooks.PreToolUse[] | . as $e
         | ($e.hooks[].command | sub(".*/";"") | sub("\\.sh$";"")) as $c
         | select($in20 | index($c))
         | (($e.matcher // "") | split("|"))[] ] | unique) as $needed
    | ([ $d.hooks.PreToolUse[]
         | select([.hooks[].command | sub(".*/";"")] | index("guardrails.sh"))
         | ((.matcher // "") | split("|"))[] ] | unique) as $covered
    | "\($needed | length)\t\(($needed - $covered) | join(","))"
  ' < "$settings" 2>/dev/null)" || out=""

  if [[ -z "$out" ]]; then
    # jq errored (malformed settings, PreToolUse absent). NOT a pass — the
    # old form turned exactly this into silence.
    bad "A9 could not evaluate .claude/settings.json — refusing to read a jq failure as coverage"
    return
  fi
  needed="${out%%$'\t'*}"
  uncovered="${out#*$'\t'}"

  # Positive control: if no migrated hook is registered at all, the difference
  # is trivially empty and the assertion proves nothing.
  if [[ "${needed:-0}" -lt 1 ]]; then
    bad "A9 non-vacuity control failed: zero matchers resolved for the ${#INSCOPE20[@]} in-scope hooks" \
        "settings.json registers none of them — the coverage check would pass vacuously"
    return
  fi
  ok "A9 non-vacuity control: $needed matcher(s) resolved for the in-scope hooks"
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
  root="$(mktemp -d -p "$HIC_TMPROOT")"
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
  # A TOKEN COUNT, not a pipe-spelling grep.
  #
  # This was `grep -cE '\| jq '`, which pins an INCIDENTAL SPELLING: it is
  # evaded outright by `$(jq …)`, `< <(jq …)`, `jq … < file` and backticks. It
  # also counted LINES rather than occurrences, so a second `jq` appended to an
  # existing line passed. Counting the bare token closes both without starting a
  # regex arms race over invocation syntax.
  #
  # Comment-stripping is load-bearing: the raw file mentions `jq` 28 times in
  # prose. Stripped, exactly two remain — `command -v jq` and the invocation.
  #
  # Deliberately NOT called a fork count. Relocating the single invocation into
  # a loop keeps the token count at 2 while multiplying the forks; this asserts
  # that no SECOND jq call site has been introduced, which is the drift that
  # actually happens. The one-fork property is a design invariant recorded in
  # the helper's own header and in ADR-157.
  want "A11 helper names the jq token exactly twice (command -v + one invocation)" "2" \
    "$(printf '%s\n' "$code" | grep -oE '\bjq\b' | grep -c . || true)"

  # --- non-vacuity preconditions -------------------------------------------
  # AN EXTRACTED RANGE THAT YIELDS EMPTY PASSES EVERY CONTENT ASSERTION.
  # `grep -cF '$'` over an empty range returns 0, and 0 is exactly what the
  # assertion below wants — so renaming `_HOOK_INPUT_JQ` made the range empty
  # and the check reported success having read nothing. This is the same class
  # as the A9 dead gate repaired in 68996d3ed, and the fix is the same: assert
  # the range is non-empty BEFORE asserting anything about its contents.
  local prog report_range
  prog="$(sed -n "/^_HOOK_INPUT_JQ='/,/^'$/p" "$helper")"
  if [[ -n "${prog//[[:space:]]/}" ]]; then
    ok "A11 non-vacuity: the _HOOK_INPUT_JQ range is non-empty ($(printf '%s\n' "$prog" | grep -c . || true) lines)"
    # No `$` in the jq program text: nothing is interpolated into it.
    want "A11 the jq program interpolates nothing (no \$ in program text)" "0" \
      "$(printf '%s\n' "$prog" | grep -cF '$' || true)"
  else
    bad "A11 the _HOOK_INPUT_JQ range extracted EMPTY — the anchor no longer matches" \
        "every content assertion over it would pass vacuously (renamed constant?)"
  fi

  # The response functions must never call exit — a sourced library that exits
  # terminates its caller invisibly and silently no-ops inside $( ) or a pipe.
  # Same non-vacuity treatment: the range is anchored on a FUNCTION NAME, so a
  # rename empties it and the ban reports clean forever.
  report_range="$(printf '%s\n' "$code" | sed -n '/^hook_input_report()/,$p')"
  if [[ -n "${report_range//[[:space:]]/}" ]]; then
    ok "A11 non-vacuity: the hook_input_report..EOF range is non-empty"
    want "A11 no response function calls exit" "0" \
      "$(printf '%s\n' "$report_range" | grep -cE '^\s*exit ' || true)"
  else
    bad "A11 the hook_input_report..EOF range extracted EMPTY — the anchor no longer matches" \
        "the no-exit ban would pass vacuously (renamed function?)"
  fi
}

# ===========================================================================
# A16 — exit code 0 is the PRECONDITION for the entire ADR-157 posture.
# ===========================================================================
# The whole suite inspected stdout JSON and discarded `$?`. That is not a
# cosmetic gap: per the Claude Code hooks reference, the exit code decides
# whether the stdout channel is READ AT ALL.
#
#   exit 0   stdout JSON is parsed; permissionDecision is honored.
#   exit 2   BLOCKING error. Tool prevented, stdout JSON IGNORED ENTIRELY,
#            stderr becomes the block reason.
#   exit 1   non-blocking error. stdout JSON IGNORED, and the tool PROCEEDS.
#
#   "You must choose one approach per hook, not both … Claude Code only
#    processes JSON on exit 0. If you exit 2, any JSON is ignored."
#
# So a non-zero exit does not degrade the posture, it DELETES it:
#   * `exit 2` in guardrails after emitting the ask → the ask is discarded and
#     the call is DENIED. ADR-157 says this hook never denies.
#   * `exit 2` in any of the 19 non-responders → that hook becomes a denier.
#   * `exit 1` anywhere → the JSON channel is voided and the tool PROCEEDS,
#     which is defect 2 restored verbatim.
#
# SCOPE OF THE CLAIM — read this before "fixing" a hook that seems to violate
# it. This asserts rc 0 on the four payload classes probed below, NOT on every
# branch a hook can reach. `pre-merge-auto-close-scan.sh` carries a deliberate
# commented `exit 2` on a branch none of these payloads reach; it is not a
# contract violation and must not be deleted as one.
a16_exit_codes() {
  local hook shim rc offenders=()

  # POSITIVE CONTROL for the rc channel itself. Every assertion below reads
  # rc_for's output; stubbing rc_for to `echo 0` left the suite fully green, so
  # nothing proved it can observe a non-zero rc at all. Same doctrine as A3's
  # vulnerable stub and A9's non-vacuity control — the fixture must be shown
  # capable of detecting the thing it is asked about.
  local probe="$HIC_TMPROOT/rc-probe.sh"
  printf '#!/usr/bin/env bash\nexit 2\n' > "$probe"
  want "A16 control: rc_for observes a NON-zero rc" "2" \
    "$(rc_for "$probe" '{}')"

  # --- class 1: unparseable (jq rejects the document; n == 0) ---------------
  offenders=()
  for hook in "${INSCOPE20[@]}"; do
    rc="$(rc_for "$hook" "$MALFORMED_PAYLOAD")"
    [[ "$rc" == "0" ]] || offenders+=("$hook → rc $rc")
  done
  if (( ${#offenders[@]} == 0 )); then
    ok "A16 all ${#INSCOPE20[@]} in-scope hooks exit 0 on an UNPARSEABLE envelope"
  else
    bad "A16 hook(s) exited non-zero on an unparseable envelope — stdout JSON is discarded" "${offenders[@]}"
  fi

  # --- class 2: happy (every contracted field a string) --------------------
  offenders=()
  for hook in "${INSCOPE20[@]}"; do
    rc="$(rc_for "$hook" "$HAPPY_PAYLOAD")"
    [[ "$rc" == "0" ]] || offenders+=("$hook → rc $rc")
  done
  if (( ${#offenders[@]} == 0 )); then
    ok "A16 all ${#INSCOPE20[@]} in-scope hooks exit 0 on a HAPPY envelope"
  else
    bad "A16 hook(s) exited non-zero on a happy envelope" "${offenders[@]}"
  fi

  # --- class 3: jq_missing -------------------------------------------------
  # The class that most needs the assertion and is easiest to omit. Here
  # hook_input_emit_ask's printf envelope is the ONLY surviving channel:
  # emit_incident builds its row with `jq -nc`, so telemetry is unrecordable.
  # A non-zero exit on this path voids the ask WITH ZERO TELEMETRY — the one
  # combination that is both silent and unguarded. Without this class the
  # mutation `[[ "$HOOK_INPUT_REASON" == jq_missing ]] && exit 1` survives A16.
  shim="$(make_jqless_path)"
  if [[ -z "$shim" ]]; then
    bad "A16 FIXTURE BROKEN — jq still reachable on the shim PATH" "the jq_missing class would be vacuous"
  else
    offenders=()
    for hook in "${INSCOPE20[@]}"; do
      rc="$(rc_for "$hook" "$ARRAY_STASH" "PATH=$shim")"
      [[ "$rc" == "0" ]] || offenders+=("$hook → rc $rc")
    done
    if (( ${#offenders[@]} == 0 )); then
      ok "A16 all ${#INSCOPE20[@]} in-scope hooks exit 0 with jq MISSING (printf ask is the only channel)"
    else
      bad "A16 hook(s) exited non-zero with jq missing — the ask is voided with no telemetry" "${offenders[@]}"
    fi
  fi

  # --- class 4: the responder's DENY path ----------------------------------
  # Asserted conjoined with the decision, never in isolation: rc 0 alone is
  # satisfied by a hook that stopped denying altogether. The idiom is borrowed
  # from pre-merge-rebase.test.sh:84-101.
  local deny_payload
  deny_payload="$(jq -nc '{tool_name:"Bash", tool_input:{command:"git stash"}}')"
  want "A16 the responder still DENIES on the deny path" "deny" \
    "$(decision_for "$HOOK_INPUT_RESPONDER_NAME" "$deny_payload")"
  want "A16 …and exits 0 while doing so (rc 2 would discard that very decision)" "0" \
    "$(rc_for "$HOOK_INPUT_RESPONDER_NAME" "$deny_payload")"
  want "A16 the responder ASKS on the fault path" "ask" \
    "$(decision_for "$HOOK_INPUT_RESPONDER_NAME" "$ARRAY_STASH")"
  want "A16 …and exits 0 while doing so" "0" \
    "$(rc_for "$HOOK_INPUT_RESPONDER_NAME" "$ARRAY_STASH")"
}

# ===========================================================================
# A13 — per-file source hygiene across all 20 in-scope hooks.
# ===========================================================================
a13_source_hygiene() {
  local hook f n src_lines bad_src=() missing=() missing_call=()
  for hook in "${INSCOPE20[@]}"; do
    f="$SCRIPT_DIR/$hook.sh"
    n="$(grep -cE 'source .*lib/hook-input\.sh' "$f" || true)"
    [[ "$n" == "1" ]] || missing+=("$hook (found $n)")
    # Fail-soft source is defect 2 one line above where every test points.
    #
    # Captured into a variable and matched with a HERESTRING rather than
    # `grep … "$f" | grep -q …`. Under `set -o pipefail` a `producer | grep -q`
    # returns non-zero when the match is early — grep closes the pipe, the
    # producer takes SIGPIPE (141) — so the `&& bad_src+=(…)` never fires and
    # the ban reports clean. That failure direction is FAIL-OPEN: a hook could
    # regain a `|| true` on its helper source and this assertion would not
    # notice. The producer here emits one short line, well under the 64 KiB
    # pipe buffer, so it does not trip today — but the shape is banned for
    # policy-gate hooks by grep-q-pipe-guard.test.sh, and a latent fail-open in
    # the assertion that guards fail-hard sourcing is not worth keeping.
    src_lines="$(grep -E 'source .*lib/hook-input\.sh' "$f" || true)"
    if [[ -n "$src_lines" ]] \
       && grep -qE '\|\|[[:space:]]*(true|:)|2>/dev/null' <<<"$src_lines"; then
      bad_src+=("$hook")
    fi
    # The `source` line alone is NOT the contract. A mutation battery showed
    # that DELETING the entire `if ! hook_parse_input … fi` block from a hook
    # left this suite fully green while the hook exited 0, wrote no incident
    # row, and ran every guard it owns against an empty command — defect 2
    # restored verbatim. Twelve of these twenty hooks have sibling suites that
    # never mention the input contract, so for them a grep for the word
    # `source` was the only thing standing between the fix and silent
    # regression. Assert the three call-site verbs too.
    # COMMENT LINES ARE STRIPPED FIRST. This grepped raw file text, and every
    # in-scope hook names these verbs in prose — measured raw=4 vs code=2 for
    # `hook_parse_input`. Replacing the real gate with `if false; then` while
    # leaving the block textually present therefore left A13 PASSING. (A3's
    # reachability property caught that mutation behaviourally, but A13's own
    # comment claims to be the last line of defence for the twelve hooks with no
    # sibling suite, and that claim was false.) Same class as A1 and A11, which
    # already strip.
    local v stripped_f
    stripped_f="$(sed 's/^[[:space:]]*#.*$//' "$f")"
    for v in hook_parse_input hook_input_report hook_input_should_ask; do
      [[ "$(printf '%s\n' "$stripped_f" | grep -cE "(^|[^A-Za-z_])${v}\b" || true)" -ge 1 ]] \
        || missing_call+=("$hook:$v")
    done
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
  if (( ${#missing_call[@]} == 0 )); then
    ok "A13 every in-scope hook invokes parse + report + should_ask at its call site"
  else
    bad "A13 hook(s) source the helper but never call it — the parse gate is absent" "${missing_call[@]}"
  fi
}

# ===========================================================================
# A14 — MERGED INTO a3_rce_regression. See properties (ii) and (iv) there.
# ===========================================================================
# This assertion asserted two properties — "non-responders stay silent" and
# "every non-responder RECORDS the fault" — over a HARDCODED LIST OF FOUR
# hooks, while its own message claimed a property of all nineteen. The fixture
# was the whole of the gap: the reviewer probed all 19 with this exact payload
# and every one was silent, recorded and rc 0, so widening the loop was a
# one-line change that had simply never been made.
#
# It is merged rather than widened in place because it drove the SAME payload
# class through the SAME hooks as A3's loop, one sandbox each — two overlapping
# loops asserting overlapping properties, with A3 needing exactly the presence
# evidence A14 was already collecting. One loop over INSCOPE20 now carries all
# five properties, and the responder's own ask is asserted there and in A16.

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
  g="$(mktemp -d -p "$HIC_TMPROOT")"
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
    # shellcheck source=lib/hook-input.sh
    ( source "$helper"; hook_parse_input "$pay" ) >/dev/null 2>&1 || true
    [[ "${IFS-}" == "$before_ifs" && "$-" == "$before_dash" ]] || drift=$((drift + 1))
  done
  want "A15 IFS and \$- unchanged across every rc path" "0" "$drift"
}

# ===========================================================================
# A17 — HAPPY-PATH VALUE FIDELITY. Nothing observed the values themselves.
# ===========================================================================
# Every assertion in this suite watched the DECISION. Not one watched what the
# helper actually hands the guards on the path where it succeeds. Measured:
# whitespace-trimming HOOK_CMD passed all five suites in this repo — and a
# trimmed value silently no-ops every anchored guard regex, which is the same
# end state as the disarm this file exists to prevent, reached by a different
# road.
#
# The trailing-newline case is asserted on HOOK_FILE_PATH, and the slot choice
# is load-bearing rather than arbitrary. Command substitution strips trailing
# newlines, so the helper protects them with a REDUNDANT PAIR — the program's
# trailing separator and a `printf 'X'` sentinel. Only the LAST emitted record
# sits at the end of `raw`, so only slot 5 is actually shielded by that pair.
# Measured against a scratch mutation dropping both: slots 1-4 keep their
# trailing newline regardless, and only HOOK_FILE_PATH flips. Asserting this on
# any other slot would let the mutation the assertion exists for pass GREEN.
#
# HOOK_CMD carries the properties that are slot-independent: leading spaces,
# trailing spaces and an embedded newline.
a17_value_fidelity() {
  local helper="$SCRIPT_DIR/lib/hook-input.sh" payload verdict

  # Built with jq so the JSON escaping is not hand-rolled. The expectations
  # inside the probe use $'...' ANSI-C quoting rather than $( ), because $( )
  # strips the very trailing newline this assertion exists to observe.
  # All FIVE slots. Covering only 1 and 5 left slot 2 (HOOK_TOOL_NAME) unpinned,
  # and that one is a live disarm: seven hooks dispatch on it, so lowercasing it
  # turns `[[ "$TOOL" == "Bash" ]] || exit 0` into an unconditional exit —
  # measured, doppler-secrets-delete-redirect went from deny to silent with the
  # whole suite still green.
  payload="$(jq -nc '{tool_name:"  Ba\nsh  ",
                      tool_input:{command:"  git \n stash  ", file_path:"/tmp/f\n"},
                      cwd:"  /w\nx  ", session_id:"  s\ns  "}')"

  verdict="$(bash -c '
      source "'"$helper"'"
      hook_parse_input "$1" || { printf "PARSE_FAIL"; exit 0; }
      exp_cmd=$'"'"'  git \n stash  '"'"'
      exp_fp=$'"'"'/tmp/f\n'"'"'
      exp_tn=$'"'"'  Ba\nsh  '"'"'
      exp_cwd=$'"'"'  /w\nx  '"'"'
      exp_sid=$'"'"'  s\ns  '"'"'
      v=0
      [[ "$HOOK_CMD"        == "$exp_cmd" ]] || v=$((v+1))
      (( ${#HOOK_CMD}       == ${#exp_cmd} )) || v=$((v+2))
      [[ "$HOOK_FILE_PATH"  == "$exp_fp"  ]] || v=$((v+4))
      (( ${#HOOK_FILE_PATH} == ${#exp_fp} )) || v=$((v+8))
      [[ "$HOOK_TOOL_NAME"  == "$exp_tn"  ]] || v=$((v+16))
      (( ${#HOOK_TOOL_NAME} == ${#exp_tn} )) || v=$((v+32))
      [[ "$HOOK_CWD"        == "$exp_cwd" ]] || v=$((v+64))
      (( ${#HOOK_CWD}       == ${#exp_cwd} )) || v=$((v+128))
      [[ "$HOOK_SESSION_ID" == "$exp_sid" ]] || v=$((v+256))
      (( ${#HOOK_SESSION_ID} == ${#exp_sid} )) || v=$((v+512))
      printf "%s" "$v"' _ "$payload" 2>/dev/null)"

  # Content AND length are both compared. A trailing-newline loss is invisible
  # to a content-only `[[ "$a" == "$b" ]]` evaluated inside $( ), which is how
  # this class survives a test that looks like it checks it.
  # Verdict bits: 1/2 cmd · 4/8 file_path · 16/32 tool_name · 64/128 cwd · 256/512 session_id
  # (content / length for each).
  want "A17 byte-exact round-trip of leading/trailing spaces, embedded and TRAILING newline" \
    "0" "${verdict:-<no-output>}"
}

a1_idiom_ban
a2_guard_still_armed
a3_a12_a14_fault_path_properties
a4_cheap_variants
a5_jq_unusable
a6_loud_disarm_end_to_end
a8_envelope_pairing
a9_designated_responder
a10_kill_switch
a11_mechanism_ban
a13_source_hygiene
a15_shell_state_hygiene
a16_exit_codes
a17_value_fidelity
a18_inscope_closure
a18b_rewriter_contract

summary

# MIN_ASSERTIONS — the floor under everything above.
#
# Commenting out the dispatch lines above yields rc 0, PASS=0, FAIL=0 and a
# printed "0/0 pass" summary. test-all.sh registers this file by glob and
# run_suite branches on the EXIT CODE alone, so CI was green with zero
# assertions executed — and every "mutation-proven" claim in the PR body is
# conditional on them running.
#
# A FLOOR, not equality: the count is developer-incremented, so `-eq` would turn
# every legitimately-added assertion into a spurious failure. Derived from a
# green run, deliberately a little below it so ordinary growth does not trip it.
# Mirrors the MIN_SUITES idiom in .github/scripts/test/run-all.sh, which exists
# for exactly this reason.
MIN_ASSERTIONS=60
if (( TOTAL < MIN_ASSERTIONS )); then
  echo "FAIL: only $TOTAL assertions ran (floor $MIN_ASSERTIONS) — the suite reported success having asserted almost nothing" >&2
  exit 1
fi

[[ "$FAIL" -eq 0 ]] || exit 1
