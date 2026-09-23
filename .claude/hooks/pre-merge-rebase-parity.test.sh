#!/usr/bin/env bash
# Review-evidence gate + envelope contract for the `.claude` hooks (#6724, #7173).
#
# The hand-ported hook mirror this file was originally written against was retired
# on 2026-09-23 (ADR-245, closes #8306). Every arm that existed to COMPARE the
# two copies has been reduced to its `.claude` half and now stands alone; the
# filename keeps its `-parity` suffix only so CI globs and history stay stable.
#
# WHAT THIS SUITE ASSERTS
#
# 1. The merge gate in `.claude/hooks/pre-merge-rebase.sh`, driven end-to-end
#    through throwaway repos: an unreviewed branch is DENIED, a
#    `Reviewed-By-Soleur` trailer ALLOWS, and evidence that exists only on MAIN
#    (pre-fork) does NOT satisfy the gate — the #6724 vacuity.
# 2. That the gate intercepts the WRAPPED command form
#    (`bash session-state.sh with_lock merge-main 600 -- gh pr merge ...`). A
#    matcher missing the `\s--\s` alternative lets that form bypass the hook
#    entirely, which is a real defect this project shipped once already.
# 3. Source-level anchors for the two evidence signals the behavioural cases
#    cannot distinguish from each other: the Signal 2 alternation (the legacy
#    "refactor: add code review findings" subject OR the `review: ` fix-inline
#    convention with an optional conventional-commit scope), and the
#    `Reviewed-By-Soleur` trailer lookup.
# 4. The ENVELOPE contract of `.claude/hooks/guardrails.sh` (#7173, ADR-157) —
#    the trust boundary rather than the merge gate: an envelope jq cannot parse
#    ASKS, a non-string command ASKS, an absent or null `tool_input` parses
#    cleanly, a missing `jq` ASKS through the printf envelope, and a 128 KB
#    padded protected command still DENIES instead of slipping through the
#    SIGPIPE/pipefail hole.
#
# THE PROTOCOL. The `.claude` copy reads `.cwd`, denies at exit 0 with
# {"hookSpecificOutput":{"permissionDecision":"deny"}}, and reaches `ask` as its
# safety verb when it cannot read an envelope. The envelope assertions pin the
# verdict AND the exit code together: without the rc half, a hook that ABORTS
# with no decision is indistinguishable from one that allows cleanly, and that
# is the exact pre-#7173 behaviour those cases were written to pin.
#
# Run via:  bash .claude/hooks/pre-merge-rebase-parity.test.sh
# Auto-discovered by scripts/test-all.sh via the `.claude/hooks/*.test.sh` glob
# in the `scripts` shard, which ci.yml runs — so this gates in CI.

set -uo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Applied to EVERY hook suite, not just ones whose hook is a sibling .sh:
# security_reminder_hook is a .py, so pairing by filename missed it and it
# kept writing the real ledger. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

# Refuse before writing, rather than let an empty operand retarget a git write at whatever
# repository the caller happens to be standing in. `git -C ""` does NOT error — it silently
# operates on the current directory, which under TEST_GROUP=scripts is the developer's live
# worktree, whose `.git/config` is the SHARED file every worktree on the machine inherits.
#
# Rejects, beyond empty: bare `/` AND its aliases `//` and `/.` (a `/*` arm accepts all three, and
# `rm -rf "/"/*` is the worst outcome in this corpus — a one-character bypass of a stated
# rejection); any path containing `..`, which can resolve back inside the real repo; and
# /proc, /sys, /dev, because `/proc/self/cwd` is absolute, passes every other arm, and resolves
# to precisely "whatever repository the caller happens to be standing in".
#
# Still no `realpath`: it breaks on a symlinked /tmp, which this corpus uses. So a symlink to
# $HOME is ACCEPTED — stated here rather than left implied, because the arms above make this
# look like a containment check and it is not.
#
# The body below is a COPY. The canonical definition lives in
# plugins/soleur/test/test-helpers.sh; plugins/soleur/test/fixture-dir-operand-assert.test.sh
# asserts this copy is byte-equal to it. Do not reword it in one file only. #7652
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOOK="$SCRIPT_DIR/pre-merge-rebase.sh"

PASS=0; FAIL=0; SKIPPED=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
# A skip is not a pass: it increments neither PASS nor the total, but it IS
# counted and printed. Without this the python3-gated cases silently turned a
# 20/20 into an 18/18 with no signal — the same accounting hole the sibling
# contract suite closed.
skip() { echo "  SKIP: $1"; SKIPPED=$((SKIPPED + 1)); }

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq missing"; echo "=== Results: 0/0 passed, 0 failed, 1 skipped ==="; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git missing"; exit 0; }

