---
title: A prefix-strip security-fix regression guard is vacuous unless the LAUNDERED target is resolvable
date: 2026-07-05
category: test-failures
module: apps/web-platform/server/context-queries-hook.ts
tags: [testing, security, vacuous-red, bash-to-ts-port, byte-parity]
pr: 6046
issue: 6046
---

## Problem

PR #6046 ported the CLI bash hook `.claude/hooks/skill-context-queries.sh` to an
in-process TS hook. The security-critical fix (deepen-plan finding F1) is that the
model-controlled skill name must be stripped with an **anchored** `startsWith("soleur:")`
strip, NOT `lastIndexOf(":")` — the latter launders `other:plugin` → `plugin`, past the
namespace-isolation gate.

The first-draft regression test asserted `call({ skill: "other:plugin" })` returns `{}`.
`pr-test-analyzer` flagged it P1 **non-discriminating**: under the *buggy* `lastIndexOf(":")`
strip, `other:plugin` launders to `plugin`, and because **no fixture skill named `plugin`
existed**, gate #2 (SKILL.md realpath/existence) returned `{}` anyway. So the test passed
under BOTH the correct anchored strip (colon fails the `^[a-z0-9-]+$` charset) AND the buggy
strip (laundered `plugin` skill doesn't exist) — the explicit guard for a CONFIRMED-high
security fix could not catch a regression of that fix.

## Solution

Add a fixture skill literally named `plugin` that resolves a real committed artifact, then
make the test discriminate: (a) assert `{ skill: "plugin" }` resolves (proves the laundered
target IS reachable — the precondition that makes the guard non-vacuous), and (b) assert
`{ skill: "other:plugin" }` still returns `{}`. Now the buggy `lastIndexOf` strip would
resolve `plugin`'s artifact and emit a note → the `toEqual({})` assertion fails; the correct
anchored strip keeps the colon → charset gate → `{}` → passes.

## Key Insight

A regression test for a **normalizer/strip/prefix-mangle security fix** (namespace strip,
path canonicalization, allowlist key derivation) is only discriminating if the fixture makes
the LAUNDERED / mis-normalized target **resolvable to an observable effect**. If the
downstream gate rejects the laundered value for an *unrelated* reason (nonexistent target,
missing row, absent file), the test passes identically with and without the fix — the
classic vacuous-RED trap, one hop downstream. Litmus: "under the buggy implementation, does
this input produce a DIFFERENT observable output than under the correct one?" If not, the
guard is decorative.

Corollary for **bash→TS ports**: a cross-language byte-parity test over a *shared committed
fixture* is the highest-value guard, but its shape coverage must exercise **every**
hand-maintained note fragment (each skip reason: `(capped at N matches)`, `(symlink)`,
`(escapes knowledge-base)`, `<out-of-tree query> (rejected)`), not just the happy/0-resolved
shapes — otherwise half the replicated literals can drift shell↔TS undetected. Four review
agents (pattern, architecture, code-quality, test-design) independently converged on this
coverage gap.

## Session Errors

- **Bash CWD drift** — `./node_modules/.bin/vitest` and a `grep` invocation failed with
  "No such file or directory" because a prior `cd <worktree-root> && git commit` left the
  shell CWD at the worktree root, not `apps/web-platform`. Recovery: prefix each Bash call
  with `cd <abs> &&`. **Prevention:** already covered by the work skill's rule to chain
  `cd <worktree-abs-path> && <cmd>` in a single Bash call; the Bash tool persists the last
  `cd` across calls, so a compound `cd` to a different dir silently relocates subsequent
  bare-relative commands.
