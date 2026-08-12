---
title: "Protect jikig-ai/soleur-marketplace — ruleset, Terraform-owned manifest, reconcile trigger"
date: 2026-08-12
slug: feat-marketplace-repo-protection
branch: feat-marketplace-repo-protection
issue: 7493
closes: 7493
lane: cross-domain
type: feat
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Plan: Protect the marketplace repo

## Overview

`jikig-ai/soleur-marketplace` is the plugin's sole distribution channel and carries **zero**
rulesets, no branch protection, and one collaborator — verified live on 2026-08-12. ADR-182
recorded two controls as deferred-not-rejected. Both deferral blockers are now resolved against
the live API, so this is certify-and-scope.

Three arms land together:

- **A — a branch ruleset** on `soleur-marketplace` requiring a PR for the default branch, plus
  deletion and force-push restrictions, declared in `infra/github/`.
- **B — Terraform owns the manifest contents** via `github_repository_file`, sourced from a file
  in this monorepo under the already-CODEOWNERS-pinned `/infra/github/` path.
- **C — a reconcile trigger**: `scheduled-marketplace-drift.yml` dispatches
  `apply-github-infra.yml` after it files its evidence, so a detected drift is corrected within
  the daily cycle rather than only reported.

A and B **must** land in the same apply or the ruleset deadlocks B's write inside the unattended
pipeline. That is the plan's central sequencing constraint.

## Research Insights

### Premise Validation (Phase 0.6)

Every premise cited by #7493 and ADR-182 was re-checked against live state on 2026-08-12.

| Premise | Verdict | Evidence |
|---|---|---|
| App has permission for a ruleset | ✅ holds | `soleur-ai` App: `administration: write`, `repository_selection: all` |
| App has `contents: write` on the marketplace repo | ✅ holds | same App, `contents: write`, org-wide |
| A ruleset would lock the sole maintainer out | ❌ **dissolved** | Both sibling rulesets carry `OrganizationAdmin` (`actor_id 0`) + `RepositoryRole 5` bypass actors; `deruelle` has `admin: true`. Mirror that block. |
| "Drift is auto-reconciled by the next apply" | ❌ **FALSE** | `apply-github-infra.yml` has no `schedule:`. Triggers are `push: main` on `infra/github/*.tf`, `infra/github/.terraform.lock.hcl`, `tests/scripts/lib/destroy-guard-filter.jq`, plus `workflow_dispatch`. Arm C exists because of this. |
| #7471 is a PR | ❌ it is a **closed issue** | `gh pr view 7471` → not a PR; `gh issue list --state all` → CLOSED |
| ADR-182 exists and defers both options | ✅ holds | `ADR-182-keyless-manifests-and-a-dedicated-marketplace-source.md` §Alternatives considered |

**Provider facts, resolved empirically rather than assumed** (this is TR4, closed at plan time):

- Provider pinned at **6.12.1** (`.terraform.lock.hcl`), constraint `~> 6.10`. Terraform 1.10.5
  locally matches the workflow's `TERRAFORM_VERSION`.
- `terraform providers schema -json` at 6.12.1: `github_repository_file.overwrite_on_create` is
  `optional=true, computed=false` with **no schema default** — the same Optional-no-default bool
  class `repository-marketplace.tf` already warns about, so omitting it means `false`.
- `github_repository_ruleset`: `repository` is **required** (so targeting a second repo through
  the same provider is native); `rules` is `min_items: 1, max_items: 1`; `deletion` and
  `non_fast_forward` are rules-level bools; `bypass_actors.actor_id` is **not** required.