[[ -f "$CLAUDE_HOOK" ]] || { echo "FAIL: hook missing: $CLAUDE_HOOK"; exit 1; }

# denied <hook> <work_dir> <command> -> "yes" | "no"
denied() {
  local hook="$1" work="$2" cmd="$3" payload out
  payload=$(jq -nc --arg c "$work" --arg x "$cmd" \
    '{tool_input: {command: $x}, cwd: $c}')
  # Exit code is deliberately ignored HERE: the merge gate denies at exit 0 with
  # a deny payload, so the decision field — not the status — is the contract the
  # gate cases read. The envelope cases below assert the rc explicitly, because
  # there absence of a decision is the failure they pin.
  # INCIDENTS_REPO_ROOT redirected: without it this helper appended REAL rows to
  # the operator's live ledger on every run — synthetic `gh pr merge 900` command
  # text in `command_snippet`, feeding rule-metrics-aggregate.sh. Pre-existing,
  # and the other half of the same defect fixed in envelope_verdict below.
  local _sb; _sb="$(mktemp -d -p "$TMP")"
  out=$(printf '%s' "$payload" | env INCIDENTS_REPO_ROOT="$_sb" "$hook" 2>/dev/null) || true
  rm -rf "$_sb"
  if jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 <<<"$out"; then
    echo "yes"
  else
    echo "no"
  fi
}

# build_repo <dir> <mode>
#   unreviewed  — branch does real work, no review of any kind (gate MUST deny)
#   reviewed    — branch carries a Reviewed-By-Soleur trailer (gate MUST allow)
#   main-only   — evidence exists but only on MAIN, pre-fork (gate MUST deny)
build_repo() {
  local work="$1" mode="$2" origin="$3"
  assert_fixture_dir "$work"
  mkdir -p "$work"
  git -C "$work" init -q
  git -C "$work" symbolic-ref HEAD refs/heads/main
  git -C "$work" config user.email t@t
  git -C "$work" config user.name t
  git -C "$work" config commit.gpgsign false
  echo base > "$work/file.txt"
  git -C "$work" add file.txt
  git -C "$work" commit -q -m init

  if [[ "$mode" == "main-only" ]]; then
    mkdir -p "$work/todos"
    echo "code-review" > "$work/todos/legacy.md"
    git -C "$work" add todos/legacy.md
    git -C "$work" commit -q -m "chore: long-lived review todo on main"
    git -C "$work" commit -q --allow-empty -m "review: findings from an older branch"
  fi

  git init -q --bare -b main "$origin"
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q origin HEAD:main
  git -C "$work" fetch --no-tags -q origin

  git -C "$work" checkout -q -b feat-parity
  echo feature > "$work/feature.txt"
  git -C "$work" add feature.txt
  git -C "$work" commit -q -m "feat: work"

  if [[ "$mode" == "reviewed" ]]; then
    git -C "$work" commit -q --allow-empty -m "chore: post-review checkpoint

Reviewed-By-Soleur: soleur:review"
  fi
}

echo "=== pre-merge-rebase gate (.claude) ==="
echo ""

TMP=$(mktemp -d -t pmr-parity.XXXXXXXX)
trap 'rm -rf "$TMP"' EXIT

# The three gate outcomes.
i=0
for case_spec in \
  "unreviewed|yes|no review evidence -> DENY" \
  "reviewed|no|Reviewed-By-Soleur trailer -> ALLOW" \
  "main-only|yes|evidence only on MAIN (the #6724 vacuity) -> DENY" \
  ; do
  mode="${case_spec%%|*}"; rest="${case_spec#*|}"
  want="${rest%%|*}"; label="${rest#*|}"
  i=$((i + 1))
  work="$TMP/w$i"
  build_repo "$work" "$mode" "$TMP/o$i.git"
  got=$(denied "$CLAUDE_HOOK" "$work" "gh pr merge 900 --squash")
  if [[ "$got" == "$want" ]]; then
    pass "[.claude] $label"
  else
    fail "[.claude] $label — expected denied=$want, got denied=$got"
  fi
done

