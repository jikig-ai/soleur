---
title: "A gate's own documentation satisfied the gate's test, and my probe for it was also wrong"
date: 2026-07-21
category: test-failures
module: plugins/soleur/skills/preflight
issue: 6772
pr: 6811
tags: [vacuous-tests, anchoring, fail-open, mutation-testing, measurement]
---

# Learning: the Sharp Edge explaining a control satisfied the test asserting the control

## Problem

#6772: preflight Check 10's Form A parser mis-read a folded YAML scalar (`command: >-`)
as the literal `>-`, which then tripped the check's own shell-active-token reject. The
check FAILed without ever running the probe, and blamed a nonexistent shell injection.

The fix is small. What made this PR expensive is that **fixing the parser is a fail-open
transition**: commands that previously failed to parse (and were therefore rejected) now
parse correctly and reach `bash -c` against the operator's ambient production credentials.
Measured: 4 corpus plans would flip reject→execute, all `doppler run -c prd_terraform`.
`env -i` does not scrub the token, because it is file-backed and `$HOME` is preserved.

## What review found that the implementation missed

Three P1s, two of them in the control the PR shipped as its own justification:

**1. The `!mode` guard was missing from the awk.** The TS mirror gated all three `command:`
rules behind `mode === null`; the awk did not. So a continuation line beginning `command:`
re-triggered the inline rule mid-fold:

    awk => [curl -fsS https://app.soleur.ai/apibar]      truncated AND concatenated
    TS  => [curl -fsS https://app.soleur.ai/api command: bar]

Under the awk-wins contract, production silently executes a corrupted command the mirror
never models. The awk's own header claimed *"No key-name matching is used"* — false, because
the inline rule IS a key-name match that survived inside the scalar.

**2. The credentialed-CLI reject was bypassable by intra-word quoting.** `"doppler"`,
`\doppler`, `dopp""ler`, `dop'p'ler` all executed. Bash resolves every one to the same
binary; the `(^|[[:space:]]|/)` anchors cannot see through quote characters. Correctly
rejected already: `/usr/bin/doppler`, `env doppler`, `DOPPLER_TOKEN=x doppler`. Fixed by
matching a dequoted COPY — never the string that executes.

**3. The test asserting the newline reject was already dead.**

## Key Insight

> **A gate's own documentation must not be able to satisfy the gate's test.**

`expect(skill).toMatch(/\$'\\n'/)` grepped the WHOLE SKILL.md. The literal `$'\n'` appears
four times: the executable Step 10.5 reject, an unrelated Check, prose about `sanitize()`,
and — decisively — a **Sharp Edge added by this very PR to explain the reject**. Deleting
the real alternative from the executable gate left the suite green. The moment a task
requires both "assert X" and "document X", a whole-file grep for X collides with itself.

This is `cq-assert-anchor-not-bare-token`, and it recurred *inside a PR that added the
documentation which broke it*. The documentation and the assertion were written in the
same change and never tested against each other.

The fix is a **line-window slice around the executable line** (`if [[ "$CMD…" =~`), not a
whole-file grep. I tried fence-pairing first and it failed differently but just as
silently: inline backticks in prose misalign the pairing, so `/```[a-z]*\n[\s\S]*?```/`
matched 50 blocks and **zero** containing either gate — a matcher that finds nothing reads
exactly like a matcher that finds nothing wrong.

## Solution

- `!mode` guard on all three awk `command:` rules; header claim made true.
- Dequoted copy (`CMD_DEQ`) for the verb match, mirrored via `dequote()` in TS.
- Both wiring assertions rescoped to a line-window; mutation-verified RED in both
  directions (delete `|$'\n'` → 1 fail; revert `CMD_DEQ` → 1 fail).
- Probe stdout removed from the Step 10.8 GitHub-issue body — `sanitize()` strips only C0
  controls, the repo is PUBLIC, and this PR creates the stdout population that reaches it.
- The denylist is now described as a denylist: wrapper indirection (`bash scripts/foo.sh`
  that self-wraps `doppler run -c prd`) is NOT caught, and the durable fix is a probe-verb
  allowlist (#6815).

## Session Errors

- **My first vacuity probe counted the wrong form.** I counted `|$'\n'` (the piped
  alternative, 1 occurrence) while the test greps the unpiped `$'\n'` (4 occurrences), and
  briefly concluded the reviewer's finding was wrong. **Prevention:** when checking whether
  an assertion is vacuous, count the EXACT string the assertion matches, not the string you
  edited.
- **A `python` regex replacement silently replaced 0 occurrences while printing success.**
  **Prevention:** always assert the substitution count (`assert n == 1`) or `diff -q`
  against a pristine backup; never trust a script that prints its own success.
- **A fence-pairing helper matched 50 blocks and 0 gates.** **Prevention:** prefer an
  anchor on the executable line over structural pairing in markdown; verify any new slice
  helper returns non-empty before asserting against it.
- **An edit left a stray `; then`, producing invalid bash inside a skill.** **Prevention:**
  extract the edited block and `bash -n` it — SKILL.md bash is real runtime and nothing
  else type-checks it.
- **Two implementation subagents died mid-run** (API stall / connection closed), leaving
  unverified edits on disk. **Prevention:** treat a dead agent's on-disk output as
  UNVERIFIED — `git status` + mutation-test what landed before committing, per the existing
  contaminated-session rule. Here F1 had landed correctly and was confirmed by mutation
  before commit.
- **The code-quality review agent died**, losing its numeric claim-verification.
  **Prevention:** re-derive the load-bearing numbers directly rather than treating a missing
  agent as a pass.

## Related

- [[2026-07-21-my-fixture-set-had-a-direction-and-both-batteries-were-blind-to-the-other-one]]
  — the sibling PR the same day; there every fixture pointed one direction, here the
  assertion's own documentation satisfied it. Same root: the test names a property it does
  not pin.
- [[2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr]]
  — anchoring on syntax, not tokens.
- #6815 — deferred: allowlist redesign, Form B fallthrough, empty-stdout false-green.
