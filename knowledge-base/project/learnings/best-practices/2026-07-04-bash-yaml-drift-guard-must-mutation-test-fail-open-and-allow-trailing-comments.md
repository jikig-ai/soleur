---
title: "Bash YAML drift-guards must mutation-test the fail-OPEN direction and treat structural anchors as comment-tolerant"
date: 2026-07-04
category: best-practices
module: ci-workflows
tags: [drift-guard, bash, awk, github-actions, fail-open, test-authoring, mutation-test]
issue: 6018
pr: 6019
---

# Bash YAML drift-guards must mutation-test the fail-OPEN direction and treat structural anchors as comment-tolerant

## Problem

While fixing #6018 (the *Version Bump and Release* workflow concluding
`startup_failure` because the plugin caller of `reusable-release.yml` never
granted the `id-token: write` its reusable `release` job requires), I added a
drift-guard test — `plugins/soleur/test/reusable-release-caller-permissions.test.sh`
— asserting **every** caller of the reusable workflow grants `id-token: write`
to its calling job.

The first version passed 4/4 on the real tree AND satisfied the author-run
negative test (remove `id-token` → FAIL). It looked done. Multi-agent review
(`pattern-recognition-specialist` + `test-design-reviewer`, independently
concurring) found it could pass GREEN while the invariant was violated:

1. **Trailing-comment job header → fail-open.** The awk job-boundary regex
   `^  [A-Za-z0-9_-]+:[[:space:]]*$` requires the line to end right after the
   colon. `  release: # the release job` is legal YAML but is NOT recognised as
   a new job, so its lines append to the *previous* job's buffer. A prior job's
   `id-token: write` then satisfies the caller's check — green while the actual
   calling job grants nothing (the exact #6018 defect the guard exists to catch).
2. **Grep scoped to the whole job, not the `permissions:` sub-block → fail-open.**
   An `id-token: write`-shaped line under `with:`/`env:` would satisfy the check
   even though no permission was granted.
3. Minor: an unanchored workflow-level fallback grep matched a commented-out
   `# id-token: write`; only the first calling job per file was checked; the
   remote (`owner/repo/...@ref`) `uses:` form was not enumerated.

## Solution

Harden the extractors (single-file, all fail-open closed):

- Match job headers with an **optional trailing comment**:
  `^  [A-Za-z0-9_-]+:[[:space:]]*(#.*)?$` — the `(#.*)?` tail is load-bearing.
- Scope the id-token check to the job's `permissions:` **sub-block** (indent
  deeper than the 4-space key, up to the next 4-space key), not the whole job.
- Classify inline `permissions:` forms (`write-all`, flow-mapping
  `{id-token: write}`) so a job broadened to inline perms is not mis-read.
- Check **every** calling job per file; enumerate both `./…` and `…@ref` forms;
  `^`-anchor every `id-token` grep so a comment never satisfies a check.

Then **mutation-test the fail-OPEN direction explicitly** — not just "remove the
grant → FAIL", but "inject the exact shapes that would let a broken caller pass":
a trailing-comment header with the grant only in a prior job; the grant moved
under `with:`; inline `write-all` (must still PASS, fail-safe). Run each against
a scratch mirror of `.github/workflows/`.

## Key Insight

A static drift-guard's own **GREEN is only trustworthy if you've proven it goes
RED on the fail-OPEN inputs**, not merely on the obvious "delete the thing" input.
A guard that greps structured config (YAML/TOML/HCL) has two silent-pass vectors
its author rarely tests:

1. **Structural anchors must be comment-tolerant.** Any regex that recognises a
   boundary (`^job:`, `^  key:`, a block delimiter) will silently mis-parse when
   a human adds a legal trailing `# comment` — and mis-parse usually means
   *merge two units and bleed one's property into the other* = fail-open.
2. **Assertions must be scoped to the sub-structure they claim to check**, not a
   whole-block grep — the target literal can appear in an adjacent, irrelevant
   key.

The cheap gate is a mutation harness that copies the config tree, injects each
fail-open shape, and asserts the guard reports RED. The author-run "remove the
line → FAIL" negative test is necessary but **not** sufficient; it only exercises
the denied-and-detected path, never the present-but-mis-parsed path.

Same family as [[2026-06-12-source-scan-containment-gate-call-detection-and-fail-closed-lexing]]
(regex-not-lexer, proxy-not-behavior fail-open classes) and
[[2026-06-29-bash-accumulate-then-exit-gate-test-three-footguns]] (verify-the-verifier),
extended to YAML-structural drift guards.

## Session Errors

1. **iac-routing-ack hook rejected the plan's first write** because the prose
   contained the literal token `doppler secrets set` while asserting it was NOT
   used. **Recovery:** rephrased to "Doppler secret writes" + added the
   `iac-routing-ack` ack comment. **Prevention:** one-off — when negating a
   gated literal in prose, paraphrase the token rather than quoting it.
2. **Plan AC1's `grep -A6 '^  release:' | grep -c 'id-token: write'` returns 0**
   because the 6-line rationale comment pushes `id-token` past the window.
   **Recovery:** re-derived with `-A9`; the drift-guard test is the authoritative
   invariant. **Prevention:** already covered — plan-quoted AC verify commands
   are preconditions to re-derive, not facts; a comment block ahead of the
   asserted line invalidates a hardcoded `-AN` window.
3. **Drift-guard test shipped fail-open in its first version** (trailing-comment
   header + whole-job grep). **Recovery:** hardened the extractors + added a
   3-shape mutation harness. **Prevention:** this learning — mutation-test the
   fail-OPEN direction for any static config drift-guard, and make structural
   anchors comment-tolerant.
4. **shellcheck SC2034** on a doc-only variable after inlining its regex.
   **Recovery:** removed the dead variable, kept the rationale as a comment.
   **Prevention:** one-off.
