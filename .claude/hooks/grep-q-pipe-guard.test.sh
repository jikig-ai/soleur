#!/usr/bin/env bash
# Drift guard for #6992: no policy-gate hook may feed a producer into `grep -q`
# through a pipe.
#
# Under `set -o pipefail` that shape reports FAILURE on a SUCCESSFUL match once
# the producer still has unwritten data when grep exits — and because these
# hooks are shaped `<match> && deny` or `if ! <match>; then <skip>`, the
# dominant failure direction is FAIL OPEN: the gate silently permits what it
# exists to block. Measured at 0 denies in 30 runs on a 128 KB plan body whose
# first line was an operator-SSH step.
#
# Use instead:
#   grep -q PATTERN <<<"$var"                              # no pipe, no SIGPIPE
#   [ "$(producer | grep -c PATTERN || true)" -gt 0 ]      # -c reads all input
#
# Scope note: this asserts ZERO, not "no growth beyond a baseline". A baseline
# allowlist that grandfathers existing entries asserts nothing on day one. The
# hooks tree was taken to zero in #6992, so zero is the enforceable invariant.
#
# #7024 added the two files it took to zero, so they cannot regress:
#   tests/scripts/test-sentry-full-root-apply.sh
#   plugins/soleur/skills/compound/test/phase-16.test.sh
# #8664 added the zot-pull mutation battery and the guard it mutates:
#   apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh
#   apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh
# #8855 added the shared row scorer and five batteries that route their verdicts through it
# (FILES_8855 below; zot-pull, the sixth consumer, stays in FILES_8664). #8763 had rewritten four
# of those infra batteries' scorers from `| grep -qF --` to `| grep -cF --`, which PATTERN does not
# see, so both passes also run PATTERN_PIPED_SCORER — otherwise a revert to that spelling passes.
# This is a LINE search: a scorer with no `--`, a long first flag, a `command`/`\grep` wrapper or a
# pipe split across lines is not seen (the derived sweep below widens the spellings; see its limits). What pins the WIRE is
# apps/web-platform/infra/lib/mutation-scorer-consumers.test.sh, which requires every battery that
# sources the lib to actually reach it.
# #7376 (the tracker for these flakes; the fix PR is #9525) added three infra/plugin suites whose
# 2026-10-05 CI flakes were this same mechanism (FILES_7376). TO ADD A FILE to FILES_7376, make three
# edits together: the array, `PIN_7376` (the pinned member count) in the pin check below, and the file's path in
# AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS in scripts/lib/test-affected-paths.sh (hand-
# maintained; the parity check below reads that array only, ignoring comments, and fails if the path is
# missing from it — otherwise `--affected` would not select this guard when that suite changes. If
# derivation later reaches these suites and the entries are pruned, drop this check with them):
#   apps/web-platform/infra/cron-egress-firewall.test.sh
#   apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh
#   plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh
# THE PRODUCER'S SIZE IS NOT A BOUND ON THE RACE. It was believed to need more than a 64 KiB pipe buffer
# (#7005, #7432); it fires with a 3-line `git log` producer (the reap suite) and with an `echo` of a
# few KB (the cron census logged `echo: write error: Broken pipe`), because the writer only has to be
# unfinished when the reader exits. Under an ignored SIGPIPE (CI) it surfaces as rc 1 instead of 141.
# The luks suite's real mechanism is the OTHER end of the pipe — a stub that never reads stdin makes
# the workflow's own `printf | ssh` take the signal — which no line search sees; the late-producer and
# non-draining-stub rows in that suite hold it. The runtime SIGPIPE control for this class lives in
# tests/scripts/test-sentry-full-root-apply.sh (T4: `yes | grep -q y`, the `type -t grep` shim guard).
# THE DERIVED SWEEP (#9217, #6601, #7005) replaced "the rest of scripts/ and plugins/ is out of scope". scan_sweep
# derives its own population: every non-ignored file with a covered extension (.sh .bash .bats .yml .yaml .tf
# .template .js; knowledge-base/ and this file excluded), asserted ZERO outside SWEEP_DEFERRALS. A new file under a
# new directory is in the population without any edit. STATED LIMITS (measured 2026-10-05; re-measure before quoting): an
# extensionless script with a shebang (5 tracked, 0 hits), fenced code in .md files that an agent executes (29 lines, mostly in
# plugins/soleur/skills/*/SKILL.md), 2 lines in .ts, the 13 hits in 5 scripts under knowledge-base/, and this file.
# The named FILES_* passes below stay as they are: they pin the SUITES whose incidents made this class, and carry the
# affected-paths wiring. The sweep is a line search, so a name in a comment is handled by the comment filter and the
# per-line marker, never by widening a glob. To take a deferred subtree to zero: convert it and delete its row.
#
# THE FORMS (pick by what the site reads; the FAIL message prints the same table):
#   echo/printf "$V" | grep -q P   ->  grep -q P <<<"$V"
#       printf '%s' (no trailing newline) with an empty-capable body, -v, a -x/-F variable pattern, a pattern that can match an
#       empty line, or a LATER STAGE that reads bytes (tail -c, wc -c):  grep -q P < <(printf '%s' "$V" [| stages])
#       (a here-string adds a newline and turns an empty value into one empty line)
#   producer | grep -q P           ->  grep -q P < <(producer)     read-only producer in a condition; its status is dropped
#   cat FILE | grep -q P           ->  grep -q P FILE
#   a bare pipeline under set -e, a side-effecting producer or a function that mutates state
#                                  ->  out=$(producer); grep -q P <<<"$out"   keeps the status and waits for the producer
#   a line that must show the shape  ->  append  # sigpipe-demo: intentional
# A gate whose MISS skips a check must route a grep that could not run (rc above 1) to the gate, not to "clean". Note that a
# failed here-string or process substitution returns rc 1 (a miss), not above 1, so this routing covers a bad pattern or an
# unreadable file, not a redirect failure.
#
set -euo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Applied to EVERY hook suite, not just ones whose hook is a sibling .sh:
# security_reminder_hook is a .py, so pairing by filename missed it and it
# kept writing the real ledger. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

