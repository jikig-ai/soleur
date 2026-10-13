---
feature: Adopt a GitHub merge queue for main (#5780)
plan: knowledge-base/project/plans/2026-06-30-feat-adopt-github-merge-queue-for-main-plan.md
branch: feat-one-shot-5780-merge-queue-main
lane: cross-domain
note: "Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed)."
date: 2026-06-30
---

# Tasks — Adopt a GitHub merge queue for `main`

Two-PR delivery. **PR-1 (workflow triggers + verify fix + stall probe) MUST merge and be
live on `main` BEFORE PR-2 (the merge_queue Terraform rule).** `merge_group` only fires
after the queue is enabled, so canary verification is inherently post-merge.

## Phase 0 — Preconditions (verify before any edit)

- [ ] 0.1 `cd infra/github && terraform init -backend=false && terraform providers schema -json`
  (clean dir) confirms `rules.merge_queue` on locked provider 6.12.1 — re-confirm no lockfile drift.
- [x] 0.2 `git grep -n "merge_group" .github/workflows/` returns zero (full edit surface).
- [x] 0.3 Read `tenant-integration.yml` jobs.`tenant-integration-required` aggregate verdict;
  confirm `detect=success, suite=skipped -> PASS`.
- [x] 0.4 Confirm CodeQL is default-setup (no `codeql.yml`; only `codeql-to-issues.yml`).
- [ ] 0.5 **HARD GATE:** confirm CodeQL default setup posts `CodeQL` on `merge_group`
  (GitHub Docs + repo Security settings). GHAS-pinned (57789) → cannot be synthetic-
  bypassed; if unconfirmed, PR-2 holds. (architecture P2-9)
- [x] 0.6 Map the 16 `required_check.context` strings in `ruleset-ci-required.tf` to their
  emitting job to confirm the producer set is **8** (7 workflows + CodeQL default setup),
  NOT skim the workflow directory. (Sharp Edge — the `skill-security-scan PR gate` miss.)

## Phase 1 (PR-1) — `merge_group:` triggers across all 7 producer workflows

- [x] 1.1 `.github/workflows/ci.yml` — add `merge_group:`. (detect-changes event-shape is
  optional polish, not load-bearing for required contexts — P2-6.)
- [x] 1.2 `.github/workflows/secret-scan.yml` — add `merge_group:`.
- [x] 1.3 `.github/workflows/pr-quality-guards.yml` — add `merge_group:` (no `types:` under it).
- [x] 1.4 `.github/workflows/legal-doc-cross-document-gate.yml` — add `merge_group:`;
  derive `enforce`'s `surface_hit` diff base from `github.event.merge_group.base_sha`;
  **forbid the empty-base → `surface_hit=false` → exit 0 path** (P1-1/P1-5).
- [x] 1.5 `.github/workflows/tenant-integration.yml` — add `merge_group:`; set
  `detect-changes -> tenant=false` on `merge_group` (heavy dev-Supabase suite already ran
  pre-queue); aggregator MUST post `tenant-integration-required` (never pending) (P1-4).
- [x] 1.6 `.github/workflows/dependency-review.yml` — `on: [pull_request]` →
  `on: { pull_request: {}, merge_group: {} }`; **pass `base-ref`/`head-ref` from
  `merge_group.{base_sha,head_sha}`** on the merge_group event (the action ERRORS without
  them; deterministic, P0-2).
- [x] 1.7 `.github/workflows/skill-security-scan-pr-trailer.yml` — add `merge_group:` +
  branch base/head SHA to `merge_group.{base_sha,head_sha}`. **The missing 7th producer
  of `skill-security-scan PR gate` — without it the queue stalls on the first PR** (P0-1).
- [x] 1.8 **(architecture review P1 — cross-ruleset enumeration gap)** `main` is gated by a
  SECOND ruleset, "CLA Required" (`cla-check` + `cla-evidence`, `scripts/required-checks.txt`).
  Its producers `cla.yml`/`cla-evidence.yml` are pull_request_target/issue_comment-driven and
  CANNOT run on `merge_group` → the queue would stall on the first PR. Created
  `.github/workflows/merge-queue-cla-synthetics.yml`: on `merge_group`, re-posts `cla-check`
  + `cla-evidence` as success check-runs on `merge_group.head_sha` via the Checks API under
  `GITHUB_TOKEN` (integration_id 15368 — an app token posts under the wrong integration and
  FAILS the ruleset match), `checks: write` only, no checkout. **Trust model (CTO ruling):
  sound because the queue ENTRY gate already required the REAL cla-check/cla-evidence green on
  the PR head (GitHub docs: "Once a PR has passed all required branch protection checks, a user
  with write access can add the PR to the queue"), and the legal evidence record was written to
  R2 Object Lock at CLA SIGN time — the synthetic is only a CI-gate signal on a throwaway ref,
  not a substitute for the evidence. Strictly safer than the existing bot-pr-with-synthetic-checks
  precedent, which greens these for bot PRs that never ran the real CLA flow.** Lesson:
  enumerate required-check producers across ALL rulesets targeting `main`, not just CI Required.

## Phase 2 (PR-1) — Latent apply-verify fix + positional-indexer audit

- [x] 2.1 `.github/workflows/apply-github-infra.yml` post-apply verify: change
  `jq '.rules[0].parameters.required_status_checks | length'` →
  `jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks | length'`.
- [x] 2.2 Confirm `audit-ruleset-bypass.sh` (~:207) and `update-ci-required-ruleset.sh`
  are already type-scoped (order-independent); canonical JSONs unaffected. No edit.
- [x] 2.3 Confirm destroy-guard unaffected: `merge_queue` addition = `0 destroy`, no
  `[ack-destroy]`. No fixture added (proven-safe path; testing the framework).

## Phase 3 (PR-1) — Active queue-stall + drift probe (observability P1)

- [x] 3.1 Create `.github/workflows/merge-queue-stall-check.yml` (GH Actions cron ~30 min;
  repo-scoped `gh api`/`gh issue` only, **GITHUB_TOKEN-only, NO app secrets** → GH-cron per
  ADR-033, state the determination in the workflow comment). **STALL-DETECTION ONLY** (CTO
  ruling, #5780): queries `gh api graphql` for `repository.mergeQueue(branch:"main").entries`,
  computes `now - enqueuedAt`, and `gh issue create`s (idempotent, label `merge-queue-stall`,
  naming stuck PR + checks link) when any entry exceeds `STALL_THRESHOLD_MINUTES` (default 30,
  ≥ ruleset `check_response_timeout_minutes` + buffer). `mergeQueue == null` (pre-PR-2 or
  nothing queued) → graceful green no-op.
  - **The ruleset-drift sub-probe was REMOVED** (it needed `Administration:Read` = app-token
    mint, which contradicts the no-app-secrets GH-cron justification). Per CTO B-3, merge_queue
    rule / silently-disabled-queue drift is detected by adding `infra/github` to the
    `scheduled-terraform-drift.yml` matrix in **PR-2** (task 5.6) — `terraform plan` covers it
    with the App-auth creds that workflow already carries, strictly more coverage than a count.
- [x] 3.2 `actionlint`-clean; `bash -c` the embedded `run:` snippets.

## Phase 4 (PR-1) — Bot synthetic-check interop (canary-gated)

- [ ] 4.1 Live-probe first: does GitHub-dispatched `merge_group` run real CI for
  GITHUB_TOKEN PRs? If the canary shows bot contexts post on the temp ref → no re-post job.
- [ ] 4.2 ONLY if the canary shows bot contexts do NOT post: create
  `.github/workflows/merge-queue-bot-synthetics.yml` that re-posts synthetics from
  `scripts/required-checks.txt` to `merge_group.head_sha` (integration_id 15368).
  **HARD: gate on bot-AUTHORED entries only — never blanket-post (forges green for human
  PRs, silently disables CI) (P1-3 guard).**

## Phase 5 (PR-2) — Terraform merge_queue block + DR-script sync + ADR/runbook

- [ ] 5.1 Add the `merge_queue {}` block to `infra/github/ruleset-ci-required.tf` (5
  decision-fields only: `merge_method=SQUASH`, `grouping_strategy=ALLGREEN`,
  `max_entries_to_merge=1`, `min_entries_to_merge=1`, `check_response_timeout_minutes`
  derived ≥1.5× slowest required-check p95). Update the ABI comment header.
- [ ] 5.2 `terraform validate` (value-level: enums, ranges).
- [ ] 5.3 `scripts/create-ci-required-ruleset.sh` (DR restore path) — add `merge_queue` to
  the hardcoded skeleton OR guard-comment + `infra/github/README.md` sync note (P1-3
  clobber risk).
- [ ] 5.4 Amend `ADR-032` ("Merge queue adoption (#5780)", status: adopting) — generalized
  "runs-on-every-merge_group" contract clause + the queue-stall failure mode.
- [ ] 5.5 Update `infra/github/README.md`: merge_queue block + params, two-PR sequencing,
  canary, kill-switch (block removal = `0 destroy`, mid-queue drain is graceful),
  admin-merge as queue-bypass-of-last-resort, DR-script sync note. Also note: ruleset
  drift detection is provided by `scheduled-terraform-drift.yml` (`infra/github` matrix,
  task 5.6); the stall probe is config-presence-blind by design.
- [ ] 5.6 **(CTO B-2)** Add `infra/github` to the `scheduled-terraform-drift.yml` matrix
  (`:35`, sibling to `apps/web-platform/infra`) so the merge_queue rule / silently-disabled-
  queue is drift-detected on a schedule via `terraform plan -detailed-exitcode` with the
  `prd_terraform` App-auth creds that workflow already carries. Land atomically WITH 5.1 (the
  rule it watches), gated behind 6.7's clean `plan→apply→plan`. Caveat: this provider's
  nested-block round-trip history (`2026-03-19-github-ruleset-stale-bypass-actors.md`) can
  perma-red the cron on `bypass_actors` churn — if a field round-trips dirty, add
  `lifecycle { ignore_changes = [<that field>] }` on THAT field only, never pre-emptively.

## Phase 6 (Post-merge canary — after PR-2 applies)

- [ ] 6.1 `apply-github-infra.yml` green; summary shows required_status_checks count 16 via
  the fixed `select(.type==...)` probe.
- [ ] 6.2 Discoverability: `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '[.rules[] | select(.type=="merge_queue")] | length'` → 1.
- [ ] 6.3 Canary human PR: approve + `gh pr merge --squash --auto`; confirm it ENTERS the
  queue, all 16 contexts report on the temp ref, merges without stalling.
- [ ] 6.4 Canary bot PR (`rule-metrics-aggregate.yml`): flows through without stalling; if
  it stalls, land the bot-filtered re-post job (Phase 4.2).
- [ ] 6.5 CodeQL posts `CodeQL` on the temp ref (re-verify the Phase 0.5 gate).
- [ ] 6.6 `merge-queue-stall-check.yml` ran ≥1 green cycle (mergeQueue null → no-op pre/post);
  force one synthetic stall to confirm it files the `merge-queue-stall` issue. **Confirm the
  `repository.mergeQueue` GraphQL query succeeds with GITHUB_TOKEN on the first live-queue run;
  if it returns a scope error, the fallback is a read-scoped fine-grained PAT — NOT the
  app-admin mint (CTO).** Ruleset-drift is now verified by 6.7 (scheduled-terraform-drift),
  not a sub-probe here.
- [ ] 6.7 `scheduled-terraform-drift.yml` `infra/github` plan is clean (no `merge_queue`
  drift) — the `plan → apply → plan` round-trip via the new matrix entry (task 5.6).
- [ ] 6.8 Flip ADR-032 status `adopting → accepted`.

## Pre-merge gate (PR-1)

- [x] `git grep -c "merge_group"` ≥1 for each of the 7 producer workflows (CodeQL is the 8th, default-setup).
- [x] `actionlint .github/workflows/*.yml` passes.
- [x] verify grep asserts: `select(.type=="required_status_checks")` present, `.rules[0]...length` absent.
- [x] `merge-queue-stall-check.yml` exists + actionlint-clean.
- [x] **(architecture review P1)** `merge-queue-cla-synthetics.yml` exists: posts `cla-check` +
  `cla-evidence` on `merge_group.head_sha` via Checks API under GITHUB_TOKEN — parity for the
  CLA Required ruleset's 2 contexts alongside the 16 CI Required contexts.
- [ ] **(PR-2 pre-enable hard gate, V-1)** Confirm CodeQL default setup AND the CLA synthetics
  both post on a real `gh-readonly-queue/main/*` ref before PR-2 flips enforcement (canary 6.3).

## Pre-merge gate (PR-2)

- [ ] `terraform validate` passes; `terraform plan` = `0 add, 1 change, 0 destroy` (in-place `~ merge_queue`, not replace).
- [ ] Merge-queue plan-tier availability + CodeQL merge_group support confirmed (else hold).
- [ ] `check_response_timeout_minutes` ≥ 1.5× slowest required check p95.