echo ""
echo "T-M: the wrapped form must be intercepted"
# `bash session-state.sh with_lock merge-main 600 -- gh pr merge ...` is the
# form a matcher without the `\s--\s` alternative lets through: the hook exits
# before any check runs. An unreviewed branch under the wrapped form must still
# deny.
i=$((i + 1))
work="$TMP/w$i"
build_repo "$work" "unreviewed" "$TMP/o$i.git"
got=$(denied "$CLAUDE_HOOK" "$work" "bash session-state.sh with_lock merge-main 600 -- gh pr merge 901 --squash")
if [[ "$got" == "yes" ]]; then
  pass "[.claude] wrapped 'with_lock ... -- gh pr merge' is intercepted"
else
  fail "[.claude] wrapped form BYPASSED the gate — the \\s--\\s matcher alternative is missing"
fi

echo ""
echo "T-S: the Signal 2 matcher and the trailer lookup are present in source"
# Source-level assertion on the alternation itself. The behavioural cases above
# cannot distinguish "matches the legacy subject only" from "matches both" when
# the fixture happens to use the trailer.
#
# Anchored on the CALL SHAPE, not the bare tokens. A first draft of this block
# grepped for `review: ` as a substring and SURVIVED the mutation it exists to
# catch: reverting the hook to the legacy-only matcher left the phrase
# `review: ` sitting in an explanatory COMMENT, which satisfied the grep. A
# body-grep sees comments too, so assert on something a comment cannot produce.
#
# Compared as a FIXED string (grep -qF), not an ERE. The matcher contains `(`,
# `)`, `[`, `^`, `*`, `?` and a literal backslash for the optional
# conventional-commit scope; hand-escaping all of that into a regex-matching-a-
# regex is where the assertion silently rots. -F also makes the check exact,
# byte-for-byte, and matches the trailer-lookup check below. A comment cannot
# produce the full `grep -E "..."` call, so the anti-drift property is preserved.
SIG2_CALL='grep -E "^[a-f0-9]+ (refactor: add code review findings|review(\([^)]*\))?: )"'
if grep -qF -- "$SIG2_CALL" "$CLAUDE_HOOK"; then
  pass "[.claude] Signal 2 uses the anchored two-pattern alternation"
else
  fail "[.claude] Signal 2 drift — expected the anchored alternation matching the legacy subject and 'review: ' with an optional (scope)"
fi
# The trailer lookup, anchored on the git format string rather than the bare key
# (which also appears in prose in the same file).
if grep -qF -- "trailers:key=Reviewed-By-Soleur,valueonly" "$CLAUDE_HOOK"; then
  pass "[.claude] trailer lookup present"
else
  fail "[.claude] trailer lookup missing — a zero-finding review cannot satisfy the gate"
fi


# ===========================================================================
# ENVELOPE CONTRACT — the trust boundary, not just the merge gate (#7173).
# ===========================================================================
# The cases below make `.claude/hooks/guardrails.sh`'s ENVELOPE handling
# executable rather than documented-in-prose-and-asserted-nowhere, which is the
# same structural blindness the merge-gate half of this file exists to fix.
#
# The reason classes and the verb each one reaches (ADR-157, ADR-165):
#
#   reason class       .claude
#   -----------------  -----------------------------------------------
#   nonstring          ask
#   unreadable doc     ask  (#7275 split the old single `unparseable`
#                            label into `empty` / `baddoc` / `nonobject`;
#                            every one of those values asks, so the
#                            DECISION is the same for all three)
#   jq_missing         ask, through the printf envelope
#   absent tool_input  parses cleanly
#
# `ask` — not deny — is deliberate: the guard cannot read the envelope, so it
# hands the call to the operator instead of guessing, and it must not silently
# allow. Before #7173 an unreadable document did not fall through at all; it
# aborted the script at rc 5 with no decision, which an assertion phrased as "no
# deny on stdout" would have been perfectly happy with.
#
# `envelope_verdict` echoes "<verdict>|<rc>". The rc half is not decoration:
# without it a hook that ABORTS with no decision is indistinguishable from one
# that allows cleanly, and that is the exact pre-#7173 behaviour these cases
# were written to pin.
#
# THE EMPTY-OUTPUT SHORT-CIRCUIT IS LOAD-BEARING. `jq -r '… // "none"' <<<""`
# emits NOTHING and exits 0, so the `|| echo "none"` fallback below was
# unreachable dead code and this function returned "" — visible in its own
# passing output as `is not denied ()`. Every assertion was written `!= "deny"`,
# so all of them passed against a hook that emitted nothing at all, including
# one that does not exist. Five review agents converged on it independently.
# The cases now assert a POSITIVE verdict and an rc, so absence cannot satisfy
# them.
#
# INCIDENTS_REPO_ROOT is redirected per call. Without it this hook appended
# real rows to the operator's live `.claude/.rule-incidents.jsonl` — measured at
# 1349 bytes per run, including synthetic `hook_self_fault` rows that feed
# `rule-metrics-aggregate.sh`, making a genuine production fault
# indistinguishable from test noise. `decision_for`/`rc_for` in the sibling
# suite set it everywhere; this helper was the one that did not.
envelope_verdict() { # <hook> <payload> [env...] -> "<deny|ask|none|other>|<rc>"
  local hook="$1" payload="$2"; shift 2
  local out rc sandbox
  sandbox="$(mktemp -d -p "$TMP")"
  # Extra env applies ONLY to the hook. Wrapping the whole call would also strip
  # jq from THIS function's own parse below, which reports `other` for every
  # verdict — a fixture defect that reads exactly like a real failure.
  out=$(cd "$sandbox" && printf '%s' "$payload" \
        | env INCIDENTS_REPO_ROOT="$sandbox" "$@" "$hook" 2>/dev/null)
  rc=$?
  rm -rf "$sandbox"
  if [[ -z "${out//[[:space:]]/}" ]]; then echo "none|$rc"; return; fi
  local v
  v=$(jq -r '(.hookSpecificOutput.permissionDecision // "other")' 2>/dev/null <<<"$out") \
    || v="other"
  [[ -z "$v" ]] && v="other"
  echo "$v|$rc"
}

