#!/usr/bin/env bash
# Review-evidence gate PARITY across both hook copies (#6724).
#
# WHY THIS EXISTS
#
# `.claude/hooks/pre-merge-rebase.sh` and `.openhands/hooks/pre-merge-rebase.sh`
# implement the same merge gate for two harness ecosystems. Every other suite
# binds HOOK to the `.claude` copy, so the openhands copy had NO coverage at all
# and its divergence was structurally undetectable. That is not hypothetical:
#
#   * its Signal 2 matched only the legacy "refactor: add code review findings"
#     subject and had never gained the `review: ` fix-inline convention, so the
#     gate was silently weaker on that host for a long time; and
#   * its command matcher was missing the `\s--\s` alternative, so the
#     `with_lock ... -- gh pr merge` wrapped form bypassed the hook ENTIRELY.
#
# Both were found by review of #6727 and fixed. This suite is what stops them
# recurring. It deliberately tests only the shared gate contract, not the
# `.claude` copy's extra machinery (incident emission, lock acquisition,
# headless routing), which the openhands port does not have.
#
# PROTOCOL DIFFERENCE — the two copies deny differently, and the assertions
# below normalise it rather than assuming one shape:
#   .claude     input .cwd          -> exit 0, {"hookSpecificOutput":{"permissionDecision":"deny"}}
#   .openhands  input .working_dir  -> exit 2, {"decision":"deny"}
#
# Run via:  bash .claude/hooks/pre-merge-rebase-parity.test.sh
# Auto-discovered by scripts/test-all.sh via the `.claude/hooks/*.test.sh` glob
# in the `scripts` shard, which ci.yml runs — so this gates in CI.

set -uo pipefail

# Refuse before writing, rather than let an empty operand retarget a git write at whatever
# repository the caller happens to be standing in. `git -C ""` does NOT error — it silently
# operates on the current directory, which under TEST_GROUP=scripts is the developer's live
# worktree, whose `.git/config` is the SHARED file every worktree on the machine inherits.
#
# Rejects bare `/` as well as empty: a `/*` case arm accepts `/`, and `rm -rf "/"/*` is the worst
# outcome available in this corpus. Tests the LEADING `/` only, never a `realpath` comparison,
# which breaks on a symlinked /tmp.
#
# The body below is a COPY. The canonical definition lives in
# plugins/soleur/test/test-helpers.sh; plugins/soleur/test/fixture-dir-operand-assert.test.sh
# asserts this copy is byte-equal to it. Do not reword it in one file only. #7652
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    /)  printf 'FATAL: fixture dir is bare /; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_HOOK="$SCRIPT_DIR/pre-merge-rebase.sh"
OPENHANDS_HOOK="$REPO_ROOT/.openhands/hooks/pre-merge-rebase.sh"

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

for h in "$CLAUDE_HOOK" "$OPENHANDS_HOOK"; do
  [[ -f "$h" ]] || { echo "FAIL: hook copy missing: $h"; exit 1; }
done

# denied <hook> <work_dir> <command> -> "yes" | "no"
# Normalises the two protocols. Sends BOTH input keys so one payload drives
# either copy.
denied() {
  local hook="$1" work="$2" cmd="$3" payload out
  payload=$(jq -nc --arg c "$work" --arg x "$cmd" \
    '{tool_input: {command: $x}, cwd: $c, working_dir: $c}')
  # Exit code is deliberately ignored: the two copies use different codes for
  # the same verdict (.claude exits 0 with a deny payload, .openhands exits 2).
  # The decision field is the shared contract.
  # INCIDENTS_REPO_ROOT redirected: without it this helper appended REAL rows to
  # the operator's live ledger on every run — synthetic `gh pr merge 900` command
  # text in `command_snippet`, feeding rule-metrics-aggregate.sh. Pre-existing,
  # and the other half of the same defect fixed in envelope_verdict below.
  local _sb; _sb="$(mktemp -d -p "$TMP")"
  out=$(printf '%s' "$payload" | env INCIDENTS_REPO_ROOT="$_sb" "$hook" 2>/dev/null) || true
  rm -rf "$_sb"
  if jq -e '(.hookSpecificOutput.permissionDecision // .decision) == "deny"' >/dev/null 2>&1 <<<"$out"; then
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
  git -C "$work" fetch -q origin

  git -C "$work" checkout -q -b feat-parity
  echo feature > "$work/feature.txt"
  git -C "$work" add feature.txt
  git -C "$work" commit -q -m "feat: work"

  if [[ "$mode" == "reviewed" ]]; then
    git -C "$work" commit -q --allow-empty -m "chore: post-review checkpoint

Reviewed-By-Soleur: soleur:review"
  fi
}

