#!/usr/bin/env bash
# shellcheck disable=SC2015  # `A && B || C` is the row idiom
# Suite for scripts/verify-agent-security-slice1.sh, the discoverability probe the W2 plan's
# Observability section names (knowledge-base/project/plans/2026-10-06-feat-plugin-destructive-command-guard-w2-plan.md).
#
# PROPERTY. The probe prints `slice1-security: ok` (exit 0) only when the plugin's destructive-command
# guard is registered under a PreToolUse matcher that reads Bash AND, run from a temp HOME and cwd, answers
# `ask` for `terraform destroy`, `deny` for `rm -rf ~` and nothing for `ls`; any other state prints
# `slice1-security: FAIL <named reason>` and exits 1. A missing jq or perl is a named FAIL, never a pass.
#
# NEVER THE LIVE HOOK. The probe's SLICE1_PLUGIN_ROOT seam points it at a COPY of plugins/soleur/hooks in a
# temp dir; every red row edits the copy. The live tree is read, never written.
#
# ROWS. A: controls (live tree; the unedited copy through the seam, which proves the seam reads the copy).
# B: the guard check turns red for a hook registered under a non-Bash matcher, a hook that is not registered
# at all, a hook that answers nothing for `terraform destroy`, a hook that asks for `ls`, a hook that asks
# where it must deny, a hook that denies where it must ask, a missing hook file and an unreadable hooks.json.
# C: missing jq / missing perl are named FAILs (a PATH of symlinks without that one tool). D: the probe
# ignores an ambient kill switch and ambient GIT_* variables (it strips both), stays inside the observability
# gate's 15 s cap, and contains no negated grep.
#
# Anti-vacuity: the case counter moves at the call site (never in pass/fail), pass+fail must equal it, an
# instrument self-test drives both helpers, and the row-count floor is a literal directly above its `if`,
# reported by a direct printf + exit 1.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="${SLICE1_SCRIPT_UNDER_TEST:-$REPO_ROOT/scripts/verify-agent-security-slice1.sh}"  # the override lets a COPY of the probe be driven (RED proof against the pre-W2 probe)
LIVE_HOOKS="$REPO_ROOT/plugins/soleur/hooks"
BASH_BIN="$(command -v bash)"

passes=0; fails=0; CASES=0
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); echo "  FAIL: $1" >&2; }
row() { # row <desc> <cond: ok|anything else> [detail]
  CASES=$((CASES + 1))
  if [[ "$2" == ok ]]; then pass "$1"; else fail "$1${3:+ -- $3}"; fi
}

_iv_p="$passes"; _iv_f="$fails"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0

