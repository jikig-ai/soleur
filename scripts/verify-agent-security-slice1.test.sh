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
# gate's 15 s cap, and contains no negated grep. E: the probe's own setup is observable. A stub hook judges the
# environment it is run in (no GIT_*, no kill switch, HOME equal to the working directory and to the envelope's cwd) and
# answers only when it is clean, so a probe that drops its GIT_* strip, its HOME= or its cd turns red (mutated COPIES of
# the probe, driven through the SLICE1_SCRIPT_UNDER_TEST seam). F: a bash that cannot do process substitution (a PATH
# whose `bash` fails `-c`) is a named FAIL ("needs /dev/fd (process substitution)"), not an "answered 'ask', want deny".
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

# The body below is the CANONICAL copy, asserted byte-for-byte against every other copy by
# plugins/soleur/test/fixture-dir-operand-assert.test.sh. Do not reword it in one file only. #7652
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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

OUT=""; RC=0
run_probe() { # run_probe [VAR=value ...] -> OUT (stdout+stderr), RC
  OUT="$(env "$@" "$BASH_BIN" "$SCRIPT" 2>&1)"; RC=$?
}
run_probe_with() { # run_probe_with <probe script> [VAR=value ...] -> OUT, RC
  local script="$1"; shift
  OUT="$(env "$@" "$BASH_BIN" "$script" 2>&1)"; RC=$?
}
replace_once() { # replace_once <src> <dst> <literal anchor> <replacement>: the anchor must occur exactly once (perl, \Q..\E)
  A="$3" R="$4" perl -0e 'my ($src, $dst) = @ARGV; open(my $in, "<", $src) or exit 2; local $/; my $s = <$in>; close $in;
    my $a = $ENV{A}; my $r = $ENV{R}; my $n = () = $s =~ /\Q$a\E/g; exit 3 unless $n == 1;
    $s =~ s/\Q$a\E/$r/; open(my $out, ">", $dst) or exit 2; print $out $s; close $out;' "$1" "$2"
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
row "ambient GIT_* variables do not break the real-hook probe (smoke; section E proves the strip with a stub that sees them)" "$([[ "$RC" -eq 0 && "$OUT" == "slice1-security: ok" ]] && echo ok)" "rc=$RC out=$OUT"
row "the probe finishes well inside the observability gate's 15 s cap" "$([[ $((t1 - t0)) -lt 15 ]] && echo ok)" "took $((t1 - t0)) s"
neg="$(grep -c -E '^[^#]*(! *grep|grep +-[a-zA-Z]*[vL])' "$SCRIPT" || true)"
row "the probe contains no negated grep" "$([[ "$neg" == 0 ]] && echo ok)" "count=$neg"
ok_lines="$(grep -c -E '^  echo "slice1-security: ok"$' "$SCRIPT" || true)"
row "the probe prints its ok line from exactly one place" "$([[ "$ok_lines" == 1 ]] && echo ok)" "count=$ok_lines"

# ---- E. the probe's setup lines are load-bearing (observable through a stub that judges its own environment) ---------------
# The stub answers like the real guard (ask for terraform destroy, deny for rm -rf ~, nothing otherwise) ONLY when it runs in the
# environment the probe promises: no GIT_* variable, no kill switch, HOME the probe's temp dir, the working directory that same
# dir and the envelope's cwd. In any other environment it answers nothing, which the probe reports as three named FAILs.
mk_plugin env
cat > "$WORK/env/hooks/destructive-command-guard.sh" <<'STUBEOF'
#!/usr/bin/env bash
in="$(cat)"
clean=1
[ -z "${SOLEUR_DISABLE_DESTRUCTIVE_GUARD+x}" ] || clean=0
for v in $(compgen -e); do case "$v" in GIT_*) clean=0 ;; esac; done
[ "$HOME" = "$PWD" ] || clean=0
case "$in" in *"\"cwd\":\"$PWD\""*) : ;; *) clean=0 ;; esac
[ "$clean" = 1 ] || exit 0
case "$in" in
  *"terraform destroy"*) printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"stub"}}' ;;
  *"rm -rf ~"*) printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"stub"}}' ;;