echo "=== pre-merge-rebase gate parity (.claude vs .openhands) ==="
echo ""

TMP=$(mktemp -d -t pmr-parity.XXXXXXXX)
trap 'rm -rf "$TMP"' EXIT

# The three gate outcomes both copies must agree on.
i=0
for case_spec in \
  "unreviewed|yes|no review evidence -> DENY" \
  "reviewed|no|Reviewed-By-Soleur trailer -> ALLOW" \
  "main-only|yes|evidence only on MAIN (the #6724 vacuity) -> DENY" \
  ; do
  mode="${case_spec%%|*}"; rest="${case_spec#*|}"
  want="${rest%%|*}"; label="${rest#*|}"
  for hook in "$CLAUDE_HOOK" "$OPENHANDS_HOOK"; do
    i=$((i + 1))
    work="$TMP/w$i"
    build_repo "$work" "$mode" "$TMP/o$i.git"
    got=$(denied "$hook" "$work" "gh pr merge 900 --squash")
    name="$(basename "$(dirname "$(dirname "$hook")")")"
    if [[ "$got" == "$want" ]]; then
      pass "[$name] $label"
    else
      fail "[$name] $label — expected denied=$want, got denied=$got"
    fi
  done
done

echo ""
echo "T-M: the wrapped form must be intercepted by BOTH copies"
# `bash session-state.sh with_lock merge-main 600 -- gh pr merge ...` was NOT
# matched by the openhands copy, so the whole hook exited before any check ran.
# An unreviewed branch under the wrapped form must still deny.
for hook in "$CLAUDE_HOOK" "$OPENHANDS_HOOK"; do
  i=$((i + 1))
  work="$TMP/w$i"
  build_repo "$work" "unreviewed" "$TMP/o$i.git"
  got=$(denied "$hook" "$work" "bash session-state.sh with_lock merge-main 600 -- gh pr merge 901 --squash")
  name="$(basename "$(dirname "$(dirname "$hook")")")"
  if [[ "$got" == "yes" ]]; then
    pass "[$name] wrapped 'with_lock ... -- gh pr merge' is intercepted"
  else
    fail "[$name] wrapped form BYPASSED the gate — the \\s--\\s matcher alternative is missing"
  fi
done

echo ""
echo "T-S: both copies carry the same Signal 2 matcher"
# Source-level parity for the alternation itself. The behavioural cases above
# cannot distinguish "matches the legacy subject only" from "matches both" when
# the fixture happens to use the trailer.
#
# Anchored on the CALL SHAPE, not the bare tokens. A first draft of this block
# grepped for `review: ` as a substring and SURVIVED the mutation it exists to
# catch: reverting the openhands copy to the legacy-only matcher left the phrase
# `review: ` sitting in an explanatory COMMENT, which satisfied the grep. Same
# class this PR fixes elsewhere — a body-grep sees comments too, so assert on
# something a comment cannot produce.
#
# Compared as a FIXED string (grep -qF), not an ERE. The matcher now contains
# `(`, `)`, `[`, `^`, `*`, `?` and a literal backslash for the optional
# conventional-commit scope; hand-escaping all of that into a regex-matching-a-
# regex is where the assertion silently rots. -F also makes the parity check
# exact — byte-for-byte, which is what "both copies carry the same matcher"
# means — and matches the trailer-lookup check below. A comment cannot produce
# the full `grep -E "..."` call, so the anti-drift property above is preserved.
SIG2_CALL='grep -E "^[a-f0-9]+ (refactor: add code review findings|review(\([^)]*\))?: )"'
for hook in "$CLAUDE_HOOK" "$OPENHANDS_HOOK"; do
  name="$(basename "$(dirname "$(dirname "$hook")")")"
  if grep -qF -- "$SIG2_CALL" "$hook"; then
    pass "[$name] Signal 2 uses the anchored two-pattern alternation"
  else
    fail "[$name] Signal 2 drift — expected the anchored alternation matching the legacy subject and 'review: ' with an optional (scope)"
  fi
