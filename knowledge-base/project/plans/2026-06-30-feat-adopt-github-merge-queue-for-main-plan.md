---
title: "Adopt a GitHub merge queue for main (strict up-to-date BEHIND-race fix)"
type: feat
issue: 5780
branch: feat-one-shot-5780-merge-queue-main
lane: cross-domain
brand_survival_threshold: none
date: 2026-06-30
status: planned
iac_routing_ack: plan-phase-2-8-reviewed
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
Phase 2.8 reviewed: this plan introduces NO manual infrastructure steps. All new
infrastructure (the merge_queue ruleset rule) routes through the existing
infra/github/ Terraform root + apply-github-infra.yml auto-apply-on-merge. There
are zero operator SSH steps, zero dashboard clicks, and zero manual Doppler-write
steps. See the `## Infrastructure (IaC)` section. (Ack comment present so the
Phase 2.8 substring scan does not false-positive on the word "Doppler" in the
credential-reuse note.)
-->

# ♻️ Adopt a GitHub merge queue for `main`

Closes #5780.

## Overview

The `CI Required` ruleset on `main` sets `strict_required_status_checks_policy = true`
(`infra/github/ruleset-ci-required.tf`) — a PR must be up-to-date with `main` before
it can merge. On an active day `main` merges faster than a web-platform PR's CI
converges (~8 min for the heavy jobs), so the PR is flipped `BEHIND`, CI restarts,
and the PR **can never converge** by manual `update-branch`. Admin-merge
(`gh pr merge --admin`) is the current escape hatch but it **bypasses the
up-to-date guarantee** the strict policy exists to provide.

The fix is to adopt a **GitHub merge queue** for `main`. The queue serializes
merges and builds each candidate against the projected post-merge state, so
"up-to-date" is satisfied **by construction** — no human/agent re-update races.
It keeps the strict-policy intent while removing the starvation, and removes the
need for routine admin-merge.

**Key research finding (premise-validating):** the `integrations/github` Terraform
provider already pinned in this repo (`~> 6.10`, locked **6.12.1**) **supports a
`merge_queue` rule block** inside `github_repository_ruleset.rules`. Probed
directly via `terraform providers schema -json` against 6.12.1 — all fields the
issue references (`merge_method`, `max_entries_to_*`, `min_entries_to_*`,
`grouping_strategy`, `check_response_timeout_minutes`) are present. So the queue
is modeled in the **existing IaC root** — no provider bump, no UI-only drift, no
violation of `hr-all-infrastructure-provisioning-servers`.

**The real work is not the Terraform block — it is the `merge_group` wiring.**
A merge queue dispatches a `merge_group` event against a temporary
`gh-readonly-queue/main/pr-N-<sha>` ref. **None** of the **8** workflows that produce
the 16 required status checks currently listen for `merge_group` (the producer set is
8, not 7: `ci.yml`, `secret-scan.yml`, `pr-quality-guards.yml`,
`legal-doc-cross-document-gate.yml`, `tenant-integration.yml`, `dependency-review.yml`,
**`skill-security-scan-pr-trailer.yml`** for the `skill-security-scan PR gate` context,
plus **CodeQL default setup**). A required
check whose workflow never fires on `merge_group` leaves the queue entry
**permanently pending → the queue stalls forever** (the merge-queue analogue of
the `[skip ci]` / path-filter deadlock in
`2026-03-20-github-required-checks-skip-ci-synthetic-status.md`). Adding
`merge_group:` to every contributing workflow — and extending the existing
always-run aggregator pattern (`tenant-integration-required`, `enforce`) to the
`merge_group` event shape — is the bulk of the change.

This is a **two-PR** change (see Sequencing): code+IaC merge cannot enable the
queue and verify `merge_group` in the same merge, because `merge_group` only ever
fires *after* the queue is live on `main`.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — this is
internal CI/merge infrastructure with no end-user surface. The *operator-facing*
failure mode is a **stalled merge queue**: PRs sit in the queue forever because a
required check never reports on `merge_group`. This is strictly better-bounded
than today's starvation (a stalled queue is loud and observable; the current
BEHIND-race is silent attrition), and the kill-switch (disable the queue rule,
re-apply) reverts to today's behavior.

**If this leaks, the user's data is exposed via:** N/A — no user data is processed,
stored, or transmitted by a merge queue. The change is declarative GitHub repo
configuration + CI workflow triggers.

**Brand-survival threshold:** `none`.

- `threshold: none, reason: This change touches no user-facing surface and processes no user data; it reconfigures how the founder's own repo gates merges to main. The one sensitive-path match in the diff (.github/workflows/secret-scan.yml) is a trigger-only edit — adding "merge_group:" to its "on:" block, with zero change to the gitleaks/allowlist logic. The secret-scan gate's protective behavior is preserved (and now also runs on the queue's merge candidate, strictly strengthening it).`

## Research Reconciliation — Spec vs. Codebase

No spec.md exists for this branch (direct one-shot path; no brainstorm). The issue
body's claims were validated directly against the codebase. All held; one was
strengthened.

| Issue claim | Reality (verified) | Plan response |
|---|---|---|
| "model it in `ruleset-ci-required.tf` if the Terraform provider supports merge-queue rules" | **Supported.** `terraform providers schema -json` on locked provider 6.12.1 shows `github_repository_ruleset.rules.merge_queue` with all 7 fields. | Model entirely in the existing IaC root. No provider bump, no UI path. |
| "Confirm bot/synthetic-check PRs interoperate with the queue (the queue builds a temp ref — verify synthetic check-runs still satisfy required contexts)" | Synthetic check-runs are pinned to the **PR head SHA**; the `gh-readonly-queue/*` temp ref has a **different SHA**, so synthetics do **not** carry over. `merge_group` is dispatched by GitHub (not the bot actor), so real CI *should* run on the temp ref — but this is unverifiable pre-merge. | Add `merge_group:` to CI workflows; add a belt-and-suspenders `merge_group`-triggered synthetic re-post for bot PRs; **live-probe** with a canary bot PR post-enablement (highest-risk item). |
| "Update `apply-github-infra.yml` / runbooks if the ruleset shape changes" | The post-apply verify uses `jq '.rules[0].parameters.required_status_checks \| length'` — `rules[0]` is a **latent fragility**: adding a `merge_queue` rule can reorder `rules[]` so `rules[0]` is no longer the status-checks rule → null → `^[0-9]+$` guard `exit 1`. | Fix verify to `jq '.rules[] \| select(.type=="required_status_checks") \| ...'` in the same IaC PR. |
| "Decide queue params (max entries, batch size, `merge_method = squash`)" | Provider exposes the full param set; defaults documented. | Set explicit params (see Phase 1); `merge_method = "SQUASH"` matches current `gh pr merge --squash`. |
| "Remove (or down-scope) admin-merge from the normal merge path" | Admin bypass is a ruleset `bypass_actors` concern; a queue does **not** auto-remove it (admins can still `--admin` past the queue). | Out of scope for the enabling PR (keep bypass_actors as-is per ADR-032); document the now-rare admin-merge as queue-bypass-of-last-resort in the runbook. Tracked as a follow-up if down-scoping is desired. |