- **`terraform validate` PASSES** on the exact proposed HCL for both resources at 6.12.1 (run in
  a sandbox with the repo's own lockfile, `-backend=false`). No `ExactlyOneOf` / `ConflictsWith`
  constraint blocks the combination.

**Three GitHub Apps can push to the sole distribution channel today** — this is arm A's
strongest and previously-unstated justification:

| App | `contents` | `repository_selection` |
|---|---|---|
| `soleur-ai` | write | all |
| `claude` | write | all |
| `entire` | write | all |

Arm A with a bypass for `soleur-ai` **only** closes the `claude` and `entire` write paths to the
manifest. That is concrete prevention, not ceremony, and it is not redundant with arm B.

### Property List (Phase 0.6b)

- **P1.** No actor outside a declared bypass set can change the marketplace default branch
  without a pull request.
- **P2.** The published manifest's content is subject to CI, required checks and CODEOWNERS
  review before it changes.
- **P3.** A drift in the published manifest is *corrected* within the daily cycle, with its
  evidence preserved.
- **P4.** The unattended `apply-github-infra` pipeline still completes end-to-end with A and B
  both live.

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | Disposition |
|---|---|---|
| `terraform import` of the existing manifest file (a third `import_*` helper in `apply-github-infra.yml`) | "first apply adopts rather than clobbers" | **CUT.** The root's README already flags that the two existing import id shapes differ and "the difference is load-bearing"; a third shape in the highest-blast-radius file is real risk. `overwrite_on_create = true` gets the same end state with zero workflow change, and its semantic — Terraform's content wins — *is* arm B's decision. The no-op property is recovered more strongly by AC8, which diffs the **published artifact** against the source file. |
| `terraform import` of the ruleset (`import_ruleset`) | "adopt an existing ruleset" | **CUT — not applicable.** `gh api repos/jikig-ai/soleur-marketplace/rulesets` returns `[]`. Arm A is a pure create. (Had it been needed, `import_ruleset` hardcodes `soleur:$id` and could not have expressed `soleur-marketplace:$id` — noted as a Sharp Edge for any future marketplace ruleset adoption.) |
| A `schedule:` on `apply-github-infra.yml` (whole-root daily reconcile) | P3, plus ruleset-drift reconcile | **CUT.** It reverts drift *before* the 06:37 drift check observes it, so an attack is silently erased with no issue filed — the opposite of `hr-observability-as-plan-quality-gate`. Arm C's ordering (evidence first, then remediate) is the load-bearing difference. |
| An allowlist of "content finding" keys for the arm C predicate | P3 | **CUT and replaced.** See Research Reconciliation R2 — the correct predicate is a one-item **denylist**, which is strictly more robust. |

### Institutional learnings applied

- `2026-08-12-certifying-a-deferral-means-re-deriving-its-benefit-not-just-its-blockers.md` —
  this session's own learning; it is why the "auto-reconciled" claim was re-derived.
- `2026-07-03-brainstorm-re-verify-adr-deferral-triggers-against-live-state.md` — the blocker
  half of the same discipline.
- ADR-032 (GitHub branch protection as IaC), ADR-031 (PR merge is the human authorization),
  ADR-033 (Inngest is the canonical cron substrate; the drift workflow's documented override).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| FR6: "adopt both new resources through the existing `import_ruleset` / `import_repository` helper pattern" | The marketplace repo has **zero** rulesets, so arm A is a pure create with nothing to import. `import_ruleset` also hardcodes `soleur:$id` and cannot express another repo. | **FR6 dropped for arm A.** Arm B adopts via `overwrite_on_create = true` instead of a third import helper — see the Cut List. |
| FR8: dispatch only on an allowlist of content findings (`version_key_present`, `source_path`, …) | The check step also emits `manifest_fetch_failed`, `manifest_unparseable`, `manifest_shape`. A **deleted or corrupted** manifest is exactly what Terraform can fix, and an allowlist would silently skip it. A future assertion would also be silently excluded. | **FR8 inverted to a denylist:** dispatch iff at least one finding is **not** `plugin_manifest_unresolvable`. One excluded key, everything else dispatches, future assertions covered by default. |
| Spec is silent on where the ruleset's correctness is verified | `apply-github-infra.yml`'s post-apply verify probes `repos/${GITHUB_REPOSITORY}/rulesets/14145388` — hardcoded to *this* repo. Nothing would assert the new ruleset. | New FR11: extend the verify step with a marketplace probe that selects **by name**, not by a ruleset id that does not exist until after the first create. |
| Spec is silent on `repository-marketplace.tf`'s own comment | Its `OWNERSHIP BOUNDARY` block states "Terraform does NOT own the repo CONTENTS" and "The ONLY control on the artifact is the daily drift guard". **This plan falsifies both sentences.** | New FR12: update that comment in the same PR. A stale ownership comment in the file a future reader consults first is the same defect class as a stale ADR claim. |
| Spec assumed the ruleset gains drift detection | `audit-ruleset-bypass.sh` hardcodes `repos/jikig-ai/soleur/rulesets/14145388` and now runs from an **Inngest cron** (`cron-ruleset-bypass-audit.ts`), not a GH Actions workflow. Extending it spans the script (337 lines), its test suite (929 lines), and the Inngest function. | **Out of scope, tracked.** See Non-Goals NG5 with an explicit re-evaluation trigger. Residual exposure is *timeliness only* — the marketplace ruleset is Terraform-managed, so any widening is reverted by the next apply (including one arm C dispatches). |
| CODEOWNERS pins `/.github/workflows/scheduled-ruleset-bypass-audit.yml` | **That file does not exist.** The job migrated to Inngest. A CODEOWNERS row matching no path protects nothing while reading as coverage — the exact failure the file's own header documents for `scheduled-content-vendor-drift.yml`. | Fold in a one-line correction (FR13). This plan's G2 depends on CODEOWNERS being accurate, so its accuracy is in scope here rather than deferred. |

## Open Code-Review Overlap

Scanned 64 open `code-review` issues against every planned path.

- **#7098** — *audit the 56 `run:` bodies whose `set` omits `-e`* — touches
  `apply-github-infra.yml`. **Disposition: Acknowledge.** Arm C adds a new `run:` body; it must
  use the explicit `set +e` … `set -e` bracket the drift workflow already models (and which
  #7304 corrected in the apply workflow's plan step). This plan does not fix the other 56.
- **#3321** — *CODEOWNERS coverage for `knowledge-base/project/learnings/`* — **Disposition:
  Acknowledge.** Unrelated concern (missing coverage); FR13 fixes a *stale* row.

## User-Brand Impact

**If this lands broken, the user experiences:** a wedged `apply-github-infra` pipeline (the A↔B
deadlock), or — worse — a marketplace manifest whose published content silently stops matching
the source of truth while every check reports green, so `claude plugin marketplace add` resolves
a stale or wrong entry.

**If this leaks, the user's workflow and credentials are exposed via:** the manifest repoint
path. An unreviewed push changes the plugin source; every installed user's next update
materialises attacker-controlled agent code that executes locally holding their
`ANTHROPIC_API_KEY` and a `GITHUB_TOKEN` with `issues: write`. Four `claude-code-action`
workflows install from this repo, two of which ship into *users'* generated CI.

**Brand-survival threshold:** `single-user incident`.

Carried forward verbatim from the brainstorm's `## User-Brand Impact` (Phase 0.1 framing).
`requires_cpo_signoff: true` is set in frontmatter; `user-impact-reviewer` is invoked at review
time per `review/SKILL.md`.

## Implementation Phases

Phase order is dependency-directed, not file-grouped. Arm A's ruleset and arm B's file write are
a single atomic unit: **the bypass actor must exist in the same apply that first enforces the
ruleset.**

### Phase 1 — Source of truth for the manifest (arm B, data)

1. Create `infra/github/soleur-marketplace-manifest.json`, **byte-identical** to what is
   published today (fetch it, do not retype it):
   `curl -fsS https://raw.githubusercontent.com/jikig-ai/soleur-marketplace/main/.claude-plugin/marketplace.json`
2. Do **not** touch `.claude-plugin/marketplace.json` in this monorepo — a different file
   serving the legacy marketplace entry, tracked in #7489.

### Phase 2 — Ruleset + file resource (arms A and B, one commit)

3. Create `infra/github/ruleset-marketplace-pr-required.tf` with the validated shape:
   `name = "Marketplace PR Required"`, `repository = "soleur-marketplace"`, `target = "branch"`,
   `enforcement = "active"`; `conditions.ref_name.include = ["~DEFAULT_BRANCH"]`; three
   `bypass_actors` blocks (`OrganizationAdmin`/0/`pull_request`, `RepositoryRole`/5/
   `pull_request`, `Integration`/**3261325**/`always`); one `rules` block carrying a
   `pull_request` rule plus `deletion = true` and `non_fast_forward = true`.
   The header comment must state why the `Integration` bypass is not a hole: the App's write is
   the *reviewed* path, because its content originates in this monorepo behind CI and CODEOWNERS.
4. Add `github_repository_file.marketplace_manifest` (same file or a sibling `.tf`):
   `repository = "soleur-marketplace"`, `branch = "main"`,
   `file = ".claude-plugin/marketplace.json"`, `content = file("${path.module}/soleur-marketplace-manifest.json")`,
   `overwrite_on_create = true`, explicit `commit_message` / `commit_author` / `commit_email`.
5. **FR12** — update `repository-marketplace.tf`'s `OWNERSHIP BOUNDARY` comment: Terraform now
   owns the contents, and the drift guard is no longer the only control.

### Phase 3 — Make the source file publish itself (FR5)

6. Extend `apply-github-infra.yml`'s `on.push.paths` with
   `infra/github/soleur-marketplace-manifest.json`. The existing `infra/github/*.tf` glob does
   **not** match a `.json` sibling; without this the manifest edits and never publishes, with no
   error anywhere.

### Phase 4 — Verifiers (FR11 + Guard 1 + Guard 3)

7. Extend the post-apply verify step with a marketplace ruleset probe: `GET
   repos/jikig-ai/soleur-marketplace/rulesets`, **select by name** (the id does not exist until
   after the first create), assert `enforcement == "active"`, assert the canonicalized
   `bypass_actors` set equals exactly the three declared entries, assert a `pull_request` rule is
   present, assert `conditions.ref_name.include == ["~DEFAULT_BRANCH"]`. The probe must fail
   closed on an empty list or a name miss, and must echo a checked-count that the step asserts
   against the expected count (anti-vacuity).
8. Add a published-artifact verify: fetch the manifest over
   `raw.githubusercontent.com` and diff against `infra/github/soleur-marketplace-manifest.json`.
   **Read the published artifact, never Terraform state** — a state-only check passes while
   publication silently failed.

### Phase 5 — Reconcile trigger (arm C)

9. Add `actions: write` to `scheduled-marketplace-drift.yml`'s `permissions`. **Nothing else** —
   the automatic `GITHUB_TOKEN` must remain the only credential, or the workflow's ADR-033
   gate-override justification (iii) "NO PRODUCT SECRETS ARE CONSUMED" becomes false.
10. After the issue file/comment step, and gated on `steps.issue.outputs.delivered == '1'`, add a
    dispatch step: `gh workflow run apply-github-infra.yml -f reason="marketplace-drift reconcile
    from run <id>"`. Ordering is load-bearing — evidence before remediation.
11. Implement the FR8 predicate as a **denylist**: dispatch iff at least one finding key is not
    `plugin_manifest_unresolvable`.
12. Update the workflow's header prose: the six assertions change role from *detector* to
    *verifier that Terraform's write took effect*. They are retained (FR9), not retired.

### Phase 6 — Tests (Guard 2)

13. Extend `scripts/marketplace-drift-check.test.sh` with the Guard 2 mutation matrix. The
    harness already extracts the step body and runs it under
    `bash --noprofile --norc -eo pipefail` with a `curl` shim — reuse it; the dispatch decision
    must be observable as a step output, or the suite fails rather than passing vacuously.

### Phase 7 — Records

14. **FR10** — amend ADR-182: mark both deferred alternatives shipped, record the resolved
    preconditions, and **correct** the "auto-reconciled by the next apply" claim in
    §Alternatives considered.
15. Update `infra/github/README.md` with the new resources and the A↔B bypass dependency.
16. C4 edits — see `## Architecture Decision (ADR/C4)`.
17. **FR13** — CODEOWNERS: correct the stale `/.github/workflows/scheduled-ruleset-bypass-audit.yml`
    row (the job runs from `cron-ruleset-bypass-audit.ts`).

## Architecture Decision (ADR/C4)

This changes an ownership boundary (Terraform now owns another repo's contents) and a trust
boundary (who may write the distribution channel), so a decision record is a deliverable here.

### ADR

**Amend ADR-182** — no new ordinal. The decision extends ADR-182's own `## Alternatives
considered` entries rather than superseding them. Three edits: mark both deferred alternatives
shipped; record the preconditions that cleared and how they were verified; **correct** the
`github_repository_file` entry's benefit claim, which asserted auto-reconciliation the apply
workflow's trigger set cannot deliver without arm C.

*(No new ADR ordinal is claimed, so the ordinal-collision gate does not apply to this PR.)*

### C4 views

Checked all three model files (`model.c4`, `views.c4`, `spec.c4`). `soleurMarketplace` is
already modelled (`model.c4:243`, added by ADR-182) and already included in the view
(`views.c4:17`), so no new `include` line is required. Two existing statements are **falsified**
by this change and one edge is missing:

1. **`model.c4:245`** — `soleurMarketplace`'s description ends *"Has no CI, no review and no
   CODEOWNERS: scheduled-marketplace-drift.yml in jikig-ai/soleur is its only control."* Both
   clauses become false. Rewrite: contents are Terraform-owned from the monorepo (so they carry
   that repo's CI, required checks and CODEOWNERS), and a default-branch ruleset restricts direct
   writes to a single bypassing App identity.
2. **`model.c4:457`** — the `github -> soleurMarketplace` edge is described as *"Daily
   unauthenticated drift check … the sole control"*. Still accurate as a *read*, no longer the
   sole control. Amend the label.
3. **New edge** — an authenticated **write** relationship from the monorepo's infra apply to
   `soleurMarketplace`, carrying the manifest content and the ruleset. Today the model shows only
   reads into this system; the write is the architecturally novel part and is unmodelled.

**External-actor / external-system / access-relationship enumeration** (the completeness mandate):
external human actors — none added (`founder` unchanged); external systems — none added
(`soleurMarketplace`, `github` and `doppler` all already modelled); data stores — none;
access relationships — **one changed** (read-only → read + authenticated write), which is item 3.

Run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` after editing.

## Infrastructure (IaC)

### Terraform changes

- **New:** `infra/github/ruleset-marketplace-pr-required.tf`
  (`github_repository_ruleset.marketplace_pr_required`),
  `github_repository_file.marketplace_manifest`,
  `infra/github/soleur-marketplace-manifest.json` (the content source).
- **Edited:** `infra/github/repository-marketplace.tf` (ownership comment), `infra/github/README.md`.
- **Provider:** `integrations/github ~> 6.10`, locked at **6.12.1**. No new provider, no new root,
  no backend change — `infra/github/` already has the R2 backend and App auth.
- **Sensitive variables:** none new. `TF_VAR_github_app_id` / `TF_VAR_github_app_private_key`
  already flow from Doppler `prd_terraform`.

### Apply path

**(a) merge-triggered apply, no bootstrap.** Arm A is a pure create (zero live rulesets); arm B
adopts via `overwrite_on_create = true`, so no import step is required and the merge to `main`
is the only trigger.

Expected first `terraform plan`: **2 to add, 0 to change, 0 to destroy** — the ruleset and the
repository file. Any `to destroy` is a defect: the destroy guard fails closed and, because
`HEAD_MSG` is empty on a `workflow_dispatch`, `[ack-destroy]` is unreachable on a reconcile run.
That is correct fail-closed behaviour for unattended remediation and must not be "fixed".

Blast radius: the marketplace repo only. Downtime: none — `github_repository_file` writes a
commit; the raw URL serves the new content immediately.

### Distinctness / drift safeguards

- `archive_on_destroy = true` on `github_repository.soleur_marketplace` stays untouched.
- The destroy-guard filter counts `required_check` shrinkage on `github_repository_ruleset` only;
  the new ruleset carries a `pull_request` rule with **no** `required_status_checks`, so
  `required_check_count` is 0 on both sides and the nested counter is unaffected. Verified by
  reading `tests/scripts/lib/destroy-guard-filter.jq`.
- `github_repository_file` replacement is forced by `repository`, `file` or `branch` changes —
  content edits are in-place updates, so normal operation never trips the resource-delete counter.
- There is no `-target` scoping on this root, so no allow-list to extend and no orphan scope-guard
  suite for `infra/github` (`tests/scripts/` has one only for sentry).

### Vendor-tier reality check

Not applicable — repository rulesets and the contents API are available on the org's current plan;
both sibling rulesets already run on it.

## Observability

```yaml
liveness_signal:
  what: scheduled-marketplace-drift daily run + its Sentry check-in
  cadence: daily at 06:37 UTC (cron "37 6 * * *")
  alert_target: Sentry monitor slug scheduled-marketplace-drift (already wired)
  configured_in: .github/workflows/scheduled-marketplace-drift.yml (sentry-heartbeat step)

error_reporting:
  destination: GitHub issue labelled ci/marketplace-drift + action-required; Sentry check-in
    status=error; a red workflow run as the fallback channel
  fail_loud: true — the check step fails closed on unreachable URL, HTML error page, or
    non-object .plugins[0]; the issue step exits 1 when drift was found but the alarm did not
    deliver; the reconcile dispatch adds a third failure mode, below

failure_modes:
  - mode: A↔B deadlock — the ruleset blocks the App's github_repository_file write
    detection: apply-github-infra run fails at the apply step with 403/422 on the contents API
    alert_route: red workflow run on push to main; the run is the operator-visible surface
  - mode: manifest source edited but never published (FR5 paths gap)
    detection: the Phase 4 published-artifact diff — fetch the raw URL and compare to the
      source file; a state-only check cannot see this
    alert_route: red apply run; and the next daily drift check reports MISMATCH and files the
      ci/marketplace-drift issue
  - mode: reconcile dispatch fails (actions:write missing, workflow renamed, API error)
    detection: the dispatch step's own exit code, checked rather than swallowed
    alert_route: ::error:: annotation + the job fails, so the daily run goes red; the Sentry
      heartbeat carries the same conjunct as the existing delivered gate
  - mode: reconcile loop — drift persists across days and the dispatch re-fires
    detection: the standing ci/marketplace-drift issue accumulates a comment per day
    alert_route: the open issue is the surface; bounded at one dispatch/day by the cron
  - mode: ruleset silently disabled or bypass set widened
    detection: the Phase 4 post-apply ruleset probe — on applies only, not daily (see NG5)
    alert_route: red apply run

logs:
  where: GitHub Actions run logs for both workflows; Sentry check-ins for the drift monitor
  retention: GitHub Actions default (90 days); Sentry per its retention

discoverability_test:
  command: >-
    curl -fsS https://raw.githubusercontent.com/jikig-ai/soleur-marketplace/main/.claude-plugin/marketplace.json
    | jq -S . > /tmp/pub.json && jq -S . infra/github/soleur-marketplace-manifest.json > /tmp/src.json
    && diff -u /tmp/src.json /tmp/pub.json && echo MANIFEST_IN_SYNC
  expected_output: "MANIFEST_IN_SYNC"
```

The probe's first token is `curl` (on the Check 10 allowlist), needs no credentials, and reads
the same URL an installer resolves — so it answers the question that matters rather than a proxy.

## Encryption Posture

Detection fires on `\.tf$`. No persistent data store is introduced and no secret is stored; the
managed artifact is a **public** manifest in a public repo.

```yaml
at_rest:
  - store: .claude-plugin/marketplace.json in jikig-ai/soleur-marketplace
    mechanism: none-required-public-artifact
    evidence: repo visibility "public" (gh api repos/jikig-ai/soleur-marketplace .private=false);
      the file's entire content is a plugin pointer, already world-readable over
      raw.githubusercontent.com
    defends_against: nothing — confidentiality is not a property of this artifact
    does_not_defend: integrity. Integrity is carried by arm A (ruleset) + arm B (Terraform
      ownership) + arm C (reconcile), which is what this plan is
    disclosed_as: public distribution manifest
    live_verification: the discoverability_test probe above

in_transit:
  - connection: Terraform (apply-github-infra runner) -> api.github.com contents + rulesets API
    tls: TLS 1.2+ enforced by api.github.com
    cert_verification: on (Go stdlib defaults; no -k, no custom transport)
    does_not_defend: a compromised App private key — the credential is the trust root here
    disclosed_as: existing GitHub App auth path, unchanged by this plan
  - connection: scheduled-marketplace-drift runner -> api.github.com (workflow dispatch, NEW)
    tls: TLS 1.2+ enforced by api.github.com
    cert_verification: on (gh CLI defaults)
    does_not_defend: nothing new — the automatic GITHUB_TOKEN is scoped to this repo and to
      actions:write; no product secret is introduced
    disclosed_as: internal CI-to-CI dispatch
```

No `exception` block: no plaintext exception, no `cert_verification: off`.

## Guard Contract

The deliverable **is** guards, so each carries a property, a structural assembly, and a mutation
matrix derived from the design rather than from whatever the implementation happens to look like.
Write the matrices before the guards.

### Guard 1 — Marketplace default-branch ruleset, and the probe that proves it

**Property.** No actor outside the three declared bypass entries can modify
`refs/heads/main` on `jikig-ai/soleur-marketplace` without a pull request, and the branch cannot
be deleted or force-pushed.

**Assembly.** The chokepoint is GitHub's ruleset evaluation for that ref — every authenticated
write passes through it, so it is structural rather than a list. The member set it quantifies
over is *every actor GitHub will authenticate for a write to that ref*: org members,
repository collaborators, **and every GitHub App installed org-wide with `contents: write`**.
Enumerated on 2026-08-12 as `soleur-ai`, `claude`, `entire` — but the assembly is the
authentication path, not that snapshot, and the guard must not be written against the snapshot.
The red-driving mechanism is the Phase 4 post-apply probe, which reads the **live ruleset**, not
the `.tf` file (a config-only check cannot see a dashboard edit).

**Mutation matrix.**

| # | Mutation | Guard must |
|---|---|---|
| 1 | Flip `enforcement` to `"disabled"` (or the ruleset is deleted live) | RED — the probe asserts `enforcement == "active"` and fails closed on an empty ruleset list. **Own-dispatch row:** a probe that returns "0 rulesets checked" and exits 0 is vacuous and must fail. |
| 2 | Add a **4th** `bypass_actors` entry after the three compliant ones | RED — **second-member row.** A probe asserting "OrganizationAdmin is present" or "bypass_actors is non-empty" passes here; only a full canonicalized-set equality catches it. This is the exact widening `audit-ruleset-bypass.sh` exists to catch on the sibling repo. |
| 3 | Remove the `pull_request` rule, leaving `deletion` + `non_fast_forward` | RED — the probe asserts a rule of type `pull_request` is present, selecting by `.type` (never a positional `.rules[0]`). |
| 4 | Change `conditions.ref_name.include` to a branch that does not exist | RED — the ruleset is `active` and structurally intact while quantifying over **nothing**. Every "is it enabled" check passes; only the ref-condition assertion catches it. |

### Guard 2 — The reconcile dispatch predicate

**Property.** A reconcile apply is dispatched for exactly those drift verdicts a Terraform apply
can fix, and never for the one verdict it cannot.

**Assembly.** The `findings` array emitted by the check step — every finding key it can produce
now *or later*. The chokepoint is the single `if:` expression on the dispatch step. Because the
assembly is open-ended by design (assertions get added), the predicate must be a **denylist of
one** (`plugin_manifest_unresolvable`), not an allowlist that silently excludes future members.

**Mutation matrix.** Driven in `scripts/marketplace-drift-check.test.sh`.

| # | Mutation | Guard must |
|---|---|---|
| 1 | Force the predicate always-true | RED — a `plugin_manifest_unresolvable`-only verdict must not dispatch (Terraform would rewrite a correct file every tick while the real breakage — a moved `plugins/soleur` — persists). |
| 2 | Force the predicate always-false | RED — a `version_key_present` verdict must dispatch. |
| 3 | Add a **new** content finding key, simulating a future assertion | RED **if implemented as an allowlist** — **second-member row.** The denylist passes by construction; this row is what makes the allowlist/denylist choice testable rather than a matter of taste. |
| 4 | Make the dispatch decision unobservable (step writes no output) | RED — **own-dispatch row.** The suite must fail rather than pass vacuously against a step whose decision it cannot read. |
| 5 | Reorder so the dispatch precedes the issue file/comment step | RED — evidence must be delivered before remediation erases it. |

### Guard 3 — Published-artifact verifier

**Property.** The content served at
`raw.githubusercontent.com/jikig-ai/soleur-marketplace/main/.claude-plugin/marketplace.json` is
byte-identical to `infra/github/soleur-marketplace-manifest.json` at `main`.

**Assembly.** The **published artifact as an installer resolves it** — not Terraform state, not
the provider's own `content` attribute, not the local file. One fetch-and-diff is the chokepoint.

**Mutation matrix.**

| # | Mutation | Guard must |
|---|---|---|
| 1 | Edit the source file without extending `on.push.paths` (the FR5 gap) | RED — the apply never fires and the published content diverges. This is the whole reason the verifier reads the published URL. |
| 2 | Rewrite the verifier to compare Terraform state instead of the fetched artifact | RED — **own-dispatch row.** A state-only check reports success while publication failed; it must be rejected in review and by the test that pins the probe's source. |
| 3 | Point `github_repository_file.file` at a different path | RED — the canonical path goes stale while a new path is written; a check scoped to "the resource applied cleanly" passes. |
| 4 | Delete the published file entirely | RED — the fetch 404s and must report a mismatch, never "no drift" (the existing fail-closed contract). |

## Acceptance Criteria

### Pre-merge (PR)

- **AC1.** `terraform validate` passes on `infra/github/` with both new resources. *(Already
  demonstrated at plan time against locked 6.12.1 — re-run on the real root.)*
- **AC2.** `infra/github/soleur-marketplace-manifest.json` is byte-identical to the currently
  published manifest: `diff <(curl -fsS <raw-url>) infra/github/soleur-marketplace-manifest.json`
  exits 0.
- **AC3.** `grep -c 'soleur-marketplace-manifest.json' .github/workflows/apply-github-infra.yml`
  ≥ 1 **inside the `on.push.paths` list** — assert the anchor, not the bare token
  (`awk` the `paths:` block, then grep).
- **AC4.** The `Integration` bypass entry uses `actor_id = 3261325` (App id). A grep for the
  installation id `122213433` in `ruleset-marketplace-pr-required.tf` returns **0**.
- **AC5.** `scheduled-marketplace-drift.yml` `permissions:` gains exactly `actions: write`; the
  workflow still references no secret other than `secrets.GITHUB_TOKEN`
  (`grep -c 'secrets\.' <file>` counts only `GITHUB_TOKEN` occurrences).
- **AC6.** `bash scripts/marketplace-drift-check.test.sh` passes, including all five Guard 2
  mutation rows.
- **AC7.** `.claude-plugin/marketplace.json` in this monorepo is unmodified:
  `git diff --name-only origin/main...HEAD -- .claude-plugin/marketplace.json` is empty.
- **AC8.** ADR-182 contains the corrected reconciliation claim: the string "auto-reconciled by
  the next apply" no longer appears as an unqualified benefit, and the §Alternatives entries for
  both options are marked shipped.
- **AC9.** `model.c4` no longer asserts the marketplace repo "has no CI, no review and no
  CODEOWNERS" as current state, and a write edge into `soleurMarketplace` exists.
  `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` pass.
- **AC10.** `repository-marketplace.tf`'s `OWNERSHIP BOUNDARY` comment no longer states Terraform
  does not own the contents.
- **AC11.** CODEOWNERS contains no row whose path does not resolve:
  every `^/` path in `.github/CODEOWNERS` either exists or is a glob with ≥1 match.
- **AC12.** `bash scripts/test-all.sh` green (the full-suite exit gate, which reaches the orphan
  suites a targeted run misses).

### Post-merge (automatic — no operator step)

- **AC13.** The merge-triggered `apply-github-infra` run is green, and its plan showed
  `2 to add, 0 to change, 0 to destroy`.
- **AC14.** `gh api repos/jikig-ai/soleur-marketplace/rulesets` returns the ruleset with
  `enforcement == "active"` and exactly the three declared bypass actors (Guard 1 rows 1–4).
- **AC15.** The discoverability probe prints `MANIFEST_IN_SYNC`.
- **AC16.** A `workflow_dispatch` of `scheduled-marketplace-drift.yml` against an intentionally
  drifted manifest files the issue **and** triggers an apply that restores it, with the issue
  body still recording the original findings verbatim (evidence-before-remediation).
- **AC17.** A simulated `plugin_manifest_unresolvable`-only verdict files an issue and dispatches
  **nothing**.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Ruleset blocks the App's file write → unattended apply wedges (G4) | The `Integration` bypass ships in the same commit as the ruleset. AC13 is the explicit test. `terraform validate` already confirms the combination is representable. |
| Auto-remediation destroys forensic evidence | Arm C's step order: issue delivered (findings captured sanitized-verbatim) **then** dispatch. Guard 2 row 5 pins the ordering. The marketplace repo's git history also retains the edit. |
| The `Integration` bypass widens who can write unreviewed | Net-negative risk. The App can already push that repo unreviewed today, as can `claude` and `entire`. After this change only `soleur-ai` can, and its content originates from a CODEOWNERS-reviewed file. |
| A reconcile dispatch fires on a transient raw.githubusercontent outage | An apply with no content change is a no-op; the cost is one workflow run. Bounded at one per day by the cron. |
| Reconcile flapping between Terraform and a human editor | Arm A makes a competing human write require a PR, so the flap cannot form. Revisit only if observed. |
| Marketplace ruleset drift is not detected daily | Accepted and tracked — NG5. Terraform reverts any widening on the next apply; only detection timeliness is missing. |
| `overwrite_on_create` clobbers unexpected live content on first apply | AC2 pins the source file byte-identical to what is published, so the first apply is content-neutral; AC15 proves it after the fact. |

## Non-Goals

- **NG1.** Retiring the legacy `jikig-ai/soleur` marketplace entry — #7489. This plan does not
  touch `.claude-plugin/marketplace.json` in this monorepo (AC7 pins that).
- **NG2.** Adding CI or CODEOWNERS *inside* `soleur-marketplace`. Arm B makes it unnecessary.
- **NG3.** A `schedule:` on `apply-github-infra.yml` — see the Cut List; it erases evidence
  before the drift check observes it.
- **NG4.** Generalising `import_ruleset` to accept a repo argument. Not needed (arm A is a pure
  create); recorded as a Sharp Edge for whoever first needs to *adopt* a marketplace ruleset.
- **NG5.** Extending `audit-ruleset-bypass.sh` to cover the marketplace ruleset. Spans a
  337-line CODEOWNERS-pinned script, a 929-line test suite, and the Inngest function that now
  runs it. **File a tracking issue** with re-evaluation trigger: *"when a second Terraform-managed
  ruleset exists outside `jikig-ai/soleur`, or when the marketplace ruleset is observed drifting
  once."* Residual exposure is timeliness only.

## Domain Review

**Domains relevant:** Engineering, Legal, Product

Carried forward from the brainstorm's `## Domain Assessments` (recorded inline by the
orchestrator at the operator's direction — the two deferral triggers were factual infrastructure
questions answered against the live GitHub API, not assessment questions).

### Engineering

**Status:** reviewed
**Assessment:** The A↔B apply-time deadlock and the `paths:` glob gap are the two defects that
would otherwise ship silently; both are structural rather than judgement calls. The reconcile
dispatch is safe because the apply is deterministic from this repo's `.tf` files at `main` and
never consumes the drifted (untrusted) manifest body.

### Legal

**Status:** reviewed
**Assessment:** No new processing surface, no personal data, no vendor terms. Strengthens the
supply-chain integrity posture already described to alpha testers; creates and discharges no
disclosure obligation.

### Product

**Status:** reviewed
**Assessment:** Invisible to users when it works, which is correct for a distribution-integrity
control. No change to install or update UX. The only new user-visible failure mode is a botched
apply breaking `marketplace add`, bounded by the destroy guard, `archive_on_destroy`, and AC13.

### Product/UX Gate

Not applicable — no file in `## Files to Create` or `## Files to Edit` matches a UI-surface path
(no `components/**/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx`, no email template).
Tier: **NONE**.

## Files to Create

- `infra/github/ruleset-marketplace-pr-required.tf`
- `infra/github/soleur-marketplace-manifest.json`

## Files to Edit

- `infra/github/repository-marketplace.tf` — ownership-boundary comment (FR12)
- `infra/github/README.md` — new resources + the A↔B bypass dependency
- `.github/workflows/apply-github-infra.yml` — `on.push.paths` (FR5) + post-apply verifiers (FR11)
- `.github/workflows/scheduled-marketplace-drift.yml` — `actions: write`, dispatch step, denylist
  predicate, header prose (arm C, FR8, FR9)
- `scripts/marketplace-drift-check.test.sh` — Guard 2 mutation matrix
- `knowledge-base/engineering/architecture/decisions/ADR-182-keyless-manifests-and-a-dedicated-marketplace-source.md` — FR10
- `knowledge-base/engineering/architecture/diagrams/model.c4` — description + edge label + new write edge
- `.github/CODEOWNERS` — stale row (FR13)

## Test Scenarios

Every scenario is of the shape *mutation → guard reddens*, not *command → terminal output* —
the deliverable is guards, so the scenarios must test the guards.

1. `enforcement: disabled` on the live ruleset → post-apply probe fails (Guard 1.1)
2. Empty ruleset list → probe fails closed rather than reporting 0-checked-OK (Guard 1.1)
3. 4th bypass actor added → canonical-set comparison fails (Guard 1.2)
4. `pull_request` rule removed → type-selected assertion fails (Guard 1.3)
5. `ref_name.include` points at a nonexistent branch → condition assertion fails (Guard 1.4)
6. Predicate forced true + `plugin_manifest_unresolvable`-only findings → no dispatch expected, test fails (Guard 2.1)
7. Predicate forced false + `version_key_present` → dispatch expected, test fails (Guard 2.2)
8. New content finding key injected → allowlist implementation fails, denylist passes (Guard 2.3)
9. Dispatch decision unobservable → suite fails rather than passing (Guard 2.4)
10. Dispatch moved before issue delivery → ordering assertion fails (Guard 2.5)
11. Source file edited, `paths:` not extended → published-artifact diff fails (Guard 3.1)
12. Verifier rewritten to read Terraform state → pinned-source assertion fails (Guard 3.2)
13. `file` attribute repointed → canonical path diff fails (Guard 3.3)
14. Published file deleted → fetch 404 reports mismatch, not "no drift" (Guard 3.4)