# Without git the `git grep … || true` sweeps below read as "no hits" and pass (#8616).
command -v git >/dev/null 2>&1 || { echo "UNRESOLVED: git missing — this suite asserted nothing; install git"; exit 3; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

FAIL=0

# Match a pipe feeding a grep that can stop at its first match: -q or -m in any flag
# cluster (-q, -qE, -F -q, -m1, ...) or the long forms --quiet, --silent, --max-count.
# Anchored on the pipe + grep so prose naming the words without the pipe shape cannot
# match; prose that spells the shape still does, which is why the named-file passes strip
# comment lines. The pipe must be a SINGLE bar (`|` or `|&`) preceded by line start or a
# non-bar: without `(^|[^|])` the second bar of a logical OR (`a || grep -q p <<<"$x"`,
# already the safe form) read as a pipe (#8807). The flag widening is #8664's.
PATTERN='(^|[^|])\|&?[[:space:]]*grep([[:space:]]+-[A-Za-z]+)*[[:space:]]+(-[A-Za-z]*[qm][A-Za-z0-9]*|--quiet|--silent|--max-count)'
# A piped awk whose program exits on the same line (#8664). A multi-line awk program is not
# seen by a line search; #8664's splitter shape is held by the battery's
# g1b-mustpass-padded-pull-item row and its positive control instead.
PATTERN_AWK_EXIT='(^|[^|])\|&?[[:space:]]*awk[^|]*[^[:alnum:]_]exit([^[:alnum:]_]|$)'
# A pipe into a grep whose flags end in `--`: the spelling the seven pre-#8855 row scorers used
# (`| grep -qF -- "$x"`, `| grep -cF -- >/dev/null "$x"`). It pins against reverting to those, not
# against SIGPIPE in general — `-c` reads all its input. Bare `| grep -c` is deliberately NOT
# matched: it is the safe counting form this file's header recommends.
PATTERN_PIPED_SCORER='(^|[^|])\|&?[[:space:]]*grep([[:space:]]+-[A-Za-z]+)*[[:space:]]+--([[:space:]]|$)'
# WHAT PATTERN_V2 CLOSES (the sweep only; the named passes keep PATTERN): the wrappers command|builtin|exec|env|nice|
# stdbuf -x|timeout N and VAR=x (6 real sites when measured, all `LC_ALL=C grep -q`), `\grep`, an absolute path, egrep and
# fgrep, a reader inside { } (4) or ( ), long flags, and an argument-taking flag before the early-exit flag
# (`grep -e P -q`, `grep -A 1 -q P`; 0 real sites, so --regexp is not added).
# WHAT A LINE REGEX CANNOT CLOSE, with the count measured on 2026-10-05 over the swept population (code lines,
# comments dropped, this file excluded; the command is `git grep --no-index --exclude-standard -anE <regex>` over the same
# pathspec as scan_sweep). Re-measure before quoting a figure; counts rot.
#   | head -N          1561 lines, 1022 of them `head -1`. Dangerous only where the site is a bare pipeline under set -e and
#                      the producer writes more than a few KB; harmless on a short single-write producer. A count ratchet
#                      would churn on every legitimate site and buy no property, so this is a review item, not a gate.
#   | awk '... exit'     59 single-line stages (PATTERN_AWK_EXIT sees them in the named passes); a multi-line awk program is not seen
#   | read                3 lines;  | sed ...q   0 lines
#   a pipe split across lines   0 today (the one that existed was converted by hand)
#   a reader reached through a variable ("$GREP" -q), a wrapper with its own flags (env -i, nice -n 10, timeout -s KILL 5,
#   /usr/bin/env grep, sudo, xargs), a pipe into a function that wraps grep, and a procsub-out reader (cmd > >(grep -q ...)):
#   0 sites each today. Known false positive: a quoted -e pattern containing a space and the text -q (0 repo hits).
# THE PRODUCER SIDE of the pipe (a stub that never reads the stdin a `printf |` feeds it, so the writer takes the signal) is
# invisible to any line search: it needs a join from each production pipe to the owning suite's stub. Tracked in #9217.

# PATTERN_V2 is the widened reader pattern the DERIVED SWEEP (scan_sweep, below) uses. The four named
# passes above keep PATTERN, so none of them can turn red on a spelling they never carried. Five parts so
# each can be mutated on its own (the harness rows in the sweep section name them):
#   LEAD   a single bar (or |&), then optionally a brace or paren group opener
#   WRAP   command|builtin|exec|env|nice|stdbuf -x|timeout N, or VAR=x, any number, no flags of their own
#   BIN    grep, egrep, fgrep, \grep or an absolute path ending in one of them
#   ARG    flags, long flags, and the argument-taking -e/-f/-A/-B/-C/-m with its operand
#   EARLY  the early-exit flag: -q/-m in a cluster, --quiet, --silent, --max-count
SWEEP_LEAD='(^|[^|])\|&?[[:space:]]*(\{[[:space:]]+|\([[:space:]]*)?'
SWEEP_WRAP='((command|builtin|exec|env|nice|stdbuf[[:space:]]+-[a-zA-Z]+|timeout[[:space:]]+[0-9a-z.]+)[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
SWEEP_BIN='(\\|/[^[:space:]]*/)?(e|f)?grep'
SWEEP_ARG='([[:space:]]+(-[A-Za-z0-9]+|--[a-z-]+(=[^[:space:]]+)?|-[efABCm][[:space:]]+[^[:space:]]+))*'
SWEEP_EARLY='[[:space:]]+(-[A-Za-z]*[qm][A-Za-z0-9]*|--quiet|--silent|--max-count)'
PATTERN_V2="${SWEEP_LEAD}${SWEEP_WRAP}${SWEEP_BIN}${SWEEP_ARG}${SWEEP_EARLY}"

# A PATTERN that does not compile must not read as "no hits": every grep below
# folds exit 2 into exit 1 (`|| true`, `! grep`), so it would pass all three
# checks having scanned nothing (#8807 review).
for _name in PATTERN PATTERN_AWK_EXIT PATTERN_PIPED_SCORER PATTERN_V2; do
  _pat="${!_name}"
  rc=0; grep -E -- "$_pat" </dev/null >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -ne 1 ]]; then
    echo "UNRESOLVED: $_name does not compile as an ERE (grep rc=$rc) — this suite asserted nothing"
    exit 3
  fi
done

# A second, hand-ported harness hook tree was in this pathspec from #7173 until
# it was retired in ADR-245 / #8306; its glob is gone with the tree. The scope
# rule is unchanged — growth happens by naming a file or a directory taken to
# zero, never by widening a glob.
hits="$(git grep -nE "$PATTERN" -- '.claude/hooks/*.sh' '.claude/hooks/lib/*.sh' \
  | grep -vE '\.test\.sh' || true)"

# The two files #7024 took to zero. Named individually, NOT via a glob — see the scope
# note above. They are .test.sh files, which the exclusion filter above deliberately drops
# from the hooks sweep, so they are matched in their own pass.
#
# TWO FILTERS, AND BOTH ARE THE SAME LESSON THIS GUARD IS ABOUT.
#
#   1. COMMENT LINES ARE STRIPPED. The pattern is a text search, so it matches prose that
#      merely NAMES the shape — and these two files necessarily document it at length. The
#      sibling `_strip_comments` in test-sentry-full-root-apply.sh exists for exactly this
#      reason (cq-assert-anchor-not-bare-token): anchor on the executable construct, never
#      on a token a comment can also produce. Written without this, the guard false-FAILs
#      on the very explanation of the bug it enforces.
#
#   2. AN EXPLICIT PER-LINE OPT-OUT. test-sentry-full-root-apply.sh's T4 arm has to USE the
#      forbidden shape: it is the synthetic reproduction of the SIGPIPE mechanism, plus the
#      `yes | grep -q y` positive control that proves the environment can exhibit SIGPIPE
#      at all. A test that demonstrates a bug must be allowed to contain it. The marker is
#      per-LINE and must be typed out, so it cannot be applied by accident or by a glob.
# A TRAILING comment on the line (whitespace before the `#`, and nothing but whitespace or end of line after the words), so a
# string that merely CONTAINS the words, or a `; echo "# sigpipe-demo: intentional"` tail, does not exempt the line.
ALLOW_MARKER='[[:space:]]#[[:space:]]*sigpipe-demo:[[:space:]]*intentional([[:space:]]|$)'
# The comment filter every scan shares: drops `path:NN:<spaces>#...` lines. `--marker` also drops a line carrying the
# per-line ALLOW_MARKER (the sweep only; the four named passes deliberately have no opt-out).
_strip_comments() { # [--marker], stdin -> stdout
  if [[ "${1:-}" == --marker ]]; then
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -vE "$ALLOW_MARKER" || true
  else
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true
  fi
}
FILES_7024=(
  'tests/scripts/test-sentry-full-root-apply.sh'
  'plugins/soleur/skills/compound/test/phase-16.test.sh'
)
hits_7024="$(git grep -nE "$PATTERN" -- "${FILES_7024[@]}" | _strip_comments --marker)"

if [[ -n "$hits" ]]; then
  FAIL=1
  echo "FAIL: pipe-into-grep-q found in policy-gate hooks (#6992 regression)"
  echo "$hits" | sed 's/^/  /'
  echo
  echo "  Rewrite as a herestring, or as grep -c compared against 0."
else
  echo "PASS: no pipe-into-grep-q in .claude/hooks/ non-test code"
fi

if [[ -n "$hits_7024" ]]; then
  FAIL=1
  echo "FAIL: pipe-into-grep-q found in a file #7024 took to zero"
  echo "$hits_7024" | sed 's/^/  /'
  echo
  echo "  Rewrite as a herestring, or as grep -c compared against 0."
else
  echo "PASS: no pipe-into-grep-q in the two files #7024 took to zero"
fi

# The zot-pull mutation battery and the guard it mutates, taken to zero in #8664 (a piped
# early-exit scorer mis-scored killed rows under load). This pass pins the grep spelling and a
# single-line piped `awk … exit`; the multi-line splitter shape is held by the battery's padded
# row. Same comment filter as the #7024 pass; no opt-out marker.
FILES_8664=(
  'apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh'
  'apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh'
)
# The shared scorer and the batteries that source it (#8855); zot-pull, also a consumer, is in
# FILES_8664. Every file that sources the lib must be in one of the two — derived below.
FILES_8855=(
  'apps/web-platform/infra/lib/mutation-scorer.sh'
  'apps/web-platform/infra/apex-single-node-replace-mutation.test.sh'
  'apps/web-platform/infra/ssl-full-mitigation-mutation.test.sh'
  'apps/web-platform/infra/www-apex-canonicalizer-mutation.test.sh'
  'apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh'
  'apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh'
)
# The three suites whose 2026-10-05 flakes were the pipe early-exit race (#7376). The luks suite's
# producer-side mechanism is NOT visible to a line search; see the header and its race rows.
FILES_7376=(
  'apps/web-platform/infra/cron-egress-firewall.test.sh'
  'apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh'
  'plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh'
)
# Every pinned file must be tracked: a git grep over a renamed or deleted path returns nothing,
# which would switch its pin off without a word. The member count is pinned for the same reason.
missing_pins=""
for f in "${FILES_7024[@]}" "${FILES_8664[@]}" "${FILES_8855[@]}" "${FILES_7376[@]}"; do
  git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || missing_pins="$missing_pins $f"
