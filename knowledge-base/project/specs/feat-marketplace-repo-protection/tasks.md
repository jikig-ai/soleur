---
title: "Tasks — Protect jikig-ai/soleur-marketplace (v2)"
feature: feat-marketplace-repo-protection
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-08-12-feat-marketplace-repo-protection-plan.md
spec: knowledge-base/project/specs/feat-marketplace-repo-protection/spec.md
issue: 7493
created: 2026-08-12
revision: v2 (post six-reviewer panel + live bypass probe)
---

# Tasks: Protect the marketplace repo

v2. The plan's §Panel Corrections lists 20 v1 defects; the `(Cn)` tags below point at them.

## Phase 1 — Manifest source of truth

- [ ] **1.1** `curl -fsS <raw-url>` the published manifest verbatim into
      `infra/github/soleur-marketplace-manifest.json` — do not retype it
- [ ] **1.2** Confirm byte-identity with plain `diff` (not `jq -S`)
- [ ] **1.3** Confirm `.claude-plugin/marketplace.json` in this monorepo is untouched (#7489)

## Phase 2 — Pre-merge source validation (Guard 4 / C7)

The highest-value addition in v2. Without it, a bad source merges, publishes, and arm C
republishes it daily forever while Guard 3 reports in-sync.

- [ ] **2.1** Extract the manifest content assertions into a script that runs against a **local
      file**: no `version` key; `source.path == plugins/soleur`; `source.url` matches
      `jikig-ai/soleur`; `source.source == git-subdir`; no `ref`/`sha`/`commit`/`branch`/`tag`;
      exactly one `plugins[]` entry; `entry.name == "soleur"`
- [ ] **2.2** Wire it as an always-run **required** check over the source file in `ci.yml`
- [ ] **2.3** Guard 4 rows: `version` key (G4.1), url/path/source changed (G4.2), appended second
      entry (G4.3), check wired non-blocking or empty file list (G4.4)

## Phase 3 — Ruleset + file resource

- [ ] **3.1** `infra/github/ruleset-marketplace-pr-required.tf` with
      `repository = github_repository.soleur_marketplace.name` — a reference, not a literal (C-P2-3):
      it supplies the dependency edge and survives a rename
- [ ] **3.2** `conditions.ref_name.include = ["~DEFAULT_BRANCH"]`, `enforcement = "active"`,
      `target = "branch"`
- [ ] **3.3** `bypass_actors`: `OrganizationAdmin`/`0`/**`always`**, `RepositoryRole`/`5`/**`always`**,
      `Integration`/**`3261325`**/`always`
- [ ] **3.4** Comment the **`always` deviation** from the sibling rulesets and the probe that
      motivated it — measured: `pull_request` mode blocks the founder's own merge (needs `--admin`),
      `always` preserves direct push and spec G5
- [ ] **3.5** Comment the App-id (`3261325`) vs installation-id (`122213433`) distinction — the repo
      already spends 11 lines on this at `apply-github-infra.yml:251-262`
- [ ] **3.6** One `rules` block: `pull_request` with **`required_approving_review_count = 1`** (C1)
      and the four remaining sub-fields set explicitly (none has a default), plus `deletion = true`
      and `non_fast_forward = true`
- [ ] **3.7** `github_repository_file.marketplace_manifest`: same `repository` reference,
      `branch = "main"`, `overwrite_on_create = true`, explicit commit metadata
- [ ] **3.8** Rewrite `repository-marketplace.tf`'s `OWNERSHIP BOUNDARY` comment, **including the
      C16 warning**: a destroy now unpublishes the manifest (no `keep_on_destroy`;
      `archive_on_destroy` protects the repo, not a file in it)
- [ ] **3.9** `terraform validate`

## Phase 4 — Publication trigger

- [ ] **4.1** Add `infra/github/soleur-marketplace-manifest.json` to `on.push.paths` —
      `infra/github/*.tf` does not match a `.json` sibling
- [ ] **4.2** Assert it **inside** the `paths:` block (`awk` then grep), not a whole-file grep

## Phase 5 — Verifiers

- [ ] **5.1** Ruleset probe as a **two-hop** (C4): list → `select(.name=="Marketplace PR Required")
      | .id` → `GET /rulesets/{id}`. The **list endpoint returns a summary only** — no `rules`,
      `bypass_actors` or `conditions`
- [ ] **5.2** Assert: `enforcement == "active"`; `required_approving_review_count == 1`; `deletion`
      and `non_fast_forward` both present (C13); `conditions.ref_name.include`
- [ ] **5.3** Bypass-set equality with **`0 → null` normalization** (C5) per the SE-1 convention at
      `ruleset-cla-required.tf:22`. Without it the probe reddens on **every** apply
- [ ] **5.4** Expected set in `scripts/marketplace-ruleset-canonical-bypass-actors.json`, beside its
      two siblings; reuse `scripts/lib/canonicalize-bypass-actors.sh`
- [ ] **5.5** Fail closed on an empty list or name miss
- [ ] **5.6** Probe must live **inside** the existing verify step —
      `apply-github-infra.yml:355` traps and shreds the PEM on step exit
- [ ] **5.7** Published-artifact verifier (C6): bounded ETag poll with `Cache-Control: no-cache`,
      ~5 min cap, then fail. Measured `max-age=300`, `source-age: 102` — a single fetch inside the
      apply job reads the **cached old copy**, making the verifier vacuous on the very first run
- [ ] **5.8** Raw `diff`, never `jq -S` — byte identity is the stated property

## Phase 6 — Reconcile trigger (arm C)

- [ ] **6.1** `permissions:` gains `actions: write`; update gate-override justification **(ii)**,
      which says "`issues: write` … AND NOTHING ELSE" (C8)
- [ ] **6.2** **Repair the Sentry heartbeat** (C9): forward `SENTRY_INGEST_DOMAIN`,
      `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY` per `scheduled-terraform-drift.yml:1258-1260`. The
      composite declares them `required: true`; Actions does not enforce that on composite inputs, so
      the check-in has **never fired**. Reword gate-override (iii) — a Sentry ingest URL is not a
      product secret
- [ ] **6.3** Add a dispatch conjunct to the heartbeat status expression so a failed dispatch cannot
      report `ok`
- [ ] **6.4** `check` step computes `dispatch_eligible=true|false` (C12) — the predicate cannot live
      in an Actions `if:` (no split/regex/iteration, and `contains()` cannot distinguish a mixed
      verdict), and the test harness only runs the `check` step's bash
- [ ] **6.5** Predicate = ≥1 finding key **not** matching the `plugin_manifest_` prefix (C2). Two
      such keys exist today (`:215`, `:217`). Match anchored keys — `manifest_unparseable` is a proper
      substring of `plugin_manifest_unparseable`
- [ ] **6.6** Dispatch step **after** the issue step:
      `if: steps.check.outcome == 'success' && steps.issue.outputs.delivered == '1' && steps.check.outputs.dispatch_eligible == 'true'`.
      **No `always()` / `!cancelled()`** — the implicit `success()` is load-bearing and is the
      opposite of the convention two steps above
- [ ] **6.7** `set -euo pipefail` (**not** a `set +e` bracket — non-zero is a real error here),
      `GH_TOKEN`, `--ref main`, `--repo`, per `inngest-watchdog-restart-dispatch.yml:41-49`
- [ ] **6.8** Verify the dispatched run **started** (spec TR2) — `gh workflow run` exits 0 on
      acceptance and returns no run id. Poll for it and append the URL to the issue comment
- [ ] **6.9** Rewrite the **issue body** (C8): `:309` still claims "no CI, no required review and no
      CODEOWNERS", and `:316-321` tells the founder to edit the published file — now blocked by arm A
      and reverted by arm C. This is the artifact read mid-incident
- [ ] **6.10** Rewrite the gate-override block `:21-27` ("Terraform … explicitly NOT its contents")
- [ ] **6.11** Name the retained assertions individually rather than by count — the file's own header
      says "three" and there are more

## Phase 7 — Guard tests

- [ ] **7.1** Guard 2 rows 1–6 in `scripts/marketplace-drift-check.test.sh`
- [ ] **7.2** Guard 1 rows 1–5 as **fixture-driven** assertions over recorded ruleset JSON — the live
      mutations cannot be driven in CI, and claiming otherwise is the ceremony the Guard Contract
      format exists to prevent
- [ ] **7.3** Fixture proving `actor_id: 0` (Terraform) and `null` (API) normalize equal (C5)
- [ ] **7.4** Guard 3 rows, including the un-busted-fetch row (C6)
- [ ] **7.5** Destroy-guard fixture for a `github_repository_file` **replacement** — delete+create
      trips `resource_deletes` (spec TR5, load-bearing per C16)

## Phase 8 — Records

- [ ] **8.1** Amend ADR-182: both alternatives shipped, preconditions recorded, reconciliation claim
      corrected. Verify by whitespace-normalized match — the phrase is **line-wrapped** in the file,
      so a plain `grep -c` returns 0 on an unmodified ADR (C14)
- [ ] **8.2** `model.c4` — rewrite `soleurMarketplace`'s description and the
      `github -> soleurMarketplace` edge label; add the authenticated **write** edge.
      `views.c4` already includes the element
- [ ] **8.3** `c4-code-syntax.test.ts` + `c4-render.test.ts`
- [ ] **8.4** `infra/github/README.md`
- [ ] **8.5** CODEOWNERS one-line fix (the job runs from `cron-ruleset-bypass-audit.ts`)
- [ ] **8.6** File **NG5** (extend the bypass audit) with its corrected justification and trigger
- [ ] **8.7** File **NG6** (narrow the `claude`/`entire` installations) — the only option that fully
      closes the two-App collusion residual
- [ ] **8.8** File **NG7** (alert channel for a failed `apply-github-infra` run) — today nothing
      outside the workflow notifies, which does not hold for arm C's dispatched runs

## Phase 9 — Exit gate

- [ ] **9.1** `bash scripts/test-all.sh`
- [ ] **9.2** `/review` → `/compound` → `/ship`