## Implementation Phases

> **Phase ordering is load-bearing.** Workflows must learn `merge_group` **before**
> the queue rule is enabled, or the first queued PR stalls. PR-1 (workflow triggers
> + apply-verify fix) merges first; PR-2 (the `merge_queue` Terraform block) merges
> second and enables the queue. See Sequencing.

### Phase 0 — Preconditions (verify at /work, before any edit)

- [x] `cd infra/github && terraform init -backend=false` then confirm the
  `merge_queue` block schema on the **locked** provider:
  `terraform providers schema -json` (clean dir without backend) →
  `rules.merge_queue` present. (Already probed at plan time on 6.12.1 — re-confirm
  no lockfile drift.)
- [ ] `git grep -n "merge_group" .github/workflows/` returns **zero** (confirms no
  workflow already wired — establishes the full edit surface).
- [ ] Read `scripts/tenant-integration-gate-verdict.sh` (or the inline aggregate
  step in `tenant-integration.yml` jobs.`tenant-integration-required`) and confirm
  the fail-closed verdict logic for `DETECT_RESULT=success, SUITE_RESULT=skipped`
  resolves to **pass** — and decide its behavior on a `merge_group` event where
  `detect-changes` short-circuits.
- [ ] Confirm CodeQL is **default setup** (no `codeql.yml` workflow file; only
  `codeql-to-issues.yml` consumes results) → its `merge_group` behavior is a
  repo-security-settings concern, not a workflow edit. **P2-9 (architecture review):
  CodeQL is GHAS-pinned (integration_id 57789) so it CANNOT be belt-and-suspendered by a
  bot synthetic — if default setup does not post `CodeQL` on the merge_group temp ref,
  the queue deadlocks with no fallback. Make this a Phase 0 HARD GATE, not a
  post-enablement discovery:** confirm via GitHub Docs ("CodeQL default setup supports
  merge queues") AND the repo Security settings before PR-2. If unconfirmed, PR-2 holds.

### Phase 1 (PR-2 content — written first, merged second) — Terraform `merge_queue` block

- [x] Add a `merge_queue { ... }` block inside `rules { ... }` in
  `infra/github/ruleset-ci-required.tf` (sibling to `required_status_checks`):

  ```hcl
  # Merge queue (#5780). Adopted to fix strict-up-to-date BEHIND starvation:
  # the queue builds each candidate against the projected post-merge state, so
  # `strict_required_status_checks_policy = true` is satisfied by construction.
  # Provider `merge_queue` block supported on integrations/github 6.12.1
  # (locked). REQUIRES every required-check workflow to also fire on
  # `merge_group` (landed in PR-1) — else queue entries stall pending forever.
  merge_queue {
    merge_method                   = "SQUASH"  # behavior-defining; matches `gh pr merge --squash`
    grouping_strategy              = "ALLGREEN" # safe default; bisection benefit latent at merge-one-at-a-time
    max_entries_to_merge           = 1          # merge one candidate at a time (the no-batching decision)
    min_entries_to_merge           = 1          # no batching -- merge as soon as green
    check_response_timeout_minutes = 15         # MUST exceed slowest required check on merge_group (see AC)
  }
  ```

  > **Param rationale (cite GitHub Docs "Managing a merge queue" + provider registry
  > `github_repository_ruleset`):** only the fields whose value is a *decision* (or
  > behavior-defining) are set — `max_entries_to_build` and
  > `min_entries_to_merge_wait_minutes` are left at provider default (they are inert at
  > `max_entries_to_merge = 1` / `min_entries_to_merge = 1`; setting them adds schema
  > noise, not clarity — code-simplicity review). `ALLGREEN` over `HEADGREEN` is the
  > safe default; its per-candidate-bisection benefit is mostly latent at our
  > merge-one-at-a-time volume but it costs nothing. `min_entries_to_merge = 1` + no
  > batching keeps latency low for a bursty, low-volume repo. **`check_response_timeout_minutes`
  > is the one value that genuinely matters and the one hidden assumption:** an under-set
  > timeout **dequeues a green PR** — re-introducing exactly the starvation we are fixing.
  > 15 is a starting point premised on the ~8-min critical path; because the merge_group
  > build runs the FULL required suite (no path-skipping once P1-1 below is fixed —
  > `tenant-integration`/`e2e` run on the candidate), the value MUST be re-derived from
  > the observed slowest required-check wall-clock (see the AC: `timeout >= 1.5x slowest
  > required check`). Confirm provider defaults with `terraform plan` at /work.

- [x] Run `terraform validate` against the block (config-phase schema validation
  fires regardless of plan — per
  `2026-05-15-terraform-import-only-beta-provider-schema-validation.md`, validate the
  **values**, not just field presence: `merge_method`/`grouping_strategy` enums,
  numeric ranges).
- [x] Update the comment header in `ruleset-ci-required.tf` to note the
  `merge_queue` rule (the 16-required-check ABI comment block).

### Phase 2 (PR-1) — Add `merge_group:` triggers to all 7 contributing workflows

For each workflow, add `merge_group:` to `on:` (alongside existing triggers). Where
a job computes a diff base from `pull_request`-only context, handle the
`merge_group` event shape (`github.event.merge_group.base_sha` / `head_sha`) so the
required context still posts. Files (each a `Files to Edit` entry):

- [ ] `.github/workflows/ci.yml` — add `merge_group:`. **`detect-changes` job
  short-circuits on `github.event_name != 'pull_request'`** (BASE_REF only set on
  PRs). On `merge_group` the queue's whole point is to test the merge candidate ->
  the heavy/path-gated jobs **should run**, not skip. Extend `detect-changes` to
  compute a base from `merge_group.base_sha` and default to "run" on `merge_group`;
  the `test` aggregator must still post `test`. Contexts: `test`, `lockfile-sync`,
  `service-role-allowlist-gate`, `tc-document-sha-guard`. (prompt: Phase 2 step ci.yml)
- [ ] `.github/workflows/secret-scan.yml` — add `merge_group:`. No path filter ->
  runs unconditionally. Contexts: `gitleaks scan`, `lint fixture content`,
  `allowlist-diff (.gitleaks.toml paths surface)`, `rename-guard (allowlist destinations)`,
  `waiver discipline (issue:#NNN trailer)`.
- [ ] `.github/workflows/pr-quality-guards.yml` — add `merge_group:`. Context:
  `Bash fixture tests for guard scripts`. (Note: `types:` lists are
  `pull_request`-only sub-filters; `merge_group:` takes no `types:`.)
- [ ] `.github/workflows/legal-doc-cross-document-gate.yml` — add `merge_group:`.
  The `enforce` job's `surface_hit` decision diffs against `github.base_ref` (empty
  on `merge_group`). **Compute `surface_hit`'s diff base from
  `github.event.merge_group.base_sha`** so the DSAR-surface detection actually runs on
  the merge candidate. **Do NOT let an empty base fall through to `surface_hit=false`
  → exit 0** — that would post a green `enforce` context on the queue ref without
  checking the candidate (P1-1: a legal-doc lockstep regression would merge unverified).
  Context: `enforce`.
