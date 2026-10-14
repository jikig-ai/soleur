# Protect `jikig-ai/soleur-marketplace` — the sole distribution channel

**Date:** 2026-08-12
**Issue:** #7493
**Branch:** `feat-marketplace-repo-protection`
**PR:** #7504
**Lane:** cross-domain

## What We're Building

Both controls ADR-182 deferred, plus the reconciliation trigger neither ADR-182 nor #7493
accounts for:

- **A — a `github_repository_ruleset` on `jikig-ai/soleur-marketplace`** requiring a PR for
  changes to `main`, declared in `infra/github/` as a sibling of the two existing rulesets and
  adopted by the same `import_ruleset` helper.
- **B — Terraform owns the manifest's CONTENTS** via `github_repository_file`. The
  source-of-truth file moves into this monorepo under `infra/github/`, where it inherits
  CI, required checks and the existing CODEOWNERS pin.
- **C — the reconcile trigger.** `scheduled-marketplace-drift.yml` dispatches
  `apply-github-infra.yml` on a content-drift verdict, so a detected drift is *corrected*
  within the day rather than waiting for the next unrelated infra edit.

## Why This Approach

ADR-182 already contains both designs in `## Alternatives considered` and deferred them on two
named preconditions — not on merit. This brainstorm is certify-and-scope, not derive-from-scratch.
Both preconditions are now resolved **against live state**, not inferred:

| Deferral trigger (ADR-182) | Live verdict | Evidence |
|---|---|---|
| "the App needs `contents: write` on that repo" | ✅ satisfied | `soleur-ai` App: `contents: write`, `administration: write`, `repository_selection: all` |
| "an untested ruleset … could lock the sole maintainer out" | ✅ dissolved | Both sibling rulesets already carry `OrganizationAdmin` (`actor_id 0`) + `RepositoryRole 5` bypass actors; `deruelle` holds `admin: true` on the repo |
| "a Terraform-managed file on a default branch interacts with branch protection" | ⚠️ real — see A↔B below | Resolved by declaring the App as an `Integration` bypass actor |

Live protection state at brainstorm time: **zero** rulesets, no branch protection, one
collaborator. The repo is unprotected by construction, exactly as the issue states.

### Two premises in #7493 that do not hold

**1. "Drift is auto-reconciled by the next apply" is overstated.** `apply-github-infra.yml`
fires only on `push: main` touching `infra/github/*.tf`, `infra/github/.terraform.lock.hcl`
and `tests/scripts/lib/destroy-guard-filter.jq`, plus `workflow_dispatch`. **It has no
schedule.** An out-of-band edit to the published manifest therefore sits unreconciled until
someone happens to edit the infra root — possibly weeks. The *daily* drift check is the faster
signal. Option B as written buys **ownership without timeliness**; ADR-182's own Alternatives
text repeats the same claim and is amended here.

**2. A and B partially conflict, and the conflict is silent.** If A requires a PR for pushes to
`main`, B's `github_repository_file` write from the App is blocked — and it fails at *apply*
time, in the unattended pipeline, which is precisely the failure mode ADR-182 refused to risk.
Resolution: declare the App as a `bypass_actors` entry with `actor_type = "Integration"`,
`actor_id = 3261325`. This is not a hole: the App's write is the *reviewed* path, because its
content originates in this monorepo behind CI, required checks and CODEOWNERS. Today that same
App can push arbitrary content to the marketplace with no review at all, so A+B is strictly
better than the status quo on this axis.

### Why the reconcile trigger is cheap here

`workflow_dispatch` is one of the two documented exceptions to the rule that a `GITHUB_TOKEN`
-triggered event does not create a new workflow run. So the drift workflow can dispatch the
apply with `permissions: actions: write` on the automatic token — **no product secret**, which
preserves the ADR-033 gate-override justification (iii) that the workflow "consumes only the
automatic `secrets.GITHUB_TOKEN`". That justification is load-bearing and must not be
invalidated as a side effect.

### The manifest is the ideal `github_repository_file` candidate