done
# DISTINCT members: a duplicated entry would keep the count while dropping a file from its pin.
distinct() { printf '%s\n' "$@" | sort -u | wc -l; }
# The pinned sizes, declared ONCE and used by both the check and its message (raise the matching value
# when you add a member to a list).
PIN_7024=2; PIN_8664=2; PIN_8855=6; PIN_7376=3
if [[ -n "$missing_pins" ]] || (( $(distinct "${FILES_7024[@]}") != PIN_7024 || $(distinct "${FILES_8664[@]}") != PIN_8664 \
      || $(distinct "${FILES_8855[@]}") != PIN_8855 || $(distinct "${FILES_7376[@]}") != PIN_7376 )); then
  FAIL=1
  echo "FAIL: a pinned file is not tracked, or a pin list changed size, so its pin covers nothing:${missing_pins:- (member count changed)}"
  echo "  Sizes now: FILES_7024=$(distinct "${FILES_7024[@]}") (pinned $PIN_7024), FILES_8664=$(distinct "${FILES_8664[@]}") (pinned $PIN_8664), FILES_8855=$(distinct "${FILES_8855[@]}") (pinned $PIN_8855), FILES_7376=$(distinct "${FILES_7376[@]}") (pinned $PIN_7376)."
  echo "  If a file was renamed, update the FILES_* list in this file to the new path; do not delete the entry. If you ADDED a member, raise the matching PIN_* value above (and, for FILES_7376, add the path to the affected-paths array named in the header)."
fi
# FILES_7376 must also be declared as edges of this guard in the affected-paths index, or a local
# `--affected` run that edits one of those suites would not select the guard (hand-maintained block).
# The membership test reads ONLY that array's body with comment lines dropped, and matches whole entry
# lines: a whole-file grep is satisfied by the same path sitting in another suite's own array (the reap
# suite names itself there) or by a commented-out entry. An empty extraction is reported, not read as "all
# present". Prints the missing members, one per line, or `UNRESOLVED: ...`.
unwired_in() { # <index file> -> missing FILES_7376 members
  local idx="$1" body f
  body="$(sed -n '/^AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS=(/,/^)/p' "$idx" 2>/dev/null | grep -vE '^[[:space:]]*#' || true)"
  if ! grep -q '"' <<<"$body"; then
    echo "UNRESOLVED: the AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS array was not found or is empty in $idx"
    return 0
  fi
  for f in "${FILES_7376[@]}"; do
    grep -qxF -- "  \"$f\"" <<<"$body" || echo "$f"
  done
}
unwired_7376="$(unwired_in scripts/lib/test-affected-paths.sh)"
if [[ -n "$unwired_7376" ]]; then
  FAIL=1
  echo "FAIL: FILES_7376 members missing from AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS in scripts/lib/test-affected-paths.sh (read from that array only, comments ignored):"
  echo "$unwired_7376" | sed 's/^/  /'
fi
# The scan both the #8664 and #8855 passes use: all three patterns, comment lines stripped. The
# non-vacuity probe below drives THIS function, so dropping a pattern or widening the comment
# filter reds there even when no pinned file carries a hit.
# A read error is NOT "no hits": it prints an UNRESOLVED line, which the caller then reports as a
# FAIL (this runs inside $( ), so an exit here would only leave the subshell).
scan_scorers() { # <files...> -> the offending lines, or nothing
  local out rc=0
  out="$(grep -HnE -- "$PATTERN|$PATTERN_AWK_EXIT|$PATTERN_PIPED_SCORER" "$@")" || rc=$?
  if (( rc > 1 )); then
    echo "UNRESOLVED: scan_scorers could not read its input (grep rc=$rc) — nothing was scanned"
    return 0
  fi
  printf '%s\n' "$out" | _strip_comments
}
hits_8664="$(scan_scorers "${FILES_8664[@]}")"
# The battery's scorer self-test is the deterministic backstop for its scorer; deleting it would
# leave only this line search. Pin that it is still there.
if ! grep -qF 'failed_on "$SELFTEST_LOG" SELFTEST-TARGET' "${FILES_8664[0]}"; then
  FAIL=1
  echo "FAIL: the #8664 scorer self-test is gone from ${FILES_8664[0]}"
fi

if [[ -n "$hits_8664" ]]; then
  FAIL=1
  echo "FAIL: pipe-into-grep-q found in a file #8664 took to zero"
  echo "$hits_8664" | sed 's/^/  /'
  echo
  echo "  Capture into a variable and match in bash, or use a herestring."
else
  echo "PASS: grep-q-zero-8664-pass (zot-pull battery and its guard)"
fi

# The shared row scorer and the batteries that route through it (#8855). All three patterns;
# same comment filter as the #7024 and #8664 passes; no opt-out marker.
hits_8855="$(scan_scorers "${FILES_8855[@]}")"
# Every file that sources the lib must be pinned in FILES_8855 or FILES_8664, so a new consumer
# cannot join unpinned. The lib's own self-test sources it as "$HERE/mutation-scorer.sh" and is not
# matched. A failed derivation is not "no consumers".
src_rc=0
lib_sourcers="$(git grep -lE '^[[:space:]]*source[[:space:]].*/lib/mutation-scorer\.sh"' -- '*.sh')" || src_rc=$?
unpinned_consumers=""
if (( src_rc > 1 )) || [[ -z "$lib_sourcers" ]]; then
  FAIL=1
  echo "FAIL: could not derive the files that source mutation-scorer.sh (git grep rc=$src_rc)"
else
  while IFS= read -r f; do
    case " ${FILES_8855[*]} ${FILES_8664[*]} " in *" $f "*) ;; *) unpinned_consumers="$unpinned_consumers $f" ;; esac
  done <<<"$lib_sourcers"
fi
if [[ -n "$unpinned_consumers" ]]; then
  FAIL=1
  echo "FAIL: these files source mutation-scorer.sh but no pin list names them:$unpinned_consumers"
  echo "  Add each to FILES_8855 (and raise its member count)."
fi
if [[ -n "$hits_8855" ]]; then
  FAIL=1
  echo "FAIL: a piped row scorer found in a file #8855 took to zero"
  echo "$hits_8855" | sed 's/^/  /'
  echo
  echo "  Score through mutation_scorer_failed_on (apps/web-platform/infra/lib/mutation-scorer.sh)."
else
  echo "PASS: grep-q-zero-8855-pass (scorer lib and five batteries)"
fi

# The three suites the #7376 flakes came from. A DEDICATED scan: PATTERN plus PATTERN_AWK_EXIT with
# comment lines stripped — NOT scan_scorers, whose PATTERN_PIPED_SCORER would flag the safe
# `| grep -cF --` lines these suites carry (-c reads all its input). Negated (`! echo | grep -q`) and
# `&&`-chained sites match too: there the race produces a false PASS, not a false failure.
scan_pipes() { # <files...> -> the offending code lines, or nothing
  local out rc=0
  out="$(grep -HnE -- "$PATTERN|$PATTERN_AWK_EXIT" "$@")" || rc=$?
  if (( rc > 1 )); then
    echo "UNRESOLVED: scan_pipes could not read its input (grep rc=$rc) — nothing was scanned"
    return 0
  fi
  printf '%s\n' "$out" | _strip_comments
}
# scan_7376 [root]: scan every FILES_7376 member under <root> (default: the repo). The probe below
# points it at a scratch copy of each real member with one bad line appended, which proves the pass
# reads the pin list's members and not some other set.
scan_7376() {
  local root="${1:-.}" f paths=()
  for f in "${FILES_7376[@]}"; do paths+=("$root/$f"); done
  scan_pipes "${paths[@]}"
}
hits_7376="$(scan_7376 .)"
if [[ "$hits_7376" == UNRESOLVED:* ]]; then
  FAIL=1
  echo "FAIL: the #7376 scan could not read its input, so nothing was scanned: $hits_7376"
elif [[ -n "$hits_7376" ]]; then
  FAIL=1
  echo "FAIL: pipe-into-grep-q found in a suite #7376 took to zero"
  echo "$hits_7376" | sed 's/^/  /'
  echo
  echo "  Use grep -q PATTERN <<<\"\$var\" or grep -q PATTERN < <(producer); the reader must not exit before the writer."
else
  echo "PASS: grep-q-zero-7376-pass (cron-egress, luks-verify and reap-archive suites)"
fi

