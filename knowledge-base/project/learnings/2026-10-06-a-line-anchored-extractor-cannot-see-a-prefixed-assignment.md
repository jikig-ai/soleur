# Learning: a line-anchored extractor cannot see a prefixed assignment — and a docs paraphrase of a probe is a probe

## Problem

#9612 normalized sixteen silent/bare `EXISTING=$(gh issue list …)` dedupe sites
to an explicit fail-open diagnostic. The first shape chosen was the one the
plan called out — `if ! EXISTING="$(gh …)"; then echo "::error::…"; EXISTING=""; fi`.
CI then failed in three places none of the targeted suites could see:

1. `watchdog-workflow-idempotence.test.ts` extracts tracker lookups with the
   line-start anchor `^\s*EXISTING="?\$\(gh issue list ` and then EXECUTES each
   captured line verbatim in a stubbed bash. The `if !` prefix both hid all 16
   sites from the extractor (anti-vacuity floor: expected ≥17, found 1) and —
   had it matched — would have left an unterminated `if` for the standalone
   exec. The fix is not a different policy; it is a different spelling of the
   same policy: `EXISTING=$(gh …) || { echo "::error::…"; EXISTING=""; }` — the
   `||` suppresses the `set -e` abort identically, the assignment stays at line
   start, and the line remains a complete statement.
2. `components.test.ts` scans markdown prose for `gh … --search` probes and
   demands `--state` + `-L/--limit`. The SKILL.md paraphrase of the new
   #7255 probe (`gh pr list --search head:ci/vendor-attest --state all`) carried
   no `--limit` and was flagged — doc text describing a command is itself part
   of the executable-surface corpus.
3. `guard-vacuity-floor` builds a mutant by slicing the floor `if`..`fi` and
   walking BACKWARD over contiguous simple assignments to bind operands. The
   new suite's `TOTAL=$((PASS+FAIL))` and `MIN_ASSERTIONS` were bound 200+
   lines away, outside the widening, so the slice died `set -u` and scored
   CONSTRUCTION — pushing the unconstructible set one past its ratchet. The
   floor operands must sit on contiguous assignment lines directly above the
   `if`.
4. The same suite's `_MIN_ALWAYS_ON_DECLARED` ratchet is `floor = count − 5`
   pinned in test-all.sh AND three places in test-all-affected.test.sh;
   adding two ALWAYS_ON suites without moving the floor fails `f1`.

## Solution

- Fail-open dedupe sites spelled `VAR=$(cmd) || { diag; VAR=""; }` — same
  semantics, extractor-visible.
- SKILL.md prose carries the probe's full argv (`--state all --limit 10`).
- Floor operands rebound contiguously above the `if`; floor literal pinned to
  `GH_ARGV_LINT_MIN_ASSERTIONS` env override + literal default.
- `_MIN_ALWAYS_ON_DECLARED` 141 → 143 (count 148 − 5) in runner + both test
  pins.

## Session Errors

1. Initial sentinel test asserted 29 assertions against a `MIN_ASSERTIONS=34`
   floor — FAIL. **Prevention:** count `pass|fail` call sites before setting
   the literal; the floor is a pinned number, derive it.
2. `gh issue create` refused twice by the filing gates (missing `--milestone`,
   then missing a filing exit). **Prevention:** read the refusal's three exits;
   meta/machinery + milestone are both required for machinery findings.
3. `deploy-script-tests` leg RED on `cutover-inngest-workflow.test.sh` with
   `printf: write error: Broken pipe` at rc=1, 7s in — a SIGPIPE flake, not an
   assertion failure; the suite passes 1000/1000 locally.
   **Prevention:** distinguish a suite's RED-by-assertion from RED-by-signal;
   the artifact log's last line is the discriminator.
4. `workspaces-luks-verify-workflow.test.sh` g3 mutation anchors initially
   used workflow-level indentation; the harness dedents `marker.sh` before
   extracting. **Prevention:** mutation anchors must be written against the
   EXTRACTED body indentation, not the workflow's.

## Prevention (recurring rules)

- When a test extracts statements by a line-start regex AND executes them,
  prefer `X=$(…) || { …; }` over `if ! X=$(…); then …; fi` — the former is a
  complete one-line statement with the same fault semantics.
- Any prose in a scanned surface (markdown or yaml) that quotes a `gh …
  --search` command is a probe for components.test.ts: carry `--state` and
  `-L` in the quote or mark it as the query's `$(…)` by another mechanism.
- New assertion floors: bind every operand on contiguous assignment lines
  directly above the `if`, and emit the failure on stderr with a word from
  the sentinel vocabulary (`FAILED:` suffices).

Follow-up filed for residual same-class sites outside #9612's enumeration:
#9659.
