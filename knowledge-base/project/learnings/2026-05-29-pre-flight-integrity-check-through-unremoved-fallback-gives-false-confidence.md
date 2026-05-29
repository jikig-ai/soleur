---
title: "A pre-flight integrity check that reads through a not-yet-removed fallback path gives false confidence — the post-mutation check is the only reliable guard"
date: 2026-05-29
category: review-patterns
module: flag-set-role
tags: [code-review, cross-reconciliation, flagsmith, eval-verify, migration-safety, reviewer-suggestion-validation]
issue: 4617
pr: 4619
---

# Pre-flight integrity check through an unremoved fallback gives false confidence

## Problem

PR #4619 (#4617) added `flip.sh --detach-shared`: it removes a feature's override
on the legacy shared `org-targeted` Flagsmith segment in both envs, then **post-detach**
eval-verifies the feature still resolves `enabled=true` for a member org (now served by
its own `<flag>-orgs` segment) and `enabled=false` for a control org.

Multi-agent review produced two plausible-sounding P2/P3 suggestions. Both were **rejected**
after cross-reconciliation against the actual migration topology — applying either would
have shipped a false-confidence guard or a contract that conflicts with reality.

## The two rejected suggestions (and why)

1. **"Add a pre-flight eval-verify (member enabled=true) BEFORE the detach POST, to refuse
   before damage instead of detecting after."** (pattern-recognition P2)
   - **Why rejected:** Pre-detach, the member evaluates `enabled=true` via the shared
     `org-targeted` override *regardless of whether `<flag>-orgs` was provisioned*. A
     pre-flight check therefore PASSES in exactly the dangerous case (member served only by
     the shared segment, per-feature segment not provisioned) — it reads through the fallback
     it's about to remove. Only the **post-detach** eval is reliable: once the shared override
     is gone, just `<flag>-orgs` can serve the member, so a drop is observable. security-sentinel
     (orthogonal) independently affirmed the post-detach design as sound — two-of-three.

2. **"Reject the synthetic-default `--control-org` for the detach verb; force a real sibling
   org so the leak check is meaningful."** (user-impact P3, optional)
   - **Why rejected:** Both real orgs in the shared segment (jikigai + sibling) are **members**
     that must STAY enabled. There is no real *non-member* sibling sitting in `org-targeted` to
     leak to. The synthetic non-member UUID is the *correct* control here (a guaranteed
     non-member). Forcing a "real sibling" control would conflict with the topology and break
     the legitimate run. Kept the existing warning instead.

## Key Insight

- **A pre-flight integrity check is only as good as the path it reads through.** When the
  mutation you're about to make removes a redundant/fallback source (a shared override, a
  dual-write sibling, a cached value), a *before* check that the redundant source still
  satisfies cannot prove the *after* state. Put the load-bearing assertion AFTER the mutation,
  where only the intended source can satisfy it. Recovery from an after-detected failure is the
  idempotent re-provision; the after-check catches the real failure that the before-check masks.
- **Reviewer suggestions must be validated against the actual data topology, not applied
  mechanically.** "Use a real control org" is good generic advice for the `--org` provisioning
  path (where the control is a genuine other org), but wrong for a detach where every real org
  is a member. Cross-reconcile a single-agent suggestion against an orthogonal agent's verdict
  and the concrete topology before fixing (per the review skill's cross-reconcile-triad rule).

## Prevention / How to apply

- When reviewing or designing a "remove a redundant source, then verify" operation, ask: *would
  the verification still pass if the thing I'm removing were never replaced?* If yes, the check
  belongs AFTER the removal, not before.
- Before applying a reviewer's "add a pre-flight guard" suggestion, trace which sources satisfy
  the guard's assertion at guard time. If a soon-to-be-removed source is one of them, the guard
  is vacuous.

## Session Errors

1. **`Edit` on `server.ts` rejected with "File has not been read yet."** Content had been viewed
   via `Bash` (`sed`), not the `Read` tool. **Recovery:** `Read` the file, then Edit succeeded.
   **Prevention:** already enforced by `hr-always-read-a-file-before-editing-it` — Bash output
   does not satisfy the Read-before-Edit gate; only the `Read` tool does. One-off, no new rule.

## Tags
category: review-patterns
module: flag-set-role
