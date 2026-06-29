---
title: Promoting a path-filtered check to REQUIRED makes its detect-changes anchors part of the security contract
date: 2026-06-29
category: integration-issues
tags: [ci, github-actions, required-checks, fail-open, tenant-isolation, path-filter, branch-protection]
issue: 5585
pr: 5688
---

# Required-check anchors must cover the VERIFIED surface, not the inherited `on.paths`

## Problem

`.github/workflows/tenant-integration.yml` (the dev-Supabase tenant-isolation
suite — the only live verification that one founder's JWT cannot read another's
rows) was path-filtered and **not required**, so a red run did not block merges
(the gap that let #5582 sit red on main). #5585 made it a required check via the
always-run aggregator gate-job pattern (a `detect-changes` job + an `if: always()`
`tenant-integration-required` job whose fail-closed verdict is registered in the
Terraform ruleset) — see ADR-032.

The shim's verdict logic was correct and well-tested. The latent fail-open was
**one layer up, in the `detect-changes` anchor set** — and it was invisible until
multi-agent review (`user-impact-reviewer`, fired by the `single-user incident`
threshold) checked the anchors against the surface the suite *actually verifies*.

## Key Insight

**Once a path-filtered check is REQUIRED, a GREEN result is an authoritative
certification ("isolation verified"), not a silent skip. Its change-detection
anchors therefore become part of the security contract — and an anchor set
narrower than the verified surface produces a false-authoritative-GREEN, which is
strictly WORSE than the prior not-required state.**

The anchors here were inherited verbatim from the old `on.paths`
(`server/`, `supabase/migrations/`, `test/server/*.tenant-isolation.test.ts`).
But 20 of 22 isolation tests `import "@/lib/supabase/tenant"`, and the suite
exercises the RLS-bypassing service-role client (`lib/supabase/service.ts`) and
per-request scoping (`middleware.ts`) — **none of which were anchored**. A PR
breaking isolation in `lib/supabase/tenant.ts` would compute `tenant=false` →
suite skipped → gate GREEN → merge unblocked, with the suite affirmatively
(and falsely) certifying isolation.

Two reviewers (`security-sentinel`, `pattern-recognition-specialist`) verified
the anchors were a faithful superset of the *old `on.paths`* and passed them —
because they checked the wrong baseline. Only the reviewer prompted to check
**anchor-vs-actual-surface** (the threshold-gated `user-impact-reviewer`) found
it. Verifying the claim empirically (`grep "from \"@/lib/supabase/tenant\"" the
isolation tests`) confirmed it was real, not a false-positive HIGH.

## Solution

1. **Widen anchors to the verified surface** (not the inherited cheap-trigger set):
   added `apps/web-platform/lib/supabase/`, `middleware.ts`, `test/helpers/`, and
   the extracted verdict script (anti-bypass).
2. **Document every deliberately-unanchored gap** as an accepted scope boundary:
   - `app/api/**/route.ts` — anchoring all routes would run the heavy dev-Supabase
     suite on the majority of PRs, defeating the rate-budget purpose that is the
     entire reason for the shim. Route isolation relies on the now-anchored
     `lib/supabase/` clients + DB RLS (migrations, anchored).
   - Bot/GITHUB_TOKEN PRs satisfy the check via a blind synthetic GREEN (suite
     never runs) — repo-wide posture for all 16 checks; accepted because the
     synthetic-posting bots touch docs/metrics, not the isolation surface.

**General rule for any future path-filtered required check:** audit the anchor
set against the surface the suite verifies (trace the suite's imports), and
record each accepted gap. The anchor set is a security contract, not just a cost
optimization.

## Prevention

- **Plan/review gate:** when a plan promotes a path-filtered workflow to required,
  the spawn prompt for the threshold-gated reviewer MUST instruct: "enumerate the
  suite's imports/surface and confirm every isolation-relevant file is an anchor;
  list each deliberately-unanchored path with a one-sentence justification." This
  is the anchor-coverage analogue of `hr-write-boundary-sentinel-sweep-all-write-sites`.
- **Reviewer baseline trap:** "anchors faithfully reproduce the former `on.paths`"
  is the WRONG assertion for a now-required check. The right assertion is "anchors
  cover the verified surface." Name the surface in the review prompt or agents
  echo the inherited-filter framing as a false-pass.

## Session Errors

1. **Edit rejected "File has not been read yet"** (workflow file pre-compaction;
   ADR-032 during the review phase) — the file had been `cat`-read or its
   read-state didn't carry across a skill boundary. **Recovery:** Read the file
   (or section) with the Read tool, then Edit. **Prevention:** already covered by
   `hr-always-read-a-file-before-editing-it`; one-off.
2. **Count off-by-one against a stale in-file comment** — wrote "14→15" for the
   ruleset widening; the live ruleset and `origin/main` `.tf` already held **15**
   (PR #4385 added `enforce` as the 15th but never updated the "14" comment), so
   the real change is 15→16. **Recovery:** ran `grep -c required_check` on
   `origin/main` + `gh api .../rulesets/<id>` before committing and corrected every
   count reference. **Prevention:** derive current-state counts from live infra /
   the as-written file, NEVER from an existing in-file comment — the comment is
   itself a stale-precondition candidate. Extends the self-derived-counts learning
   (`2026-05-20-plan-time-pr-vs-issue-disambiguation-and-self-derived-counts.md`)
   to the case where the stale source is a code comment.
3. **`set -o pipefail` poisoned a stderr assertion** —
   `bash script 2>&1 >/dev/null | grep -q '::error::'` returned the script's
   expected exit 1 (the pipeline's last non-zero under `pipefail`), not grep's
   match status, so the assertion read as failed even though the annotation was
   present. **Recovery:** capture stderr into a var first
   (`err=$(bash script 2>&1 >/dev/null) || true; printf '%s' "$err" | grep -q ...`).
   **Prevention:** when asserting on the stderr/stdout *content* of a command that
   is EXPECTED to exit non-zero, capture into a variable with `|| true` — never
   pipe it under `set -o pipefail`.
4. **Monitor `.status` polling failed (exit 1)** — polled for per-agent `.status`
   files that don't exist; background agents notify on completion directly.
   **Recovery:** awaited the completion notifications. **Prevention:** one-off;
   rely on the harness completion events, don't invent status-file polling.
