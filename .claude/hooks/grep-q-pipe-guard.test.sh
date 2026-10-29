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
# pipe split across lines is not seen (the derived sweep below widens the spellings and joins a pipe that ends a line; see its limits). What pins the WIRE is
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
# derives its own population: every non-ignored file with a covered extension (SWEEP_EXTS: sh bash bats yml yaml tf template js ts tsx mjs cjs py; this
# file and every knowledge-base archive/ directory excluded), asserted ZERO outside SWEEP_DEFERRALS, plus two multi-line passes (a pipe that ends a
# line, joined to the next code line; the code lines of a markdown fence that holds pipefail). A new file under a new directory is in the population
# without any edit.
# STATED LIMITS of the sweep (Item F state, measured 2026-10-15 over about 4,500 files: 4,494 before the fix round, 4,496 at its head; counts rot, so
# re-measure before quoting one; each figure's command is in evidence.md of the Item F spec dir, archived at ship under knowledge-base/project/specs/archive/):
#   population  an extensionless script with a shebang (6 tracked, 0 hits); a file type outside SWEEP_EXTS (.tftpl .service .tmpl .json .toml .html Dockerfile:
#               0 hits in code when measured; the only .json hits are 4 lines of this change's own mutation-rows.json); .md outside knowledge-base is read through
#               its pipefail fences only, so a fence without pipefail (18 lines in 6 files), prose (12 lines, among them the inline probe templates at
#               plugins/soleur/skills/ship/SKILL.md "HTTP probe" and "DNS probe"), a fence inside a blockquote or a <pre> block, a fence opened on a list-item line
#               (`- ```bash`) and a split pipe inside a fence are not read; markdown under knowledge-base (runbooks); the 14 hits in 6 scripts under
#               knowledge-base archive/ directories (frozen records, never run); a path that holds a colon, a quote, a backslash or a control character (the sweep
#               REFUSES such a tree: UNRESOLVED, since the hit format cannot carry it); and this file.
#   syntax      a reader behind a function (25 candidate functions, 0 call sites); a compound-command opener or a reader that is not the first command of its group
#               (`x | if grep -q p; then`, `x | while grep -q p`, `x | ! grep -q p`, `x | { cd d; grep -q p; }`; `{ grep -q p; }` and `( grep -q p )` ARE read); a
#               binary spelled as a relative or variable-prefixed path (`./grep`, `"$DIR/grep"`), `/usr/bin/env grep`, `busybox grep`, an array expansion
#               (`"${GREP[@]}"`), `ack`; an env assignment with a quoted value (`FOO="a b" grep`); one wrapper with more than four own tokens (wrap-5-tokens: a stack
#               of several short wrappers IS read) or a wrapper outside the list (the list is in the WRAP comment below); inside `sh -c`: a payload that holds an
#               ESCAPED quote of its own kind BEFORE the reader (one after it is read), `--rcfile f -c`, `--init-file f -c` and `-c --`, a shell outside sh bash dash ash mksh rbash zsh ksh fish (`busybox sh`, `"$SHELL"`, `/usr/bin/env bash`); a
#               backslash continuation other than a pipe's own (`x | \` joined to its next line, which may itself be continued, and a continued line that ends the
#               file is joined too); code after a `/* ... */` opener on the same line (in the JS family and Terraform the line is dropped as a comment; in a shell file it is read); a line that ends in `: |` or a lone `|`
#               line is read as a YAML block scalar in every file type, so a shell pipe written that way is not joined; a `#` or an open quote at the end of a line
#               makes the split pass over-read (a joined line that is not a pipe), never miss.
#   markers     the marker is matched as text: a string that holds the words followed by a space still exempts its line. SWEEP_MARKER_PIN pins every marked line of
#               the swept files per file; the markdown pass never honours the marker; for a split pipe the marker goes on the READER line (the next code line).
#   cost        git's regex engine is quadratic in the length of ONE physical line for some shapes: a line made of `a=| ` words (each a VAR=value token that holds a bar,
#               so the wrapper run restarts at every bar) took about 0.5 s at 5 KB, 8 s at 20 KB and 29 s at 40 KB, while 15 other shapes of 20 to 400 KB finished in
#               under 60 ms on one git 2.55 build, so the figure depends on the shape and the build. The longest tracked line is 6,296 bytes (scripts/guard-vacuity-floor.test.sh,
#               a regex alternation that holds a bar). mawk's regex is quadratic too: a bar line carrying a 20 KB run of spaces takes about 5 s, and 40,000 backslash-continued
#               lines 5 to 14 s; no line in the tree is near either. The split pass skips a line without a bar before any regex runs. A generated bundle that long needs an ignore entry, not a wider limit.
#   reach       `test-all.sh --affected` selects this guard only for the paths its declared edge list names (apps/web-platform and tests/ paths, .claude/hooks); not
#               plugins/ (the `plugins/.` entry minted a dead `^plugins/./` edge and was deleted in #9441; two named plugin test files do select it), .github/, scripts/*.sh outside scripts/lib, scripts/*.py, lefthook.yml, knowledge-base code
#               or markdown: the full battery in CI always runs it.
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
_self="$(cd -P "$REPO_ROOT/.claude/hooks" && pwd -P)/grep-q-pipe-guard.test.sh"   # absolute: the script has cd'd to the repo root, a relative ${BASH_SOURCE[0]} would not resolve

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
# WHAT PATTERN_V2 CLOSES (the sweep only; the named passes keep PATTERN): the part comments at its definition list every spelling. Item F (#9217) widened it
# past the S6 set to wrappers with their own flags (sudo, doas, time, nohup, setsid, xargs, env -i PATH=x, timeout -s KILL 5), zgrep rg ag ugrep pcregrep, an
# `sh -c` reader behind the same wrappers, one bare operand between flags (`grep P -q`), `-5q`, abbreviated long options (--qui, --max=1) and a variable whose
# name carries grep. None had a live site when measured: the widening adds 0 hits over the swept population (33 equal 33), so it is protection for the next
# site, not a conversion. `xargs` is kept although xargs drains its stdin (measured PIPESTATUS 0 123: no SIGPIPE): `x | xargs grep -q p` is flagged for review,
# but its hazard is xargs's own status under pipefail, not the early exit, so the here-string remedy printed below does not apply to it (wrap-xargs).
# WHAT A LINE REGEX STILL CANNOT CLOSE (Item F state, measured 2026-10-15 over about 4,500 swept files: code lines, comments dropped, this file excluded; the
# commands are in evidence.md of the Item F spec dir, archived at ship). Counts rot: re-measure before quoting one. The syntax-level residuals are listed under
# STATED LIMITS above and pinned as `res` cases in the sweep probe; these are the reader classes:
#   | head -N          760 lines (578 of them `head -1`) in 290 files. A reader that exits after N lines is dangerous only where the site is a bare pipeline
#                      under set -e and the producer writes more than a few KB. No static property separates the harmful from the harmless (the chain
#                      `x | head -1 | grep -q p` is matched by its grep half); a count ratchet would churn on every legitimate site and buy no property.
#                      A review item, tracked with the awk exit below as one conversion wave.
#   | awk '... exit'   42 single-line stages and 13 multi-line programs. PATTERN_AWK_EXIT sees the single-line form in the named passes only; a multi-line
#                      program needs a program-extent parser, and most are value-extraction captures.
#   | read             6 lines, none a real reader;  | sed ...q   1 line (a `!q` filter in plugins/soleur/test/preflight-check10-suite-integrity.test.sh)
#   a reader behind a variable whose name does not carry grep (866 stages, 1 with an early flag, a `-hmac` option and not a reader).
#   a procsub-out reader (cmd > >(grep -q ...)) and a quoted -q inside a pattern (the stated false positives `grep -c p -eq`, `rg -tmd p`, `rg --max-columns 100 p`,
#   `grep -- -q` and `xargs echo grep -q p`, pinned as fp cases).
#   the marker (ALLOW_MARKER): an in-string match still EXEMPTS its line; SWEEP_MARKER_PIN pins every marked line per file, so a new one is a visible edit.
# THE PRODUCER SIDE of the pipe (a stub that never reads the stdin a `printf |` feeds it, so the writer takes the signal) is
# invisible to any line search: it needs a join from each production pipe to the owning suite's stub. S7b (#9217) adds that join
# (the block headed THE PRODUCER SIDE near the end of this file): it derives every (test file, verb) pair, requires a PRODUCER_JOIN row
# for each, pins the stdin drain of every `drains` row inside the extent of its own stub, and runs the hazard for real. S7c widened what it
# derives (split lines, wrapped verbs, any producer before a bar, libraries, helper-built and loop-built stubs, more file types). What it
# still does NOT see is listed under STATED LIMITS in that block; a pair whose suite never reaches the stub is an exempt text-only row, and a
# process substitution is not a pipe. The series stays open: the follow-on slices of #9217 are listed in that block, not planned here, and
# this header does not claim the series is finished.

# PATTERN_V2 is the widened reader pattern the DERIVED SWEEP (scan_sweep, below) uses. The four named
# passes above keep PATTERN, so none of them can turn red on a spelling they never carried. Five parts plus an `sh -c` alternative, so
# each can be mutated on its own (the case table in the sweep probe names one case per part and per member of every alternation):
#   LEAD   a single bar (or |&), then optionally a brace or paren group opener
#   WRAP   command|builtin|exec|env|nice|stdbuf|timeout|sudo|doas|time|nohup|setsid|xargs|ionice|chrt|taskset|unbuffer|flock, each with up to four word tokens of its
#          own flags and operands, or VAR=x, any number; a fifth token on ONE wrapper is the stated residual (wrap-5-tokens)
#   BIN    grep, egrep, fgrep, zgrep, zegrep, rg, ag, ugrep, pcregrep, `\grep` or an absolute path ending in one of them, or a variable
#          whose NAME carries grep (`"$GREP"`, `${GREP_BIN}`, `${GREP:-grep}`); any other variable is not read (866 stages, 1 with an early flag)
#   ARG    flags, long flags, and the argument-taking -e/-f/-A/-B/-C/-m/-d/-D with its operand, then AT MOST ONE bare operand, then more
#          flags (GNU grep permutes: `grep P -q`). The operand is one shell word, quote-aware (TOK): an unbounded run of tokens read quoted test
#          strings as code (measured over the 8-extension population of 2026-10-05: an unbounded run of unquoted words +115 lines, an unbounded quote-aware run +5, one operand 0)
#   EARLY  the early-exit flag: -q/-m in a cluster (digits allowed, `-5q`), --quiet --silent --max-count in any unambiguous abbreviation
#          (--qui, --s, --sil, --m=1, --ma=1, --max=1, --max-c=1), and a terminator (anything but a letter, digit, `_` or `-`) so the flag is a whole word
#   SHC    the reader inside `sh -c '...'` / `bash -lc "..."` / `bash -euo pipefail -c '...'` / `bash --norc -c '...'` (SWEEP_SHELL: sh bash dash ash mksh rbash zsh ksh fish, or a
#          path to one; SWEEP_SHF: any run of option clusters, `-o NAME`-style options with their operand, `+x` and long options before the `-c` cluster): its own
#          alternative because the quote hides the grep from the grammar above; the payload may hold the OTHER quote kind and may start with `$'`. It is built
#          from the SAME lead, wrapper, binary, argument and early parts, so it cannot drift from them.
# What stays unread, stated: see STATED LIMITS and WHAT A LINE REGEX STILL CANNOT CLOSE above; the `res` and `fp` cases of the sweep probe pin each.
SWEEP_LEAD='(^|[^|])\|&?[[:space:]]*(\{[[:space:]]+|\([[:space:]]*)?'
SWEEP_TOK='('"'"'[^'"'"']*'"'"'|"[^"]*"|[^[:space:]'"'"'"|;&)}]+)+'
SWEEP_WRAPW='(command|builtin|exec|env|nice|stdbuf|timeout|sudo|doas|time|nohup|setsid|xargs|ionice|chrt|taskset|unbuffer|flock)'
SWEEP_WRAP="(${SWEEP_WRAPW}([[:space:]]+${SWEEP_TOK}){0,4}[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*"
SWEEP_BIN='((\\|/[^[:space:]]*/)?(e|f|z|ze)?grep|(\\|/[^[:space:]]*/)?(rg|ag|ugrep|pcregrep)|"?\$\{?[A-Za-z_]*[Gg][Rr][Ee][Pp][A-Za-z_]*(:-[^}]*)?\}?"?)'
SWEEP_FLAG='([[:space:]]+(-[A-Za-z0-9]+|--[a-z-]+(=[^[:space:]]+)?|-[efABCmdD][[:space:]]+[^[:space:]]+))*'
SWEEP_ARG="${SWEEP_FLAG}([[:space:]]+${SWEEP_TOK})?${SWEEP_FLAG}"
SWEEP_EARLY='[[:space:]]+(-[A-Za-z0-9]*[qm][A-Za-z0-9]*|--(q[a-z]*|s(i[a-z]*)?|m(a(x(-c[a-z]*)?)?)?)(=[^[:space:]]*)?)([^[:alnum:]_-]|$)'
SWEEP_SHELL='((\\|/[^[:space:]]*/)?((ba|da|rba|a|mk|z|k)?sh|fish))'
SWEEP_SHF='([[:space:]]+([-+][A-Za-z]*[oO][[:space:]]+[A-Za-z]+|[-+][A-Za-z]+|--[a-z-]+))*'
SWEEP_SHQ="(\\\$?'([^']*[^[:alnum:]_/.-])?|\"([^\"]*[^[:alnum:]_/.-])?)"
SWEEP_SHC="${SWEEP_LEAD}${SWEEP_WRAP}${SWEEP_SHELL}${SWEEP_SHF}[[:space:]]+-[A-Za-z]*c[A-Za-z]*[[:space:]]+${SWEEP_SHQ}${SWEEP_BIN}${SWEEP_ARG}${SWEEP_EARLY}"
PATTERN_V2="${SWEEP_LEAD}${SWEEP_WRAP}${SWEEP_BIN}${SWEEP_ARG}${SWEEP_EARLY}|${SWEEP_SHC}"
# Every alternative of PATTERN_V2 starts at a bar, so a line without one cannot match: the sweep ANDs this literal in front of the pattern (git's regexec has
# no literal prefilter and tries the lead group at every byte: 24 s of user CPU became 2 s on one host, 0.58 s of wall became 0.30 s on a quieter git build, byte-identical output). The probe pins the property (pattern-bar-prefilter).
SWEEP_PREFILTER='\|'

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
# `; echo "# sigpipe-demo: intentional"` tail does not exempt the line. STATED LIMIT (Item F): a string that
# contains the words followed by a space (`"a # sigpipe-demo: intentional b"`) is still EXEMPTED; the compensating control is SWEEP_MARKER_PIN, which pins every
# marked line of the swept files (knowledge-base code outside archive/ included) per file, so a new marker is a visible one-row edit with its reason in the PR body.
# A markdown fence has no opt-out at all.
ALLOW_MARKER='[[:space:]]#[[:space:]]*sigpipe-demo:[[:space:]]*intentional([[:space:]]|$)'
# The comment filter every scan shares, PER LANGUAGE (Item F): `path:NN:<spaces>#...` is a comment in a shell, YAML, Terraform, template, Python or
# markdown-fence line, and `//`, `/*` and a leading `*` (a JSDoc line: `*` then a space, a slash or the end) are comments in the JS family (js ts tsx mjs
# cjs); Terraform has `//` and `/*` only. A `#` line in a .ts or .js file is code (a private field), a `//` line in a .py file is code, and a `*) ...` case arm in a .sh
# or .ts file is code, so each filter reads only its own extensions. The three extension lists (hash, slash, c-block) are the style of each SWEEP_EXTS member (comment-style-lists
# in the probe requires every swept extension to name one), and .md is read only through its fences. `--marker`
# also drops a line carrying the per-line ALLOW_MARKER (the sweep only; the four named passes deliberately have no opt-out, and the markdown pass never
# honours it: a marker in a fence is no entry of SWEEP_MARKER_PIN). `-a` keeps a line with a non-UTF-8 byte a line: without it grep prints
# "Binary file matches" in its place and the hit is dropped.
SWEEP_HASH_EXTS=(sh bash bats yml yaml tf template py md)
SWEEP_SLASH_EXTS=(js ts tsx mjs cjs)
SWEEP_CBLOCK_EXTS=(tf)   # `//` and `/*` open a comment here, a leading `*` does not: in a heredoc it is a crontab line
_strip_comments() { # [--marker], stdin -> stdout
  local IFS='|' hash_re slash_re cblock_re
  hash_re='^[^:]+\.('"${SWEEP_HASH_EXTS[*]}"'):[0-9]+:[[:space:]]*#'
  slash_re='^[^:]+\.('"${SWEEP_SLASH_EXTS[*]}"'):[0-9]+:[[:space:]]*(//|/\*|\*([[:space:]/]|$))'
  cblock_re='^[^:]+\.('"${SWEEP_CBLOCK_EXTS[*]}"'):[0-9]+:[[:space:]]*(//|/\*)'
  if [[ "${1:-}" == --marker ]]; then
    LC_ALL=C grep -avE "$hash_re" | LC_ALL=C grep -avE "$slash_re" | LC_ALL=C grep -avE "$cblock_re" | LC_ALL=C grep -avE "$ALLOW_MARKER" || true
  else
    LC_ALL=C grep -avE "$hash_re" | LC_ALL=C grep -avE "$slash_re" | LC_ALL=C grep -avE "$cblock_re" || true
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
  'apps/web-platform/infra/docker-run-tuple.test.sh'
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
PIN_7024=2; PIN_8664=2; PIN_8855=7; PIN_7376=3
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
# the population without any edit. Limits, stated plainly: a LINE search plus two multi-line passes (the
# header lists what none of them see), coverage by EXTENSION (an extensionless script with a shebang is not swept), and `git grep` reads
# the working tree, so run this suite from the checkout you edited.
#
# Flags, and why each is there (measured on this tree): --no-index lets the probe plant files that are not
# tracked; --exclude-standard keeps it out of node_modules and ignored trees (1.0 s versus 24.3 s and ten stray
# hits without it); -a makes a NUL-bearing file searchable as text; core.excludesFile=/dev/null stops a
# developer's global ignore file changing the local result; core.quotePath=false keeps a non-ASCII path a path (git otherwise prints it quoted and the
# awk passes could not open the file); LC_ALL=C makes every regex byte-wise: in a UTF-8 locale `[^|]` and `.` do not match an invalid byte, so one stray 0xFF before
# a bar hid the whole line from the pattern (and from the split listing) while `-a` only kept the line a line.
# The extension list, one array. Item F builds the pathspec AND the extension witness from it, so a dropped entry would drop out of both; the
# literal count and the separately typed list below are what see a drop (ext-count, ext-expected).
SWEEP_EXTS=(sh bash bats yml yaml tf template js ts tsx mjs cjs py)
SWEEP_EXT_COUNT=13
SWEEP_EXT_EXPECTED='sh bash bats yml yaml tf template js ts tsx mjs cjs py'
SWEEP_PATHSPEC=()
for _e in "${SWEEP_EXTS[@]}"; do SWEEP_PATHSPEC+=(":(glob)**/*.$_e"); done
# Markdown outside knowledge-base is read by scan_md only (fenced code that an agent executes), never line by line: prose names the shape.
SWEEP_MD_PATHSPEC=(':(glob)**/*.md' ':(exclude)knowledge-base')
SWEEP_PATHSPEC+=(
  # Item F (item 9): knowledge-base code files are read, archived records are not. The exclusion is path-segment exact: an archive/ directory at
  # any depth, never a name that merely contains the word. `.md` under knowledge-base stays unread because the extension list has no md.
  ':(exclude,glob)knowledge-base/**/archive/**'
  # This file carries the forbidden shape in its own probe fixtures, so it cannot sweep itself.
  ':(exclude).claude/hooks/grep-q-pipe-guard.test.sh'
)
# One swept file under each of these must exist, or the derivation is reading the wrong tree.
SWEEP_CANARIES=('scripts/' 'plugins/soleur/' 'apps/web-platform/scripts/' 'apps/cla-evidence/' 'tests/' 'plugins/soleur/scripts/' 'plugins/soleur/skills/' 'apps/web-platform/infra/' 'apps/web-platform/test/')
SWEEP_FLOOR=4000   # measured about 4,500 swept files on 2026-10-15 (4,494 before the fix round's two spec-dir scripts) (`git grep -al -e ''` under SWEEP_PATHSPEC; 1,646 with the 8 extensions of 2026-10-05); a population below the floor is a FAIL, never "no hits"
SWEEP_FLOOR_MIN=3500   # a literal beside the floor: the floor can only move with a visible edit of THIS number (floor-lower-bound below)
# The multi-line passes carry their own floors, each with a literal MIN beside it (md-floor-lower-bound in the probe): the markdown files that mention
# pipefail, the fence lines the fence awk printed from them, and the joined lines the split awk printed. They are TRIPWIRES for a pass that is not running
# (a stub, a broken opener, a listing that lost a directory), set far below the measured counts so an ordinary edit of one document cannot trip them; they do
# not measure the tree. Each counter is also tied to the lines its program printed (scan_sweep), so a counter that lies reads UNRESOLVED too.
SWEEP_MD_FLOOR=12; SWEEP_MD_FLOOR_MIN=10             # measured 21 markdown files outside knowledge-base that mention pipefail (8 of them hold a pipefail fence), 2026-10-15
SWEEP_MD_FENCE_FLOOR=150; SWEEP_MD_FENCE_FLOOR_MIN=100   # measured 676 code lines in those fences, 455 of them in plugins/soleur/commands/go.md alone (the other 7 files: 221); a stub prints 0
SWEEP_SPLIT_FLOOR=250; SWEEP_SPLIT_FLOOR_MIN=200        # measured 400 joined lines (a trailing bar, a bar and a backslash or comment, a backslash-continued next line); a stub prints 0
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
)