- [ ] `.github/workflows/tenant-integration.yml` — add `merge_group:`. **Decision
  (architecture review P1-4): on `merge_group`, set `detect-changes` -> `tenant=false`
  (skip the heavy suite) and let the aggregator post `tenant-integration-required` via
  the `suite=skipped` path.** Rationale: the heavy suite already ran (and passed) on the
  PR before it became queue-eligible; re-running the dev-Supabase isolation suite (which
  consumes `DOPPLER_TOKEN_DEV_SCHEDULED` + live dev-Supabase) on EVERY queue candidate
  defeats #5585's rate-budget purpose and risks dev-Supabase rate-limit exposure under
  bursty queueing — AND `secrets.*` availability on a GITHUB_TOKEN-authored `merge_group`
  event is not guaranteed. **The aggregator MUST still post a context on `merge_group`**
  (never go pending). Note this differs from the `enforce`/`detect-changes` base-sha
  handling because the tenant suite is a heavyweight side-effecting suite whose pre-queue
  PR run is authoritative; the cheap gates (legal-doc, ci) re-run on the candidate.
  Confirm the verdict script resolves `detect=success, suite=skipped -> PASS`. Context:
  `tenant-integration-required`.
- [ ] `.github/workflows/dependency-review.yml` — change `on: [pull_request]` ->
  `on: { pull_request: {}, merge_group: {} }`. Context: `dependency-review`.
  **P0-2 (architecture review): `actions/dependency-review-action@v4.9.0` REQUIRES a
  base/head pair and ERRORS on `merge_group` ("Can't find base/head commits") unless
  given `base-ref`/`head-ref`.** Because `dependency-review` is a pinned required
  context, an erroring action reports FAILING and blocks the queue as hard as a stall —
  this is deterministic, NOT a live-probe item. Resolve concretely in PR-1: on the
  `merge_group` event pass `base-ref: ${{ github.event.merge_group.base_sha }}` +
  `head-ref: ${{ github.event.merge_group.head_sha }}` to the action (or wrap behind an
  always-run aggregator that posts `dependency-review` success on `merge_group`).
- [ ] `.github/workflows/skill-security-scan-pr-trailer.yml` — **add `merge_group:`**
  (P0-1, architecture review — this was the missing 7th producer). It is the SOLE
  producer of the pinned required context `skill-security-scan PR gate` (job name at
  `:40`), and is currently `on: pull_request` only, reading
  `github.event.pull_request.{head,base}.sha`. On `merge_group` it never fires -> the
  context never reports -> **the queue stalls on the very first PR.** Add `merge_group:`
  AND branch its base/head SHA derivation to `github.event.merge_group.{base_sha,head_sha}`
  on the merge_group event. Context: `skill-security-scan PR gate`.
- [ ] **CodeQL** — default setup (no workflow file). Verify in repo Security
  settings that CodeQL default setup runs on `merge_group` / the queue temp ref
  (GitHub Docs: default setup supports merge queues). If it does **not** post
  `CodeQL` on `merge_group`, the queue deadlocks on the GHAS-pinned (57789)
  context. This is a **settings probe**, recorded in the canary AC, not a file edit.

### Phase 3 (PR-1) — Fix latent apply-verify fragility

- [ ] `.github/workflows/apply-github-infra.yml` (post-apply verify step, ~line 340):
  change `jq '.rules[0].parameters.required_status_checks | length'` ->
  `jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks | length'`.
  Rationale: adding a `merge_queue` rule can reorder `rules[]` so `rules[0]` is no
  longer the status-checks rule; `select(.type==...)` is order-independent. (Lands in
  PR-1 so the verify is robust **before** PR-2 adds the rule.)
- [ ] Confirm `scripts/audit-ruleset-bypass.sh` is already order-independent — it uses
  `jq '... | select(.type=="required_status_checks")'` (~line 207), NOT a positional
  `.rules[N]` index, so the audit is unaffected by adding a sibling `merge_queue` rule.
  Likewise `scripts/update-ci-required-ruleset.sh` already preserves sibling rules
  (`map(select(.type != "required_status_checks"))` re-emits the merge_queue rule). The
  canonical JSONs (`ci-required-ruleset-canonical-{required-status-checks,bypass-actors}.json`)
  assert only the status-checks array + bypass actors, neither of which changes.