CLAUDE_GUARD="$SCRIPT_DIR/guardrails.sh"

# A lone high surrogate in a SIBLING field, emitted raw. The command itself stays
# a clean, fully-armed `rm -rf $HOME` — so this is not a malformed-command case,
# it is a case where the guard cannot read an envelope that carries a live
# command. The field it sits in is arbitrary; what matters is that jq refuses the
# document while the command inside it is real.
SURROGATE_PAYLOAD="$(python3 -c 'import sys; sys.stdout.write("{\"session_note\":\"\\ud800\",\"cwd\":\"/tmp\",\"tool_input\":{\"command\":\"rm -rf $HOME\"}}")' 2>/dev/null)"

# want_env <label> <expected "verdict|rc"> <hook> <payload>
# Asserts the PAIR positively. Never `!= "deny"`: a negative over a verdict that
# can be empty is satisfied by absence, which is the whole defect above.
want_env() {
  local label="$1" expect="$2" hook="$3" payload="$4"; shift 4
  local got
  got="$(envelope_verdict "$hook" "$payload" "$@")"
  if [[ "$got" == "$expect" ]]; then pass "$label → $got"
  else fail "$label: want $expect, got $got"; fi
}

if [[ -z "$SURROGATE_PAYLOAD" ]]; then
  skip "python3 missing — unreadable-envelope case (1 assertion not run)"
else
  # exit 0 is half the point: the ask has to arrive as a DECISION. Before #7173
  # the same input aborted the script, which a verdict-only assertion could not
  # tell apart from a clean allow.
  want_env "[.claude] unreadable envelope ASKS (ADR-157), exit 0" "ask|0" "$CLAUDE_GUARD" "$SURROGATE_PAYLOAD"
fi

