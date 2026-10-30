---
title: "docs: terraform apply runbooks prescribe pre-O5b prd_terraform AWS_* (read-only) — state push 403s mid-apply"
type: fix
date: 2026-10-24
slug: docs-terraform-apply-runbooks-cred-drift
branch: feat-one-shot-10979-runbook-cred-drift
issue: 10979
closes: 10979
lane: cross-domain
domain: engineering
brand_survival_threshold: none
---

# docs: terraform apply runbooks prescribe pre-O5b prd_terraform AWS_* (read-only) — state push 403s mid-apply

## Enhancement Summary

**Deepened on:** 2026-10-24
**Sections enhanced:** 4 (`Research Insights`, `Files to Edit`, `Acceptance Criteria`, `Dependencies & Risks`)
**Research agents used:** none — no Task-capable subagent in this planning context; all deepen-plan gates and checks executed inline (`Reviewed-Coverage: sequential-fallback`, no independent review ran)

### Deepen verification results (soleur:deepen-plan gates, all PASS)

- §4.6 User-Brand Impact: section present, threshold `none`, no sensitive-path files in Files-to-Edit — pass.
- §4.7 Observability: pure-docs plan (every Files-to-Edit path is `*.md` under `knowledge-base/`) — skipped by rule.
- §4.8 PAT-shaped variable: zero regex hits — pass.
- §4.9 UI wireframe / §4.10 Encryption posture / §4.11 Guard contract: no trigger (no UI files, no `.tf`/store, no guard deliverable) — skipped by rule.
- §4.12 Scope Check: exactly one unfenced `## Scope Check`, all subsections present, all asks `mapped`, every `inferred` row justified, `Recommendation: single PR` — pass.
- §4.5 Network-outage: zero trigger patterns in Overview/Problem Statement; the plan prescribes no apply against provisioner-bearing resources (it edits docs that prescribe applies) — skipped.
- Live citation checks: issue #10979 OPEN; #9360 MERGED (cited only as the pre-existing supersession precedent inside `infra/github/README.md`); #8209 OPEN (its runbook is the citation target; O5b is complete per the runbook's own O-step ledger — the issue remains open for later O-steps); `ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md` exists under `knowledge-base/engineering/architecture/decisions/`.
- Self-grep scope audit (plan-sharp-edges §self-grep): AC-1's grep path (`knowledge-base/engineering/operations/runbooks/`) cannot match this plan (`knowledge-base/project/plans/`), `tasks.md`, or the learnings (`knowledge-base/project/learnings/`) that legitimately retain the old recipe text under supersession notes — the AC tests exactly the surface it means.
- AC-8 diff-scope includes the pipeline's own writes (`specs/<branch>/*` artifacts) so the AC is true on the final tree, not just the work-phase edits.

### Key improvements from the deepen pass

1. Confirmed the canonical §Local Terraform invocation section is silent on the backend's ambient `AWS_*` leg — the gap every annotation-note pointer inherits; elevated to a first-class plan item (AC-6).
2. Resolved both scope-item-5 evaluations to YES with evidence: the `tf()` wrapper feeds the backend from ambient `AWS_*` (push = write), and all four learnings warrant "in part, for writes" supersession notes (the old recipe still works for reads — the sharp-edges catalogue itself prescribes it for drift-remediation reads).
3. Enumerated the full stale-recipe surface beyond the `runbooks/` bound and dispositioned it (follow-up recommendation in `decision-challenges.md`) rather than silently widening or dropping it.

## Overview

Since the credential-tier cutover (`infra-credential-tiers-8209.md` step O5b, ADR-241 lineage), `prd_terraform`'s `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` are an intentionally **read-only** R2 pair for the `soleur-terraform-state` bucket: GET works (plans, refreshes, `state pull`), PUT 403s. The read/write pair lives in `soleur-infra-privileged/prd` as `TF_STATE_AWS_ACCESS_KEY_ID`/`TF_STATE_AWS_SECRET_ACCESS_KEY`, which CI's `infra-credentials` composite aliases onto the plain `AWS_*` names (`.github/actions/infra-credentials/action.yml` ~L393–L422). Three runbooks still prescribe sourcing `AWS_*` from `prd_terraform` for state-**writing** terraform invocations; following one mid-apply 403s on the S3 state push and leaves `errored.tfstate` plus a state-fork risk (observed 2026-10-24 during a `doppler_secret.inngest_config_digest` promotion). This plan rewrites those prescriptions to the canonical post-cutover form, names the correct Doppler secret in `inngest-config-refresh.md` step 3, annotates a state-repair `tf()` wrapper that shares the same hole, and supersedes the dated learnings that call the old recipe "canonical". Docs-only: no product code, no workflow edits.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Research Insights