# scan_sweep <root> -> line 1 `SWEPT: <n> files`, then any `UNRESOLVED: ...` lines, then the code lines that match
# (path:line:text, comment lines and marked lines dropped). `git grep` exits 1 for "no hits" and above 1 on a
# fatal error: only the first is zero hits. The caller turns UNRESOLVED into a top-level exit 3 (this runs inside
# $( ), where an exit would only leave the subshell).
# The one place the sweep's flags and pathspec live: scan_sweep's listing, scan_sweep's scan and the test-canary check below all call it, so an
# exclusion or an ignore handling edit moves all three together and cannot hide a file from the scan while the canary still sees it.
sweep_git_grep() { # <root> [--md] <git grep options...>
  local root="$1"; shift
  if [[ "${1:-}" == --md ]]; then   # the markdown listing (scan_md) reads the same flags over its own pathspec
    shift
    LC_ALL=C git -c core.excludesFile=/dev/null -c core.quotePath=false -C "$root" grep --no-index --exclude-standard "$@" -- "${SWEEP_MD_PATHSPEC[@]}"
  else
    LC_ALL=C git -c core.excludesFile=/dev/null -c core.quotePath=false -C "$root" grep --no-index --exclude-standard "$@" -- "${SWEEP_PATHSPEC[@]}"
  fi
}
# Two LINEARISERS (Item F): awk programs that turn what a line search cannot see into `path:NN:text` lines, which scan_sweep then runs through the
# same widened PATTERN_V2 and the same comment filter as every other line (no regex travels through awk -v: backslash processing differs between
# gawk and mawk, and the pattern has exactly one home). POSIX awk only (no gensub, no \b, no 3-argument match). Every file name reaches awk as ./name, so
# a root-level file called A=b.sh is a file and not a variable assignment, and the programs print the name without that prefix.
#   split  a line that ends in a single bar (not `||`, not a YAML block-scalar indicator, not a comment), or in a bar and then a backslash or a `# comment`, is
#          joined to the next code line (comment and blank lines in between are skipped; a backslash-continued next line is read to its end) as
#          `path:<bar's line>: | <next line, left-trimmed>`. In a JS-family or Terraform file a `//`, `/*` or `*` line is a comment too.
#          It ends with `SPLITJOINS: <n>`, the number of joined lines it printed (the sweep floors it: a pass that prints nothing on the real tree is not running).
#   fence  the code lines of a markdown fence, but only a fence whose own text holds the token pipefail anywhere (checked at close; an unclosed fence closes at
#          EOF; a comment that names it or `set +o pipefail` counts too: an over-read, pinned as md-fp-*, never a miss, because the document may set it elsewhere); a fence is opened by 3+ backticks or tildes, indented or not, and closed by the SAME character, at least as many, nothing after.
#          The file name is taken when the fence OPENS: an unclosed fence is flushed by the next file's first record, when FILENAME already names that file.
#          It ends with `FENCELINES: <n>`, the number of fence lines it printed (floored like SPLITJOINS).
# Both programs skip a line that cannot matter before any regex runs (split: no bar on it; mawk's regex is quadratic in a line's length).
SWEEP_SPLIT_LIST='(^|[^|])\|&?[[:space:]]*(\\[[:space:]]*|#.*)?$'
SWEEP_SPLIT_AWK='
  function nm(f) { return substr(f, 3) }
  function inlist(a, n,   i) {
    for (i = 1; i <= n; i++) if (substr(FILENAME, length(FILENAME) - length(a[i])) == "." a[i]) return 1
    return 0
  }
  function iscm(l) {
    if (js) return l ~ /^[ \t]*(\/\/|\/\*|\*([ \t\/]|$))/
    if (cb) return l ~ /^[ \t]*(\/\/|\/\*)/
    return 0
  }
  function flush() {
    if (cont) { print cname ":" pn ": | " acc; nj++ }
    cont = 0; acc = ""
  }
  FNR == 1 { flush(); pend = 0; nx = split(slash_exts, sx, " "); nc = split(cblock_exts, cx, " "); js = inlist(sx, nx); cb = inlist(cx, nc) }
  !pend && !cont && index($0, "|") == 0 { next }
  {
    line = $0; sub(/\r$/, "", line)
    if (pend) {
      if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/ || iscm(line)) { next }
      t = line; sub(/^[ \t]+/, "", t); acc = ""; pend = 0; cont = 1; cname = nm(FILENAME)
    } else if (cont) {
      t = line; sub(/^[ \t]+/, "", t)
    }
    if (cont) {
      if (t ~ /\\$/) { sub(/[ \t]*\\$/, "", t); acc = acc (acc == "" ? "" : " ") t; next }
      acc = acc (acc == "" ? "" : " ") t; cont = 0
      print cname ":" pn ": | " acc; nj++
    }
    if (line ~ /[^|][ \t]*\|&?[ \t]*(\\[ \t]*|#.*)?$/ || line ~ /^[ \t]*\|&?[ \t]*(\\[ \t]*|#.*)?$/) {
      if (line ~ /:[ \t]*[|>][-+]?[ \t]*(#.*)?$/ || line ~ /^[ \t]*-?[ \t]*[|>][-+]?[ \t]*(#.*)?$/) next
      if (line ~ /^[ \t]*#/) next
      if (iscm(line)) next
      pend = 1; pn = FNR
    }
  }
  END { flush(); print "SPLITJOINS: " nj + 0 }
'
SWEEP_FENCE_AWK='
  function close_fence(   i) {
    if (hasPf) { for (i = 1; i <= n; i++) print ofile ":" ln[i] ":" tx[i]; nfl += n }
    inf = 0; n = 0; hasPf = 0
  }
  FNR == 1 { if (inf) close_fence(); inf = 0; n = 0; hasPf = 0 }
  {
    line = $0; sub(/\r$/, "", line)
    if (match(line, /^[ \t]*(```+|~~~+)/)) {
      s = substr(line, RSTART, RLENGTH); gsub(/[ \t]/, "", s)
      ch = substr(s, 1, 1); len = length(s)
      if (!inf) { inf = 1; ofile = substr(FILENAME, 3); fch = ch; flen = len; n = 0; hasPf = 0; next }
      rest = substr(line, RSTART + RLENGTH)
      if (ch == fch && len >= flen && rest ~ /^[ \t]*$/) { close_fence(); next }
    }
    if (inf) { n++; ln[n] = FNR; tx[n] = line; if (line ~ /pipefail/) hasPf = 1 }
  }
  END { if (inf) close_fence(); print "FENCELINES: " nfl + 0 }
'
# scan_split <root> -> the joined candidate lines then `SPLITJOINS: <n>`, or an UNRESOLVED line (never a silent empty result).
scan_split() {
  local root="$1" list rc=0 l
  local -a files=()
  list="$(sweep_git_grep "$root" -alE -e "$SWEEP_PREFILTER" --and -e "$SWEEP_SPLIT_LIST")" || rc=$?
  if (( rc > 1 )); then echo "UNRESOLVED: scan_split could not list the files that end a line in a pipe in $root (git grep rc=$rc) — nothing was scanned"; return 0; fi
  while IFS= read -r l; do [[ -n "$l" ]] && files+=("./$l"); done <<<"$list"
  if (( ${#files[@]} == 0 )); then echo "SPLITJOINS: 0"; return 0; fi
  ( cd "$root" && LC_ALL=C awk -v slash_exts="${SWEEP_SLASH_EXTS[*]}" -v cblock_exts="${SWEEP_CBLOCK_EXTS[*]}" "$SWEEP_SPLIT_AWK" "${files[@]}" ) || echo "UNRESOLVED: scan_split's awk failed in $root — nothing was scanned"
}
# scan_md <root> -> `MDSWEPT: <n> files` (the markdown files that mention pipefail), then the code lines of their pipefail fences and `FENCELINES: <n>`, or an UNRESOLVED line.
scan_md() {
  local root="$1" list rc=0 l bad
  local -a files=()
  list="$(sweep_git_grep "$root" --md -al -e pipefail)" || rc=$?
  if (( rc > 1 )); then echo "MDSWEPT: 0 files"; echo "UNRESOLVED: scan_md could not list the markdown files that mention pipefail in $root (git grep rc=$rc) — nothing was scanned"; return 0; fi
  bad="$(LC_ALL=C grep -aE '["\\:[:cntrl:]]' <<<"$list" | head -n 3 || true)"   # the same refusal as the code listing: the hit format path:NN:text cannot carry such a path
  if [[ -n "$bad" ]]; then echo "MDSWEPT: 0 files"; echo "UNRESOLVED: a markdown path holds a colon, a quote, a backslash or a control character, which the hit format path:NN:text cannot carry (first: ${bad//$'\n'/ | }) — rename the file or give it an ignore entry"; return 0; fi
  while IFS= read -r l; do [[ -n "$l" ]] && files+=("./$l"); done <<<"$list"
  echo "MDSWEPT: ${#files[@]} files"
  if (( ${#files[@]} == 0 )); then echo "FENCELINES: 0"; return 0; fi
  ( cd "$root" && LC_ALL=C awk "$SWEEP_FENCE_AWK" "${files[@]}" ) || echo "UNRESOLVED: scan_md's awk failed in $root — nothing was scanned"
}
# scan_sweep <root> -> `SWEPT: <n> files`, then `MDSWEPT`, `SPLITJOINS` and `FENCELINES` counts, any UNRESOLVED lines, then the matching code lines. The line
# scan and the split joins honour the per-line marker; the markdown fence lines never do (a marker in a fence is no entry of the pin).
scan_sweep() { LC_ALL=C _scan_sweep_c "$@"; }   # bash exports a variable assignment made for a function call to everything the function runs: git, grep, sed and the awk passes
_counter_tie() { # <reported joins> <printed joins> <reported fence lines> <printed fence lines> -> an UNRESOLVED line when a program's counter is not the count of the lines it printed
  if [[ "${1:-0}" != "$2" || "${3:-0}" != "$4" ]]; then
    echo "UNRESOLVED: the split pass reported ${1:-<none>} joins and printed $2, the fence pass reported ${3:-<none>} fence lines and printed $4 — a counter that is not the number of lines printed cannot back a floor"
  fi
}
_scan_sweep_c() {
  local root="$1" out rc=0 files nfiles c split_out md_out mdn sjn fln cand_split cand_md bad sj_lines fl_lines ct
  files="$(sweep_git_grep "$root" -al -e '')" || rc=$?
  if (( rc > 1 )); then
    echo "SWEPT: 0 files"
    echo "UNRESOLVED: scan_sweep could not list its population in $root (git grep rc=$rc) — nothing was scanned"
    return 0
  fi
  nfiles=$(printf '%s\n' "$files" | grep -ac . || true)
  echo "SWEPT: $nfiles files"
  # The hit format is path:NN:text and the comment filter and the verdict cut the path at the first colon: a path that holds a colon, a quote (git quotes such a
  # path and awk cannot open it), a backslash or a control character would forge or hide a hit, so the sweep refuses the tree instead of reading it.
  bad="$(LC_ALL=C grep -aE '["\\:[:cntrl:]]' <<<"$files" | head -n 3 || true)"
  if [[ -n "$bad" ]]; then
    echo "UNRESOLVED: a swept path holds a colon, a quote, a backslash or a control character, which the hit format path:NN:text cannot carry (first: ${bad//$'\n'/ | }) — rename the file or give it an ignore entry"
    return 0
  fi
  for c in "${SWEEP_CANARIES[@]}"; do
    grep -aq -- "^$c" <<<"$files" || echo "UNRESOLVED: no swept file under $c in $root — the population is not the repository's"
  done
  rc=0
  out="$(sweep_git_grep "$root" -anE -e "$SWEEP_PREFILTER" --and -e "$PATTERN_V2")" || rc=$?
  if (( rc > 1 )); then
    echo "UNRESOLVED: scan_sweep could not read its input in $root (git grep rc=$rc) — nothing was scanned"
    return 0
  fi
  split_out="$(scan_split "$root")"
  md_out="$(scan_md "$root")"
  mdn="$(sed -n 's/^MDSWEPT: \([0-9]*\) files$/\1/p' <<<"$md_out")"
  sjn="$(sed -n 's/^SPLITJOINS: \([0-9]*\)$/\1/p' <<<"$split_out")"
  fln="$(sed -n 's/^FENCELINES: \([0-9]*\)$/\1/p' <<<"$md_out")"
  if grep -aq '^UNRESOLVED:' <<<"$split_out"$'\n'"$md_out"; then
    echo "MDSWEPT: ${mdn:-0} files"; echo "SPLITJOINS: 0"; echo "FENCELINES: 0"
    grep -a '^UNRESOLVED:' <<<"$split_out"$'\n'"$md_out"; return 0
  fi
  # The floors read these counters, so each is tied to the lines its program printed, and the counter this function reports is the COUNT OF THOSE LINES: a program
  # that reports a number it did not print is a stub or a bug, not a count.
  sj_lines=$(grep -acE '^[^:]+:[0-9]+: \| ' <<<"$split_out" || true)
  fl_lines=$(grep -acE '^[^:]+:[0-9]+:' <<<"$md_out" || true)
  echo "MDSWEPT: ${mdn:-0} files"
  echo "SPLITJOINS: $sj_lines"
  echo "FENCELINES: $fl_lines"
  ct="$(_counter_tie "${sjn:-}" "$sj_lines" "${fln:-}" "$fl_lines")"
  if [[ -n "$ct" ]]; then echo "$ct"; return 0; fi
  cand_split="$(grep -aE -- "$PATTERN_V2" <<<"$split_out" || true)"
  cand_md="$(grep -aE -- "$PATTERN_V2" <<<"$md_out" || true)"
  { printf '%s\n' "$out" | _strip_comments --marker; printf '%s\n' "$cand_split" | _strip_comments --marker; printf '%s\n' "$cand_md" | _strip_comments; } | grep -a . || true
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
    [[ -n "$line" ]] || continue
    # the four counter lines, matched exactly: a glob here would let a file NAMED like one (SWEPT:x.sh) hide its own hits
    if [[ "$line" =~ ^(SWEPT|MDSWEPT):\ [0-9]+\ files$ || "$line" =~ ^(SPLITJOINS|FENCELINES):\ [0-9]+$ ]]; then continue; fi
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
    if grep -aq -E '^[^:]+:[0-9]+: \| ' <<<"$undeferred"; then
      echo "  A line shown as  path:NN: | text  is a SPLIT pipe: line NN ends in a pipe (or a pipe and a backslash or comment) and 'text' is the next code line, where the reader is."
      echo "  Fix the reader on that next line, or the pipe on line NN; the reported line number is the pipe's. An intentional demo carries the marker on the READER line (the next code line), not on line NN."
    fi
    if grep -aq -E '^[^:]+\.md:[0-9]+:' <<<"$undeferred"; then
      echo "  A .md hit is a line inside a fenced code block that also holds the word pipefail (an agent runs such a fence under pipefail): fix the line in the fence."
      echo "  A fence line carries no opt-out marker; a comment naming pipefail or 'set +o pipefail' still counts, because the document may set it elsewhere."
    fi
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
    echo "           the same shapes behind a wrapper (sudo, env, timeout, nohup ...), as rg/zgrep/pcregrep, as \"\$GREP\", or inside  sh -c '...'  ->  the same forms: the reader's stdin is the producer"
    echo "           behind xargs: xargs drains its stdin, so there is no early exit to fix; the hazard is its own status (123) under pipefail: capture the producer, then run xargs on the capture"
    echo "           an intentional demo of the shape  ->  append  # sigpipe-demo: intentional  to that line (not honoured inside a markdown fence)"
    echo "  A subtree that reached zero stays at zero: do NOT add a deferral row for it (the test-shaped and production row sets are pinned); rewrite the hit."
  fi
}

# sweep_main <root> <floor> <md floor> <fence-line floor> <split-join floor> -> prints the verdict lines; rc 0 clean, 1 a violation, 3 unresolved. The caller
# folds the rc into FAIL / exit 3, and the probe drives this same function on scratch roots, so the whole chain is exercised, not only its parts. The three
# floors after the first are REQUIRED arguments (a caller that forgets one fails loudly instead of defaulting to "no floor"). The file floor is a FAIL (the sweep
# ran and its hits are still printed); the other three are UNRESOLVED (rc 3) because a pass that printed nothing has nothing to judge, and the suite exits at once.
# NOTE: callers run this as `sweep_main ... || rc=$?`, which suspends `set -e` inside it; every fallible command in the chain is
# therefore guarded by hand, so do not rely on errexit when you add one.
sweep_main() {
  local root="$1" floor="$2" mdfloor="${3:?sweep_main needs the markdown-file floor}" fencefloor="${4:?sweep_main needs the fence-line floor}" splitfloor="${5:?sweep_main needs the split-join floor}" scan n mdn fln sjn
  SWEEP_FAIL=0
  scan="$(scan_sweep "$root")"
  SWEEP_LAST_SCAN="$scan"   # the spec-dir-zero row reads the real run's scan; set here, never by the probe's scratch roots reading it back
  if grep -q '^UNRESOLVED:' <<<"$scan"; then
    grep '^UNRESOLVED:' <<<"$scan"
    return 3
  fi
  mdn="$(sed -n 's/^MDSWEPT: \([0-9]*\) files$/\1/p' <<<"$scan")"
  fln="$(sed -n 's/^FENCELINES: \([0-9]*\)$/\1/p' <<<"$scan")"
  sjn="$(sed -n 's/^SPLITJOINS: \([0-9]*\)$/\1/p' <<<"$scan")"
  if [[ ! "${mdn:-}" =~ ^[0-9]+$ ]] || (( mdn < mdfloor )); then
    echo "UNRESOLVED: the markdown listing read ${mdn:-<no count>} files that mention pipefail, below SWEEP_MD_FLOOR $mdfloor — the fence pass would assert nothing. A truncated listing is a wrong tree or a broken SWEEP_MD_PATHSPEC; if documents legitimately dropped the word pipefail, lower SWEEP_MD_FLOOR (and the SWEEP_MD_FLOOR_MIN literal beside it) in a reviewed edit"
    return 3
  fi
  if [[ ! "${fln:-}" =~ ^[0-9]+$ ]] || (( fln < fencefloor )); then
    echo "UNRESOLVED: the fence pass printed ${fln:-<no count>} code lines from pipefail fences, below SWEEP_MD_FENCE_FLOOR $fencefloor — a pass that emits nothing on real documents asserts nothing; a stub, a broken fence opener or deleted fences all read like this (an edited SWEEP_MD_PATHSPEC shrinks it too; lower SWEEP_MD_FENCE_FLOOR and its _MIN literal only for a measured, reviewed shrink)"
    return 3
  fi
  if [[ ! "${sjn:-}" =~ ^[0-9]+$ ]] || (( sjn < splitfloor )); then
    echo "UNRESOLVED: the split pass joined ${sjn:-<no count>} lines, below SWEEP_SPLIT_FLOOR $splitfloor — a pass that joins nothing on the real tree asserts nothing (an edited SWEEP_EXTS, such as a dropped sh, shrinks it too: check ext-count first; lower SWEEP_SPLIT_FLOOR and its _MIN literal only for a measured, reviewed shrink)"
    return 3
  fi
  n="$(sed -n '1s/^SWEPT: \([0-9]*\) files$/\1/p' <<<"$scan")"
  SWEEP_N="${n:-0}"
  if [[ ! "${n:-0}" =~ ^[0-9]+$ ]] || (( ${n:-0} < floor )); then
    SWEEP_FAIL=1
    echo "FAIL: the derived sweep read ${n:-<no count>} files, below SWEEP_FLOOR $floor — the population is truncated, so a pass would assert nothing (a wrong checkout, a pathspec that lost an extension or a directory; if files were legitimately removed in bulk, lower SWEEP_FLOOR and the SWEEP_FLOOR_MIN literal beside it in a reviewed edit)"
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
sweep_main . "$SWEEP_FLOOR" "$SWEEP_MD_FLOOR" "$SWEEP_MD_FENCE_FLOOR" "$SWEEP_SPLIT_FLOOR" || sweep_rc=$?
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
x | env -i grep -q p
x | sudo grep -q p
x | grep p -q
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
V2_BAD_LINES=32; V2_GOOD_LINES=14   # pinned literals: deleting a fixture line cannot lower both sides
v2_bad_lines=$(wc -l < "$probe/bad-v2.sh")
v2_good_lines=$(wc -l < "$probe/good-v2.sh")
v2_bad_hits=$(grep -cE -- "$PATTERN_V2" "$probe/bad-v2.sh" || true)
v2_good_hits=$(grep -cE -- "$PATTERN_V2" "$probe/good-v2.sh" || true)
# scan_sweep uses `git grep -E` behind the bar prefilter, not grep -E: run the same fixtures through that exact form so a dialect divergence shows.
v2_git_bad=$(git -C "$probe" grep --no-index -nE -e "$SWEEP_PREFILTER" --and -e "$PATTERN_V2" -- bad-v2.sh | grep -c . || true)
v2_git_good=$(git -C "$probe" grep --no-index -nE -e "$SWEEP_PREFILTER" --and -e "$PATTERN_V2" -- good-v2.sh | grep -c . || true)
[[ "$v2_bad_lines" == "$V2_BAD_LINES" && "$v2_good_lines" == "$V2_GOOD_LINES" ]] \
  || sweep_probe_fail+=("v2-fixtures: a fixture file changed length (bad $v2_bad_lines/$V2_BAD_LINES, good $v2_good_lines/$V2_GOOD_LINES)")
[[ "$v2_bad_hits" == "$V2_BAD_LINES" ]] || sweep_probe_fail+=("v2-bad: PATTERN_V2 matched ${v2_bad_hits:-<grep error>}/$V2_BAD_LINES forbidden spellings")
[[ "$v2_good_hits" == 0 ]] || sweep_probe_fail+=("v2-good: PATTERN_V2 matched ${v2_good_hits:-<grep error>} safe lines (want 0)")
[[ "$v2_git_bad" == "$V2_BAD_LINES" && "$v2_git_good" == 0 ]] \
  || sweep_probe_fail+=("v2-git-dialect: git grep matched ${v2_git_bad:-<error>}/$V2_BAD_LINES bad and ${v2_git_good:-<error>} good (want all and 0)")

# The bar prefilter is only sound while every alternative of PATTERN_V2 starts at a bar: the lead part opens with the literal, the `sh -c` alternative is built
# from the same lead, and the whole pattern is exactly those two. A third alternative with no bar (a process-substitution reader, for one) must widen or drop the prefilter.
[[ "$SWEEP_LEAD" == "(^|[^|])${SWEEP_PREFILTER}"* && "$SWEEP_SHC" == "${SWEEP_LEAD}"* && "$PATTERN_V2" == "${SWEEP_LEAD}${SWEEP_WRAP}${SWEEP_BIN}${SWEEP_ARG}${SWEEP_EARLY}|${SWEEP_SHC}" ]] \
  || sweep_probe_fail+=("pattern-bar-prefilter: PATTERN_V2 is no longer exactly 'the lead form | the sh -c form built from the same lead', so the bar prefilter ($SWEEP_PREFILTER, ANDed in front of it by scan_sweep) can drop a match the pattern would make; give the new alternative's own literal to the prefilter (-e A --or -e B inside parentheses) or remove the prefilter")

# ---- Item F, Guard 1 (#9217): the reader grammar as a table of NAMED cases. One line per case: <kind> <name> <text>.
#   bad  must match          good must NOT match
#   res  a stated residual: must NOT match, pinned so widening it is a visible edit of this table
#   fp   a stated false positive: matches by design, pinned
# A mutation of one pattern part reds the case that names it ("wrap-sudo"), not a count. The table is the second member of every part of
# PATTERN_V2; the live-tree equality (0 undeferred hits on the real tree) and the committed prototype output are the other two.
read -r -d '' V2_CASES <<'EOF' || true
bad wrap-sudo x | sudo grep -q p
bad wrap-sudo-u x | sudo -u root grep -q p
bad wrap-doas x | doas grep -q p
bad wrap-env-i x | env -i grep -q p
bad wrap-env-i-path x | env -i PATH=/bin grep -q p
bad wrap-nice-n x | nice -n 10 grep -q p
bad wrap-timeout-s x | timeout -s KILL 5 grep -q p
bad wrap-time x | time grep -q p
bad wrap-xargs x | xargs grep -q p
bad wrap-xargs-n1 x | xargs -n1 grep -q p
bad wrap-command-p x | command -p grep -q p
bad wrap-nohup x | nohup grep -q p
bad wrap-setsid x | setsid grep -q p
bad wrap-stdbuf x | stdbuf -oL -eL grep -q p
bad wrap-4-tokens x | sudo -u root -g wheel grep -q p
bad wrap-ionice x | ionice -c3 grep -q p
bad wrap-chrt x | chrt 10 grep -q p
bad wrap-taskset x | taskset 0x1 grep -q p
bad wrap-unbuffer x | unbuffer grep -q p
bad wrap-flock x | flock /tmp/l grep -q p
bad bin-zgrep x | zgrep -q p
bad bin-zegrep x | zegrep -q p
bad bin-rg x | rg -q p
bad bin-rg-path x | /usr/bin/rg -q p
bad bin-rg-bs x | \rg -q p
bad bin-rg-long x | rg --quiet p
bad bin-ag x | ag -q p
bad bin-ugrep x | ugrep -q p
bad bin-pcregrep x | pcregrep -q p
bad var-dq x | "$GREP" -q p
bad var-brace x | ${GREP_BIN} -qE p
bad var-bare x | $GREP --quiet p
bad var-default x | ${GREP:-grep} -q p
bad var-lower x | "${grep_bin}" -q p
bad arg-after-operand x | grep p -q
bad arg-E-operand x | grep -E p -q
bad arg-two-e x | grep -e a -e b -q
bad arg-d-skip x | grep -d skip -q p
bad arg-long-hyphen x | grep --fixed-strings --quiet p
bad arg-trailing-flags x | grep p -i -q
bad arg-sq-operand x | grep 'a b' -q
bad arg-dq-operand x | grep "a b" -q
bad arg-twice-f x | grep -f a -f b -q p
bad arg-twice-A x | grep -A 1 -A 2 -q p
bad arg-twice-B x | grep -B 1 -B 2 -q p
bad arg-twice-C x | grep -C 1 -C 2 -q p
bad arg-twice-d x | grep -d skip -d read -q p
bad arg-twice-D x | grep -D skip -D read -q p
bad arg-context x | grep --context 3 -q p
bad arg-context-eq x | grep --context=3 -q p
bad early-5q x | grep -5q p
bad early-qui x | grep --qui p
bad early-sil x | grep --sil p
bad early-max x | grep --max=1 p
bad early-max-c x | grep --max-c=1 p
bad early-s x | grep --s p
bad early-m x | grep --m=1 p
bad early-ma x | grep --ma=1 p
bad early-m-sep x | grep -m 1 p
bad early-term-semi x | grep -q;
bad early-term-amp x | grep -q&
bad early-term-quote x | grep -q'p'
bad early-term-dquote x | grep -q"p"
bad early-term-redirect x | grep -q>/dev/null
bad early-term-pipe x | grep -q|cat
bad shc-single x | sh -c 'grep -q p'
bad shc-lc x | bash -lc "grep -qE p"
bad shc-dash x | dash -c 'grep -q p'
bad shc-zsh x | zsh -c 'grep -q p'
bad shc-ksh x | ksh -c 'grep -q p'
bad shc-abs x | /bin/sh -c 'grep -q p'
bad shc-wrap x | sudo sh -c 'grep -q p'
bad shc-group x | { sh -c 'grep -q p'; }
bad shc-pipefail x | bash -o pipefail -c 'grep -q p'
bad shc-rg x | sh -c 'rg -q p'
bad shc-egrep x | sh -c 'egrep -q p'
bad shc-quiet-long x | sh -c 'grep --quiet p'
bad shc-max-count x | sh -c 'grep --max-count=1 p'
bad shc-after-operand x | sh -c 'grep p -q'
bad shc-euo x | bash -euo pipefail -c 'grep -q p'
bad shc-eo x | bash -eo pipefail -c 'grep -q p'
bad shc-norc x | bash --norc -c 'grep -q p'
bad shc-norc2 x | bash --noprofile --norc -c 'grep -q p'
bad shc-plus-e x | bash +e -c 'grep -q p'
bad shc-O x | bash -O extglob -c 'grep -q p'
bad shc-ce x | bash -ce 'grep -q p'
bad shc-e-c x | bash -e -c 'grep -q p'
bad shc-inner-sq x | bash -c "cd 'd' && grep -q p f"
bad shc-inner-dq x | bash -c 'cd "$d" && grep -q p f'
bad shc-ansi x | bash -c $'grep -q p'
bad shc-ash x | ash -c 'grep -q p'
bad shc-mksh x | mksh -c 'grep -q p'
bad shc-fish x | fish -c 'grep -q p'
bad shc-rbash x | rbash -c 'grep -q p'
bad shc-plus-o x | bash +o pipefail -c 'grep -q p'
bad head-chain x | head -1 | grep -q p
bad head-chain-n x | head -n 1 | grep -qE p
good quoted-context-pipe expect 'adds a | grep -cx >/dev/null 1.2.3.4' 'no_ll' 'test "$(ev)" -eq 0'
good var-hook x | "$HOOK" -q p
good var-hmac x | "$CMD" -hmac key
good rg-sort x | rg --sort path p
good rg-max-depth x | rg --max-depth 2 p
good rg-smart-case x | rg --smart-case p
good shc-count x | sh -c 'grep -c p'
good shc-echo x | sh -c 'echo ok'
good shc-xgrep x | sh -c 'xgrep -q p'
good rg-stats x | rg --stats p
good wrap-sudo-tee x | sudo tee /etc/f
good wrap-time-cat x | time cat
good wrap-command-v x | command -v grep
good wrap-xargs-echo-foo x | xargs echo foo
good grep-cF-quoted x | grep -cF 'a -q b' >/dev/null
good grep-c-then-q x | grep -c p; foo -q
good grep-c-and-q x | grep -c p && foo -q
good tr-then-grep x | tr a b; grep p f -q
good or-herestring x || grep -q p <<<"$x"
good no-pipe grep p -q <<<"$x"
good head-only x | head -1
good awk-exit x | awk '{print; exit}'
good grep-oE x | grep -oE p
good grep-l x | grep -l p
good sub-count $(x | grep -c p) -eq 1
res wrap-5-tokens x | sudo -u root -g wheel -E grep -q p
res wrap-abs-env x | /usr/bin/env grep -q p
res env-quoted-value x | FOO="a b" grep -q p
res shc-escaped-quote x | sh -c "echo \"hi\"; grep -q p"
res shc-busybox x | busybox sh -c 'grep -q p'
res shc-rcfile x | bash --rcfile f -c 'grep -q p'
res shc-shell-var x | "$SHELL" -c 'grep -q p'
res compound-if x | if grep -q p; then :; fi
res compound-bang x | ! grep -q p
res group-nonfirst x | { cd d; grep -q p; }
res bin-rel-path x | ./grep -q p
res bin-var-path x | "$DIR/grep" -q p
res bin-busybox x | busybox grep -q p
res var-array x | "${GREP[@]}" -q p
res procsub-out x > >(grep -q p)
fp fp-eq x | grep -c p -eq
fp fp-xargs-echo x | xargs echo grep -q p
fp fp-rg-type x | rg -tmd p
fp fp-rg-max-columns x | rg --max-columns 100 p
fp fp-dashdash x | grep -- -q
EOF
V2_CASE_COUNT=142
v2_case_misses() { # <pattern> -> one "[kind name]" per case the pattern disagrees with, "[INSTRUMENT name rc=N]" when grep itself failed
  local pat="$1" line kind rest name text r out=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    kind="${line%% *}"; rest="${line#* }"; name="${rest%% *}"; text="${rest#* }"
    r=0; grep -E -- "$pat" <<<"$text" >/dev/null 2>&1 || r=$?
    if (( r > 1 )); then out+="[INSTRUMENT $name rc=$r]"; continue; fi
    case "$kind:$r" in
      bad:0|good:1|res:1|fp:0) ;;
      *) out+="[$kind $name]" ;;
    esac
  done <<<"$V2_CASES"
  printf '%s' "$out"
}
v2_case_n=$(grep -c . <<<"$V2_CASES" || true)
v2_case_bad="$(v2_case_misses "$PATTERN_V2")"
# The same table through the engine and the form the sweep scans with (git grep behind the bar prefilter): every `bad` text must be found, every `good` or `res`
# text not. v2_case_misses uses plain grep, so a bar-less alternative would agree with its own case there and be invisible to the sweep.
v2_git_t="$probe/cases-git"; mkdir -p "$v2_git_t"
: > "$v2_git_t/bad.txt"; : > "$v2_git_t/other.txt"
while IFS= read -r _l; do
  [[ -n "$_l" ]] || continue
  case "${_l%% *}" in bad) printf '%s\n' "${_l#* * }" >> "$v2_git_t/bad.txt" ;; good|res) printf '%s\n' "${_l#* * }" >> "$v2_git_t/other.txt" ;; esac
done <<<"$V2_CASES"
v2_git_nb=$(grep -c . "$v2_git_t/bad.txt" || true)
v2_git_no=$(grep -c . "$v2_git_t/other.txt" || true)
v2_git_nobar=$(grep -vc '|' "$v2_git_t/bad.txt" || true)   # a bad case without a bar is the shape the prefilter would hide
v2_git_hb=$(LC_ALL=C git -C "$v2_git_t" grep --no-index -anE -e "$SWEEP_PREFILTER" --and -e "$PATTERN_V2" -- bad.txt | grep -c . || true)
v2_git_ho=$(LC_ALL=C git -C "$v2_git_t" grep --no-index -anE -e "$SWEEP_PREFILTER" --and -e "$PATTERN_V2" -- other.txt | grep -c . || true)
[[ "$v2_git_nb" -gt 0 && "$v2_git_no" -gt 0 && "$v2_git_nobar" == 0 && "$v2_git_hb" == "$v2_git_nb" && "$v2_git_ho" == 0 ]] \
  || sweep_probe_fail+=("v2-cases-git: through git grep behind the bar prefilter the case table found ${v2_git_hb:-<err>} of $v2_git_nb bad texts and ${v2_git_ho:-<err>} of $v2_git_no good or residual texts, with ${v2_git_nobar:-<err>} bad texts holding no bar (want all, 0 and 0; the table has to hold a bar in every bad text: the sweep reads with this engine and form)")
[[ "$v2_case_n" == "$V2_CASE_COUNT" && -z "$v2_case_bad" ]] \
  || sweep_probe_fail+=("v2-cases: ran ${v2_case_n:-<err>}/$V2_CASE_COUNT cases, PATTERN_V2 disagreed on: ${v2_case_bad:-none} (a [bad ..] case is a spelling the pattern no longer reads; a [good ..] or [res ..] case is one it now over-reads; an [fp ..] case stopped matching)")
# The loop must be able to fail: the same table against a pattern with the wrapper part removed has to miss the wrapper cases.
PATTERN_V2_NOWRAP="${SWEEP_LEAD}${SWEEP_BIN}${SWEEP_ARG}${SWEEP_EARLY}"
v2_case_neg="$(v2_case_misses "$PATTERN_V2_NOWRAP")"
[[ "$v2_case_neg" == *"[bad wrap-sudo]"* && "$v2_case_neg" == *"[bad wrap-env-i-path]"* ]] \
  || sweep_probe_fail+=("v2-cases-negative: the case loop reported [${v2_case_neg:0:120}] against a pattern with the wrapper part removed (want the wrapper cases named, so the loop can see a miss)")

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
# The verdict's notes (a split hit and a fence hit are shown as path:NN:text; the notes say what that means and where the marker goes) and its counter lines,
# which are matched exactly: a file NAMED like a counter must not hide its hit.
vn="$( SWEEP_FAIL=0; SWEEP_DEFERRALS=(); sweep_verdict $'scripts/a.sh:3: | sudo grep -q p f\ndocs/b.md:7:x | sudo grep -q p' )"
[[ "$vn" == *"is a SPLIT pipe"* && "$vn" == *"on the READER line"* && "$vn" == *"fenced code block that also holds the word pipefail"* && "$vn" == *"behind xargs"* ]] \
  || sweep_probe_fail+=("verdict-notes: the failure text lacks the split-pipe note, the marker-on-the-reader-line advice, the fence note or the xargs remedy (a hit shown as path:NN: | text is otherwise unreadable): ${vn:0:200}")
_vp 'outside the deferral table' 'a/* | = | 1 | #1' -- 'a/x.sh:1:t' 'SWEPT:x.sh:1:t' 'FENCELINES:y.sh:2:t' \
  || sweep_probe_fail+=("verdict-counter-name: a hit in a file named like a counter line (SWEPT:x.sh) was skipped as a counter; the counter lines are matched exactly")

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
GATED_PROD_ROWS=5
GATED_PROD_GLOBS=$'apps/web-platform/infra/cloud-init-registry.yml\napps/web-platform/infra/cloud-init-inngest.yml\napps/web-platform/infra/cloud-init-git-data.yml\napps/web-platform/infra/git-data-bootstrap.sh\napps/web-platform/infra/workspaces-luks.tf\n'
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
rc_bad=0;  ( SWEEP_DEFERRALS=(); sweep_main "$sr" 1 0 0 0 >/dev/null ) || rc_bad=$?
rc_ok=0;   ( SWEEP_DEFERRALS=(); sweep_main "$okroot" 1 0 0 0 >/dev/null ) || rc_ok=$?
rc_low=0;  ( SWEEP_DEFERRALS=(); sweep_main "$okroot" 100 0 0 0 >/dev/null ) || rc_low=$?
rc_none=0; ( SWEEP_DEFERRALS=(); sweep_main "$probe/emptyroot" 1 0 0 0 >/dev/null ) || rc_none=$?
[[ "$rc_bad" == 1 && "$rc_ok" == 0 && "$rc_low" == 1 && "$rc_none" == 3 ]] \
  || sweep_probe_fail+=("sweep-main: rc violating/compliant/below-floor/empty = $rc_bad/$rc_ok/$rc_low/$rc_none (want 1/0/1/3)")
sm_a="$( ( sweep_main "$okroot" 1 ) 2>&1 || true )"; sm_b="$( ( sweep_main "$okroot" 1 0 ) 2>&1 || true )"; sm_c="$( ( sweep_main "$okroot" 1 0 0 ) 2>&1 || true )"
[[ "$sm_a" == *"needs the markdown-file floor"* && "$sm_b" == *"needs the fence-line floor"* && "$sm_c" == *"needs the split-join floor"* ]] \
  || sweep_probe_fail+=("sweep-main-args: a call with a missing floor argument must stop with a message naming it (a default of 0 is a floor that cannot fail); got [${sm_a:0:60}] [${sm_b:0:60}] [${sm_c:0:60}]")
# The counter tie: a program whose counter is not the count of the lines it printed reads UNRESOLVED (the control drives the function; the two statements that
# call it are pinned as text at their indent).
ct_a="$(_counter_tie 3 3 5 5)"; ct_b="$(_counter_tie 3 4 5 5)"; ct_c="$(_counter_tie 3 3 5 6)"; ct_d="$(_counter_tie '' 0 '' 0)"
ct_w1=$(grep -cE '^  ct="\$\(_counter_tie ' "$_self" || true)
ct_w2=$(grep -cE '^  if \[\[ -n "\$ct" \]\]; then echo "\$ct"; return 0; fi$' "$_self" || true)
[[ -z "$ct_a" && "$ct_b" == "UNRESOLVED: "* && "$ct_c" == "UNRESOLVED: "* && -z "$ct_d" && "$ct_w1" == 1 && "$ct_w2" == 1 ]] \
  || sweep_probe_fail+=("counter-tie: _counter_tie read matching counters as [${ct_a:0:30}] (want empty), a join mismatch as [${ct_b:0:30}] and a fence mismatch as [${ct_c:0:30}] (want UNRESOLVED), absent counters on empty output as [${ct_d:0:30}] (want empty); its call and test statements found ${ct_w1:-<err>}/${ct_w2:-<err>} times (want 1 and 1)")
# A swept path the hit format cannot carry is refused, not read: a colon, a quote, a backslash or a control character.
cn="$probe/cnroot"; mkdir -p "$cn" && cp -R "$okroot/." "$cn/"
printf '%s\n' 'echo "$x" | grep -q p' > "$cn/scripts/SWEPT:x.sh"
cn_out="$(scan_sweep "$cn")"
cn2="$probe/cnroot2"; mkdir -p "$cn2" && cp -R "$okroot/." "$cn2/"
printf '%s\n' 'echo "$x" | grep -q p' > "$cn2/scripts/q\"x.sh"
cn2_out="$(scan_sweep "$cn2")"
cn3="$probe/cnroot3"; mkdir -p "$cn3" && cp -R "$okroot/." "$cn3/"
mkdir -p "$cn3/docs"; printf '%s\n' '```bash' 'set -o pipefail' 'x | sudo grep -q p' '```' > "$cn3/docs/x.sh:1:#.md"
cn3_out="$(scan_sweep "$cn3")"
[[ "$cn_out" == *"UNRESOLVED: a swept path holds a colon"* && "$cn2_out" == *"UNRESOLVED: a swept path holds a colon"* && "$cn3_out" == *"UNRESOLVED: a markdown path holds a colon"* ]] \
  || sweep_probe_fail+=("path-refusal: a swept file named SWEPT:x.sh or q\"x.sh was read instead of refused (its hit would be forged, hidden or unreadable; a markdown path too): [${cn_out: -100}] [${cn2_out: -100}] [${cn3_out: -100}]")
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

# ---- Item F, Guards 2 and 3 (#9217): the multi-line passes, the widened population and the bypass pin.
# One scratch root carries a file per CASE (the case name is in the file name), laid over the compliant canary layout so the population is not
# UNRESOLVED. A must-report case names the line the pass has to report (the bar's line, not the next line's); a must-not case names the file.
# The fixtures are written with printf from words, in this file only: the spec dir and the repository are swept, so no fixture lives anywhere else.
ml="$probe/mlroot"; mkdir -p "$ml" && cp -R "$okroot/." "$ml/"
_ml_put() { local f="$ml/$1"; shift; mkdir -p "$(dirname "$f")"; printf '%s\n' "$@" > "$f"; }
_ml_put scripts/ml-split-sudo.sh          'x |' '  sudo grep -q p f'
_ml_put scripts/ml-split-line-number.sh   'a' 'b' 'x |' '  grep -q p f'
_ml_put scripts/ml-split-second-site.sh   'x |' '  sudo grep -q p f' 'y' 'z |&' '  grep -qE p f'
_ml_put scripts/ml-split-comment-next.sh  'x |' '# note' '  sudo grep -q p f'
_ml_put scripts/ml-split-blank-next.sh    'x |' '' '  sudo grep -q p f'
_ml_put scripts/ml-split-pipe-amp.sh      'x |&' '  sudo grep -q p f'
_ml_put scripts/ml-split-or-or.sh         'x ||' '  sudo grep -q p f'
_ml_put scripts/ml-split-block-scalar.yml 'run: |' '  sudo grep -q p "$f"'
_ml_put scripts/ml-split-eof-a.sh         'echo a' 'x |'
_ml_put scripts/ml-split-eof-b.sh         '  sudo grep -q p f' 'z |'
_ml_put scripts/ml-split-lone-bar.yml     'run:' '  |' '  sudo grep -q p "$f"'
_ml_put docs/ml-md-env-i.md               'prose' '```bash' 'set -o pipefail' 'x | env -i grep -q p' '```'
_ml_put docs/ml-md-pipefail-after-hit.md  '```sh' 'x | sudo grep -q p' 'set -euo pipefail' '```'
_ml_put docs/ml-md-tilde.md               '~~~' 'set -o pipefail' 'x | sudo grep -q p' '~~~'
_ml_put docs/ml-md-indented.md            '- item' '  ```sh' '  set -o pipefail' '  x | sudo grep -q p' '  ```'
_ml_put docs/ml-md-long-fence.md          '````' 'set -o pipefail' 'x | sudo grep -q p' '```' 'w | sudo grep -q p' '````' 'q | sudo grep -q p'
_ml_put docs/ml-md-tilde-mismatch.md      '~~~' 'set -o pipefail' '```' 'x | sudo grep -q p' '~~~'
_ml_put docs/ml-md-unclosed-fence.md      '```bash' 'set -o pipefail' 'x | sudo grep -q p'
printf '%s\r\n' '```bash' 'set -o pipefail' 'x | sudo grep -q p' '```' 'y | sudo grep -q p' > "$ml/docs/ml-md-crlf.md"
_ml_put docs/ml-md-pipefail-leak.md       '```bash' 'set -o pipefail' '```' '```bash' 'x | sudo grep -q p' '```'
_ml_put docs/ml-md-pipefail-other-fence.md '```bash' 'x | sudo grep -q p' '```' '```bash' 'set -o pipefail' '```'
_ml_put docs/ml-md-no-pipefail.md         '```bash' 'x | sudo grep -q p' '```'
_ml_put docs/ml-md-prose.md               'x | sudo grep -q p' '```bash' 'set -o pipefail' '```'
_ml_put docs/ml-md-comment-line.md        '```bash' 'set -o pipefail' '# x | sudo grep -q p' '```'
_ml_put docs/ml-md-grep-c.md              '```bash' 'set -o pipefail' 'x | grep -c p' '```'
_ml_put scripts/ml-split-backslash.sh     'x | \' '  sudo grep -q p f'
_ml_put scripts/ml-split-bar-backslash.sh 'x |\' '  grep -q p f'
_ml_put scripts/ml-split-bar-comment.sh   'x | # filter' '  sudo grep -q p f'
_ml_put scripts/ml-split-continued.sh     'x |' '  sudo -u root \' '  grep -q p f'
printf '%s\r\n' 'x |' '  sudo grep -q p f' > "$ml/scripts/ml-split-crlf.sh"
_ml_put scripts/ml-split-chain3.sh        'x |' 'y |' '  sudo grep -q p f'
_ml_put scripts/ml-split-comment-bar.sh   '# note |' '  sudo grep -q p f'
_ml_put scripts/ml-split-or-or-listed.sh  'x ||' '  sudo grep -q p f' 'y |' '  cat'
_ml_put scripts/ml-split-block-comment.yml 'run: | # keep' '  sudo grep -q p "$f"'
_ml_put scripts/ml-split-js-comment.ts    '// choose a |' '  sudo grep -q p f'
_ml_put scripts/ml-split-js-between.ts    'x |' '// note' '  sudo grep -q p f'
_ml_put A=b.sh                            'x |' '  sudo grep -q p f'
_ml_put "scripts/ml-caf"$'\303\251'".sh"    'x |' '  sudo grep -q p f'
printf 'x | sudo grep -q p \377\n' > "$ml/scripts/ml-nonutf8.sh"
_ml_put docs/ml-md-unclosed-a.md          '```bash' 'set -o pipefail' 'x | sudo grep -q p'
_ml_put docs/ml-md-unclosed-b.md          'plain text that mentions pipefail'
_ml_put docs/ml-md-marker.md              '```bash' 'set -o pipefail' 'x | sudo grep -q p  # sigpipe-demo: intentional' '```'
_ml_put docs/ml-md-closer-info.md         '```bash' 'set -o pipefail' '``` text' 'x | sudo grep -q p' '```'
{ printf '%s\n' '```bash' 'set -o pipefail'; for _i in $(seq 1 45); do echo "echo $_i"; done; printf '%s\n' 'x | sudo grep -q p' '```'; } > "$ml/docs/ml-md-long-run.md"
_ml_put docs/ml-md-pipefail-comment.md    '```bash' '# note: needs pipefail' 'x | sudo grep -q p' '```'
_ml_put docs/ml-md-pipefail-off.md        '```bash' 'set +o pipefail' 'x | sudo grep -q p' '```'
_ml_put knowledge-base/ml-md-kb.md        '```bash' 'set -o pipefail' 'x | sudo grep -q p' '```'
_ml_put scripts/ml-split-cont3.sh        'x |' 'grep \' '-E \' '-q p'
_ml_put scripts/ml-split-eof-cont-a.sh    'x |' '  sudo grep -q p \'
_ml_put scripts/ml-split-eof-cont-b.sh    'sudo grep -q p f'
_ml_put scripts/ml-split-js-stale-a.ts    'x |' '// note' '  sudo grep -q p f'
_ml_put scripts/ml-split-js-stale-b.sh    'echo hi' 'x |' '// note' '  sudo grep -q p f'
_ml_put scripts/ml-split-acc.sh           'x |' '  sudo grep -q p f' 'y |' '  cat'
_ml_put tests/zz-split-eof-cont-last.sh  'x |' '  sudo grep -q p \'   # sorts after every other file of the root: the continuation is pending at the END of the whole run
printf 'x \377| sudo grep -q p\n' > "$ml/scripts/ml-bytes-before-bar.sh"
printf 'x | grep "\377" -q a\n' > "$ml/scripts/ml-bytes-quoted.sh"
printf 'x | # caf\351\n  sudo grep -q p f\n' > "$ml/scripts/ml-split-latin1.sh"
printf 'x |\n  sudo grep "\377" -q a\n' > "$ml/scripts/ml-split-bytes-reader.sh"
printf '%s\n' '```bash' 'set -o pipefail' > "$ml/docs/ml-md-bytes.md"; printf 'x | grep "\377" -q a\n```\n' >> "$ml/docs/ml-md-bytes.md"
printf 'x |\n  sudo grep -q p f\n' > "$ml/scripts/ml-caf"$'\351'"-latin1-name.sh"
_ml_put A=b.md                            '```bash' 'set -o pipefail' 'x | sudo grep -q p' '```'
_ml_put "docs/ml-caf"$'\303\251'".md"       '```bash' 'set -o pipefail' 'x | sudo grep -q p' '```'
_ml_put docs/ml-md-info-opener.md         '```bash title="a b"' 'set -o pipefail' 'x | sudo grep -q p' '```'
ml_out="$(scan_sweep "$ml")"
ml_miss=""; ml_over=""
_ml_want() { local name="$1" path="$2" ln="$3" kind="${4:-}"; grep -q -- "^$path:$ln:" <<<"$ml_out" || ml_miss+=" $name${kind:+/}$kind"; }
_ml_not()  { local name="$1" path="$2"; if [[ ! -f "$ml/${path%%:*}" ]]; then ml_miss+=" $name/nofile"; elif grep -q -- "^$path:" <<<"$ml_out"; then ml_over+=" $name"; fi; }   # a must-not on a file that is not there passes for the wrong reason
_ml_want split-sudo         scripts/ml-split-sudo.sh 1
_ml_want split-line-number  scripts/ml-split-line-number.sh 3
_ml_want split-second-site  scripts/ml-split-second-site.sh 1 first
_ml_want split-second-site  scripts/ml-split-second-site.sh 4 second
_ml_want split-comment-next scripts/ml-split-comment-next.sh 1
_ml_want split-blank-next   scripts/ml-split-blank-next.sh 1
_ml_want split-pipe-amp     scripts/ml-split-pipe-amp.sh 1
_ml_not  split-or-or        scripts/ml-split-or-or.sh
_ml_not  split-block-scalar scripts/ml-split-block-scalar.yml
_ml_not  split-eof          scripts/ml-split-eof-a.sh
_ml_not  split-eof-next-file scripts/ml-split-eof-b.sh
_ml_not  split-lone-bar     scripts/ml-split-lone-bar.yml
_ml_want md-env-i               docs/ml-md-env-i.md 4
_ml_want md-pipefail-after-hit  docs/ml-md-pipefail-after-hit.md 2
_ml_want md-tilde               docs/ml-md-tilde.md 3
_ml_want md-indented            docs/ml-md-indented.md 4
_ml_want md-long-fence          docs/ml-md-long-fence.md 3 inside
_ml_want md-long-fence          docs/ml-md-long-fence.md 5 after-short-fence
_ml_want md-tilde-mismatch      docs/ml-md-tilde-mismatch.md 4
_ml_want md-unclosed-fence      docs/ml-md-unclosed-fence.md 3
_ml_want md-crlf                docs/ml-md-crlf.md 3
_ml_not  md-long-fence-after    docs/ml-md-long-fence.md:7
_ml_not  md-crlf-after          docs/ml-md-crlf.md:5
_ml_not  md-pipefail-leak       docs/ml-md-pipefail-leak.md
_ml_not  md-pipefail-other-fence docs/ml-md-pipefail-other-fence.md
_ml_not  md-no-pipefail         docs/ml-md-no-pipefail.md
_ml_not  md-prose               docs/ml-md-prose.md
_ml_not  md-comment-line        docs/ml-md-comment-line.md
_ml_not  md-grep-c              docs/ml-md-grep-c.md
_ml_want split-backslash        scripts/ml-split-backslash.sh 1
_ml_want split-bar-backslash    scripts/ml-split-bar-backslash.sh 1
_ml_want split-bar-comment      scripts/ml-split-bar-comment.sh 1
_ml_want split-js-between       scripts/ml-split-js-between.ts 1
_ml_want split-continued        scripts/ml-split-continued.sh 1
_ml_want split-crlf             scripts/ml-split-crlf.sh 1
_ml_want split-chain3           scripts/ml-split-chain3.sh 2
_ml_want split-assign-name      A=b.sh 1
_ml_want split-nonascii-name    "scripts/ml-caf"$'\303\251'".sh" 1
_ml_want split-nonutf8          scripts/ml-nonutf8.sh 1
_ml_not  split-comment-bar      scripts/ml-split-comment-bar.sh
_ml_not  split-or-or-listed     scripts/ml-split-or-or-listed.sh:1
_ml_not  split-block-comment    scripts/ml-split-block-comment.yml
_ml_not  split-js-comment       scripts/ml-split-js-comment.ts
_ml_want md-unclosed-a          docs/ml-md-unclosed-a.md 3
_ml_not  md-unclosed-neighbor   docs/ml-md-unclosed-b.md
_ml_want md-marker              docs/ml-md-marker.md 3
_ml_want md-closer-info         docs/ml-md-closer-info.md 4
_ml_want md-long-run            docs/ml-md-long-run.md 48
_ml_want md-fp-pipefail-comment docs/ml-md-pipefail-comment.md 3
_ml_want md-fp-pipefail-off     docs/ml-md-pipefail-off.md 3
_ml_not  md-kb-excluded         knowledge-base/ml-md-kb.md
_ml_want split-cont3            scripts/ml-split-cont3.sh 1
_ml_want split-eof-cont         scripts/ml-split-eof-cont-a.sh 1
_ml_not  split-eof-cont-next    scripts/ml-split-eof-cont-b.sh
_ml_want split-js-stale-a       scripts/ml-split-js-stale-a.ts 1
_ml_not  split-js-stale-b       scripts/ml-split-js-stale-b.sh
_ml_want split-acc              scripts/ml-split-acc.sh 1
_ml_want split-eof-cont-last    tests/zz-split-eof-cont-last.sh 1
_ml_not  split-acc-reset        scripts/ml-split-acc.sh:3
_ml_want bytes-before-bar       scripts/ml-bytes-before-bar.sh 1
_ml_want bytes-quoted           scripts/ml-bytes-quoted.sh 1
_ml_want split-latin1           scripts/ml-split-latin1.sh 1
_ml_want split-bytes-reader     scripts/ml-split-bytes-reader.sh 1
_ml_want md-bytes               docs/ml-md-bytes.md 3
_ml_want split-latin1-name      "scripts/ml-caf"$'\351'"-latin1-name.sh" 1
_ml_want md-root-assign         A=b.md 3
_ml_want md-nonascii-name       "docs/ml-caf"$'\303\251'".md" 3
_ml_want md-info-opener         docs/ml-md-info-opener.md 3
_ml_pick() { # <split|md> <case names...> -> the names of that half, routed by the split- name prefix, each with a leading space
  local half="$1" w out=""; shift
  for w in "$@"; do
    case "$w" in
      split-*) if [[ "$half" == split ]]; then out+=" $w"; fi ;;
      *) if [[ "$half" == md ]]; then out+=" $w"; fi ;;
    esac
  done
  printf '%s' "$out"
}
# shellcheck disable=SC2086  # the word lists are space-separated case names, split on purpose
_ml_report() { # <miss words> <over words> -> one line per non-empty half; the four checks below are these four lines
  local miss="$1" over="$2" w
  w="$(_ml_pick split $miss)"; if [[ -n "$w" ]]; then printf '%s\n' "split-must-report: the sweep did not report the bar's line for:$w (a pipe that ends a line is read together with the next code line; the reported line is the bar's; a name ending /nofile is a fixture that was not written)"; fi
  w="$(_ml_pick split $over)"; if [[ -n "$w" ]]; then printf '%s\n' "split-must-not: the sweep reported a join it must not make:$w (a logical OR, a YAML block-scalar indicator, a bar with nothing after it)"; fi
  w="$(_ml_pick md $miss)"; if [[ -n "$w" ]]; then printf '%s\n' "md-must-report: the sweep did not report a fenced early-exit pipe in:$w (a fence that holds pipefail is code the executing shell reads under it)"; fi
  w="$(_ml_pick md $over)"; if [[ -n "$w" ]]; then printf '%s\n' "md-must-not: the sweep reported a line it must not:$w (prose, a comment line, a fence without pipefail, pipefail in a different fence, a reader that drains)"; fi
}
# The dispatch above is the part of this block that decides whether a case can fail at all: pin how many calls there are (a deleted call is a case that can
# no longer fail), drive the two recorders, the router and the report on a synthetic scan, and read them back.
ML_WANT_CALLS=46; ML_NOT_CALLS=22   # pinned: the number of ^_ml_want and ^_ml_not lines above
ml_nw=$(grep -cE '^_ml_want ' "$_self" || true)
ml_nn=$(grep -cE '^_ml_not ' "$_self" || true)
ml_ctl_root="$probe/ctlroot"; mkdir -p "$ml_ctl_root/a" && : > "$ml_ctl_root/a/x.sh"
ml_ctl="$( ml="$ml_ctl_root"; ml_out=$'a/x.sh:1:t'; ml_miss=""; ml_over=""; _ml_want c1 a/x.sh 1; _ml_want c2 a/y.sh 1; _ml_want c5 a/x.sh 2; _ml_not c3 a/x.sh; _ml_not c4 a/y.sh; _ml_not c6 a/x.sh:2; echo "$ml_miss|$ml_over" )"
ml_route="$(_ml_pick split split-a md-b split-c):$(_ml_pick md split-a md-b split-c)"
ml_rep_ctl="$(_ml_report ' split-a md-b' ' split-c md-d')"
ml_rep_bad=""
_ml_names=(split-must-report md-must-report split-must-not md-must-not); _ml_words=(split-a md-b split-c md-d)
for _i in 0 1 2 3; do
  _l="$(grep -a "^${_ml_names[_i]}:" <<<"$ml_rep_ctl" || true)"
  [[ "$_l" == *" ${_ml_words[_i]} "* || "$_l" == *" ${_ml_words[_i]}" ]] || ml_rep_bad+=" ${_ml_names[_i]}(word)"
  [[ "$_l" != *"${_ml_words[(_i + 1) % 4]}"* ]] || ml_rep_bad+=" ${_ml_names[_i]}(leak)"
done
ml_rep="$(_ml_report "$ml_miss" "$ml_over")"
ml_wire_a=$(grep -cE '^ml_rep="\$\(_ml_report "\$ml_miss" "\$ml_over"\)"$' "$_self" || true)   # the two statements that turn the report into a failure, pinned as text at column 0
ml_wire_b=$(grep -cE '^\[\[ -z "\$ml_rep" \]\] \\$' "$_self" || true)
[[ "$ml_wire_a" == 1 && "$ml_wire_b" == 1 && "$ml_nw" == "$ML_WANT_CALLS" && "$ml_nn" == "$ML_NOT_CALLS" && "$ml_ctl" == " c2 c5 c4/nofile| c3" && "$ml_route" == " split-a split-c: md-b" && -z "$ml_rep_bad" ]] \
  || sweep_probe_fail+=("ml-dispatch: the fixture checks above have ${ml_nw:-<err>} _ml_want and ${ml_nn:-<err>} _ml_not calls (pinned at $ML_WANT_CALLS and $ML_NOT_CALLS: a deleted call is a case that can no longer fail; add or remove a case and its pin together), the recorders read [${ml_ctl:-<err>}] on a synthetic scan (want [ c2 c5 c4/nofile| c3]: a wrong line, a missing file and an over-read), the router [${ml_route:-<err>}] (want [ split-a split-c: md-b]), the report mis-routed:${ml_rep_bad:- none}, the report capture and failure statements found ${ml_wire_a:-<err>}/${ml_wire_b:-<err>} times (want 1 and 1)")
[[ -z "$ml_rep" ]] \
  || sweep_probe_fail+=("fixture-checks (multi-line passes):"$'\n'"$(sed 's/^/    /' <<<"$ml_rep")")
ml_split_n=$(grep -c '^scripts/ml-split-' <<<"$ml_out" || true)
ml_md_n=$(grep -c '^docs/ml-md-' <<<"$ml_out" || true)
[[ "$ml_split_n" -gt 0 && "$ml_md_n" -gt 0 ]] \
  || sweep_probe_fail+=("sweep-wiring-multiline: scan_sweep reported ${ml_split_n:-<err>} split-pass lines and ${ml_md_n:-<err>} markdown-pass lines on a root built to produce both (want both above 0: the passes are not wired into the sweep)")

# Guard 3: one planted violation per extension, read through the same scan_sweep, so the pathspec and the extension list cannot disagree unseen.
ew="$probe/extroot"; mkdir -p "$ew" && cp -R "$okroot/." "$ew/"
for _e in ${SWEEP_EXTS[@]+"${SWEEP_EXTS[@]}"}; do
  printf '%s\n' 'echo "$x" | grep -q p' > "$ew/scripts/witness-$_e.$_e"
  printf '%s\n' 'x |' '  sudo grep -q p f' > "$ew/scripts/witness-split-$_e.$_e"   # the split pass has to list and read every extension too
done
ew_out="$(scan_sweep "$ew")"
ew_swept=$(sed -n '1s/^SWEPT: \([0-9]*\) files$/\1/p' <<<"$ew_out")
ew_miss=""
for _e in ${SWEEP_EXTS[@]+"${SWEEP_EXTS[@]}"}; do
  grep -q -- "^scripts/witness-$_e\\.$_e:" <<<"$ew_out" || ew_miss+=" $_e"
  grep -q -- "^scripts/witness-split-$_e\\.$_e:1:" <<<"$ew_out" || ew_miss+=" split-$_e"
done
[[ "${#SWEEP_EXTS[@]}" -gt 0 && "${ew_swept:-0}" == $(( SWEEP_CANARY_COUNT + 2 * ${#SWEEP_EXTS[@]} )) && -z "$ew_miss" ]] \
  || sweep_probe_fail+=("ext-witness: the sweep read ${ew_swept:-<err>} files of a root holding $SWEEP_CANARY_COUNT canaries and ${#SWEEP_EXTS[@]} planted single-line plus ${#SWEEP_EXTS[@]} planted split-pair files and did not report a planted violation of:${ew_miss:- none} (an extension missing from the pathspec is a file type nobody reads; read 0 files means the list is empty)")
[[ "${#SWEEP_EXTS[@]}" == "$SWEEP_EXT_COUNT" ]] \
  || sweep_probe_fail+=("ext-count: SWEEP_EXTS holds ${#SWEEP_EXTS[@]} extensions, pinned at $SWEEP_EXT_COUNT — the list changed: a dropped extension leaves SWEEP_PATHSPEC and the witness together (that file type is no longer read), an added one is read but unpinned; if you changed the list on purpose, edit SWEEP_EXT_COUNT, SWEEP_EXT_EXPECTED, SWEEP_COMMENT_STYLES and the two comment lists in the same commit")
[[ "${SWEEP_EXTS[*]}" == "$SWEEP_EXT_EXPECTED" ]] \
  || sweep_probe_fail+=("ext-expected: SWEEP_EXTS is [${SWEEP_EXTS[*]}], the separately typed list is [$SWEEP_EXT_EXPECTED]")
(( SWEEP_FLOOR >= SWEEP_FLOOR_MIN )) \
  || sweep_probe_fail+=("floor-lower-bound: SWEEP_FLOOR is $SWEEP_FLOOR, below the literal SWEEP_FLOOR_MIN of $SWEEP_FLOOR_MIN — a floor far under the population stops guarding truncation; raise it, and lower the literal only in a reviewed edit")
fl_rc=0; fl_out="$( ( SWEEP_DEFERRALS=(); sweep_main "$okroot" "$SWEEP_FLOOR" 0 0 0 ) 2>&1 )" || fl_rc=$?
[[ "$fl_rc" == 1 && "$fl_out" == *"below SWEEP_FLOOR $SWEEP_FLOOR"* ]] \
  || sweep_probe_fail+=("floor-truncated: a $SWEEP_CANARY_COUNT-file population under the real floor gave rc ${fl_rc:-<err>} and [${fl_out:0:80}] (want rc 1 and a 'below SWEEP_FLOOR $SWEEP_FLOOR' message)")
# The three multi-line floors: each has a literal MIN beside it, and each reads UNRESOLVED (rc 3) naming its own variable when its pass prints too little. The
# control is the same root with the floor at 0, which reads rc 1 (the planted hits), so rc 3 is the floor and not a broken root.
(( SWEEP_MD_FLOOR >= SWEEP_MD_FLOOR_MIN && SWEEP_MD_FENCE_FLOOR >= SWEEP_MD_FENCE_FLOOR_MIN && SWEEP_SPLIT_FLOOR >= SWEEP_SPLIT_FLOOR_MIN )) \
  || sweep_probe_fail+=("md-floor-lower-bound: SWEEP_MD_FLOOR $SWEEP_MD_FLOOR/$SWEEP_MD_FLOOR_MIN, SWEEP_MD_FENCE_FLOOR $SWEEP_MD_FENCE_FLOOR/$SWEEP_MD_FENCE_FLOOR_MIN or SWEEP_SPLIT_FLOOR $SWEEP_SPLIT_FLOOR/$SWEEP_SPLIT_FLOOR_MIN is below its literal minimum — a floor far under the measured population stops guarding truncation; raise it, and lower the literal only in a reviewed edit")
mf_ctl=0; ( SWEEP_DEFERRALS=(); sweep_main "$ml" 1 0 0 0 >/dev/null 2>&1 ) || mf_ctl=$?
mf_md=0;  mf_md_out="$( ( SWEEP_DEFERRALS=(); sweep_main "$okroot" 1 "$SWEEP_MD_FLOOR" 0 0 ) 2>&1 )" || mf_md=$?
mf_fn=0;  mf_fn_out="$( ( SWEEP_DEFERRALS=(); sweep_main "$ml" 1 0 "$SWEEP_MD_FENCE_FLOOR" 0 ) 2>&1 )" || mf_fn=$?
mf_sp=0;  mf_sp_out="$( ( SWEEP_DEFERRALS=(); sweep_main "$ml" 1 0 0 "$SWEEP_SPLIT_FLOOR" ) 2>&1 )" || mf_sp=$?
[[ "$mf_ctl" == 1 && "$mf_md" == 3 && "$mf_md_out" == *"below SWEEP_MD_FLOOR $SWEEP_MD_FLOOR"* && "$mf_fn" == 3 && "$mf_fn_out" == *"below SWEEP_MD_FENCE_FLOOR $SWEEP_MD_FENCE_FLOOR"* \
      && "$mf_sp" == 3 && "$mf_sp_out" == *"below SWEEP_SPLIT_FLOOR $SWEEP_SPLIT_FLOOR"* ]] \
  || sweep_probe_fail+=("md-floor-truncated: the multi-line floors on scratch roots gave rc ${mf_ctl:-<err>} with every floor at 0 (want 1: the planted hits), then ${mf_md:-<err>}/${mf_fn:-<err>}/${mf_sp:-<err>} for the markdown-file, fence-line and split-join floors (want 3/3/3, each message naming its own SWEEP_ variable)")
# Each floor must read ITS OWN counter. On the multi-line fixture root the three counters are pairwise distinct (asserted); a floor set to a counter's exact value
# passes (rc 1: the planted hits), the same floor plus one reads UNRESOLVED naming that floor, so a floor wired to another pass's counter cannot hide.
ml_c_sj=$(export LC_ALL=C; scan_split "$ml" | grep -acE '^[^:]+:[0-9]+: \| ' || true)
ml_c_fl=$(export LC_ALL=C; scan_md "$ml" | grep -acE '^[^:]+:[0-9]+:' || true)
ml_c_md=$(export LC_ALL=C; scan_md "$ml" | sed -n 's/^MDSWEPT: \([0-9]*\) files$/\1/p')
mx=""
if [[ "$ml_c_sj" != "$ml_c_fl" && "$ml_c_sj" != "$ml_c_md" && "$ml_c_fl" != "$ml_c_md" && "${ml_c_sj:-0}" -gt 0 && "${ml_c_fl:-0}" -gt 0 && "${ml_c_md:-0}" -gt 0 ]]; then
  for _k in 1 2 3; do
    case "$_k" in 1) _v=$ml_c_md; _want="below SWEEP_MD_FLOOR" ;; 2) _v=$ml_c_fl; _want="below SWEEP_MD_FENCE_FLOOR" ;; *) _v=$ml_c_sj; _want="below SWEEP_SPLIT_FLOOR" ;; esac
    _a=(0 0 0); _a[_k - 1]=$_v
    _r=0; ( SWEEP_DEFERRALS=(); sweep_main "$ml" 1 "${_a[0]}" "${_a[1]}" "${_a[2]}" >/dev/null 2>&1 ) || _r=$?
    [[ "$_r" == 1 ]] || mx+=" exact$_k(rc $_r, want 1)"
    _a[_k - 1]=$(( _v + 1 ))
    _r=0; _o="$( ( SWEEP_DEFERRALS=(); sweep_main "$ml" 1 "${_a[0]}" "${_a[1]}" "${_a[2]}" ) 2>&1 )" || _r=$?
    [[ "$_r" == 3 && "$_o" == *"$_want"* ]] || mx+=" plus1-$_k(rc $_r, want 3 and '$_want')"
  done
else
  mx=" counters not pairwise distinct and positive (joins ${ml_c_sj:-<err>}, fence lines ${ml_c_fl:-<err>}, markdown files ${ml_c_md:-<err>})"
fi
[[ -z "$mx" ]] \
  || sweep_probe_fail+=("md-floor-exact: on the multi-line root a floor at its own counter's value must pass and one above it must read UNRESOLVED naming that floor:$mx")

# The knowledge-base exclusion is path-segment exact: an archive/ directory at any depth is out, a directory that merely contains the word is not.
kb="$probe/kbroot"; mkdir -p "$kb" && cp -R "$okroot/." "$kb/"
_kb_put() { mkdir -p "$(dirname "$kb/$1")"; printf '%s\n' 'echo "$x" | grep -q p' > "$kb/$1"; }
_kb_put knowledge-base/project/specs/feat-x/bootstrap.sh
_kb_put knowledge-base/project/specs/archive/20260101-x/y.sh
_kb_put knowledge-base/x/archived-notes/y.sh
_kb_put knowledge-base/a/b/archive/c.sh
kb_out="$(scan_sweep "$kb")"
kb_miss=""; kb_over=""
grep -q -- '^knowledge-base/project/specs/feat-x/bootstrap\.sh:' <<<"$kb_out" || kb_miss+=" kb-witness"
grep -q -- '^knowledge-base/x/archived-notes/y\.sh:' <<<"$kb_out" || kb_miss+=" kb-archive-lookalike"
grep -q -- '^knowledge-base/project/specs/archive/' <<<"$kb_out" && kb_over+=" kb-archive-must-not"
grep -q -- '^knowledge-base/a/b/archive/' <<<"$kb_out" && kb_over+=" kb-archive-nested-must-not"
[[ -z "$kb_miss" && -z "$kb_over" ]] \
  || sweep_probe_fail+=("kb-population: the sweep did not read:${kb_miss:- none}; it read an archived record it must not:${kb_over:- none} (SWEEP_PATHSPEC reads knowledge-base code files outside an archive/ directory; a name that only contains archive is not an archive, and its ':(exclude,glob)knowledge-base/**/archive/**' entry is the one that decides)")

# The comment filter is per language: a JS-family comment is not a shell comment and a shell case arm is not a JS comment.
cm="$probe/cmroot"; mkdir -p "$cm" && cp -R "$okroot/." "$cm/"
_cm_put() { mkdir -p "$(dirname "$cm/$1")"; printf '%s\n' "$2" > "$cm/$1"; }
_cm_put scripts/cm-ts-slash-comment.ts '// echo "$x" | grep -q p'
_cm_put scripts/cm-ts-jsdoc-star.ts ' * echo "$x" | grep -q p'
_cm_put scripts/cm-ts-block-comment.ts '/* echo "$x" | grep -q p */'
_cm_put scripts/cm-py-hash-comment.py '# echo "$x" | grep -q p'
_cm_put scripts/cm-ts-hash-line.ts '# echo "$x" | grep -q p'
_cm_put scripts/cm-py-slash-line.py '// echo "$x" | grep -q p'
_cm_put scripts/cm-sh-case-arm.sh '  *) echo "$x" | grep -q p ;;'
_cm_put scripts/cm-ts-star-paren.ts ' *) echo "$x" | grep -q p ;;'
_cm_put scripts/cm-tf-cron-star.tf '*/5 * * * * root echo "$x" | grep -q p'
_cm_put scripts/cm-tf-block-comment.tf '/* echo "$x" | grep -q p */'
cm_out="$(scan_sweep "$cm")"
cm_miss=""; cm_over=""
for _c in ts-hash-line.ts py-slash-line.py sh-case-arm.sh ts-star-paren.ts tf-cron-star.tf; do grep -q -- "^scripts/cm-$_c:" <<<"$cm_out" || cm_miss+=" ${_c%.*}"; done
for _c in ts-slash-comment.ts ts-jsdoc-star.ts ts-block-comment.ts py-hash-comment.py tf-block-comment.tf; do if grep -q -- "^scripts/cm-$_c:" <<<"$cm_out"; then cm_over+=" ${_c%.*}"; fi; done
[[ -z "$cm_miss" && -z "$cm_over" ]] \
  || sweep_probe_fail+=("comment-filter: code lines the filter dropped:${cm_miss:- none}; comment lines it kept:${cm_over:- none} (a # line is code in a .ts file, a // line is code in a .py file, a * case arm is code in a .sh or .ts file)")
# The comment style of EVERY swept extension, typed out once more beside the two lists: each extension gets a # line and a // line, and the table says which of
# the two is a comment there (dropped) and which is code (reported). A list that gained or lost an extension, or a regex that stopped reading one, disagrees with it.
SWEEP_COMMENT_STYLES='sh:# bash:# bats:# yml:# yaml:# tf:#// template:# py:# js://* ts://* tsx://* mjs://* cjs://*'   # # = hash comment, // = slash and block-open comment, a trailing * = a leading star line too (JSDoc)
cs="$probe/csroot"; mkdir -p "$cs" && cp -R "$okroot/." "$cs/"
for _s in $SWEEP_COMMENT_STYLES; do
  printf '%s\n' '# echo "$x" | grep -q p' > "$cs/scripts/cs-hash-${_s%%:*}.${_s%%:*}"
  printf '%s\n' '// echo "$x" | grep -q p' > "$cs/scripts/cs-slash-${_s%%:*}.${_s%%:*}"
  printf '%s\n' '* echo "$x" | grep -q p' > "$cs/scripts/cs-star-${_s%%:*}.${_s%%:*}"
  printf '%s\n' 'x |' '// note' '  sudo grep -q p f' > "$cs/scripts/cs-split-${_s%%:*}.${_s%%:*}"
  printf '%s\n' 'x |' '* note' '  sudo grep -q p f' > "$cs/scripts/cs-splitstar-${_s%%:*}.${_s%%:*}"
done
cs_out="$(scan_sweep "$cs")"
cs_bad=""; cs_lists=""; cs_n=0
_cs_h=" ${SWEEP_HASH_EXTS[*]} "; _cs_s=" ${SWEEP_SLASH_EXTS[*]} "; _cs_b=" ${SWEEP_CBLOCK_EXTS[*]} "
for _s in $SWEEP_COMMENT_STYLES; do
  _e="${_s%%:*}"; _st="${_s#*:}"; cs_n=$((cs_n + 1))
  for _kind in hash slash star split splitstar; do
    case "$_kind" in
      hash) if [[ "$_st" == *'#'* ]]; then _want=dropped; else _want=reported; fi ;;
      slash) if [[ "$_st" == *//* ]]; then _want=dropped; else _want=reported; fi ;;
      star) if [[ "$_st" == *'*' ]]; then _want=dropped; else _want=reported; fi ;;
      splitstar) if [[ "$_st" == *'*' ]]; then _want=reported; else _want=none; fi ;;   # a star line between a bar and its reader is a comment only where the style says so (JSDoc), as in the filter
      split) if [[ "$_st" == *//* ]]; then _want=reported; else _want=none; fi ;;   # a // line between a bar and its reader is a comment (skipped, the join is made) only where the style says so
    esac
    if grep -aq -- "^scripts/cs-$_kind-$_e\\.$_e:" <<<"$cs_out"; then _got=reported; else _got=none; fi
    if [[ "$_kind" != split && "$_kind" != splitstar && "$_got" == none ]]; then _got=dropped; fi
    [[ "$_got" == "$_want" ]] || cs_bad+=" $_kind-$_e(want $_want)"
  done
  _der=""
  if [[ "$_cs_h" == *" $_e "* ]]; then _der+='#'; fi
  if [[ "$_cs_s" == *" $_e "* ]]; then _der+='//*'; elif [[ "$_cs_b" == *" $_e "* ]]; then _der+='//'; fi
  [[ "$_der" == "$_st" ]] || cs_lists+=" $_e(table '$_st', lists '$_der')"
done
for _e in ${SWEEP_HASH_EXTS[@]+"${SWEEP_HASH_EXTS[@]}"} ${SWEEP_SLASH_EXTS[@]+"${SWEEP_SLASH_EXTS[@]}"} ${SWEEP_CBLOCK_EXTS[@]+"${SWEEP_CBLOCK_EXTS[@]}"}; do
  [[ " $SWEEP_COMMENT_STYLES " == *" $_e:"* || "$_e" == md ]] || cs_lists+=" $_e(in a list, not in the table)"
done
if [[ " ${SWEEP_SLASH_EXTS[*]} ${SWEEP_CBLOCK_EXTS[*]} " == *" md "* ]]; then cs_lists+=" md(markdown is read through its fences and takes the hash comment only)"; fi
[[ "$cs_n" == "${#SWEEP_EXTS[@]}" && -z "$cs_bad" && -z "$cs_lists" ]] \
  || sweep_probe_fail+=("comment-style-lists: ${cs_n:-<err>} extensions in the style table (want ${#SWEEP_EXTS[@]}, one per SWEEP_EXTS member); lines read the wrong way:${cs_bad:- none}; lists that disagree with the table:${cs_lists:- none} (SWEEP_HASH_EXTS, SWEEP_SLASH_EXTS and SWEEP_CBLOCK_EXTS drive _strip_comments; a new extension needs its comment style in both places)")

# The marker pin: every marked line in the swept files (the guard and every knowledge-base archive/ directory excluded) is pinned per file. The derivation
# goes through sweep_git_grep, so its population is exactly the swept files. A new marker needs the reason in the PR body and one row here. Markdown is not
# swept line by line and scan_md never honours the marker (md-marker in the multi-line fixtures), so a fence cannot carry an unpinned exemption.
read -r -d '' SWEEP_MARKER_PIN_ROWS <<'EOF' || true
.claude/hooks/iac-plan-write-guard.test.sh:1
apps/web-platform/infra/cron-egress-self-heal.test.sh:3
apps/web-platform/infra/registry-luks-launch-gate.test.sh:1
apps/web-platform/infra/registry-luks.test.sh:2
apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh:3
apps/web-platform/infra/supabase-advisor/scan-workflow-mutation.test.sh:4
apps/web-platform/infra/workspaces-luks-freeze.test.sh:2
apps/web-platform/infra/workspaces-luks-verify-root-mtime.test.sh:1
apps/web-platform/test/infra/ghcr-blocked-alert.test.sh:1
plugins/soleur/test/worktree-manager-porcelain-sigpipe.test.sh:1
tests/scripts/test-git-data-birth-readiness-gate.sh:4
tests/scripts/test-sentry-full-root-apply.sh:2
EOF
SWEEP_MARKER_PIN="${SWEEP_MARKER_PIN_ROWS%$'\n'}"   # path:count, sorted bytewise (LC_ALL=C), one row per line so a change is a one-line diff
mp_rc=0; mp_raw="$(sweep_git_grep . -cE -e 'sigpipe-demo' --and -e "$ALLOW_MARKER")" || mp_rc=$?   # the literal first: 4.8 s CPU became 0.5 s, the same rows
mp_now="$(LC_ALL=C sort <<<"$mp_raw")"
[[ "$mp_rc" -le 1 && "$mp_now" == "$SWEEP_MARKER_PIN" ]] \
  || sweep_probe_fail+=("marker-pin: the per-file counts of '# sigpipe-demo: intentional' lines differ from SWEEP_MARKER_PIN (git grep rc ${mp_rc:-<err>}). '<' is pinned and absent now, '>' is present now and unpinned:"$'\n'"$(diff <(printf '%s\n' "$SWEEP_MARKER_PIN") <(printf '%s\n' "$mp_now") | sed 's/^/    /' || true)"$'\n'"    To accept a NEW marker: put its reason in the PR body and paste the '>' row (path:count, in this sorted order) into the SWEEP_MARKER_PIN_ROWS block above this check; a marker in a markdown fence is never honoured, so it cannot be pinned")

# Self-sweep (G3-10): the real run read the repository, including this change's own spec dir; a fixture or a reader shape written as text in a script
# there would be a hit. Zero undeferred hits under the specs tree, by name, so the failure says where the shape came from.
# The scan must be the real run's (it starts with its SWEPT line): an unset or empty SWEEP_LAST_SCAN counts zero hits and would pass.
_spec_dir_state() { # <scan> -> "noscan", or "hits:<n>" (the count of reader-shaped lines under knowledge-base/project/specs/)
  local scan="$1" n
  [[ "$scan" == SWEPT:* && "$scan" == *$'\nFENCELINES: '* ]] || { echo noscan; return 0; }
  n=$(grep -ac '^knowledge-base/project/specs/[^:]*:[0-9]*:' <<<"$scan" || true)
  echo "hits:$n"
}
sd_state="$(_spec_dir_state "${SWEEP_LAST_SCAN:-}")"
sd_ctl="$(_spec_dir_state $'SWEPT: 3 files\nMDSWEPT: 0 files\nSPLITJOINS: 0\nFENCELINES: 0\nknowledge-base/project/specs/f/a.sh:1:t\nscripts/b.sh:2:t')|$(_spec_dir_state '')|$(_spec_dir_state 'SWEPT: 1 files')|$(_spec_dir_state $'SWEPT: 1 files\nMDSWEPT: 0 files\nSPLITJOINS: 0\nFENCELINES: 0')"
sd_msg="the real sweep reported ${sd_state#hits:} reader-shaped line(s) under knowledge-base/project/specs/ (a spec-dir script holds a literal early-exit reader: keep such text in .txt data files and build mutants with printf)"
[[ "$sd_state" != noscan ]] || sd_msg="this check ran with no complete scan to read (SWEEP_LAST_SCAN is empty or cut, so the real sweep recorded none and zero hits would mean nothing)"
[[ "$sd_state" == hits:0 && "$sd_ctl" == "hits:1|noscan|noscan|hits:0" ]] \
  || sweep_probe_fail+=("spec-dir-zero: $sd_msg (the check's own control read [$sd_ctl], want [hits:1|noscan|noscan|hits:0])")

# What a line regex deliberately does NOT match (documented residuals) and the one known false positive, pinned as literal counts so a
# widening or a regression shows up as a changed number and a header edit rather than as silent drift.
cat > "$probe/residual-v2.sh" <<'EOF'
x | head -1
x | awk '/p/ { exit }'
x | sed 1q
x | read y
EOF
cat > "$probe/fp-v2.sh" <<'EOF'
x | grep -c p -eq
x | xargs echo grep -q p
EOF
res_hits=$(grep -cE -- "$PATTERN_V2" "$probe/residual-v2.sh" || true)
fp_hits=$(grep -cE -- "$PATTERN_V2" "$probe/fp-v2.sh" || true)
[[ "$res_hits" == 0 && "$fp_hits" == 2 ]] || sweep_probe_fail+=("residual-v2: documented residuals (head, awk exit, sed q, read) matched ${res_hits:-<err>} (want 0), the two documented false positives (grep -c p -eq, xargs echo grep) matched ${fp_hits:-<err>} (want 2)")

# Test-shaped canaries. The root canaries (SWEEP_CANARIES) are satisfied by ANY swept file under a root, so an ignore glob or a pathspec
# exclusion that hides only the test files (`*.test.sh`) leaves a root canary green while the sweep stops reading exactly the files this
# guard exists for. One stable test file per representative test-bearing location (nine, not all of them: the listing of tracked-but-ignored
# files below covers every ignore rule, and these cover a pathspec exclusion) is named here and must appear in the sweep's own population (the same
# listing scan_sweep derives, through the same sweep_git_grep, over the real tree). Pick long-lived suites of load-bearing components; if one is
# renamed, edit this list, never the sweep. They are NOT added to SWEEP_CANARIES: that loop also runs on every scratch-root fixture above.
SWEEP_TEST_CANARIES=('.claude/hooks/guardrails.test.sh' 'plugins/soleur/test/deploy-arm.test.sh' 'plugins/soleur/scripts/emit-decision.test.sh' 'plugins/soleur/skills/community/test/community-argv.test.sh' 'apps/web-platform/infra/ci-deploy.test.sh' 'apps/web-platform/scripts/anthropic-key-distinctness.test.sh' 'apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh' 'apps/cla-evidence/scripts/inspect.test.sh' 'scripts/actions-queue-health.test.sh' 'apps/web-platform/test/scripts/run-migrations-unmerged-gate.test.ts')
SWEEP_TEST_CANARY_COUNT=10   # pinned beside the array: a canary deleted from the array alone must not pass
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
tc_hidden="$(git -c core.excludesFile=/dev/null ls-files -ci --exclude-standard -- "${SWEEP_PATHSPEC[@]}" "${SWEEP_MD_PATHSPEC[@]}")" || tc_hidden="<ls-files failed>"
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
# THE PRODUCER SIDE (S7b, #9217 Arm P; widened by S7c). The consumer side above bans `| grep -q`; this half covers the OTHER end of the same
# pipe: a non-test script feeds text into a verb, and a test STUB for that verb exits without reading stdin, so the writer dies
# (SIGPIPE 141, or EPIPE where CI ignores SIGPIPE). Three guards share one table, PRODUCER_JOIN, whose evidence is
# knowledge-base/project/specs/archive/20261012-033826-feat-one-shot-grep-q-pipe-guard-s7b-producer-join/evidence.md (S7b) and
# knowledge-base/project/specs/archive/20261014-132045-feat-one-shot-grep-q-pipe-guard-s7c-derivation-recall/evidence.md (S7c: the per-pair reach table and the arm increments).
#   1. SET IDENTITY over what the derivation can see. pj_join_pairs derives every (test file, verb) pair where the test file names a non-test
#      file (.sh .bash .yml .yaml .tf .tftpl .template .service .tmpl, one list) that pipes into the verb under pipefail with its status observed,
#      and the test file (or one sourced file) stubs that verb. Pipefail is the file's own token, `shell: bash` in a workflow, or, for a library,
#      the token of a file that sources it (a subprocess does not inherit the option, so the owning test file's token is not read). A site is read
#      on a LOGICAL line (a trailing backslash or a trailing single bar outside quotes joins the next code line, a YAML block-scalar indicator
#      does not; a joined line keeps its first 8192 bytes and the text joined after them, see Long lines under STATED LIMITS) and is either the old printf/echo/cat
#      producer or ANY stage before a single bar outside quotes (a case-pattern alternation is not a pipe); the verb may sit behind timeout, env,
#      command (not -v or -V), nice, stdbuf, exec, builtin or VAR=x; the string of a double-quoted annotation echo is dropped up to its FIRST double
#      quote (a pipe before the echo or after that quote is read; what a `$( )` inside the string does is under Annotations in STATED LIMITS). A stub is a function, a file written to .../VERB (also `> "$d/jq"; chmod`),
#      a stub-helper call naming the verb as any argument, or a file written inside a `for` loop over the verb names, in the test file or in one
#      sourced file. Every derived pair has exactly one row and every row still derives. PJ_TRIPLES pins the (test file, verb, producer file)
#      count, so a new producer of an already-listed pair is a deliberate edit and not a silent pass; an unlisted pair names its producer file(s).
#      An `exempt` row starts with one word of a closed vocabulary (PJ_VOCAB, pinned as a literal list of nine words); `fenced` is the one word that carries a tracker link
#      and must read `fenced #<digits> <reason>`, and the number of fenced rows is pinned (2).
#   2. A `drains` row's stub reads stdin early: in each of its N stub definitions a drain keyed on the flag token sits in the opener line or the
#      next PJ_DRAIN_WINDOW code lines of the SAME definition, with no bare exit or return before it. The extent of a stub ends at the next stub
#      opener of ANY verb (function, helper call or heredoc writer), its heredoc terminator or its closing brace; a one-line logging write does not
#      end it. This is a four-line TEXT window; it does not prove that the arm the producer reaches reads. A drain behind a tty test that reads only
#      on a terminal, behind a constant short-circuit, backgrounded, with a heredoc or an input redirect, or `cat FILE` as its whole operand, is not a drain; several
#      spellings that read a file or stop at once ARE credited all the same (Drain check, under STATED LIMITS).
#   3. The hazard is real and the checker can see a vacuous stub (the dynamic control below), and every verdict this block prints is driven by a
#      fixture that must make it print (a verdict neutered to a no-op turns the probe red).
# STATED LIMITS (S7c state, measured at the fix-round-C head; counts rot, re-measure before quoting). The derivation is a line scanner over text, not a shell parser.
#   Not seen at the producer: an extensionless file (6 tracked files carry a shell shebang: three shims or stubs, the reference-transaction hook and pre-commit and pre-push, which hold their pipes
#   inside command substitutions; no pair was derived from them when that arm was measured ALONE (J0 R6, before the any-producer arm), and the owner relation needs a `name.ext` token, so an extensionless file
#   is never an owner here whatever it pipes: the 0 is not a measurement of what a shebang arm would add beside the any-producer arm); a bar inside `"$( )"`, after an apostrophe inside a double-quoted string
#   or after a quoted string that spans physical lines (`jq -r '` newline `.a` newline `' f | curl`): the quote-parity test reads every later bar of the physical line as quoted. Ignoring parity adds 23 triples
#   (258 to 281): 12 new pairs, ten of them prose words (`no`, `out`, `must`, `the`), two real (`grep`, `markdown-lint.sh`), and nine triples on pairs that already exist (`jq`, `sed`, `sha256sum`, `tr`: real verbs on
#   workflow and monitor files, so the loss is not only prose); a bar that ends a case-pattern shape (`x=$(jq . | curl)`, `( a | VERB )`: the case-pattern exclusion hides it, and relaxing it adds 4 triples, 3 new
#   pairs, all prose words); a verb behind `sudo -u U VERB` (sudo skips its flag but not the flag's argument, so `U` is read as the verb), `| nohup|time|ionice|setsid|flock|xargs VERB`, an absolute path, a
#   backslash or a variable (`| /usr/bin/curl`, `| \curl`, `| $C`), `timeout "$T" VERB`, `env -C D VERB`, `A=$(..) VERB`, a group opener (`printf x | ( umask 077; curl ... )`, and `{ curl` and `( curl` with a
#   space after the opener, which are not read either); a pipe that ends in `|&` or in `| # comment` (the line is not joined); a workflow step whose `shell:` is a quoted form (`shell: "bash"`; `shell: bash` followed by
#   anything DOES derive, including `shell: bash -e {0}`, which GitHub does not run with pipefail: an over-read, not a miss); pipefail reaching a library other than through a statement-start `. lib` or `source lib`
#   of a plain word; the owner relation, which is the basename as a whole token in the test file (a built name, or `.yaml` for `.yml`, is not matched; a test file that names a non-test file only in a FULL-LINE comment is
#   not an owner, but one that names it in a trailing comment (`: # bash x.sh`) is, an over-read; a name that appears only in a SOURCED harness is not read: owner tokens are read in the test file itself, stubs one hop
#   further); a stub stored two or more hops away.
#   Long lines. A logical line that grows past JOINBYTES (8192) keeps joining, so the consumer of a trailing bar is still read, but it stops growing: its first 8192 bytes are read and so is the text joined since the last squeeze (up to 8192 more bytes: a chain of short lines behind a long one keeps every
#   consumer in it; past that bound only the newest line is kept); the text between is dropped (a site, or a `|| true`, only there is not seen: a missing site demands no row, a missing `|| true` demands one) and its quote parity is carried by at most one double and one single quote (squeeze).
#   JOINCAP (a logical line joins at most 50 further lines) and UNWRAPCAP (the 200 characters after a bar) are exact: the 51st further line, or a verb that ends at character 201, is not read, and fixtures sit on both sides of each
#   value (and of JOINBYTES: a verb that ends at byte 8192 or 8193). The loop list is compacted at 32 entries; no output depends on that threshold (only finished entries are dropped), so it cannot be pinned by a fixture and is not. The scan of the bars of ONE physical line is quadratic in its bars and length (anybar takes a substring per
#   bar): the longest physical line of the corpus is about 6 KB; 64000 bars on a 256 KB line took 3.2 s under gawk and 2.3 s under mawk 1.3.4 20200120 at load 3.3 (256038 bytes), and 19 s and 9 s at load 10 (a similar line of 256000 bytes): the figures are load-bound, the quadratic shape is not. A single physical line is not bounded by JOINBYTES.
#   The loop arm is SLOWER under mawk: 30000 consecutive `for vN in zz; do` lines (a new loop variable each, so a new dynamic regex each) took 30 s under mawk 1.3.4 20200120 against 5 s under gawk, at load 10; the corpus itself takes
#   1.2 s under mawk and 3.4 s under gawk. The compaction bounds the entries, not the regex compiles.
#   Annotations (R8): the string of an annotation echo is dropped only when it is double-quoted, up to its FIRST double quote (ANNOT), so a pipe inside a `$( )` in the string is HIDDEN when the substitution holds no double
#   quote (`$(cat f | head -1)`: annot-cmdsub-hidden) and READ, as residue, when it holds one (`$(printf '%s' "$p" | grep -c .)` leaves `echo "$p" | grep -c .) ...`: annot-cmdsub-quoted; the one tree instance, the
#   `echo "::error::..."` lines of git-data-rung2-rehearsal.yml, is read by that accident, not by design); a single-quoted or unquoted `::error::` annotation drops the rest of the logical line; an annotation string that spans
#   physical lines is dropped on its first line only (a bar on a later line of the string is read as code, so that limit adds pairs rather than hiding them). `|| true` and `|| :` make a site unobserved anywhere on the logical line.
#   Stubs not seen at the test file: one written by echo, tee, install, cp or ln -s; `function v {` without parentheses; `v()` with the brace on the next line; a loop body longer than 15 lines; a stub helper outside the literal list
#   (`make_stub write_stub stub_cmd mkstub stub`, `wstub` is not on it); a helper call or a loop that sits in a sourced file (they are read only in the test file itself; the sourced file contributes functions and file writes
#   only); a stub whose body sits in a helper function defined inside a heredoc stub; a second echo-written definition of an already-pinned verb is neither counted nor drain-checked. A loop is read when the `do` is on its `for` line
#   (the body after `; do` is read on that line) or the body writes a file named by the loop variable in the next 15 lines; a loop that writes a per-verb LOG (`> "$d/$b.log"`) is read as a stub of every verb of its list
#   (an over-derivation: it demands a row), and a closed same-line loop whose body writes nothing stays live for 15 lines, so a later unrelated write to `$d/$b` credits the stub. No `drains` row is possible for a loop-built or
#   same-line-loop stub (the finder finds no definition: rc 3), so such a pair can only be exempt.
#   Drain check: the brace bound compares leading whitespace by character count, so a tab counts as one character. The rare drain spellings fail closed with a hint naming the accepted form
#   (`[ -t 0 ] && true || cat`, a drain followed by a backgrounded `sleep`, a here-string in a command substitution, a `#` inside a string ahead of the drain, `if [ -t 0 ]; then ...; else cat; fi`,
#   a multi-line if/then/cat). A bare exit or return line ahead of the drain disarms it even in an earlier case arm (use an arm-drain row for such a stub). CREDITED although they read nothing, a file or stop at once (the
#   detector is a text pattern): `cat >/dev/null "$F"`, `cat >"$F" "$G"`, `dd of=/dev/null </dev/null`, `timeout 0.001 cat`, `echo "cat >/dev/null"`, `: the cat`, `exit 0 && cat >/dev/null`, `cat >&-`, `cat >/dev/full`, `if false;
#   then cat >/dev/null; fi`, `[ 1 = 2 ] && cat >/dev/null`, `[ ! -t 1 ] || cat >/dev/null`, `cat >/dev/null 2>&-`. These text-window limits are NOT attempted and are listed so that a reader does not assume them closed: a drain
#   in another case arm than the one the producer reaches (case-arm crossing), a heredoc writer with an unquoted delimiter, a never-true condition (`[ -n "${NEVER:-}" ] && cat`, `if false; then cat`), `cat <&3` (a descriptor
#   other than stdin), and a spelling inside a string. No `drains` row relies on any of them (the 31 stub definitions of the 21 drains rows were read for this), and closing them needs a parser, not a wider window.
#   Rows: an `exempt` row is an attestation, not a measurement: only its first word is checked against the closed vocabulary (and, for `fenced`, the tracker number), and the reach table in the S7c evidence file (not this table) says which
#   pairs ran at all. PJ_TRIPLES is a count pin: an edit that adds one triple and removes another leaves the count and passes (the swap escape; a set-diff pin is deliberately not attempted here).
#   Recompute PJ_TRIPLES from a tree with no uncommitted tracked change: `PJ_ALL="$(git ls-files)"; . <(sed -n '/^# PJ-DERIVE-BEGIN/,/^# PJ-DERIVE-END/p' .claude/hooks/grep-q-pipe-guard.test.sh); pj_join_pairs | LC_ALL=C sort -u | wc -l`
#   (the guard prints the same number on its PASS line). The derivation is bounded: a wrapper chain is read to 200 characters, a joined line to 8192 bytes and 50 lines, the loop list to 32 entries.
# STILL OPEN (listed, not planned here): the series of #9217 continues with the wave A3 carriers (six carrier rows and 23 later-wave sites, gated on a host replace)
# and the #9639 and #9638 triage. Item I (PR #10459) removes the infra-step JOBS pin of main-health-monitor.yml; its soak runs under tracker #7432, which stays
# open, and its merge record goes on #9217. Items D and H are recorded as not
# fixed, Item E as moot, and Item G (a --ratchets selector in scripts/test-all.sh) as not fixed, each with its reason on #9217; Item F is the multi-line passes, the
# widened reader pattern and population in the sweep above, and the survivors it left are listed under its STATED LIMITS. This block does not claim the series is finished.
# THE PRE-PUSH AFFECTED GATE DOES NOT SELECT THIS GUARD for a change to many of the files it reads. Measured 2026-10-16 at ee8644bded over this guard's own pairs, with
# `bash scripts/test-all.sh --print-selection --paths=<one path>` reading the selected bit: it selects the guard for 47 of the 98 producer files and 64 of the 97 owner suites and NOT for
# the other 51 and 33 (.github workflows and actions, plugin hooks and skill scripts, many scripts/*.sh). The 12-entry declared array (AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS in
# scripts/lib/test-affected-paths.sh) is only part of the declared edge. CI's full battery runs this guard, so a PR that adds one `| verb` to an unselected producer is green locally and red in CI; run it by hand
# after editing a script a suite stubs a verb for. Tracked in #10447; per-path rows and the re-measure recipe are in selection-measurement.md, found by name under knowledge-base/project/specs/archive/ after this merges.
# Only tracked files are read, so a new untracked file is invisible until it is staged. This awk derivation is AUTHORITATIVE. j0-derive.py in the S7c spec directory is a
# one-time cross-check of it (its sorted triples equalled the awk's at the S7c head, recorded in evidence.md); nothing in CI runs it, so an unexplained difference between the two is
# the port drifting, and only a person who runs it will see one.
PJ_DRAIN_WINDOW=4
PJ_ALL="$(git ls-files)"
PJ_TRIPLES=303   # recomputed from a green run (+6 at #10540 fix round: the key-rotate suite stubs doppler (1 producer file) and a jq shim (5 producer files); +1 at #10540: tests/scripts/test-argv-bearer-sweep.sh | jq | scripts/inngest-key-rotate.sh, a new producer of the already-judged (sweep, jq) pair; -1 at #11195: the plaintext-volume destroy gate suite's curl shim triple leaves with the deleted suite, undoing the +1 at #11179 recorded below; +1 at #11361: the egress-enforce probe suite stubs nft and names resolve.sh only in assert/comment text; +2 at #11260 round 2: the probe suite greps cloud-init-inngest.yml as text for the key-file writer pin; +2 at #11260: the key-continuity probe's flip-script pipeline reaches the provision-unit suite's timeout stub by name and the probe suite's own failing-head shim; 291 on main, +1 at #11179: the plaintext-volume destroy gate suite's curl shim, which drains its stdin config first; 291 on main, minus 1 at #10112: the retired inngest-luks-cutover suite's triple leaves with the file): the number of distinct (test file, verb, producer file) triples (289 -> 291 with the access suite's docker stub for the container probe, #8211 PR-E: two producer files; 286 -> 287 with the orphan-sweep guard's R9 curl shim, which drains its stdin config; earlier: 294 -> 286 at G1 PR-4a, #10937: seven triples of the four retired probes leave, and deriving HM5_FILES from the HMAC manifest drops the sweep's literal join on inngest-soak-6178.sh) (+1 at #10931: the registry wiring suite's doppler stub; +1 at #10696: the secret-scan suite's pass-through perl wrapper)
PJ_VOCAB=' not-a-command text-only unverified helper-built-stub variable-named-verb pass-through deliberate-fault arm-drain fenced '
PJ_FENCED_RE='^fenced[[:space:]]+#[0-9]+[[:space:]]+[^[:space:]]'   # the one word that carries a tracker link (pj_judge)
PRODUCER_JOIN=(
  '.claude/hooks/browser-snapshot-credential-guard.test.sh | jq | exempt | deliberate-fault never: def 156 `exit 127` first statement (jq absent shim; the row asserts the degraded deny) (reach T1; t1:rc1/0s red:rc0/1s; hits 1)'
  '.claude/hooks/git-commit-secret-scan.test.sh | perl | exempt | pass-through wrapper (R46i) logs one line then execs the real perl, which reads the piped command text'
  '.claude/hooks/grep-rewrite.test.sh | grep | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T1; t1:rc0/10s; hits 2)'
  '.claude/hooks/grep-rewrite.test.sh | jq | drains | 2 | *'
  '.claude/hooks/guardrails.test.sh | perl | exempt | deliberate-fault never: def 1034 `exit 127` first statement (perl absent stub, the fixture is "without perl the fallback still gates") (reach T1; t1:rc0/61s; hits 6)'
  '.github/scripts/test/fixtures-validate-infra-templates.sh | terraform | exempt | unverified reach probe: suite did not finish green here (cap or host), no matching piped call seen (1 non-test producers) (reach T1; t1:rc1/10s red:rc1/5s; hits 0)'
  '.github/scripts/test/test-mint-inngest-bootstrap-tag~.sh | gh | exempt | arm-drain all-arms-keyed: def 112 `body=$(cat)` at opener+29, after the arg parse; the earlier exits (FORBID 99, unmodelled flag 64, DELETE) are rows where no piped call may arrive (reach T2; t2:rc0/175s; hits 62 (stdin-flag))'
  'apps/cla-evidence/scripts/bootstrap-r2-probe.test.sh | doppler | drains | 1 | *'
  'scripts/betterstack-incident-mirror.test.sh | curl | drains | 1 | *'
  'apps/web-platform/infra/cat-deploy-state.test.sh | docker | exempt | text-only derived site ci-deploy.sh is grep-pinned only (the SDK_BASH_SMOKE_STATE_FILE default-path assert); the docker mock serves docker inspect alone and no piped call reaches it'
  'apps/web-platform/infra/ci-deploy.test.sh | curl | exempt | text-only derived sites cloud-init-inngest.yml (its two printf-to-curl -K - pipes: the Better Stack and the Sentry phone-home emitters) are grep-pinned only; ci-deploy.sh:378 feeds --config - via < <(printf) not a pipe'
  'apps/web-platform/infra/ci-deploy.test.sh | docker | drains | 2 | --password-stdin'
  'apps/web-platform/infra/ci-deploy.test.sh | doppler | exempt | unverified reach probe: suite did not finish green here (cap or host), no matching piped call seen (1 non-test producers) (reach T1; t1:rc124/300s; hits 0 (stdin-flag))'
  'apps/web-platform/infra/ci-deploy.test.sh | logger | exempt | arm-drain the logger mock of create_mock_logger (def 69) drains stdin first when no message operand follows the options (S7c edit, wire assert after the Layer 3 rollback case); the other four logger definitions are in-process function shadows of small extracted functions that no pipe feeds (reach: T1, hits 757)'
  'apps/web-platform/infra/ci-deploy.test.sh | openssl | exempt | text-only the suite names cloud-init-inngest.yml only to grep-pin it; the derived producer there is the health script echo-to-openssl s_client pipe, which this suite never executes, and the one openssl definition here (fo99_run) records its argv then delegates to the real openssl via command'
  'apps/web-platform/infra/ci-deploy.test.sh | python3 | exempt | unverified reach probe: suite did not finish green here (cap or host), no matching piped call seen (3 non-test producers) (reach T1; t1:rc124/300s; hits 0)'
  'apps/web-platform/infra/ci-deploy.test.sh | rc | exempt | not-a-command rc is a variable written by printf > $d/rc, no stub exists'
  'apps/web-platform/infra/ci-deploy.test.sh | tr | exempt | deliberate-fault stub exits 3 on purpose; pipeline status is the second tr, decided by the stub, not by a write race'
  'apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh | docker | exempt | fenced #9217 the docker stub (def 2004) logs its arguments and exits without reading the piped docker login --password-stdin of the inngest cloud-init template (5 hits); the owner file is not editable in this change; the suite is green at base (240/240), so the writer is a race and not a certain failure; the fix stays on the series tracker'
  'apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh | timeout | exempt | text-only the suite names inngest-cutover-flip.sh as a staged file and never runs it; its timeout stub wraps docker pull'
  'apps/web-platform/infra/inngest-luks-key-probe.test.sh | cryptsetup | exempt | text-only the suite greps cloud-init-inngest.yml as source text for the key-file writer line and never runs it'
  'apps/web-platform/infra/inngest-luks-key-probe.test.sh | head | exempt | deliberate-fault never reads: the head shim exits 1 as its first statement (a failing upstream stage; the case asserts the indeterminate at=key verdict)'
  'apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh | timeout | exempt | fenced #9217 the timeout stub passes the pipe on to the docker stub (def 2025 shift then exec), which never drains it; the owner file is not editable in this change; the suite is green at base (240/240); the fix stays on the series tracker'
  'apps/web-platform/infra/cloud-init-web-zot-seed.test.sh | curl | exempt | text-only derived sites cloud-init-inngest.yml:442,532 not executed; hits 806x11 are < <(printf) in scripts/fresh-host-boot-trail.sh:94,263'
  'apps/web-platform/infra/cloud-init-web-zot-seed.test.sh | docker | exempt | arm-drain all-arms-keyed: def 361 `login)` arm `pw=$(cat)` at opener+8; def 903 has no login arm (pull/cp only) and no hit reached it (reach T1; t1:rc0/49s; hits 77 (stdin-flag))'
  'apps/web-platform/infra/cloud-init-web-zot-seed.test.sh | timeout | exempt | pass-through wrapper logs then execs the wrapped command, which reads'
  'apps/web-platform/infra/cron-egress-enforce-probe.test.sh | nft | exempt | text-only resolve.sh is named only in the mint-parity assert text and a comment (whole-token basename owner match); the probe runs nft list against the stub, resolve.sh:492 echo|nft -f - is not run'
  'apps/web-platform/infra/cron-egress-firewall.test.sh | docker | exempt | text-only derived sites are apply-web-platform-infra.yml docker login lines, grep-pinned; resolve.sh:305 docker exec -i not reached (container absent in RB run)'
  'apps/web-platform/infra/cron-egress-firewall.test.sh | nft | exempt | helper-built-stub the RB resolver run pipes echo|nft -f - into rbmk-built stub (compliant, first stmt drains);'
  'apps/web-platform/infra/cron-egress-ghcr-probe.test.sh | nft | exempt | text-only suite extracts only the GHCR probe fn and constants; resolve.sh:492 apply is not run'
  'apps/web-platform/infra/cron-egress-nftables.test.sh | nft | drains | 1 | -f'
  'apps/web-platform/infra/cron-egress-self-heal.test.sh | jq | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T1; t1:rc1/14s red:rc0/33s red3:rc0/23s; hits 0)'
  'apps/web-platform/infra/cron-egress-self-heal.test.sh | nft | exempt | text-only suite extracts enforcement_probe/enforcement_extra and the self-heal block only; resolve.sh:492 not extracted'
  'apps/web-platform/infra/cutover-inngest-workflow.test.sh | curl | exempt | text-only the hits are process substitutions; the one executed pipe (cutover-inngest.sh:557) is invisible to the join and its stub drains'
  'apps/web-platform/infra/cutover-inngest-workflow.test.sh | doppler | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T2; t2:rc1/80s red2:rc0/36s; hits 0 (stdin-flag))'
  'apps/web-platform/infra/doppler-download-error-channel.test.sh | doppler | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T1; t1:rc0/4s; hits 0 (stdin-flag))'
  'apps/web-platform/infra/fresh-boot-ready.test.sh | curl | exempt | text-only the derived site is only text-pinned; the executed pipe (soleur-host-bootstrap.sh:1062) runs without pipefail'
  'apps/web-platform/infra/fresh-boot-ready.test.sh | doppler | exempt | text-only the derived producer apps/cla-evidence/infra/bootstrap.sh matches by basename only; the suite says bootstrap.sh only in assertion messages about the host bootstrap script and never runs the cla-evidence script'
  'apps/web-platform/infra/git-data-bootstrap-store-verify.test.sh | cryptsetup | exempt | text-only luksOpen pipe site (the `cryptsetup luksOpen --key-file -` line in git-data-bootstrap.sh section 1) is outside the extracted store-verify unit; stub answers isLuks only'
  'apps/web-platform/infra/git-data-cutover-access.test.sh | doppler | exempt | arm-drain the finalizer stub (def 2450) drains stdin as the first act of its secrets set arm (S7c edit, wire assert FZ1); the other three doppler stubs refuse or serve get only and receive no piped set (3 non-test producers)'
  'apps/web-platform/infra/git-data-cutover-access.test.sh | docker | drains | 1 | *'
  'apps/web-platform/infra/git-data-flag-precheck.test.sh | doppler | drains | 1 | = set'
  'apps/web-platform/infra/git-data-liveness.test.sh | curl | exempt | arm-drain def 180 drains in its --config arm at opener+4 and def 859 is a one-line printf stub whose body is cat >/dev/null (the finder reads the newline escape before cat as a word, so it cannot credit it); 122 piped --config - calls (reach T1)'
  'apps/web-platform/infra/git-data-luks-reopen.test.sh | cryptsetup | exempt | arm-drain the luksOpen arm reads the key (cat to key_seen) before any exit; keyed on the subcommand, not the flag'
  'apps/web-platform/infra/git-data-root-key.test.sh | curl | drains | 1 | *'
  'apps/web-platform/infra/git-data-root-key.test.sh | doppler | exempt | text-only reach probe: suite ran green and no piped call reached the stub (2 non-test producers) (reach T1; t1:rc0/97s; hits 0 (stdin-flag))'
  'apps/web-platform/infra/git-data-rung2-rehearsal.test.sh | curl | drains | 1 | *'
  'apps/web-platform/infra/infra-config-apply.test.sh | logger | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T2; t2:rc1/78s red2:rc1/48s; hits 2)'
  'apps/web-platform/infra/infra-config-apply.test.sh | sha256sum | exempt | text-only sha256sum is the pipe producer with a file operand at infra-config-apply.sh:489,512; no stdin is piped into it'
  'apps/web-platform/infra/inngest-boot-emitter.test.sh | curl | drains | 2 | *'
  'apps/web-platform/infra/inngest-dedicated-host-classify.test.sh | curl | exempt | text-only the suite runs only the probe and nolive steps of the inngest health workflow; the piped site is its pool probe step (printf Authorization to curl --header @-), which the suite never runs; the 13 stdin hits of the reach probe are the bearer-curl library process substitution, not a pipe (S7c re-read, evidence Phase 3)'
  'apps/web-platform/infra/inngest-dedicated-host-classify.test.sh | jq | drains | 1 | -R'
  'apps/web-platform/infra/inngest-host.test.sh | openssl | drains | 1 | s_client'
  'apps/web-platform/infra/inngest-inventory.test.sh | logger | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T2; t2:rc0/27s; hits 0)'
  'apps/web-platform/infra/inngest-key-rotate-workflow.test.sh | doppler | exempt | text-only no piped call reaches the strict doppler stub: the rotation script only reads (get, --only-names) and execs doppler run; the apply-web-platform-infra.yml producer pipes into doppler only in its CI-token mint step, which this suite never executes'
  'apps/web-platform/infra/inngest-key-rotate-workflow.test.sh | jq | exempt | deliberate-fault some-arms: the jq shim exits 5 only when state/jq_fail_tls exists AND the program names the tls-health marker (the kr_tls_rows read, whose input is a printf of a few lines, so no writer can see a broken pipe), else it execs the real jq, which reads the piped text'
  'apps/web-platform/infra/inngest-link-flip-workflow.test.sh | doppler | drains | 1 | *'
  'apps/web-platform/infra/inngest-link-resolver.test.sh | docker | exempt | text-only the suite sources only the inngest-link-resolver block of ci-deploy.sh (no pipe into docker inside it); the derived producer sites (the printf-to-docker-login --password-stdin pipe, the canary layer 3 pipe into logger and the docker logs pipe into logger) lie outside the block and are never executed here'
  'apps/web-platform/infra/inngest-link-resolver.test.sh | grep | exempt | pass-through the two grep shims (novv strips -v then execs the real grep; dropline execs the real grep and trims its last line) are put on PATH only for scrub calls, which read a file operand and never a pipe; the canary check in piped greps in ci-deploy.sh run in rows that use the docker stub and the real grep'
  'apps/web-platform/infra/inngest-link-resolver.test.sh | logger | exempt | text-only the suite sources only the inngest-link-resolver block of ci-deploy.sh, whose logger calls are plain calls or after a || (no pipe into logger); the derived producer sites (canary layer 3 and docker logs piped into logger) lie outside the block and are never executed here'
  'apps/web-platform/infra/inngest.test.sh | curl | exempt | text-only the probe body under test never pipes into curl; both stubs ignore stdin'
  'apps/web-platform/infra/inngest.test.sh | logger | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T2; t2:rc0/36s; hits 0)'
  'apps/web-platform/infra/luks-monitor.test.sh | cryptsetup | drains | 2 | --key-file -'
  'apps/web-platform/infra/luks-monitor.test.sh | curl | exempt | text-only no producer pipes into curl in luks-monitor.sh or workspaces-luks-emit.sh'
  'apps/web-platform/infra/luks-monitor.test.sh | died | exempt | not-a-command a shell function of workspaces-luks-harness; the producer site is prose in a printf message (reach T1; t1:rc0/16s; hits 0)'
  'apps/web-platform/infra/registry-boot-guard.test.sh | htpasswd | drains | 1 | *'
  'apps/web-platform/infra/registry-luks-escrow.test.sh | cryptsetup | drains | 1 | --key-file -'
  'apps/web-platform/infra/resend-inbound-bootstrap.test.sh | doppler | exempt | text-only step 4 pipe (resend-inbound-bootstrap.sh:252) is unreachable: the curl shim returns an empty domain list so step 1 exits first'
  'apps/web-platform/infra/scripts/sigpipe-triage-feasibility.test.sh | grep | exempt | arm-drain the shims drain on purpose and only when reading stdin (the suite negative arms depend on it)'
  'apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh | doppler | exempt | text-only the derived producer apps/cla-evidence/infra/bootstrap.sh matches by basename only; the suite says bootstrap.sh only in assertion messages about the host bootstrap script and never runs the cla-evidence script'
  'apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh | curl | exempt | text-only the suite names cloud-init-inngest.yml and workspaces-luks-provision.sh only to grep their text; the curl stub (exit 0, stdin ignored) serves the F5 emit and none of their piped curl calls is run'
  'apps/web-platform/infra/web-bash-synthetic.test.sh | docker | exempt | text-only derived site ci-deploy.sh is named as text only (the verdict-library source anchor and the SBS cross-reference comments); the suite is a mock docker serving inspect, stats and exec for web-bash-synthetic.sh, and no piped call from ci-deploy.sh reaches it'
  'apps/web-platform/infra/web-ghcr-deny.test.sh | docker | exempt | text-only the shim only sees `timeout 120 sudo docker pull` with no piped stdin'
  'apps/web-platform/infra/web-ghcr-deny.test.sh | timeout | exempt | text-only no pipe feeds the timeout shim here (cloud-init-registry.yml:2085 is not run)'
  'apps/web-platform/infra/web-probes-token-rotation.test.sh | doppler | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T1; t1:rc0/20s; hits 0 (stdin-flag))'
  'apps/web-platform/infra/web-zot-consumer-probe.test.sh | curl | exempt | text-only the suite names cloud-init-inngest.yml only to read its ZIREF pin; that file printf-to-curl -K - pipes (lines 442, 532) are not run, the suite curl stub serves the probe script'
  'apps/web-platform/infra/webhook-doppler-token-reread.test.sh | logger | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T2; t2:rc0/7s; hits 0)'
  'apps/web-platform/infra/workspaces-boot-unlock.test.sh | awk | exempt | unverified reach probe: suite did not finish green here (cap or host), no matching piped call seen (1 non-test producers) (reach T1; t1:rc124/300s; hits 0)'
  'apps/web-platform/infra/workspaces-boot-unlock.test.sh | cryptsetup | exempt | arm-drain the luksOpen arm reads the key (cat to key_seen) before any exit; keyed on the subcommand, not the flag'
  'apps/web-platform/infra/workspaces-boot-unlock.test.sh | doppler | exempt | unverified reach probe: suite did not finish green here (cap or host), no matching piped call seen (1 non-test producers) (reach T1; t1:rc124/300s; hits 0 (stdin-flag))'
  'apps/web-platform/infra/workspaces-luks-freeze.test.sh | cryptsetup | exempt | text-only no piped call observed; the sourced harness stubs drain'
  'apps/web-platform/infra/workspaces-luks-freeze.test.sh | died | exempt | not-a-command a shell function of workspaces-luks-harness; the producer site is prose in a printf message (reach T1; t1:rc0/49s; hits 0)'
  'apps/web-platform/infra/workspaces-luks-host-token-refresh.test.sh | doppler | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T1; t1:rc0/2s; hits 0 (stdin-flag))'
  'apps/web-platform/infra/workspaces-luks-host-token-refresh.test.sh | grep | exempt | pass-through delegates: recorder shim (loop at 82) logs argv then execs the real grep (reach T1; t1:rc0/2s; hits 32)'
  'apps/web-platform/infra/workspaces-luks-host-token-refresh.test.sh | sed | exempt | pass-through delegates: recorder shim execs the real sed (reach T1; t1:rc0/2s; hits 6)'
  'apps/web-platform/infra/workspaces-luks-provision.test.sh | awk | exempt | pass-through delegates: def 1190 exits 1 for a `canon=` awk (fault arm) else execs the real awk, which reads stdin (reach T1; t1:rc137/305s; hits 2)'
  'apps/web-platform/infra/workspaces-luks-provision.test.sh | cryptsetup | exempt | arm-drain all-arms-keyed: def 129 drains `key=$(cat)` as the first statement of the luksFormat and luksOpen arms; other verbs never receive a pipe (reach T1; t1:rc137/305s; hits 742)'
  'apps/web-platform/infra/workspaces-luks-provision.test.sh | curl | drains | 1 | --config -'
  'apps/web-platform/infra/workspaces-luks-rollback-refusal.test.sh | cryptsetup | exempt | unverified suite exits 2 in the isolated run (finds no block device); the sourced harness stubs drain'
  'apps/web-platform/infra/workspaces-luks-rollback-refusal.test.sh | died | exempt | not-a-command a shell function of workspaces-luks-harness; the producer site is prose in a printf message (reach T1; t1:rc2/0s red:rc2/0s; hits 0)'
  'apps/web-platform/infra/workspaces-luks-rollback-refusal.test.sh | rc | exempt | not-a-command rc is the f6() stub-exit-code parameter (F6_RC), not a command'
  'apps/web-platform/infra/workspaces-luks-staging.test.sh | cryptsetup | exempt | text-only no piped call observed; the sourced harness stubs drain'
  'apps/web-platform/infra/workspaces-luks-staging.test.sh | died | exempt | not-a-command a shell function of workspaces-luks-harness; the producer site is prose in a printf message (reach T1; t1:rc0/10s; hits 0)'
  'apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh | jq | exempt | text-only the stub is on PATH only for the web2_marker g3 sandbox, whose judge reads file operands, never a pipe'
  'apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh | ssh | exempt | variable-named-verb workflow calls ${WEB_HOST_SSH}, bound to the sshstub stand-in; arms drain for luks-monitor.sh and tar xzf'
  'apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh | cryptsetup | exempt | text-only the heartbeat only runs `cryptsetup status`; luksOpen pipes (cloud-init-registry.yml:1968,2085,2446) are outside the rendered heartbeat'
  'apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh | htpasswd | drains | 1 | *'
  'apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh | jq | exempt | deliberate-fault never: def 560 `exit 127` first statement (jq absent stub, NOJQ farm) (reach T1; t1:rc0/50s; hits 4)'
  'apps/web-platform/infra/zot-image-fetch.test.sh | cryptsetup | exempt | unverified the host-tool farm of the heartbeat block writes `exit 1` as the whole stub for six verbs in one same-line loop (def 411), and a second cryptsetup stub (def 212) answers `status` only and exits 64 otherwise; the suite renders only the heartbeat, which runs cryptsetup status and luksUUID reads, and no luksOpen pipe is run (S7c same-line loop arm) (reach: not probed, read by hand)'
  'apps/web-platform/infra/zot-image-fetch.test.sh | htpasswd | exempt | text-only the six verbs are stubbed `exit 1` in the heartbeat fixture, but the probe is guarded by `[ -f /etc/zot/htpasswd ]` (an absolute host path no fixture creates), so no piped call reaches the stub'
  'apps/web-platform/scripts/lib/in-image-copy-src.test.sh | tar | exempt | arm-drain all-arms-keyed: def 187 `-xf)` arm `cat >/dev/null` at opener+5 inside the argv loop, before any exit; `-cf)` arm prints and exits (producer side) (reach T2; t2:rc0/1s; hits 4)'
  'apps/web-platform/scripts/postgrest-reload-schema.test.sh | curl | exempt | arm-drain all-arms-unconditional: def 41 drains `cat > $CURL_STDIN_FILE` at opener+13 before any exit (outside the finder window) (reach T1; t1:rc0/1s; hits 19 (stdin-flag))'
  'apps/web-platform/scripts/run-migrations-schema-probe.test.sh | psql | exempt | arm-drain all-arms-keyed: defs 89 and 230 `if [[ -z $sql ]]; then cat >/dev/null; exit 0; fi` after the arg parse, before any other exit (reach T2; t2:rc0/2s; hits 7)'
  'apps/web-platform/test/infra/ghcr-blocked-alert.test.sh | doppler | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T1; t1:rc2/0s red:rc0/45s; hits 0 (stdin-flag))'
  'plugins/soleur/skills/community/test/community-argv.test.sh | base64 | exempt | pass-through delegates: recorder shim execs the real base64 (reach T1; t1:rc0/52s; hits 19)'
  'plugins/soleur/scripts/delegation-verify.test.sh | gh | exempt | text-only the derived site is not a pipe into gh: plugins/soleur/scripts/delegation-verify.sh:363 is a case-pattern alternation of quoted allowlist strings (`"gh run view"*|"gh run list"*|...`) that the line scanner reads as `| gh`; the file never pipes text into the gh stub (its two `printf | grep` pipes were rewritten to here-strings and process substitutions)'
  'plugins/soleur/skills/community/test/community-argv.test.sh | curl | exempt | arm-drain all-arms-keyed: def 147 drains `cat > $d/stdin.$n` / `body.$n` inside the argv loop (`--config -`, `--data-binary @-`) before any exit (SHIM_MUTATE rows deliberately drain to /dev/null) (reach T1; t1:rc0/52s; hits 81 (stdin-flag))'
  'plugins/soleur/skills/community/test/community-argv.test.sh | hmac_sha1_b64 | exempt | not-a-command shell function in scripts/lib/hmac-sha1-b64.sh'
  'plugins/soleur/skills/community/test/community-argv.test.sh | jq | exempt | pass-through shim: logs argv then execs the real jq, which reads (its one exit-5 arm is the unpiped createSession program)'
  'plugins/soleur/skills/community/test/community-argv.test.sh | od | exempt | pass-through delegates: recorder shim (1178 loop) logs argv then `exec`s the real od, which reads stdin (reach T1; t1:rc0/52s; hits 36)'
  'plugins/soleur/skills/community/test/community-argv.test.sh | openssl | exempt | pass-through delegates: recorder shim execs the real openssl (reach T1; t1:rc0/52s; hits 56)'
  'plugins/soleur/skills/community/test/community-argv.test.sh | tr | exempt | pass-through delegates: recorder shim execs the real tr (reach T1; t1:rc0/52s; hits 36)'
  'plugins/soleur/test/boundary-prefix.test.sh | gh | exempt | text-only the derived site is not a pipe into gh: plugins/soleur/scripts/delegation-verify.sh:363 is a case-pattern alternation of quoted allowlist strings (`"gh run view"*|"gh run list"*|...`) that the line scanner reads as `| gh`; the file never pipes text into the gh stub (its two `printf | grep` pipes were rewritten to here-strings and process substitutions)'
  'plugins/soleur/test/ci-pr-affected-preactivation.test.sh | sed | exempt | deliberate-fault some-arms: the shim exits 1 only for a sed program naming the lock variable (the lock-transform-failed arm), else execs the real sed; the driver text is piped to it by the gate and the arm asserts the unknown(transform-failed) verdict'
  'plugins/soleur/test/destructive-command-guard-hook.test.sh | jq | exempt | pass-through delegates: shims `-nc) exit 3` fault arm else `exec` real jq (reads stdin); the producer shape `-j .tool_input.command` reaches the exec arm (reach T1; t1:rc124/300s; hits 12)'
  'plugins/soleur/test/destructive-command-guard-hook.test.sh | lexer | exempt | not-a-command a word in a quoted case-pattern alternation (destructive-command-guard:382), prose (reach T1; t1:rc124/300s; hits 0)'
  'plugins/soleur/test/destructive-command-guard-hook.test.sh | perl | exempt | deliberate-fault never: def 292 `exit 255` first statement (bad perl farm) (reach T1; t1:rc124/300s; hits 2)'
  'plugins/soleur/test/flag-detach-shared.test.sh | doppler | exempt | unverified suite fails at base under the isolated run (rc1 at 21s); stub set arm never reads'
  'plugins/soleur/test/flag-org-scoping-pr2.test.sh | doppler | exempt | unverified suite fails at base under the isolated run (rc1 at 15s); stub set arm never reads'
  'plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh | curl | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T1; t1:rc0/29s; hits 0 (stdin-flag))'
  'plugins/soleur/test/hold-gate-eval.test.sh | gh | exempt | text-only the derived site is not a pipe into gh: plugins/soleur/scripts/delegation-verify.sh:363 is a case-pattern alternation of quoted allowlist strings (`"gh run view"*|"gh run list"*|...`) that the line scanner reads as `| gh`; the file never pipes text into the gh stub (its two `printf | grep` pipes were rewritten to here-strings and process substitutions)'
  'plugins/soleur/test/inngest-config-bundle-mirror.test.sh | sha256sum | drains | 1 | *'
  'plugins/soleur/test/operator-9321-stages.test.sh | doppler | exempt | text-only the derived producer apps/cla-evidence/infra/bootstrap.sh matches by basename only; the suite names the generated operator script under knowledge-base/project/specs (also called bootstrap.sh), not the cla-evidence one'
  'plugins/soleur/test/operator-9321-stages.test.sh | gh | exempt | arm-drain all-arms-keyed: stub-world def (lib/operator-stub-world:155) `secret set` arm `cat >/dev/null` at opener+8, first statement of the arm (reach T1; t1:rc2/0s red:rc0/258s; hits 24 (stdin-flag))'
  'plugins/soleur/test/operator-9321-stages.test.sh | jq | exempt | pass-through shim in lib/operator-stub-world.sh: logs then execs the real jq'
  'plugins/soleur/test/operator-ack-guard.test.sh | doppler | drains | 1 | secrets set'
  'plugins/soleur/test/operator-agent-runnable.test.sh | doppler | exempt | text-only the derived producer apps/cla-evidence/infra/bootstrap.sh matches by basename only; the suite names the generated operator script under knowledge-base/project/specs (also called bootstrap.sh), not the cla-evidence one'
  'plugins/soleur/test/operator-agent-runnable.test.sh | gh | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T1; t1:rc1/18s red:rc0/88s; hits 0 (stdin-flag))'
  'plugins/soleur/test/operator-agent-runnable.test.sh | jq | exempt | pass-through delegates: stub-world shim (lib/operator-stub-world:276) logs then execs the real jq; the `for bin in ... jq ...` loop at 114 is a tool-availability check, not a stub writer (reach T1; t1:rc1/18s red:rc0/88s; hits 12)'
  'plugins/soleur/test/operator-digest-provision.test.sh | gh | drains | 1 | secret set'
  'plugins/soleur/test/operator-script.test.sh | doppler | exempt | text-only no piped call observed (rc0 158s); the shared stub-world doppler set arm reads'
  'plugins/soleur/test/operator-script.test.sh | gh | exempt | arm-drain all-arms-keyed: def 147 `secret set` arm `cat >> $GH_STDIN_LOG` at opener+8; the stub-world def (lib/operator-stub-world:155) drains `cat >/dev/null` in its `secret set` arm (reach T1; t1:rc0/277s; hits 6 (stdin-flag))'
  'plugins/soleur/test/operator-script.test.sh | jq | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T1; t1:rc0/277s; hits 0)'
  'plugins/soleur/test/operator-stage-approval-hook.test.sh | doppler | exempt | text-only no piped call observed (rc0 12s)'
  'plugins/soleur/test/operator-stage-approval-hook.test.sh | gh | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T1; t1:rc0/12s; hits 0 (stdin-flag))'
  'plugins/soleur/test/operator-stage-approval-hook.test.sh | jq | exempt | text-only no piped call observed (rc0 12s); stub-world jq is a pass-through exec'
  'plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh | sha256sum | drains | 1 | -c -'
  'plugins/soleur/test/sole-copy-drift-check.test.sh | curl | exempt | arm-drain the curl stub reads its config from stdin (`cat > "$rec.$n.stdin"`) after argument parsing, so a refusal arm exits before the read; the only producer is bearer-curl.sh feeding one header line, far under any pipe buffer'
  'plugins/soleur/test/sole-copy-drift-check.test.sh | doppler | exempt | text-only the apply-web-platform-infra.yml mention is a forbidden-vocabulary string in the issue-body check, never executed; the job under test calls doppler without a pipe into it'
  'plugins/soleur/test/ship-followthrough-directive.test.sh | parse_directive | exempt | not-a-command shell function in scripts/sweep-followthroughs.sh'
  'plugins/soleur/test/technical-ruling-gate.test.sh | gh | exempt | text-only the derived site is not a pipe into gh: plugins/soleur/scripts/delegation-verify.sh:363 is a case-pattern alternation of quoted allowlist strings (`"gh run view"*|"gh run list"*|...`) that the line scanner reads as `| gh`; the file never pipes text into the gh stub (its two `printf | grep` pipes were rewritten to here-strings and process substitutions)'
  'scripts/check-cloudflare-token-drift.test.sh | curl | exempt | arm-drain all-arms-keyed: def 237 drains `_stdin_cfg=$(cat)` in the `--config -` arm at opener+10, before any decision or exit (reach T1; t1:rc0/90s; hits 299 (stdin-flag))'
  'scripts/check-cloudflare-token-drift.test.sh | doppler | exempt | text-only reach probe: suite ran green and no piped call reached the stub (2 non-test producers) (reach T1; t1:rc0/90s; hits 0 (stdin-flag))'
  'scripts/check-deploy-script-parity.test.sh | python3 | exempt | deliberate-fault some-arms: def 234 `[[ $1 == -I ]] && exit 1` (fails ONLY the HMAC call), else execs the real python3 (reach T2; t2:rc0/3s; hits 2)'
  'scripts/check-web-host-escrow-config.test.sh | doppler | exempt | unverified reach probe: suite did not finish green here (cap or host), no matching piped call seen (1 non-test producers) (reach T1; t1:rc124/301s; hits 0 (stdin-flag))'
  'scripts/ci-demand-census.test.sh | jq | exempt | text-only no piped jq in scripts/ci-demand-census.sh (every jq reads a file operand); the ci.yml sites in sites.txt are fixture names, not exercised'
  'scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh | tr | exempt | deliberate-fault never: `printf #!/usr/bin/env bash\nexit 5\n` at 334 (failing tr, "a failing CR strip is never read as no marker")'
  'scripts/followthroughs/inngest-soak-6178.test.sh | python3 | exempt | deliberate-fault python3 stubs exit 1 or print a non-digest to drive the refused-signature rows, and the producer is printf with an empty write (no EPIPE possible) of the followthrough script (reach: not probed, found by the final configuration, read by hand)'
  'scripts/followthroughs/web2-luks-live-6931.test.sh | ready | exempt | not-a-command a word in a usage comment of betterstack-query:110; the suite stubs a ready function and no non-test pipe feeds it (reach T2; t2:rc0/169s; hits 324)'
  'scripts/followthroughs/workspaces-plaintext-hold-9348.test.sh | jq | drains | 1 | *'
  'scripts/followthroughs/zot-soak-6122.test.sh | curl | exempt | text-only no pipe into curl: the soak feeds --config - via a process substitution `< <(printf ...)` (zot-soak-6122.sh:274-276) whose writer status is never observed'
  'scripts/inngest-probe-heartbeat-feeder.test.sh | curl | exempt | arm-drain all-arms-unconditional: def 131 `stdin="$(cat)"` at opener+5 before any exit (one line outside the window) (reach T1; t1:rc0/33s; hits 101 (stdin-flag))'
  'scripts/lint-dual-lockfile.test.sh | bunfig.local.toml | exempt | not-a-command a file name in a case-pattern alternation (lint-dual-lockfile:52) (reach T2; t2:rc0/3s; hits 0)'
  'scripts/lint-workflow-local-action-checkout.test.sh | bc_hmac_sha256_hex | exempt | not-a-command shell function sourced from scripts/lib/bearer-curl.sh, the suite only lints track.sh text'
  'scripts/marketplace-drift-check.test.sh | jq | exempt | text-only the checked step (scheduled-marketplace-drift.yml check) reads jq stdin by here-string `<<<` only, never a pipe into jq'
  'scripts/rotate-supabase-db-credential.test.sh | doppler | drains | 1 | secrets set'
  'scripts/ship-incident-pir-gate-mutation.test.sh | awk | exempt | deliberate-fault never: def 394 `exit 2` first statement (broken strip stage, M10/N10 rows) (reach T1; t1:rc0/9s; hits 4)'
  'scripts/sweep-followthroughs.test.sh | gh | drains | 5 | --body-file -'
  'scripts/test-content-publisher.sh | _liquid_redact_secrets | exempt | not-a-command a shell function of content-publisher that the suite sources; not a stub and not an external command (reach T2; t2:rc0/28s; hits 0)'
  'scripts/test-jaccard-duplicates.sh | AGENTS.md | exempt | not-a-command a file name inside a markdown table printed by rule-audit, prose (reach T2; t2:rc0/1s; hits 0)'
  'scripts/test-jaccard-duplicates.sh | constitution.md | exempt | not-a-command a file name inside a markdown table printed by rule-audit, prose (reach T2; t2:rc0/1s; hits 0)'
  'scripts/verify-agent-security-slice1.test.sh | bash | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T2; t2:rc0/8s; hits 0)'
  'scripts/watch-registration-narrowing-9564.test.sh | gh | exempt | arm-drain the issue comment arm reads stdin in both branches before exit; keyed on the subcommand'
  'tests/hooks/test_incidents.sh | jq | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T1; t1:rc0/1s; hits 0)'
  'tests/scripts/test-argv-bearer-sweep.sh | curl | exempt | arm-drain some-arms: 6 shims; 1523/3279 drain `cat > $D/$n.stdin` on `--config -` after the arg parse; 126/2484/3713 exit 99 on an unmodelled flag before any read; 3793 execs the real curl (reach T1; t1:rc124/301s; hits 455 (stdin-flag))'
  'tests/scripts/test-argv-bearer-sweep.sh | docker | drains | 1 | *'
  'tests/scripts/test-argv-bearer-sweep.sh | doppler | exempt | unverified reach probe: suite did not finish green here (cap or host), no matching piped call seen (3 non-test producers) (reach T1; t1:rc124/301s; hits 0 (stdin-flag))'
  'tests/scripts/test-argv-bearer-sweep.sh | fatal | exempt | not-a-command a word in a case-pattern alternation (cloud-init-registry:1759), prose (reach T1; t1:rc124/301s; hits 0)'
  'tests/scripts/test-argv-bearer-sweep.sh | htpasswd | exempt | text-only every htpasswd word is registry-template site text or mutation text; the executable arm stubs docker, never htpasswd, so no piped call reaches an htpasswd stub'
  'tests/scripts/test-argv-bearer-sweep.sh | jq | exempt | pass-through shim records argv then execs the real jq on every path'
  'tests/scripts/test-argv-bearer-sweep.sh | python3 | exempt | deliberate-fault never: the PYSEL and PYGARB fault stubs fail only `-I` / print a non-digest (fault stubs for the parity E1b rows) (reach T1; t1:rc124/301s; hits 13)'
  'tests/scripts/test-destroy-guard-counter-web-platform.sh | doppler | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T1; t1:rc0/41s; hits 0 (stdin-flag))'
  'tests/scripts/test-git-data-birth-readiness-gate.sh | curl | exempt | unverified reach probe: suite did not finish green here (cap or host), no matching piped call seen (2 non-test producers) (reach T1; t1:rc124/300s; hits 0 (stdin-flag))'
  'tests/scripts/test-git-data-birth-readiness-gate.sh | grep | exempt | pass-through shim execs the real grep; its exit-2 fault arm is reached only through a here-string since #9210, so no pipe reaches it'
  'tests/scripts/test-git-data-wipe-wedge.sh | doppler | exempt | text-only reach probe not run for this pair: the producer pipes into doppler only in the CI-token mint step of apply-web-platform-infra.yml (two secrets set calls), which this suite never executes; it extracts the plan-time gates and runs them under a shim that answers doppler run or a quiet success'
  'tests/scripts/test-git-data-boot-signal-poll.sh | doppler | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T1; t1:rc0/21s; hits 0 (stdin-flag))'
  'tests/scripts/test-git-data-rung2-evidence-capture.sh | curl | exempt | text-only reach probe: suite ran green and no piped call reached the stub (2 non-test producers) (reach T1; t1:rc1/92s red3:rc0/38s; hits 0 (stdin-flag))'
  'tests/scripts/test-registry-d10-workflow-wiring.sh | doppler | exempt | text-only the suite runs only the restore step body, which calls doppler bare in a command substitution with no stdin; the text piped into doppler lives in other steps of the workflow file it names, and none of those steps runs (1 non-test producers)'
  'tests/scripts/test-sentry-alert-live-fidelity.sh | curl | drains | 2 | *'
  'plugins/soleur/test/token-drift-workflow-causes.test.sh | curl | drains | 1 | *'
  'tests/scripts/test-supabase-advisor-scan.sh | curl | drains | 1 | --header @-'
  'tests/scripts/test-workspaces-luks-cutover-gate.sh | cryptsetup | exempt | text-only reach probe: suite ran green and no piped call reached the stub (1 non-test producers) (reach T1; t1:rc0/5s; hits 0)'
  'tests/scripts/test-zot-log-channel-probe.sh | awk | drains | 2 | *'
)
# A row may spell its test-file column with one `~` before the extension (`name~.sh`): the battery-tag-authorship suite follows every path literal of a closure
# member, so a row that names a glob-collected suite in full pulls that suite (and its tag-authoring git commands) into the battery closure. The `~` hides the literal from
# that scan; this line removes it before any reader sees a row.
PRODUCER_JOIN=("${PRODUCER_JOIN[@]//\~/}")
# PJ-DERIVE-BEGIN
# One awk program: the five definitions of the derivation. Measured, not promised: the program parses and the guard prints the same verdict lines (and the same triples) under gawk, mawk 1.3.4
# (20200120 and 20240123) and busybox awk 1.38 (command and result in the S7c evidence, the sections "Fix round A" and "Post-merge and fix round C"); it uses no \b, no gensub and no intervals (all three differ: mawk has no
# gensub, mawk 20200120 does not match `a{3}`, and gawk evaluates `m[k] = (k in m ? m[k] "," : "") x` before it creates `m[k]` where mawk and busybox do not; no lint reads those, they are avoided by hand), and the
# lint below (pj_collide) rejects the one construct THIS file's programs could carry that gawk accepts and mawk does not: a function parameter that is also a function name.
#   non-test file  tracked file of a PJ_EXTS extension, not test-shaped, not under knowledge-base/ or fixtures/
#   test file      tracked .sh, test-shaped
#   text pipe      on a logical line (joined over a trailing backslash or bar): (printf|echo|cat) ... | WORD, or any stage before a single bar
#                  outside quotes | WORD, WORD behind sudo, a wrapper or VAR=x; kept when the file has pipefail in scope (its own token, `shell: bash`,
#                  or a sourcing file's token for a library) and the logical line carries no `|| true` or `|| :` (anywhere on it); an annotation echo's string is dropped to its first double quote
#   stub of WORD   in a test file or in a file it sources (one hop, unique basename): `WORD() {`, a file written to .../WORD by cat or
#                  printf, a stub-helper call naming WORD as any argument, or (test file only) a `for` loop over names whose body writes .../$VAR
#   owner          a test file whose lines, full-line comments aside, hold the non-test file's basename as a whole token (a trailing comment counts)
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
  XRE = "[.](" exts ")([^A-Za-z0-9_.-]|$)"
  HELPCALL = "^[ \t]*(make_stub|write_stub|stub_cmd|mkstub|stub)[ \t]+[^<>;|&)]*"   # R5a: a stub-helper call at the start of a statement, every argument
  FORRE = "^[ \t]*for[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+in[ \t]+"           # R5b: a loop over verb names
  sq = sprintf("%c", 39)
  STRIPL = "^[\"" sq "(){};]+"; STRIPR = "[\"" sq "(){};]+$"
  ANNOT = "::(error|warning|notice)::([^\"\\\\]|\\\\.)*(\"|$)"   # R8: the annotation string, to its closing unescaped quote
  YBLOCK = "(:|(^|[ \t])-)[ \t]*[|>][-+]?[ \t]*$"   # a YAML block-scalar indicator (key: | or - |) ends a line with a bar that is not a pipe
  nw = split("timeout env command nice stdbuf exec builtin", wl, " "); for (i = 1; i <= nw; i++) WRAP[wl[i]] = 1
  JOINCAP = 50   # a logical line joins at most this many further lines...
  JOINBYTES = 8192   # ...and stops growing once it is this long: the first JOINBYTES bytes and what is joined after them (the text joined since the last squeeze, up to JOINBYTES, then only the newest line) are read, the text between is not (squeeze)
  UNWRAPCAP = 200   # the characters after a bar that unwrap reads: a wrapper chain longer than this names no verb
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
# R3: a producer of any kind. Every single bar outside quotes is a pipe into the word after it (a bar preceded by a bar or a backslash, or followed by a bar, is
# not; `|&` is). Quote parity of the text before the bar (an even number of unescaped double quotes and of single quotes) keeps a bar inside a string out; a
# bar followed by a word and a closing parenthesis is a case-pattern alternation (`a|curl) :;;`), not a pipe. The old printf/echo/cat scan stays as a second
# site source and the two are unioned, so a regression of this arm cannot move the rows the old scan defines.
function anybar(l,   rest, bs0, p, pos, pc, nx, pre, after, nd, ns) {
  rest = l; bs0 = 0
  while ((p = index(rest, "|")) > 0) {
    pos = bs0 + p; bs0 = pos; rest = substr(l, pos + 1)
    pc = (pos > 1) ? substr(l, pos - 1, 1) : ""
    nx = substr(l, pos + 1, 1)
    if (pc == "|" || pc == "\\" || nx == "|") continue
    after = substr(l, pos + 1 + (nx == "&"))
    sub(/^[ \t]+/, "", after)
    if (after !~ /^[A-Za-z_"(){};]/ && substr(after, 1, 1) != sq) continue     # no word can follow: nothing to read
    if (after ~ /^[A-Za-z_][A-Za-z0-9_.-]*[ \t]*\)/) continue                    # case-pattern alternation
    pre = substr(l, 1, pos - 1); gsub(/\\./, "", pre); nd = gsub(/"/, "", pre); ns = gsub(sq, "", pre)
    if (nd % 2 != 0 || ns % 2 != 0) continue                                      # the bar is inside a string
    unwrap(substr(after, 1, UNWRAPCAP))
  }
}
# The site scan of ONE logical line of a non-test file: the annotation strip (R8), the pipefail token, and every text pipe on it.
function site(l,   s, m, rst) {
  if (l ~ /^[ \t]*#/) return
  if (index(l, "::")) gsub(ANNOT, "", l)   # an annotation echo shows the operator a command: its text is not a pipe (a double-quoted string is dropped to its FIRST double quote; a pipe before it or after that quote is read, see Annotations in STATED LIMITS)
  if (index(l, "pipefail")) pf = 1
  if (isy && l ~ /shell:[ \t]*bash/) pf = 1
  if (!index(l, "|")) return
  o = !(index(l, "||") && l ~ UNOBS)
  anybar(l)
  if (index(l, "printf") || index(l, "echo") || index(l, "cat")) {
    s = l
    while (match(s, PIPE)) {
      m = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
      sub(/^.*\|[ \t]*/, "", m)
      if (m ~ /^sudo[ \t]+(-[A-Za-z0-9_]+[ \t]+)*[A-Za-z_]/) sub(/^sudo[ \t]+(-[A-Za-z0-9_]+[ \t]+)*/, "", m)
      addsite(m)
      if ((m in WRAP) || substr(s, 1, 1) == "=") { rst = s; sub(/\|.*$/, "", rst); unwrap(substr(m rst, 1, UNWRAPCAP)) }
    }
  }
}
# R5b: the loop list keeps its finished entries until no loop is active, so a file of loops each begun within 15 lines of the last would grow it without end and
# loopchk would walk it on every line. At 32 entries the finished ones are dropped (at most 15 can be active); nothing a live entry reads moves.
function lcompact(   k, j) {
  j = 0
  for (k = 1; k <= nlp; k++) if (ll[k] > 0) { j++; if (j != k) { lw[j] = lw[k]; ll[j] = ll[k]; lre1[j] = lre1[k]; lre2[j] = lre2[k] } }
  nlp = j
}
# R5b: a stub built in a loop over verb names. The body is the next 15 lines up to a `done` at column 0; when a line of it writes a file named by
# the loop variable (or calls a stub helper with it), every bare lowercase word of the loop list is a stub of the suite.
function loopwords(k,   i, nw2, wa, w) {   # every bare lowercase word of the list of loop k is a stub of this suite
  nw2 = split(lw[k], wa, /[ \t]+/)
  for (i = 1; i <= nw2; i++) {
    w = wa[i]; sub(STRIPL, "", w); sub(STRIPR, "", w)
    if (w ~ /^[a-z][a-z0-9_.-]*$/) hs[file, w] = 1
  }
}
function loopchk(line,   k) {
  for (k = 1; k <= nlp; k++) {
    if (ll[k] <= 0) continue
    if (line ~ /^done/) { ll[k] = 0; lact--; continue }
    ll[k]--
    if (ll[k] == 0) lact--
    if (line ~ lre1[k] || line ~ lre2[k]) {
      loopwords(k)
      if (ll[k] > 0) { ll[k] = 0; lact-- }
    }
  }
}
# R1: a joined line that has grown past JOINBYTES keeps joining (so the consumer of a trailing bar is still read) but stops growing: its first JOINBYTES bytes stay, the text joined
# after them is dropped (a site there is not read), and the quote parity of everything dropped is carried by at most one double and one single quote placed after the kept text, so
# a later bar is judged as if the dropped text were still there. The pending trailing bar, if any, stays last. The first squeeze runs when the line passes JOINBYTES; after it, the text
# joined since is KEPT until it too passes JOINBYTES (sqlen is the length right after the last squeeze), so a chain of short lines behind a long one keeps every consumer in it; the
# retained text is at most about 2 x JOINBYTES plus the line being joined.
function squeeze(   q, h, qd, qs, hd, hs2) {
  q = substr(cur, 1, length(cur) - hbar); h = substr(q, 1, JOINBYTES)
  gsub(/\\./, "", q); qd = gsub(/"/, "", q); qs = gsub(sq, "", q)
  gsub(/\\./, "", h); hd = gsub(/"/, "", h); hs2 = gsub(sq, "", h)
  cur = substr(cur, 1, JOINBYTES) " " ((qd - hd) % 2 != 0 ? "\"" : "") ((qs - hs2) % 2 != 0 ? sq : "") (hbar ? "|" : "")
  sqlen = length(cur)
}
# R1: a code line that ends in a backslash, or in a single bar outside quotes that is not a YAML block-scalar indicator, absorbs the next line.
function feed(raw,   t, s, q, nd, ns, fn, fk, fw) {
  if (hold && hbar && raw ~ /^[ \t]*#/) return   # a comment line between the stages of a pipe is not code: the pipe goes on past it
  if (hold) { if (length(cur) > JOINBYTES + sqlen) squeeze(); t = raw; sub(/^[ \t]+/, "", t); cur = cur " " t; hn++ } else { cur = raw; hn = 0; sqlen = 0 }
  hold = 0
  t = substr(cur, length(cur), 1)
  if (hn < JOINCAP && (t == "\\" || t == "|" || t == " " || t == "\t" || t == "\r") && cur !~ /^[ \t]*#/) {   # only a line whose last character can end in a backslash or a bar is looked at
    fn = length(cur); fk = (fn > 64) ? fn - 63 : 1; fw = substr(cur, fk); sub(/[ \t\r]+$/, "", fw)   # the end of the line is stripped first: a long line is not copied to find its last character
    if (length(fw) < 2 && fk > 1) { fw = cur; sub(/[ \t\r]+$/, "", fw); fk = 1 }
    fn = fk - 1 + length(fw)   # the length of cur without its trailing blanks
    if (fw ~ /\\$/ && fw !~ /\\\\$/) { cur = substr(cur, 1, fn - 1); hold = 1; hbar = 0 }
    else if (fw ~ /\|$/ && fw !~ /\|\|$/) {
      s = substr(cur, 1, fn)
      if (s !~ YBLOCK) {
        q = substr(s, 1, fn - 1); gsub(/\\./, "", q); nd = gsub(/"/, "", q); ns = gsub(sq, "", q)
        if (nd % 2 == 0 && ns % 2 == 0) { cur = s; hold = 1; hbar = 1 }
      }
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
  # a line with none of these can change nothing in the site scan, so only these (and the continuation of a joined line) reach it
  if (isnt && (hold || index($0, "|") || index($0, "\\") || index($0, "pipefail") || (isy && index($0, "shell:")))) feed($0)
  if (ist && lact > 0) loopchk($0)
  match($0, /^[ \t]*/); c = substr($0, RLENGTH + 1, 1)   # the first character of the code decides which of the statement-start rules below can apply
  if (c == "#") next
  l = $0
  if (index(l, "::")) sub(/::(error|warning|notice)::.*$/, "", l)   # physical lines: the pipefail token of a test file (the sourcer of a library may be one), and the stubs below
  if (!isnt && index(l, "pipefail")) pf = 1
  if (iss && index(l, "()")) {
    if (l ~ FNRE) { m = l; sub(/^[ \t]*(function[ \t]+)?/, "", m); sub(/[ \t]*\(\).*$/, "", m); addfp(file, m) }
  }
  if (iss && index(l, ">") && (index(l, "cat") || index(l, "printf"))) {
    s = l
    while (match(s, PATHRE)) {
      m = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
      sub(/["; \t]+$/, "", m); sub(/^.*\//, "", m); addfp(file, m)   # the name, without the quote, the semicolon or the blank that ended the match (R7: a stub file written to a jq path and followed by a semicolon was recorded as jq with the quote and the semicolon kept)
    }
  }
  if (ist && c == "f" && match(l, FORRE)) {   # R5b: remember the loop; its next lines are read by loopchk
    v = substr(l, RSTART, RLENGTH); rest = substr(l, RSTART + RLENGTH)
    sub(/^[ \t]*for[ \t]+/, "", v); sub(/[ \t]+in[ \t]+$/, "", v)
    body = ""; if (match(rest, /;[ \t]*do([^A-Za-z0-9_]|$)/)) { body = substr(rest, RSTART + RLENGTH); rest = substr(rest, 1, RSTART - 1) }
    sub(/;[ \t]*$/, "", rest)
    if (lact == 0) nlp = 0
    if (nlp >= 32) lcompact()
    nlp++; lact++; lw[nlp] = rest; ll[nlp] = 15
    lre1[nlp] = "(cat|printf)[^|]*>>?[ \t]*\"?[^ \"]*/(\\$" v "([^A-Za-z0-9_]|$)|\\$\\{" v "\\})"
    lre2[nlp] = "^[ \t]*(make_stub|write_stub|stub_cmd|mkstub|stub)([^A-Za-z0-9_]|$)[^|]*\\$" v "([^A-Za-z0-9_]|$)"
    if (body != "" && (body ~ lre1[nlp] || body ~ lre2[nlp])) { loopwords(nlp); ll[nlp] = 0; lact-- }   # the whole loop on one line: for, then `; do`, a file write named by the loop variable, then `; done`
  }
  if (ist) {
    if (index(l, ".") && l ~ XRE) {
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
  if ((c == "." || c == "s") && l ~ /^[ \t]*(\.|source)[ \t]/ && match(l, SRCRE)) {
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
# read it, so no arm can widen one of the three and not the others. The awk gets it as `-v exts=a|b|c` (PJ_EXTS_RE).
PJ_EXTS='sh bash yml yaml tf tftpl template service tmpl'
PJ_EXTS_RE="${PJ_EXTS// /|}"
# pj_derive <listing file> <files...> -> "<test file>\t<verb>\t<non-test file>" per derived pair x producer, unsorted. The ONE call of the derivation:
# the real run and every derivation fixture go through it, so a fixture exercises the same program the tree does.
pj_derive() { local listing="$1"; shift; LC_ALL=C awk -v exts="$PJ_EXTS_RE" "$PJ_AWK" "$listing" "$@"; }
# pj_join_pairs -> "<test file>\t<verb>\t<non-test file>" per derived pair x producer, unsorted. Tracked files only, so an untracked
# scratch file cannot move the set. rc 0 whatever it derives; the caller treats an empty result as UNRESOLVED. One awk run over one
# `git ls-files` listing, one token set per test file; the cheap `index` tests in front of each regex keep it to a few seconds (it reads about 42 MB;
# measured 4.4 to 5.5 s of user CPU at origin/main and 6.1 to 7.9 s at this head under load, S7c review performance seat). LC_ALL=C: no locale-dependent
# classes, and one tracked fixture holds invalid UTF-8.
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
# PJ_UNIQ_SH: the tracked .sh files whose basename is unique among ALL tracked files (the derivation's one-hop sourcing rule: a sourced name that two tracked files
# share names no file), built once so that pj_sourced reads a short list instead of the whole listing on each call.
PJ_UNIQ_SH="$(printf '%s\n' "$PJ_ALL" | LC_ALL=C awk '{ b = $0; sub(/^.*\//, "", b); bc[b]++; bp[b] = $0 } END { for (b in bc) if (bc[b] == 1 && bp[b] ~ /\.sh$/) print bp[b] }')"
# pj_sourced <test file> -> the tracked .sh files it sources, one hop, by that unique basename, comment lines skipped, the file itself excluded. The derivation
# (`src` in PJ_AWK) reads the same statements, and pj_check_rows reads the stubs of the sourced files as well as the test file's own.
pj_sourced() {
  LC_ALL=C awk -v self="$1" 'NR == FNR { b = $0; sub(/^.*\//, "", b); bu[b] = $0; next }
    match($0, /^[ \t]*(\.|source)[ \t]+"?[^" \t;]+/) { m = substr($0, RSTART, RLENGTH); sub(/^[ \t]*(\.|source)[ \t]+"?/, "", m); sub(/^.*\//, "", m)
      if ((m in bu) && bu[m] != self) print bu[m] }' <(printf '%s\n' "$PJ_UNIQ_SH") "$1"
}
# pj_defs <file> <verb> <token> -> one line per stub definition of the verb in the file: `ok <file>:<line>` when a drain keyed on the
# token (any drain when the token is *; the token may sit on an earlier line of the window than the drain) sits in the definition's
# opener line or in the PJ_DRAIN_WINDOW code lines after it, else `no <file>:<line>`. Comment and blank lines are not code lines, and a trailing comment is cut.
# The openers are a function opener, a file written to .../VERB by cat or printf, and a stub-helper call at the start of a statement; the extent of a stub ends
# at the next opener of ANY verb (function, helper call, heredoc writer), at its heredoc terminator, at the closing brace of its function (an indent no deeper than the
# opener's; on its own line for a one-line stub), and a bare exit or return ahead of the drain disarms it. A drain is a bare cat or a cat with a redirect or a command
# substitution (not `cat FILE`, not `cat < FILE`), or dd of=, minus the shapes PJ_NODRAIN names; the detector and the dynamic control below share one pattern. LC_ALL=C like the derivation.
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
# non-negated tty test on any descriptor (it reads only on a terminal: `[ -t 0 ] &&`, `[ -t 1 ] &&`, `test -t 0 &&`, `if [ -t 0 ]; then`), backgrounded (`cat >/dev/null &`, `cat >/dev/null & wait`:
# a background command reads /dev/null), with a heredoc (cat <<EOF reads the heredoc, not the pipe), with an input redirect (cat >/dev/null </dev/null reads the file,
# `<&-` reads nothing), cat as a word of a command that only names it (`echo cat`, `type cat`, `which cat`, `command -v cat`), dd with a count (it stops after N blocks
# and the writer is still blocked on the rest), or a line that exits or returns before the cat (`exit 0; cat >/dev/null`). Each of these is a real non-reader: the dynamic
# control below runs every one against a 1 MiB pipe, except the `return` form, which is a non-reader under dash (it leaves the script) and not under a bash 5 named sh (a bash invoked as sh is in POSIX mode and a failed `return` exits it with status 2; bash 3.2 as sh reports the error and goes on, rc 0; the shell-parity check
# below rejects a spelling that differs): it is held by the `samereturn` window fixture alone. The left word boundary of the `echo|printf|type|which|command -v` alternative keeps an identifier that merely ends in one of
# those words (`mytype cat >/dev/null`) a drain, and lets a path-qualified one (`/bin/echo cat`, `x.printf cat`) read as the non-reader it is: PJ_DET_EDGE and PJ_DET_EDGE_BAD below.
PJ_NODRAIN='[^|][|][[:space:]]*cat|(true|false|:)[[:space:]]*(&&|[|][|])[[:space:]]*cat|[[][[]?[[:space:]]+-t[[:space:]]+[0-9]+[[:space:]]+[]][]]?[[:space:]]*(&&|;[[:space:]]*then)|(^|[^[:alnum:]_])test[[:space:]]+-t[[:space:]]+[0-9]+[[:space:]]*(&&|;[[:space:]]*then)|[^&]&[[:space:]]*$|cat[^|;&]*[^&<>]&([^&>]|$)|cat[^|;]*<<|cat[^|;<]*<[^<&]|cat[^|;]*<&-|(^|[^[:alnum:]_-])(echo|printf|type|which|command[[:space:]]+-[vV])[[:space:]]+([^;|&]*[[:space:]])?cat|(^|[^[:alnum:]_./-])dd[[:space:]][^;|&]*count=|^[[:space:]]*(exit|return)([[:space:]]+[0-9]+)?[[:space:]]*;'
pj_defs() { LC_ALL=C awk -v verb="$2" -v token="$3" -v win="$PJ_DRAIN_WINDOW" -v detect="$PJ_DETECT" -v nodrain="$PJ_NODRAIN" "$PJ_DEFS_AWK" "$1"; }
pj_detects() { LC_ALL=C awk -v detect="$PJ_DETECT" -v nodrain="$PJ_NODRAIN" 'BEGIN { exit !(ARGV[1] ~ detect && ARGV[1] !~ nodrain) }' "$1"; }
# pj_collide <awk program text> -> `<function>:<parameter>` per parameter of a `function f(...)` header that is also the name of a function of the same program, wherever that function is
# defined (before or after the header). gawk accepts that (outside --posix), mawk and busybox awk stop on it ("syntax error at or near <name>"), so the guard would pass here and turn
# red on a runner whose awk is mawk. Pure awk (no gawk extension). The program is read as ONE text, so an indented `function` line, two functions on one line and a parameter list that
# continues on the next line are read; the word `function` in a comment or a string followed by a name and a parenthesis is read as a header too (it can only add a report). NOT read: the
# gawk-only keyword `func` (mawk rejects it for its own reason). Run over the program texts (PJ_AWK, PJ_DEFS_AWK) and over fixtures that must and must not collide.
PJ_COLLIDE_AWK='
{ prog = prog " " $0 }
END {
  s = prog
  while (match(s, /(^|[^A-Za-z0-9_])function[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/)) {
    h = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
    sub(/^[^f]*function[ \t]+/, "", h); sub(/[ \t]*\($/, "", h); isfn[h] = 1; nfn++
    pl = s; sub(/\).*$/, "", pl)
    n = split(pl, pa, ","); for (i = 1; i <= n; i++) { w = pa[i]; gsub(/[ \t]+/, "", w); if (w != "") { np++; pf[np] = h; pp[np] = w } }
  }
  for (i = 1; i <= np; i++) if (pp[i] in isfn) print pf[i] ":" pp[i]
  print "FUNCS " nfn
}'
# pj_collide_raw: the collisions, then a last line `FUNCS <n>` (the number of function headers the lint read), so a caller can see that the lint ran over a program and read it. pj_collide: the collisions only.
pj_collide_raw() { printf '%s\n' "$1" | LC_ALL=C awk "$PJ_COLLIDE_AWK"; }
pj_collide() { pj_collide_raw "$1" | { grep -v '^FUNCS ' || true; }; }
PJ_FAIL=0
# pj_judge <pairs>: the table's rows on stdin, one per line. Prints one FAIL line per way the rows disagree with the derived pairs (unlisted
# pair, stale row, duplicate, reason outside the vocabulary, unknown kind). It touches no stub file, so the probe can drive it with fixtures.
# An unlisted pair names the non-test file(s) that derive it, read from the triples in pj_raw (the derivation's third column), so a contributor sees which
# pipe caused it; with no triples for the pair it says so instead of printing an empty list.
pj_judge() {
  local pairs="$1" row s v k r w keys="" vnv="" sorted unl unlj stale dupes p ent
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    IFS='|' read -r s v k r <<<"$row"; pj_trim s; pj_trim v; pj_trim k; pj_trim r
    keys+="$s|$v"$'\n'
    w="${r%%[[:space:]]*}"
    case "$k" in
      drains) ;;
      exempt)
        [[ "$PJ_VOCAB" == *" $w "* ]] \
          || echo "FAIL: exempt row without a vocabulary reason: $s | $v | exempt | ${r:0:60} (reason must be one of:$PJ_VOCAB)"
        # `fenced` is the one word that carries a tracker link: `fenced #<digits> <reason>`, the number the only machine-checked part (a bare `fenced` is a word anyone can type)
        [[ "$w" != fenced || "$r" =~ $PJ_FENCED_RE ]] \
          || echo "FAIL: a fenced exempt row must name its tracker issue: $s | $v | exempt | ${r:0:60} (want: fenced #<digits> <reason>, the reason not empty)"
        # a variable-named-verb row is never stale (the derivation cannot see such a verb), but its suite must still exist
        [[ "$w" == variable-named-verb && -f "$s" ]] && vnv+="$s|$v"$'\n' ;;
      *) echo "FAIL: PRODUCER_JOIN row for $s $v has kind '$k' (want drains or exempt)" ;;
    esac
  done
  sorted="$(LC_ALL=C sort <<<"${keys%$'\n'}")"
  unl="$(LC_ALL=C comm -23 <(printf '%s\n' "$pairs") <(printf '%s\n' "$sorted"))"
  stale="$(LC_ALL=C comm -13 <(printf '%s\n' "$pairs") <(printf '%s\n' "$sorted") | { grep -vxF -f <(printf '%s' "$vnv") || true; })"
  dupes="$(uniq -d <<<"$sorted")"
  if [[ -n "$unl" ]]; then   # ONE awk joins the unlisted pairs (file 1, in order) with the triples (file 2): the producer files of each pair, unique and sorted; no per-pair lookup in bash
    unlj="$(LC_ALL=C awk -F'\t' 'NR == FNR { if ($0 != "") { u[$0] = 1; ord[++n] = $0 } next }
      NF >= 3 { k = $1 "|" $2; if (k in u) { if (k in m) m[k] = m[k] ", " $3; else m[k] = $3 } }
      END { for (i = 1; i <= n; i++) print ord[i] "\t" ((ord[i] in m) ? m[ord[i]] : "") }' <(printf '%s\n' "$unl") <(LC_ALL=C sort -u <<<"${pj_raw-}"))"
  fi
  while IFS=$'\t' read -r p ent; do
    [[ -z "$p" ]] && continue
    echo "FAIL: unlisted pair: ${p%%|*} stubs '${p#*|}' and names a non-test file that pipes text into it (${ent:-producer file not in pj_raw}) — add a PRODUCER_JOIN row: '${p%%|*} | ${p#*|} | drains | <definitions> | <flag token or *>' (drain form: the case line in the FAIL text of a drains row) or an exempt row with a reason from:$PJ_VOCAB"
  done <<<"${unlj-}"
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    echo "FAIL: stale join row: ${p%%|*} | ${p#*|} no longer derives (its stub, its producer or its suite is gone) — delete the row"
  done <<<"$stale"
  [[ -z "$dupes" ]] || echo "FAIL: duplicate PRODUCER_JOIN row(s): ${dupes//$'\n'/ }"
}
# pj_check_rows <pairs>: the PRODUCER_JOIN rows on stdin. Prints one FAIL line per way a `drains` row disagrees with its stubs (malformed row, definition count, a
# definition with no drain keyed on the row's flag), and UNRESOLVED with rc 3 when a row finds no definition at all. It prints and sets nothing else, so
# the probe drives it with fixture rows and the caller merges its output (a verdict neutered to a no-op turns the control red).
# When $2 is the word `counts` its last line is `ROWS-CHECKED <rows read> <drains rows whose stubs were looked up>`: the real run compares both against the table's own
# size (pj_check_counts), so a checker that was fed junk or a slice of the table cannot pass on the strength of a separate loop's count. Without it nothing is added.
pj_check_rows() {
  local pairs="$1" cnt="${2-}" row s v k r d t res f found hint l nrow=0 ndr=0
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    nrow=$((nrow + 1))
    IFS='|' read -r s v k r <<<"$row"; pj_trim s; pj_trim v; pj_trim k; pj_trim r
    [[ "$k" == drains ]] || continue
    IFS='|' read -r d t <<<"$r"
    d="${d//[[:space:]]/}"; pj_trim t
    if [[ ! "$d" =~ ^[1-9][0-9]*$ || -z "$t" ]]; then echo "FAIL: malformed drains row for $s $v: want '<suite> | <v> | drains | <definitions> | <flag token or *>'"; continue; fi
    grep -qxF -- "$s|$v" <<<"$pairs" || continue   # the pair no longer derives: pj_judge reports the stale row, and a finder run would only add noise
    res=""
    for f in "$s" $(pj_sourced "$s"); do res+="$(pj_defs "$f" "$v" "$t")"$'\n'; done
    found=$(grep -c . <<<"$res" || true)
    if (( found == 0 )); then echo "UNRESOLVED: the drains row for $s $v found 0 stub definitions — a definition finder that sees nothing asserts nothing"; return 3; fi
    ndr=$((ndr + 1))
    (( found == d )) || echo "FAIL: $s stubs '$v' in $found definitions, the row pins $d — a definition was added or removed; edit the row and give every definition the drain"
    hint='[ -t 0 ] || timeout 2 cat >/dev/null'; [[ "$t" == "*" ]] || hint="case \" \$* \" in *\" $t \"*) $hint ;; esac"
    while IFS= read -r l; do
      [[ "$l" == no\ * ]] || continue
      echo "FAIL: ${l#no } defines the '$v' stub with no stdin drain keyed on '$t' in its opener line or the next $PJ_DRAIN_WINDOW code lines of the same definition, or a bare exit comes first — a stub that exits unread makes the producer's printf take SIGPIPE/EPIPE under pipefail; start the stub with: $hint"
    done <<<"$res"
  done
  [[ "$cnt" != counts ]] || printf 'ROWS-CHECKED %s %s\n' "$nrow" "$ndr"
}
# pj_check_counts <rows checked> <rows in the table> <drains checked> <drains rows verified>: the checker must have looked at every row and every drains row it
# is credited with. Prints its FAIL line when either differs.
pj_check_counts() {
  { [[ "$1" =~ ^[0-9]+$ && "$3" =~ ^[0-9]+$ ]] && (( $1 == $2 && $3 == $4 )); } \
    || echo "FAIL: the definition checker looked at $1 of the table's $2 rows and $3 of its $4 drains rows — it was fed a slice or something that is not the table, so the drains verdict below would be vacuous"
}
# pj_check_triples <found> <pin>: the producer-triple pin. Prints its FAIL line when the two differ.
pj_check_triples() {
  (( $1 == $2 )) || echo "FAIL: the derivation found $1 (test file, verb, producer file) triples and PJ_TRIPLES pins $2 — a producer of an already-listed pair appeared or went away; re-check the exempt rows of the pairs it feeds (a text-only row may now be an executed pipe), then update PJ_TRIPLES"
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
pj_drain_n=0; pj_exempt_n=0; pj_fenced_n=0; pj_vnv=""; pj_joined=""
for _row in ${PRODUCER_JOIN[@]+"${PRODUCER_JOIN[@]}"}; do
  IFS='|' read -r _s _v _k _r <<<"$_row"; pj_trim _s; pj_trim _v; pj_trim _k; pj_trim _r
  case "$_k" in
    drains)
      IFS='|' read -r _d _t <<<"$_r"
      _d="${_d//[[:space:]]/}"; pj_trim _t
      [[ "$_d" =~ ^[1-9][0-9]*$ && -n "$_t" ]] || continue   # malformed: pj_check_rows reports it
      grep -qxF -- "$_s|$_v" <<<"$pj_pairs" || continue      # stale: pj_judge reports it
      pj_drain_n=$((pj_drain_n + 1)); pj_joined+="JOINED: $_s | $_v | drains | $_d | $_t"$'\n' ;;
    exempt)
      [[ "${_r%%[[:space:]]*}" == variable-named-verb && -f "$_s" ]] && pj_vnv+="$_s|$_v"$'\n'
      [[ "${_r%%[[:space:]]*}" == fenced ]] && pj_fenced_n=$((pj_fenced_n + 1))
      pj_exempt_n=$((pj_exempt_n + 1)); pj_joined+="JOINED: $_s | $_v | exempt | ${_r:0:80}"$'\n' ;;
  esac
done
pj_j="$(printf '%s\n' ${PRODUCER_JOIN[@]+"${PRODUCER_JOIN[@]}"} | pj_judge "$pj_pairs")"
[[ -z "$pj_j" ]] || { PJ_FAIL=1; printf '%s\n' "$pj_j"; }
pj_rc_rc=0
pj_rc_out="$(printf '%s\n' ${PRODUCER_JOIN[@]+"${PRODUCER_JOIN[@]}"} | pj_check_rows "$pj_pairs" counts)" || pj_rc_rc=$?
if (( pj_rc_rc == 3 )); then printf '%s\n' "$pj_rc_out"; exit 3; fi
pj_rc="$(grep -v '^ROWS-CHECKED ' <<<"$pj_rc_out" || true)"
[[ -z "$pj_rc" ]] || { PJ_FAIL=1; printf '%s\n' "$pj_rc"; }
read -r _ pj_chk_rows pj_chk_drains < <(grep '^ROWS-CHECKED ' <<<"$pj_rc_out") || true   # the outer || true is load-bearing (no count line: read returns 1 and the count check below says why); the process substitution's own status is never seen
PJ_FLOOR_DRAINS=22   # the floor on drains rows the checker verified, pinned by value in the wiring check; ratchet it with the table
(( pj_drain_n >= PJ_FLOOR_DRAINS )) || { PJ_FAIL=1; echo "FAIL: the checker verified $pj_drain_n drains rows, the floor is $PJ_FLOOR_DRAINS — a drains row was flipped to exempt, deleted, gone stale (its pair no longer derives) or malformed (the lines above name which), which silences its stub check; restore it, or lower the floor in the same edit with the reason"; }
pj_cc="$(pj_check_counts "${pj_chk_rows-}" "${#PRODUCER_JOIN[@]}" "${pj_chk_drains-}" "$pj_drain_n")"
[[ -z "$pj_cc" ]] || { PJ_FAIL=1; printf '%s\n' "$pj_cc"; }
pj_tc="$(pj_check_triples "$pj_tri_n" "$PJ_TRIPLES")"
[[ -z "$pj_tc" ]] || { PJ_FAIL=1; printf '%s\n' "$pj_tc"; }
printf '%s' "${pj_joined-}"
if (( PJ_FAIL == 0 )); then echo "PASS: grep-q-producer-join ($pj_n derived pairs, $pj_tri_n producer triples; $pj_chk_drains of $pj_drain_n drains rows verified by the checker, $pj_exempt_n exempt rows with a vocabulary reason, $pj_chk_rows of ${#PRODUCER_JOIN[@]} rows read)"; fi
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
pj_jfail=""; pj_jc_n=0
pj_jc() { local want="$1" pairs="$2" out; shift 2; pj_jc_n=$((pj_jc_n + 1)); out="$(printf '%s\n' "$@" | pj_judge "$pairs")"
  if [[ -z "$want" ]]; then [[ -z "$out" ]] || pj_jfail+="[clean table printed: ${out:0:50}]"; else [[ "$out" == *"$want"* ]] || pj_jfail+="[no '$want' for a fixture that must print it]"; fi; }
pj_jc '' 'a.test.sh|v' 'a.test.sh | v | exempt | text-only x'
pj_jc 'unlisted pair' 'a.test.sh|v' ''
pj_raw=$'a.test.sh\tv\tfxprod.sh\na.test.sh\tv\tfxlib.sh\na.test.sh\tother\tfxno.sh' pj_jc 'names a non-test file that pipes text into it (fxlib.sh, fxprod.sh)' 'a.test.sh|v' ''
pj_raw=$'ab.test.sh\tv\tfxx.sh\nb.test.sh\tv\tfxprod.sh' pj_jc 'pipes text into it (fxprod.sh)' 'b.test.sh|v' ''
pj_jc 'stale join row' '' 'a.test.sh | v | exempt | text-only x'
pj_jc 'duplicate PRODUCER_JOIN' 'a.test.sh|v' 'a.test.sh | v | exempt | text-only x' 'a.test.sh | v | exempt | text-only x'
pj_jc 'without a vocabulary reason' 'a.test.sh|v' 'a.test.sh | v | exempt | banana x'
pj_jc '' 'a.test.sh|v' 'a.test.sh | v | exempt | fenced #9217 x'
pj_jc 'must name its tracker issue' 'a.test.sh|v' 'a.test.sh | v | exempt | fenced #9217'
pj_jc 'must name its tracker issue' 'a.test.sh|v' 'a.test.sh | v | exempt | fenced x'
pj_jc 'must name its tracker issue' 'a.test.sh|v' 'a.test.sh | v | exempt | fenced'
pj_jc 'must name its tracker issue' 'a.test.sh|v' 'a.test.sh | v | exempt | fenced #x y'
pj_jc 'must name its tracker issue' 'a.test.sh|v' 'a.test.sh | v | exempt | fenced # y'
pj_jc 'must name its tracker issue' 'a.test.sh|v' 'a.test.sh | v | exempt | fenced #12x y'
pj_jc 'without a vocabulary reason' 'a.test.sh|v' 'a.test.sh | v | exempt | fencedx #9217 x'
pj_jc 'without a vocabulary reason' 'a.test.sh|v' 'a.test.sh | v | exempt | fence #9217 x'
pj_jc 'without a vocabulary reason' 'a.test.sh|v' 'a.test.sh | v | exempt | blocked-#1 x'
pj_jc 'without a vocabulary reason' 'a.test.sh|v' 'a.test.sh | v | exempt | blocked-#9217 x'
pj_jc "has kind 'exemptt'" 'a.test.sh|v' 'a.test.sh | v | exemptt | text-only x'
pj_jc 'stale join row' '' 'ghost.test.sh | v | exempt | variable-named-verb x'
pj_empty_n=$(pj_judge "$pj_pairs" </dev/null | grep -c 'unlisted pair' || true)
# The vocabulary is pinned as the literal word list (nine words; a word added or dropped is an edit of PJ_VOCAB and of this line), and the number of `fenced` rows (the one word that is a tracker link) as a literal: a new
# fenced row is a deliberate edit of this count, so the class "a known live race, acknowledged" cannot grow unseen.
[[ -z "$pj_jfail" && "$pj_empty_n" == "$pj_n" && "$PJ_VOCAB" == ' not-a-command text-only unverified helper-built-stub variable-named-verb pass-through deliberate-fault arm-drain fenced ' && "$pj_fenced_n" == 2 ]] \
  || sweep_probe_fail+=("producer-join-judge: the table verdicts misread their fixtures ${pj_jfail:-none}; the closed vocabulary reads [${PJ_VOCAB}] (want the nine words, ending in fenced); with an empty table ${pj_empty_n:-<err>} of $pj_n derived pairs read as unlisted (want all); the table holds ${pj_fenced_n:-<err>} fenced rows (want 2)")
# The collision lint (P1-1: the local `base` of anybar shadowed `function base`, which gawk takes and mawk rejects): the real programs must be clean, a known collision
# must be found (positive control), a program with distinct names must pass (must-pass control).
# The real programs go through ONE call each, in a loop over their NAMES, and each call's `FUNCS <n>` trailer is counted: a program dropped from the loop, or a call removed, leaves a trailer missing, and a lint that
# read fewer headers than the program's own column-0 `function` lines is red (the lint read the program, not an empty string).
pj_col_raw=""; pj_col_cols=0; pj_col_names=""
for _pn in PJ_AWK PJ_DEFS_AWK; do
  pj_col_names+="$_pn "
  pj_col_raw+="$(pj_collide_raw "${!_pn}")"$'\n'
  pj_col_cols=$((pj_col_cols + $(grep -c '^function' <<<"${!_pn}" || true)))
done
pj_col_real="$(grep -v '^FUNCS ' <<<"$pj_col_raw" | grep . || true)"
pj_col_progs=$(grep -c '^FUNCS ' <<<"$pj_col_raw" || true)
pj_col_read=$(sed -n 's/^FUNCS //p' <<<"$pj_col_raw" | LC_ALL=C awk '{ n += $1 } END { print n + 0 }')
pj_col_pos="$(pj_collide $'function base(p) { return p }\nfunction anybar(l,   rest, base, p) { return l }')"
pj_col_neg="$(pj_collide $'function base(p) { return p }\nfunction anybar(l,   rest, bs0, p) { return l }')"
pj_col_two="$(pj_collide $'function a(x) { return x }\nfunction b(y,   a) { return y }\nfunction c(a) { return a }' | tr '\n' ' ')"
pj_col_shapes="$(pj_collide $'function base(p) { return p }\n    function anybar(l,   base) { return l }')|$(pj_collide $'function base(p) { return p } function anybar(l,   base) { return l }')|$(pj_collide $'function base(p) { return p }\nfunction anybar(l,\n   rest, base) { return l }')|$(pj_collide $'function anybar(l,   base) { return l }\nfunction base(p) { return p }')"
[[ -z "$pj_col_real" && "$pj_col_progs" == 2 && "$pj_col_names" == "PJ_AWK PJ_DEFS_AWK " && "$pj_col_cols" -gt 0 && "$pj_col_read" -ge "$pj_col_cols" && "$pj_col_pos" == "anybar:base" && -z "$pj_col_neg" && "$pj_col_two" == "b:a c:a " \
  && "$pj_col_shapes" == "anybar:base|anybar:base|anybar:base|anybar:base" ]] \
  || sweep_probe_fail+=("awk-param-collision: a function parameter that is also a function name in the derivation or the finder program [${pj_col_real:-none}] (want none: mawk stops on it), read from ${pj_col_progs:-<err>} programs named [${pj_col_names}] (want 2: PJ_AWK PJ_DEFS_AWK) with ${pj_col_read:-<err>} headers against ${pj_col_cols:-<err>} column-0 ones (want at least as many); the known collision read as [${pj_col_pos:-NOTHING}] (want anybar:base), the distinct-name program as [${pj_col_neg:-none}] (want none), two collisions as [${pj_col_two:-none}] (want b:a c:a); an indented header, two functions on one line, a parameter list continued on the next line and a function defined after its use read as [${pj_col_shapes:-NOTHING}] (want anybar:base four times)")
# The same lint over the sweep's two awk programs (they define functions, and mawk stops on a parameter that is also a function name): clean, and read (5 headers).
sw_col_raw="$(pj_collide_raw "$SWEEP_SPLIT_AWK")"$'\n'"$(pj_collide_raw "$SWEEP_FENCE_AWK")"
sw_col_real="$(grep -v '^FUNCS ' <<<"$sw_col_raw" | grep . || true)"
sw_col_read=$(sed -n 's/^FUNCS //p' <<<"$sw_col_raw" | LC_ALL=C awk '{ n += $1 } END { print n + 0 }')
[[ -z "$sw_col_real" && "$sw_col_read" == 5 ]] \
  || sweep_probe_fail+=("sweep-awk-collision: a function parameter that is also a function name in SWEEP_SPLIT_AWK or SWEEP_FENCE_AWK [${sw_col_real:-none}] (want none: mawk stops on it), read ${sw_col_read:-<err>} function headers (want 5: nm, inlist, iscm, flush, close_fence)")
mkdir -p "$probe/pj"
# GUARD 1, the derivation fixture suite. One case table and one loop, run through pj_derive (the call the real run makes) and the shared extension list.
# A case is `name @@ expectations @@ file=text @@ file=text`: each expectation is `y:VERB` (the pair fxa.test.sh|VERB must derive) or `n:VERB` (it must
# not); a file spec writes `text` to `name/file` flat in the case's own directory. The text is a bash $'...' string, so a case line never starts at
# column 0 or with a stub opener, and the placeholders {GT} (a redirect) and {H} (a stub helper) keep this file from reading as a stub itself.
# Every arm of the derivation has a case that must derive and a case that must not (R1 pipe-split / quoted-trailing-bar, R2 wrapper-* / command-v and wrapper-bare, R3 other-producer /
# case-alternation, R4 library-sourced / library-sourcer-no-pipefail, R5a helper-arg1 / helper-other-verb and helper-mid-statement, R5b loop-built / loop-nonverb, R6 one pair
# per extension of PJ_EXTS: `ext-<e>` must derive, `ext-<e>-no-pipefail` must not, and `ext-unlisted` must not, so dropping an extension from PJ_EXTS turns its named case red,
# R7 stub-semicolon / stub-other-verb, R8 annot-pipe-before / annot-pipe-inside and annot-cmdsub-hidden / annot-cmdsub-quoted, the three caps by value (wrapcap-edge-in/out, joinbytes-edge-in/out, joincap-in/out, and what a long line
# keeps: joinbytes-trailing-bar*, joinbytes-middle-dropped), R1 x R3 (r1r3-*; the double-quoted `$(` split over two lines is a pinned MISS), the workflow shell token (yml-shell-bash, its over-read `-e {0}` and its quoted miss), the
# owner named in a trailing comment (a pinned over-read) and a second unlisted extension (ext-unlisted-json)); a new case is one table line and moves the floors below (pj_floor, literals pinned by the wiring check).
# Generated fixture text for the three bounds of the derivation (no literal of this size in the table): a wrapper chain longer than UNWRAPCAP characters, a joined
# line longer than JOINBYTES, and more loops than the loop list holds before it drops the finished ones.
_pj_asg_long=''; for ((_i = 0; _i < 60; _i++)); do _pj_asg_long+='A=1 '; done      # 240 characters
_pj_asg_short=''; for ((_i = 0; _i < 25; _i++)); do _pj_asg_short+='A=1 '; done    # 100 characters
printf -v _pj_pad_big '%9000s' ''; _pj_pad_big="${_pj_pad_big// /a}"               # over JOINBYTES (8192)
printf -v _pj_pad_small '%100s' ''; _pj_pad_small="${_pj_pad_small// /a}"
# THE CAPS ARE PINNED BY VALUE, one fixture just inside and one just outside each (a cap moved by one reds one of the two). UNWRAPCAP: `env`, 47 four-character assignments, one five-character
# assignment and `curl` put the end of the verb at character 200 of the text after the bar (read) or 201 (cut to `cur`: no verb). JOINBYTES: the stub-verb pipe ends exactly at byte 8192 of the logical
# line (the first 8192 bytes are read) or one byte later (cut to `cur`). JOINCAP: the 50th further line is joined (its `|| true` makes the site unobserved), the 51st is not (the site stays observed).
# The loop-list compaction at 32 entries cannot be pinned by value: it drops only finished entries, so no output depends on the threshold (`loop-many` pins that a live loop survives the move).
_pj_cap_in='env '; for ((_i = 0; _i < 48; _i++)); do _pj_cap_in+='A=1 '; done; _pj_cap_in+='curl'                      # 200 characters, the verb ends at the cap
_pj_cap_out='env '; for ((_i = 0; _i < 47; _i++)); do _pj_cap_out+='A=1 '; done; _pj_cap_out+='AB=1 curl'            # 201 characters
printf -v _pj_jb_in '%8177s' ''; printf -v _pj_jb_out '%8178s' ''                                                    # blanks ahead of `printf x | curl`: 15 characters, so the verb ends at byte 8192 or 8193
printf -v _pj_strad '%8190s' ''; _pj_strad=": ${_pj_strad// /a}"                                                    # 2 + 8190 bytes, so a double quote right after it is byte 8193 of the logical line: it straddles the 8192 cut
printf -v _pj_blank70 '%70s' ''                                                                                       # trailing blanks past the 64-character window feed() looks at first
_pj_jc_fill49=''; for ((_i = 0; _i < 49; _i++)); do _pj_jc_fill49+=$'  : \\\n'; done
_pj_jc_fill50="$_pj_jc_fill49"$'  : \\\n'
# 29 loops, then the one that names the verb, then 5 more: the 33rd loop start drops the finished entries while the verb's loop is still live and moves it
_pj_loops=''; for ((_i = 1; _i <= 35; _i++)); do if (( _i == 30 )); then _pj_loops+=$'for vkey in curl; do\n'; else _pj_loops+="for v$_i in zz; do"$'\n'; fi; done
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
  $'comment-between-stages @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x |\n# a comment between the stages\ncurl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'backslash-split @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf \'%s\\n\' \\\n  "$a" | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'backslash-split-bar-first @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | \\\n  curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'quoted-trailing-bar @@ n:curl @@ fxprod.sh=set -o pipefail\necho \'a |\ncurl b\'\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'yaml-block-scalar @@ n:curl @@ fxprod.yml=steps:\n  - shell: bash\n    run: echo ab: |\n      curl a\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.yml\n'
  $'continuation-or-true @@ n:curl @@ fxprod.sh=set -o pipefail\nprintf x \\\n  | curl -K - || true\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'wrapper-timeout @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | timeout 5 curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'wrapper-timeout-k @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | timeout -k 2 5 curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'wrapper-timeout-s @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | timeout -s KILL 5 curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
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
  $'stub-in-sourced @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh=. ./fxstubs.sh\nbash fxprod.sh\n @@ fxstubs.sh=curl() { :; }\n'
  $'loop-built @@ y:curl y:jq @@ fxprod.sh=set -o pipefail\nprintf x | curl -K -\nprintf y | jq .\n @@ fxa.test.sh=for b in curl jq; do\n  printf x {GT} "$d/$b"\ndone\nbash fxprod.sh\n'
  $'loop-nonverb @@ n:curl n:jq @@ fxprod.sh=set -o pipefail\nprintf x | curl -K -\nprintf y | jq .\n @@ fxa.test.sh=for b in curl jq; do\n  printf x {GT} "$d/log"\ndone\nbash fxprod.sh\n'
  $'other-producer @@ y:curl @@ fxprod.sh=set -o pipefail\njq -r .x f | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'other-producer-second-bar @@ y:curl y:tee @@ fxprod.sh=set -o pipefail\njq -r .x f | tee y | curl -K -\n @@ fxa.test.sh=curl() { :; }\ntee() { :; }\nbash fxprod.sh\n'
  $'other-producer-and-amp @@ y:curl @@ fxprod.sh=set -o pipefail\njq -r .x f |& curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'other-producer-status-dropped @@ n:curl @@ fxprod.sh=set -o pipefail\njq -r .x f | curl -K - || true\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'other-producer-wrapped @@ y:curl @@ fxprod.sh=set -o pipefail\njq -r .x f | timeout 5 curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'quoted-bar @@ n:curl @@ fxprod.sh=set -o pipefail\nfoo "a | curl"\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'quoted-bar-single @@ n:curl @@ fxprod.sh=set -o pipefail\nfoo \'a | curl\'\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'case-alternation @@ n:curl @@ fxprod.sh=set -o pipefail\ncase $x in a|curl) :;; esac\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'command-v-any @@ n:curl @@ fxprod.sh=set -o pipefail\nfoo x | command -v curl\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'yaml-list-block-scalar @@ n:curl @@ fxprod.yml=runcmd:\n  - set -o pipefail\n  - |\n    curl -K - x\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.yml\n'
  $'tf-producer @@ y:curl @@ fxprod.tf=resource "x" "y" {\n  command = <<-EOT\n    set -o pipefail\n    printf x | curl -K -\n  EOT\n}\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.tf\n'
  $'ext-bash @@ y:curl @@ fxprod.bash=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.bash\n'
  $'ext-bash-no-pipefail @@ n:curl @@ fxprod.bash=printf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.bash\n'
  $'ext-yml @@ y:curl @@ fxprod.yml=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.yml\n'
  $'ext-yml-no-pipefail @@ n:curl @@ fxprod.yml=printf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.yml\n'
  $'ext-yaml @@ y:curl @@ fxprod.yaml=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.yaml\n'
  $'ext-yaml-no-pipefail @@ n:curl @@ fxprod.yaml=printf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.yaml\n'
  $'ext-tftpl @@ y:curl @@ fxprod.tftpl=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.tftpl\n'
  $'ext-tftpl-no-pipefail @@ n:curl @@ fxprod.tftpl=printf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.tftpl\n'
  $'ext-template @@ y:curl @@ fxprod.template=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.template\n'
  $'ext-template-no-pipefail @@ n:curl @@ fxprod.template=printf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.template\n'
  $'ext-service @@ y:curl @@ fxprod.service=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.service\n'
  $'ext-service-no-pipefail @@ n:curl @@ fxprod.service=printf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.service\n'
  $'ext-tmpl @@ y:curl @@ fxprod.tmpl=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.tmpl\n'
  $'ext-tmpl-no-pipefail @@ n:curl @@ fxprod.tmpl=printf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.tmpl\n'
  $'ext-unlisted @@ n:curl @@ fxprod.txt=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.txt\n'
  $'helper-other-verb @@ n:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh={H} "$d" jq\nbash fxprod.sh\n'
  $'helper-mid-statement @@ n:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh=foo && {H} "$d" curl\nbash fxprod.sh\n'
  $'wrapcap-under @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | env '"$_pj_asg_short"$'curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'wrapcap-over @@ n:curl @@ fxprod.sh=set -o pipefail\nprintf x | env '"$_pj_asg_long"$'curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'joinbytes-under @@ n:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -K - \\\n  '"$_pj_pad_small"$' \\\n  || true\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'joinbytes-over-tail @@ n:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -K - \\\n  '"$_pj_pad_big"$' \\\n  || true\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'joinbytes-middle-dropped @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -K - \\\n  '"$_pj_pad_big"$' \\\n  || true \\\n  '"$_pj_pad_big"$' \\\n  : tail\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'joinbytes-kept-since-squeeze @@ n:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -K - \\\n  '"$_pj_pad_big"$' \\\n  || true \\\n  : tail\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'joinbytes-chain-3 @@ y:jq y:tr @@ fxprod.sh=set -o pipefail\n: '"$_pj_pad_big"$' |\n  jq . |\n  tr a b\n @@ fxa.test.sh=jq() { :; }\ntr() { :; }\nbash fxprod.sh\n'
  $'joinbytes-chain-4 @@ y:jq y:tr y:curl @@ fxprod.sh=set -o pipefail\n: '"$_pj_pad_big"$' |\n  jq . |\n  tr a b |\n  curl -K -\n @@ fxa.test.sh=jq() { :; }\ntr() { :; }\ncurl() { :; }\nbash fxprod.sh\n'
  $'joinbytes-chain-backslash @@ y:jq y:tr @@ fxprod.sh=set -o pipefail\n: '"$_pj_pad_big"$' \\\n  | jq . \\\n  | tr a b\n @@ fxa.test.sh=jq() { :; }\ntr() { :; }\nbash fxprod.sh\n'
  $'joinbytes-two-lines @@ n:curl y:jq @@ fxprod.sh=set -o pipefail\n: '"$_pj_pad_big"$' |\n  jq . \n'"$_pj_jb_out"$'printf x | curl -K - \\\n  : x\n @@ fxa.test.sh=curl() { :; }\njq() { :; }\nbash fxprod.sh\n'
  $'joinbytes-straddle-open @@ n:curl @@ fxprod.sh=set -o pipefail\n'"$_pj_strad"$'"abc \\\n  : x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'joinbytes-straddle-closed @@ y:curl @@ fxprod.sh=set -o pipefail\n'"$_pj_strad"$'"abc \\\n  : x" | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'joinbytes-trailing-bar @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | tr a b | : '"$_pj_pad_big"$' |\n  curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'joinbytes-trailing-bar-quote @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | tr a b | : "'"$_pj_pad_big"$' x" |\n  curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'joinbytes-trailing-bar-squote @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | tr a b | : \''"$_pj_pad_big"$' x\' |\n  curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'join-blanks-bar @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | tr a b |'"$_pj_blank70"$'\n  curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'join-blanks-backslash @@ n:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -K - \\'"$_pj_blank70"$'\n  || true\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'joinbytes-edge-in @@ y:curl @@ fxprod.sh=set -o pipefail\n'"$_pj_jb_in"$'printf x | curl -K - \\\n  : x\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'joinbytes-edge-out @@ n:curl @@ fxprod.sh=set -o pipefail\n'"$_pj_jb_out"$'printf x | curl -K - \\\n  : x\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'joincap-in @@ n:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -K - \\\n'"$_pj_jc_fill49"$'  || true\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'joincap-out @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -K - \\\n'"$_pj_jc_fill50"$'  || true\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'wrapcap-edge-in @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | '"$_pj_cap_in"$' -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'wrapcap-edge-out @@ n:curl @@ fxprod.sh=set -o pipefail\nprintf x | '"$_pj_cap_out"$' -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'annot-cmdsub-hidden @@ n:head @@ fxprod.sh=set -o pipefail\necho "::error::fail $(cat f | head -1)"\n @@ fxa.test.sh=head() { :; }\nbash fxprod.sh\n'
  $'annot-cmdsub-quoted @@ y:grep @@ fxprod.sh=set -o pipefail\necho "::error::n $(printf \'%s\' "$p" | grep -c .) tail"\n @@ fxa.test.sh=grep() { :; }\nbash fxprod.sh\n'
  $'r1r3-any-producer-split @@ y:curl @@ fxprod.sh=set -o pipefail\njq -r .x f |\n  curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'r1r3-cmdsub-split @@ y:curl @@ fxprod.sh=set -o pipefail\nx=$(a \\\n  | curl -K -)\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'r1r3-dq-cmdsub-split-known-miss @@ n:curl @@ fxprod.sh=set -o pipefail\nx="$(a \\\n  | curl -K -)"\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.sh\n'
  $'yml-shell-bash @@ y:curl @@ fxprod.yml=steps:\n  - shell: bash\n    run: printf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.yml\n'
  $'yml-shell-bash-args-overread @@ y:curl @@ fxprod.yml=steps:\n  - shell: bash -e {0}\n    run: printf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.yml\n'
  $'yml-shell-quoted-known-miss @@ n:curl @@ fxprod.yml=steps:\n  - shell: "bash"\n    run: printf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.yml\n'
  $'owner-trailing-comment-overread @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\n: # bash fxprod.sh\n'
  $'ext-unlisted-json @@ n:curl @@ fxprod.json=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.json\n'
  $'loop-sameline-helper @@ y:curl y:jq @@ fxprod.sh=set -o pipefail\nprintf x | curl -K -\nprintf y | jq .\n @@ fxa.test.sh=for b in curl jq; do {H} "$d" $b; done\nbash fxprod.sh\n'
  $'loop-sameline @@ y:curl y:jq @@ fxprod.sh=set -o pipefail\nprintf x | curl -K -\nprintf y | jq .\n @@ fxa.test.sh=for b in curl jq; do printf x {GT} "$d/$b"; done\nbash fxprod.sh\n'
  $'loop-sameline-nonverb @@ n:curl n:jq @@ fxprod.sh=set -o pipefail\nprintf x | curl -K -\nprintf y | jq .\n @@ fxa.test.sh=for b in curl jq; do printf x {GT} "$d/log"; done\nbash fxprod.sh\n'
  $'loop-many @@ y:curl @@ fxprod.sh=set -o pipefail\nprintf x | curl -K -\n @@ fxa.test.sh='"$_pj_loops"$'  printf x {GT} "$d/$vkey"\ndone\nbash fxprod.sh\n'
  $'tf-no-pipefail @@ n:curl @@ fxprod.tf=resource "x" "y" {\n  command = <<-EOT\n    printf x | curl -K -\n  EOT\n}\n @@ fxa.test.sh=curl() { :; }\nbash fxprod.tf\n'
)
# FLOORS. A deleted case, row or spelling is the one edit no check of the table can see, so each table, and each count of what ran, has a floor: an absolute literal, reported with printf and exit
# (not through the helper it backs). pj_floor <name> <floor> <actual> <what is counted>: the literal is written once, in the call, and is the value its message prints; the wiring check pins
# every call by name and literal (a floor lowered to 1, or turned into another floor, is red there). Ratchet the literal, and the wiring entry, in the edit that adds a case, row or spelling.
# The one floor that does not exit is the drains-row floor (it merges into PJ_FAIL like the verdicts around it, and is pinned the same way).
pj_floor() {
  [[ "$3" =~ ^[0-9]+$ ]] && (( $3 >= $2 )) \
    || { printf '%s\n' "FAIL: floor $1: $4 is ${3:-<none>}, the floor is $2 — something was deleted or did not run; restore it, or lower the floor in the same edit with the reason (and in the wiring check's list)"; exit 1; }
}
pj_floor cases 109 "${#PJ_CASES[@]}" "the number of derivation cases in the table"
# pj_split <string>: split on ` @@ ` into the array _pj_f
pj_split() { local s="$1"; _pj_f=(); while [[ "$s" == *' @@ '* ]]; do _pj_f+=("${s%% @@ *}"); s="${s#* @@ }"; done; _pj_f+=("$s"); }
# pj_derive_dir <dir> -> the triples of the files flat in <dir>: the files whose extension is on PJ_EXTS are the file set (the real run's listing pathspec),
# every file is the listing (the basename index).
pj_derive_dir() {
  local d="$1" f e
  local -a sel=()
  : > "$d.lst"
  for f in "$d"/*; do
    f="${f##*/}"; printf '%s\n' "$f" >> "$d.lst"
    for e in $PJ_EXTS; do
      if [[ "$f" == *."$e" ]]; then sel+=("$f"); break; fi
    done
  done
  (( ${#sel[@]} > 0 )) || return 0
  ( cd "$d" && pj_derive "$d.lst" "${sel[@]}" )
}
pj_dfail=""; pj_dy=0; pj_dn=0; pj_cr=0; pj_ey=0; pj_en=0
# pj_expect <case> <y:VERB|n:VERB> <derivation output, a newline before and after>: one expectation of one case. pj_ey and pj_en count the expectations EVALUATED on each side (what the floors read, so a case
# that fails names itself in pj_dfail and is not hidden behind a floor); pj_dy and pj_dn count the ones met.
pj_expect() {
  local hit=n
  [[ "$3" == *$'\n'"fxa.test.sh"$'\t'"${2#*:}"$'\t'* ]] && hit=y
  if [[ "${2%%:*}" == y ]]; then
    pj_ey=$((pj_ey + 1))
    if [[ "$hit" == y ]]; then pj_dy=$((pj_dy + 1)); else pj_dfail+="[$1 must derive ${2#*:}]"; fi
  else
    pj_en=$((pj_en + 1))
    if [[ "$hit" == n ]]; then pj_dn=$((pj_dn + 1)); else pj_dfail+="[$1 must NOT derive ${2#*:}]"; fi
  fi
}
mkdir -p "$probe/pjd"
for _c in "${PJ_CASES[@]}"; do
  pj_cr=$((pj_cr + 1))
  pj_split "$_c"
  _cn="${_pj_f[0]}"; _cd="$probe/pjd/$_cn"; mkdir -p "$_cd"
  for ((_i = 2; _i < ${#_pj_f[@]}; _i++)); do
    _tx="${_pj_f[_i]#*=}"; _tx="${_tx//\{GT\}/>}"; _tx="${_tx//\{H\}/mkstub}"
    printf '%s' "$_tx" > "$_cd/${_pj_f[_i]%%=*}"
  done
  _out=$'\n'"$(pj_derive_dir "$_cd")"$'\n'
  for _x in ${_pj_f[1]}; do pj_expect "$_cn" "$_x" "$_out"; done
done
(( pj_dy > 0 )) || pj_dfail+="[the fixture run derived nothing]"
# What RAN, not only what is declared: every case of the table was read (a loop cut to its first entries reds here), and the expectations evaluated on each side are floored as literals (a loop that
# stops reading its expectations after the first one leaves a count below the floor). Reported directly, like the table floor, not through pj_dfail; a case that fails is named by derivation-fixtures instead.
(( pj_cr == ${#PJ_CASES[@]} )) || { printf '%s\n' "FAIL: the derivation loop read $pj_cr of the table's ${#PJ_CASES[@]} cases"; exit 1; }
pj_floor cases-run 109 "$pj_cr" "the number of derivation cases the loop ran"
pj_floor cases-y 71 "$pj_ey" "the number of must-derive expectations evaluated"
pj_floor cases-n 50 "$pj_en" "the number of must-not-derive expectations evaluated"
# The verdict of each side is given an expectation that must fail it (a must-derive on output without the pair, a must-NOT-derive on output with it), and the record is unwound: a side whose verdict was
# neutered would otherwise count every expectation as met. Reported directly.
pj_ex_save="$pj_dfail"; pj_ex_dy=$pj_dy; pj_ex_dn=$pj_dn; pj_ex_ey=$pj_ey; pj_ex_en=$pj_en; pj_dfail=""
pj_expect ctl-y y:ctlverb $'\n\n'; pj_ex_a="$pj_dfail"; pj_dfail=""
pj_expect ctl-n n:ctlverb $'\nfxa.test.sh\tctlverb\tfxprod.sh\n'; pj_ex_b="$pj_dfail"
pj_dfail="$pj_ex_save"; pj_dy=$pj_ex_dy; pj_dn=$pj_ex_dn; pj_ey=$pj_ex_ey; pj_en=$pj_ex_en
[[ "$pj_ex_a" == '[ctl-y must derive ctlverb]' && "$pj_ex_b" == '[ctl-n must NOT derive ctlverb]' ]] \
  || { printf '%s\n' "FAIL: derivation-fixtures control: an expectation that must fail recorded [${pj_ex_a:-nothing}] for a must-derive on output without the pair and [${pj_ex_b:-nothing}] for a must-NOT-derive on output with it — every case would pass vacuously on that side"; exit 1; }
[[ -z "$pj_dfail" ]] \
  || sweep_probe_fail+=("derivation-fixtures: ${#PJ_CASES[@]} cases through pj_derive; failed: $pj_dfail")
# GUARD 3, the row checks and the triple pin driven with fixtures that must make each verdict print (a verdict neutered to a no-op, or a loop
# that stopped at its first row, must turn this red). pj_check_rows and pj_check_triples are the verdict functions the real run calls.
printf '%s\n' 'curl() {' '  [ -t 0 ] || cat >/dev/null' '}' > "$probe/pj/rc-ok.sh"
printf '%s\n' 'curl() {' '  exit 0' '}' > "$probe/pj/rc-bad.sh"
printf '%s\n' ':' > "$probe/pj/rc-none.sh"
printf '%s\n' 'curl() {' '  cat >/dev/null' '}' 'curl() {' '  cat >/dev/null' '}' > "$probe/pj/rc-two.sh"
pj_rcpairs="$probe/pj/rc-ok.sh|curl"$'\n'"$probe/pj/rc-bad.sh|curl"$'\n'"$probe/pj/rc-none.sh|curl"$'\n'"$probe/pj/rc-two.sh|curl"
pj_rcfail=""; pj_rcc_n=0; pj_tcc_n=0; pj_ccc_n=0; pj_cnt_n=0
pj_rcc() { local want="$1" out; shift; pj_rcc_n=$((pj_rcc_n + 1))
  out="$(printf '%s\n' "$@" | pj_check_rows "$pj_rcpairs" 2>&1)" || true
  if [[ -z "$want" ]]; then [[ -z "$out" ]] || pj_rcfail+="[clean rows printed: ${out:0:60}]"; else [[ "$out" == *"$want"* ]] || pj_rcfail+="[no '$want' for a fixture that must print it: ${out:0:60}]"; fi; }
pj_tcc() { local want="$1" out; pj_tcc_n=$((pj_tcc_n + 1)); out="$(pj_check_triples "$2" "$3" 2>&1)" || true
  if [[ -z "$want" ]]; then [[ -z "$out" ]] || pj_rcfail+="[clean triples printed: ${out:0:60}]"; else [[ "$out" == *"$want"* ]] || pj_rcfail+="[no '$want' for a triple count that must print it: ${out:0:60}]"; fi; }
_rok="$probe/pj/rc-ok.sh | curl | drains | 1 | *"
_rbad="$probe/pj/rc-bad.sh | curl | drains | 1 | *"
_rmal="$probe/pj/rc-ok.sh | curl | drains | x | *"
pj_rcc '' "$_rok"
pj_rcc "stubs 'curl' in 1 definitions, the row pins 2" "$probe/pj/rc-ok.sh | curl | drains | 2 | *"
pj_rcc "stubs 'curl' in 2 definitions, the row pins 1" "$probe/pj/rc-two.sh | curl | drains | 1 | *"
pj_rcc '' "$probe/pj/rc-two.sh | curl | drains | 2 | *"
pj_rcc "defines the 'curl' stub with no stdin drain" "$_rbad"
pj_rcc 'malformed drains row' "$_rmal"
pj_rcc 'malformed drains row' "$_rmal" "$_rbad"
pj_rcc 'with no stdin drain' "$_rmal" "$_rbad"
pj_rcc 'found 0 stub definitions' "$probe/pj/rc-none.sh | curl | drains | 1 | *"
pj_tcc '' 5 5
pj_tcc 'triples and PJ_TRIPLES pins 6' 5 6
pj_tcc 'found 6 (test file, verb, producer file) triples and PJ_TRIPLES pins 5' 6 5
# the row count the checker reports (P1-3): a table read in full reports every row and every drains row; junk or a slice reports fewer
pj_ccc() { local want="$1" out; pj_ccc_n=$((pj_ccc_n + 1)); out="$(pj_check_counts "$2" "$3" "$4" "$5" 2>&1)" || true
  if [[ -z "$want" ]]; then [[ -z "$out" ]] || pj_rcfail+="[clean counts printed: ${out:0:60}]"; else [[ "$out" == *"$want"* ]] || pj_rcfail+="[no '$want' for counts that must print it: ${out:0:60}]"; fi; }
pj_ccc '' 153 153 21 21
pj_ccc 'looked at 1 of the table' 1 153 21 21
pj_ccc 'looked at 153 of the table' 153 153 0 21
pj_ccc 'looked at  of the table' '' 153 '' 21
# both directions: a checker fed the table twice (more rows than the table, more drains rows than it holds) is as wrong as one fed a slice
pj_ccc 'looked at 306 of the table' 306 153 42 21
pj_ccc 'looked at 153 of the table' 153 153 42 21
pj_ccc 'looked at 154 of the table' 154 153 21 21
# pj_cntfx <want> <rows...>: the count line the checker reports for these rows
pj_cntfx() { local want="$1" got; shift; pj_cnt_n=$((pj_cnt_n + 1))
  got="$(printf '%s\n' "$@" | pj_check_rows "$pj_rcpairs" counts 2>&1 | grep '^ROWS-CHECKED ' || true)"
  [[ "$got" == "ROWS-CHECKED $want" ]] || pj_rcfail+="[pj_check_rows reported '$got' for ${#} rows (want 'ROWS-CHECKED $want')]"; }
pj_cntfx '3 2' "$_rok" "$_rbad" "$_rmal"   # three rows of which two are well-formed drains rows
pj_cntfx '1 0' junk                        # one junk row
pj_cntfx '6 4' "$_rok" "$_rbad" "$_rmal" "$_rok" "$_rbad" "$_rmal"   # the same rows fed twice: both counts double, so a count above the table's is reported, not capped
[[ -z "$(printf '%s\n' "$_rok" | pj_check_rows "$pj_rcpairs" 2>&1)" ]] || pj_rcfail+="[pj_check_rows printed a count line without being asked for one]"
# Each fixture driver needs a known-NEGATIVE control, like vp-negative for _vp: a driver that never records a failure would make every fixture above vacuous. Each is run
# once with an input that MUST fail it (a wanted text that cannot appear in OUTPUT THAT IS NOT EMPTY, so a driver weakened from "contains the wanted text" to "printed something" still
# fails its control; a clean expectation for output that cannot be clean), the failure record is unwound, and the result is reported with printf and exit, not through the check it backs.
pj_neg_save="$pj_jfail"; pj_neg_a=""; pj_neg_b=""
pj_jc 'ZZZ-never-printed' 'a.test.sh|v' ''; [[ "$pj_jfail" != "$pj_neg_save" ]] && pj_neg_a+="[pj_jc]"; pj_jfail="$pj_neg_save"
pj_jc '' 'a.test.sh|v' ''; [[ "$pj_jfail" != "$pj_neg_save" ]] && pj_neg_b+="[pj_jc]"; pj_jfail="$pj_neg_save"
pj_neg_save="$pj_rcfail"
pj_rcc 'ZZZ-never-printed' "$_rbad"; [[ "$pj_rcfail" != "$pj_neg_save" ]] && pj_neg_a+="[pj_rcc]"; pj_rcfail="$pj_neg_save"
pj_rcc '' "$_rbad"; [[ "$pj_rcfail" != "$pj_neg_save" ]] && pj_neg_b+="[pj_rcc]"; pj_rcfail="$pj_neg_save"
pj_tcc 'ZZZ-never-printed' 5 6; [[ "$pj_rcfail" != "$pj_neg_save" ]] && pj_neg_a+="[pj_tcc]"; pj_rcfail="$pj_neg_save"
pj_tcc '' 5 6; [[ "$pj_rcfail" != "$pj_neg_save" ]] && pj_neg_b+="[pj_tcc]"; pj_rcfail="$pj_neg_save"
pj_ccc 'ZZZ-never-printed' 1 153 0 21; [[ "$pj_rcfail" != "$pj_neg_save" ]] && pj_neg_a+="[pj_ccc]"; pj_rcfail="$pj_neg_save"
pj_ccc '' 1 153 0 21; [[ "$pj_rcfail" != "$pj_neg_save" ]] && pj_neg_b+="[pj_ccc]"; pj_rcfail="$pj_neg_save"
pj_cntfx '9 9' "$_rok"; [[ "$pj_rcfail" != "$pj_neg_save" ]] && pj_neg_a+="[pj_cntfx]"; pj_rcfail="$pj_neg_save"
[[ "$pj_neg_a" == "[pj_jc][pj_rcc][pj_tcc][pj_ccc][pj_cntfx]" && "$pj_neg_b" == "[pj_jc][pj_rcc][pj_tcc][pj_ccc]" ]] \
  || { printf '%s\n' "FAIL: producer-join-negative-controls: a fixture driver recorded no failure for an input that must fail it (wanted text that cannot appear: [${pj_neg_a:-none}] of [pj_jc][pj_rcc][pj_tcc][pj_ccc][pj_cntfx]; a clean expectation for output that cannot be clean: [${pj_neg_b:-none}] of [pj_jc][pj_rcc][pj_tcc][pj_ccc]) — every fixture it runs would pass vacuously"; exit 1; }
# ROW EXISTENCE: a driver proves it CAN fail, not that its rows are still there. Each driver counts its calls (the negative controls above included), and the counts are floored as literals,
# so a family whose rows were all deleted is red (the controls alone leave two calls per family).
pj_floor judge-fixtures 22 "$pj_jc_n" "the number of pj_jc calls (judge fixtures and controls)"
pj_floor rows-fixtures 11 "$pj_rcc_n" "the number of pj_rcc calls (row-check fixtures and controls)"
pj_floor triple-fixtures 5 "$pj_tcc_n" "the number of pj_tcc calls (triple-pin fixtures and controls)"
pj_floor count-fixtures 9 "$pj_ccc_n" "the number of pj_ccc calls (count-pin fixtures and controls)"
pj_floor rowcount-fixtures 4 "$pj_cnt_n" "the number of pj_cntfx calls (ROWS-CHECKED fixtures and control)"
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
# GUARD 2, the extent of a stub is its own. Each fixture is one bound alone: another verb's opener (crossverb: the first body is never closed), another verb's stub-helper
# call (crosshelp), another verb's heredoc writer (crosshd), the next opener of the SAME verb written as a one-line file write (crossown), the closing brace of the
# function (crossbrace) or of a one-line stub (crossoneline), the heredoc terminator (crossheredoc); and a bare exit or return ahead of the drain disarms it whether it ends in
# a blank (returnfirst), a semicolon (exitsemi), nothing (exitbare) or a same-line cat (sameexit, samereturn). Three must-pass fixtures hold the other side (a logging write
# before the drain is not a bound; a one-line stub is its own extent; an inner brace group closes at a deeper indent than the opener and does not end the function).
# All are read through pj_defs, the finder the rows use.
_lw="  printf x $_gt$_gt \"\$d/args\""   # split so that no line of this file reads as a file written to .../args
_hp=mk; _hp+=stub   # the helper's name, split for the same reason: no line of this file is a stub-helper call
_pw="printf x $_gt \"\$d/"   # a one-line stub write, split like _cw
printf '%s\n' 'curl() {' '  :' 'gh() {' '  cat >/dev/null' '}' > "$probe/pj/crossverb.sh"
printf '%s\n' 'curl() {' '  :' "  $_hp \"\$d\" gh" '  cat >/dev/null' '}' > "$probe/pj/crosshelp.sh"
printf '%s\n' 'curl() {' '  :' "  ${_cw}gh\" <<'EOF'" '  cat >/dev/null' 'EOF' '}' > "$probe/pj/crosshd.sh"
printf '%s\n' "${_pw}curl\"" '  :' "${_pw}curl\"" 'cat >/dev/null' > "$probe/pj/crossown.sh"
printf '%s\n' 'curl() {' '  :' '}' 'cat >/dev/null' > "$probe/pj/crossbrace.sh"
printf '%s\n' "${_cw}curl\" <<'EOF'" ':' 'EOF' 'cat >/dev/null' > "$probe/pj/crossheredoc.sh"
printf '%s\n' 'curl() {' "$_lw" '  cat >/dev/null' '}' > "$probe/pj/logwrite.sh"
printf '%s\n' 'curl() { cat >/dev/null; }' > "$probe/pj/oneline.sh"
printf '%s\n' 'curl() { :; }' 'cat >/dev/null' > "$probe/pj/crossoneline.sh"
printf '%s\n' 'curl() {' '  {' '    :' '  }' '  cat >/dev/null' '}' > "$probe/pj/innerbrace.sh"
printf '%s\n' 'curl() {' '  return 0' '  cat >/dev/null' '}' > "$probe/pj/returnfirst.sh"
printf '%s\n' 'curl() {' '  exit;' '  cat >/dev/null' '}' > "$probe/pj/exitsemi.sh"
printf '%s\n' 'curl() {' '  exit' '  cat >/dev/null' '}' > "$probe/pj/exitbare.sh"
printf '%s\n' 'curl() {' '  exit 0; cat >/dev/null' '}' > "$probe/pj/sameexit.sh"
printf '%s\n' 'curl() {' '  return 0; cat >/dev/null' '}' > "$probe/pj/samereturn.sh"
pj_w_bad="$(for _n in crossverb crosshelp crosshd crossown crossbrace crossheredoc crossoneline returnfirst exitsemi exitbare sameexit samereturn; do pj_defs "$probe/pj/$_n.sh" curl '*' | cut -d' ' -f1 | tr '\n' ' '; echo -n '|'; done)"
pj_w_ok="$(for _n in logwrite oneline innerbrace; do pj_defs "$probe/pj/$_n.sh" curl '*' | cut -d' ' -f1 | tr '\n' ' '; echo -n '|'; done)"
[[ "$pj_w_bad" == "no |no |no |no ok |no |no |no |no |no |no |no |no |" && "$pj_w_ok" == "ok |ok |ok |" ]] \
  || sweep_probe_fail+=("producer-join-window: another verb's opener, stub-helper call or heredoc writer, the next one-line write of the same verb, the closing brace, the heredoc terminator, a bare exit or return (with a blank, a semicolon, nothing or a same-line cat after it) must end a stub's extent or disarm it [${pj_w_bad:-none}] (want crossverb, crosshelp, crosshd, crossown, crossbrace, crossheredoc, crossoneline, returnfirst, exitsemi, exitbare, sameexit, samereturn: no |no |no |no ok |no |no |no |no |no |no |no |no |); a logging write before the drain, a one-line stub and an inner brace group must still read as drains [${pj_w_ok:-none}] (want logwrite, oneline, innerbrace: ok |ok |ok |)")
# pj_sourced, driven over a file that sources a unique library by a relative path, one by a quoted variable path, one that is a comment, one whose name two tracked files
# share (not in the unique list) and itself. The unique list is the function's global, so the fixture sets it for one call.
printf '%s\n' '. ./lib/fxl.sh' '# . ./lib/fxc.sh' 'source "$D/fxm.sh"' '. ./fxdup.sh' ". $probe/pj/src.test.sh" 'echo . ./fxq.sh' > "$probe/pj/src.test.sh"
pj_src_got="$(PJ_UNIQ_SH=$'lib/fxl.sh\nlib/fxm.sh\nlib/fxc.sh\nlib/fxq.sh\n'"$probe/pj/src.test.sh"; pj_sourced "$probe/pj/src.test.sh" | tr '\n' ' ')"
[[ "$pj_src_got" == "lib/fxl.sh lib/fxm.sh " ]] \
  || sweep_probe_fail+=("producer-join-sourced: pj_sourced read [${pj_src_got:-nothing}] from a file that sources a unique library, a quoted variable path, a comment, a shared name, itself and an echo (want [lib/fxl.sh lib/fxm.sh ])")
# THE DYNAMIC CONTROL. A pin reads text; this runs the hazard. The producer writes more than a pipe buffer holds (1 MiB), so a stub
# that exits unread fails the pipeline under pipefail whatever the timing, with SIGPIPE ignored (CI: EPIPE, rc 1) and with the default
# disposition (rc 141); a stub that drains it succeeds. Each spelling runs under the interpreter it is tagged for. Both arrays feed the
# detector too: an accepted spelling must be seen as a drain and a non-reading one must not. An sh-tagged spelling must read the same under dash and under a bash named sh (the rule is at pj_hazard and is checked).
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
  'sh|echo cat >/dev/null'
  'sh|command -v cat >/dev/null'
  'sh|type cat'
  'sh|which cat'
  'sh|dd of=/dev/null count=1'
  'bash|dd of=/dev/null bs=1 count=1'
  'bash|[ -t 1 ] && cat >/dev/null'
  'sh|cat >/dev/null <&-'
  'sh|cat >/dev/null & wait'
  'sh|exit 0; cat >/dev/null'
  'sh|printf cat >/dev/null'
  'sh|command -V cat >/dev/null'
)
# Spellings the DETECTOR must credit although no stub runs them (a lexical neighbour of the word cat, not a reader or a non-reader in any shell that has the word as a command): an identifier that merely ENDS in
# echo, printf or type, followed by cat. PJ_NODRAIN's (echo|printf|type|which|command -v) alternative has a left word boundary, so these stay drains; without it they read as `echo cat`. Not run, so not tagged by a shell.
PJ_DET_EDGE=(
  'det|mytype cat >/dev/null'
  'det|reprintf cat >/dev/null'
  'det|my_echo cat >/dev/null'
)
# ...and the other side of the same boundary: a path-qualified or dotted command word IS the word (`/bin/echo cat` prints, it does not read), so the detector must NOT credit these (detector-only, like the list above: the
# last one is not a command on any host).
PJ_DET_EDGE_BAD=(
  'det|/bin/echo cat >/dev/null'
  'det|/usr/bin/printf cat >/dev/null'
  'det|x.printf cat >/dev/null'
)
# Floors (see pj_floor): a deleted spelling is the one edit no check of the lists can see. The run of every spelling against a real pipe is below; these two only keep the lists from shrinking unseen.
pj_floor drain-ok 9 "${#PJ_DRAIN_OK[@]}" "the number of accepted drain spellings"
pj_floor drain-bad 26 "${#PJ_DRAIN_BAD[@]}" "the number of non-reading spellings"
# pj_hazard <interp> <ignore|default> <spelling> -> the pipeline's exit status under pipefail, on stdout. The interpreters: `bash`; `sh`, which is dash where the host has it (an sh-tagged spelling must not depend on
# which /bin/sh the host has) and /bin/sh otherwise; `shbash`, a bash invoked under the name sh, so in POSIX mode (what /bin/sh is on Arch, Fedora, macOS and in a container without dash; the name is what sets the mode and is pinned by a control below).
# THE RULE FOR AN sh-TAGGED SPELLING: it must read, or not read, the same under dash and under a bash named sh. A spelling whose meaning depends on the shell (a top-level `return`: dash leaves the script, a bash 5 named sh
# exits with status 2 on the error, bash 3.2 named sh reports it and goes on, a bash not named sh goes on) would pass where dash is on PATH and turn the guard red on a host where it is not; the shell-parity check below runs every sh-tagged spelling under a bash named sh as well and requires
# the verdict of its own list (the dash run is the main leg), so such a spelling is red HERE, on whichever host it is added.
PJ_SH="$(command -v dash || true)"; [[ -n "$PJ_SH" ]] || PJ_SH=/bin/sh
PJ_SH_BASH="$probe/pj/sh"; ln -s "$(command -v bash)" "$PJ_SH_BASH"
pj_hazard() {
  local interp="$1" disp="$2" body="$3" stub="$probe/pj/hz-$1.sh" rc=0 runner=""
  if [[ "$interp" == sh || "$interp" == shbash ]]; then
    printf '%s\n' '#!/bin/sh' "$body" 'exit 0' > "$stub"; runner="$PJ_SH"; [[ "$interp" == shbash ]] && runner="$PJ_SH_BASH"
  else printf '%s\n' '#!/usr/bin/env bash' "$body" 'exit 0' > "$stub"; fi
  chmod +x "$stub"
  timeout 20 bash -c 'set -o pipefail; [ "$1" = ignore ] && trap "" PIPE; shift; head -c 1048576 /dev/zero 2>/dev/null | "$@" -K -' _ "$disp" ${runner:+"$runner"} "$stub" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}
# pj_unread <rc>: only EPIPE (1) and SIGPIPE (141) mean "the pipeline failed because the stub never read"; a syntax error, exit 3, a timeout or a missing shell is an instrument fault.
pj_unread() { case "$1" in 1|141) return 0 ;; *) return 1 ;; esac; }
# The four legs of the check of the two spelling lists, each its own function so that each can be given an input that must fail it (the controls below). A leg prints OK when its verdict is the
# wanted one and a bracketed description otherwise; the loops COUNT the OK answers, and the counts are compared with the lists and floored, so a leg that is neutered, or whose answer a loop drops, leaves a count short:
#   dynamic reader     an accepted spelling must make the pipeline succeed        dynamic non-reader   a non-reading spelling must make it fail with EPIPE or SIGPIPE
#   detector reader    the drain detector must see an accepted spelling            detector non-reader  the detector must NOT see a non-reading one
pj_leg_dok()  { if [[ "$(pj_hazard "$1" "$2" "$3")" == 0 ]]; then printf OK; else printf '[%s/%s %s]' "$1" "$2" "$3"; fi; }
pj_leg_dbad() { if pj_unread "$(pj_hazard "$1" "$2" "$3")"; then printf OK; else printf '[%s/%s %s]' "$1" "$2" "$3"; fi; }
pj_leg_tok()  { if pj_detects "$1"; then printf OK; else printf '[accepted spelling not detected: %s]' "$1"; fi; }
pj_leg_tbad() { if pj_detects "$1"; then printf '[non-reading spelling detected as a drain: %s]' "$1"; else printf OK; fi; }
# pj_leg <runs counter> <OK counter> <failure list> <leg function> <args...>: one run of a leg: the run is counted (the floors read these, so a failing spelling is named by its own check and not hidden behind a floor),
# its OK is counted again, anything else is appended to the failure list
pj_leg() { local run="$1" cnt="$2" lst="$3" r; shift 3; printf -v "$run" '%s' "$(( ${!run} + 1 ))"; r="$("$@")"; if [[ "$r" == OK ]]; then printf -v "$cnt" '%s' "$(( ${!cnt} + 1 ))"; else printf -v "$lst" '%s' "${!lst}$r"; fi; }
pj_pipe_ign=0; [[ -n "$(trap -p PIPE)" ]] && pj_pipe_ign=1   # SIGPIPE inherited ignored: the guard was started by a parent that ignores it
pj_dyn_ctl=""; pj_dyn_ok=""; pj_dyn_bad=""; pj_dyn_n=0; pj_n_dok=0; pj_n_dbad=0; pj_n_tok=0; pj_n_tbad=0; pj_r_dok=0; pj_r_dbad=0; pj_r_tok=0; pj_r_tbad=0
pj_unread 141 && pj_unread 1 && ! pj_unread 0 && ! pj_unread 3 && ! pj_unread 124 && ! pj_unread 127 || pj_dyn_ctl+="[pj_unread grades a status it must not]"
[[ "$(pj_hazard bash default 'exit 3')" == 3 ]] || pj_dyn_ctl+="[an exit 3 stub did not surface rc 3]"
# The two dispositions are told apart: a stub that never reads makes the writer fail with rc 1 (EPIPE) where SIGPIPE is ignored (CI) and with rc 141 under the default disposition. pj_unread accepts both, so
# without this a hazard that ignored its disposition argument, or applied one always, would pass every spelling. An ignored SIGPIPE is inherited and cannot be reset from bash, so where THIS guard was started with
# SIGPIPE ignored (a CI runner: `trap -p PIPE` names it, read once above at the probe) the `default` run is ignored too and rc 1 is the right answer for both; rc 141 is asserted only where the guard itself sees SIGPIPE at
# its default. pj_disp_ok is the verdict, given fixtures that must go both ways (the relaxation must not become unconditional), and a child started with SIGPIPE ignored must give rc 1 for `default` (the premise).
pj_disp_ok() { # <rc under ignore> <rc under default> <1 when SIGPIPE was inherited ignored>
  [[ "$1" == 1 ]] || return 1
  if [[ "$3" == 1 ]]; then [[ "$2" == 1 || "$2" == 141 ]]; else [[ "$2" == 141 ]]; fi
}
pj_disp_ign="$(pj_hazard bash ignore ':')"; pj_disp_def="$(pj_hazard bash default ':')"
pj_disp_inh="$( ( trap '' PIPE; pj_hazard bash default ':' ) )"
{ pj_disp_ok 1 141 0 && pj_disp_ok 1 1 1 && pj_disp_ok 1 141 1 && ! pj_disp_ok 1 1 0 && ! pj_disp_ok 141 141 0 && ! pj_disp_ok 141 141 1 && ! pj_disp_ok 1 0 1 && ! pj_disp_ok 1 0 0 && [[ "$pj_disp_inh" == 1 ]]; } \
  || pj_dyn_ctl+="[the disposition verdict misread its fixtures (rc 1 for default is right only where SIGPIPE was inherited ignored), or a child started with SIGPIPE ignored gave rc ${pj_disp_inh:-<none>} for default (want 1)]"
# the probe is cross-checked against the kernel's own record where there is one (Linux: bit 12 of SigIgn is SIGPIPE), so a probe forced either way is red on the host that disagrees
if [[ -r /proc/$$/status ]]; then
  pj_sigign="$(sed -n 's/^SigIgn:[[:space:]]*//p' /proc/$$/status)"
  [[ "$pj_sigign" =~ ^[0-9a-fA-F]+$ ]] && (( ((16#${pj_sigign: -4}) >> 12 & 1) == pj_pipe_ign )) || pj_dyn_ctl+="[the SIGPIPE probe (trap -p PIPE: $pj_pipe_ign) disagrees with SigIgn ${pj_sigign:-<none>} of /proc/$$/status]"
fi
pj_disp_ok "$pj_disp_ign" "$pj_disp_def" "$pj_pipe_ign" || pj_dyn_ctl+="[an unread stub did not give rc 1 under an ignored SIGPIPE and rc $( ((pj_pipe_ign)) && echo '1 or 141 (SIGPIPE was inherited ignored)' || echo 141) under the default disposition: $pj_disp_ign and $pj_disp_def]"
# each leg is given an input that must fail it, or its verdict could be neutered unseen
[[ "$(pj_leg_dok sh default ':')" != OK ]] || pj_dyn_ctl+="[the dynamic reader leg passed a stub that never reads]"
[[ "$(pj_leg_dbad sh default 'cat >/dev/null')" != OK ]] || pj_dyn_ctl+="[the dynamic non-reader leg passed a stub that drains]"
[[ "$(pj_leg_tok ':')" != OK ]] || pj_dyn_ctl+="[the detector reader leg accepted a line that drains nothing]"
[[ "$(pj_leg_tbad 'cat >/dev/null')" != OK ]] || pj_dyn_ctl+="[the detector non-reader leg accepted a drain as a non-reader]"
[[ "$(pj_leg_dok sh default 'cat >/dev/null')" == OK && "$(pj_leg_dbad sh default ':')" == OK && "$(pj_leg_tok 'cat >/dev/null')" == OK && "$(pj_leg_tbad ':')" == OK ]] \
  || pj_dyn_ctl+="[a leg did not answer OK for the input it must pass]"
for _d in ignore default; do
  for _i in sh bash; do [[ "$(pj_hazard "$_i" "$_d" ':')" != 0 ]] || pj_dyn_ctl+="[$_i/$_d control stub exited unread and the pipeline still succeeded]"; done
  for _e in ${PJ_DRAIN_OK[@]+"${PJ_DRAIN_OK[@]}"}; do
    pj_dyn_n=$((pj_dyn_n + 1)); pj_leg pj_r_dok pj_n_dok pj_dyn_ok pj_leg_dok "${_e%%|*}" "$_d" "${_e#*|}"
  done
  for _e in ${PJ_DRAIN_BAD[@]+"${PJ_DRAIN_BAD[@]}"}; do
    pj_dyn_n=$((pj_dyn_n + 1)); pj_leg pj_r_dbad pj_n_dbad pj_dyn_bad pj_leg_dbad "${_e%%|*}" "$_d" "${_e#*|}"
  done
done
pj_det_bad=""
for _e in ${PJ_DRAIN_OK[@]+"${PJ_DRAIN_OK[@]}"} ${PJ_DET_EDGE[@]+"${PJ_DET_EDGE[@]}"}; do pj_leg pj_r_tok pj_n_tok pj_det_bad pj_leg_tok "${_e#*|}"; done
for _e in ${PJ_DRAIN_BAD[@]+"${PJ_DRAIN_BAD[@]}"} ${PJ_DET_EDGE_BAD[@]+"${PJ_DET_EDGE_BAD[@]}"}; do pj_leg pj_r_tbad pj_n_tbad pj_det_bad pj_leg_tbad "${_e#*|}"; done
# The shell-parity rule (above), run: every sh-tagged spelling gives the verdict of its own list under a bash named sh as well (the dash run is the leg above), under both dispositions; counted like the legs. Its control is a
# spelling that differs between the shells, run under the bash only (so the control does not depend on the host having dash): `return 0; cat >/dev/null` must NOT read as a non-reader there, and the status says WHICH
# bash it is: 2 where a bash named sh is in POSIX mode and exits on the failed `return` (bash 5), 0 for bash 3.2, which goes on (the name sh is pinned: a bash with another name goes on, rc 0, on every version, so a renamed symlink is red on bash 5).
pj_ret_rc="$(pj_hazard shbash default 'return 0; cat >/dev/null')"
[[ "$(pj_leg_dbad shbash default 'return 0; cat >/dev/null')" != OK && "$(pj_leg_dbad shbash default ':')" == OK && ( "$pj_ret_rc" == 2 || ( "${BASH_VERSINFO[0]}" -lt 4 && "$pj_ret_rc" == 0 ) ) ]] \
  || pj_dyn_ctl+="[a bash named sh gave rc ${pj_ret_rc:-<none>} for a top-level return before a drain (want 2, or 0 on bash 3.2) or did not tell it from a stub that never reads]"
pj_shp_bad=""; pj_shp_ok=0; pj_shp_run=0; pj_shp_run_a=0; pj_shp_run_b=0; pj_sh_tagged=0
for _e in ${PJ_DRAIN_OK[@]+"${PJ_DRAIN_OK[@]}"}; do
  [[ "${_e%%|*}" == sh ]] || continue
  pj_sh_tagged=$((pj_sh_tagged + 1))
  for _d in ignore default; do pj_leg pj_shp_run_a pj_shp_ok pj_shp_bad pj_leg_dok shbash "$_d" "${_e#*|}"; done
done
for _e in ${PJ_DRAIN_BAD[@]+"${PJ_DRAIN_BAD[@]}"}; do
  [[ "${_e%%|*}" == sh ]] || continue
  pj_sh_tagged=$((pj_sh_tagged + 1))
  for _d in ignore default; do pj_leg pj_shp_run_b pj_shp_ok pj_shp_bad pj_leg_dbad shbash "$_d" "${_e#*|}"; done
done
[[ -z "$pj_dyn_ctl" ]] \
  || sweep_probe_fail+=("producer-hazard-control: the control did not reproduce the failure: $pj_dyn_ctl — the guard would otherwise certify a hazard it cannot produce")
[[ -z "$pj_dyn_ok" ]] \
  || sweep_probe_fail+=("producer-drain-accepted: accepted drain spellings that did not make the pipeline succeed: $pj_dyn_ok")
[[ -z "$pj_dyn_bad" && -z "$pj_det_bad" ]] \
  || sweep_probe_fail+=("producer-drain-nonreading: non-reading spellings that made the pipeline succeed: ${pj_dyn_bad:-none}; detector disagreements: ${pj_det_bad:-none}")
(( pj_dyn_n == 2 * (${#PJ_DRAIN_OK[@]} + ${#PJ_DRAIN_BAD[@]}) && ${#PJ_DRAIN_OK[@]} > 0 && ${#PJ_DRAIN_BAD[@]} > 0 \
   && pj_n_dok == 2 * ${#PJ_DRAIN_OK[@]} && pj_n_dbad == 2 * ${#PJ_DRAIN_BAD[@]} && pj_n_tok == ${#PJ_DRAIN_OK[@]} + ${#PJ_DET_EDGE[@]} && pj_n_tbad == ${#PJ_DRAIN_BAD[@]} + ${#PJ_DET_EDGE_BAD[@]} )) \
  || sweep_probe_fail+=("producer-drain-zero: ${pj_dyn_n:-<err>} spelling runs for ${#PJ_DRAIN_OK[@]} accepted and ${#PJ_DRAIN_BAD[@]} non-reading spellings, and the four legs ran ${pj_n_dok:-<err>} / ${pj_n_dbad:-<err>} / ${pj_n_tok:-<err>} / ${pj_n_tbad:-<err>} times (want two dispositions each for the dynamic legs, one run each for the detector legs, and neither list empty — zero spellings ran is never a pass)")
pj_shp_run=$((pj_shp_run_a + pj_shp_run_b))
[[ -z "$pj_shp_bad" && "$pj_sh_tagged" -gt 0 && "$pj_shp_run" == $((2 * pj_sh_tagged)) && "$pj_shp_ok" == "$pj_shp_run" ]] \
  || sweep_probe_fail+=("producer-shell-parity: an sh-tagged spelling does not give its list's verdict under a bash named sh (it differs between dash and bash): ${pj_shp_bad:-none}; ${pj_shp_ok:-<err>} listed verdicts in ${pj_shp_run:-<err>} runs for ${pj_sh_tagged:-<err>} sh-tagged spellings (want two runs per spelling, all as listed, and at least one spelling) — retag it, reword it, or drop it: it would turn the guard red on a host with no dash")
# The legs, floored as literals (reported directly): neutering a leg, or cutting its loop, leaves a count below the floor.
pj_floor leg-dyn-ok 18 "$pj_r_dok" "the number of dynamic accepted-spelling runs"
pj_floor leg-dyn-bad 52 "$pj_r_dbad" "the number of dynamic non-reading-spelling runs"
pj_floor leg-det-ok 12 "$pj_r_tok" "the number of detector accepted-spelling runs"
pj_floor leg-det-bad 29 "$pj_r_tbad" "the number of detector non-reading-spelling runs"
# each of the two shell-parity loops (accepted list, non-reading list) is floored on its own runs: deleting one leaves the other's count equal to its own tagged count and passes the comparison above
pj_floor shell-parity-ok 12 "$pj_shp_run_a" "the number of shell-parity runs of the accepted sh-tagged spellings"
pj_floor shell-parity-bad 38 "$pj_shp_run_b" "the number of shell-parity runs of the non-reading sh-tagged spellings"
# pj_floor itself is driven (a floor function that always passed would make every floor above a no-op): below its floor, or with no count, it prints its FAIL line and exits 1; at the floor it is silent and returns 0.
pj_fl_rc=0; pj_fl_lo="$( ( pj_floor ctl 5 4 'a count' ) 2>&1 )" || pj_fl_rc=$?
pj_fl_none="$( ( pj_floor ctl 5 '' 'a count' ) 2>&1 )" || true
pj_fl_eq="$( ( pj_floor ctl 5 5 'a count' ) 2>&1 )" && pj_fl_eq_rc=0 || pj_fl_eq_rc=$?
[[ "$pj_fl_rc" == 1 && "$pj_fl_lo" == 'FAIL: floor ctl: a count is 4, the floor is 5'* && "$pj_fl_none" == 'FAIL: floor ctl: a count is <none>'* && -z "$pj_fl_eq" && "$pj_fl_eq_rc" == 0 ]] \
  || sweep_probe_fail+=("producer-floor-control: pj_floor exited ${pj_fl_rc:-<err>} below its floor (want 1) printing [${pj_fl_lo:0:80}], printed [${pj_fl_none:0:80}] for no count, and [${pj_fl_eq:0:80}] with rc ${pj_fl_eq_rc:-<err>} at its floor (want silence and 0)")

# Return wiring. The sweep's return code reaches this suite's exit status through statements the probe rows above do not exercise: the capture and
# the fold at the top level (adjacent, unindented, once each), the probe verdict gate below, and a single exit. Each pinned pattern is anchored to
# the whole statement at column 0 on a non-comment line, so a mention in a comment or in a message string (this check's own) cannot satisfy it,
# and an indented copy inside a dead branch or a function does not count. A sweep that never ran by any route (an unindented dead branch
# included) is caught separately: SWEEP_N, set only by sweep_main, must hold a swept-file count. Statements that can still reach the exit (an
# inserted assignment or `exit` or a trap between these pins and the gate, a deleted direct block, an `exit` ahead of the pins) are not pinned
# here: the guard cannot defend its own control flow beyond these text pins, and a diff that edits it is reviewed.
_code=$(grep -vE '^[[:space:]]*#' "$_self" || true)
wire_a=$(grep -cE '^sweep_main \. "\$SWEEP_FLOOR" "\$SWEEP_MD_FLOOR" "\$SWEEP_MD_FENCE_FLOOR" "\$SWEEP_SPLIT_FLOOR" \|\| sweep_rc=\$\?[[:space:]]*$' <<<"$_code" || true)
wire_b=$(grep -cE '^sweep_fold "\$sweep_rc"[[:space:]]*$' <<<"$_code" || true)
wire_adj=$(grep -A1 -E '^sweep_main \. "\$SWEEP_FLOOR" "\$SWEEP_MD_FLOOR" "\$SWEEP_MD_FENCE_FLOOR" "\$SWEEP_SPLIT_FLOOR" \|\| sweep_rc=\$\?[[:space:]]*$' <<<"$_code" | grep -cE '^sweep_fold "\$sweep_rc"[[:space:]]*$' || true)
[[ "$wire_a" == 1 && "$wire_b" == 1 && "$wire_adj" == 1 ]] \
  || sweep_probe_fail+=("return-wiring: unindented capture ${wire_a:-<err>}, fold ${wire_b:-<err>}, capture immediately followed by the fold ${wire_adj:-<err>} (want exactly 1 each). This protects the path by which the sweep verdict reaches this suite's exit status. Expected, at column 0 and once each: 'sweep_main . \"\$SWEEP_FLOOR\" \"\$SWEEP_MD_FLOOR\" \"\$SWEEP_MD_FENCE_FLOOR\" \"\$SWEEP_SPLIT_FLOOR\" || sweep_rc=\$?' directly followed by 'sweep_fold \"\$sweep_rc\"'. Fix: restore the statement; if it moved legitimately, update this pin, not the sweep")
# The verdict gate and the final exit are pinned the same way, but they report DIRECTLY (FAIL and exit 1 below, just ahead of the gate): a failure
# appended to sweep_probe_fail is read by that very gate, so a gate edited to always pass would silence its own pin.
# The producer-join verdict sinks: the judge, the row checks and the triple pin each print their FAIL lines into a variable that ONE column-0 statement merges into
# PJ_FAIL (so a neutered assignment or merge prints nothing, or prints and still exits 0), and a single column-0 fold turns the flag into the suite verdict.
# Each assignment and each merge is pinned; the verdict functions themselves are driven by the producer-join-verdicts and producer-join-judge controls above.
wire_pjn=$(grep -cE '^\[\[ -z "\$pj_j" \]\] \|\| \{ PJ_FAIL=1; ' <<<"$_code" || true)
wire_pjj=$(grep -cE '^pj_j="\$\(printf .%s\\n. .*[|] pj_judge "\$pj_pairs"\)"[[:space:]]*$' <<<"$_code" || true)
wire_pjr=$(grep -cE '^\[\[ -z "\$pj_rc" \]\] \|\| \{ PJ_FAIL=1; ' <<<"$_code" || true)
wire_pjrr=$(grep -cE '^pj_rc_out="\$\(printf .%s\\n. \$\{PRODUCER_JOIN\[@\]\+"\$\{PRODUCER_JOIN\[@\]\}"\} \| pj_check_rows "\$pj_pairs" counts\)" \|\| pj_rc_rc=\$\?[[:space:]]*$' <<<"$_code" || true)
wire_pjrs=$(grep -cE '^pj_rc="\$\(grep -v .\^ROWS-CHECKED . <<<"\$pj_rc_out" \|\| true\)"[[:space:]]*$' <<<"$_code" || true)
wire_pjc=$(grep -cE '^\[\[ -z "\$pj_cc" \]\] \|\| \{ PJ_FAIL=1; ' <<<"$_code" || true)
wire_pjcc=$(grep -cE '^pj_cc="\$\(pj_check_counts "\$\{pj_chk_rows-\}" "\$\{#PRODUCER_JOIN\[@\]\}" "\$\{pj_chk_drains-\}" "\$pj_drain_n"\)"[[:space:]]*$' <<<"$_code" || true)
wire_pjt=$(grep -cE '^\[\[ -z "\$pj_tc" \]\] \|\| \{ PJ_FAIL=1; ' <<<"$_code" || true)
wire_pjtt=$(grep -cE '^pj_tc="\$\(pj_check_triples "\$pj_tri_n" "\$PJ_TRIPLES"\)"[[:space:]]*$' <<<"$_code" || true)
wire_pjg=$(grep -cE '^\(\( PJ_FAIL == 0 \)\) \|\| FAIL=1[[:space:]]*$' <<<"$_code" || true)
# The floors report DIRECTLY (pj_floor: printf and exit), like the gate below, except the drains-row floor, which merges into PJ_FAIL beside the verdicts it follows and is pinned as such. WIRE_FLOORS lists every
# pj_floor call by NAME, LITERAL and MEASURED ARGUMENT: each must appear at column 0 exactly once with that literal and that count expression (so a floor lowered to 1, turned into another floor, deleted or duplicated is red here), and no other pj_floor call
# may exist. The list is a second place on purpose: a floor is ratcheted by editing the call and its entry together.
WIRE_FLOORS=(
  'cases 109 "${#PJ_CASES[@]}"' 'cases-run 109 "$pj_cr"' 'cases-y 71 "$pj_ey"' 'cases-n 50 "$pj_en"' 'drain-ok 9 "${#PJ_DRAIN_OK[@]}"' 'drain-bad 26 "${#PJ_DRAIN_BAD[@]}"'
  'judge-fixtures 22 "$pj_jc_n"' 'rows-fixtures 11 "$pj_rcc_n"' 'triple-fixtures 5 "$pj_tcc_n"' 'count-fixtures 9 "$pj_ccc_n"' 'rowcount-fixtures 4 "$pj_cnt_n"'
  'leg-dyn-ok 18 "$pj_r_dok"' 'leg-dyn-bad 52 "$pj_r_dbad"' 'leg-det-ok 12 "$pj_r_tok"' 'leg-det-bad 29 "$pj_r_tbad"'
  'shell-parity-ok 12 "$pj_shp_run_a"' 'shell-parity-bad 38 "$pj_shp_run_b"'
)
# each entry is the call up to its message: name, literal AND the measured argument, so a floor cannot be satisfied by an expression that does not count what its name says
wire_flr_lines="$(grep '^pj_floor ' <<<"$_code" || true)"
wire_flr_bad=""
for _fl in "${WIRE_FLOORS[@]}"; do
  _fn=0
  while IFS= read -r _l; do [[ "$_l" == "pj_floor $_fl "* ]] && _fn=$((_fn + 1)); done <<<"$wire_flr_lines"
  [[ "$_fn" == 1 ]] || wire_flr_bad+=" ${_fl%% *}"
done
wire_flr_n=$(grep -cE '^pj_floor [a-z-]+ [0-9]+ ' <<<"$_code" || true)
wire_flr_fn=$(grep -cE '^pj_floor\(\) \{[[:space:]]*$' <<<"$_code" || true)
wire_pjf=$(grep -cE '^\(\( pj_drain_n >= PJ_FLOOR_DRAINS \)\) \|\| \{ PJ_FAIL=1; echo .*\$PJ_FLOOR_DRAINS' <<<"$_code" || true)
wire_pjfv=$(grep -cE '^PJ_FLOOR_DRAINS=22([[:space:]]|$)' <<<"$_code" || true)
wire_pjq=$(grep -cE '^read -r _ pj_chk_rows pj_chk_drains < <\(grep .\^ROWS-CHECKED . <<<"\$pj_rc_out"\) \|\| true([[:space:]]|$)' <<<"$_code" || true)
wire_neg=$(grep -cE '^  \|\| \{ printf .%s\\n. "FAIL: producer-join-negative-controls' <<<"$_code" || true)
[[ "$wire_pjn" == 1 && "$wire_pjj" == 1 && "$wire_pjr" == 1 && "$wire_pjrr" == 1 && "$wire_pjrs" == 1 && "$wire_pjc" == 1 && "$wire_pjcc" == 1 && "$wire_pjt" == 1 && "$wire_pjtt" == 1 && "$wire_pjg" == 1 \
   && -z "$wire_flr_bad" && "$wire_flr_n" == "${#WIRE_FLOORS[@]}" && "$wire_flr_fn" == 1 && "$wire_pjf" == 1 && "$wire_pjfv" == 1 && "$wire_pjq" == 1 && "$wire_neg" == 1 ]] \
  || sweep_probe_fail+=("producer-join-wiring: the pj_judge merge ${wire_pjn:-<err>} and its assignment ${wire_pjj:-<err>}, the row-check merge ${wire_pjr:-<err>} and its assignment, which must feed the whole table and ask for the counts ${wire_pjrr:-<err>}, the strip of the count line ${wire_pjrs:-<err>}, the read of the count line ${wire_pjq:-<err>}, the row-count merge ${wire_pjc:-<err>} and its assignment ${wire_pjcc:-<err>}, the triple-pin merge ${wire_pjt:-<err>} and its assignment ${wire_pjtt:-<err>}, the column-0 fold into FAIL ${wire_pjg:-<err>}, the floors not at column 0 with their listed literal exactly once [${wire_flr_bad:-none}] (${wire_flr_n:-<err>} pj_floor calls against ${#WIRE_FLOORS[@]} listed, ${wire_flr_fn:-<err>} definitions of pj_floor), the drains-row floor ${wire_pjf:-<err>} and its value ${wire_pjfv:-<err>} and the negative-control exit ${wire_neg:-<err>} (want 1 each, at column 0)")
wire_gate=$(grep -cE '^if \(\( \$\{#sweep_probe_fail\[@\]\} == 0 \)\); then[[:space:]]*$' <<<"$_code" || true)
wire_exit=$(grep -cE '^exit "\$FAIL"[[:space:]]*$' <<<"$_code" || true)
wire_else=$(grep -B1 -E '[e]cho "FAIL: the derived sweep.s own probe is broken' <<<"$_code" | grep -cE '^  FAIL=1[[:space:]]*$' || true)
wire_exit1=$(grep -A2 -E '[e]cho "FAIL: the derived sweep.s own probe is broken' <<<"$_code" | grep -cE '^  exit 1([[:space:]]|$)' || true)
# The reader pattern has ONE home (Item F): a single column-0 assignment of PATTERN_V2, read by the sweep (and so by both linearisers' output), and
# neither linearising pass names a pattern at all. A private copy, or the old PATTERN, in a pass would read a V2-only spelling as clean; the must-report
# cases above that use a V2-only spelling (split-sudo, md-env-i) are what see a narrower copy at run time, and this row names the structure.
ps_n=$(grep -c '^PATTERN_V2=' <<<"$_code" || true)
ps_sweep="$(declare -f scan_sweep _scan_sweep_c)"   # the wrapper that sets the locale and the function it calls
ps_lin="$(declare -f scan_split scan_md)"
ps_reads=no; [[ "$ps_sweep" == *PATTERN_V2* ]] && ps_reads=yes
ps_old=no; [[ "$ps_sweep" == *'"$PATTERN"'* ]] && ps_old=yes
ps_priv=no; [[ "$ps_lin" == *PATTERN* ]] && ps_priv=yes
[[ "$ps_n" == 1 && "$ps_reads" == yes && "$ps_old" == no && "$ps_priv" == no ]] \
  || sweep_probe_fail+=("pattern-single-source: PATTERN_V2 is assigned ${ps_n:-<err>} times at column 0 (want 1), scan_sweep reads it: $ps_reads (want yes), scan_sweep names the old PATTERN: $ps_old (want no), a linearising pass names a pattern: $ps_priv (want no)")

# A probe check that is DELETED cannot fail, so the number of checks is pinned: every check above ends in
# `|| sweep_probe_fail+=(...)` (or `&& ...` for a negative control), so the count of NON-COMMENT lines carrying that tail is the count
# of checks (the pin's own line included); comment lines are excluded, so rewording a comment can neither hide a deletion nor trip the pin,
# and the append is counted only where an `||` or `&&` operator immediately precedes it, so a bare tail with no operator cannot stand in for
# a deleted check (a decoy that fabricates a whole `|| sweep_probe_fail+=(` line is an edit of the probe itself, which review reads).
SWEEP_PROBE_CHECKS=81
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