done
# The trailer lookup must be present in both, anchored on the git format string
# rather than the bare key (which appears in prose in both files).
for hook in "$CLAUDE_HOOK" "$OPENHANDS_HOOK"; do
  name="$(basename "$(dirname "$(dirname "$hook")")")"
  if grep -qF -- "trailers:key=Reviewed-By-Soleur,valueonly" "$hook"; then
    pass "[$name] trailer lookup present"
  else
    fail "[$name] trailer lookup missing — a zero-finding review cannot satisfy this copy"
  fi
done


# ===========================================================================
# ENVELOPE PARITY — the trust boundary, not just the merge gate (#7173).
# ===========================================================================
# The three cases below make the two harnesses' ENVELOPE handling executable.
# Until now the divergence was documented in prose and asserted nowhere, which
# is the same structural blindness the merge-gate half of this file exists to
# fix — this file's own header records that silent divergence has happened
# twice already.
#
# The two protocols differ by design and the cases assert the DIFFERENCE, not a
# false symmetry:
#
#   reason class      .claude                    .openhands
#   ----------------  -------------------------  --------------------------
#   nonstring         ask   (ADR-157)            deny  (no `ask` exists here)
#   unparseable       ask                        deny
#   jq_missing        ask, printf envelope       fail OPEN, loudly
#   absent tool_input parses cleanly             parses cleanly
#
# The `unparseable` row is written against MEASURED behaviour. An earlier draft
# of this case asserted the mirror "falls through" on an unparseable envelope
# and would have PASSED while asserting the opposite of the truth: the mirror's
# own `unparseable` branch is unreachable (it requires the shape program to fail
# on a document the simpler extractions already parsed), and before #7173 a
# malformed document did not fall through at all — it aborted the script at rc 5
# with no decision. Asserting "no deny on stdout" would have been satisfied by
# that abort. It is asserted as a deny because that is what the mirror now does.
#
# `envelope_verdict` deliberately does NOT normalise the two protocols the way
# `denied` above does: which harness denies and which asks IS the property.
# Echoes "<verdict>|<rc>". The rc half is not decoration: without it a hook that
# ABORTS with no decision is indistinguishable from one that allows cleanly, and
# that is the exact pre-#7173 behaviour these cases were written to pin.
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
# INCIDENTS_REPO_ROOT is redirected per call. Without it these hooks appended
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
  v=$(jq -r '(.hookSpecificOutput.permissionDecision // .decision // "other")' 2>/dev/null <<<"$out") \
    || v="other"
  [[ -z "$v" ]] && v="other"
  echo "$v|$rc"
}

CLAUDE_GUARD="$SCRIPT_DIR/guardrails.sh"
OPENHANDS_GUARD="$REPO_ROOT/.openhands/hooks/guardrails.sh"

# A lone high surrogate in a SIBLING field. The command itself stays a clean,
# fully-armed `rm -rf $HOME` — so this is not a malformed-command case, it is a
# case where the guard cannot read an envelope that carries a live command.
# OpenHands is Python: json.dumps re-emits \ud800, so the document is valid to
# its parser and invalid to jq.
SURROGATE_PAYLOAD="$(python3 -c 'import sys; sys.stdout.write("{\"working_dir\":\"\\ud800\",\"cwd\":\"/tmp\",\"tool_input\":{\"command\":\"rm -rf $HOME\"}}")' 2>/dev/null)"

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

