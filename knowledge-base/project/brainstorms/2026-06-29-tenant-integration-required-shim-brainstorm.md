---
date: 2026-06-29
topic: tenant-integration required-check shim
issue: 5585
branch: feat-tenant-integration-required-shim
pr: 5688
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: Make `tenant-integration.yml` a required check without blocking unrelated PRs

## What We're Building

A **required-check shim** so the dev-Supabase tenant-isolation suite
(`.github/workflows/tenant-integration.yml`) gates merges for PRs that touch the
tenant-isolation surface, while remaining a no-op (reported green) for the ~95%
of PRs that don't — without burning dev-Supabase rate budget.

The suite is the only authoritative live verification that one founder's JWT
cannot read another's `users` / repo / session-sync / email-triage rows. Today
it is path-filtered and **not** required, so a red run does not block merges —
the exact gap that let #5582 sit red on `main`.

## Why This Approach

The naive fix — flip the path-filtered workflow to "required" — **fails**:
GitHub never reports a status context for a workflow that was filtered out by
`on.<event>.paths`, so the required check sits at "Expected — Waiting" forever
and blocks every PR that doesn't touch the filtered paths.

**Decisive precedent:** the repo *already solves this exact problem*. `ci.yml`'s
required `test` job is an `if: always()` aggregator that inspects
`needs.{test-webplat,test-bun,test-scripts}.result` and fails closed. Its own
comment states why: *"some branch-protection configs treat `skipped` as success
(fail-open)"* — so the repo deliberately uses always()+result-inspection instead
of relying on skip semantics. `ci.yml`'s `detect-changes` job is the established
path-detection idiom (checkout `fetch-depth: 0` + `git diff --name-only
origin/$BASE_REF...HEAD` + grep → boolean output).

Chosen design mirrors both idioms exactly — no new pattern, no new vendor action:

1. **Remove** the workflow-level `on.pull_request.paths` filter so the workflow
   always triggers on PRs (a context is always produced).
2. Add a cheap **`detect-changes`** job (checkout + git diff, **no Doppler/Supabase**)
   emitting a `tenant` boolean. On non-PR events (push to `main`,
   `workflow_dispatch`) it short-circuits to `tenant=true` (main is the source of
   truth), mirroring `ci.yml`'s `detect-changes`.
3. **Gate** the existing heavy `tenant-integration` job with
   `if: needs.detect-changes.outputs.tenant == 'true'` — preserves the
   rate-budget invariant: the Doppler/dev-Supabase work runs only on relevant PRs.
4. Add an always-run **`tenant-integration-required`** gate job
   (`if: always()`, `needs: [detect-changes, tenant-integration]`) that asserts
   inside `run:` (not in the job `if:`): **pass iff the heavy job result is
   `success` OR `skipped`; fail on `failure`, `cancelled`, or empty.** This job
   is the required context.
5. **Register** `tenant-integration-required` as a required status check in
   ruleset **"CI Required" (id 14145388)** — automated via `gh api`, **after**
   this PR merges to `main`.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Shim architecture | Aggregator gate job (mirror `ci.yml` `test`) | Proven fail-closed idiom already in repo; no new pattern |
| Path detection | Repo's hand-rolled `detect-changes` git-diff job | Consistency; no third-party action to pin/audit (rejected dorny/paths-filter) |
| Gate predicate | Pass on `success`\|`skipped`; fail on everything else | Fail-closed; `cancelled` ≠ verified pass; assert in `run:` not job `if:` |
| Required context | `tenant-integration-required` (gate job), NOT the heavy job | Heavy job is conditionally `skipped`; gate job always reports |
| Merge gate substrate | GitHub **ruleset 14145388** ("CI Required"), not classic branch protection | `main` has no classic protection (404); rulesets are the live gate |
| Registration timing | **Post-merge** `gh api`, idempotent (append-only) | Pre-merge registration strands every open PR on a missing context |
| Registration mechanism | Automated `gh api` PUT/PATCH in ship/postmerge step | `hr-never-label-any-step-as-manual-without` / never-defer-operator-actions |
| push-to-main trigger | Keep (green-on-main signal); `detect-changes` → `tenant=true` on non-PR | `$BASE_REF` is empty on push; per-event base guard avoids broken diff |
| ADR | None needed | CI plumbing within an established pattern (CTO) |
| Visual design (Phase 3.55) | N/A — no UI surface | Pure CI/infra change |

## Open Questions

1. **concurrency:** current workflow uses `cancel-in-progress: false`. CTO
   suggests `true` (keyed on PR ref) so superseded runs self-cancel → gate goes
   red on the stale commit → forces re-run on latest. Trade-off: a superseded
   commit shows transient red until the new run finishes. Decide at plan time.
2. **Exact ruleset JSON shape** for the `gh api` registration call (read current
   `required_status_checks` array, append `tenant-integration-required` only if
   absent) — confirm GitHub stores contexts as the **job-level check name**
   (`tenant-integration-required`), not the workflow `name:`.
3. Should `detect-changes` path anchors stay byte-identical to the current
   `on.paths` list (tenant-isolation tests, `server/**`, `supabase/migrations/**`)?
   Default: yes — single source of truth, documented to keep in lock-step.

## User-Brand Impact

- **Artifact:** the `tenant-integration-required` CI gate (the check deciding
  whether tenant-isolation regressions can merge to `main`).
- **Vector:** a fail-open shim (skipped-as-success, or a gate that doesn't
  propagate the heavy job's failure) lets a cross-tenant data-isolation
  regression merge silently → one founder reads another founder's rows.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Engineering (CTO). Legal (CLO) and Product (CPO) assessed as
**low-relevance** and not spawned: the change ships no user-facing surface, no
legal document, and no product decision — it hardens an existing security gate.
The brand-critical *threshold* still carries forward to the plan.

### Engineering

**Summary:** Approach is sound and introduces no new pattern (mirrors `ci.yml`
`test` + `detect-changes`); complexity is small. Hardening: match `test`'s exact
predicate (pass on `success`/`skipped` only, fail-closed on `cancelled`/empty);
assert inside `run:` not job `if:` (an `if:`-skipped gate reports no context and
reopens the very gap being closed); scope/guard the `git diff` base per-event so
the push-to-`main` path doesn't break on empty `$BASE_REF`; post-merge
registration is correct and must be automated + idempotent via `gh api`; prefer
the hand-rolled `detect-changes` over `dorny/paths-filter` (no new supply-chain
pin, single path-semantics source of truth).