**Files verified (this session, branch `feat-one-shot-10979-runbook-cred-drift`):**

- `knowledge-base/engineering/operations/runbooks/inngest-server.md:2455-2456` — Cutover step 0 exports `AWS_*` from `prd_terraform` before a `terraform apply -target=` that writes state. The only `secrets get AWS_ACCESS_KEY_ID` hit under `runbooks/`.
- `knowledge-base/engineering/operations/runbooks/grok-build-hetzner-dogfood.md:47` — `export AWS_ACCESS_KEY_ID=… AWS_SECRET_ACCESS_KEY=…` (ellipsis form, so the scope-item-4 grep does NOT match it; fixed via the block rewrite). Lines 49/57 use single-loader `doppler run -p soleur -c prd_terraform`. Its caveat note (~L40-44) already points at `infra-credential-tiers-8209.md` §Local Terraform invocation — the block must be made to match the note, and the note reworded (it currently calls the block "the PRE-cutover one").
- `knowledge-base/engineering/operations/runbooks/inngest-config-refresh.md` step 3 (~L73) — says "set `TF_VAR_inngest_config_digest=…`"; the Doppler secret to set is `INNGEST_CONFIG_DIGEST` in `soleur/prd_terraform` (the tf-var transformer produces `TF_VAR_inngest_config_digest`; a literal `TF_VAR_inngest_config_digest` secret becomes `TF_VAR_tf_var_inngest_config_digest`, undeclared-var noise — verified in `apps/web-platform/infra/variables.tf:677` and `inngest-config-digest.tf:31,43`). The step's manual apply is a state write and needs the credential pointer too.
- `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md:~457` — the state-loss-recovery `tf()` wrapper (`doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- terraform …`) feeds the backend from **ambient** `AWS_*` only; step 5's `tf state push` (~L470) writes state and would 403 on the read-only pair. Its `state pull` at ~L509 uses `--only-secrets AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY` (no transformer — names pass untransformed) for a GET: read-only pair is correct there.
- Canonical reference: `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` §Local Terraform invocation (L898-916) prescribes the nested-loader form but is **silent on the backend's ambient `AWS_*` leg** — the tf-var transformer renames every injected secret to `TF_VAR_*`, so neither loader ever sets `AWS_ACCESS_KEY_ID` for the S3 backend. Confirmed by the workflow comment at `.github/workflows/apply-web-platform-infra.yml` ~L1241 ("`--name-transformer tf-var` injects TF_VAR_* doppler secrets but passes those bare AWS_* vars through untouched") and the CI "Extract backend credentials" + Tier-B alias mechanism (`action.yml` L393-422). Every annotated runbook's "canonical form" pointer resolves to a recipe that still 403s on state writes unless this leg is documented.
- Verified replacement recipe (issue #10979 body, operator-written from the incident): export `AWS_*` from `TF_STATE_AWS_*` in `soleur-infra-privileged/prd`, plus `TF_VAR_hcloud_token`/`TF_VAR_doppler_token_tf`/`TF_VAR_cf_api_token_r2` from the same project (evicted from `prd_terraform` at O10), then `doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- terraform …`. The equivalent canonical form used below keeps the nested loaders (outer `soleur-infra-privileged` loader injects those `TF_VAR_*` automatically; inner `prd_terraform` carries `--preserve-env`) and adds the `AWS_*` export — same effect, consistent with the annotation text every other runbook already carries.
- `inngest-server.md` also has a state-writing single-loader apply at ~L3048 (step 3b, `apply -replace=doppler_service_token.inngest_arm_write`) and the key-rotation flow at L1836-1848 — both nominally covered by the file's existing "covers every occurrence in this file" Tier-B note (L1827-1831), which the §Local Terraform invocation clarification (item E below) makes actually correct. No per-site edit needed there; AC asserts the canonical section carries the AWS_* leg.
- Dated learnings prescribing the old recipe: `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md` (the "canonical invocation triplet"), `integration-issues/2026-04-05-terraform-doppler-dual-credential-pattern.md`, `bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md` (:93 "Canonical pattern"), <!-- lint-infra-ignore start -->`workflow-patterns/2026-07-07-agent-runs-terraform-apply-never-route-to-operator.md`<!-- lint-infra-ignore end --> (agent-run apply cred pattern). The corpus has an established `> **Superseded … (#N):**` blockquote convention (e.g. `2026-06-02-auto-merge-livelock-fast-moving-main.md:45`). Precision required: the old recipe still works for **read-only** invocations (plan/pull/refresh — the drift workflow uses it to this day); only state-WRITING invocations (apply, `state push`, `import`, `taint`) 403. Supersession notes must say "in part, for writes".
- **Adjacent stale sites outside the scoped sweep** (`git grep 'secrets get AWS_ACCESS_KEY_ID'`, whole repo): `infra/github/README.md` ×6 blocks (same `soleur-terraform-state` backend — `infra/github/main.tf:6`; import/`state push`/`apply` blocks are writes; already carries a partial `Superseded 2026-10-01 (#9360)` note for the App-key leg but not the `AWS_*` leg), `apps/web-platform/infra/sentry/README.md:88-89` (init+plan only → read-only → still works), `apps/cla-evidence/infra/bootstrap.sh:127-128` (runs `terraform apply -auto-approve` → broken; it is executable code), `apps/web-platform/scripts/bootstrap-live-verify.sh:62-66` (verify path → likely reads). Recorded for a follow-up issue; descoped here per the item-4 `runbooks/` bound (see Scope Check).
- Premise validation: issue #10979 OPEN (`gh issue view`), title matches; `prd_terraform` read-only pair documented at `infra-credential-tiers-8209.md` O5b row and `action.yml` comment; canonical §Local Terraform invocation exists at L898. All cited runbook sites verified at the line numbers quoted (±5). No stale premise found.
- Property list (0.6b): (P1) every runbook prescription of a state-writing local terraform invocation names a credential recipe whose `AWS_*` pair can PUT to `soleur-terraform-state`; (P2) the canonical reference the annotation notes point at documents the ambient `AWS_*` leg, so the pointer chain resolves to a working recipe; (P3) `git grep 'secrets get AWS_ACCESS_KEY_ID' -- knowledge-base/engineering/operations/runbooks/` is empty after the edits; (P4) dated learnings that call the old recipe canonical carry a supersession pointer so a future agent does not follow them into a 403.
- Cut list (0.6b): a committed CI lint enforcing the grep (regression machinery the ask does not request — the one-shot grep AC covers this PR; candidate follow-up, not built); rewriting `infra/github/README.md` and the two scripts in this PR (outside the `runbooks/` bound; scripts are code — follow-up issue recommended).
- Open Code-Review Overlap: None — `gh issue list --label code-review` bodies checked against all four runbook paths; zero matches.

## Problem Statement / Motivation

`prd_terraform`'s `AWS_*` pair 403s on PUT to `soleur-terraform-state` by design (O5b — a branch actor must not be able to forge state). Docs that still tell a reader to export it for an apply are armed traps: the Doppler-side write succeeds, the S3 state push fails mid-apply, and the repo is left with `errored.tfstate` and a fork risk on prod state. The 2026-10-24 `inngest_config_digest` promotion hit exactly this. Separately, `inngest-config-refresh.md`'s `TF_VAR_inngest_config_digest` phrasing already caused one mis-set of a `TF_VAR_`-prefixed Doppler secret (stray deleted outside this PR).

## Proposed Solution

Per-file doc edits, all prescribing the same canonical post-cutover recipe (verified against issue #10979's stated correct form):

```bash
# Backend (read/write) — Tier B; the tf-var transformer renames injected
# secrets, so the S3 backend's bare AWS_* must come from the ambient env:
export AWS_ACCESS_KEY_ID=$(doppler secrets get TF_STATE_AWS_ACCESS_KEY_ID -p soleur-infra-privileged -c prd --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get TF_STATE_AWS_SECRET_ACCESS_KEY -p soleur-infra-privileged -c prd --plain)

# Variables — outer Tier-B loader, inner prd_terraform with --preserve-env:
doppler run -p soleur-infra-privileged -c prd --name-transformer tf-var -- \
  doppler run -p soleur -c prd_terraform --name-transformer tf-var --preserve-env -- \
  terraform -chdir=apps/web-platform/infra <cmd>
```

(The issue body spells the same thing with explicit `TF_VAR_hcloud_token`/`TF_VAR_doppler_token_tf`/`TF_VAR_cf_api_token_r2` exports + single `--preserve-env` loader; the nested form is the one every existing annotation note names "canonical" and auto-covers future Tier-B additions. Either satisfies ACs; prefer the nested form for consistency.)

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` — §Local Terraform invocation (after ~L916): add a paragraph stating the loaders inject `TF_VAR_*` only; the S3 backend reads bare `AWS_*` from ambient env, so for a state-WRITING invocation export the Tier-B pair (`TF_STATE_AWS_*` → `AWS_*`, recipe lines above) before invoking; the `prd_terraform` pair suffices for read-only commands. Note also that the inner loader's transformed `TF_VAR_aws_*` (from `prd_terraform`'s read-only pair) is undeclared-var noise the backend never reads — harmless, but worth one sentence so a reader does not mistake it for the credential path. Load-bearing: every annotation note in other runbooks points here as canonical.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — Cutover step 0 (~L2455): replace the two `export AWS_*=…prd_terraform…` lines with the recipe above (exports + nested loader for the apply; `terraform -chdir=apps/web-platform/infra init -input=false` stays bare — it reads the ambient `AWS_*` directly and needs no transformer, per the canonical triplet). Keep the rest of the block (`init`, `doppler secrets get INNGEST_REDIS_PASSWORD -p soleur -c prd` verification) unchanged. Add a one-line why: post-O5b the `prd_terraform` pair is read-only and PUTs 403.
- `knowledge-base/engineering/operations/runbooks/grok-build-hetzner-dogfood.md` — ~L40-64: rewrite the operator-local apply block to the recipe above (exports + bare `terraform init` + nested loader, keeping `env TF_VAR_enable_grok_dogfood=true` on the inner command and both `-target` sets), and reword the caveat note so it explains the form instead of flagging the block as pre-cutover (keep the pointer to §Local Terraform invocation).
- `knowledge-base/engineering/operations/runbooks/inngest-config-refresh.md` — step 3 (~L73): name `INNGEST_CONFIG_DIGEST` in `soleur/prd_terraform` explicitly as the secret to set; note the tf-var transformer surfaces it to terraform as `TF_VAR_inngest_config_digest` and that a secret literally named `TF_VAR_inngest_config_digest` arrives as `TF_VAR_tf_var_inngest_config_digest` (undeclared-var noise — the mis-set already observed); add the state-write credential pointer (this apply needs the Tier-B `AWS_*` export leg).
- `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` — at the `tf()` wrapper definition (~L457): add a short annotation that the wrapper feeds the backend from ambient `AWS_*`, which for the step-5 `tf state push` (a write) must be the Tier-B read/write pair exported per §Local Terraform invocation — while the §Route-B `state pull` (~L509) reads `prd_terraform` `AWS_*` via `--only-secrets` (no transformer), a read for which the read-only pair is correct.
- `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md` — `> **Superseded in part (2026-10-24, #10979):**` note at the "canonical invocation triplet" block: still correct for read-only invocations; for writes, `AWS_*` now sources from `TF_STATE_AWS_*` in `soleur-infra-privileged/prd` (O5b/ADR-241).
- `knowledge-base/project/learnings/integration-issues/2026-04-05-terraform-doppler-dual-credential-pattern.md` — same partial-supersession note at its recipe block.
- `knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md` — same note on the :93 "Canonical pattern" bullet (drift reads remain valid; the operator-manual apply ritual's export source moved).
- `knowledge-base/project/learnings/workflow-patterns/2026-07-07-agent-runs-terraform-apply-never-route-to-operator.md` — same note at its cred-pattern block (an apply is a write; the `AWS_*` source is Tier B).
- `infra/github/README.md` — (CTO ruling 2026-10-24, Item B: widened into this PR — same defect class on the same `soleur-terraform-state` bucket, `infra/github/main.tf:5-6`; still `*.md`, still docs-only.) Six `export AWS_*=…prd_terraform…` blocks (`:57,:333,:367,:443,:627,:675`) feed write-path prescriptions — `import` (`:314,:338,:372,:452,:636`), `apply` (`:318,:641`), `state push` (`:691`) — and the existing `Superseded 2026-10-01 (#9360)` notes (`:272,:347,:500,:621`) cover only the App-key leg while the `AWS_*` leg still routes to the 403. Rewrite each write-path block to the canonical recipe (Tier-B `AWS_*` ambient export from `TF_STATE_AWS_*` + loaders per §Local Terraform invocation) and amend each #9360 note to name the `AWS_*` leg. Read-only `plan` blocks may keep either pair — normalize to the write pair for consistency.

## Files to Create

None. (`knowledge-base/project/specs/feat-one-shot-10979-runbook-cred-drift/tasks.md` is generated by the plan pipeline, not a work-phase deliverable.)

## Technical Considerations

- The fix is textual; the risk is *recipe accuracy*. Every prescribed line was verified against: the issue body's operator-verified recipe, `infra-credential-tiers-8209.md` §Local Terraform invocation + O5b/O10 rows, the `infra-credentials` action's `TF_STATE_AWS_*`→`AWS_*` alias (`.github/actions/infra-credentials/action.yml` L393-422), and the workflow comment that ambient `AWS_*` pass `--name-transformer tf-var` untouched (`.github/workflows/apply-web-platform-infra.yml` ~L1241).
- Read-vs-write precision is the whole defect: do NOT blanket-replace `prd_terraform` `AWS_*` reads — read-only invocations (`plan`, `state pull`, `refresh`) still work on the read-only pair, and learnings notes must say "in part, for writes".
- `errored.tfstate` side-note (context only, not a deliverable): the runbooks already warn R2 has no state lock (`use_lockfile = false`, `main.tf:17`); a mid-apply 403 is exactly the fork scenario the credential tier exists to bound.

## User-Brand Impact

- **If this lands broken, the user experiences:** a runbook reader reproduces the mid-apply state-push 403, leaving `errored.tfstate` and a state-fork risk on `soleur-terraform-state` — an operator-facing ops failure, no end-user surface.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the diff moves secret *names* and Doppler project/config paths between doc lines; no values are printed or stored.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal runbook text with no end-user-facing artifact; worst case is an already-observed internal ops failure mode, not a user breach.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — docs-only change to internal ops runbooks, aligning text with ADR-241 (already decided; no new architecture, no vendor/procurement, no UI surface, no legal or marketing surface). Engineering adjacency was assessed and declined: the credential-tier decision itself is recorded; this change does not revisit it.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "inngest-server.md §Cutover step 0 (~line 2455): replace the export AWS_* from prd_terraform recipe with the canonical post-cutover form" [issue #10979 scope] | inngest-server.md edit | mapped |
| 2 | "grok-build-hetzner-dogfood.md (~line 47): … update the code block to the canonical wrapped-loader form (its caveat note already points at infra-credential-tiers-8209.md §Local Terraform invocation; make the block match the note)" [issue #10979 scope] | grok-build-hetzner-dogfood.md edit | mapped |
| 3 | "inngest-config-refresh.md step 3 (~line 73): name the Doppler secret INNGEST_CONFIG_DIGEST in soleur/prd_terraform explicitly" [issue #10979 scope] | inngest-config-refresh.md edit | mapped |
| 4 | "Sweep: after edits, git grep 'secrets get AWS_ACCESS_KEY_ID' -- 'knowledge-base/engineering/operations/runbooks/' must return zero hits" [issue #10979 scope] | AC-1 + verification step in tasks | mapped |
| 5 | "whether inngest-luks-cutover-6894.md's state-repair tf() wrapper (~line 457, a state-WRITING path) needs the same Tier-B annotation — its state pull at ~line 509 is read-only and correct. Also whether dated learnings … warrant a supersession note" [issue #10979 scope] | luks-cutover annotation + 4 learnings notes (both resolved YES — see Research Insights) | mapped |
| 6 | "Docs-only change — no product code, no workflow edits" [issue #10979 scope] | Files-to-Edit list (all `*.md` under `knowledge-base/`) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| inngest-server.md step-0 rewrite | ask 1 | asked |
| grok-build-hetzner-dogfood.md block+note | ask 2 | asked |
| inngest-config-refresh.md step-3 rewrite | ask 3 | asked |
| runbooks/ zero-grep AC | ask 4 | asked |
| luks-cutover tf() annotation | ask 5 | asked |
| four learnings supersession notes | ask 5 | asked |
| `infra-credential-tiers-8209.md` §Local Terraform invocation AWS_* paragraph | — | inferred — justification: every site note points at that section as "canonical form"; it documents the loaders but not the backend's ambient `AWS_*` leg, so a reader following the pointer still 403s on state writes. Required for ask 1/2's "canonical form" to actually resolve. |
| step-3 state-write credential pointer sentence in inngest-config-refresh.md | "the TF_VAR_inngest_config_digest phrasing caused a mis-set" + incident context ("manual apply that writes state … 403s") | inferred — justification: step 3's interim route is a manual targeted apply (a state write); without the pointer the clarified text still routes the reader to the 403. |
| follow-up issue recommendation for `infra/github/README.md`, `apps/web-platform/infra/sentry/README.md`, `apps/cla-evidence/infra/bootstrap.sh`, `apps/web-platform/scripts/bootstrap-live-verify.sh` | — | inferred — justification: issue body says "any other runbook … is stale — grep", but scope item 4 bounds the AC to `runbooks/`; recorded and descoped rather than silently folded in. |

### Split Assessment

- Subsystems touched: 1 — `knowledge-base/`
- Planned files: 9 (8 edits + tasks.md) | Estimated changed lines: ~90
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC-1: `git grep 'secrets get AWS_ACCESS_KEY_ID' -- 'knowledge-base/engineering/operations/runbooks/' infra/github/README.md` returns zero hits.
- [ ] AC-2: `inngest-server.md` Cutover step 0 contains no `export AWS_` sourced from `prd_terraform`; its terraform apply is wrapped per the canonical post-cutover form (Tier-B `AWS_*` export + loader with `--preserve-env` on the inner `prd_terraform` pass).
- [ ] AC-3: `grok-build-hetzner-dogfood.md`'s local apply block uses the canonical wrapped-loader form and the caveat note no longer calls the block "the PRE-cutover one".
- [ ] AC-4: `inngest-config-refresh.md` step 3 names `INNGEST_CONFIG_DIGEST` in `soleur/prd_terraform` explicitly and warns that a literal `TF_VAR_`-prefixed secret name lands as `TF_VAR_tf_var_inngest_config_digest`.
- [ ] AC-5: `inngest-luks-cutover-6894.md`'s `tf()` wrapper carries a Tier-B `AWS_*` annotation distinguishing the step-5 `state push` (write) from the Route-B `state pull` (read, read-only pair correct).
- [ ] AC-6: `infra-credential-tiers-8209.md` §Local Terraform invocation documents that the loaders inject `TF_VAR_*` only and the backend's bare `AWS_*` must be exported from `TF_STATE_AWS_*` for state-writing invocations.
- [ ] AC-7: each of the four dated learnings carries a `Superseded in part (2026-10-24, #10979)` note scoped to state-writing invocations.
- [ ] AC-8: `git diff --name-only origin/main...HEAD` touches only `*.md` files under `knowledge-base/` (the runbooks, the learnings, and this feature's `specs/`+`plans/` pipeline artifacts) plus `infra/github/README.md` — no product code, no workflow files, no `apps/` or `.github/` paths.
- [ ] AC-9: every `secrets get AWS_ACCESS_KEY_ID` block in `infra/github/README.md` feeding a state-writing invocation (`import`/`apply`/`state push`) prescribes the canonical recipe, and each pre-existing `Superseded 2026-10-01 (#9360)` note is amended to name the `AWS_*` leg alongside the App-key leg.
- [ ] AC-10: a follow-up issue covering `apps/cla-evidence/infra/bootstrap.sh` and `apps/web-platform/scripts/bootstrap-live-verify.sh` (both export `prd_terraform` `AWS_*` then run `terraform apply -auto-approve` — executable code, live 403-armed; `bootstrap-live-verify.sh` is the documented leak-rotation path) is filed before the PR ships (CTO ruling: mandatory ship gate). **Filed: #10990.**

## Test Scenarios

Docs-only change; verification is grep/read-based, not suite-based.

- Given the edits land, when `git grep 'secrets get AWS_ACCESS_KEY_ID' -- 'knowledge-base/engineering/operations/runbooks/'` runs, then it exits non-zero with no output (zero hits).
- Given a reader follows `inngest-server.md` step 0 verbatim, when they reach the apply, then the prescribed shell holds `AWS_*` sourced from `soleur-infra-privileged/prd` `TF_STATE_AWS_*` and a `--preserve-env` inner loader.
- Given a reader greps the four learnings for the recipe, when they read the recipe block, then a dated supersession note is adjacent and names the write-path correction.
- Regression: the Route-B `state pull` (~L509) and drift-workflow read-only uses of `prd_terraform` `AWS_*` are untouched — the notes scope the supersession to writes.

## Success Metrics

Zero remaining runbook prescriptions of `prd_terraform` `AWS_*` for writing invocations; the canonical reference section self-containedly explains the ambient `AWS_*` leg; no new `secrets get AWS_ACCESS_KEY_ID` hits under `runbooks/`.

## Dependencies & Risks

- No code or CI changes; risk is prose accuracy — mitigated by quoting the incident-verified recipe and anchoring to `infra-credential-tiers-8209.md` §Local Terraform invocation.
- Adjacent stale sites: `infra/github/README.md` was widened into this PR by CTO ruling (Item B). The two scripts remain: `apps/cla-evidence/infra/bootstrap.sh` (`:127-141` — exports the read-only pair then `terraform apply -auto-approve`) and `apps/web-platform/scripts/bootstrap-live-verify.sh` (`:62-70` export + `:84-87` `terraform apply -auto-approve`; the documented leak-rotation path) are both state-WRITING — the earlier "likely reads" characterization was wrong — and stay descoped as executable code; their fix is a follow-up issue that MUST be filed before this PR ships (AC-10). `apps/web-platform/infra/sentry/README.md` is init+plan only — still works, no fix.
- Plan-review panel and domain leaders were not spawned (no Task-capable subagent available in this planning context) — a sequential self-review was performed instead (`Reviewed-Coverage: sequential-fallback`).

## References & Research

- Canonical recipe authority: issue #10979 body ("Correct recipe for a manual apps/web-platform/infra apply") + `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` §Local Terraform invocation (L898-916), O5b row (~L303), O10 row (~L307).
- CI mechanism proving the ambient-AWS leg: `.github/actions/infra-credentials/action.yml` L393-422; `.github/workflows/apply-web-platform-infra.yml` ~L1241 comment + "Extract backend credentials" step.
- Variable/secret-name proof for AC-4: `apps/web-platform/infra/variables.tf:677`, `apps/web-platform/infra/inngest-config-digest.tf:31,43`.
- Supersession-note convention: `knowledge-base/project/learnings/2026-06-02-auto-merge-livelock-fast-moving-main.md:45`.
- Prior annotation convention: `inngest-server.md` L1827-1831, `admin-ip-drift.md` ~L160-166, `cloudflare-service-token-rotation.md` ~L33-38.