# The mirror is THREE blocking hooks, not one. Only guardrails.sh was exercised
# before, so pre-merge-rebase.sh's and worktree-write-guard.sh's envelope
# handling — including the availability fix — was asserted nowhere.
OH_PMR="$REPO_ROOT/.openhands/hooks/pre-merge-rebase.sh"
OH_WWG="$REPO_ROOT/.openhands/hooks/worktree-write-guard.sh"

if [[ -z "$SURROGATE_PAYLOAD" ]]; then
  skip "python3 missing — unparseable-envelope parity cases (4 assertions not run)"
else
  want_env "[.claude] unparseable envelope ASKS (ADR-157), exit 0" "ask|0" "$CLAUDE_GUARD" "$SURROGATE_PAYLOAD"
  # rc 2 is the point: before #7173 this aborted at rc 5 with NO decision, which
  # a verdict-only assertion could not tell apart from a clean allow.
  want_env "[.openhands] unparseable envelope DENIES, exit 2" "deny|2" "$OPENHANDS_GUARD" "$SURROGATE_PAYLOAD"
  want_env "[.openhands pre-merge-rebase] unparseable DENIES, exit 2" "deny|2" "$OH_PMR" "$SURROGATE_PAYLOAD"
  want_env "[.openhands worktree-write-guard] unparseable DENIES, exit 2" "deny|2" "$OH_WWG" "$SURROGATE_PAYLOAD"
fi

NONSTRING_PAYLOAD_EARLY='{"working_dir":"/tmp","cwd":"/tmp","tool_input":{"command":["git","stash"]}}'
# jq_missing — the only fail-OPEN class, and the one whose regression is silent.
# It was asserted NOWHERE for the mirror before this: named in the table above
# and in the ADR, tested by nothing. The shim keeps every binary the hooks need
# and drops only jq; `$src == /*` rejects shell builtins and functions, whose
# `command -v` returns a bare name and would otherwise create a dangling
# self-referential symlink (measured — it silently broke `grep` inside the shim
# and made this fixture report the wrong thing).
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
  fail "[fixture] jq still reachable on the jq-less shim — the jq_missing cases would be vacuous"
else
  # .claude ASKS (the printf envelope is the only surviving channel there).
  v="$(envelope_verdict "$CLAUDE_GUARD" "$NONSTRING_PAYLOAD_EARLY" "PATH=$_SHIM")"
  [[ "$v" == "ask|0" ]] && pass "[.claude] jq missing → ask, exit 0 → $v" \
                        || fail "[.claude] jq missing: want ask|0, got $v"
  # .openhands fails OPEN on a benign command — denying would block its own repair.
  v="$(envelope_verdict "$OPENHANDS_GUARD" '{"working_dir":"/tmp","tool_input":{"command":"echo hi"}}' "PATH=$_SHIM")"
  [[ "$v" == "none|0" ]] && pass "[.openhands] jq missing + benign → fails open, exit 0 → $v" \
                         || fail "[.openhands] jq missing + benign: want none|0, got $v"
  # …but NOT unconditionally: a protected pattern in the raw document still denies.
  v="$(envelope_verdict "$OPENHANDS_GUARD" '{"working_dir":"/tmp","tool_input":{"command":"rm -rf $HOME"}}' "PATH=$_SHIM")"
  [[ "$v" == "deny|2" ]] && pass "[.openhands] jq missing + protected pattern → deny, exit 2 → $v" \
                         || fail "[.openhands] jq missing + protected pattern: want deny|2, got $v"
  # …and the repair path stays open, which is the whole basis of the fail-open.
  v="$(envelope_verdict "$OPENHANDS_GUARD" '{"working_dir":"/tmp","tool_input":{"command":"apt-get install -y jq"}}' "PATH=$_SHIM")"
  [[ "$v" == "none|0" ]] && pass "[.openhands] jq missing + the repair command itself → allowed → $v" \
                         || fail "[.openhands] jq missing + repair command: want none|0, got $v"
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
sys.stdout.write(json.dumps({"working_dir":"/tmp","cwd":"/tmp",
  "tool_input":{"command":sys.argv[1]+"\n"+("#"*79+"\n")*1700}}))' "$1"
}
if ! command -v python3 >/dev/null 2>&1; then
  skip "python3 missing — SIGPIPE padding-bypass parity case (1 assertion not run)"
