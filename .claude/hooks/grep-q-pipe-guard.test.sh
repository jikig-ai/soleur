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
#   producer | grep -cE PATTERN >/dev/null                 # POSIX sh, Terraform inline, cloud-init runcmd, or an input
#                                                          # that may be empty: the exit status equals grep -q's (0 iff a line
#                                                          # was selected, -v and empty input included), it reads the whole
#                                                          # stream so the producer never takes EPIPE, and a here-string
#                                                          # would add a newline (printf '' | grep -qv x is rc 1; grep -qv x
#                                                          # <<<"" is rc 0) and is not valid in /bin/sh. It reads to EOF, so never
#                                                          # use it on a producer that does not end (yes, tail -f).
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
#   POSIX sh, Terraform inline, runcmd, or a value that may be empty  ->  producer | grep -cE P >/dev/null   (same exit status as -q, reads all input)
#   an output-bearing  | grep -m1 P | ...  in bash, on a value that is never empty  ->  grep -m1 P <<<"$V" | ...
#   a line that must show the shape  ->  append  # sigpipe-demo: intentional
# Wave B (#9217) converted the test-harness rows with a codemod (scripts/grep-q-drain-codemod.py), which S7a deleted together with its selftest once no
# glob row was left to convert; it is recoverable from commit 6a86eae0ec. A NEW hit is converted by hand with the forms table above, and a line
# that must show the shape carries the marker. The producer side of the pipe (S7b) is pinned by the join block near the end of this file.
# To recompute SWEEP_PROBE_CHECKS after editing the probe (the same pipeline the pin below runs):
#   grep -vE '^[[:space:]]*#' .claude/hooks/grep-q-pipe-guard.test.sh | grep -cE '(\|\||&&)[[:space:]]+sweep_probe_fail\+=\('
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
# invisible to any line search: it needs a join from each production pipe to the owning suite's stub. S7b (#9217) adds that join
# (the block headed THE PRODUCER SIDE near the end of this file): it derives every (test file, verb) pair, requires a PRODUCER_JOIN row
# for each, pins the stdin drain of every `drains` row within a four-line text window, and runs the hazard for real. What it does NOT
# cover is listed under STATED LIMITS in that block (pipes split over lines, wrapped verbs, helper-built stubs, variable verbs, process
# substitutions, and a pair whose suite never reaches the stub: an exempt text-only row says so). Follow-on slices of #9217 remain open (affected-edge selection for a changed producer, and the other wave A3 carriers);
# this header does not claim the series is finished.

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
# A TRAILING comment on the line (whitespace before the `#`, and the words followed by whitespace or end of line, so a trailing reason in parentheses after them is accepted), so a
# `; echo "# sigpipe-demo: intentional"` tail does not exempt the line. KNOWN HOLE (Item F, measured in the S4 review): a string that
# contains the words followed by a space (`"a # sigpipe-demo: intentional b"`) still matches, and the marker is not capped per file.
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
SWEEP_CANARIES=('scripts/' 'plugins/soleur/' 'apps/web-platform/scripts/' 'apps/cla-evidence/' 'tests/' 'plugins/soleur/scripts/' 'plugins/soleur/skills/' 'apps/web-platform/infra/' 'apps/web-platform/test/')
SWEEP_FLOOR=1400   # measured 1,646 swept files on 2026-10-05 (1,405 without every non-.sh file); a truncated population reads UNRESOLVED, never "no hits"
SWEEP_CANARY_COUNT=9   # pinned beside SWEEP_CANARIES: the probe compares against this literal, not against the array's own length
# To add a canary root: the array and SWEEP_CANARY_COUNT here, then one violating file for it in the sweep probe's sweeproot (a spelling
# PATTERN_V2 matches), the sw_roots alternation, and one compliant file in okroot. The hit and population checks compare against
# SWEEP_CANARY_COUNT, so a root added in only some of those places fails loudly.

# What is deferred, one row per line: glob | mode | ceiling | tracker. A row is an OWNER for the hits under it, first
# match wins (so ORDER is semantic: a more specific row goes above a broader one), a FILES_* member is never deferred.
#   mode `=`   the subtree is small and slow-moving: hits must equal the ceiling (lower it when you convert one)
#   mode `<=`  the wave that converts it owns tightening: hits must stay at or below the ceiling; slack is printed. Shrink-only is
#              a CONVENTION here, not enforced: slack frees headroom for a new instance until the wave PR lowers the number.
# Globs are matched with bash `[[ == ]]`, so `*` CROSSES `/`. Keep every loose (`<=`) row TEST-SHAPED (`*.test.sh` or a test/ or tests/
# directory as a glob, a glob-free `*.test.sh` path, or a path under plugins/soleur/test/) so production code can never fall into slack: a
# production hit then lands in "outside the deferral table" whatever any row's slack. A row that owns production-class files must be
# tight (`=`). Today every row is tight and file-exact, and the probe pins that no row uses mode `<=` (a ceiling number on an `=` row can
# only equal the hit count, so raising it is a visible one-line edit, never slack).
# A row whose subtree reaches zero is STALE and fails: the wave that converts a subtree deletes its row in the same PR.
# Every row names its tracker. These are the only places a new instance can hide, so the diff of this table is the
# review surface: raising a number is a visible, one-line, reviewable act and every run prints each row.
# A glob row at slack 0 pins the COUNT per row, not the sites, so moving one hit between two files under the same glob (add one, delete one) would stay
# green; S7a closed that for the last two glob rows by making every row file-exact (`_ts_re` below classifies a glob-free test path as test-shaped).
# S6 took apps/web-platform/ (all but the six file-exact carrier rows below) to zero; its marked lines are demonstrations, mutation recipes and their landing checks, needles for carrier bytes, and two message or payload strings, and the
# apps/web-platform/infra/ root canary is witnessed today by those six rows going stale (not ablation-proved), so it matters once they convert.
# S3 (scripts/) and S4 (tests/) took their subtrees to zero and deleted their rows; S5 did the same for the plugins/soleur/ test files outside
# plugins/soleur/test/ (its five counted pins stay). The test-shaped row globs are pinned (GATED_TEST_ROWS), so a new or widened one, however it is
# spelled, is a visible two-place edit. The drained form
# `grep -c ... >/dev/null` those slices wrote is deliberate (same exit status for stdin operands, and the producer is read to EOF): do not rewrite it to a here-string.
SWEEP_DEFERRALS=(
  # The counted data pins in six test files, each a pipe inside a string, a mutation payload or .md-fence text (marker-exempt demos are not
  # counted). They are file-exact and tight (`=`), so moving a hit from one file to another turns the guard red where a glob row at the same
  # count stayed green. Two limits stay: the count is per FILE, so converting one hit and adding another inside the same file is not seen; and
  # renaming or splitting one of these six files needs a row edit in the same PR (a stale row names the file, and its message says how).
  '.claude/hooks/background-poll-prefer-monitor.test.sh | = | 1 | #9217'
  '.claude/hooks/pkill-self-match-guard.test.sh | = | 4 | #9217'
  'plugins/soleur/test/deploy-arm-mutations.sh | = | 1 | #9217'
  'plugins/soleur/test/deploy-arm.test.sh | = | 1 | #9217'
  'plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh | = | 1 | #9217'
  'plugins/soleur/test/worktree-manager-porcelain-sigpipe.test.sh | = | 2 | #9217'
  # Wave A2 (this table's last production rows) converted .github/, lefthook.yml, the drain workflow prompt and every other
  # apps/web-platform/infra file. These four stay, file-exact and tight (`=`), because their bytes feed `user_data` of
  # `hcloud_server.{registry,inngest,git_data}`, which carry NO `ignore_changes = [user_data]` (ADR-100, ADR-169): any edit is a
  # host replace at the next full apply or maintenance-window dispatch, and the per-merge apply excludes those hosts, so the drift
  # would sit silent until then. Convert them only inside a PR already scheduled for that dispatch, and delete the row there.
  'apps/web-platform/infra/cloud-init-registry.yml | = | 13 | #9217'
  'apps/web-platform/infra/cloud-init-inngest.yml | = | 4 | #9217'
  'apps/web-platform/infra/cloud-init-git-data.yml | = | 3 | #9217'
  'apps/web-platform/infra/git-data-bootstrap.sh | = | 1 | #9217'
  # A fifth, for a different reason: workspaces-luks.tf's public-log forensic print is sha256-pinned and its `grep -q` form is the one the
  # forbidden-diagnostic rule allows (apps/web-platform/infra/luks-monitor-install.test.sh, G2 and G4). Converting it needs that security
  # review, so it rides a PR that carries the review, not a lint sweep.
  'apps/web-platform/infra/workspaces-luks.tf | = | 1 | #9217'
  # A sixth class, found at review: a script BAKED into a digest-pinned image whose pin lives in a user_data file. The inngest bootstrap
  # image carries inngest-luks-cutover.sh at tag vinngest-v1.1.44 and cloud-init-inngest-bootstrap.test.sh (GuardA) requires every baked
  # carrier byte-identical to that tag, so a one-token edit needs a new image AND a pin bump in cloud-init-inngest.yml (= an inngest host
  # replace). Convert it only in the PR that mints the next image tag, and delete the row there.
  'apps/web-platform/infra/inngest-luks-cutover.sh | = | 1 | #9217'
)