ADR-182 made the entry **keyless and release-invariant** — there is no version to publish per
release, so the file is effectively write-once. That removes the usual objection to Terraform
owning file contents (a hot file fighting the apply loop) and is the strongest argument for B
that #7493 does not make.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Ship A + B + C together | Operator-selected. A prevents unauthorized push; B puts contents under review; C is what makes B's reconciliation claim true. Any subset leaves a named gap. |
| 2 | Source of truth at `infra/github/soleur-marketplace-manifest.json` | `/infra/github/` is already a CODEOWNERS-pinned path, so B's "gains CODEOWNERS" claim becomes true with no CODEOWNERS edit. |
| 3 | Extend `apply-github-infra.yml` `paths:` to include the manifest | The existing trigger is `infra/github/*.tf` — a `.json` sibling does **not** match. Without this, editing the manifest in this monorepo would not trigger its own publication. Easy to miss; would ship as a silent no-op. |
| 4 | App declared as `Integration` bypass actor (`actor_id = 3261325`, App ID not installation ID) | Required for B to apply under A. Mirrors the existing CLA-bot `Integration` entry in `ruleset-cla-required.tf`. |
| 5 | Ruleset mirrors sibling bypass actors (`OrganizationAdmin` 0, `RepositoryRole` 5) | Dissolves the lockout risk that deferred A. `bypass_mode = "pull_request"` matches the siblings. |
| 6 | Drift workflow files/comments the issue FIRST, then dispatches | Auto-remediation overwrites the attacker's edit. Evidence must be captured in the issue body (already sanitized verbatim) before the reconcile runs. |
| 7 | Dispatch only on **manifest-content** findings, never on `plugin_manifest_unresolvable` | Assertion 3 fires when *this monorepo* moved `plugins/soleur`. There the manifest is correct and reconciling it is the wrong fix — it would repeatedly rewrite a correct file while the real breakage persists. |
| 8 | Keep all six drift assertions | ADR-182 says "two become redundant". Under B they change *role* rather than retiring: they become the verifier that Terraform's write actually took effect. A `github_repository_file` that silently fails to apply is exactly the silent-failure class this repo gates against. |
| 9 | Amend ADR-182 rather than write a new ADR | The decision extends ADR-182's own deferred alternatives and corrects its reconciliation claim. |

## User-Brand Impact

- **Artifact:** the `jikig-ai/soleur-marketplace` manifest — the file every installed user's
  `claude plugin marketplace add` / `plugin update` resolves through.
- **Vector:** an unreviewed push repoints the plugin source, and every installed user's next
  update materialises attacker-controlled agent code that executes locally holding their
  `ANTHROPIC_API_KEY` and a `GITHUB_TOKEN` with `issues: write`. Four `claude-code-action`
  workflows install from this repo, two of which ship into *users'* generated CI.
- **Threshold:** `single-user incident`.

## Non-Goals

- **Retiring the legacy `jikig-ai/soleur` marketplace entry.** Tracked separately in #7489; this
  work does not touch `.claude-plugin/marketplace.json` in this monorepo, which is a *different*
  file serving the legacy entry. The two must not be conflated during implementation.
- **Adding CI or CODEOWNERS inside `soleur-marketplace` itself.** B makes that unnecessary — the
  review happens in this monorepo, where the content originates.
- **A schedule on `apply-github-infra.yml`.** Considered as an alternative to C and rejected: a
  daily unattended `terraform apply` over the whole GitHub infra root has far more blast radius
  than an event-driven dispatch scoped to an actual drift verdict.

## Open Questions

1. Does `github_repository_file` under provider `~> 6.10` need `overwrite_on_create = true` for
   the first apply against the already-populated path? The file exists live, so the create would
   otherwise 422. Resolve at plan time against the pinned provider schema rather than assuming.
2. Should the reconcile dispatch be gated behind a second consecutive drift tick, to avoid a
   flapping loop if Terraform and a human disagree? Leaning no — the ruleset (A) makes a
   competing human write require a PR, so the flap cannot form.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

Recorded inline by the orchestrator rather than by a parallel leader spawn (operator-selected):
ADR-182's two deferral triggers were factual infrastructure questions, and both were answered
against the live GitHub API above rather than by assessment.

### Engineering

**Summary:** The A↔B apply-time conflict and the missing `paths:` trigger are the two defects
that would have shipped silently; both are structural, not judgement calls. The reconcile
dispatch is safe because the apply is deterministic from this repo's `.tf` files at `main` and
never consumes the drifted (untrusted) manifest body.

### Legal

**Summary:** No new processing surface, no personal data, no vendor terms. The control
strengthens the supply-chain integrity claim already made to alpha testers; no disclosure
obligation is created or discharged by this change.

### Product

**Summary:** Invisible to users when it works, which is correct for a distribution-integrity
control. It does not alter install or update UX; the only user-visible failure mode it can
introduce is a botched apply breaking `marketplace add`, which decision 6/7 and the existing
`archive_on_destroy` + `[ack-destroy]` guards bound.

## Capability Gaps

None. Every primitive this needs already exists in `infra/github/`:
`github_repository_ruleset` (2 live declarations, `grep -n bypass_actors infra/github/ruleset-cla-required.tf`),
the `import_ruleset` / `import_repository` helpers in `apply-github-infra.yml`, the CODEOWNERS
pin on `/infra/github/`, and the destroy-guard gate. `github_repository_file` is new to this
root but ships in the already-pinned `integrations/github ~> 6.10` provider
(`infra/github/versions.tf:12-13`).