else
  # `rm -rf $HOME` and not `git stash`: the stash guard only fires when the
  # resolved dir is inside a worktree, so on a /tmp fixture it correctly allows
  # and the case would pass for the wrong reason. The recursive-delete ownership
  # proof denies unconditionally, which is what makes this a real pin — and it
  # is the guard the measured bypass actually defeated.
  want_env "[.openhands] a 128 KB-padded 'rm -rf \$HOME' still DENIES (SIGPIPE bypass)" "deny|2" \
    "$OPENHANDS_GUARD" "$(_pad_payload 'rm -rf $HOME')"
fi

# `internal` — the shape program itself failing must be LOUD, not silent.
# Before the fix the fallback assigned a value nothing branched on, so a broken
# shape program disarmed every guard below it with no stdout, no stderr and no
# record. Asserted behaviourally against a MUTATED COPY, because the class is
# unreachable on a correct program by construction.
_broken_shape_copy="$TMP/guardrails-broken-shape.sh"
sed 's/if (type == "object")/if (typeXX == "object")/' "$OPENHANDS_GUARD" > "$_broken_shape_copy"
if ! grep -q 'typeXX' "$_broken_shape_copy"; then
  fail "[fixture] could not break the shape program — the internal-class case would be vacuous"
else
  _stderr="$(printf '%s' "$NONSTRING_PAYLOAD_EARLY" | bash "$_broken_shape_copy" 2>&1 >/dev/null || true)"
  if [[ -n "${_stderr//[[:space:]]/}" ]]; then
    pass "[.openhands] a broken shape program fails open LOUDLY (internal class)"
  else
    fail "[.openhands] a broken shape program failed open SILENTLY — no stdout, no stderr, guards disarmed"
  fi
fi

# Non-string: the original ADR-156 signature. Both must refuse to coerce; they
# refuse with different verbs.
NONSTRING_PAYLOAD='{"working_dir":"/tmp","cwd":"/tmp","tool_input":{"command":["git","stash"]}}'
want_env "[.claude] non-string command ASKS, exit 0" "ask|0" "$CLAUDE_GUARD" "$NONSTRING_PAYLOAD"
want_env "[.openhands] non-string command DENIES, exit 2" "deny|2" "$OPENHANDS_GUARD" "$NONSTRING_PAYLOAD"

# Absent / null tool_input. This is the case NEITHER of the two divergence
# classes above would catch, and the mirror got it wrong in the AVAILABILITY
# direction: its type conjunct read `$t == null` where jq's `type` returns the
# STRING "null", so the comparison was unsatisfiable and every payload with an
# absent or null tool_input was DENIED — on a harness with no `ask` and no
# recovery path, while .claude parsed the same payloads cleanly.
for payload in '{"working_dir":"/tmp","cwd":"/tmp"}' '{"working_dir":"/tmp","cwd":"/tmp","tool_input":null}'; do
  label="$([[ "$payload" == *tool_input* ]] && echo "null" || echo "absent")"
  want_env "[.claude] $label tool_input parses cleanly" "none|0" "$CLAUDE_GUARD" "$payload"
  for h in "$OPENHANDS_GUARD" "$OH_PMR" "$OH_WWG"; do
    want_env "[.openhands $(basename "$h" .sh)] $label tool_input parses cleanly" "none|0" "$h" "$payload"
  done
done

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed, $SKIPPED skipped ==="
[[ "$FAIL" -eq 0 ]] || exit 1