command -v jq >/dev/null 2>&1 || { echo "[FATAL] jq required" >&2; exit 1; }
command -v perl >/dev/null 2>&1 || { echo "[FATAL] perl required" >&2; exit 1; }
[[ -f "$SCRIPT" && -d "$LIVE_HOOKS" ]] || { echo "[FATAL] probe or live hooks directory missing" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

OUT=""; RC=0
run_probe() { # run_probe [VAR=value ...] -> OUT (stdout+stderr), RC
  OUT="$(env "$@" "$BASH_BIN" "$SCRIPT" 2>&1)"; RC=$?
}
mk_plugin() { # mk_plugin <name> -> a fresh copy of the live hooks directory under $WORK/<name>/hooks
  mkdir -p "$WORK/$1" && cp -R "$LIVE_HOOKS" "$WORK/$1/hooks"
}
red() { # red <desc> <fragment> : the last run_probe exited 1 and said FAIL with the fragment, and never ok
  local ok=
  [[ "$RC" -eq 1 && "$OUT" == *"slice1-security: FAIL"*"$2"* && "$OUT" != *"slice1-security: ok"* ]] && ok=ok
  row "$1" "$ok" "rc=$RC out=${OUT//$'\n'/ | }"
}
write_stub() { # write_stub <path> <body...> : replace a hook with a stub
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$1"; chmod +x "$1"
}
ASK='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"stub"}}'
DENY='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"stub"}}'

# ---- A. controls --------------------------------------------------------------------------------
t0="$(date +%s)"
run_probe
t1="$(date +%s)"
row "control: the live tree prints ok and exits 0" "$([[ "$RC" -eq 0 && "$OUT" == "slice1-security: ok" ]] && echo ok)" "rc=$RC out=$OUT"
mk_plugin ctl
run_probe SLICE1_PLUGIN_ROOT="$WORK/ctl"
row "control: an unedited copy through the seam prints ok" "$([[ "$RC" -eq 0 && "$OUT" == "slice1-security: ok" ]] && echo ok)" "rc=$RC out=$OUT"

# ---- B. the guard check goes red ----------------------------------------------------------------
mk_plugin m1
jq '(.hooks.PreToolUse[] | select(any(.hooks[]?; (.command // "") | contains("destructive-command-guard.sh"))) | .matcher) = "^Read$"' \
  "$WORK/m1/hooks/hooks.json" > "$WORK/m1/h.json" && mv "$WORK/m1/h.json" "$WORK/m1/hooks/hooks.json"
run_probe SLICE1_PLUGIN_ROOT="$WORK/m1"
red "a guard registered under a non-Bash matcher turns the probe red" "guard registered under a PreToolUse matcher that reads Bash"

mk_plugin m2
jq '.hooks.PreToolUse |= map(select(any(.hooks[]?; (.command // "") | contains("destructive-command-guard.sh")) | not))' \
  "$WORK/m2/hooks/hooks.json" > "$WORK/m2/h.json" && mv "$WORK/m2/h.json" "$WORK/m2/hooks/hooks.json"
run_probe SLICE1_PLUGIN_ROOT="$WORK/m2"
red "a guard that is not registered at all turns the probe red" "guard registered under a PreToolUse matcher that reads Bash"

mk_plugin m3
write_stub "$WORK/m3/hooks/destructive-command-guard.sh" 'exit 0'
run_probe SLICE1_PLUGIN_ROOT="$WORK/m3"
red "a hook that answers nothing for terraform destroy turns the probe red" "guard probe 'terraform destroy' answered '', want ask"
row "the same silent hook also fails the rm -rf ~ probe" "$([[ "$OUT" == *"guard probe 'rm -rf ~' answered '', want deny"* ]] && echo ok)" "out=$OUT"

mk_plugin m4
write_stub "$WORK/m4/hooks/destructive-command-guard.sh" "printf '%s\\n' '$ASK'"
run_probe SLICE1_PLUGIN_ROOT="$WORK/m4"
red "a hook that asks for ls turns the probe red" "guard probe 'ls' answered 'ask', want silence"
row "a hook that always asks also fails the rm -rf ~ probe (ask where deny is required)" "$([[ "$OUT" == *"guard probe 'rm -rf ~' answered 'ask', want deny"* ]] && echo ok)" "out=$OUT"

mk_plugin m5
write_stub "$WORK/m5/hooks/destructive-command-guard.sh" "printf '%s\\n' '$DENY'"
run_probe SLICE1_PLUGIN_ROOT="$WORK/m5"
red "a hook that denies terraform destroy (must ask) turns the probe red" "guard probe 'terraform destroy' answered 'deny', want ask"

mk_plugin m6
rm -f "$WORK/m6/hooks/destructive-command-guard.sh"
run_probe SLICE1_PLUGIN_ROOT="$WORK/m6"
red "a missing hook file is a named FAIL" "missing file"

mk_plugin m7
printf '{ not json' > "$WORK/m7/hooks/hooks.json"
run_probe SLICE1_PLUGIN_ROOT="$WORK/m7"
red "an unreadable hooks.json turns the probe red" "guard registered under a PreToolUse matcher that reads Bash"

# ---- C. missing dependencies are named failures -------------------------------------------------
farm_without() { # farm_without <tool> -> a PATH directory holding symlinks to everything the probe and hook need except <tool>
  local d="$WORK/farm-$1" t p
  mkdir -p "$d"
  for t in bash env dirname grep mktemp rm cat sed awk cp mv cut tr head sort uniq git jq perl timeout date; do
    [[ "$t" == "$1" ]] && continue
    p="$(command -v "$t" 2>/dev/null)" && [[ "$p" == /* ]] && ln -sf "$p" "$d/$t"
  done
  printf '%s' "$d"
}
run_probe PATH="$(farm_without jq)"
red "a PATH without jq is a named FAIL, not a pass" "guard check needs jq on PATH"
run_probe PATH="$(farm_without perl)"
red "a PATH without perl is a named FAIL, not a pass" "guard check needs perl on PATH"

# ---- D. environment hygiene, cap, shape ---------------------------------------------------------
run_probe SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1
row "an ambient kill switch does not blind the probe (it unsets it)" "$([[ "$RC" -eq 0 && "$OUT" == "slice1-security: ok" ]] && echo ok)" "rc=$RC out=$OUT"
run_probe GIT_DIR=/nonexistent/dir GIT_INDEX_FILE=/nonexistent/index GIT_WORK_TREE=/nonexistent
row "ambient GIT_* variables do not leak into the probe (stripped by prefix)" "$([[ "$RC" -eq 0 && "$OUT" == "slice1-security: ok" ]] && echo ok)" "rc=$RC out=$OUT"
row "the probe finishes well inside the observability gate's 15 s cap" "$([[ $((t1 - t0)) -lt 15 ]] && echo ok)" "took $((t1 - t0)) s"
neg="$(grep -c -E '^[^#]*(! *grep|grep +-[a-zA-Z]*[vL])' "$SCRIPT" || true)"
row "the probe contains no negated grep" "$([[ "$neg" == 0 ]] && echo ok)" "count=$neg"
ok_lines="$(grep -c -E '^  echo "slice1-security: ok"$' "$SCRIPT" || true)"
row "the probe prints its ok line from exactly one place" "$([[ "$ok_lines" == 1 ]] && echo ok)" "count=$ok_lines"

# ---- summary and the vacuity floor --------------------------------------------------------------
echo "cases=$CASES passes=$passes fails=$fails"
if [[ $((passes + fails)) -ne "$CASES" ]]; then
  printf '[FATAL] anti-vacuity: %s verdicts recorded for %s cases\n' "$((passes + fails))" "$CASES" >&2; exit 1
fi
MIN_CASES=18
if [[ "$CASES" -lt "$MIN_CASES" ]]; then
  printf '[FATAL] anti-vacuity: only %s assertions ran, floor is %s\n' "$CASES" "$MIN_CASES" >&2
  exit 1
fi
[[ "$fails" -eq 0 ]]
