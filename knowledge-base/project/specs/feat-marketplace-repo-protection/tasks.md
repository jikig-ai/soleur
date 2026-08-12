---
title: "Tasks — Protect jikig-ai/soleur-marketplace"
feature: feat-marketplace-repo-protection
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-08-12-feat-marketplace-repo-protection-plan.md
spec: knowledge-base/project/specs/feat-marketplace-repo-protection/spec.md
issue: 7493
created: 2026-08-12
---

# Tasks: Protect the marketplace repo

Phase order is dependency-directed. **Tasks 2.1–2.3 must land in one commit** — the ruleset and
the App bypass actor cannot be split, or the unattended apply deadlocks.

## Phase 1 — Manifest source of truth (arm B, data)

- [ ] **1.1** Fetch the live published manifest and write it verbatim to
      `infra/github/soleur-marketplace-manifest.json`. Do not retype it —
      `curl -fsS https://raw.githubusercontent.com/jikig-ai/soleur-marketplace/main/.claude-plugin/marketplace.json`
- [ ] **1.2** Confirm byte-identity (AC2): `diff <(curl -fsS <raw-url>) infra/github/soleur-marketplace-manifest.json`
- [ ] **1.3** Confirm `.claude-plugin/marketplace.json` in this monorepo is untouched (AC7) — it
      serves the legacy entry (#7489), a different file

## Phase 2 — Ruleset + file resource (arms A and B — ONE commit)

- [ ] **2.1** Create `infra/github/ruleset-marketplace-pr-required.tf`:
      `github_repository_ruleset.marketplace_pr_required`, `repository = "soleur-marketplace"`,
      `target = "branch"`, `enforcement = "active"`,
      `conditions.ref_name.include = ["~DEFAULT_BRANCH"]`
- [ ] **2.2** Add the three `bypass_actors` blocks: `OrganizationAdmin`/`0`/`pull_request`,
      `RepositoryRole`/`5`/`pull_request`, `Integration`/**`3261325`**/`always`.
      3261325 is the **App id**; the installation id 122213433 must not appear (AC4)
- [ ] **2.3** Add the single `rules` block: a `pull_request` rule plus `deletion = true` and
      `non_fast_forward = true` (`rules` is `min_items: 1, max_items: 1` at provider 6.12.1)
- [ ] **2.4** Add `github_repository_file.marketplace_manifest` with
      `overwrite_on_create = true`, explicit `branch = "main"`, and explicit
      `commit_message`/`commit_author`/`commit_email`
- [ ] **2.5** Header comment: state why the `Integration` bypass is not a hole (the App's write is
      the reviewed path — content originates in this monorepo behind CI + CODEOWNERS), and that
      the bypass is what keeps arm B applying under arm A
- [ ] **2.6** Update `infra/github/repository-marketplace.tf`'s `OWNERSHIP BOUNDARY` comment —
      it currently states Terraform does not own the contents (AC10)
- [ ] **2.7** `cd infra/github && terraform validate` (AC1)

## Phase 3 — Publication trigger

- [ ] **3.1** Add `infra/github/soleur-marketplace-manifest.json` to `on.push.paths` in
      `.github/workflows/apply-github-infra.yml`. The existing `infra/github/*.tf` glob does not
      match a `.json` sibling — without this the manifest never publishes and nothing reports it
- [ ] **3.2** Assert the anchor, not the bare token (AC3): `awk` the `paths:` block, then grep

## Phase 4 — Verifiers (Guard 1 + Guard 3)

- [ ] **4.1** Extend the post-apply verify step with a marketplace ruleset probe:
      `GET repos/jikig-ai/soleur-marketplace/rulesets`, **select by name** (the id does not exist
      until after the first create)
- [ ] **4.2** Probe assertions: `enforcement == "active"`; canonicalized `bypass_actors` equals
      exactly the three declared entries; a rule of `.type == "pull_request"` is present (select
      by type, never positional `.rules[0]`); `conditions.ref_name.include == ["~DEFAULT_BRANCH"]`
- [ ] **4.3** Anti-vacuity: fail closed on an empty ruleset list or a name miss; echo a
      checked-count and assert it against the expected count
- [ ] **4.4** Add the published-artifact verifier: fetch the raw URL and diff against the source
      file. **Read the published artifact, never Terraform state** — a state-only check reports
      success while publication failed

## Phase 5 — Reconcile trigger (arm C)

- [ ] **5.1** Add `actions: write` to `scheduled-marketplace-drift.yml` `permissions:` — and
      nothing else. The automatic `GITHUB_TOKEN` must stay the only credential or the ADR-033
      gate-override justification (iii) becomes false (AC5)
- [ ] **5.2** Add the dispatch step **after** the issue file/comment step, gated on
      `steps.issue.outputs.delivered == '1'`:
      `gh workflow run apply-github-infra.yml -f reason="..."`
- [ ] **5.3** Implement the predicate as a **denylist of one**: dispatch iff at least one finding
      key is not `plugin_manifest_unresolvable`. Not an allowlist — a future assertion would be
      silently excluded
- [ ] **5.4** Check the dispatch step's exit code rather than swallowing it; emit the decision as
      a step output so Guard 2 can observe it
- [ ] **5.5** Use the explicit `set +e` … `set -e` bracket in the new `run:` body (inherited
      `bash -e`; see #7304 and open issue #7098)
- [ ] **5.6** Update the workflow header prose: the six assertions change role from *detector* to
      *verifier that Terraform's write took effect*. Retained, not retired

## Phase 6 — Guard tests

- [ ] **6.1** Guard 2.1 — predicate forced true + `plugin_manifest_unresolvable`-only findings →
      must not dispatch
- [ ] **6.2** Guard 2.2 — predicate forced false + `version_key_present` → must dispatch
- [ ] **6.3** Guard 2.3 — inject a NEW content finding key → denylist dispatches, an allowlist
      would not (this row is what makes the design choice testable)
- [ ] **6.4** Guard 2.4 — dispatch decision unobservable → suite fails rather than passes
- [ ] **6.5** Guard 2.5 — dispatch reordered before issue delivery → ordering assertion fails
- [ ] **6.6** `bash scripts/marketplace-drift-check.test.sh` green (AC6)

## Phase 7 — Records

- [ ] **7.1** Amend ADR-182: mark both deferred alternatives shipped, record the resolved
      preconditions, and **correct** the "auto-reconciled by the next apply" claim (AC8)
- [ ] **7.2** `model.c4:245` — rewrite `soleurMarketplace`'s description; it asserts "no CI, no
      review and no CODEOWNERS … its only control", both clauses falsified
- [ ] **7.3** `model.c4:457` — amend the `github -> soleurMarketplace` edge label (still a valid
      read, no longer the sole control)
- [ ] **7.4** Add the new authenticated **write** edge into `soleurMarketplace` from the infra
      apply. `views.c4:17` already includes the element, so no new `include` line
- [ ] **7.5** Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` (AC9)
- [ ] **7.6** `infra/github/README.md` — new resources + the A↔B bypass dependency
- [ ] **7.7** CODEOWNERS — correct the stale
      `/.github/workflows/scheduled-ruleset-bypass-audit.yml` row; the job runs from
      `apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts`. Verified as the
      only stale row, so AC11 is a one-line fix
- [ ] **7.8** File the NG5 tracking issue (extend `audit-ruleset-bypass.sh` to the marketplace
      ruleset) with its re-evaluation trigger

## Phase 8 — Exit gate

- [ ] **8.1** `bash scripts/test-all.sh` green — the full-suite gate reaches orphan suites a
      targeted run misses (AC12)
- [ ] **8.2** `/review` → `/compound` → `/ship`
- [ ] **8.3** Post-merge (automatic, no operator step): confirm the apply run is green and its
      plan showed `2 to add, 0 to change, 0 to destroy` (AC13); AC14–AC17 verify from CI