# scan_sweep <root> -> line 1 `SWEPT: <n> files`, then any `UNRESOLVED: ...` lines, then the code lines that match
# (path:line:text, comment lines and marked lines dropped). `git grep` exits 1 for "no hits" and above 1 on a
# fatal error: only the first is zero hits. The caller turns UNRESOLVED into a top-level exit 3 (this runs inside
# $( ), where an exit would only leave the subshell).
# The one place the sweep's flags and pathspec live: scan_sweep's listing, scan_sweep's scan and the test-canary check below all call it, so an
# exclusion or an ignore handling edit moves all three together and cannot hide a file from the scan while the canary still sees it.
sweep_git_grep() { # <root> <git grep options...>
  local root="$1"; shift
  git -c core.excludesFile=/dev/null -C "$root" grep --no-index --exclude-standard "$@" -- "${SWEEP_PATHSPEC[@]}"
}
scan_sweep() {
  local root="$1" out rc=0 files nfiles c
  files="$(sweep_git_grep "$root" -al -e '')" || rc=$?
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
  out="$(sweep_git_grep "$root" -anE -e "$PATTERN_V2")" || rc=$?
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
      SWEEP_FAIL=1; echo "FAIL: stale deferral: ${r_glob[i]} has no hits left — delete its row from SWEEP_DEFERRALS (and its GATED_TEST_ROWS or GATED_PROD_GLOBS line) in the PR that converted it; if the file was renamed or split, rename the row and that line instead"
    elif (( n > ceil )); then
      SWEEP_FAIL=1; echo "FAIL: deferral ceiling exceeded: ${r_glob[i]} has $n hits, ceiling $ceil — a new early-exit pipe landed in a deferred subtree; use the forms in this file's header (some file-exact apps/web-platform/infra rows feed a host user_data or a pinned artifact: read the comment above SWEEP_DEFERRALS before converting one)"
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
    echo "           POSIX sh, Terraform inline, runcmd, or a value that may be empty  ->  producer | grep -cE P >/dev/null   (same exit status as -q, reads all input, no newline added)"
    echo "           an output-bearing  | grep -m1 P  in bash, with a value that is never empty  ->  grep -m1 P <<<\"\$V\" | ..."
    echo "           an output-bearing  producer | grep -m1 P  (value may be empty, or a producer)  ->  grep -m1 P < <(producer)"
    echo "           an intentional demo of the shape  ->  append  # sigpipe-demo: intentional  to that line"
    echo "  A subtree that reached zero stays at zero: do NOT add a deferral row for it (the test-shaped and production row sets are pinned); rewrite the hit."
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
unset SWEEP_N   # an ambient value must not satisfy the evidence that the sweep ran (sweep_fold and the return-wiring block read it)
sweep_main . "$SWEEP_FLOOR" || sweep_rc=$?
sweep_fold "$sweep_rc"

# Non-vacuity: the pattern must actually match the shape it forbids. Without
# this, a typo in PATTERN would make the guard pass forever on any input.
probe="$(mktemp -d)" && [[ "$probe" == /* ]] \
  || { echo "UNRESOLVED: mktemp -d failed or returned a relative path; the probe would write outside a scratch root; free space under /var/tmp or set TMPDIR to a writable absolute directory"; exit 3; }
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
x | grep -cE p >/dev/null
x | grep -cvx p >/dev/null
x | grep -cwF -- "$E" >/dev/null
EOF
V2_BAD_LINES=29; V2_GOOD_LINES=14   # pinned literals: deleting a fixture line cannot lower both sides
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
# line and the `a || grep` shape that must NOT be reported. Each root uses a different spelling and at least one is V2-only (a command/egrep/LC_ALL=C prefix),
# so the sweep is proved to run PATTERN_V2 and not PATTERN. A gitignored directory must stay unscanned.
sr="$probe/sweeproot"
mkdir -p "$sr/scripts" "$sr/plugins/soleur/scripts" "$sr/plugins/soleur/skills" "$sr/apps/web-platform/scripts" "$sr/apps/web-platform/infra" "$sr/apps/web-platform/test" "$sr/apps/cla-evidence" "$sr/tests" "$sr/ignored"
_noise() { printf '%s\n' '# echo "$y" | grep -q p' 'echo "$z" | grep -q p # sigpipe-demo: intentional' 'a || grep -q p <<<"$x"'; }
{ _noise; echo 'echo "$x" | grep -q p'; }              > "$sr/scripts/x.sh"
{ _noise; echo 'echo "$x" | LC_ALL=C grep -q p'; }     > "$sr/plugins/soleur/x.sh"
{ _noise; echo 'echo "$x" | { grep -m1 p || true; }'; } > "$sr/apps/web-platform/scripts/x.sh"
{ _noise; echo 'echo "$x" | grep --quiet p'; }         > "$sr/apps/cla-evidence/x.sh"
{ _noise; echo 'echo "$x" | grep --silent p'; }        > "$sr/tests/x.sh"
{ _noise; echo 'echo "$x" | command grep -q p'; }      > "$sr/plugins/soleur/scripts/x.sh"
{ _noise; echo 'echo "$x" | egrep -q p'; }              > "$sr/plugins/soleur/skills/x.sh"
{ _noise; echo 'echo "$x" | grep -iq p'; }              > "$sr/apps/web-platform/infra/x.sh"
{ _noise; echo 'echo "$x" | fgrep -q p'; }              > "$sr/apps/web-platform/test/x.sh"
echo 'echo "$x" | grep -q p' > "$sr/ignored/x.sh"
echo 'ignored/' > "$sr/.gitignore"
sw_out="$(scan_sweep "$sr")"
sw_hits=$(grep -c '^[^:]*:[0-9]*:' <<<"$sw_out" || true)
sw_roots=$(grep -E '^(scripts|plugins/soleur|apps/web-platform/scripts|apps/cla-evidence|tests|plugins/soleur/scripts|plugins/soleur/skills|apps/web-platform/infra|apps/web-platform/test)/x\.sh:' <<<"$sw_out" | cut -d: -f1 | sort -u | grep -c . || true)
sw_swept=$(sed -n '1s/^SWEPT: \([0-9]*\) files$/\1/p' <<<"$sw_out")
sw_unres=$(grep -c '^UNRESOLVED:' <<<"$sw_out" || true)
[[ "$sw_hits" == "$SWEEP_CANARY_COUNT" && "$sw_roots" == "$SWEEP_CANARY_COUNT" ]] || sweep_probe_fail+=("sweep-wiring: ${sw_hits:-<err>} hits over ${sw_roots:-<err>} canary roots (want exactly one per root: $SWEEP_CANARY_COUNT and $SWEEP_CANARY_COUNT; a comment, a marked line, the || shape and a gitignored dir must not count)")
[[ "$sw_swept" == "$SWEEP_CANARY_COUNT" && "$sw_unres" == 0 ]] || sweep_probe_fail+=("sweep-population: swept ${sw_swept:-<err>} files (want $SWEEP_CANARY_COUNT: the ignored one is excluded), ${sw_unres:-<err>} UNRESOLVED lines (want 0)")
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

# The REAL table (Waves A2 and B). The synthetic rows above prove the arithmetic; these prove the table this file SHIPS still owns what it
# must and nothing it must not. The scan runs scan_sweep on a scratch root (so SWEEP_PATHSPEC and PATTERN_V2 are exercised, not
# only the verdict) and the verdict reads the live SWEEP_DEFERRALS. Planted: one violating line under each subtree a wave took
# to zero (S3: scripts/, S4: tests/ at two depths and in a non-.sh extension, S5: plugins/soleur/ at seven depths and shapes, S6: apps/web-platform/ at seven depths and shapes), plus a compliant file under the roots no violator satisfies (scripts/, plugins/soleur/, apps/cla-evidence/; the apps/web-platform/scripts/ plant below is now redundant with its violator and kept as a harmless control; the tests/ and plugins/soleur/{scripts,skills}/ violators cover the rest) so the
# population is not UNRESOLVED. To add a canary: append its path to real_paths and bump REAL_PLANTED; nothing else moves.
_real_undeferred() { # <scan root> -> each path the CURRENT SWEEP_DEFERRALS leaves outside every row, one per line
  local v
  v="$( SWEEP_FAIL=0; sweep_verdict "$(scan_sweep "$1")"; echo "SWEEP_FAIL=$SWEEP_FAIL" )"
  sed -n '/^FAIL: pipe-into-early-exit-grep outside/,$p' <<<"$v" | grep -E '^  [^ ]+:[0-9]+:' | sed 's/^  //' | cut -d: -f1 || true
}
rr="$probe/realroot"
REAL_PLANTED=31   # pinned beside real_paths: a path deleted from the array alone must not pass (the plant and the expectation shrink together)
real_paths=(
  .github/workflows/zz.yml
  lefthook.yml
  plugins/soleur/skills/drain-labeled-backlog/workflows/drain-labeled-backlog.workflow.js
  apps/web-platform/infra/zz-new.sh
  scripts/zz.test.sh
  scripts/lib/zz.test.sh
  scripts/followthroughs/zz.test.sh
  scripts/test-zz.sh
  tests/zz.sh
  tests/scripts/test-zz.sh
  tests/scripts/lib/zz.sh
  tests/scripts/fixtures/zz.sh
  tests/scripts/fixtures/zz/zz.sh
  tests/commands/test-zz.sh
  tests/hooks/test_zz.sh
  tests/fixtures/zz.yml
  tests/fixtures/zz/zz.yml
  plugins/soleur/zz.test.sh
  plugins/soleur/scripts/zz.test.sh
  plugins/soleur/scripts/lib/zz.test.sh
  plugins/soleur/hooks/zz.test.sh
  plugins/soleur/skills/zz/test/zz.test.sh
  plugins/soleur/skills/zz/test/fixtures/zz.test.sh
  plugins/soleur/skills/zz/scripts/zz.test.sh
  apps/web-platform/zz.test.sh
  apps/web-platform/infra/zz.test.sh
  apps/web-platform/infra/lib/zz.test.sh
  apps/web-platform/infra/supabase-advisor/zz.test.sh
  apps/web-platform/scripts/zz.test.sh
  apps/web-platform/test/zz.test.sh
  apps/web-platform/test/infra/zz.test.sh
)
for _f in "${real_paths[@]}"; do
  mkdir -p "$rr/$(dirname "$_f")"
  echo 'echo "$x" | grep -q p' > "$rr/$_f"
done
for _f in scripts/c.sh plugins/soleur/c.sh apps/web-platform/scripts/c.sh apps/cla-evidence/c.sh; do
  mkdir -p "$rr/$(dirname "$_f")"
  echo 'grep -q p <<<"$x"' > "$rr/$_f"
done
real_want="$(printf '%s\n' "${real_paths[@]}" | LC_ALL=C sort)"
real_got="$(_real_undeferred "$rr" | LC_ALL=C sort)"
[[ "$real_got" == "$real_want" ]] \
  || sweep_probe_fail+=("real-table-owner: the shipped table left [${real_got//$'\n'/ }] outside every row (want exactly the $REAL_PLANTED planted paths: a path a row now owns, or a pathspec that dropped one, changes this)")
real_none=$( SWEEP_DEFERRALS=(); _real_undeferred "$rr" | grep -c . || true )
real_all=$( SWEEP_DEFERRALS=('* | <= | 99 | #1'); _real_undeferred "$rr" | grep -c . || true )
# A row that owns every tests/ canary must leave exactly the others undeferred: this is the control that the owner comparison above can fail.
real_tests_row="$( SWEEP_DEFERRALS=('tests/* | <= | 99 | #1'); _real_undeferred "$rr" | LC_ALL=C sort )"
real_nontests="$(printf '%s\n' "${real_paths[@]}" | { grep -v '^tests/' || true; } | LC_ALL=C sort)"
# Same control for plugins/soleur/: a row that owns every plugins/soleur/**/*.test.sh canary must leave exactly the others undeferred.
real_plug_row="$( SWEEP_DEFERRALS=('plugins/soleur/*.test.sh | <= | 99 | #1'); _real_undeferred "$rr" | LC_ALL=C sort )"
real_nonplug="$(printf '%s\n' "${real_paths[@]}" | { grep -v '^plugins/soleur/.*\.test\.sh$' || true; } | LC_ALL=C sort)"
[[ "$real_none" == "$REAL_PLANTED" && "$real_all" == 0 && "$real_tests_row" == "$real_nontests" && "$real_plug_row" == "$real_nonplug" ]] \
  || sweep_probe_fail+=("real-table-control: with no rows ${real_none:-<err>} planted paths were undeferred (want $REAL_PLANTED), with a catch-all row ${real_all:-<err>} (want 0), with a tests/ row [${real_tests_row//$'\n'/ }] (want exactly the non-tests/ canaries), with a plugins/soleur/*.test.sh row [${real_plug_row//$'\n'/ }] (want exactly the canaries that are not plugins/soleur/**/*.test.sh) — the helper above does not read the table it is given")
# A loose (<=) row's slack is where a NEW instance hides, so every loose row must be test-shaped: *.test.sh or a test/ or tests/ directory (as a glob),
# or a glob-free *.test.sh path or a path under plugins/soleur/test/. A production-shaped loose glob would turn this header's own invariant into a convention.
_ts_re='(^|/)(tests?/\*|\*\.test\.sh)$|^[^*?[:space:]]*\.test\.sh$|^plugins/soleur/test/[^*?[:space:]]+$'
_loose_not_test_shaped() { # <rows...> -> the glob of each `<=` row that is not test-shaped
  local row g m
  for row in "$@"; do
    IFS='|' read -r g m _ <<<"$row"
    g="${g#"${g%%[![:space:]]*}"}"; g="${g%"${g##*[![:space:]]}"}"; m="${m//[[:space:]]/}"
    [[ "$m" == "<=" ]] || continue
    [[ "$g" =~ $_ts_re ]] || echo "$g"
  done
}
loose_bad="$(_loose_not_test_shaped "${SWEEP_DEFERRALS[@]}")"
loose_n=0
for _row in "${SWEEP_DEFERRALS[@]}"; do
  IFS='|' read -r _ _m _ <<<"$_row"; _m="${_m//[[:space:]]/}"   # the mode as sweep_verdict reads it: every blank removed
  [[ "$_m" == "<=" ]] && loose_n=$((loose_n + 1))
done
# tests/ went to zero in S4 and every canary under it is owned by NO row; a resurrected row there (even a test-shaped one such as
# `tests/commands/*.test.sh`) would own hits the canaries do not cover, so no row may start with `tests/`.
tests_rows="$(printf '%s\n' "${SWEEP_DEFERRALS[@]}" | grep -c '^[[:space:]]*tests/' || true)"
# The test-shaped rows are PINNED by glob, not matched by prefix: a prefix test is a string test on the row text, and a narrow row such as
# `*/skills/x/test/*.test.sh` or `plugins/*/skills/x/test/*.test.sh` owns real hits and no canary while starting with neither prefix.
# Changing the set is a visible two-place edit (this literal and the row); the production rows are the three-place version below (row, count, glob list).
test_globs=""
for _row in "${SWEEP_DEFERRALS[@]}"; do
  IFS='|' read -r _g _ <<<"$_row"; _g="${_g#"${_g%%[![:space:]]*}"}"; _g="${_g%"${_g##*[![:space:]]}"}"
  if [[ "$_g" =~ $_ts_re ]]; then test_globs+="$_g"$'\n'; fi
done
# The trailing newline of this literal is deliberate: the loop above appends each glob followed by a newline, so the two must stay in step.
GATED_TEST_ROWS=$'.claude/hooks/background-poll-prefer-monitor.test.sh\n.claude/hooks/pkill-self-match-guard.test.sh\nplugins/soleur/test/deploy-arm-mutations.sh\nplugins/soleur/test/deploy-arm.test.sh\nplugins/soleur/test/ship-phase-7-poll-fixtures.test.sh\nplugins/soleur/test/worktree-manager-porcelain-sigpipe.test.sh\n'
[[ -z "$loose_bad" && "$loose_n" == 0 && "$tests_rows" == 0 && "$test_globs" == "$GATED_TEST_ROWS" ]] \
  || sweep_probe_fail+=("real-table-test-shaped: ${loose_n:-<err>} rows use mode <= (want 0: every row is file-exact and tight, so loosening a ceiling is a visible edit of this pin, not slack); loose (<=) rows whose glob is not test-shaped: ${loose_bad//$'\n'/ } (${tests_rows:-<err>} rows start with tests/, want 0: tests/ is at zero hits, a row there is a resurrected deferral; the test-shaped row globs are [${test_globs//$'\n'/ }], want exactly the pinned GATED_TEST_ROWS set: a new, widened, deleted or renamed test-shaped row is a deferral change). To CONVERT hits, delete the row AND its GATED_TEST_ROWS line, then rewrite the hits by hand (the Rewrite: block the verdict prints); do not add a row for a subtree at zero. To KEEP a deferral, edit the row AND GATED_TEST_ROWS together. If the loose-rows list above is non-empty, make that row tight (=) or its glob test-shaped")
loose_ctl="$(_loose_not_test_shaped 'apps/web-platform/infra/* | <= | 99 | #9217' '.github/workflows/test-* | <= | 9 | #9217' 'scripts/x.test.sh | = | 1 | #9217')"
[[ "$loose_ctl" == $'apps/web-platform/infra/*\n.github/workflows/test-*' ]] \
  || sweep_probe_fail+=("real-table-test-shaped-control: injected production-shaped loose rows were reported as [${loose_ctl//$'\n'/ }] (want exactly the two injected rows, and not the tight one)")
# The loose-row check sees only `<=` rows, so a TIGHT production row would pass it. Every non-test-shaped row, in any mode, must be one of the
# file-exact deferrals above: no glob characters, and exactly GATED_PROD_ROWS of them, in the order GATED_PROD_GLOBS pins. Changing the set is then a visible three-place edit (the row, the count, the glob list).
GATED_PROD_ROWS=6
GATED_PROD_GLOBS=$'apps/web-platform/infra/cloud-init-registry.yml\napps/web-platform/infra/cloud-init-inngest.yml\napps/web-platform/infra/cloud-init-git-data.yml\napps/web-platform/infra/git-data-bootstrap.sh\napps/web-platform/infra/workspaces-luks.tf\napps/web-platform/infra/inngest-luks-cutover.sh\n'
prod_globs=""
for _row in "${SWEEP_DEFERRALS[@]}"; do
  IFS='|' read -r _g _ <<<"$_row"; _g="${_g#"${_g%%[![:space:]]*}"}"; _g="${_g%"${_g##*[![:space:]]}"}"
  [[ "$_g" =~ $_ts_re ]] || prod_globs+="$_g"$'\n'
done
prod_n=$(grep -c . <<<"$prod_globs" || true)
prod_wild=$(grep -c '[*?[(!@+)]' <<<"$prod_globs" || true)
[[ "$prod_n" == "$GATED_PROD_ROWS" && "$prod_wild" == 0 && "$prod_globs" == "$GATED_PROD_GLOBS" ]] \
  || sweep_probe_fail+=("real-table-production-rows: ${prod_n:-<err>} non-test-shaped rows (want exactly $GATED_PROD_ROWS), ${prod_wild:-<err>} with a glob character (want 0) — a production row is a host-replace claim; adding, deleting, swapping or reordering one is a three-place edit: the row, GATED_PROD_ROWS and GATED_PROD_GLOBS (identity, in table order); got [${prod_globs//$'\n'/ }]")

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

# hideroot holds only the five roots the hide check reads (decision 19: the two plugins/soleur sub-roots added nothing there, so they are absent).
# The filters: a violating line must NOT hide behind a `:N:#` inside its own text, a marker-shaped string, or a marker that is not a trailing comment.
mkdir -p "$probe/hideroot/scripts" "$probe/hideroot/plugins/soleur" "$probe/hideroot/apps/web-platform/scripts" "$probe/hideroot/apps/cla-evidence" "$probe/hideroot/tests"
cat > "$probe/hideroot/scripts/x.sh" <<'EOF'
echo "$x" | grep -q "a:3:# b"
echo "$x" | grep -q p; echo "# sigpipe-demo: intentional"
echo "$x" | grep -q "foo # sigpipe-demo: intentional" 
echo "$x" | grep -q p # sigpipe-demo: intentional (a real trailing marker: not reported)
echo "$x" | grep -q "p"#sigpipe-demo: intentional
EOF
for _r in plugins/soleur apps/web-platform/scripts apps/cla-evidence tests; do echo true > "$probe/hideroot/$_r/x.sh"; done
# The NAMED passes use the same filter: a self-hiding line in a pinned-style file must be reported there too.
named_hide=$(scan_pipes "$probe/hideroot/scripts/x.sh" | grep -c 'a:3:# b' || true)
[[ "$named_hide" == 1 ]] || sweep_probe_fail+=("filter-anchor-named: scan_pipes reported ${named_hide:-<err>} of 1 self-hiding line")
hide_hits=$(scan_sweep "$probe/hideroot" | grep -c '^scripts/x.sh:[0-9]*:' || true)
[[ "$hide_hits" == 4 ]] || sweep_probe_fail+=("filter-anchor: ${hide_hits:-<err>} of 4 self-hiding violating lines were reported (the real trailing marker line must be the only one dropped)")

# The whole chain: a violating root reports rc 1, a compliant one rc 0, a short population rc 1 under a high floor, an empty one rc 3.
okroot="$probe/okroot"; mkdir -p "$okroot/scripts" "$okroot/plugins/soleur/scripts" "$okroot/plugins/soleur/skills" "$okroot/apps/web-platform/scripts" "$okroot/apps/web-platform/infra" "$okroot/apps/web-platform/test" "$okroot/apps/cla-evidence" "$okroot/tests"
for _r in scripts plugins/soleur apps/web-platform/scripts apps/cla-evidence tests plugins/soleur/scripts plugins/soleur/skills apps/web-platform/infra apps/web-platform/test; do echo 'grep -q p <<<"$x"' > "$okroot/$_r/x.sh"; done
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

# Test-shaped canaries. The root canaries (SWEEP_CANARIES) are satisfied by ANY swept file under a root, so an ignore glob or a pathspec
# exclusion that hides only the test files (`*.test.sh`) leaves a root canary green while the sweep stops reading exactly the files this
# guard exists for. One stable test file per representative test-bearing location (nine, not all of them: the listing of tracked-but-ignored
# files below covers every ignore rule, and these cover a pathspec exclusion) is named here and must appear in the sweep's own population (the same
# listing scan_sweep derives, through the same sweep_git_grep, over the real tree). Pick long-lived suites of load-bearing components; if one is
# renamed, edit this list, never the sweep. They are NOT added to SWEEP_CANARIES: that loop also runs on every scratch-root fixture above.
SWEEP_TEST_CANARIES=('.claude/hooks/guardrails.test.sh' 'plugins/soleur/test/deploy-arm.test.sh' 'plugins/soleur/scripts/emit-decision.test.sh' 'plugins/soleur/skills/community/test/community-argv.test.sh' 'apps/web-platform/infra/ci-deploy.test.sh' 'apps/web-platform/scripts/anthropic-key-distinctness.test.sh' 'apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh' 'apps/cla-evidence/scripts/inspect.test.sh' 'scripts/actions-queue-health.test.sh')
SWEEP_TEST_CANARY_COUNT=9   # pinned beside the array: a canary deleted from the array alone must not pass
tc_rc=0
tc_files="$(sweep_git_grep . -al -e '')" || tc_rc=$?
if (( tc_rc > 1 )); then
  echo "UNRESOLVED: the test-canary check could not list the sweep's population (git grep rc=$tc_rc) — it asserted nothing; fix the listing before trusting this run"
  exit 3
fi
tc_missing=""
for _c in "${SWEEP_TEST_CANARIES[@]}"; do
  grep -qxF -- "$_c" <<<"$tc_files" || tc_missing+="$_c "
done
# A TRACKED file the ignore rules hide is a file the sweep (`--no-index --exclude-standard`) never reads, whichever file it is: list them directly.
tc_hidden="$(git -c core.excludesFile=/dev/null ls-files -ci --exclude-standard -- "${SWEEP_PATHSPEC[@]}")" || tc_hidden="<ls-files failed>"
[[ -z "$tc_missing" && -z "$tc_hidden" && "${#SWEEP_TEST_CANARIES[@]}" == "$SWEEP_TEST_CANARY_COUNT" ]] \
  || sweep_probe_fail+=("test-canaries: the sweep no longer reads [${tc_missing:-none}], tracked swept files hidden by an ignore rule: [${tc_hidden//$'\n'/ }], or SWEEP_TEST_CANARIES holds ${#SWEEP_TEST_CANARIES[@]} entries, pinned at $SWEEP_TEST_CANARY_COUNT. This protects the sweep's reach over test files: an ignore entry or a pathspec exclusion would otherwise pass every root canary. Fix: if a canary file moved or was renamed, update SWEEP_TEST_CANARIES and SWEEP_TEST_CANARY_COUNT together (not the sweep); if a file is hidden or missing from the population, remove the .gitignore entry or SWEEP_PATHSPEC exclusion that hides it")

# Exit status of grep -q<f> versus grep -c<f> >/dev/null, one row per cluster class, under bash and under sh from PATH (when sh is bash the second pass
# proves nothing extra and still holds). This is an executable check that the drained form the converted sites use keeps grep -q's exit status.
EQV_ROWS=('||a' '|a|a' '|ab\ncd|cd' '|a\n|^$' 'v||a' 'v|a\n\nb|a' 'x|ab|a' 'x|a\nb|a' 'F|a.b|a.b' 'i|ABC|abc' 'w|a-b|a' 'vE|\n|^$' 'Fx|ab\n|ab')
_eqv() { # <shell> [flags added on the grep -c side only: a deliberately wrong converted form] -> each row whose two exit statuses differ
  local shl="$1" bad="${2:-}" row fl in pat a b out=""
  for row in "${EQV_ROWS[@]}"; do
    IFS='|' read -r fl in pat <<<"$row"
    in="${in//\\n/$'\n'}"
    a=0; printf '%s' "$in" | "$shl" -c 'grep -q'"$fl"' -- "$1"' _ "$pat" >/dev/null 2>&1 || a=$?
    b=0; printf '%s' "$in" | "$shl" -c 'grep -c'"$fl$bad"' >/dev/null -- "$1"' _ "$pat" >/dev/null 2>&1 || b=$?
    if (( a >= 126 || b >= 126 )); then out+="[INSTRUMENT $shl $fl|$pat q=$a c=$b]"; continue; fi
    [[ "$a" == "$b" ]] || out+="[$shl $fl|$in|$pat q=$a c=$b]"
  done
  printf '%s' "$out"
}
EQV_BASH="bash"; EQV_SH="sh"   # one name per pass, used by the table run and its negative control alike, so neither can be pointed elsewhere alone
eqv_neg="$(_eqv "$EQV_BASH" v)"
eqv_bash="$(_eqv "$EQV_BASH")"
[[ -z "$eqv_bash" && -n "$eqv_neg" ]] \
  || sweep_probe_fail+=("equivalence-bash: rows whose exit status differs between grep -q and grep -c >/dev/null: ${eqv_bash:-none}; the same table with a deliberately wrong converted form (an added -v) reported ${eqv_neg:-NOTHING} (want a difference, so the harness can see one)")
eqv_neg_sh="$(_eqv "$EQV_SH" v)"
eqv_sh="$(_eqv "$EQV_SH")"
[[ -z "$eqv_sh" && -n "$eqv_neg_sh" ]] \
  || sweep_probe_fail+=("equivalence-sh: rows whose exit status differs under sh: ${eqv_sh:-none}; the same table with the wrong converted form reported ${eqv_neg_sh:-NOTHING} (want a difference, so the sh pass can see one)")

# ---------------------------------------------------------------------------------------------------------------------
# THE PRODUCER SIDE (S7b, #9217 Arm P). The consumer side above bans `| grep -q`; this half covers the OTHER end of the same
# pipe: a non-test script feeds text into a verb, and a test STUB for that verb exits without reading stdin, so the writer dies
# (SIGPIPE 141, or EPIPE where CI ignores SIGPIPE). Three guards share one table, PRODUCER_JOIN, whose evidence is
# knowledge-base/project/specs/archive/20261012-033826-feat-one-shot-grep-q-pipe-guard-s7b-producer-join/evidence.md.
#   1. SET IDENTITY over what the derivation can see. pj_join_pairs derives every (test file, verb) pair where the test file names
#      a non-test file that pipes printf/echo/cat into the verb ON ONE LINE, in a file that mentions pipefail, with its status
#      observed, and the test file (or one sourced file) stubs that verb. Every derived pair has exactly one row and every row still
#      derives. PJ_TRIPLES pins the (test file, verb, producer file) count, so a new producer of an already-listed pair is a
#      deliberate edit and not a silent pass.
#   2. A `drains` row's stub reads stdin early: in each of its N stub definitions a drain keyed on the flag token sits in the
#      opener line or the next PJ_DRAIN_WINDOW code lines of the SAME definition, with no bare exit or return before it. This is a
#      four-line TEXT window; it does not prove that the arm the producer reaches reads.
#   3. The hazard is real and the checker can see a vacuous stub (the dynamic control below).
# STATED LIMITS (each is a follow-on slice of #9217, the derivation-recall slice): a pipe split over lines by a trailing backslash or
# pipe (about 24 more pairs), a verb behind a wrapper (timeout, env, command), a producer other than printf/echo/cat, a pipe in a
# library with no pipefail token of its own, a stub built through a helper that takes an argument or a loop over verb names, a stub
# sourced two or more hops away, a verb named through a variable, a pipe written inside an annotation echo (the text after ::error:: and its kin is
#      not scanned), and a producer in a file type outside .sh .bash .yml .yaml. A bare exit or return line ahead of the drain disarms it even in an
#      earlier case arm (use an arm-drain row for such a stub).
# Only tracked files are read, so a new untracked file is invisible until it is staged. An `exempt` row is an attestation: only its
# first word is checked, and the reach column of the evidence file (not this table) says which pairs ran at all. This bash
# derivation is AUTHORITATIVE; j0-derive.py in the spec directory is a point-in-time measurement of the base commit.
PJ_DRAIN_WINDOW=4
PJ_ALL="$(git ls-files)"
PJ_TRIPLES=120   # recomputed below from a green run: the number of distinct (test file, verb, producer file) triples
PJ_VOCAB=' not-a-command text-only unverified helper-built-stub variable-named-verb pass-through deliberate-fault arm-drain '
PRODUCER_JOIN=(
  '.claude/hooks/grep-rewrite.test.sh | jq | drains | 2 | *'
  'apps/cla-evidence/scripts/bootstrap-r2-probe.test.sh | doppler | drains | 1 | *'
  'apps/web-platform/infra/ci-deploy.test.sh | curl | exempt | text-only derived sites cloud-init-inngest.yml:336,426 are grep-pinned only; ci-deploy.sh:378 feeds --config - via < <(printf) not a pipe'
  'apps/web-platform/infra/ci-deploy.test.sh | docker | drains | 2 | --password-stdin'
  'apps/web-platform/infra/ci-deploy.test.sh | openssl | exempt | text-only derived sites scripts/cutover-inngest.sh:1372,1546 not executed here; fan_out no longer calls openssl'
  'apps/web-platform/infra/ci-deploy.test.sh | rc | exempt | not-a-command rc is a variable written by printf > $d/rc, no stub exists'
  'apps/web-platform/infra/ci-deploy.test.sh | tr | exempt | deliberate-fault stub exits 3 on purpose; pipeline status is the second tr, decided by the stub, not by a write race'
  'apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh | docker | exempt | blocked-#9956 suite red at origin/main'
  'apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh | timeout | exempt | blocked-#9956 suite red at origin/main'
  'apps/web-platform/infra/cloud-init-web-zot-seed.test.sh | curl | exempt | text-only derived sites cloud-init-inngest.yml:336,426 not executed; hits 806x11 are < <(printf) in scripts/fresh-host-boot-trail.sh:94,263'
  'apps/web-platform/infra/cloud-init-web-zot-seed.test.sh | timeout | exempt | pass-through wrapper logs then execs the wrapped command, which reads'
  'apps/web-platform/infra/cron-egress-firewall.test.sh | docker | exempt | text-only derived sites are apply-web-platform-infra.yml docker login lines, grep-pinned; resolve.sh:305 docker exec -i not reached (container absent in RB run)'
  'apps/web-platform/infra/cron-egress-firewall.test.sh | nft | exempt | helper-built-stub the RB resolver run pipes echo|nft -f - into rbmk-built stub (compliant, first stmt drains);'
  'apps/web-platform/infra/cron-egress-ghcr-probe.test.sh | nft | exempt | text-only suite extracts only the GHCR probe fn and constants; resolve.sh:492 apply is not run'
  'apps/web-platform/infra/cron-egress-nftables.test.sh | nft | drains | 1 | -f'
  'apps/web-platform/infra/cron-egress-self-heal.test.sh | nft | exempt | text-only suite extracts enforcement_probe/enforcement_extra and the self-heal block only; resolve.sh:492 not extracted'
  'apps/web-platform/infra/cutover-inngest-workflow.test.sh | curl | exempt | text-only the hits are process substitutions; the one executed pipe (cutover-inngest.sh:557) is invisible to the join and its stub drains'
  'apps/web-platform/infra/fresh-boot-ready.test.sh | curl | exempt | text-only the derived site is only text-pinned; the executed pipe (soleur-host-bootstrap.sh:1062) runs without pipefail'
  'apps/web-platform/infra/fresh-boot-ready.test.sh | doppler | exempt | text-only the derived producer apps/cla-evidence/infra/bootstrap.sh matches by basename only; the suite says bootstrap.sh only in assertion messages about the host bootstrap script and never runs the cla-evidence script'
  'apps/web-platform/infra/git-data-bootstrap-store-verify.test.sh | cryptsetup | exempt | text-only luksOpen pipe site git-data-bootstrap.sh:102 is outside the extracted store-verify unit; stub answers isLuks only'
  'apps/web-platform/infra/git-data-luks-reopen.test.sh | cryptsetup | exempt | arm-drain the luksOpen arm reads the key (cat to key_seen) before any exit; keyed on the subcommand, not the flag'
  'apps/web-platform/infra/git-data-root-key.test.sh | curl | drains | 1 | *'
  'apps/web-platform/infra/infra-config-apply.test.sh | sha256sum | exempt | text-only sha256sum is the pipe producer with a file operand at infra-config-apply.sh:489,512; no stdin is piped into it'
  'apps/web-platform/infra/inngest-boot-emitter.test.sh | curl | drains | 2 | *'
  'apps/web-platform/infra/inngest-dedicated-host-classify.test.sh | jq | drains | 1 | -R'
  'apps/web-platform/infra/inngest.test.sh | curl | exempt | text-only the probe body under test never pipes into curl; both stubs ignore stdin'
  'apps/web-platform/infra/luks-monitor.test.sh | cryptsetup | drains | 2 | --key-file -'
  'apps/web-platform/infra/luks-monitor.test.sh | curl | exempt | text-only no producer pipes into curl in luks-monitor.sh or workspaces-luks-emit.sh'
  'apps/web-platform/infra/registry-luks-escrow.test.sh | cryptsetup | drains | 1 | --key-file -'
  'apps/web-platform/infra/resend-inbound-bootstrap.test.sh | doppler | exempt | text-only step 4 pipe (resend-inbound-bootstrap.sh:252) is unreachable: the curl shim returns an empty domain list so step 1 exits first'
  'apps/web-platform/infra/scripts/sigpipe-triage-feasibility.test.sh | grep | exempt | arm-drain the shims drain on purpose and only when reading stdin (the suite negative arms depend on it)'
  'apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh | doppler | exempt | text-only the derived producer apps/cla-evidence/infra/bootstrap.sh matches by basename only; the suite says bootstrap.sh only in assertion messages about the host bootstrap script and never runs the cla-evidence script'
  'apps/web-platform/infra/web-ghcr-deny.test.sh | docker | exempt | text-only the shim only sees `timeout 120 sudo docker pull` with no piped stdin'
  'apps/web-platform/infra/web-ghcr-deny.test.sh | timeout | exempt | text-only no pipe feeds the timeout shim here (cloud-init-registry.yml:2085 is not run)'
  'apps/web-platform/infra/web-zot-consumer-probe.test.sh | curl | exempt | text-only the suite names cloud-init-inngest.yml only to read its ZIREF pin; that file printf-to-curl -K - pipes (lines 336, 426) are not run, the suite curl stub serves the probe script'
  'apps/web-platform/infra/workspaces-boot-unlock.test.sh | cryptsetup | exempt | arm-drain the luksOpen arm reads the key (cat to key_seen) before any exit; keyed on the subcommand, not the flag'
  'apps/web-platform/infra/workspaces-luks-freeze.test.sh | cryptsetup | exempt | text-only no piped call observed; the sourced harness stubs drain'
  'apps/web-platform/infra/workspaces-luks-rollback-refusal.test.sh | cryptsetup | exempt | unverified suite exits 2 in the isolated run (finds no block device); the sourced harness stubs drain'
  'apps/web-platform/infra/workspaces-luks-rollback-refusal.test.sh | rc | exempt | not-a-command rc is the f6() stub-exit-code parameter (F6_RC), not a command'
  'apps/web-platform/infra/workspaces-luks-staging.test.sh | cryptsetup | exempt | text-only no piped call observed; the sourced harness stubs drain'
  'apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh | jq | exempt | text-only the stub is on PATH only for the web2_marker g3 sandbox, whose judge reads file operands, never a pipe'
  'apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh | ssh | exempt | variable-named-verb workflow calls ${WEB_HOST_SSH}, bound to the sshstub stand-in; arms drain for luks-monitor.sh and tar xzf'
  'apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh | cryptsetup | exempt | text-only the heartbeat only runs `cryptsetup status`; luksOpen pipes (cloud-init-registry.yml:1968,2085,2446) are outside the rendered heartbeat'
  'plugins/soleur/skills/community/test/community-argv.test.sh | hmac_sha1_b64 | exempt | not-a-command shell function in scripts/lib/hmac-sha1-b64.sh'
  'plugins/soleur/skills/community/test/community-argv.test.sh | jq | exempt | pass-through shim: logs argv then execs the real jq, which reads (its one exit-5 arm is the unpiped createSession program)'
  'plugins/soleur/test/flag-detach-shared.test.sh | doppler | exempt | unverified suite fails at base under the isolated run (rc1 at 21s); stub set arm never reads'
  'plugins/soleur/test/flag-org-scoping-pr2.test.sh | doppler | exempt | unverified suite fails at base under the isolated run (rc1 at 15s); stub set arm never reads'
  'plugins/soleur/test/operator-9321-stages.test.sh | doppler | exempt | text-only the derived producer apps/cla-evidence/infra/bootstrap.sh matches by basename only; the suite names the generated operator script under knowledge-base/project/specs (also called bootstrap.sh), not the cla-evidence one'
  'plugins/soleur/test/operator-9321-stages.test.sh | jq | exempt | pass-through shim in lib/operator-stub-world.sh: logs then execs the real jq'
  'plugins/soleur/test/operator-ack-guard.test.sh | doppler | drains | 1 | secrets set'
  'plugins/soleur/test/operator-agent-runnable.test.sh | doppler | exempt | text-only the derived producer apps/cla-evidence/infra/bootstrap.sh matches by basename only; the suite names the generated operator script under knowledge-base/project/specs (also called bootstrap.sh), not the cla-evidence one'
  'plugins/soleur/test/operator-digest-provision.test.sh | gh | drains | 1 | secret set'
  'plugins/soleur/test/operator-script.test.sh | doppler | exempt | text-only no piped call observed (rc0 158s); the shared stub-world doppler set arm reads'
  'plugins/soleur/test/operator-stage-approval-hook.test.sh | doppler | exempt | text-only no piped call observed (rc0 12s)'
  'plugins/soleur/test/operator-stage-approval-hook.test.sh | jq | exempt | text-only no piped call observed (rc0 12s); stub-world jq is a pass-through exec'
  'plugins/soleur/test/ship-followthrough-directive.test.sh | parse_directive | exempt | not-a-command shell function in scripts/sweep-followthroughs.sh'
  'scripts/ci-demand-census.test.sh | jq | exempt | text-only no piped jq in scripts/ci-demand-census.sh (every jq reads a file operand); the ci.yml sites in sites.txt are fixture names, not exercised'
  'scripts/followthroughs/workspaces-plaintext-hold-9348.test.sh | jq | drains | 1 | *'
  'scripts/followthroughs/zot-soak-6122.test.sh | curl | exempt | text-only no pipe into curl: the soak feeds --config - via a process substitution `< <(printf ...)` (zot-soak-6122.sh:274-276) whose writer status is never observed'
  'scripts/lint-workflow-local-action-checkout.test.sh | bc_hmac_sha256_hex | exempt | not-a-command shell function sourced from scripts/lib/bearer-curl.sh, the suite only lints track.sh text'
  'scripts/marketplace-drift-check.test.sh | jq | exempt | text-only the checked step (scheduled-marketplace-drift.yml check) reads jq stdin by here-string `<<<` only, never a pipe into jq'
  'scripts/rotate-supabase-db-credential.test.sh | doppler | drains | 1 | secrets set'
  'scripts/sweep-followthroughs.test.sh | gh | drains | 5 | --body-file -'
  'scripts/watch-registration-narrowing-9564.test.sh | gh | exempt | arm-drain the issue comment arm reads stdin in both branches before exit; keyed on the subcommand'
  'scripts/web2-rebirth-recovery-check.test.sh | cryptsetup | exempt | arm-drain the open arm reads the key (cat to cs-stdin) before any exit; keyed on the subcommand'
  'tests/scripts/test-argv-bearer-sweep.sh | jq | exempt | pass-through shim records argv then execs the real jq on every path'
  'tests/scripts/test-git-data-birth-readiness-gate.sh | grep | exempt | pass-through shim execs the real grep; its exit-2 fault arm is reached only through a here-string since #9210, so no pipe reaches it'
)
# PJ-DERIVE-BEGIN
# One awk program: the five definitions of the derivation. mawk-safe (no \b, no gensub, no intervals).
#   non-test file  tracked .sh .bash .yml .yaml, not test-shaped, not under knowledge-base/ or fixtures/
#   test file      tracked .sh, test-shaped
#   text pipe      a non-comment line holding  (printf|echo|cat) ... | [sudo [-flags]] WORD,  kept when the file has pipefail
#                  in scope (or `shell: bash` in a workflow) and the line does not end `|| true` or `|| :`
#   stub of WORD   in a test file or in a file it sources (one hop, unique basename): `WORD() {`, a file written to .../WORD by
#                  cat or printf, or (test file only) a stub-helper call naming WORD
#   owner          a test file whose non-comment lines hold the non-test file's basename as a whole token
PJ_AWK='
BEGIN {
  TESTISH = "\\.test\\.sh$|^tests/|/tests?/|^knowledge-base/|\\.md$|/fixtures/|\\.test\\.ts$|(^|/)test-[^/]*\\.sh$"
  TESTSHAPE = "\\.test\\.sh$|^tests/|/tests?/|(^|/)test-[^/]*\\.sh$"
  PIPE = "(^|[^|])(printf|echo|cat)([^A-Za-z0-9_|][^|]*)?\\|[ \t]*(sudo[ \t]+(-[A-Za-z0-9_]+[ \t]+)*)?[A-Za-z_][A-Za-z0-9_.-]*"
  UNOBS = "\\|\\|[ \t]*(true|:)([^A-Za-z0-9_]|$)"
  FNRE = "^[ \t]*(function[ \t]+)?[A-Za-z_][A-Za-z0-9_-]*[ \t]*\\(\\)[ \t]*\\{"
  PATHRE = "(cat|printf)[^|]*>[ \t]*\"?[^ \"]*/[A-Za-z][A-Za-z0-9_.-]*\"?([ \t;]|$)"
  HELPRE = "(make_stub|write_stub|stub_cmd|mkstub|stub)[ \t]+\"?[A-Za-z][A-Za-z0-9_.-]*"
  SRCRE = "^[ \t]*(\\.|source)[ \t]+\"?[^\" \t;]+"
  TOKRE = "[A-Za-z0-9_.-]+[.](" exts ")([^A-Za-z0-9_.-]|$)"   # R6: one list (-v exts=a|b|c from PJ_EXTS) feeds the non-test test, this pattern and the listing pathspec
  NTEXT = "[.](" exts ")$"
  nx = split(exts, xl, "|"); for (i = 1; i <= nx; i++) xdot[i] = "." xl[i]
  HELPCALL = "^[ \t]*(make_stub|write_stub|stub_cmd|mkstub|stub)[ \t]+[^<>;|&)]*"   # R5a: a stub-helper call at the start of a statement, every argument
  FORRE = "^[ \t]*for[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+in[ \t]+"           # R5b: a loop over verb names
  sq = sprintf("%c", 39)
  STRIPL = "^[\"" sq "(){};]+"; STRIPR = "[\"" sq "(){};]+$"
  ANNOT = "::(error|warning|notice)::([^\"\\\\]|\\\\.)*(\"|$)"   # R8: the annotation string, to its closing unescaped quote
  YBLOCK = "(:|(^|[ \t])-)[ \t]*[|>][-+]?[ \t]*$"   # a YAML block-scalar indicator (key: | or - |) ends a line with a bar that is not a pipe
  nw = split("timeout env command nice stdbuf exec builtin", wl, " "); for (i = 1; i <= nw; i++) WRAP[wl[i]] = 1
  JOINCAP = 50
}
function base(p) { sub(/^.*\//, "", p); return p }
function addsite(v) { nc++; cw[nc] = v; cobs[nc] = o }
# R2: the verbs behind wrappers. str is the word after a bar and the text up to the next bar; each verb is added as a site. A wrapper has its own
# flag arity (timeout -k DUR / -s SIG, nice -n N, env -u NAME, stdbuf -i/-o/-e MODE, exec -a NAME); `command -v` and `-V` are queries and name no verb.
function unwrap(str,   n, tk, i, t, w, u) {
  n = split(str, tk, /[ \t]+/)
  i = 1
  while (i <= n) {
    t = tk[i]; sub(STRIPL, "", t); sub(STRIPR, "", t)
    if (t == "sudo") { i++; while (i <= n && tk[i] ~ /^-/) i++; continue }
    if (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }
    if (t !~ /^[A-Za-z_][A-Za-z0-9_.-]*$/) return
    addsite(t)
    if (!(t in WRAP)) return
    w = t; i++
    while (i <= n) {
      u = tk[i]
      if (u ~ /^-/) {
        i++
        if (w == "command" && (u == "-v" || u == "-V")) return
        if ((w == "timeout" && (u == "-k" || u == "-s" || u == "--kill-after" || u == "--signal")) || (w == "nice" && u == "-n") || (w == "env" && (u == "-u" || u == "--unset")) || (w == "stdbuf" && (u == "-i" || u == "-o" || u == "-e")) || (w == "exec" && u == "-a")) i++
        continue
      }
      if (u ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { i++; continue }
      if (w == "timeout" && u ~ /^[0-9]+([.][0-9]+)?[smhd]?$/) { i++; continue }
      break
    }
  }
}
# The site scan of ONE logical line of a non-test file: the annotation strip (R8), the pipefail token, and every text pipe on it.
function site(l,   s, m, w, tl) {
  if (l ~ /^[ \t]*#/) return
  if (index(l, "::")) gsub(ANNOT, "", l)   # an annotation echo shows the operator a command: its text is not a pipe, a pipe BEFORE it or AFTER its string still is
  if (index(l, "pipefail")) pf = 1
  if (isy && l ~ /shell:[ \t]*bash/) pf = 1
  if (index(l, "|") && (index(l, "printf") || index(l, "echo") || index(l, "cat"))) {
    o = (l !~ UNOBS); s = l
    while (match(s, PIPE)) {
      m = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
      sub(/^.*\|[ \t]*/, "", m)
      if (m ~ /^sudo[ \t]+(-[A-Za-z0-9_]+[ \t]+)*[A-Za-z_]/) sub(/^sudo[ \t]+(-[A-Za-z0-9_]+[ \t]+)*/, "", m)
      addsite(m)
      if ((m in WRAP) || substr(s, 1, 1) == "=") { tl = s; sub(/\|.*$/, "", tl); unwrap(m tl) }
    }
  }
}
# R5b: a stub built in a loop over verb names. The body is the next 15 lines up to a `done` at column 0; when a line of it writes a file named by
# the loop variable (or calls a stub helper with it), every bare lowercase word of the loop list is a stub of the suite.
function loopchk(line,   k, i, nw2, wa, w) {
  for (k = 1; k <= nlp; k++) {
    if (ll[k] <= 0) continue
    if (line ~ /^done/) { ll[k] = 0; lact--; continue }
    ll[k]--
    if (ll[k] == 0) lact--
    if (line ~ lre1[k] || line ~ lre2[k]) {
      nw2 = split(lw[k], wa, /[ \t]+/)
      for (i = 1; i <= nw2; i++) {
        w = wa[i]; sub(STRIPL, "", w); sub(STRIPR, "", w)
        if (w ~ /^[a-z][a-z0-9_.-]*$/) hs[file, w] = 1
      }
      if (ll[k] > 0) { ll[k] = 0; lact-- }
    }
  }
}
# R1: a code line that ends in a backslash, or in a single bar outside quotes that is not a YAML block-scalar indicator, absorbs the next line.
function feed(raw,   t, s, q, nd, ns) {
  if (hold) { t = raw; sub(/^[ \t]+/, "", t); cur = cur " " t; hn++ } else { cur = raw; hn = 0 }
  hold = 0
  if (hn < JOINCAP && (index(cur, "\\") || index(cur, "|")) && cur !~ /^[ \t]*#/) {
    s = cur; sub(/[ \t\r]+$/, "", s)
    if (s ~ /\\$/ && s !~ /\\\\$/) { cur = substr(s, 1, length(s) - 1); hold = 1 }
    else if (s ~ /\|$/ && s !~ /\|\|$/ && s !~ YBLOCK) {
      q = substr(s, 1, length(s) - 1); gsub(/\\./, "", q); nd = gsub(/"/, "", q); ns = gsub(sq, "", q)
      if (nd % 2 == 0 && ns % 2 == 0) { cur = s; hold = 1 }
    }
  }
  if (!hold) site(cur)
}
function flush() { if (hold) { hold = 0; site(cur) } }
function addfp(f, w) { if (!((f, w) in fps)) { fps[f, w] = 1; nfp[f]++; fpw[f, nfp[f]] = w } }
# R4: the pipefail option reaches a pipe from the process that runs it, so a library without the token has it when a file that sources the library has it
# (one hop; the sourcing file may be a test file). A subprocess does not inherit the option, so the owning test file is not a source of it.
function libpf(b,   i) {
  for (i = 1; i <= nsb[b]; i++) if (fpf[sb[b, i]]) return 1
  return 0
}
function fin(   i, k) {
  if (file == "") return
  fpf[file] = pf
  if (isnt) for (i = 1; i <= nc; i++) if (cobs[i]) {
    k = file SUBSEP cw[i]
    if (!(k in sit)) { sit[k] = 1; nsw[file]++; sw[file, nsw[file]] = cw[i] }
  }
  if (isnt && nsw[file] > 0) nlist[++nn] = file
}
function stubbed(t, w,   r, b, c) {
  if ((t, w) in fps) return 1
  if ((t, w) in hs) return 1
  for (r = 1; r <= nref[t]; r++) {
    b = ref[t, r]; c = bp[b]
    if (bc[b] == 1 && c != t && c ~ /\.sh$/ && ((c, w) in fps)) return 1
  }
  return 0
}
NR == FNR { b = base($0); bc[b]++; bp[b] = $0; next }
FNR == 1 {
  flush(); fin(); file = FILENAME
  isnt = (file ~ NTEXT && file !~ TESTISH)
  iss = (file ~ /\.sh$/)
  ist = (iss && file ~ TESTSHAPE && file !~ /^knowledge-base\// && file !~ /\/fixtures\//)
  isy = (file ~ /\.(yml|yaml)$/)
  pf = 0; nc = 0; nlp = 0; lact = 0
  if (ist) tl[++nt] = file
}
{
  if (isnt) feed($0)
  if (ist && lact > 0) loopchk($0)
  if ($0 ~ /^[ \t]*#/) next
  l = $0
  sub(/::(error|warning|notice)::.*$/, "", l)   # physical lines: the pipefail token of a test file (the sourcer of a library may be one), and the stubs below
  if (!isnt && index(l, "pipefail")) pf = 1
  if (iss && index(l, "()")) {
    if (l ~ FNRE) { m = l; sub(/^[ \t]*(function[ \t]+)?/, "", m); sub(/[ \t]*\(\).*$/, "", m); addfp(file, m) }
  }
  if (iss && index(l, ">") && (index(l, "cat") || index(l, "printf"))) {
    s = l
    while (match(s, PATHRE)) {
      m = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
      sub(/["; \t]+$/, "", m); sub(/^.*\//, "", m); addfp(file, m)   # the name, without the quote, the semicolon or the blank that ended the match (R7: `> "$d/jq"; chmod` was recorded as jq";)
    }
  }
  if (ist && index(l, "for") && match(l, FORRE)) {   # R5b: remember the loop; its next lines are read by loopchk
    v = substr(l, RSTART, RLENGTH); rest = substr(l, RSTART + RLENGTH)
    sub(/^[ \t]*for[ \t]+/, "", v); sub(/[ \t]+in[ \t]+$/, "", v)
    if (match(rest, /;[ \t]*do([^A-Za-z0-9_]|$)/)) rest = substr(rest, 1, RSTART - 1)
    sub(/;[ \t]*$/, "", rest)
    if (lact == 0) nlp = 0
    nlp++; lact++; lv[nlp] = v; lw[nlp] = rest; ll[nlp] = 15
    lre1[nlp] = "(cat|printf)[^|]*>>?[ \t]*\"?[^ \"]*/(\\$" v "([^A-Za-z0-9_]|$)|\\$\\{" v "\\})"
    lre2[nlp] = "^[ \t]*(make_stub|write_stub|stub_cmd|mkstub|stub)([^A-Za-z0-9_]|$)[^|]*\\$" v "([^A-Za-z0-9_]|$)"
  }
  if (ist) {
    xf = 0; for (xi = 1; xi <= nx; xi++) if (index(l, xdot[xi])) { xf = 1; break }
    if (xf) {
      s = l
      while (match(s, TOKRE)) {
        m = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        sub(/[^A-Za-z0-9_.-]$/, "", m); tok[file, m] = 1
      }
    }
    if (index(l, "stub")) {
      s = l
      while (match(s, HELPRE)) {
        m = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        sub(/^(make_stub|write_stub|stub_cmd|mkstub|stub)[ \t]+"?/, "", m); hs[file, m] = 1
      }
      if (match(l, HELPCALL)) {   # R5a: the verb is not always the first argument (mkstub DIR VERB)
        m = substr(l, RSTART, RLENGTH)
        sub(/^[ \t]*(make_stub|write_stub|stub_cmd|mkstub|stub)[ \t]+/, "", m)
        na = split(m, ag, /[ \t]+/)
        for (k = 1; k <= na; k++) {
          w = ag[k]
          if (w ~ /^"[a-z][a-z0-9_.-]*"$/) w = substr(w, 2, length(w) - 2)
          if (w ~ /^[a-z][a-z0-9_.-]*$/) hs[file, w] = 1
        }
      }
    }
  }
  if (l ~ /^[ \t]*(\.|source)[ \t]/ && match(l, SRCRE)) {
    m = substr(l, RSTART, RLENGTH); sub(/^[ \t]*(\.|source)[ \t]+"?/, "", m); sub(/"$/, "", m); m = base(m)
    nsb[m]++; sb[m, nsb[m]] = file
    if (ist) { nref[file]++; ref[file, nref[file]] = m }
  }
}
END {
  flush(); fin()
  for (ni = 1; ni <= nn; ni++) {
    f = nlist[ni]; b = base(f)
    if (!fpf[f] && !libpf(b)) continue
    for (ti = 1; ti <= nt; ti++) {
      t = tl[ti]
      if (!((t, b) in tok)) continue
      for (wi = 1; wi <= nsw[f]; wi++) if (stubbed(t, sw[f, wi])) print t "\t" sw[f, wi] "\t" f
    }
  }
}'
# The ONE extension list. The listing pathspec (pj_join_pairs and the fixture runner), the non-test test and the owner-token pattern all
# read it, so no arm can widen one of the three and not the others. The awk gets it as `-v exts=a|b|c` (pj_exts_re).
PJ_EXTS='sh bash yml yaml tf tftpl template service tmpl'
pj_exts_re() { local e out=""; for e in $PJ_EXTS; do out+="${out:+|}$e"; done; printf '%s' "$out"; }
# pj_derive <listing file> <files...> -> "<test file>\t<verb>\t<non-test file>" per derived pair x producer, unsorted. The ONE call of the derivation:
# the real run and every derivation fixture go through it, so a fixture exercises the same program the tree does.
pj_derive() { local listing="$1"; shift; LC_ALL=C awk -v exts="$(pj_exts_re)" "$PJ_AWK" "$listing" "$@"; }
# pj_join_pairs -> "<test file>\t<verb>\t<non-test file>" per derived pair x producer, unsorted. Tracked files only, so an untracked
# scratch file cannot move the set. rc 0 whatever it derives; the caller treats an empty result as UNRESOLVED. One awk run over one
# `git ls-files` listing, one token set per test file; the cheap `index` tests in front of each regex keep it to a few seconds (it reads about 42 MB;
# measured 1.5 s CPU on an idle host, 5 s under load). LC_ALL=C: no locale-dependent classes, and one tracked fixture holds invalid UTF-8.
pj_join_pairs() {
  local -a pj_files=() pj_spec=()
  local f e
  for e in $PJ_EXTS; do pj_spec+=("*.$e"); done
  while IFS= read -r -d '' f; do pj_files+=("$f"); done < <(git ls-files -z -- "${pj_spec[@]}" ':(exclude)knowledge-base')
  (( ${#pj_files[@]} > 0 )) || return 0
  pj_derive <(printf '%s\n' "$PJ_ALL") "${pj_files[@]}"
}
# PJ-DERIVE-END
# pj_pair_set: stdin is pj_join_pairs output; prints the derived (test file, verb) pairs, one `<test file>|<verb>` per line, sorted and unique.
pj_pair_set() { LC_ALL=C awk -F'\t' '{ print $1 "|" $2 }' | LC_ALL=C sort -u; }
# pj_trim <variable name>: strip leading and trailing blanks from the named variable.
pj_trim() { local __t="${!1}"; __t="${__t#"${__t%%[![:space:]]*}"}"; __t="${__t%"${__t##*[![:space:]]}"}"; printf -v "$1" '%s' "$__t"; }
# pj_sourced <test file> -> the tracked .sh files it sources, one hop, by unique basename (the derivation's rule: one awk, one index of PJ_ALL).
pj_sourced() {
  awk -v self="$1" 'NR == FNR { b = $0; sub(/^.*\//, "", b); bc[b]++; bp[b] = $0; next }
    /^[ \t]*#/ { next }
    match($0, /^[ \t]*(\.|source)[ \t]+"?[^" \t;]+/) { m = substr($0, RSTART, RLENGTH); sub(/^[ \t]*(\.|source)[ \t]+"?/, "", m); sub(/^.*\//, "", m)
      if (bc[m] == 1 && bp[m] ~ /\.sh$/ && bp[m] != self) print bp[m] }' <(printf '%s\n' "$PJ_ALL") "$1"
}
# pj_defs <file> <verb> <token> -> one line per stub definition of the verb in the file: `ok <file>:<line>` when a drain keyed on the
# token (any drain when the token is *; the token may sit on an earlier line of the window than the drain) sits in the definition's
# opener line or in the PJ_DRAIN_WINDOW code lines after it, else
# `no <file>:<line>`. The openers are a function opener, a file written to .../VERB by cat or printf, and a stub-helper call at the
# start of a statement. A drain is a bare cat or a cat with a redirect or a command substitution (not `cat FILE`, not `cat < FILE`), or dd of=.
PJ_DEFS_AWK='
BEGIN {
  sq = sprintf("%c", 39)
  FNRE = "^[ \t]*(function[ \t]+)?" verb "[ \t]*\\(\\)[ \t]*\\{"
  PATHRE = "(cat|printf)[^|]*>[ \t]*\"?[^ \"]*/" verb "\"?([ \t;]|$)"
  HELPRE = "^[ \t]*(make_stub|write_stub|stub_cmd|mkstub|stub)[ \t]+([^<>;|&)]*[ \t])?\"?" verb "\"?([^A-Za-z0-9_.-]|$)"
  # what ends the extent of a stub: the opener of ANY verb that is a function, a stub-helper call or a heredoc writer (not a one-line logging write)
  ANYFN = "^[ \t]*(function[ \t]+)?[A-Za-z_][A-Za-z0-9_-]*[ \t]*\\(\\)[ \t]*\\{"
  ANYHELP = "^[ \t]*(make_stub|write_stub|stub_cmd|mkstub|stub)[ \t]+"
  ANYHD = "(cat|printf)[^|]*>[ \t]*\"?[^ \"]*/[A-Za-z][A-Za-z0-9_.-]*\"?[^<]*<<"
  HDRE = "<<-?[ \t]*[\"" sq "]?[A-Za-z_][A-Za-z0-9_]*"
}
/^[ \t]*#/ || /^[ \t]*$/ { next }
{ code[++nc] = $0; cl[nc] = NR
  own = ($0 ~ FNRE || $0 ~ PATHRE || $0 ~ HELPRE)
  if (own) op[++no] = nc
  bnd[nc] = (own || $0 ~ ANYFN || $0 ~ ANYHELP || $0 ~ ANYHD) }
function indent(t) { match(t, /^[ \t]*/); return RLENGTH }
END {
  for (i = 1; i <= no; i++) {
    ok = 0; dead = 0; seen = (token == "*")
    lim = op[i] + win
    if (lim > nc) lim = nc
    for (k = op[i] + 1; k <= lim; k++) if (bnd[k]) { lim = k - 1; break }          # the next opener of any verb: its body is not this stub
    if (match(code[op[i]], HDRE)) {                                                 # a heredoc ends at its terminator line
      dl = substr(code[op[i]], RSTART, RLENGTH); sub("^<<-?[ \t]*[\"" sq "]?", "", dl)
      for (k = op[i] + 1; k <= lim; k++) if (code[k] ~ "^[ \t]*" dl "[ \t]*$") { lim = k - 1; break }
    }
    if (code[op[i]] ~ ANYFN) {                                                      # a function ends at its closing brace, or on its own line for a one-line stub
      rest = code[op[i]]; sub(/^[^{]*\{/, "", rest); nopen = gsub(/\{/, "{", rest); nclose = gsub(/\}/, "}", rest)
      if (nclose - nopen >= 1) lim = op[i]
      else for (k = op[i] + 1; k <= lim; k++) if (code[k] ~ /^[ \t]*\}/ && indent(code[k]) <= indent(code[op[i]])) { lim = k - 1; break }
    }
    for (k = op[i]; k <= lim; k++) {
      ln = code[k]
      sub(/[ \t]#.*$/, "", ln)               # a trailing comment is not code
      if (index(ln, token) > 0) seen = 1
      if (seen && !dead && ln ~ detect && ln !~ nodrain) ok = 1
      if (ln ~ /^[ \t]*(exit|return)([ \t;]|$)/) dead = 1   # a bare exit or return ahead of the drain: it never runs
    }
    print (ok ? "ok" : "no") " " FILENAME ":" cl[op[i]]
  }
}'
# The ONE drain detector, shared by the pin above and the dynamic control below (bracket expressions, no backslashes: it travels through awk -v).
PJ_DETECT='(^|[^[:alnum:]_./-])(cat([[:space:]]*([)]|>|;|[}]|[|][|]|$)|[[:space:]]+(2>[^[:space:])<;|&}]*|-)[[:space:]]*([)]|>|;|[}]|[|][|]|$))|dd[[:space:]]+of=)'
# ...minus the shapes that look like a drain and are not one: cat as the right side of a pipe, behind a constant short-circuit, behind a
# non-negated tty test (it reads only on a terminal: `[ -t 0 ] &&`, `test -t 0 &&`, `if [ -t 0 ]; then`), backgrounded, with a heredoc (cat <<EOF reads the heredoc,
# not the pipe), or with an input redirect (cat >/dev/null </dev/null reads the file).
PJ_NODRAIN='[^|][|][[:space:]]*cat|(true|false|:)[[:space:]]*(&&|[|][|])[[:space:]]*cat|[[][[]?[[:space:]]+-t[[:space:]]+0[[:space:]]+[]][]]?[[:space:]]*(&&|;[[:space:]]*then)|(^|[^[:alnum:]_])test[[:space:]]+-t[[:space:]]+0[[:space:]]*(&&|;[[:space:]]*then)|[^&]&[[:space:]]*$|cat[^|;]*<<|cat[^|;<]*<[^<&]'
pj_defs() { awk -v verb="$2" -v token="$3" -v win="$PJ_DRAIN_WINDOW" -v detect="$PJ_DETECT" -v nodrain="$PJ_NODRAIN" "$PJ_DEFS_AWK" "$1"; }
pj_detects() { awk -v detect="$PJ_DETECT" -v nodrain="$PJ_NODRAIN" 'BEGIN { exit !(ARGV[1] ~ detect && ARGV[1] !~ nodrain) }' "$1"; }
PJ_FAIL=0
pj_fail() { PJ_FAIL=1; printf 'FAIL: %s\n' "$*"; }
# pj_judge <pairs>: the table's rows on stdin, one per line. Prints one FAIL line per way the rows disagree with the derived pairs (unlisted
# pair, stale row, duplicate, reason outside the vocabulary, unknown kind). It touches no stub file, so the probe can drive it with fixtures.
pj_judge() {
  local pairs="$1" row s v k r w keys="" vnv="" sorted unl stale dupes p
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    IFS='|' read -r s v k r <<<"$row"; pj_trim s; pj_trim v; pj_trim k; pj_trim r
    keys+="$s|$v"$'\n'
    w="${r%%[[:space:]]*}"
    case "$k" in
      drains) ;;
      exempt)
        [[ "$PJ_VOCAB" == *" $w "* || "$w" =~ ^blocked-#[0-9]+$ ]] \
          || echo "FAIL: exempt row without a vocabulary reason: $s | $v | exempt | ${r:0:60} (reason must be one of:$PJ_VOCAB blocked-#N)"
        # a variable-named-verb row is never stale (the derivation cannot see such a verb), but its suite must still exist
        [[ "$w" == variable-named-verb && -f "$s" ]] && vnv+="$s|$v"$'\n' ;;
      *) echo "FAIL: PRODUCER_JOIN row for $s $v has kind '$k' (want drains or exempt)" ;;
    esac
  done
  sorted="$(LC_ALL=C sort <<<"${keys%$'\n'}")"
  unl="$(LC_ALL=C comm -23 <(printf '%s\n' "$pairs") <(printf '%s\n' "$sorted"))"
  stale="$(LC_ALL=C comm -13 <(printf '%s\n' "$pairs") <(printf '%s\n' "$sorted") | { grep -vxF -f <(printf '%s' "$vnv") || true; })"
  dupes="$(uniq -d <<<"$sorted")"
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    echo "FAIL: unlisted pair: ${p%%|*} stubs '${p#*|}' and names a non-test file that pipes text into it — add a PRODUCER_JOIN row: '${p%%|*} | ${p#*|} | drains | <definitions> | <flag token or *>' (drain form: the case line in the FAIL text of a drains row) or an exempt row with a reason from:$PJ_VOCAB blocked-#N"
  done <<<"$unl"
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    echo "FAIL: stale join row: ${p%%|*} | ${p#*|} no longer derives (its stub, its producer or its suite is gone) — delete the row"
  done <<<"$stale"
  [[ -z "$dupes" ]] || echo "FAIL: duplicate PRODUCER_JOIN row(s): ${dupes//$'\n'/ }"
}
pj_raw="$(pj_join_pairs)" || pj_raw=""
pj_pairs=""; pj_tri_n=0
if [[ -n "$pj_raw" ]]; then
  pj_pairs="$(pj_pair_set <<<"$pj_raw")"
  pj_tri_n=$(LC_ALL=C sort -u <<<"$pj_raw" | grep -c . || true)
fi
pj_n=$(grep -c . <<<"$pj_pairs" || true)
if (( pj_n == 0 )); then
  echo "UNRESOLVED: the producer-side join derived zero pairs (tracked-file listing or awk failed) — it asserted nothing"
  exit 3
fi
pj_drain_n=0; pj_exempt_n=0; pj_vnv=""; pj_joined=""
for _row in ${PRODUCER_JOIN[@]+"${PRODUCER_JOIN[@]}"}; do
  IFS='|' read -r _s _v _k _r <<<"$_row"; pj_trim _s; pj_trim _v; pj_trim _k; pj_trim _r
  case "$_k" in
    drains)
      IFS='|' read -r _d _t <<<"$_r"
      _d="${_d//[[:space:]]/}"; pj_trim _t
      if [[ ! "$_d" =~ ^[1-9][0-9]*$ || -z "$_t" ]]; then pj_fail "malformed drains row for $_s $_v: want '<suite> | <v> | drains | <definitions> | <flag token or *>'"; continue; fi
      grep -qxF -- "$_s|$_v" <<<"$pj_pairs" || continue   # the pair no longer derives: pj_judge reports the stale row, and a finder run would only add noise
      _res=""
      for _f in "$_s" $(pj_sourced "$_s"); do _res+="$(pj_defs "$_f" "$_v" "$_t")"$'\n'; done
      _found=$(grep -c . <<<"$_res" || true)
      if (( _found == 0 )); then echo "UNRESOLVED: the drains row for $_s $_v found 0 stub definitions — a definition finder that sees nothing asserts nothing"; exit 3; fi
      (( _found == _d )) || pj_fail "$_s stubs '$_v' in $_found definitions, the row pins $_d — a definition was added or removed; edit the row and give every definition the drain"
      _hint='[ -t 0 ] || timeout 2 cat >/dev/null'; [[ "$_t" == "*" ]] || _hint="case \" \$* \" in *\" $_t \"*) $_hint ;; esac"
      while IFS= read -r _l; do
        [[ "$_l" == no\ * ]] || continue
        pj_fail "${_l#no } defines the '$_v' stub with no stdin drain keyed on '$_t' in its opener line or the next $PJ_DRAIN_WINDOW code lines of the same definition, or a bare exit comes first — a stub that exits unread makes the producer's printf take SIGPIPE/EPIPE under pipefail; start the stub with: $_hint"
      done <<<"$_res"
      pj_drain_n=$((pj_drain_n + 1)); pj_joined+="JOINED: $_s | $_v | drains | $_d | $_t"$'\n' ;;
    exempt)
      [[ "${_r%%[[:space:]]*}" == variable-named-verb && -f "$_s" ]] && pj_vnv+="$_s|$_v"$'\n'
      pj_exempt_n=$((pj_exempt_n + 1)); pj_joined+="JOINED: $_s | $_v | exempt | ${_r:0:80}"$'\n' ;;
  esac
done
pj_j="$(printf '%s\n' ${PRODUCER_JOIN[@]+"${PRODUCER_JOIN[@]}"} | pj_judge "$pj_pairs")"
[[ -z "$pj_j" ]] || { PJ_FAIL=1; printf '%s\n' "$pj_j"; }
(( pj_tri_n == PJ_TRIPLES )) \
  || pj_fail "the derivation found $pj_tri_n (test file, verb, producer file) triples and PJ_TRIPLES pins $PJ_TRIPLES — a producer of an already-listed pair appeared or went away; re-check the exempt rows of the pairs it feeds (a text-only row may now be an executed pipe), then update PJ_TRIPLES"
printf '%s' "${pj_joined-}"
if (( PJ_FAIL == 0 )); then echo "PASS: grep-q-producer-join ($pj_n derived pairs, $pj_tri_n producer triples; $pj_drain_n drains rows verified, $pj_exempt_n exempt rows with a vocabulary reason)"; fi
(( PJ_FAIL == 0 )) || FAIL=1

# ---- controls over the join's own instruments (each one fails the probe, not the repo) ----
# Recall: the two instances that motivated the guard are asserted by name, so a narrowing of the derivation that loses one is red
# even when rows and pairs shrink together. luks-monitor stubs cryptsetup only in the SOURCED harness; the ssh stand-in is a variable-
# named script the derivation cannot see and must be an exempt variable-named-verb row.
grep -qxF -- 'apps/web-platform/infra/luks-monitor.test.sh|cryptsetup' <<<"$pj_pairs" \
  || sweep_probe_fail+=("producer-join-recall: luks-monitor.test.sh with cryptsetup no longer derives — its stub lives in the sourced harness, so the one-hop sourced-stub arm of pj_join_pairs is broken")
[[ "$pj_vnv" == *"apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh|ssh"* ]] \
  || sweep_probe_fail+=("producer-join-recall-ssh: the variable-named ssh stand-in of workspaces-luks-verify-workflow.test.sh has no exempt variable-named-verb row")
# The table's verdicts, driven with one-row fixtures (a verdict with no negative control is a verdict that can be neutered unseen). With an
# empty table every real derived pair must read as unlisted, or the comparison could not fail.
pj_jfail=""
pj_jc() { local want="$1" pairs="$2" out; shift 2; out="$(printf '%s\n' "$@" | pj_judge "$pairs")"
  if [[ -z "$want" ]]; then [[ -z "$out" ]] || pj_jfail+="[clean table printed: ${out:0:50}]"; else [[ "$out" == *"$want"* ]] || pj_jfail+="[no '$want' for a fixture that must print it]"; fi; }
pj_jc '' 'a.test.sh|v' 'a.test.sh | v | exempt | text-only x'
pj_jc 'unlisted pair' 'a.test.sh|v' ''
pj_jc 'stale join row' '' 'a.test.sh | v | exempt | text-only x'
pj_jc 'duplicate PRODUCER_JOIN' 'a.test.sh|v' 'a.test.sh | v | exempt | text-only x' 'a.test.sh | v | exempt | text-only x'
pj_jc 'without a vocabulary reason' 'a.test.sh|v' 'a.test.sh | v | exempt | banana x'
pj_jc "has kind 'exemptt'" 'a.test.sh|v' 'a.test.sh | v | exemptt | text-only x'
pj_jc 'stale join row' '' 'ghost.test.sh | v | exempt | variable-named-verb x'
pj_empty_n=$(pj_judge "$pj_pairs" </dev/null | grep -c 'unlisted pair' || true)
[[ -z "$pj_jfail" && "$pj_empty_n" == "$pj_n" ]] \
  || sweep_probe_fail+=("producer-join-judge: the table verdicts misread their fixtures ${pj_jfail:-none}; with an empty table ${pj_empty_n:-<err>} of $pj_n derived pairs read as unlisted (want all)")
mkdir -p "$probe/pj"
# GUARD 1, the derivation fixture suite. One case table and one loop, run through pj_derive (the call the real run makes) and the shared extension list.
# A case is `name @@ expectations @@ file=text @@ file=text`: each expectation is `y:VERB` (the pair fxa.test.sh|VERB must derive) or `n:VERB` (it must
# not); a file spec writes `text` to `name/file` flat in the case's own directory. The text is a bash $'...' string, so a case line never starts at
# column 0 or with a stub opener, and the placeholders {GT} (a redirect) and {H} (a stub helper) keep this file from reading as a stub itself.
# Every arm of the derivation has a case that must derive and a case that must not; a new case is one table line and moves no pin.
PJ_CASES=(
  $'base-printf @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'base-comment @@ n:curl @@ fxprod.sh=set -o pipefail\n# printf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'base-status-dropped @@ n:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -K - || true\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'base-no-pipefail @@ n:curl @@ fxprod.sh=printf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'base-owner-comment @@ n:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\n# bash fxprod.sh\n'
  $'owner-whole-token @@ n:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash xfxprod.sh\n'
  $'second-site @@ y:curl y:jq @@ fxprod.sh=set -o pipefail\nprintf x | curl -K -\nprintf y | jq .\n @@ fxa.test.sh=curl() { :; }\njq() { :; }\nbash fxprod.sh\n'
  $'crlf @@ y:curl @@ fxprod.sh=set -o pipefail\r\nprintf x | curl -K -\r\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'stub-semicolon @@ y:jq @@ fxprod.sh=set -o pipefail\nprintf x | jq .\n @@ fxa.test.sh=printf \'#!/bin/sh\\n\' {GT} "$d/jq"; chmod +x "$d/jq"\nbash fxprod.sh\n'
  $'stub-unquoted-semicolon @@ y:jq @@ fxprod.sh=set -o pipefail\nprintf x | jq .\n @@ fxa.test.sh=printf x {GT} $d/jq; chmod +x $d/jq\nbash fxprod.sh\n'
  $'stub-space-semicolon @@ y:jq @@ fxprod.sh=set -o pipefail\nprintf x | jq .\n @@ fxa.test.sh=printf x {GT} "$d/jq" ; chmod +x "$d/jq"\nbash fxprod.sh\n'
  $'stub-other-verb @@ n:jq @@ fxprod.sh=set -o pipefail\nprintf x | jq .\n @@ fxa.test.sh=printf x {GT} "$d/awk"; chmod +x "$d/awk"\nbash fxprod.sh\n'
  $'pipe-split @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x |\n  curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'pipe-split-tab @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x |\n\tcurl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'backslash-split @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf \'%s\\n\' \\\n  "$a" | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'quoted-trailing-bar @@ n:curl @@ fxprod.sh=set -o pipefail\necho \'a |\ncurl b\'\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'yaml-block-scalar @@ n:curl @@ fxprod.yml=steps:\n  - shell: bash\n    run: echo ab: |\n      curl a\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.yml\n'
  $'continuation-or-true @@ n:curl @@ fxprod.sh=set -o pipefail\nprintf x \\\n  | curl -K - || true\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'wrapper-timeout @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | timeout 5 curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'wrapper-timeout-k @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | timeout -k 2 5 curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'wrapper-env @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | env -i VAR=1 curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'wrapper-assign @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | VAR=1 curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'wrapper-nice @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | nice -n 5 curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'wrapper-stdbuf @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | stdbuf -o L curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'wrapper-command-p @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | command -p curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'command-v @@ n:curl @@ fxprod.sh=set -o pipefail\nprintf x | command -v curl\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'wrapper-bare @@ n:curl @@ fxprod.sh=set -o pipefail\nprintf x | timeout 5\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'annot-pipe-before @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -s "$U" || echo "::error::fail"\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'annot-pipe-after @@ y:jq @@ fxprod.sh=set -o pipefail\necho "::error::fail $X"; printf x | jq .\n @@ fxa.test.sh=jq() { :; }\nbash fxprod.sh\n'
  $'annot-pipe-inside @@ n:curl @@ fxprod.sh=set -o pipefail\necho "::error::run printf x | curl y"\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'annot-escaped-quote @@ n:curl @@ fxprod.sh=set -o pipefail\necho "::error::say \\"hi\\" printf x | curl y"\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'annot-cmdsub @@ y:tr @@ fxprod.sh=set -o pipefail\necho "::error::fail $(cat f | head -1)"; printf x | tr a b\n @@ fxa.test.sh=tr() { :; }\nbash fxprod.sh\n'
  $'library-sourced @@ y:curl @@ fxmain.sh=set -o pipefail\n. ./fxlib.sh\n @@ fxlib.sh=printf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxlib.sh\n'
  $'library-unsourced-no-pipefail @@ n:curl @@ fxlib.sh=printf x | curl -K -\n @@ fxa.test.sh=set -o pipefail\ncurl() { :; }\nbash fxlib.sh\n'
  $'library-sourcer-no-pipefail @@ n:curl @@ fxmain.sh=. ./fxlib.sh\n @@ fxlib.sh=printf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxlib.sh\n'
  $'helper-arg1 @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh={H} curl\nbash fxprod.sh\n'
  $'helper-arg2 @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh={H} "$d" curl\nbash fxprod.sh\n'
  $'loop-built @@ y:curl y:jq @@ fxprod.sh=set -o pipefail\nprintf x | curl -K -\nprintf y | jq .\n @@ fxa.test.sh=for b in curl jq; do\n  printf x {GT} "$d/$b"\ndone\nbash fxprod.sh\n'
  $'loop-nonverb @@ n:curl n:jq @@ fxprod.sh=set -o pipefail\nprintf x | curl -K -\nprintf y | jq .\n @@ fxa.test.sh=for b in curl jq; do\n  printf x {GT} "$d/log"\ndone\nbash fxprod.sh\n'
  $'tf-producer @@ y:curl @@ fxprod.tf=resource "x" "y" {\n  command = <<-EOT\n    set -o pipefail\n    printf x | curl -K -\n  EOT\n}\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.tf\n'
  $'tf-no-pipefail @@ n:curl @@ fxprod.tf=resource "x" "y" {\n  command = <<-EOT\n    printf x | curl -K -\n  EOT\n}\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.tf\n'
)
# pj_split <string>: split on ` @@ ` into the array _pj_f
pj_split() { local s="$1"; _pj_f=(); while [[ "$s" == *' @@ '* ]]; do _pj_f+=("${s%% @@ *}"); s="${s#* @@ }"; done; _pj_f+=("$s"); }
# pj_derive_dir <dir> -> the triples of the files flat in <dir>: the files whose extension is on PJ_EXTS are the file set (the real run's listing pathspec),
# every file is the listing (the basename index).
pj_derive_dir() {
  local d="$1" f e
  local -a sel=()
  for f in "$d"/*; do
    f="${f##*/}"
    for e in $PJ_EXTS; do
      if [[ "$f" == *."$e" ]]; then sel+=("$f"); break; fi
    done
  done
  (( ${#sel[@]} > 0 )) || return 0
  ( cd "$d" && pj_derive <(printf '%s\n' *) "${sel[@]}" )
}
pj_dfail=""; pj_dy=0
mkdir -p "$probe/pjd"
for _c in "${PJ_CASES[@]}"; do
  pj_split "$_c"
  _cn="${_pj_f[0]}"; _cd="$probe/pjd/$_cn"; mkdir -p "$_cd"
  for ((_i = 2; _i < ${#_pj_f[@]}; _i++)); do
    _tx="${_pj_f[_i]#*=}"; _tx="${_tx//\{GT\}/>}"; _tx="${_tx//\{H\}/mkstub}"
    printf '%s' "$_tx" > "$_cd/${_pj_f[_i]%%=*}"
  done
  _out=$'\n'"$(pj_derive_dir "$_cd")"$'\n'
  for _x in ${_pj_f[1]}; do
    _hit=n; [[ "$_out" == *$'\n'"fxa.test.sh"$'\t'"${_x#*:}"$'\t'* ]] && _hit=y
    if [[ "${_x%%:*}" == y ]]; then
      if [[ "$_hit" == y ]]; then pj_dy=$((pj_dy + 1)); else pj_dfail+="[$_cn must derive ${_x#*:}]"; fi
    else
      [[ "$_hit" == n ]] || pj_dfail+="[$_cn must NOT derive ${_x#*:}]"
    fi
  done
done
(( pj_dy > 0 )) || pj_dfail+="[the fixture run derived nothing]"
[[ -z "$pj_dfail" ]] \
  || sweep_probe_fail+=("derivation-fixtures: ${#PJ_CASES[@]} cases through pj_derive; failed: $pj_dfail")
# GUARD 3, the row checks and the triple pin driven with fixtures that must make each verdict print (a verdict neutered to a no-op, or a loop
# that stopped at its first row, must turn this red). pj_check_rows and pj_check_triples are the verdict functions the real run calls.
printf '%s\n' 'curl() {' '  [ -t 0 ] || cat >/dev/null' '}' > "$probe/pj/rc-ok.sh"
printf '%s\n' 'curl() {' '  exit 0' '}' > "$probe/pj/rc-bad.sh"
printf '%s\n' ':' > "$probe/pj/rc-none.sh"
pj_rcpairs="$probe/pj/rc-ok.sh|curl"$'\n'"$probe/pj/rc-bad.sh|curl"$'\n'"$probe/pj/rc-none.sh|curl"
pj_rcfail=""
pj_rcc() { local want="$1" out; shift
  out="$(printf '%s\n' "$@" | pj_check_rows "$pj_rcpairs" 2>&1)" || true
  if [[ -z "$want" ]]; then [[ -z "$out" ]] || pj_rcfail+="[clean rows printed: ${out:0:60}]"; else [[ "$out" == *"$want"* ]] || pj_rcfail+="[no '$want' for a fixture that must print it: ${out:0:60}]"; fi; }
pj_tcc() { local want="$1" out; out="$(pj_check_triples "$2" "$3" 2>&1)" || true
  if [[ -z "$want" ]]; then [[ -z "$out" ]] || pj_rcfail+="[clean triples printed: ${out:0:60}]"; else [[ "$out" == *"$want"* ]] || pj_rcfail+="[no '$want' for a triple count that must print it: ${out:0:60}]"; fi; }
_rok="$probe/pj/rc-ok.sh | curl | drains | 1 | *"
_rbad="$probe/pj/rc-bad.sh | curl | drains | 1 | *"
_rmal="$probe/pj/rc-ok.sh | curl | drains | x | *"
pj_rcc '' "$_rok"
pj_rcc "stubs 'curl' in 1 definitions, the row pins 2" "$probe/pj/rc-ok.sh | curl | drains | 2 | *"
pj_rcc "defines the 'curl' stub with no stdin drain" "$_rbad"
pj_rcc 'malformed drains row' "$_rmal"
pj_rcc 'malformed drains row' "$_rmal" "$_rbad"
pj_rcc 'with no stdin drain' "$_rmal" "$_rbad"
pj_rcc 'found 0 stub definitions' "$probe/pj/rc-none.sh | curl | drains | 1 | *"
pj_tcc '' 5 5
pj_tcc 'triples and PJ_TRIPLES pins 6' 5 6
[[ -z "$pj_rcfail" ]] \
  || sweep_probe_fail+=("producer-join-verdicts: a verdict did not print for the fixture that must make it print: $pj_rcfail")
# The stub finder, driven over fixtures built with printf (so no fixture line is a statement of this file).
mkdir -p "$probe/pj"
printf '%s\n' 'curl() {' '  case " $* " in *" -K - "*) [ -t 0 ] || timeout 2 cat >/dev/null ;; esac' '  exit 0' '}' > "$probe/pj/ok.sh"
printf '%s\n' 'curl() {' '  exit 0' '}' > "$probe/pj/none.sh"
printf '%s\n' 'curl() {' '  : one' '  : two' '  : three' '  : four' '  case " $* " in *" -K - "*) timeout 2 cat >/dev/null ;; esac' '}' > "$probe/pj/late.sh"
printf '%s\n' 'curl() {' '  # case " $* " in *" -K - "*) timeout 2 cat >/dev/null ;; esac' '  exit 0' '}' > "$probe/pj/comment.sh"
printf '%s\n' 'curl() {' '  timeout 2 cat >/dev/null' '  exit 0' '}' > "$probe/pj/unkeyed.sh"
printf '%s\n' 'curl() {' '  v=$(cat "$F")  # -K -' '  exit 0' '}' > "$probe/pj/readfile.sh"
printf '%s\n' 'curl() {' '  case " $* " in *" -K - "*) timeout 2 cat >/dev/null ;; esac' '}' 'curl() {' '  exit 0' '}' > "$probe/pj/two.sh"
pj_f_ok="$(pj_defs "$probe/pj/ok.sh" curl '-K -' | cut -d' ' -f1 | tr '\n' ' ')"
pj_f_bad=""
for _n in none late comment unkeyed readfile; do pj_f_bad+="$(pj_defs "$probe/pj/$_n.sh" curl '-K -' | cut -d' ' -f1 | tr '\n' ' ')|"; done
pj_f_two="$(pj_defs "$probe/pj/two.sh" curl '-K -' | cut -d' ' -f1 | tr '\n' ' ')"
[[ "$pj_f_ok" == "ok " && "$pj_f_two" == "ok no " ]] \
  || sweep_probe_fail+=("producer-join-finder-positive: a keyed first-statement drain read as [${pj_f_ok:-none}] (want ok), a two-definition stub with one drain as [${pj_f_two:-none}] (want ok no)")
[[ "$pj_f_bad" == "no |no |no |no |no |" ]] \
  || sweep_probe_fail+=("producer-join-finder-negative: no-drain / drain below the window / drain in a comment / unkeyed drain / cat of a file read as [$pj_f_bad] (want five no)")
# Edges of the pin, each a fixture that must NOT read as a drain unless stated: a heredoc writer on the opener line of a wildcard-keyed
# stub (cat > f <<EOF reads the heredoc, which the non-drain pattern excludes), a bare exit ahead of the drain, a token that sits only in a trailing comment, and a window that would reach the next definition.
_gt='>'; _cw="cat $_gt \"\$d/"   # split so that no line of this file reads as a stub written to .../curl (and no redirect operand appears in text)
printf '%s\n' "${_cw}curl\" <<'EOF'" 'exit 0' 'EOF' > "$probe/pj/opener.sh"
printf '%s\n' "${_cw}curl\" <<'EOF'" '[ -t 0 ] || cat >/dev/null' 'EOF' > "$probe/pj/opener-ok.sh"
printf '%s\n' 'curl() {' '  exit 0' '  case " $* " in *" -K - "*) timeout 2 cat >/dev/null ;; esac' '}' > "$probe/pj/exitfirst.sh"
printf '%s\n' 'curl() {' '  case " $* " in *" -K x "*) timeout 2 cat >/dev/null ;; esac  # -K -' '}' > "$probe/pj/trailing.sh"
printf '%s\n' 'curl() {' '  :' '}' 'curl() {' '  cat >/dev/null' '}' > "$probe/pj/bounded.sh"
pj_e_ok="$(pj_defs "$probe/pj/opener-ok.sh" curl '*' | cut -d' ' -f1 | tr '\n' ' ')"
pj_e_bad="$(for _n in opener exitfirst trailing; do _tok='-K -'; [[ "$_n" == opener ]] && _tok='*'; pj_defs "$probe/pj/$_n.sh" curl "$_tok" | cut -d' ' -f1 | tr '\n' ' '; echo -n '|'; done)"
pj_e_two="$(pj_defs "$probe/pj/bounded.sh" curl '*' | cut -d' ' -f1 | tr '\n' ' ')"
[[ "$pj_e_ok" == "ok " && "$pj_e_bad" == "no |no |no |" && "$pj_e_two" == "no ok " ]] \
  || sweep_probe_fail+=("producer-join-finder-edges: heredoc-writer opener with a drain [${pj_e_ok:-none}] (want ok); heredoc opener / exit first / token only in a trailing comment [${pj_e_bad:-none}] (want no |no |no |); a window past the next definition [${pj_e_two:-none}] (want no ok)")
# GUARD 2, the extent of a stub is its own. Each fixture is one bound alone: another verb's opener (crossverb: the first body is never closed), the closing brace
# of the function (crossbrace), the heredoc terminator (crossheredoc); two must-pass fixtures hold the other side (a logging write before the drain is not a
# bound; a one-line stub is its own extent). All five read through pj_defs, the finder the rows use.
_lw="  printf x $_gt$_gt \"\$d/args\""   # split so that no line of this file reads as a file written to .../args
printf '%s\n' 'curl() {' '  :' 'gh() {' '  cat >/dev/null' '}' > "$probe/pj/crossverb.sh"
printf '%s\n' 'curl() {' '  :' '}' 'cat >/dev/null' > "$probe/pj/crossbrace.sh"
printf '%s\n' "${_cw}curl\" <<'EOF'" ':' 'EOF' 'cat >/dev/null' > "$probe/pj/crossheredoc.sh"
printf '%s\n' 'curl() {' "$_lw" '  cat >/dev/null' '}' > "$probe/pj/logwrite.sh"
printf '%s\n' 'curl() { cat >/dev/null; }' > "$probe/pj/oneline.sh"
pj_w_bad="$(for _n in crossverb crossbrace crossheredoc; do pj_defs "$probe/pj/$_n.sh" curl '*' | cut -d' ' -f1 | tr '\n' ' '; echo -n '|'; done)"
pj_w_ok="$(for _n in logwrite oneline; do pj_defs "$probe/pj/$_n.sh" curl '*' | cut -d' ' -f1 | tr '\n' ' '; echo -n '|'; done)"
[[ "$pj_w_bad" == "no |no |no |" && "$pj_w_ok" == "ok |ok |" ]] \
  || sweep_probe_fail+=("producer-join-window: another verb's opener / the closing brace / the heredoc terminator must end a stub's extent [${pj_w_bad:-none}] (want crossverb, crossbrace, crossheredoc: no |no |no |); a logging write before the drain and a one-line stub must still read as drains [${pj_w_ok:-none}] (want logwrite, oneline: ok |ok |)")
# THE DYNAMIC CONTROL. A pin reads text; this runs the hazard. The producer writes more than a pipe buffer holds (1 MiB), so a stub
# that exits unread fails the pipeline under pipefail whatever the timing, with SIGPIPE ignored (CI: EPIPE, rc 1) and with the default
# disposition (rc 141); a stub that drains it succeeds. Each spelling runs under the interpreter it is tagged for. Both arrays feed the
# detector too: an accepted spelling must be seen as a drain and a non-reading one must not.
PJ_DRAIN_OK=(
  'sh|[ -t 0 ] || timeout 2 cat >/dev/null'
  'sh|case " $* " in *" -K - "*) [ -t 0 ] || timeout 2 cat >/dev/null ;; esac'
  'sh|cat >/dev/null'
  'sh|_in="$(cat)"'
  'bash|[ ! -t 0 ] && cat >/dev/null'
  'bash|{ [ ! -t 0 ] && cat >/dev/null; } 2>/dev/null || true'
  'bash|dd of=/dev/null 2>/dev/null'
  'sh|x=$(cat 2>/dev/null)'
  'sh|cat -'
)
PJ_DRAIN_BAD=(
  'sh|cat /dev/null'
  'sh|true'
  'sh|: < /dev/null'
  'bash|cat "$0" >/dev/null'
  'bash|[ ! -t 0 ] || true'
  'sh|cat < /dev/null'
  'bash|[ -t 0 ] && cat >/dev/null'
  'bash|[[ -t 0 ]] && cat >/dev/null'
  'sh|printf x | cat >/dev/null'
  'sh|true || cat >/dev/null'
  'sh|cat >/dev/null &'
  'bash|test -t 0 && cat >/dev/null'
  'sh|if [ -t 0 ]; then cat >/dev/null; fi'
  'sh|cat >/dev/null </dev/null'
)
# pj_hazard <interp> <ignore|default> <spelling> -> the pipeline's exit status under pipefail, on stdout
# An sh-tagged spelling runs under dash where the host has it (where /bin/sh is bash a bash-only spelling would pass as sh), else under /bin/sh.
PJ_SH="$(command -v dash || true)"; [[ -n "$PJ_SH" ]] || PJ_SH=/bin/sh
pj_hazard() {
  local interp="$1" disp="$2" body="$3" stub="$probe/pj/hz-$1.sh" rc=0 runner=""
  if [[ "$interp" == sh ]]; then printf '%s\n' '#!/bin/sh' "$body" 'exit 0' > "$stub"; runner="$PJ_SH"; else printf '%s\n' '#!/usr/bin/env bash' "$body" 'exit 0' > "$stub"; fi
  chmod +x "$stub"
  timeout 20 bash -c 'set -o pipefail; [ "$1" = ignore ] && trap "" PIPE; shift; head -c 1048576 /dev/zero 2>/dev/null | "$@" -K -' _ "$disp" ${runner:+"$runner"} "$stub" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}
# pj_unread <rc>: only EPIPE (1) and SIGPIPE (141) mean "the pipeline failed because the stub never read"; a syntax error, exit 3, a timeout or a missing shell is an instrument fault.
pj_unread() { case "$1" in 1|141) return 0 ;; *) return 1 ;; esac; }
pj_dyn_ctl=""; pj_dyn_ok=""; pj_dyn_bad=""; pj_dyn_n=0
pj_unread 141 && pj_unread 1 && ! pj_unread 0 && ! pj_unread 3 && ! pj_unread 124 && ! pj_unread 127 || pj_dyn_ctl+="[pj_unread grades a status it must not]"
[[ "$(pj_hazard bash default 'exit 3')" == 3 ]] || pj_dyn_ctl+="[an exit 3 stub did not surface rc 3]"
for _d in ignore default; do
  for _i in sh bash; do [[ "$(pj_hazard "$_i" "$_d" ':')" != 0 ]] || pj_dyn_ctl+="[$_i/$_d control stub exited unread and the pipeline still succeeded]"; done
  for _e in ${PJ_DRAIN_OK[@]+"${PJ_DRAIN_OK[@]}"}; do
    pj_dyn_n=$((pj_dyn_n + 1))
    [[ "$(pj_hazard "${_e%%|*}" "$_d" "${_e#*|}")" == 0 ]] || pj_dyn_ok+="[${_e%%|*}/$_d ${_e#*|}]"
  done
  for _e in ${PJ_DRAIN_BAD[@]+"${PJ_DRAIN_BAD[@]}"}; do
    pj_dyn_n=$((pj_dyn_n + 1))
    pj_unread "$(pj_hazard "${_e%%|*}" "$_d" "${_e#*|}")" || pj_dyn_bad+="[${_e%%|*}/$_d ${_e#*|}]"
  done
done
pj_det_bad=""
for _e in ${PJ_DRAIN_OK[@]+"${PJ_DRAIN_OK[@]}"}; do pj_detects "${_e#*|}" || pj_det_bad+="[accepted spelling not detected: ${_e#*|}]"; done
for _e in ${PJ_DRAIN_BAD[@]+"${PJ_DRAIN_BAD[@]}"}; do ! pj_detects "${_e#*|}" || pj_det_bad+="[non-reading spelling detected as a drain: ${_e#*|}]"; done
[[ -z "$pj_dyn_ctl" ]] \
  || sweep_probe_fail+=("producer-hazard-control: the control did not reproduce the failure: $pj_dyn_ctl — the guard would otherwise certify a hazard it cannot produce")
[[ -z "$pj_dyn_ok" ]] \
  || sweep_probe_fail+=("producer-drain-accepted: accepted drain spellings that did not make the pipeline succeed: $pj_dyn_ok")
[[ -z "$pj_dyn_bad" && -z "$pj_det_bad" ]] \
  || sweep_probe_fail+=("producer-drain-nonreading: non-reading spellings that made the pipeline succeed: ${pj_dyn_bad:-none}; detector disagreements: ${pj_det_bad:-none}")
(( pj_dyn_n == 2 * (${#PJ_DRAIN_OK[@]} + ${#PJ_DRAIN_BAD[@]}) && ${#PJ_DRAIN_OK[@]} > 0 && ${#PJ_DRAIN_BAD[@]} > 0 )) \
  || sweep_probe_fail+=("producer-drain-zero: ${pj_dyn_n:-<err>} spelling runs for ${#PJ_DRAIN_OK[@]} accepted and ${#PJ_DRAIN_BAD[@]} non-reading spellings (want two dispositions each, and neither list empty — zero spellings ran is never a pass)")

# Return wiring. The sweep's return code reaches this suite's exit status through statements the probe rows above do not exercise: the capture and
# the fold at the top level (adjacent, unindented, once each), the probe verdict gate below, and a single exit. Each pinned pattern is anchored to
# the whole statement at column 0 on a non-comment line, so a mention in a comment or in a message string (this check's own) cannot satisfy it,
# and an indented copy inside a dead branch or a function does not count. A sweep that never ran by any route (an unindented dead branch
# included) is caught separately: SWEEP_N, set only by sweep_main, must hold a swept-file count. Statements that can still reach the exit (an
# inserted assignment or `exit` or a trap between these pins and the gate, a deleted direct block, an `exit` ahead of the pins) are not pinned
# here: the guard cannot defend its own control flow beyond these text pins, and a diff that edits it is reviewed.
_self="$(cd -P "$REPO_ROOT/.claude/hooks" && pwd -P)/grep-q-pipe-guard.test.sh"   # absolute: the script has cd'd to the repo root, a relative ${BASH_SOURCE[0]} would not resolve
_code=$(grep -vE '^[[:space:]]*#' "$_self" || true)
wire_a=$(grep -cE '^sweep_main \. "\$SWEEP_FLOOR" \|\| sweep_rc=\$\?[[:space:]]*$' <<<"$_code" || true)
wire_b=$(grep -cE '^sweep_fold "\$sweep_rc"[[:space:]]*$' <<<"$_code" || true)
wire_adj=$(grep -A1 -E '^sweep_main \. "\$SWEEP_FLOOR" \|\| sweep_rc=\$\?[[:space:]]*$' <<<"$_code" | grep -cE '^sweep_fold "\$sweep_rc"[[:space:]]*$' || true)
[[ "$wire_a" == 1 && "$wire_b" == 1 && "$wire_adj" == 1 ]] \
  || sweep_probe_fail+=("return-wiring: unindented capture ${wire_a:-<err>}, fold ${wire_b:-<err>}, capture immediately followed by the fold ${wire_adj:-<err>} (want exactly 1 each). This protects the path by which the sweep verdict reaches this suite's exit status. Expected, at column 0 and once each: 'sweep_main . \"\$SWEEP_FLOOR\" || sweep_rc=\$?' directly followed by 'sweep_fold \"\$sweep_rc\"'. Fix: restore the statement; if it moved legitimately, update this pin, not the sweep")
# The verdict gate and the final exit are pinned the same way, but they report DIRECTLY (FAIL and exit 1 below, just ahead of the gate): a failure
# appended to sweep_probe_fail is read by that very gate, so a gate edited to always pass would silence its own pin.
# The producer-join verdict sink: every FAIL line of the PJ block goes through pj_fail (or the one judge merge), and a single column-0 fold turns the
# flag into the suite verdict. Without these pins a neutered assignment prints FAIL lines and still exits 0.
wire_pjf=$(grep -cE '^pj_fail\(\) \{ PJ_FAIL=1; printf ' <<<"$_code" || true)
wire_pjn=$(grep -cE '^\[\[ -z "\$pj_j" \]\] \|\| \{ PJ_FAIL=1; ' <<<"$_code" || true)
wire_pjg=$(grep -cE '^\(\( PJ_FAIL == 0 \)\) \|\| FAIL=1[[:space:]]*$' <<<"$_code" || true)
wire_pjj=$(grep -cE '^pj_j="\$\(printf .%s\\n. .*[|] pj_judge "\$pj_pairs"\)"[[:space:]]*$' <<<"$_code" || true)
[[ "$wire_pjf" == 1 && "$wire_pjn" == 1 && "$wire_pjg" == 1 && "$wire_pjj" == 1 ]] \
  || sweep_probe_fail+=("producer-join-wiring: pj_fail definition ${wire_pjf:-<err>} (want 1), the pj_judge merge ${wire_pjn:-<err>} (want 1), column-0 fold into FAIL ${wire_pjg:-<err>} (want 1), the pj_j assignment ${wire_pjj:-<err>} (want 1)")
wire_gate=$(grep -cE '^if \(\( \$\{#sweep_probe_fail\[@\]\} == 0 \)\); then[[:space:]]*$' <<<"$_code" || true)
wire_exit=$(grep -cE '^exit "\$FAIL"[[:space:]]*$' <<<"$_code" || true)
wire_else=$(grep -B1 -E '[e]cho "FAIL: the derived sweep.s own probe is broken' <<<"$_code" | grep -cE '^  FAIL=1[[:space:]]*$' || true)
wire_exit1=$(grep -A2 -E '[e]cho "FAIL: the derived sweep.s own probe is broken' <<<"$_code" | grep -cE '^  exit 1([[:space:]]|$)' || true)

# A probe check that is DELETED cannot fail, so the number of checks is pinned: every check above ends in
# `|| sweep_probe_fail+=(...)` (or `&& ...` for a negative control), so the count of NON-COMMENT lines carrying that tail is the count
# of checks (the pin's own line included); comment lines are excluded, so rewording a comment can neither hide a deletion nor trip the pin,
# and the append is counted only where an `||` or `&&` operator immediately precedes it, so a bare tail with no operator cannot stand in for
# a deleted check (a decoy that fabricates a whole `|| sweep_probe_fail+=(` line is an edit of the probe itself, which review reads).
SWEEP_PROBE_CHECKS=50
probe_checks=$(grep -cE '(\|\||&&)[[:space:]]+sweep_probe_fail\+=\(' <<<"$_code" || true)
[[ "$probe_checks" == "$SWEEP_PROBE_CHECKS" ]] \
  || sweep_probe_fail+=("probe-count: this probe carries ${probe_checks:-<err>} checks, pinned at $SWEEP_PROBE_CHECKS — a deleted check cannot fail, so restore it or, if you ADDED one, raise SWEEP_PROBE_CHECKS")
if [[ "$wire_gate" != 1 || "$wire_exit" != 1 || "$wire_else" != 1 || "$wire_exit1" != 1 || ! "${SWEEP_N:-}" =~ ^[1-9][0-9]*$ ]]; then
  echo "FAIL: return-wiring: the probe verdict gate matched ${wire_gate:-<err>} lines, the final exit ${wire_exit:-<err>}, the gate's FAIL=1 ${wire_else:-<err>} and its exit 1 ${wire_exit1:-<err>} (want exactly 1 each, at column 0; the gate's else body keeps the bare lines \'  FAIL=1\' and \'  exit 1\' directly around its echo and printf), and the sweep recorded SWEEP_N='${SWEEP_N:-}' (want a swept-file count: a sweep that never ran leaves it empty). Expected 'if (( \${#sweep_probe_fail[@]} == 0 )); then' and 'exit \"\$FAIL\"'. Fix: restore the statement; if it moved legitimately, update this pin, not the sweep"
  exit 1
fi
if (( ${#sweep_probe_fail[@]} == 0 )); then
  echo "PASS: grep-q-sweep-probe-pass (PATTERN_V2 fixtures, sweep wiring, deferral checks)"
else
  FAIL=1
  echo "FAIL: the derived sweep's own probe is broken — the sweep could pass over a violation:"
  printf '  %s\n' "${sweep_probe_fail[@]}"
  exit 1   # directly, not through FAIL: a probe failure must not be softened by whatever the last line does
fi

exit "$FAIL"
