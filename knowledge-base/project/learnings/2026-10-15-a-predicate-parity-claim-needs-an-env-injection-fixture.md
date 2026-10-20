---
title: "A predicate-parity claim needs an env-injection fixture, not just fixture-class agreement"
date: 2026-10-15
category: workflow-patterns
issue: 10383
pr: 10386
---

# A predicate-parity claim needs an env-injection fixture, not just fixture-class agreement

## What happened

PR #10386 (bare-root CWD marker) inlined the same three-term config-FILE
predicate into `.claude/hooks/bare-root-cwd-guard.sh` and
`git-repo-readiness-diag.sh`, claiming parity and pinning it with a
behavioral test that ran both producers over five fixture classes (bare /
plain / masked / symlinked `.git` / non-repo). Review (A-P2) falsified the
claim in one check: the guard unsets `GIT_DIR` family before evaluating,
the diag arm did not — so `GIT_DIR=<plain-clone>` at a real bare root made
`--is-inside-work-tree` true in the diag's pre-gate and silently suppressed
the marker while the guard fired.

## The rule

When two copies of a predicate are claimed to agree, the parity suite must
cover the **environment** axis, not only the filesystem-shape axis. Env-
sensitive probes (`git rev-parse --is-inside-work-tree`,
`--is-bare-repository`) read the inherited env; a `GIT_*` location var is an
injection vector exactly because hooks/test fixtures legitimately carry
them. Scrub inside the arm (never script-top if the outer verdict is
env-intentional) and add an env-injection shape to the parity loop.

Companion defect found the same review: a loader shape filter documented as
"accepts only the documented shape" checked only line 1 and forwarded the
rest verbatim — the allowlist-a-message-class-must-rebuild-it class already
codified in the repo, re-shipped. Grep for the claim's mechanism (prefix
test on `${OUT%%\n*}` covers line 1 only) before writing "accepts only"
into a comment or README.

## Detect

- `git -C <fixture> rev-parse --is-inside-work-tree` answers differently
  under `GIT_DIR=<other>` — that IS the measurement.
- A parity test that iterates fixture *classes* but never mutates the env
  pins shape-parity only; name it that, or add the env row.