# ---------------------------------------------------------------------------------------------------
# THE DERIVED SWEEP (#9217, #6601, #7005). The named passes above pin a handful of files one by one;
# repo-wide that is ~1,100 sites in ~300 files, so enumerating them does not scale and every entry would
# also need an edit of scripts/lib/test-affected-paths.sh (which arms the full battery on every push).
# This pass derives its population instead: every non-ignored file with a covered extension, scanned with
# PATTERN_V2, asserted ZERO outside the deferral table. A file added next month under a new directory is in
# the population without any edit. Limits, stated plainly: a LINE search (a shape split across lines is not
# seen), coverage by EXTENSION (an extensionless script with a shebang is not swept), and `git grep` reads
# the working tree, so run this suite from the checkout you edited.
#
# Flags, and why each is there (measured on this tree): --no-index lets the probe plant files that are not
# tracked; --exclude-standard keeps it out of node_modules and ignored trees (1.0 s versus 24.3 s and ten stray
# hits without it); -a makes a NUL-bearing file searchable as text; core.excludesFile=/dev/null stops a
# developer's global ignore file changing the local result.
SWEEP_PATHSPEC=(
  ':(glob)**/*.sh' ':(glob)**/*.bash' ':(glob)**/*.bats' ':(glob)**/*.yml' ':(glob)**/*.yaml'
  ':(glob)**/*.tf' ':(glob)**/*.template' ':(glob)**/*.js'
  ':(exclude)knowledge-base'
  # This file carries the forbidden shape in its own probe fixtures, so it cannot sweep itself.
  ':(exclude).claude/hooks/grep-q-pipe-guard.test.sh'
)
# One swept file under each of these must exist, or the derivation is reading the wrong tree.
SWEEP_CANARIES=('scripts/' 'plugins/soleur/' 'apps/web-platform/scripts/' 'apps/cla-evidence/')
SWEEP_FLOOR=1400   # measured 1,646 swept files on 2026-10-05 (1,405 without every non-.sh file); a truncated population reads UNRESOLVED, never "no hits"
SWEEP_CANARY_COUNT=4   # pinned beside SWEEP_CANARIES: the probe compares against this literal, not against the array's own length

# What is deferred, one row per line: glob | mode | ceiling | tracker. A row is an OWNER for the hits under it, first
# match wins (so ORDER is semantic: a more specific row goes above a broader one), a FILES_* member is never deferred.
#   mode `=`   the subtree is small and slow-moving: hits must equal the ceiling (lower it when you convert one)
#   mode `<=`  the wave that converts it owns tightening: hits must stay at or below the ceiling; slack is printed. Shrink-only is
#              a CONVENTION here, not enforced: slack frees headroom for a new instance until the wave PR lowers the number.
# Globs are matched with bash `[[ == ]]`, so `*` CROSSES `/`. Keep every loose (`<=`) row TEST-SHAPED (`*.test.sh`, a test/ or
# tests/ directory, a `test-*` basename under scripts/) so production code can never fall into slack: a production hit then
# lands in "outside the deferral table" whatever any row's slack. A row that owns production-class files must be tight (`=`).
# A row whose subtree reaches zero is STALE and fails: the wave that converts a subtree deletes its row in the same PR.
# Every row names its tracker. These are the only places a new instance can hide, so the diff of this table is the
# review surface: raising a number is a visible, one-line, reviewable act and every run prints each row.
SWEEP_DEFERRALS=(
  'plugins/soleur/skills/drain-labeled-backlog/workflows/drain-labeled-backlog.workflow.js | = | 2 | #9217'   # DATA: an LLM prompt literal, not code; leaves only if the prompt text is rewritten
  '.claude/*.test.sh | <= | 91 | #9217'
  'tests/* | <= | 181 | #9217'
  'plugins/soleur/test/* | <= | 137 | #9217'
  'plugins/soleur/*.test.sh | <= | 66 | #9217'
  'apps/web-platform/*.test.sh | <= | 187 | #9217'
  '.github/scripts/test/* | <= | 11 | #9217'
  'scripts/*.test.sh | <= | 120 | #9217'
  'scripts/test-* | <= | 6 | #9217'
  'scripts/lib/test-* | <= | 1 | #9217'
  '*.test.sh | <= | 2 | #9217'
  'apps/web-platform/infra/* | = | 92 | #9217'
  '.github/* | = | 45 | #9217'
  'lefthook.yml | = | 1 | #9217'
)

# scan_sweep <root> -> line 1 `SWEPT: <n> files`, then any `UNRESOLVED: ...` lines, then the code lines that match
# (path:line:text, comment lines and marked lines dropped). `git grep` exits 1 for "no hits" and above 1 on a
# fatal error: only the first is zero hits. The caller turns UNRESOLVED into a top-level exit 3 (this runs inside
# $( ), where an exit would only leave the subshell).
scan_sweep() {
  local root="$1" out rc=0 files nfiles c
  files="$(git -c core.excludesFile=/dev/null -C "$root" grep --no-index --exclude-standard -al -e '' -- "${SWEEP_PATHSPEC[@]}")" || rc=$?
  if (( rc > 1 )); then
    echo "SWEPT: 0 files"
    echo "UNRESOLVED: scan_sweep could not list its population in $root (git grep rc=$rc) — nothing was scanned"
    return 0
  fi
  nfiles=$(printf '%s\n' "$files" | grep -c . || true)
  echo "SWEPT: $nfiles files"
  for c in "${SWEEP_CANARIES[@]}"; do
    grep -q -- "^$c" <<<"$files" || echo "UNRESOLVED: no swept file under $c in $root — the population is not the repository's"
  done
  rc=0
  out="$(git -c core.excludesFile=/dev/null -C "$root" grep --no-index --exclude-standard -anE -e "$PATTERN_V2" -- "${SWEEP_PATHSPEC[@]}")" || rc=$?
  if (( rc > 1 )); then
    echo "UNRESOLVED: scan_sweep could not read its input in $root (git grep rc=$rc) — nothing was scanned"
    return 0
  fi
  printf '%s\n' "$out" | _strip_comments --marker | grep . || true
}