- [x] **P1-3 (architecture review): `scripts/create-ci-required-ruleset.sh` is the ONE
  remaining positional/clobber risk.** It is the documented disaster-recovery RESTORE
  path and does a full `POST` of a hardcoded skeleton containing ONLY a
  `required_status_checks` rule (`:73-92`) — if ever re-run after PR-2 applies, it
  **silently clobbers the Terraform-managed `merge_queue` rule** (full replace, no
  destroy-guard trip, queue silently disabled). Mitigate in PR-2: add the `merge_queue`
  block to this skeleton (kept in sync with the `.tf`), OR add a guard comment + a note
  in `infra/github/README.md` that the DR script must be re-synced with the TF rule
  before any re-run. Add `scripts/create-ci-required-ruleset.sh` to `## Files to Edit`.
- [ ] Confirm the destroy-guard is unaffected (no plan edit needed):
  `tests/scripts/lib/destroy-guard-filter.jq` counts only `required_check` shrinkage +
  resource deletes; adding a `merge_queue` rule = `0 destroy` -> no `[ack-destroy]`
  needed. PR-2's first plan is `Plan: 0 to add, 1 to change, 0 to destroy` (in-place
  ruleset update). **No regression fixture is added** — the existing filter is provably
  safe for a rule *addition*, so a fixture for that path tests the framework, not this
  change (code-simplicity review).

### Phase 4 (PR-1) — Bot synthetic-check interop (belt-and-suspenders)

- [ ] **Live-probe first (cheapest path).** The correct outcome is that
  GitHub-dispatched `merge_group` events trigger the real CI workflows even for
  GITHUB_TOKEN-authored PRs (the infinite-loop suppression is keyed on the bot
  *actor* pushing, and `merge_group` is dispatched by GitHub). If the post-enablement
  canary shows the bot PR's required contexts post on the temp ref, **no
  re-post job is needed** and this phase is documentation only.
- [ ] **If the canary shows bot-PR contexts do NOT post on `merge_group`:** add a
  `merge_group`-triggered job (in the relevant workflow, or a small dedicated
  `merge-queue-bot-synthetics.yml`) that re-posts the synthetic check-runs from
  `scripts/required-checks.txt` to `github.event.merge_group.head_sha` with
  `integration_id` 15368 — mirroring `bot-pr-with-synthetic-checks/action.yml`'s
  posting logic but keyed on the queue temp SHA.
  **HARD REQUIREMENT (P1-3, architecture review): the re-post job MUST gate on
  detecting that the queue entry's PR is bot-authored** (e.g. the head commit author /
  PR author is `github-actions[bot]`) and synthesize ONLY for those entries. A job that
  blanket-posts green required contexts on EVERY `merge_group` event would **forge
  green checks for human PRs too — silently disabling real CI for everyone.** For human
  PRs, the real `merge_group`-triggered CI (Phase 2) must report; the synthetic path is
  exclusively a bot-PR fallback. Only the bot's caller
  (`.github/workflows/rule-metrics-aggregate.yml`) produces such PRs today.
- [ ] No change to `scripts/required-checks.txt` content (merge_queue is a rule, not
  a status check).
  (Out of scope: the stale `scheduled-ruleset-bypass-audit.yml` comment doc-drift is
  unrelated to merge queues — fix it in a separate trivial PR, not bundled here, per
  code-simplicity review.)

### Phase 5 (PR-2) — ADR + runbook (deliverables, not follow-ups)

- [x] Amend `ADR-032-github-branch-protection-as-iac.md` with a merge-queue
  decision section (see Architecture Decision below). The "verify runs-on-every-PR
  before requiring a check" contract clause generalizes to "runs-on-every-
  `merge_group`"; record it.
- [x] Update `infra/github/README.md`: document the `merge_queue` block + chosen
  params, the two-PR sequencing, the post-enablement canary verification, the
  kill-switch (remove the `merge_queue` block + re-apply reverts to pre-queue
  behavior), and admin-merge as queue-bypass-of-last-resort.

## Files to Edit

- `infra/github/ruleset-ci-required.tf` — add `merge_queue {}` block (PR-2)
- `infra/github/README.md` — document queue + sequencing + canary + kill-switch + DR-script sync note (PR-2)
- `.github/workflows/ci.yml` — `merge_group:` (detect-changes event-shape is optional polish — see P2-6; not load-bearing for required contexts) (PR-1)
- `.github/workflows/secret-scan.yml` — `merge_group:` (PR-1)
- `.github/workflows/pr-quality-guards.yml` — `merge_group:` (PR-1)
- `.github/workflows/legal-doc-cross-document-gate.yml` — `merge_group:` + `enforce` base from `merge_group.base_sha` (P1-1/P1-5) (PR-1)
- `.github/workflows/tenant-integration.yml` — `merge_group:` + `tenant=false` skip + aggregator posts on event (P1-4) (PR-1)
- `.github/workflows/dependency-review.yml` — `merge_group:` + `base-ref`/`head-ref` on merge_group (P0-2) (PR-1)
- `.github/workflows/skill-security-scan-pr-trailer.yml` — `merge_group:` + base/head sha branch (P0-1; the missing producer) (PR-1)
- `.github/workflows/apply-github-infra.yml` — verify `rules[0]` -> `select(.type==...)` fix (PR-1)
- `scripts/create-ci-required-ruleset.sh` — add `merge_queue` to the DR skeleton OR guard-comment + README sync note (P1-3) (PR-2)
- `.github/workflows/scheduled-terraform-drift.yml` — add `infra/github` to the matrix so the merge_queue rule is drift-detected on a schedule (CTO B-2, PR-2)
- `knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md` — amend (PR-2)

## Files to Create

