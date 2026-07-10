---
title: "Making a copy-then-sign publish non-blocking: a sign-failure is NOT a clean miss"
date: 2026-07-09
category: best-practices
tags: [ci, supply-chain, cosign, zot, registry, non-blocking, fallback, observability]
issue: 6274
pr: TBD
---

# Learning: a sign-failure in a non-blocking copy-then-sign publish defeats a pull-side "absence" fallback

## Problem

#6274 made the GHCR→zot mirror step non-release-blocking (`continue-on-error: true`
+ an `exit 0` inner shell + bounded retry + a `mirror_status=degraded` signal), so a
transient `connection reset` mid blob-upload no longer reds a successful release. The
step does two things per release: **(1)** `crane copy` each tag GHCR→zot, then **(2)**
`cosign sign` the zot digest once. The first implementation wrapped BOTH in a single
`degraded()` handler that exits 0 on any failure with one remediation hint.

The two failure modes are **not equivalent**, and treating them identically shipped a
latent post-cutover boot-block:

- `crane copy` failure → the image is **ABSENT** from zot → a clean *miss*. The host's
  `pull_image_with_fallback` (ci-deploy.sh) gets a zot pull miss and **atomically falls
  back to GHCR**. Safe.
- `cosign sign` failure (after the copies already landed) → the image is **PRESENT BUT
  UNSIGNED** in zot. This is NOT a miss: post-cutover the host's `docker pull zot_ref:TAG`
  **succeeds** (present), so `IMAGE` is reassigned to the zot ref and the GHCR fallback is
  **never taken**; `verify_image_signature` then returns `unsigned` → enforce-mode
  **hard-blocks the boot**. The GHCR fallback cannot rescue it because the fault is a
  verify failure, not a pull miss.

The single `degraded()` hint also told the operator to "backfill via `crane copy`" — but
`crane copy` re-mirrors the blob and does **not** re-sign, so following the hint leaves
the copy present-but-unsigned and never clears the fault.

## Solution

Split the failure handling so the sign-failure carries its own accurate semantics:

- Parameterize `degraded()` with a remediation `$2`; make the DEFAULT remediation include
  `cosign sign` (every backfill must re-sign — a bare `crane copy` never writes the
  signature referrer).
- On `cosign sign` failure specifically, pass a distinct warning that (a) names the
  present-but-unsigned state, (b) gives an exact re-sign command, and (c) states the
  post-cutover boot-block consequence.
- Amend the ADR to name BOTH post-cutover boot-gating shapes (missing vs
  present-but-unsigned) instead of conflating them under "miss".

## Key Insight

**When you make a multi-step publish (copy-then-sign, upload-then-checksum,
write-then-index) non-blocking, enumerate each step's failure mode against the
DOWNSTREAM consumer's fallback contract — do not collapse them into one "degraded"
bucket.** A pull-side / read-side fallback that keys on **absence** (miss → use the other
source) is silently defeated by a **present-but-invalid** artifact (present → used →
fails a later integrity gate with no fallback left). The dangerous step is the one that
runs *after* the artifact becomes visible but *before* it becomes valid. The remediation
string is part of the contract: it must actually clear the specific fault, not the
generic one.

Corollary (observability): a green release that leaves a present-but-invalid secondary
artifact is a **latent** failure — loud at the moment it's created (Slack/`::warning::`),
silent until a future consumer trips it. Keep the create-time signal loud AND make sure a
pre-cutover gate (here: `zot-entry-gate.sh` / soak gate) re-checks the invariant before
the consumer's fallback is retired.

## How this was caught

`security-sentinel`, prompted to trace the exit-0 change through to the host consumer
(`apps/web-platform/infra/ci-deploy.sh`), surfaced it as P2. A correctness/pattern lens
alone (`pattern-recognition-specialist`) verified the shell logic was internally correct
and did NOT surface it — the defect lived in the seam between the workflow's exit-0
semantics and the host's fallback contract, a different file. This is the
"feature-wiring composition bug" class: module A (workflow) correct, module B (host pull)
correct, A+B violate an invariant that lives in B's fallback logic. The review-spawn
prompt naming the downstream consumer explicitly is what reached it.

## Session Errors

1. **Planning subagent hit the API session limit (resets 4pm Europe/Paris).** —
   Recovery: partial-artifact recovery — the plan + `tasks.md` were on disk; committed
   them (`3509a6df3`) and resumed at the work phase. — Prevention: none needed; one-shot's
   Step 1-2 partial-artifact recovery path handled it as designed. External/transient.
2. **`tasks.md` Write failed (`File has not been read yet`) after an earlier commit.** —
   Recovery: Read the file, then Write. — Prevention: covered by
   `hr-always-read-a-file-before-editing-it` (re-read after compaction). One-off.
3. **AC1 `grep -c 'continue-on-error: true'` returned +2, not the plan's +1.** — Cause: an
   explanatory comment contained the literal counted string. Recovery: reworded the comment
   to drop `: true`. — Prevention: known class
   ([[2026-06-17-grep-assertion-over-script-body-false-matches-own-comments]]) — a plan AC
   that greps a bare literal collides with explanatory comments naming that literal.
4. **Plan AC4 (`actionlint … exit 0`) was infeasible — `actionlint` already exits 1 on
   `origin/main`.** — Recovery: re-derived the realistic bar (0 new shellcheck notes, 0
   error-severity; CI does not run actionlint). — Prevention: plan-quoted AC verify commands
   are preconditions to re-derive against baseline, not facts (work-phase Phase 1 guidance).
5. **First-pass impl treated `cosign sign` failure identically to a `crane copy` miss (the
   subject of this learning).** — Recovery: split the handler + accurate remediation +
   ADR fix (`1b8162dce`). — Prevention: this learning; routed to the review defect-class
   catalogue.