esac
STUBEOF
chmod +x "$WORK/env/hooks/destructive-command-guard.sh"
run_probe SLICE1_PLUGIN_ROOT="$WORK/env" GIT_DIR=/nonexistent/dir GIT_INDEX_FILE=/nonexistent/index GIT_WORK_TREE=/nonexistent SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1
row "control: an environment-judging stub agrees through the unedited probe even with ambient GIT_* and the kill switch set" "$([[ "$RC" -eq 0 && "$OUT" == "slice1-security: ok" ]] && echo ok)" "rc=$RC out=${OUT//$'\n'/ | }"
mk_probe_copy() { # mk_probe_copy <name> <anchor> <replacement> -> PROBE_COPY (a probe whose root is a scratch dir that links the live apps tree)
  local d="$WORK/pc-$1"
  PROBE_COPY="$d/scripts/verify-agent-security-slice1.sh"
  mkdir -p "$d/scripts" && ln -s "$REPO_ROOT/apps" "$d/apps" || return 1
  replace_once "$SCRIPT" "$PROBE_COPY" "$2" "$3" || return 1
  ! cmp -s "$SCRIPT" "$PROBE_COPY" && "$BASH_BIN" -n "$PROBE_COPY"
}
V_OK="slice1-security: ok"
# a mutated copy must still be green against the REAL guard (the edit changes only the setup), or the red below would be the edit's fault
setup_row() { # setup_row <name> <desc> <anchor> <replacement> [VAR=value ...]
  local name="$1" desc="$2" a="$3" r="$4"; shift 4
  if ! mk_probe_copy "$name" "$a" "$r"; then row "$desc (the edit landed in the probe copy)" "" "anchor not found exactly once, or the copy does not parse"; return 0; fi
  run_probe_with "$PROBE_COPY" SLICE1_PLUGIN_ROOT="$WORK/env" "$@"
  row "$desc" "$([[ "$RC" -eq 1 && "$OUT" == *"slice1-security: FAIL guard probe"* && "$OUT" != *"$V_OK"* ]] && echo ok)" "rc=$RC out=${OUT//$'\n'/ | }"
}
setup_row v1 "the probe's GIT_* strip is load-bearing: a probe that keeps GIT_* goes red against the environment-judging stub" \
  'case "$v" in GIT_*) unset "$v" ;; esac' ':' GIT_DIR=/nonexistent/dir
setup_row v3 "the probe's HOME= is load-bearing: a probe that keeps the caller's HOME goes red" \
  '| HOME="$tmp" bash "$guard"' '| bash "$guard"'
setup_row v4 "the probe's cd into its temp dir is load-bearing: a probe that stays in the caller's directory goes red" \
  'cd "$tmp" && printf' 'printf'

# ---- F. a bash without process substitution is a named failure --------------------------------------------------------
d="$(farm_without bash)"
assert_fixture_dir "$d"
cat > "$d/bash" <<BASHEOF
#!/bin/sh
if [ "\$1" = -c ]; then echo "bash: /dev/fd/63: No such file or directory" >&2; exit 1; fi
exec "$BASH_BIN" "\$@"
BASHEOF
chmod +x "$d/bash"
run_probe PATH="$d"
red "a bash that cannot do process substitution is a named FAIL (needs /dev/fd)" "guard check needs /dev/fd (process substitution)"
row "that failure does not read as a wrong answer from the guard (no 'answered' line)" "$([[ "$OUT" != *"answered"* ]] && echo ok)" "out=${OUT//$'\n'/ | }"

# ---- summary and the vacuity floor --------------------------------------------------------------
echo "cases=$CASES passes=$passes fails=$fails"
if [[ $((passes + fails)) -ne "$CASES" ]]; then
  printf '[FATAL] anti-vacuity: %s verdicts recorded for %s cases\n' "$((passes + fails))" "$CASES" >&2; exit 1
fi
MIN_CASES=24
if [[ "$CASES" -lt "$MIN_CASES" ]]; then
  printf '[FATAL] anti-vacuity: only %s assertions ran, floor is %s\n' "$CASES" "$MIN_CASES" >&2
  exit 1
fi
[[ "$fails" -eq 0 ]]