# sweep_verdict <scan output> -> prints the PASS/FAIL lines and DEFERRED lines, sets SWEEP_FAIL=1 on failure.
# Runs in the caller's shell (no $( )) so it can set the failure flag; the row arithmetic is plain bash.
sweep_verdict() {
  local scan="$1" line path i owner row glob mode ceil tracker n slack
  local -a r_glob=() r_mode=() r_ceil=() r_tracker=() r_n=()
  local undeferred="" nund=0 pinned=" ${FILES_7024[*]} ${FILES_8664[*]} ${FILES_8855[*]} ${FILES_7376[*]} "
  for row in ${SWEEP_DEFERRALS[@]+"${SWEEP_DEFERRALS[@]}"}; do
    IFS='|' read -r glob mode ceil tracker <<<"$row"
    glob="${glob#"${glob%%[![:space:]]*}"}"; glob="${glob%"${glob##*[![:space:]]}"}"
    mode="${mode//[[:space:]]/}"; ceil="${ceil//[[:space:]]/}"; tracker="${tracker//[[:space:]]/}"
    r_glob+=("$glob"); r_mode+=("$mode"); r_ceil+=("$ceil"); r_tracker+=("$tracker"); r_n+=(0)
    if [[ ! "$ceil" =~ ^[0-9]+$ || ! "$tracker" =~ ^#[0-9]+$ || ( "$mode" != "=" && "$mode" != "<=" ) ]]; then
      SWEEP_FAIL=1
      echo "FAIL: malformed deferral row '$row' (want: glob | = or <= | ceiling | #tracker)"
    fi
  done
  while IFS= read -r line; do
    [[ -n "$line" && "$line" != SWEPT:* ]] || continue
    path="${line%%:*}"
    owner=-1
    if [[ "$pinned" != *" $path "* ]]; then
      for ((i = 0; i < ${#r_glob[@]}; i++)); do
        # shellcheck disable=SC2053  # the glob is the point: the row's glob is matched as a pattern
        if [[ "$path" == ${r_glob[i]} ]]; then owner=$i; break; fi
      done
    fi
    if [[ "$owner" != -1 ]]; then r_n[owner]=$(( r_n[owner] + 1 )); else undeferred+="$line"$'\n'; nund=$(( nund + 1 )); fi
  done <<<"$scan"
  for ((i = 0; i < ${#r_glob[@]}; i++)); do
    n="${r_n[i]}"; ceil="${r_ceil[i]}"; mode="${r_mode[i]}"; slack=$(( ceil - n ))
    echo "DEFERRED: ${r_glob[i]} ($n hits, ceiling $ceil, mode $mode, slack $slack, ${r_tracker[i]})"
    if (( n == 0 )); then
      SWEEP_FAIL=1; echo "FAIL: stale deferral: ${r_glob[i]} has no hits left — delete its row from SWEEP_DEFERRALS in the PR that converted it"
    elif (( n > ceil )); then
      SWEEP_FAIL=1; echo "FAIL: deferral ceiling exceeded: ${r_glob[i]} has $n hits, ceiling $ceil — a new early-exit pipe landed in a deferred subtree; use the forms in this file's header"
    elif [[ "$mode" == "=" ]] && (( n < ceil )); then
      SWEEP_FAIL=1; echo "FAIL: deferral ceiling is loose: ${r_glob[i]} has $n hits, ceiling $ceil — lower the ceiling to $n"
    fi
  done
  if (( nund > 0 )); then
    SWEEP_FAIL=1
    echo "FAIL: pipe-into-early-exit-grep outside the deferral table ($nund site(s)); under pipefail a match can read as a miss (#9217)"
    printf '%s' "$undeferred" | awk 'NR <= 50 { print "  " $0 } END { if (NR > 50) print "  ... " NR - 50 " more" }'
    echo "  (this scan reads untracked, non-ignored files too: a vendored tree with no ignore line is read as code)"
    echo
    echo "  Rewrite: echo \"\$V\" | grep -q P         ->  grep -q P <<<\"\$V\"   (printf with a newline in its format is the same)"
    echo "           printf '%s' \"\$V\" with -v, -x/-F and a variable pattern, a pattern that can match an empty line, or a stage"
    echo "             after it that reads bytes (tail -c, wc -c)  ->  grep -q P < <(printf '%s' \"\$V\" [| stages])   (a here-string adds a newline)"
    echo "           producer | grep -q P              ->  grep -q P < <(producer)   (read-only producer, inside a condition)"
    echo "           cat FILE | grep -q P              ->  grep -q P FILE"
    echo "           a bare pipeline under set -e      ->  out=\$(producer); grep -q P <<<\"\$out\"   (keeps the producer's status)"
    echo "           an intentional demo of the shape  ->  append  # sigpipe-demo: intentional  to that line"
  fi
}

# sweep_main <root> <floor> -> prints the verdict lines; rc 0 clean, 1 a violation, 3 unresolved. The caller folds the rc into
# FAIL / exit 3, and the probe drives this same function on scratch roots, so the whole chain is exercised, not only its parts.
# NOTE: callers run this as `sweep_main ... || rc=$?`, which suspends `set -e` inside it; every fallible command in the chain is
# therefore guarded by hand, so do not rely on errexit when you add one.
sweep_main() {
  local root="$1" floor="$2" scan n
  SWEEP_FAIL=0
  scan="$(scan_sweep "$root")"
  if grep -q '^UNRESOLVED:' <<<"$scan"; then
    grep '^UNRESOLVED:' <<<"$scan"
    return 3
  fi
  n="$(sed -n '1s/^SWEPT: \([0-9]*\) files$/\1/p' <<<"$scan")"
  SWEEP_N="${n:-0}"
  if [[ ! "${n:-0}" =~ ^[0-9]+$ ]] || (( ${n:-0} < floor )); then
    SWEEP_FAIL=1
    echo "FAIL: the derived sweep read ${n:-<no count>} files, below the floor of $floor — the population is truncated, so a pass would assert nothing"
  fi
  sweep_verdict "$scan"
  return "$SWEEP_FAIL"
}
# sweep_fold <rc from sweep_main>: 3 is UNRESOLVED and exits the suite, any other non-zero is a failure, zero prints the PASS line.
sweep_fold() {
  if (( $1 == 3 )); then
    exit 3
  elif (( $1 != 0 )); then
    FAIL=1
  elif [[ ! "${SWEEP_N:-}" =~ ^[1-9][0-9]*$ ]]; then
    FAIL=1   # rc 0 with no recorded population means the sweep never ran: a pass here would assert nothing
    echo "FAIL: the derived sweep reported success without recording a swept-file count — it did not run"
  else
    echo "PASS: grep-q-zero-sweep-pass ($SWEEP_N files swept; deferrals above)"
  fi
}
sweep_rc=0
sweep_main . "$SWEEP_FLOOR" || sweep_rc=$?
sweep_fold "$sweep_rc"

# Non-vacuity: the pattern must actually match the shape it forbids. Without
# this, a typo in PATTERN would make the guard pass forever on any input.
probe="$(mktemp -d)"
trap 'rm -rf "$probe"' EXIT
cat > "$probe/bad.sh" <<'EOF'
echo "$x" | grep -q 'p'
echo "$x"|grep -Eq 'p'
| grep -qE 'p'
echo "$x" |& grep -qE 'p'
done|grep -iq 'p'
$(f)|grep -sq 'p'
echo "$x" | grep -F -q p
echo "$x" | grep --quiet p
echo "$x" | grep -m1 p
EOF
cat > "$probe/good.sh" <<'EOF'
grep -qE 'p' <<<"$x"
a || grep -qE 'p' <<<"$x"
     || grep -qE 'p' <<<"$b"; then
|| grep -qE 'p' <<<"$x"
EOF
cat > "$probe/bad-awk.sh" <<'EOF'
echo "$x" | awk '/p/ { exit }'
EOF
cat > "$probe/good-awk.sh" <<'EOF'
awk '/p/ { exit }' "$f"
a || awk '/p/ { exit }' "$f"
EOF
# The six distinct pre-PR scorer spellings (ssl and www shared one; parity's first two did too),
# and lines from the same files that must not match.
cat > "$probe/bad-scorer.sh" <<'EOF'
    if [[ "$expect" != "-" ]] && ! grep -E '^  FAIL|^\[VACUITY\]|^\[FATAL\]' "$WORK/out.txt" | grep -cF -- >/dev/null "$expect"; then
  if ! grep -E '^  FAIL|^\[FATAL\]' "$log" | grep -cF -- >/dev/null "$expect"; then
  elif grep -F "[FAIL]" "$OUT" | grep -cF -- >/dev/null "$anchor"; then
  elif [[ "$want" == red ]] && grep -F "[FAIL]" "$OUT" | grep -cF -- >/dev/null "$anchor"; then
  for a in "$@"; do grep -F '[FAIL]' "$OUT" | grep -qF -- "$a" || return 1; done
  grep -E '^  FAIL' "$log" | grep -qF -- "$expect"
EOF
cat > "$probe/comment-scorer.sh" <<'EOF'
  # history: this used to read  grep -E '^  FAIL' "$log" | grep -qF -- "$expect"
EOF
cat > "$probe/good-scorer.sh" <<'EOF'
printf '%s' "$m" | grep -cF 'www.soleur.ai' >/dev/null
  | grep -v '/\.terraform/' | sed 's/x/y/'
a || grep -qF -- "$x" <<<"$y"
mutation_scorer_failed_on "$log" '^  FAIL' "$e"
grep -qF -- "$a" "$f"
EOF

# The shapes the #7376 pass must see: a NEGATED pipe (race direction: false PASS), a `&&` chain, a
# short git producer; and the two safe spellings it must not.
cat > "$probe/bad-7376.sh" <<'EOF'
! echo "$x" | grep -qF "HIT"
echo "$x" | grep -qx 'p' && MISS+="p "
git -C "$r" log --oneline -3 --format=%s | grep -q 'chore(archive-kb)'
echo "$x" | awk '/p/ { exit }'
echo "$x" | grep -q p # a code line with a trailing comment is still code
EOF
cat > "$probe/good-7376.sh" <<'EOF'
! grep -qF "HIT" <<<"$x"
grep -qx 'p' <<<"$x" && MISS+="p "
grep -q 'chore(archive-kb)' < <(git -C "$r" log --oneline -3 --format=%s)
a || grep -q 'p' < <(producer)
n=$(printf '%s\n' "$x" | grep -cF -- 'p')
EOF
cat > "$probe/comment-7376.sh" <<'EOF'
  # history: this used to read  echo "$x" | grep -q 'p'
EOF

# Wiring: a scratch copy of EACH real pinned member plus one appended bad line; the pass must report
# exactly one hit per member (so a member that is not read, or a real member that already carries a
# hit, both change the count).
mkdir -p "$probe/root"
wire_members=0
for _f in "${FILES_7376[@]}"; do
  mkdir -p "$probe/root/$(dirname "$_f")"
  if cp "$_f" "$probe/root/$_f" && printf '%s\n' 'echo "$x" | grep -q p' >> "$probe/root/$_f"; then
    wire_members=$((wire_members + 1))
  fi
done
p7376_wire_hits=$(scan_7376 "$probe/root" | grep -c . || true)

# The parity check's own non-vacuity: a member named in ANOTHER suite's array, and a commented-out entry in
# the guard's array, must both read as missing; the one genuinely present member must not. An index with no
# such array must read as UNRESOLVED.
mkdir -p "$probe/idx"
{
  echo 'AFFECTED_OTHER_SUITE_PATHS=('
  printf '  "%s"\n' "${FILES_7376[0]}"
  echo ')'
  echo 'AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS=('
  printf '  # "%s"\n' "${FILES_7376[1]}"
  printf '  "%s"\n' "${FILES_7376[2]}"
  echo ')'
} > "$probe/idx/index.sh"
printf 'AFFECTED_UNRELATED=(\n  "x"\n)\n' > "$probe/idx/noarray.sh"
parity_missing=$(unwired_in "$probe/idx/index.sh" | grep -c . || true)
parity_has_third=$(unwired_in "$probe/idx/index.sh" | grep -cxF -- "${FILES_7376[2]}" || true)
parity_unresolved=$(unwired_in "$probe/idx/noarray.sh" | grep -c '^UNRESOLVED' || true)

# Every bad line must match and no good line may, compared as COUNTS: a grep error
# prints no count, so it can never equal the line total or 0 (a negated `grep -q`
# would read exit 2 as a pass). Both files must be non-empty, or either half
# passes having checked nothing.
bad_lines=$(wc -l < "$probe/bad.sh")
bad_hits=$(grep -cE -- "$PATTERN" "$probe/bad.sh" || true)
good_hits=$(grep -cE -- "$PATTERN" "$probe/good.sh" || true)
awk_bad_hits=$(grep -cE -- "$PATTERN_AWK_EXIT" "$probe/bad-awk.sh" || true)
awk_good_hits=$(grep -cE -- "$PATTERN_AWK_EXIT" "$probe/good-awk.sh" || true)
scorer_bad_lines=$(wc -l < "$probe/bad-scorer.sh")
scorer_bad_hits=$(grep -cE -- "$PATTERN_PIPED_SCORER" "$probe/bad-scorer.sh" || true)
scorer_good_hits=$(grep -cE -- "$PATTERN_PIPED_SCORER" "$probe/good-scorer.sh" || true)
# The scan itself, not just its pattern strings: every bad line is reported, a comment is not.
scan_bad_hits=$(scan_scorers "$probe/bad-scorer.sh" | grep -c . || true)
scan_comment_hits=$(scan_scorers "$probe/comment-scorer.sh" | grep -c . || true)
# The #7376 scan itself: every bad line reported, no safe spelling and no comment reported.
p7376_bad_lines=$(wc -l < "$probe/bad-7376.sh")
p7376_bad_hits=$(scan_pipes "$probe/bad-7376.sh" | grep -c . || true)
p7376_good_hits=$(scan_pipes "$probe/good-7376.sh" | grep -c . || true)
p7376_comment_hits=$(scan_pipes "$probe/comment-7376.sh" | grep -c . || true)
# An unreadable input is reported as UNRESOLVED (never as "no hits").
p7376_unreadable=$(scan_pipes "$probe/does-not-exist.sh" 2>/dev/null | grep -c '^UNRESOLVED' || true)
if [[ "$bad_lines" -gt 0 && "$bad_hits" == "$bad_lines" && -s "$probe/good.sh" && "$good_hits" == 0 \
      && "$awk_bad_hits" == 1 && "$awk_good_hits" == 0 \
      && "$scorer_bad_lines" -gt 0 && "$scorer_bad_hits" == "$scorer_bad_lines" \
      && -s "$probe/good-scorer.sh" && "$scorer_good_hits" == 0 \
      && "$scan_bad_hits" == "$scorer_bad_lines" && -s "$probe/comment-scorer.sh" && "$scan_comment_hits" == 0 \
      && "$p7376_bad_lines" -gt 0 && "$p7376_bad_hits" == "$p7376_bad_lines" \
      && -s "$probe/good-7376.sh" && "$p7376_good_hits" == 0 && -s "$probe/comment-7376.sh" && "$p7376_comment_hits" == 0 \
      && "$p7376_unreadable" == 1 \
      && "$parity_missing" == 2 && "$parity_has_third" == 0 && "$parity_unresolved" == 1 \
      && "$wire_members" == "${#FILES_7376[@]}" && "$p7376_wire_hits" == "${#FILES_7376[@]}" ]]; then
  echo "PASS: guard pattern matches the forbidden shapes and not the fixed shapes (incl. || herestrings, #8807)"
else
  FAIL=1
  echo "FAIL: guard pattern is broken — it cannot distinguish the shapes"
  echo "  forbidden lines matched: ${bad_hits:-<grep error>}/$bad_lines (want all)"
  echo "  fixed lines matched:     ${good_hits:-<grep error>} (want 0)"
  echo "  piped awk exit matched:  ${awk_bad_hits:-<grep error>}/1, fixed awk: ${awk_good_hits:-<grep error>} (want 0)"
  echo "  piped scorer matched:    ${scorer_bad_hits:-<grep error>}/$scorer_bad_lines, fixed: ${scorer_good_hits:-<grep error>} (want 0)"
  echo "  scan_scorers reported:   ${scan_bad_hits:-<error>}/$scorer_bad_lines bad lines, ${scan_comment_hits:-<error>} comment lines (want 0)"
  echo "  scan_pipes (#7376):      ${p7376_bad_hits:-<error>}/$p7376_bad_lines bad lines, ${p7376_good_hits:-<error>} safe lines, ${p7376_comment_hits:-<error>} comment lines (want 0 and 0)"
  echo "  scan_7376 wiring:        ${p7376_wire_hits:-<error>} hits over $wire_members scratch members (want one per member: ${#FILES_7376[@]}); unreadable-input reports: ${p7376_unreadable:-<error>} (want 1)"
  echo "  parity check probe:      ${parity_missing:-<error>} missing (want 2: a member only in another array, a commented-out one), present member reported missing: ${parity_has_third:-<error>} (want 0), no-array index unresolved: ${parity_unresolved:-<error>} (want 1)"
fi

# ---------------------------------------------------------------------------------------------------
# Probe for the derived sweep and PATTERN_V2 (#9217). Every conjunct below names its own diagnostic: one
# boolean cannot say which half broke, and a deleted assignment would abort under `set -u` with no message.
sweep_probe_fail=()

# PATTERN_V2 fixtures, in their own files: appending these to bad.sh/good.sh would break the V1 conjunct above.
cat > "$probe/bad-v2.sh" <<'EOF'
x | LC_ALL=C grep -q p
x | LC_ALL=C LANG=C grep -q p
x | command env LC_ALL=C grep -q p
x | env LC_ALL=C grep -qE p
x | exec grep -q p
x | nice grep -q p
x | timeout 5 grep -q p
x | stdbuf -oL grep -q p
x | { grep -m1 -E v || [ $? -eq 1 ]; }
x | (grep -q p)
x |& grep -q p
x | grep --quiet p
x | grep --silent p
x | grep --max-count=1 p
x | grep -e p -q
x | grep -A 1 -q p
x | \grep -q p
x | /usr/bin/grep -q p
x | egrep -q p
x | fgrep -q p
x | grep -iEm1 p
x | grep -F -q p
x | grep -F -A1 -q p
x | builtin grep -q p
x | /bin/grep -q p
x | grep --color=never -q p
x | grep -A1 -q p
x | timeout 5s grep -q p
x | FOO= grep -q p
EOF
cat > "$probe/good-v2.sh" <<'EOF'
grep -q p <<<"$x"
a || grep -q p <<<"$x"
x | grep -c p
x | grep -v p
x | grep -cE p
x | grep -F -- "$m"
x | grep -E 'a-q'
x | grep -l p
x | grep -oE p
x | sed 's/a/b/'
grep -e p -q "$f"
EOF
V2_BAD_LINES=29; V2_GOOD_LINES=11   # pinned literals: deleting a fixture line cannot lower both sides
v2_bad_lines=$(wc -l < "$probe/bad-v2.sh")
v2_good_lines=$(wc -l < "$probe/good-v2.sh")
v2_bad_hits=$(grep -cE -- "$PATTERN_V2" "$probe/bad-v2.sh" || true)
v2_good_hits=$(grep -cE -- "$PATTERN_V2" "$probe/good-v2.sh" || true)
# scan_sweep uses `git grep -E`, not grep -E: run the same fixtures through it so a dialect divergence shows.
v2_git_bad=$(git -C "$probe" grep --no-index -nE -e "$PATTERN_V2" -- bad-v2.sh | grep -c . || true)
v2_git_good=$(git -C "$probe" grep --no-index -nE -e "$PATTERN_V2" -- good-v2.sh | grep -c . || true)
[[ "$v2_bad_lines" == "$V2_BAD_LINES" && "$v2_good_lines" == "$V2_GOOD_LINES" ]] \
  || sweep_probe_fail+=("v2-fixtures: a fixture file changed length (bad $v2_bad_lines/$V2_BAD_LINES, good $v2_good_lines/$V2_GOOD_LINES)")
[[ "$v2_bad_hits" == "$V2_BAD_LINES" ]] || sweep_probe_fail+=("v2-bad: PATTERN_V2 matched ${v2_bad_hits:-<grep error>}/$V2_BAD_LINES forbidden spellings")
[[ "$v2_good_hits" == 0 ]] || sweep_probe_fail+=("v2-good: PATTERN_V2 matched ${v2_good_hits:-<grep error>} safe lines (want 0)")
[[ "$v2_git_bad" == "$V2_BAD_LINES" && "$v2_git_good" == 0 ]] \
  || sweep_probe_fail+=("v2-git-dialect: git grep matched ${v2_git_bad:-<error>}/$V2_BAD_LINES bad and ${v2_git_good:-<error>} good (want all and 0)")

# The sweep itself, on a scratch root with one file under EACH canary root: a bad line, plus a comment line, a marked
# line and the `a || grep` shape that must NOT be reported. Each root uses a different V2-only spelling, so the sweep
# is proved to run PATTERN_V2 and not PATTERN. A gitignored directory must stay unscanned.
sr="$probe/sweeproot"
mkdir -p "$sr/scripts" "$sr/plugins/soleur" "$sr/apps/web-platform/scripts" "$sr/apps/cla-evidence" "$sr/ignored"
_noise() { printf '%s\n' '# echo "$y" | grep -q p' 'echo "$z" | grep -q p # sigpipe-demo: intentional' 'a || grep -q p <<<"$x"'; }
{ _noise; echo 'echo "$x" | grep -q p'; }              > "$sr/scripts/x.sh"
{ _noise; echo 'echo "$x" | LC_ALL=C grep -q p'; }     > "$sr/plugins/soleur/x.sh"
{ _noise; echo 'echo "$x" | { grep -m1 p || true; }'; } > "$sr/apps/web-platform/scripts/x.sh"
{ _noise; echo 'echo "$x" | grep --quiet p'; }         > "$sr/apps/cla-evidence/x.sh"
echo 'echo "$x" | grep -q p' > "$sr/ignored/x.sh"
echo 'ignored/' > "$sr/.gitignore"
sw_out="$(scan_sweep "$sr")"
sw_hits=$(grep -c '^[^:]*:[0-9]*:' <<<"$sw_out" || true)
sw_roots=$(grep -E '^(scripts|plugins/soleur|apps/web-platform/scripts|apps/cla-evidence)/x\.sh:' <<<"$sw_out" | cut -d: -f1 | sort -u | grep -c . || true)
sw_swept=$(sed -n '1s/^SWEPT: \([0-9]*\) files$/\1/p' <<<"$sw_out")
sw_unres=$(grep -c '^UNRESOLVED:' <<<"$sw_out" || true)
[[ "$sw_hits" == 4 && "$sw_roots" == 4 ]] || sweep_probe_fail+=("sweep-wiring: ${sw_hits:-<err>} hits over ${sw_roots:-<err>} canary roots (want exactly one per root: 4 and 4; a comment, a marked line, the || shape and a gitignored dir must not count)")
[[ "$sw_swept" == 4 && "$sw_unres" == 0 ]] || sweep_probe_fail+=("sweep-population: swept ${sw_swept:-<err>} files (want 4: the ignored one is excluded), ${sw_unres:-<err>} UNRESOLVED lines (want 0)")
# An unreadable root and a population missing the canaries are UNRESOLVED, never "no hits".
mkdir -p "$probe/emptyroot" && echo 'true' > "$probe/emptyroot/x.sh"
un_missing=$(scan_sweep "$probe/does-not-exist" 2>/dev/null | grep -c '^UNRESOLVED:' || true)
un_canary=$(scan_sweep "$probe/emptyroot" | grep -c '^UNRESOLVED: no swept file under' || true)
[[ "$un_missing" -ge 1 && "$un_canary" == "${#SWEEP_CANARIES[@]}" ]] \
  || sweep_probe_fail+=("sweep-unresolved: unreadable root reported ${un_missing:-<err>} times (want >=1), missing canaries reported ${un_canary:-<err>} (want ${#SWEEP_CANARIES[@]})")

# The deferral table's own checks, driven on synthetic scan output with a synthetic table (so a real subtree reaching
# zero cannot be what these read). Each row isolates one check; the carve-out row uses a REAL FILES_7376 member.
_vp() { # <expected substring or -> <table row...> -- <scan lines...>
  local want="$1" rows=() lines=() out
  shift
  while [[ "${1:-}" != "--" && $# -gt 0 ]]; do rows+=("$1"); shift; done
  shift
  lines=("$@")
  out="$( SWEEP_FAIL=0; SWEEP_DEFERRALS=("${rows[@]}"); sweep_verdict "$(printf '%s\n' ${lines[@]+"${lines[@]}"})"; echo "SWEEP_FAIL=$SWEEP_FAIL" )"
  if [[ "$want" == - ]]; then
    [[ "$out" == *"SWEEP_FAIL=0" && "$out" != *"FAIL:"* ]]
  else
    [[ "$out" == *"SWEEP_FAIL=1"* && "$out" == *"$want"* ]]
  fi
}
_vp -                   'a/* | = | 2 | #1' -- 'a/x.sh:1:t' 'a/y.sh:2:t'          || sweep_probe_fail+=("deferral-ok: a row whose hits equal its ceiling was rejected")
_vp 'stale deferral'    'a/* | = | 2 | #1' --                                   || sweep_probe_fail+=("deferral-stale: a row with zero hits was not reported stale")
_vp 'ceiling exceeded'  'a/* | <= | 1 | #1' -- 'a/x.sh:1:t' 'a/y.sh:2:t'         || sweep_probe_fail+=("deferral-ceiling: hits above a ceiling were accepted")
_vp 'ceiling is loose'  'a/* | = | 3 | #1' -- 'a/x.sh:1:t' 'a/y.sh:2:t'          || sweep_probe_fail+=("deferral-tight: a tight (=) row with slack was accepted")
_vp -                   'a/* | <= | 3 | #1' -- 'a/x.sh:1:t' 'a/y.sh:2:t'         || sweep_probe_fail+=("deferral-loose-ok: a loose (<=) row with slack was rejected")
_vp 'outside the deferral table' 'a/* | = | 1 | #1' -- 'a/x.sh:1:t' 'b/z.sh:2:t' || sweep_probe_fail+=("deferral-undeferred: a hit under no row was accepted")
_vp 'malformed deferral row' 'a/* | = | 1 | no-tracker' -- 'a/x.sh:1:t'         || sweep_probe_fail+=("deferral-tracker: a row without a #tracker token was accepted")
_vp 'outside the deferral table' 'apps/* | <= | 9 | #1' -- "${FILES_7376[0]}:1:t" || sweep_probe_fail+=("deferral-carveout: a pinned FILES_7376 member was deferred by a broader row")
own="$( SWEEP_FAIL=0; SWEEP_DEFERRALS=('a/b/* | = | 1 | #1' 'a/* | = | 1 | #2'); sweep_verdict $'a/b/x.sh:1:t\na/y.sh:2:t'; echo "SWEEP_FAIL=$SWEEP_FAIL" )"
[[ "$own" == *"DEFERRED: a/b/* (1 hits"* && "$own" == *"DEFERRED: a/* (1 hits"* && "$own" == *"SWEEP_FAIL=0" ]] \
  || sweep_probe_fail+=("deferral-owner: first-match-wins did not give each overlapping row its own hit")

# _vp itself needs a known-NEGATIVE control: a helper that always returned 0 would make every row above vacuous.
_vp 'ZZZ-never-printed' 'a/* | <= | 1 | #1' -- 'a/x.sh:1:t' 'a/y.sh:2:t' && sweep_probe_fail+=("vp-negative: _vp accepted a failing case whose expected diagnostic cannot appear")
# Every FILES_* list needs its own carve-out row: the pinned set is the concatenation of four arrays.
# For each member: its top directory gives a row that WOULD own it (checked), and the carve-out must keep it out of that row.
carve_bad=""
for _m in "${FILES_7024[@]}" "${FILES_8664[@]}" "${FILES_8855[@]}" "${FILES_7376[@]}"; do
  _g="${_m%%/*}/*"
  # shellcheck disable=SC2053  # the glob is the point
  [[ "$_m" == $_g ]] || { carve_bad+=" $_m(no-row)"; continue; }
  _vp 'outside the deferral table' "$_g | <= | 9 | #1" -- "$_m:1:t" || carve_bad+=" $_m"
done
[[ -z "$carve_bad" ]] || sweep_probe_fail+=("deferral-carveout: pinned members deferred by a broader row (or no owning row to prove it):$carve_bad")

# The canary count is a LITERAL, and the canary match is anchored: `scripts/` must not be satisfied by `apps/web-platform/scripts/`.
[[ "${#SWEEP_CANARIES[@]}" == "$SWEEP_CANARY_COUNT" ]] || sweep_probe_fail+=("canary-count: SWEEP_CANARIES has ${#SWEEP_CANARIES[@]} roots, pinned at $SWEEP_CANARY_COUNT")
mkdir -p "$probe/shiftroot/apps/web-platform/scripts" && echo true > "$probe/shiftroot/apps/web-platform/scripts/x.sh"
un_anchor=$(scan_sweep "$probe/shiftroot" | grep -c '^UNRESOLVED: no swept file under scripts/' || true)
[[ "$un_anchor" == 1 ]] || sweep_probe_fail+=("canary-anchor: a nested apps/web-platform/scripts/ file satisfied the top-level scripts/ canary (reported ${un_anchor:-<err>} times, want 1)")

# The filters: a violating line must NOT hide behind a `:N:#` inside its own text, a marker-shaped string, or a marker that is not a trailing comment.
mkdir -p "$probe/hideroot/scripts" "$probe/hideroot/plugins/soleur" "$probe/hideroot/apps/web-platform/scripts" "$probe/hideroot/apps/cla-evidence"
cat > "$probe/hideroot/scripts/x.sh" <<'EOF'
echo "$x" | grep -q "a:3:# b"
echo "$x" | grep -q p; echo "# sigpipe-demo: intentional"
echo "$x" | grep -q "foo # sigpipe-demo: intentional" 
echo "$x" | grep -q p # sigpipe-demo: intentional (a real trailing marker: not reported)
echo "$x" | grep -q "p"#sigpipe-demo: intentional
EOF
for _r in plugins/soleur apps/web-platform/scripts apps/cla-evidence; do echo true > "$probe/hideroot/$_r/x.sh"; done
# The NAMED passes use the same filter: a self-hiding line in a pinned-style file must be reported there too.
named_hide=$(scan_pipes "$probe/hideroot/scripts/x.sh" | grep -c 'a:3:# b' || true)
[[ "$named_hide" == 1 ]] || sweep_probe_fail+=("filter-anchor-named: scan_pipes reported ${named_hide:-<err>} of 1 self-hiding line")
hide_hits=$(scan_sweep "$probe/hideroot" | grep -c '^scripts/x.sh:[0-9]*:' || true)
[[ "$hide_hits" == 4 ]] || sweep_probe_fail+=("filter-anchor: ${hide_hits:-<err>} of 4 self-hiding violating lines were reported (the real trailing marker line must be the only one dropped)")

# The whole chain: a violating root reports rc 1, a compliant one rc 0, a short population rc 1 under a high floor, an empty one rc 3.
okroot="$probe/okroot"; mkdir -p "$okroot/scripts" "$okroot/plugins/soleur" "$okroot/apps/web-platform/scripts" "$okroot/apps/cla-evidence"
for _r in scripts plugins/soleur apps/web-platform/scripts apps/cla-evidence; do echo 'grep -q p <<<"$x"' > "$okroot/$_r/x.sh"; done
rc_bad=0;  ( SWEEP_DEFERRALS=(); sweep_main "$sr" 1 >/dev/null ) || rc_bad=$?
rc_ok=0;   ( SWEEP_DEFERRALS=(); sweep_main "$okroot" 1 >/dev/null ) || rc_ok=$?
rc_low=0;  ( SWEEP_DEFERRALS=(); sweep_main "$okroot" 100 >/dev/null ) || rc_low=$?
rc_none=0; ( SWEEP_DEFERRALS=(); sweep_main "$probe/emptyroot" 1 >/dev/null ) || rc_none=$?
[[ "$rc_bad" == 1 && "$rc_ok" == 0 && "$rc_low" == 1 && "$rc_none" == 3 ]] \
  || sweep_probe_fail+=("sweep-main: rc violating/compliant/below-floor/empty = $rc_bad/$rc_ok/$rc_low/$rc_none (want 1/0/1/3)")
# The fold itself, driven the way the suite uses it: rc 1 sets FAIL, rc 3 exits 3, rc 0 prints PASS and leaves FAIL alone.
fold_a=$( FAIL=0; sweep_fold 1 >/dev/null; echo "$FAIL" ) || true
fold_b=0; ( FAIL=0; sweep_fold 3 >/dev/null ) || fold_b=$?
fold_c=$( FAIL=0; SWEEP_N=7; out=$(sweep_fold 0); echo "$FAIL:$out" ) || true
fold_d=$( FAIL=0; unset SWEEP_N; sweep_fold 0 >/dev/null; echo "$FAIL" ) || true
[[ "$fold_a" == 1 && "$fold_b" == 3 && "$fold_c" == "0:PASS: grep-q-zero-sweep-pass (7 files swept; deferrals above)" && "$fold_d" == 1 ]] \
  || sweep_probe_fail+=("sweep-fold: fold rc1/rc3/rc0/rc0-without-count gave ${fold_a:-<err>}/${fold_b:-<err>}/${fold_c:-<err>}/${fold_d:-<err>} (want 1/3/0:PASS.../1)")
# The suite's own exit is the fold of FAIL, and nothing after it may soften it: the last line is exactly `exit "$FAIL"` and FAIL is assigned 0 once.
[[ "$(tail -n 1 "${BASH_SOURCE[0]}")" == 'exit "$FAIL"' && "$(grep -c '^FAIL=0$' "${BASH_SOURCE[0]}")" == 1 ]] \
  || sweep_probe_fail+=("exit-fold: the last line of this file is not exit \"\$FAIL\", or FAIL is reset to 0 more than once")

# What a line regex deliberately does NOT match (documented residuals) and the one known false positive, pinned as literal counts so a
# widening or a regression shows up as a changed number and a header edit rather than as silent drift.
cat > "$probe/residual-v2.sh" <<'EOF'
x | env -i grep -q p
x | sudo grep -q p
x | grep p -q
EOF
cat > "$probe/fp-v2.sh" <<'EOF'
x | grep -e "a -q b" file
EOF
res_hits=$(grep -cE -- "$PATTERN_V2" "$probe/residual-v2.sh" || true)
fp_hits=$(grep -cE -- "$PATTERN_V2" "$probe/fp-v2.sh" || true)
[[ "$res_hits" == 0 && "$fp_hits" == 1 ]] || sweep_probe_fail+=("residual-v2: documented residuals matched ${res_hits:-<err>} (want 0), the documented false positive matched ${fp_hits:-<err>} (want 1)")

# A probe check that is DELETED cannot fail, so the number of checks is pinned: every check above ends in
# `|| sweep_probe_fail+=(...)` (or `&& ...` for a negative control), so the count of NON-COMMENT lines carrying that tail is the count
# of checks (the pin's own line and its counting line included); comment lines are excluded, so rewording a comment can neither hide a
# deletion nor trip the pin, and a `#` inside a check's own string does not hide it from the count.
SWEEP_PROBE_CHECKS=28
probe_checks=$(grep -vE '^[[:space:]]*#' "${BASH_SOURCE[0]}" | grep -c 'sweep_probe_fail+=(' || true)
[[ "$probe_checks" == "$SWEEP_PROBE_CHECKS" ]] \
  || sweep_probe_fail+=("probe-count: this probe carries ${probe_checks:-<err>} checks, pinned at $SWEEP_PROBE_CHECKS — a deleted check cannot fail, so restore it or, if you ADDED one, raise SWEEP_PROBE_CHECKS")
if (( ${#sweep_probe_fail[@]} == 0 )); then
  echo "PASS: grep-q-sweep-probe-pass (PATTERN_V2 fixtures, sweep wiring, deferral checks)"
else
  FAIL=1
  echo "FAIL: the derived sweep's own probe is broken — the sweep could pass over a violation:"
  printf '  %s\n' "${sweep_probe_fail[@]}"
  exit 1   # directly, not through FAIL: a probe failure must not be softened by whatever the last line does
fi

exit "$FAIL"