NONSTRING_PAYLOAD_EARLY='{"cwd":"/tmp","tool_input":{"command":["git","stash"]}}'
# jq_missing — a silent-regression class: with jq gone the guard's normal parse
# path is unavailable entirely, and the hand-written printf envelope is the only
# surviving channel through which it can still say anything at all. The shim
# keeps every binary the hook needs and drops only jq; `$src == /*` rejects
# shell builtins and functions, whose `command -v` returns a bare name and would
# otherwise create a dangling self-referential symlink (measured — it silently
# broke `grep` inside the shim and made this fixture report the wrong thing).
_jqless_path() {
  local d b src; d="$(mktemp -d -p "$TMP")"
  for b in bash sh env grep sed awk tr cat cut head tail sort uniq wc date \
           mkdir rm ln ls mktemp dirname basename realpath xargs flock git printf; do
    src="$(env -i PATH=/usr/bin:/bin bash --noprofile --norc -c 'command -v "$1"' _ "$b" 2>/dev/null)" || continue
    [[ "$src" == /* ]] || continue
    ln -sf "$src" "$d/$b" 2>/dev/null
  done
  PATH="$d" command -v jq >/dev/null 2>&1 && { echo ""; return; }
  echo "$d"
}
_SHIM="$(_jqless_path)"
if [[ -z "$_SHIM" ]]; then
  fail "[fixture] jq still reachable on the jq-less shim — the jq_missing case would be vacuous"
else
  v="$(envelope_verdict "$CLAUDE_GUARD" "$NONSTRING_PAYLOAD_EARLY" "PATH=$_SHIM")"
  [[ "$v" == "ask|0" ]] && pass "[.claude] jq missing → ask, exit 0 → $v" \
                        || fail "[.claude] jq missing: want ask|0, got $v"
fi

# SIGPIPE PADDING BYPASS (behavioural). grep-q-pipe-guard.test.sh forbids the
# SHAPE textually; this asserts the CONSEQUENCE, which is what actually matters
# and what no test covered. Under `set -o pipefail` a `producer | grep -q` whose
# match is early leaves the producer with unwritten data, it takes SIGPIPE (141),
# pipefail promotes that to the pipeline status, the `if` reads false and the
# guard is skipped. Measured before the fix: rm -rf on HOME denied at 8 KB and
# returned rc 0 with NO decision at 131 KB and 526 KB.
#
# The padding must exceed the 64 KiB pipe buffer or the race cannot occur at all
# — a smaller fixture passes against the broken code and proves nothing.
_pad_payload() { # <command> -> json with ~128 KB of trailing padding
  python3 -c '
import json,sys
sys.stdout.write(json.dumps({"cwd":"/tmp",
  "tool_input":{"command":sys.argv[1]+"\n"+("#"*79+"\n")*1700}}))' "$1"
}
if ! command -v python3 >/dev/null 2>&1; then
  skip "python3 missing — SIGPIPE padding-bypass case (1 assertion not run)"
else
  # `rm -rf $HOME` and not `git stash`: the stash guard only fires when the
  # resolved dir is inside a worktree, so on a /tmp fixture it correctly allows
  # and the case would pass for the wrong reason. The recursive-delete ownership
  # proof denies unconditionally, which is what makes this a real pin — and it
  # is the guard the measured bypass actually defeated.
  want_env "[.claude] a 128 KB-padded 'rm -rf \$HOME' still DENIES (SIGPIPE bypass)" "deny|0" \
    "$CLAUDE_GUARD" "$(_pad_payload 'rm -rf $HOME')"
fi

# Non-string: the original ADR-156 signature. The guard must refuse to coerce a
# JSON array into a command string rather than stringifying it and scanning the
# result.
NONSTRING_PAYLOAD='{"cwd":"/tmp","tool_input":{"command":["git","stash"]}}'
want_env "[.claude] non-string command ASKS, exit 0" "ask|0" "$CLAUDE_GUARD" "$NONSTRING_PAYLOAD"

# Absent / null tool_input — the AVAILABILITY direction. A shape check that
# mixes up jq's `null` value with the STRING "null" its `type` returns turns
# every no-tool_input envelope into a refusal, which blocks calls the guard has
# no business touching. Both spellings must parse cleanly and emit no decision.
for payload in '{"cwd":"/tmp"}' '{"cwd":"/tmp","tool_input":null}'; do
  label="$([[ "$payload" == *tool_input* ]] && echo "null" || echo "absent")"
  want_env "[.claude] $label tool_input parses cleanly" "none|0" "$CLAUDE_GUARD" "$payload"
done

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed, $SKIPPED skipped ==="

# --- ANTI-VACUITY FLOOR (ADR-193) -----------------------------------------------------------
# Absolute and hand-ratcheted, NOT derived from the run. `FAIL -eq 0` alone is satisfied by a
# suite that executed nothing, and this file is unusually exposed to that: ADR-245's retirement
# removed every comparison arm, halving the case count in one edit, and a later edit that guts
# the rest the same way would report `0/0 passed, 0 failed` and exit 0.
#
# Measured 2026-09-23 immediately after that reduction: 12 executed cases. Raise this in the SAME
# edit that adds a case, never in a later tidy-up — slack in a floor is deletion budget.
#
# Reported with printf + exit, never through pass()/fail(): a floor that calls the helper it
# backstops cannot see that helper being disarmed.
MIN_CASES=12
_executed=$((PASS + FAIL))
if [[ "$_executed" -lt "$MIN_CASES" ]]; then
  printf '\nFATAL: anti-vacuity: %d case(s) executed, floor is %d. The suite ran but did not assert what it claims to.\n' \
    "$_executed" "$MIN_CASES" >&2
  exit 1
fi

[[ "$FAIL" -eq 0 ]] || exit 1