- `.github/workflows/merge-queue-stall-check.yml` — scheduled (~30 min) queue-**stall** probe ONLY (GITHUB_TOKEN-only, no app secrets); files a `merge-queue-stall` issue on a stuck entry (PR-1, observability P1). The active liveness signal — NOT conditional. **(CTO B-3: the ruleset-drift sub-probe was moved OUT of this workflow to `scheduled-terraform-drift.yml`'s `infra/github` matrix in PR-2 — it needed elevated scope this no-app-secrets cron deliberately avoids.)**
- `.github/workflows/merge-queue-cla-synthetics.yml` — **(architecture review P1, PR-1)** on `merge_group`, re-posts the **CLA Required** ruleset's `cla-check` + `cla-evidence` contexts as success check-runs on `merge_group.head_sha` (Checks API, GITHUB_TOKEN/integration_id 15368, `checks: write` only, no checkout). The CLA producers (`cla.yml`/`cla-evidence.yml`) are PR/comment-driven and can't run on merge_group; without this the queue stalls on PR #1. **Trust model (record in the ADR-032 amendment, PR-2):** the synthetic is sound because (1) the queue ENTRY gate already required the real CLA contexts green on the PR head before admission, and (2) the legal evidence record is written to R2 Object Lock at CLA *sign* time, not merge-group time — so the synthetic is a CI-gate signal on a throwaway ref, never a substitute for the evidence. CLA is an author-property invariant under the octopus merge. `main` is gated by TWO rulesets (CI Required + CLA Required); enumerate producers across both.
- (conditional, only if Phase 4 canary shows bot contexts don't post on merge_group)
  `.github/workflows/merge-queue-bot-synthetics.yml` — bot-AUTHORED-entry-filtered synthetic re-post (P1-3 guard). Created only on canary failure; default path creates nothing here.

## Open Code-Review Overlap

None. (Ran `gh issue list --label code-review --state open --json number,title,body --limit 200`
then matched each planned file path via standalone `jq --arg`. No open code-review
scope-out names any file in `## Files to Edit` / `## Files to Create`. Recorded so the
next planner sees the check ran.)

## Infrastructure (IaC)

This change IS infrastructure (a GitHub branch-protection ruleset rule) and routes
through the existing `infra/github/` Terraform root + `apply-github-infra.yml`
auto-apply — no operator SSH, no dashboard click, no manual secret-write.

### Terraform changes

- File: `infra/github/ruleset-ci-required.tf` — adds a `merge_queue {}` rule block
  to the existing `github_repository_ruleset.ci_required`.
- Provider: `integrations/github ~> 6.10` (locked 6.12.1) — **unchanged**; the
  `merge_queue` block is supported at this version (schema-probed).
- Sensitive variables: **none new.** Reuses the existing App-auth provider
  credentials (`TF_VAR_github_app_id`, `TF_VAR_github_app_private_key`, sourced from
  the Doppler `prd_terraform` config by the apply workflow) and R2 backend creds —
  all already provisioned by prior PRs (#4150/#4384). No new mint, no new write.

### Apply path

Path **(b) auto-apply-on-merge.** Merging PR-2 (which touches `infra/github/*.tf`)
triggers `apply-github-infra.yml` automatically; the PR merge IS the human
attestation per `hr-menu-option-ack-not-prod-write-auth`. Plan shape:
`Plan: 0 to add, 1 to change, 0 to destroy` (in-place ruleset update) -> no
`[ack-destroy]` needed. Blast radius: the founder's repo only. Downtime: none
(enabling a queue does not block in-flight PRs; it changes how the next merge lands).

### Distinctness / drift safeguards

- `dev != prd` N/A — there is one GitHub repo (`jikig-ai/soleur`); no dev/prd split
  for branch protection.
- **Drift risk (provider nested-block history):** per
  `2026-03-19-github-ruleset-stale-bypass-actors.md` this provider has a history of
  mangling nested ruleset blocks across patches. AC: run `plan -> apply -> plan` and
  assert the second plan shows **no `merge_queue` drift**. Only add
  `lifecycle { ignore_changes = [...] }` on a *specific* field that round-trips
  badly — do **not** pre-emptively ignore.
- State: `github/terraform.tfstate` in R2 (`use_lockfile = false`); merge_queue
  params land in state (non-secret).

### Vendor-tier reality check

GitHub merge queue requires GitHub Team/Enterprise for private repos (available on
public repos). **AC: confirm merge queue is enableable on `jikig-ai/soleur`'s current
plan tier before PR-2** — if the plan tier does not include merge queue, the
`terraform apply` will error and PR-2 must be held pending a plan upgrade (operator
decision). This is the single external gate that could block the IaC apply.

## Observability

> **Active-stall probe is a PR-1 deliverable, not a soak (observability + architecture
> review, P1).** The headline failure mode (a required check never reports on
> `merge_group` → a queue entry pending forever) must NOT rely on "operator notices the
> queue UI" — that reproduces the silent-attrition firefight #5780 exists to kill, and is
> worst for unwatched bot PRs. PR-1 adds a scheduled **queue-stall probe**:
> `merge-queue-stall-check.yml` (GH Actions cron, ~every 30 min — repo-scoped: only
> `gh api`/`gh issue`, no app context/secrets, so GH-cron is acceptable over Inngest per
> ADR-033; state the determination in the workflow comment). It queries
> `gh api graphql` for `repository.mergeQueue(branch:"main").entries`, computes
> `now - enqueuedAt` per entry, and `gh issue create`s (idempotent, label
> `merge-queue-stall`, naming the stuck PR + pending context) when any entry exceeds
> `check_response_timeout_minutes + buffer`. This is the keyboard-visible, no-human-in-loop
> signal. The same workflow runs a **ruleset-drift probe** (the `gh api .../rulesets/14145388`
> merge_queue-presence check below) so drift has a REAL scheduled detector.

```yaml
liveness_signal:
  what: "No merge-queue entry on main has been pending longer than (check_response_timeout_minutes + buffer). A stuck entry = a required check not reporting on merge_group. PLUS: the merge_queue rule remains present on ruleset 14145388 (drift probe)."
  cadence: "Scheduled probe every ~30 min via merge-queue-stall-check.yml (GH Actions cron); also event-driven per merge attempt via the queue UI timeline."
  alert_target: "Probe fails -> gh issue create (label merge-queue-stall) naming the stuck PR + pending context. NOT operator-eyeballing."
  configured_in: "New PR-1 workflow .github/workflows/merge-queue-stall-check.yml (gh api graphql mergeQueue.entries + gh api rulesets/14145388); the live queue at https://github.com/jikig-ai/soleur/queue/main is the human cross-check."
error_reporting:
  destination: "GitHub Actions run logs for each merge_group event (per-workflow); apply-github-infra.yml run summary for the IaC apply; merge-queue-stall-check.yml run + the gh issue it files."
  fail_loud: "A required check missing on merge_group leaves the queue entry pending (visible in the queue UI AND filed as an issue by the stall probe) rather than silently merging — fail-visible by construction + actively alerted."
failure_modes:
  - mode: "Required check never reports on merge_group (workflow missing merge_group trigger)"
    detection: "merge-queue-stall-check.yml finds an entry pending > timeout; names the missing context."
    alert_route: "gh issue (label merge-queue-stall); canary AC (post-merge) catches it pre-reliance."
  - mode: "Path-filtered required check SKIPPED + posted forged-success on merge_group (detect-changes short-circuits unsafely)"
    detection: "P1-1 fix forbids the skip+pass arm; if it regressed, a tenant-isolation/legal regression merges green. Caught by reading detect-changes diff-base logic at review, not by a runtime probe (the forged-green is invisible to the stall probe — it is NOT pending)."
    alert_route: "Plan/review-time gate (the P1-1 fix); NOT runtime-detectable once forged-green merges. This is why the skip-arm is forbidden, not merely discouraged."
  - mode: "Bot PR synthetic checks not present on temp ref SHA"
    detection: "Bot PR (from rule-metrics-aggregate.yml) pending in queue > timeout -> merge-queue-stall-check.yml files an issue."
    alert_route: "Stall probe + canary bot PR; mitigation is the bot-filtered merge_group re-post job (Phase 4)."
  - mode: "Provider drift on merge_queue block (block removed/mangled outside Terraform)"
    detection: "merge-queue-stall-check.yml's ruleset-drift probe finds merge_queue-rule count != 1; the next apply-github-infra.yml plan also surfaces it."
    alert_route: "gh issue from the drift probe; apply-github-infra.yml fails closed on unexpected plan shape. (NOTE: rule-audit.yml does NOT audit the GitHub ruleset — it audits AGENTS.md/constitution governance + Anthropic model drift — so it is NOT a detector here; the new probe is.)"
logs:
  where: "GitHub Actions run logs (merge_group events + merge-queue-stall-check.yml) + apply-github-infra.yml run summary + the GitHub merge-queue timeline UI."
  retention: "GitHub Actions default (90 days); filed stall/drift issues persist until closed."
discoverability_test:
  command: "gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '[.rules[] | select(.type==\"merge_queue\")] | length'"
  expected_output: "1"
  functioning_verification: "This probe confirms the rule is APPLIED (config-present), NOT that the queue DRAINS — proxy vs invariant (observability P2). The throughput/functioning signal is the Phase-6 canary (one human + one bot PR flow through) + the standing merge-queue-stall-check.yml probe. Do not read count==1 as 'queue works'."
```

> Note: `gh api .../rulesets/14145388` requires `Administration:Read` (the App
> installation carries it; a bare `GITHUB_TOKEN` does not — same as the existing
> post-apply verify step). The discoverability test is **ssh-free** and confirms the
> `merge_queue` rule is APPLIED on the ruleset after PR-2 (it does not prove the queue
> drains — see `functioning_verification`).

## Architecture Decision (ADR/C4)

This plan makes an architectural decision — it changes **how merges to `main` are
gated** (a cross-cutting trust/dispatch boundary affecting every workstream). The
ADR amendment is a deliverable of THIS plan (PR-2), not a follow-up.

### ADR

Amend **ADR-032 — GitHub branch-protection ruleset as IaC** with a "Merge queue
adoption (#5780)" section: the decision (adopt a GitHub merge queue modeled via the
provider `merge_queue` block), the chosen params + rationale, the generalized
contract clause ("verify runs-on-every-`merge_group` before relying on the queue,"
extending the existing "runs-on-every-PR" clause), and the new failure mode
(permanent-pending queue stall). New ADR vs amend: **amend** — this extends ADR-032's
existing branch-protection-as-IaC decision rather than introducing an orthogonal one.

### C4 views

**No C4 impact.** Verified by reading all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):
a merge queue is a **process gate on the CI/merge pipeline**, not a new external
actor, external system, container, or data store. Enumerated for this feature:
(a) external human actors — none new (the founder/contributors already model as the
PR author; the queue does not add a correspondent/recipient); (b) external systems
— none new (GitHub Actions + the GitHub ruleset are the same already-modeled CI
edge; no new vendor/webhook/store); (c) containers/data stores touched — none (no
new persistent state beyond the existing `github/terraform.tfstate`, already an
infra artifact, not a C4 container); (d) actor<->surface access relationships — the
merge gate's mechanism changes (serialize-and-build-on-projected-state) but the
*who-can-merge-to-main* relationship is unchanged (bypass_actors untouched). At
/work, read the three `.c4` files to confirm (not just grep the feature noun) and
re-run the C4 validation tests (`apps/web-platform/test/c4-code-syntax.test.ts`
+ `c4-render.test.ts`) to confirm no edit was needed.

### Sequencing

The decision (queue gates merges to `main`) is only *true* after PR-2 applies AND
the canary verifies `merge_group` reporting. The ADR amendment is authored in PR-2
describing the target state with a "status: adopting" note until the canary
confirms; flip to "accepted" after the canary passes.

## Acceptance Criteria

### Pre-merge (PR-1 — workflow triggers + verify fix + stall probe)

- [ ] `git grep -c "merge_group" .github/workflows/ci.yml .github/workflows/secret-scan.yml .github/workflows/pr-quality-guards.yml .github/workflows/legal-doc-cross-document-gate.yml .github/workflows/tenant-integration.yml .github/workflows/dependency-review.yml .github/workflows/skill-security-scan-pr-trailer.yml` returns >=1 for **each** of the **7** files (the 8th producer, CodeQL, is default-setup — confirmed via the Phase 0 hard gate, not a file grep).
- [ ] `actionlint .github/workflows/*.yml` passes (validates `merge_group:` syntax). For embedded `run:` shell, `bash -c '<extracted snippet>'` (never `bash -n <file.yml>`).
- [ ] `apply-github-infra.yml` post-apply verify uses `select(.type=="required_status_checks")` — assert with `grep -F 'select(.type=="required_status_checks")' .github/workflows/apply-github-infra.yml` returns >=1, AND `grep -F '.rules[0].parameters.required_status_checks | length' .github/workflows/apply-github-infra.yml` returns **0**.
- [ ] `dependency-review.yml` passes `base-ref`/`head-ref` from `merge_group.{base_sha,head_sha}` on the merge_group event (P0-2); `skill-security-scan-pr-trailer.yml` and `legal-doc-cross-document-gate.yml` derive their diff base from `merge_group.base_sha` on the merge_group event (P0-1/P1-5).
- [ ] `tenant-integration.yml` `detect-changes` sets `tenant=false` on `merge_group` AND the aggregator posts `tenant-integration-required` (never pending) — confirmed by reading the job + the aggregate verdict step (P1-4); the unsafe "skip + forged-success" arm for the cheap gates is NOT used (P1-1).
- [ ] `.github/workflows/merge-queue-stall-check.yml` exists, is `actionlint`-clean, its `gh api`/`gh issue` calls are syntactically valid, and its cron + threshold (`check_response_timeout_minutes + buffer`) are wired (observability P1).

### Pre-merge (PR-2 — Terraform merge_queue block)

- [x] `cd infra/github && terraform validate` passes with the `merge_queue` block.
- [ ] `terraform plan` (via the apply workflow's doppler-tf-var invocation, or locally
  with creds) shows `Plan: 0 to add, 1 to change, 0 to destroy` and the change is an
  in-place `~ merge_queue` addition on `github_repository_ruleset.ci_required` (NOT a
  `replace`).
- [ ] Merge-queue availability confirmed on `jikig-ai/soleur`'s current GitHub plan
  tier (vendor-tier reality check) — else PR-2 held.
- [ ] CodeQL default setup `merge_group` support confirmed (Phase 0 hard gate) — else PR-2 held.
- [ ] `check_response_timeout_minutes` >= 1.5x the observed wall-clock p95 of the slowest
  required check on a `merge_group` build (architecture P2-3 — the magic-number-15 guard).
  If the slowest required check exceeds ~10 min, raise the timeout accordingly.
- [x] ADR-032 amended (status: adopting) and `infra/github/README.md` updated (incl. the
  `create-ci-required-ruleset.sh` DR-sync note, P1-3).

### Post-merge (operator / CI canary — after PR-2 applies)

- [ ] `apply-github-infra.yml` ran green on the PR-2 merge; its summary shows the
  expected required_status_checks count (16) via the fixed `select(.type==...)` probe.
- [ ] Discoverability test passes:
  `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '[.rules[] | select(.type=="merge_queue")] | length'` -> `1` (App-auth token).
- [ ] **Canary human PR:** open a trivial PR, approve it, run `gh pr merge --squash --auto`,
  confirm it **enters the queue** (not direct-merge), all 16 required contexts report
  on the `merge_group` temp ref, and it merges without stalling.
- [ ] **Canary bot PR:** trigger / wait for a `rule-metrics-aggregate.yml` bot PR (the
  one confirmed bot-PR producer that calls `bot-pr-with-synthetic-checks`) and confirm
  it flows through the queue without stalling. If it stalls on pending contexts, land
  Phase 4's bot-AUTHORED-entry-filtered `merge_group` synthetic re-post job (P1-3 guard)
  in a follow-up PR and re-verify.
- [ ] CodeQL default setup posts `CodeQL` on the temp ref (confirmed by the Phase 0 hard
  gate; re-verify in the canary).
- [ ] **Stall probe live:** `merge-queue-stall-check.yml` has run >=1 green cycle
  (`mergeQueue == null` → graceful no-op when nothing is queued). Force a synthetic stall
  (e.g. a deliberately-pending entry) once to confirm it files the `merge-queue-stall`
  issue. (CTO B-3: the drift sub-probe was removed from this workflow; merge_queue-rule
  drift is now detected by `scheduled-terraform-drift.yml` with `infra/github` in its
  matrix — see next AC. Stall detection and drift detection are deliberately separated.)
- [ ] **Ruleset drift (CTO B-2):** `scheduled-terraform-drift.yml` `infra/github` plan is
  clean — `plan -> apply -> plan` round-trip shows **no `merge_queue` drift**. `terraform
  plan` here also catches a *silently-disabled* queue (rule removed without a matching
  Terraform change → no entries → the stall probe cannot see it).
- [ ] Flip ADR-032 amendment status `adopting -> accepted`.

## Soak / Follow-Through Enrollment

The post-merge canary ACs are **point-in-time** verifications (one human PR + one bot
PR through the queue) — they confirm the queue functions, then close. **Steady-state
queue health is NOT a time-boxed soak; it is a permanent need covered by the scheduled
`merge-queue-stall-check.yml` probe** (a PR-1 deliverable — observability P1/P2), which
files an issue on any stuck entry or merge_queue-rule drift indefinitely. So no
`scripts/followthroughs/<name>-5780.sh` soak enrollment is required: the standing probe,
not a 7-day soak, is the correct mechanism for a gate that governs every future merge.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)

**Status:** reviewed (carried inline — single-domain CI/infra change matching the
issue's own `domain/engineering` label; no cross-domain leader spawn warranted)

**Assessment:** This is a pure CI/merge-infrastructure change with engineering-only
implications. The cross-cutting concern is **merge cadence affects every
workstream's velocity** (plugin, web-platform, telegram-bridge, docs) — but the
direction is strictly positive (eliminates BEHIND-starvation; removes routine
admin-merge gate erosion). Architectural risk is concentrated in the `merge_group`
wiring (queue-stall failure mode), fully enumerated in Risks + the canary ACs. The
provider-support premise is validated (no UI-only drift, no IaC-rule violation).
No Product/UX, Legal, Finance, Marketing, Sales, Support, or Operations surface is
touched. The mechanical UI-surface override did **not** fire (no `components/**`,
`app/**/page.tsx`, `app/**/layout.tsx`, or other UI-surface path in Files lists).

### Product/UX Gate

Not applicable — Product domain NONE (no user-facing surface; UI-surface override
did not fire).

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Queue deadlock** — a required check whose workflow lacks `merge_group:` leaves queue entries permanently pending. | Add `merge_group:` to ALL **7** contributing workflows incl. the easily-missed `skill-security-scan-pr-trailer.yml` (P0-1) + confirm CodeQL default setup (8th producer); pre-merge AC greps each; stall probe + canary prove reporting. **Highest-probability failure.** |
| **`dependency-review` action ERRORS (not pends) on merge_group** — pinned required context reports failing -> queue blocked. | Pass `base-ref`/`head-ref` from `merge_group.{base,head}_sha` (P0-2); deterministic, fixed in PR-1 not probed. |
| **Forged-success on skipped security suite** — `detect-changes`/`surface_hit` short-circuits to skip+pass on merge_group, merging a tenant-isolation/legal regression unverified. | P1-1: forbid the skip+pass arm for cheap gates (derive base from `merge_group.base_sha`); P1-4: for the heavy tenant suite, skip on merge_group but rely on the authoritative pre-queue PR run + aggregator-posts-skip. Review-time gate (not runtime-detectable once forged-green merges). |
| **DR restore script clobbers the merge_queue rule** — `create-ci-required-ruleset.sh` full-POSTs a skeleton without merge_queue. | P1-3: add merge_queue to the DR skeleton or guard-comment + README sync note. |
| **Bot PR synthetic checks don't carry to temp ref SHA** — bot PR stalls. | Live-probe via canary bot PR; bot-AUTHORED-entry-filtered `merge_group` re-post job (Phase 4) if needed — MUST NOT blanket-post (forges green for human PRs, P1-3 guard). **Cannot verify pre-merge.** |
| **Queue-stall is silent steady-state** — after canary, a later regression (workflow drops merge_group) re-stalls with no alert. | Scheduled `merge-queue-stall-check.yml` probe files an issue on any entry pending > timeout (observability P1) — the active liveness signal, a PR-1 deliverable. |
| **`rules[0]` verify breakage** in apply pipeline once a 2nd rule exists. | Fix to `select(.type=="required_status_checks")` in PR-1 (Phase 3), **before** PR-2 adds the rule. |
| **Provider nested-block drift** on `merge_queue` (6.x history). | `plan -> apply -> plan` drift AC; `lifecycle.ignore_changes` only on a proven-bad field, never pre-emptive. |
| **`merge_group` untestable pre-merge** (only fires post-enablement on main). | ACs split Pre-merge (plan/validate/grep/actionlint) vs Post-merge canary. ADR status `adopting` until canary passes. |
| **Wrong sequencing** — enabling the queue before workflows learn `merge_group`. | Two-PR split: PR-1 (triggers + verify fix) merges first; PR-2 (rule) second. |
| **Vendor-tier gate** — merge queue may require a paid GitHub plan for private repos. | Pre-PR-2 AC confirms availability; hold PR-2 if not (operator plan-upgrade decision). |
| **CodeQL default setup may not post `CodeQL` on merge_group** -> GHAS-pinned context deadlock. | Settings probe + canary AC; GitHub Docs indicate default setup supports merge queues — confirm empirically. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This
  plan's section is filled (threshold `none` + scope-out reason for the
  `secret-scan.yml` sensitive-path match).
- **The required-context producer set is 8, not 7** — `skill-security-scan PR gate` is
  produced by `skill-security-scan-pr-trailer.yml` (easily missed because its job name
  doesn't match the workflow filename), and CodeQL is default-setup (no workflow file).
  Enumerate producers by the 16 `required_check.context` strings in
  `ruleset-ci-required.tf` mapped to their emitting job, NOT by skimming the workflow
  directory. A single omitted producer stalls the queue on the first PR.
- **`discoverability_test` asserts the rule is APPLIED, not that the queue DRAINS** —
  a proxy, not the invariant. The functional signal is the canary (one-shot) + the
  scheduled stall probe (standing). Don't mistake `merge_queue rule count == 1` for
  "the queue works."
- **`rule-audit.yml` does NOT audit the GitHub ruleset** (it audits AGENTS.md/constitution
  governance + Anthropic model drift) — do not cite it as a merge_queue drift detector.
  The new `merge-queue-stall-check.yml` is the real scheduled detector.
- `merge_group:` takes **no** `types:` sub-filter (unlike `pull_request`). Adding a
  `types:` list under `merge_group:` is a no-op at best, a schema warning at worst.
- **A `merge_group`-triggered synthetic re-post job MUST filter to bot-authored queue
  entries** — a blanket post of green required contexts on every merge_group forges
  green for human PRs, silently disabling real CI for everyone (P1-3 guard).
- The post-apply verify token needs `Administration:Read` (App installation), not the
  bare `GITHUB_TOKEN` — the discoverability test inherits this.
- `bash -n <file.yml>` parses the YAML header as bash — use `actionlint` for the YAML
  and `bash -c '<snippet>'` for embedded `run:` shell.
- Provider param **defaults** may differ from the values set here; run `terraform plan`
  at /work to confirm the explicit block produces the intended live state (the block
  is kept explicit for ABI clarity, not because every field overrides a default).
- The destroy-guard is provably safe for a `merge_queue` *addition* (no `required_check`
  removed), but a future PR that *removes* the `merge_queue` block to kill-switch the
  queue is `0 destroy` too (it's a rule-block removal, not a `required_check` removal)
  — the guard will NOT flag it, which is the intended behavior (kill-switch must not be
  ack-gated). Document this in the README so a reviewer doesn't mistake it for a guard gap.

## GDPR / Compliance

Skipped — no regulated-data surface. The change touches no schema, migration, auth
flow, API route, or `.sql` file, and introduces no new LLM/external-API processing of
operator-session data, no new cron reading from learnings/specs, and no new artifact
distribution surface. (Triggers (a)-(d) of the gate do not fire; brand-survival
threshold is `none`.)
