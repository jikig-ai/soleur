---
title: "fix(infra): apply-github-infra mints from the evicted soleur-ai key — move it to the Tier-B soleur-infra App"
type: fix
date: 2026-10-01
slug: fix-retier-apply-github-infra-app-identity
branch: feat-one-shot-retier-apply-github-infra-app
issue: 8209
closes: []
priority: p1-high
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix(infra): move apply-github-infra's App identity to the Tier-B soleur-infra App

## Enhancement Summary

**Deepened on:** 2026-10-01
**Sections enhanced:** Proposed Solution (A, B, D, Deferred), Implementation Phases (0, 4, 5),
Acceptance Criteria, User-Brand Impact, Architecture Decision, Observability.
**Agents used:**

- `soleur:engineering:review:security-sentinel`;
- `soleur:engineering:review:architecture-strategist`;
- a mechanical verify-the-negative, attribution and self-audit pass;
- earlier, the plan-review panel (DHH, Kieran, code simplicity, CTO) and the scoped advisor consult.

### Key Improvements

1. **Kill switch made reliable.** With `squash_merge_commit_message=COMMIT_MESSAGES`, a token in a
   commit **subject** becomes `* <subject>` or gets a `(#N)` suffix appended, which defeats the preflight's
   line-anchored regex. The token must be a commit **body** line. It is also passed explicitly with
   `gh pr merge --auto --squash --body-file`. AC3 reads `%b`, not `%B`.
2. **Records completed.**
   - Three more `model.c4` phrases in the `github -> soleurMarketplace` edge become false; the
     known-gap clause also goes on the edge.
   - ADR-032 §Authentication gets a dated "superseded by ADR-241 D5" line.
   - The runbook's O4/O13 chain gains "this PR + proof run" as a precondition.
   - The D5 Statuses row gains one flip-blocking sentence, so a later green no-op cannot flip D5
     while the manifest write path is known to be broken.
3. **Token handling tightened.**
   - The revoke step keys on `steps.mint.outcome`.
   - `entrypoint_audit` scopes `GH_TOKEN` to the one `gh issue comment` line.
   - The User-Brand leak text no longer overstates the scoped token's role: the job already holds
     the soleur-infra PEM.

### New Considerations Discovered

- **A pre-existing branch-plant path, filed as a tracked issue (Phase 0.2), not folded in.** Until
  O11, `DOPPLER_TOKEN_WRITE` can plant `ACTIONS_INTEGRATION_ID` / `CODEQL_INTEGRATION_ID` /
  `GH_OWNER` / `GH_REPO` in `prd_terraform`. `--name-transformer tf-var` then feeds them to
  Terraform and rebinds the required checks in place. That change is invisible to the count-only
  destroy guard and verify.
  - Pinning job-level env literals was considered and not adopted: they would silently override
    any future `variables.tf` default change.
  - It predates this PR (`wg-when-an-audit-identifies-pre-existing`).
- **O13 depends on this PR.** Every O13 rotation sub-step runs the O4 canary, which includes a
  no-op `apply-github-infra`, and that has been red since O10.

## Overview

Since operator step O10 of #8209 (2026-10-01), every run of `apply-github-infra.yml` fails. Its own
"Fetch GitHub App credentials from Doppler" step still reads the soleur-ai App key from Doppler
`soleur/prd_terraform`. O10 replaced that key with the `EVICTED_SEE_ADR_241` sentinel, so the step
refuses it by name with `verdict=legacy_app_key_evicted`. This was measured on run 36839787788
(2026-10-01 08:59Z, `workflow_dispatch` on `main`): the loader reported `source=tier_b exported=10`,
and the job then died at the fetch step.

The Terraform side does not need fixing. `infra/github/main.tf`'s provider already selects **INFRA
mode** (the soleur-infra App) whenever the loader exports a non-empty
`TF_VAR_github_infra_app_private_key`. The 2026-09-29 canary, run 36539258756 (`source=tier_b`),
refreshed every `infra/github` resource on both repositories in that mode and planned "No changes".
What still depends on the evicted key is the workflow's own scaffolding:

1. the fetch step, which this fix deletes, and
2. the post-apply verify step's inline JWT mint, which signs with that PEM against the soleur-ai
   installation `122213433`.

The dispatch-only `entrypoint_audit` job of `apply-web-platform-infra.yml` has the same defect. It
mints a soleur-ai token from the same evicted key, solely to post a comment on #6767.

This PR moves both workflows off the evicted key:

- **`apply-github-infra.yml`** mints its verify token from the existing
  `.github/actions/mint-infra-app-token` composite (soleur-infra, installation `166065653`). It mints
  **before** Terraform runs, which also turns the composite's exact-grant and exact-repositories
  checks into a per-run proof that the installation covers both managed repositories.
- **`entrypoint_audit`** posts with the job's own `github.token`. Its job already declares
  `issues: write`, and the soleur-infra App has no `issues` permission.
- **Census:** G4e's live count moves from a floor of 3 to an exact 1. A clause is added that no
  reading site sits in a Tier-B job.
- **Records:** ADR-241 gets a dated note, and the runbooks, `infra/github/README.md` and the C4 edge
  are corrected.

No key is restored into `prd_terraform`.

**Merge side effect.** `apply-github-infra.yml` does not fire on merge, because no `infra/github/*.tf`
path is touched. `apply-web-platform-infra.yml` **does** list itself in its own `on.push.paths`. So a
merge that edits it would start its full push `apply`, unless the squash commit carries
`[skip-web-platform-apply]` on its own line (see Phase 4). The single authorized post-merge dispatch
is a no-op `apply-github-infra` run that proves `source=tier_b` end to end.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Problem Statement

- **Symptom:** `apply-github-infra.yml` is red on every trigger:
  - push-to-main on `infra/github/**`;
  - manual dispatch;
  - the unattended reconcile that `scheduled-marketplace-drift.yml` dispatches on a content-drift
    verdict (#7493).

  Ruleset changes and marketplace-manifest reconciles cannot land. The CI-required ruleset
  (`14145388`), the CLA ruleset (`13304872`) and the marketplace ruleset are frozen at their
  last-applied state.
- **Root cause:** #8209 moved the Terraform **provider** to the Tier-B identity (D5's three-mode
  selector) and moved every other App-token consumer (#9262). It did not move the two inline mints
  above. Census row G4e asserts only that every reader of `GITHUB_APP_PRIVATE_KEY` refuses the
  sentinel *by name*, and floors the reader count at 3. Both readers do refuse it, so G4e stayed
  green on a job that could no longer run. Nothing asserted that a **Tier-B** job reads that name
  at all.
- **Why now:** O10 ran on 2026-10-01. Before O10, the fetch read a still-valid soleur-ai key, so the
  defect was latent: the provider ran as soleur-infra while the verify step ran as soleur-ai.

## Research Reconciliation — Spec vs. Codebase

| Claim (task / prior docs) | Reality (measured 2026-10-01) | Plan response |
|---|---|---|
| "apply-github-infra mints its GitHub App token from the soleur-ai key" | The **provider** has run as soleur-infra since 2026-09-29. The loader exports `TF_VAR_github_infra_app_*`, and `main.tf` selects INFRA mode on non-emptiness. Only the workflow's fetch and verify steps still use the soleur-ai key. | Leave `infra/github/*.tf` alone. Fix only the two workflow steps. |
| "Move entrypoint_audit's App credentials to that Tier-B App" | soleur-infra's live grant is `actions, administration, contents, environments, metadata, pull_requests, secrets`. It has **no `issues`**, and the job's only App use is `gh issue comment` on #6767. | Use the job's own `github.token` (the job already declares `issues: write`). Widening an admin-capable App with `issues:write` would need an operator acceptance step and buys nothing. CTO: B1. |
| "Verify soleur-infra installation covers every repo infra/github manages" | `infra/github` manages exactly two repositories. `jikig-ai/soleur` holds rulesets `ci_required` and `cla_required`. `jikig-ai/soleur-marketplace` holds `github_repository`, `github_branch_default`, ruleset `marketplace_pr_required` and `github_repository_file`. The local user token cannot list a selected installation's repositories (`GET /user/installations/166065653/repositories` returns 403). The INFRA-mode refresh on 2026-09-29 read all of them with "No changes", which is indirect evidence that both are selected. | Make coverage a **per-run, fail-closed** check: mint with `repositories: soleur,soleur-marketplace` **before** the first Terraform step. GitHub returns 422 for a repository outside the installation, and the composite's exact-repositories check refuses anything else. |
| "Permissions cover the managed resource types" | Rulesets, repository settings and the default branch need `administration:write`. `github_repository_file` needs `contents:write`. Both are granted. **But** the marketplace ruleset's `bypass_actors` names the soleur-ai App (`Integration 3261325`), not soleur-infra (`5118911`). A future manifest write as soleur-infra will be refused by the "Marketplace PR Required" ruleset. | A **known gap, deferred P1** to a follow-up PR that must touch `infra/github/*.tf`. Merging it auto-applies a production ruleset write, which needs its own authorization. The follow-up is filed in Phase 0. See §Deferred. |
| "Post-apply verify needs Administration:Read" (learning 2026-05-25) | GitHub docs: `bypass_actors` "is only returned if the user making the API request has write access to the ruleset". `scripts/verify-marketplace-ruleset.sh` asserts the bypass set (`.bypass_actors // []`, so a missing key fails as an empty set). | The scoped token requests `{"administration":"write"}`, which is narrower than the unscoped installation token the provider already holds in the same job. It is revoked after use. |
| Census G4e "floor 3" | Three live readers: `apply-github-infra`, `board-status-sync` (legacy arm), and `apply-web-platform-infra::entrypoint_audit`. | Two leave, so the live count goes to an exact `== 1`, with a dated rationale. `board-status-sync` stays a Tier-A reader: it mints `soleur-board` first, and its runs on 2026-10-01 are green. Deleting its now-dead legacy arm is a scope question, recorded in `decision-challenges.md`. |
| (implicit) "a workflows-only PR does not touch production" | `apply-web-platform-infra.yml`'s `on.push.paths` lists the file itself. Measured: PR #7617's squash message did not carry a `[skip-web-platform-apply]` token placed only in the PR **body**, and run 32293304282 applied unattended (commit ce69b92463, runbook note). | Put `[skip-web-platform-apply]` on its own line in a **branch commit message**. Then verify that the merge commit carries it and that the push run's preflight logged the kill switch. |

## Proposed Solution

### A. `.github/workflows/apply-github-infra.yml` (job `apply`)

1. **Delete** step `Fetch GitHub App credentials from Doppler`, the whole step. It is the only
   writer of `TF_VAR_github_app_id`, `TF_VAR_github_app_private_key`, `APP_ID` and `APP_PEM_FILE`.
   The provider is then in INFRA mode by construction:
   - The loader exports `TF_VAR_github_infra_app_private_key` from the same Tier-B project the mint
     below reads.
   - `main.tf`'s selector ignores the legacy pair whenever that key is non-empty.
   - The `prd_terraform` sentinel that `doppler run --name-transformer tf-var` still injects as
     `TF_VAR_github_app_private_key` is therefore dead input.
2. **Add, in its place** (after `Verify required secrets present`, before `Extract backend
   credentials`), one step:
   **`Mint soleur-infra App token (administration:write on soleur, soleur-marketplace)`**, with
   `id: mint`.
   - It `uses: ./.github/actions/mint-infra-app-token` with
     `doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}`, `installation-id: "166065653"`,
     `permissions: '{"administration":"write"}'` and `repositories: soleur,soleur-marketplace`.
   - Placing it **before** Terraform makes it the job's Tier-B identity preflight. It fails closed,
     naming its cause, before any state or GitHub write, in each of these cases:
     - the environment secret is absent (`doppler-token is empty`). The loader's legacy arm is taken
       on exactly this condition, so legacy mode can never reach Terraform;
     - the Tier-B names are missing (`GITHUB_INFRA_APP_ID not readable …`);
     - the key is not a PEM (`openssl rsa -check`);
     - the installation does not cover a managed repository (GitHub's own 422 message, relayed
       sanitized);
     - the grant differs (exact-grant check).
   - Its `::notice title=app-token::app=soleur-infra installation=… permissions=…` line is the
     per-run evidence. **In this job the installation id prints as `***`**: the loader masks every
     value of the Tier-B project, and `GITHUB_INFRA_APP_INSTALLATION_ID=166065653` is one of them.
     The sibling mint jobs print the number only because they do not run the loader.
3. **Post-apply verify** (`id: verify`):
   - Drop `APP_ID`, `APP_PEM_FILE` and `INSTALLATION_ID` from `env:`, and add
     `INSTALL_TOKEN: ${{ steps.mint.outputs.token }}`. The token is a step output, never
     `$GITHUB_ENV`, so no Terraform or Doppler step sees it.
   - Delete Steps 1–2 (JWT mint and exchange) and the PEM-shred trap.
   - Keep the Steps 3–5 **assertions** unchanged; only the token source changes. Every
     `GH_TOKEN="$INSTALL_TOKEN"` site stays as is (the sweep covers three ruleset GETs plus the
     marketplace list and detail GETs).
   - Rewrite the comments that become false: "PEM file shred is handled by the EXIT trap", and
     Step 5's "the EXIT trap at the top shreds $APP_PEM_FILE … mint an installation token".
   - Fail closed if `INSTALL_TOKEN` is empty (one line).
4. **Add a final step** `Revoke the soleur-infra token` with
   `if: always() && steps.mint.outcome == 'success'`. Do not compare the secret in an expression;
   the composite already revokes on its own refusal paths. The step passes the token through
   `env:`, never as `${{ }}` inside `run:`. It does a best-effort
   `curl -sS --max-time 10 -X DELETE … /installation/token || true` and never echoes the token. This mirrors
   `mint-inngest-bootstrap-tag.yml`'s revoke-after-use. The token carries `administration:write`
   and is otherwise live for an hour, including on the failed-apply path where verify never runs.
5. **Comments only:**
   - the header's `Auth:` bullet, which said soleur-ai from `prd_terraform`, now names soleur-infra
     via the Tier-B loader plus the mint composite;
   - the import step's "App-installation scope" comment (soleur-ai `122213433`,
     `repository_selection == all`) now names soleur-infra `166065653`, `selected`, with coverage
     asserted by the mint step;
   - the verify step's "Mint a short-lived App-installation token from the soleur-ai App" comment.

### B. `.github/workflows/apply-web-platform-infra.yml` (job `entrypoint_audit`)

- Delete the job-level `INSTALLATION_ID: "122213433"` env and its comment.
- In step `Run entrypoint drift audit (read-only) and post findings to #6767`:
  - Delete the inline App mint, from the "Mint a short-lived GitHub App installation token" comment
    through the `echo "::add-mask::$INSTALL_TOKEN"` line.
  - Rewrite the next line, `GH_TOKEN="$INSTALL_TOKEN" gh issue comment …`, as
    `GH_TOKEN="$AUDIT_POST_TOKEN" gh issue comment "$AUDIT_ISSUE" --body-file /tmp/audit-body.md`.
    Leaving it as is would trip `set -u` on the unbound `INSTALL_TOKEN`.
  - Add `AUDIT_POST_TOKEN: ${{ github.token }}` to the step's `env:`. This name is not `GH_TOKEN`,
    so the earlier `preapply-entrypoint-gate.sh --audit --live` call does not inherit `gh` auth.
    The job already declares `permissions: { contents: read, issues: write }`. The token holds only
    `issues:write`, strictly narrower than the org-wide soleur-ai token it replaces. Comments now
    come from `github-actions[bot]`; nothing keys on the author.
- Leave `environment: infra-privileged`, the loader and the CF reads untouched. They are out of
  scope, and the runbook's O13 uses this job as a CI-side read proof.
- The file must stay under ADR-231's 490,000-byte cap. It is 483,707 bytes today, and this edit
  only **removes** bytes.

### C. `tests/scripts/test-infra-privileged-tier-census.sh` (row G4e only; no new row)

- **Exact pin.** The live-tree count goes from `len(app_key_sites) >= 3` to an exact `== 1`.
  - Fixture trees **also** pin `== 1`, because the pristine fixture carries exactly one reader,
    `appkey.yml`. That makes a "second reader" mutant drivable RED in CI rather than only on the
    live tree.
  - The suite already has the exact-pin precedent in `MUTANT_FLOOR`. Any new reader of the evicted
    name, Tier A or B, becomes a deliberate census edit with a dated rationale, rather than passing
    silently because it carries the refusal.
  - Add a dated comment: `# Floor 3 -> exact 1 (#<PR>): apply-github-infra and
    apply-web-platform-infra::entrypoint_audit no longer read GITHUB_APP_PRIVATE_KEY …`.
  - Add a sunset note: the row retires once `board-status-sync`'s legacy arm and the Doppler name are
    deleted.
- **Tier clause.** No reading site may sit in a job whose `env_arms` intersect
  `TIER_B_ENVIRONMENTS`. After O10 such a read can only ever return the sentinel, which is exactly
  this incident's shape. The clause is about five lines inside G4e's existing loop. It needs the
  site's job: walk `doc["jobs"]` (or `runs.steps` for a composite) rather than calling the flat
  `step_bodies`, and treat a composite as job-less, so not Tier-B. `TIER_B_ENVIRONMENTS` is a
  literal that G1d cross-checks against Terraform; it is not derived here.
- **Mutants.** Two new ones on the existing fixture:
  - `g4-e3-second-reader`: a second reading step with the refusal, added to `appkey.yml`. Expected
    RED via the pin (2 != 1). This is the "second member" row.
  - `g4-e4-tier-b-reader`: `environment: infra-privileged` added to `appkey.yml`'s job, and its
    trigger made non-PR. Expected RED via the tier clause.
- `CENSUS_ROWS` stays `38`. `MUTANT_FLOOR` (exact, currently `64`) is raised by exactly the number
  of executions the two mutants add, as measured, since `MUTANTS_RUN` increments per `mutate`. The
  assertion `FLOOR` (`175`, `-lt` only) is raised to the new measured passes-plus-fails count, with
  the existing dated-note style.

### D. Records (docs only, no behavior; only statements that are now false)

- **ADR-241**: add a dated section, `### 2026-10-01 (#<PR>): apply-github-infra and
  entrypoint_audit leave the soleur-ai key`, in the shape of the 2026-09-30 #9262 note. It records:
  - the apply path no longer reads `prd_terraform` for any GitHub identity;
  - the verify mint is the soleur-infra composite, run before Terraform;
  - `entrypoint_audit` uses `github.token`;
  - G4e moves from a floor of 3 to an exact 1, plus the tier clause;
  - the **known gap**: the marketplace bypass actor is still soleur-ai, with a link to the
    follow-up issue;
  - D5's evidence, limb by limb:
    - O4c is done, as an O10 precondition;
    - board sync is green on 2026-10-01, with run ids;
    - the apply has only a *dispatched no-op* (this plan's AC12), not an apply-on-merge.

    The new plan's ACs are named "this plan's AC12" so they cannot be confused with the #8209
    plan's AC12–AC16.

  No decision status changes. **The D5 Statuses row gains one dated sentence** (the #9262
  precedent): "and the marketplace bypass-actor follow-up has landed, with a manifest write
  exercised as soleur-infra". This blocks a premature `accepted` while a D5 write path is known to
  be broken.
- **ADR-032 §Authentication** ("The current model uses the `soleur-ai` App (id 3261325,
  installation 122213433)…") gets a dated line: "Superseded for CI applies by ADR-241 D5 (#8209):
  the soleur-infra App, installation 166065653." This is docs only.
- **Runbook `infra-credential-tiers-8209.md`:**
  - one dated note on O4/O13 (§Sequencing):
    - the chain becomes "O10 → this PR merged plus its proof run green → O13", because each O13
      sub-step re-runs the O4 canary, whose `apply-github-infra` no-op has been red since O10;
    - O4's limb about the bypass list is **open for the marketplace** until the follow-up lands, so
      an operator does not read the known gap as a fault;
  - one dated line on the Group-1 `::entrypoint_audit` row (`github.token`);
  - one dated line on the Group-2 `apply-github-infra.yml::apply` row: the credential is now
    `DOPPLER_TOKEN_INFRA_PRIVILEGED` → mint composite. A 422 at the mint means an installation
    repository-grant change, which needs operator authorization; it is not a key problem.
- **Runbook `apply-web-platform-infra-job-rationale.md` §legacy-app-key-evicted:** "Three consumers
  …" becomes one consumer (`board-status-sync.yml`'s legacy arm), with a one-line dated note.
- **`infra/github/README.md`:**
  - the Phase 0 auth paragraph: in CI the apply runs INFRA mode only;
  - the bypass-coupling paragraph: the bypass actor is still soleur-ai, which is the known gap, with
    a pointer to the follow-up.

  `*.md` files in `infra/github/` do not match the push filter `infra/github/*.tf`.
- **`.github/actions/mint-infra-app-token/action.yml`:** a description-only fix. "Three inline
  App-JWT copies still exist (board-status-sync.yml, apply-github-infra.yml,
  apply-web-platform-infra.yml)" becomes one (board-status-sync.yml), and apply-github-infra is
  named as a consumer.
- **C4 (`knowledge-base/engineering/architecture/diagrams/model.c4`):**
  - the `github -> soleurMarketplace` edge opens "as the soleur-ai App"; change it to "as the
    soleur-infra App (#8209 infra mode)";
  - the same edge's "three remaining inline readers … (apply-github-infra, board-status-sync and
    apply-web-platform-infra; census row G4e)" becomes "the one remaining reader
    (board-status-sync's legacy arm; census row G4e)";
  - three more phrases in the same edge become false:
    - "since #9262 NOT the soleur-ai credential named above" is rewritten, because the opener no
      longer names soleur-ai;
    - "legacy mode (today's soleur-ai key from prd_terraform, the BEFORE state)" becomes "legacy
      mode (the evicted key; resolves to `EVICTED_SEE_ADR_241`)";
    - "THE IDENTITY ON BOTH WRITES CHANGES" becomes "CHANGED (#<PR>)";
  - the edge also asserts that the manifest write works, so it carries the known-gap clause too;
  - the `soleurMarketplace` element's "bypassed only by … the soleur-ai App" is still **true**, and
    that is the gap. Append a known-gap clause naming the follow-up;
  - regenerate `model.likec4.json` with `bash scripts/regenerate-c4-model.sh`.

  The `github -> doppler` edge is **not** edited: its sentence about the two inngest jobs ("do NOT
  load the project through infra-credentials") stays true.

### Deferred (tracked, P1): marketplace ruleset bypass actor

**What:**

- swap `bypass_actors { actor_id = 3261325 }` for `5118911` (soleur-infra) in
  `infra/github/ruleset-marketplace-pr-required.tf` and
  `scripts/marketplace-ruleset-canonical-bypass-actors.json`, plus the
  `verify-marketplace-ruleset.test.sh` fixtures;
- `commit_author` / `commit_email` become `soleur-infra[bot]`. **Order matters:**
  `github_repository_file.marketplace_manifest` has no `depends_on` on the ruleset (`grep depends_on
  infra/github/*.tf` is empty). So either add `depends_on = [github_repository_ruleset.marketplace_pr_required]`
  in the same PR, or move the author change to a second PR. Otherwise the file write can race ahead
  of the bypass swap and get a 409;
- remove the dead legacy-mode arm in `infra/github/main.tf`;
- refresh the stale `122213433` / soleur-ai comments in `infra/github/*.tf`.

The issue body states three more things:

- **The expected plan:** rulesets updated in place; the file updated in place with **one** new
  commit, because the `commit_author` change re-commits even identical content; 0 destroyed.
- **What must ship together:** the canonical bypass JSON and the `.tf` swap, in the same PR, or
  the post-apply verify goes red.
- **What its merge proves:** the merge apply runs as soleur-infra, so its post-apply verify and
  its manifest write supply D5's write-limb evidence. It also carries the explicit production-apply authorization request
that its merge needs. The title contains "Repository rule violations", so searching for the 409 text
finds it.

**Why not here:**

- Every one of those edits is under `infra/github/*.tf` or alters the verify canonical. Merging it
  auto-triggers a **production ruleset write** on push, and this session authorizes only one
  post-merge no-op proof dispatch.
- It is also a security decision. The CTO recommends **swap, not add**: soleur-ai's runtime key sits
  on the web host, so keeping it as a bypass actor turns a web-host compromise into a supply-chain
  push.

**Safety of deferring:**

- It fails loud and does no damage. A content-drift reconcile that fires before the follow-up lands
  changes only `github_repository_file.marketplace_manifest`, which is refused (409, repository rule
  violations). The published file and state are unchanged, the run goes red, and the drift issue
  stays open.
- That is strictly better than today, where every apply dies at the fetch.
- A combined ruleset-plus-manifest change could apply partially (R5). The follow-up issue blocks
  such edits until it lands.

**Re-evaluation:** the next `infra/github` PR. The work phase files the issue as Phase 0, task 0.1.

## Implementation Phases

**Phase 0 — tracking (before code)**

- 0.1 File the follow-up issue, with the §Deferred text as its body. Title: "infra(github):
  Repository rule violations on marketplace manifest writes — bypass actor still names soleur-ai
  (3261325), swap to soleur-infra (5118911)". Labels `priority/p1-high`, `domain/engineering`,
  `type/security`. Milestone per `knowledge-base/product/roadmap.md`. Link it from the ADR-241 note
  and the README.

- 0.2 File the pre-existing finding (security review P1-B) as its own issue. Title:
  "infra(github): prd_terraform-planted ACTIONS/CODEQL_INTEGRATION_ID or GH_OWNER/GH_REPO reach
  Terraform via tf-var and rebind required checks in place".
  - Labels: `priority/p1-high`, `domain/engineering`, `type/security`.
  - Body: the path; why the count-only destroy guard and verify miss it; the candidate fixes
    (verify asserts integration ids and contexts by value; or a `--only-secrets` allowlist on the
    tf-var `doppler run`; or O11 closes it).
  - Why job-level env pins were rejected: they would silently override future `variables.tf`
    defaults.

**Phase 1 — failing census first (RED)**

- 1.1 Change G4e to the exact pin plus the tier clause, and add mutants `g4-e3` and `g4-e4`. Run
  `bash tests/scripts/test-infra-privileged-tier-census.sh`. **Expected RED on the live tree**:
  G4e reports 3 sites (pin `== 1` violated), and its tier clause names `apply-github-infra.yml` and
  `apply-web-platform-infra.yml`. This is the reproduction, in a static form.

**Phase 2 — workflows (GREEN)**

- 2.1 `apply-github-infra.yml` edits A.1–A.5.
- 2.2 `apply-web-platform-infra.yml` edit B. Byte check:
  `wc -c .github/workflows/apply-web-platform-infra.yml` stays `< 490000`.
- 2.3 Re-run the census: all rows green and every mutant RED. Set `MUTANT_FLOOR` and `FLOOR` to the
  measured counts.
- 2.4 Run the composite's own suites unchanged
  (`bash .github/scripts/test/test-mint-inngest-bootstrap-tag.sh` and
  `bash .github/scripts/test/test-bump-inngest-bootstrap-pin.sh`). Their one-minter/S19 rows read
  only their own workflow files. Also run `bash tests/scripts/test-preapply-entrypoint-gate.sh`,
  whose D2 shape test covers `entrypoint_audit`.
- 2.5 Run the workflow lints the repo runs on PRs over both files: actionlint,
  `scripts/lint-workflow-step-env-refs.py`, `scripts/lint-workflow-local-action-checkout.py`,
  `lint-workflow-issue-write-scope` and the SHA-pin lint.

**Phase 3 — records**

- 3.1 ADR-241 dated section.
- 3.2 The two runbooks (one-line dated notes).
- 3.3 `infra/github/README.md` and the mint composite description.
- 3.4 `model.c4` edge and element. Then run `bash scripts/regenerate-c4-model.sh`,
  `bash plugins/soleur/test/c4-model-freshness.test.sh` and
  `bash plugins/soleur/test/c4-count-parity.test.sh`.

**Phase 4 — ship (UNTRUSTED-CI, auto-merge only)**

- 4.1 Commit with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test` and rely on CI. **At least one
  branch commit carries `[skip-web-platform-apply]` as a line of its message BODY, never its
  subject.**
  - The repo's `squash_merge_commit_message=COMMIT_MESSAGES` setting rewrites a multi-commit
    squash's subjects as `* <subject>`, and appends a `(#N)` suffix to a single-commit squash's subject.
    Either breaks the preflight's `(^|\n)\[skip-web-platform-apply\]($|\n)` match.
  - A token only in the PR body is lost entirely (PR #7617).
  - **Also arm auto-merge with an explicit body:**
    `gh pr merge <N> --auto --squash --body-file <f>`, where `<f>` contains the token on its own
    line. An explicit body replaces the generated one, so this holds even if the branch is
    squashed or rebased later. The PR body's
  first line answers "does merging this alone mutate production?": **No**, because:
  - `apply-github-infra.yml`'s `paths:` are untouched;
  - `apply-web-platform-infra.yml`'s self-triggered push apply is skipped by the kill switch;
  - `entrypoint_audit` is dispatch-only.

  The only production action is the single authorized post-merge proof dispatch.
- 4.2 Assert against the merge-base that the diff touches none of these, so the merge fires no
  `apply-github-infra` push:
  - `infra/github/*.tf`;
  - `infra/github/.terraform.lock.hcl`;
  - `infra/github/soleur-marketplace-manifest.json`;
  - `tests/scripts/lib/destroy-guard-filter.jq`.
- 4.3 Required checks are green **by name on the exact head SHA**. Auto-merge only.

**Phase 5 — post-merge proof (the one authorized production dispatch)**

- 5.0 Two prechecks, both read-only.
  - **Kill switch held.** `git log -1 --format=%B <merge-sha> | grep -x '\[skip-web-platform-apply\]'`
    matches, and the merge's `apply-web-platform-infra` push run shows preflight
    `Kill switch detected` with `apply` skipped. If it did not hold, report it at once: an
    unauthorized apply ran.
  - **No drift**, so the proof stays a no-op. Run
    `git diff --quiet 38d64df696 <merge-sha> -- 'infra/github/*.tf' infra/github/.terraform.lock.hcl infra/github/soleur-marketplace-manifest.json tests/scripts/lib/destroy-guard-filter.jq`.
    The paths are limited to the push filter, because this PR edits `infra/github/README.md`.
    `38d64df696` is the head of the last green apply (run 36539258756). The only later run,
    36839787788, failed before Terraform. The assumption is that no `infra/github` push-filter
    change merged since. If the check reports a difference, stop: the dispatch would apply
    unapplied declarations, a production write beyond the authorized proof. Report it instead.
- 5.1 Dispatch the proof:
  `T=$(date -u +%FT%TZ); gh workflow run apply-github-infra.yml -R jikig-ai/soleur --ref main -f reason="#8209 O10 fix-forward proof: Tier-B identity (no-op)"`.
  Resolve the run id in a bounded until-loop. Filter on `event == workflow_dispatch`,
  `createdAt >= T` and the actor being this session's `gh` user, so the scheduled drift
  reconcile's dispatch is never picked up by mistake. Then arm a Monitor until-loop on
  `gh run view <id> --json status,conclusion`, never a background sleep.
- 5.2 Pass criteria: exactly AC12.
- 5.3 **Not dispatched**, because there is no authorization: `apply-web-platform-infra.yml` with
  `apply_target=entrypoint-audit`. Its change is proven statically, by census G4e plus the
  `test-preapply-entrypoint-gate.sh` D2 shape test and diff review. Offer the dispatch as an
  optional, separately authorized step.

## Files to Edit

- `.github/workflows/apply-github-infra.yml`
- `.github/workflows/apply-web-platform-infra.yml`
- `.github/actions/mint-infra-app-token/action.yml` (`description:` text only)
- `tests/scripts/test-infra-privileged-tier-census.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`
- `knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md` (one dated line)
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`
- `infra/github/README.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated, not hand-edited)

Pipeline-written files also land in the diff: `knowledge-base/project/specs/<branch>/` artifacts
and any generated index.

## Files to Create

None. The census mutants run on the census script's own generated fixture tree (`appkey.yml`).

## Alternative Approaches Considered

| Option | Why not |
|---|---|
| Restore a soleur-ai key into `prd_terraform` | Undoes O10 on a config every branch can read. Explicitly forbidden (ADR-241 D5, runbook O10). |
| Keep the fetch step and read `GITHUB_INFRA_APP_*` from `$GITHUB_ENV` to drive the existing inline JWT | It is a fourth inline copy of the JWT recipe. The repo already has one tested composite that mints this identity with exact-grant and exact-repositories checks (#9262). |
| Mint the verify token *after* apply, at the old verify position | It loses the pre-apply coverage proof. A missing repository would surface as a provider 404 mid-apply ("Not Found", not "Forbidden"; see the import-step comment) instead of a named refusal before any write. |
| Scoped `{"administration":"read"}` | `bypass_actors` is omitted for callers without write access to the ruleset, so `verify-marketplace-ruleset.sh` would fail every run. A weaker assertion would fail open. |
| `entrypoint_audit`: widen soleur-infra with `issues:write` (B2) | Gives an `administration:write` App a new scope, and needs an operator App-permission acceptance. `github.token` already holds exactly this grant, job-scoped. |
| Fold the marketplace bypass swap in here | Its merge auto-applies a production ruleset write that is not authorized in this session, and it is a security decision of its own. Deferred P1 (§Deferred). |
| Pre-apply refusal `manifest_write_blocked_bypass_gap` when the plan touches `github_repository_file.marketplace_manifest` (CTO optional; advisor) | Cut. The 409 is already loud and leaves no damage, and the follow-up removes the gap. A guard whose only purpose expires with the next PR is machinery to delete. |
| An assert-and-pin step: `tier_b_identity_missing` plus an empty legacy `TF_VAR_github_app_*` export (advisor; dropped at plan review) | The mint fails first on the same condition the loader's legacy arm keys on (an empty `DOPPLER_TOKEN_INFRA_PRIVILEGED`). Both read the same Tier-B project, and `main.tf` ignores the legacy pair whenever the infra key is set. So it would re-check the same fact through a second channel. DHH and code simplicity both cut it. |
| A new census row G4g, "no Tier-B job reads the key", with 3 chokepoints and 6 mutants (dropped at plan review) | G4e pinned to exactly 1 already turns RED on any new reader. A five-line tier clause inside G4e captures the incident's shape. Chokepoint 2 (following a `uses:` into a composite) would be new census machinery, and chokepoint 3 (scripts) has zero members today. All four reviewers converged on cutting it. |

## Research Insights

**Premise validation (Phase 0.6).** The checks below were all made on 2026-10-01.

- #8209: OPEN. #9262 (the sibling re-tier) is merged.
- Run 36839787788 is `failure` at step "Fetch GitHub App credentials from Doppler". Its loader
  notice reads `source=tier_b exported=10`.
- `soleur-infra-privileged/prd` holds `GITHUB_INFRA_APP_ID`, `GITHUB_INFRA_APP_INSTALLATION_ID` and
  `GITHUB_INFRA_APP_PRIVATE_KEY`. Only the names were listed; no value was read.
- The `GET /orgs/jikig-ai/installations` installation row for soleur-infra: App `5118911`,
  installation `166065653`, `repository_selection=selected`, permissions
  `actions:write, administration:write, contents:write, environments:write, metadata:read,
  pull_requests:write, secrets:write`.
- `board-status-sync.yml` runs on 2026-10-01 are green. It mints `soleur-board` first, so its
  legacy arm is unused.
- Draft PR #9360 already exists for this branch.

Two premises in the task were refined, not refuted:

- the provider already runs as soleur-infra, so only the workflow scaffolding is stale;
- `entrypoint_audit` cannot move to soleur-infra **as is**, because that App has no `issues`
  permission.

**Property List (Phase 0.6b).**

- P1: `apply-github-infra.yml` runs green from `main` with no read of the evicted soleur-ai key.
- P2: its post-apply verify still asserts both repos' rulesets, including `bypass_actors`, and the
  published manifest.
- P3: a run fails **before any write** if the Tier-B identity is absent or the soleur-infra
  installation does not cover a managed repository.
- P4: a key restored into `prd_terraform` cannot be used by this job, and no step suggests
  restoring one.
- P5: `entrypoint_audit` can post its #6767 comment with no soleur-ai key.
- P6: CI catches any Tier-B job that reads `GITHUB_APP_PRIVATE_KEY` again.
- P7: ADR-241, the runbooks, the README and C4 describe the post-change identity truthfully,
  including the known bypass gap.

**Cut List (Phase 0.6b).**

- A new inline JWT recipe (P2): covered by the existing `mint-infra-app-token` composite (#9262).
- A Tier-B identity assertion and an empty legacy `TF_VAR_` pin (P3, P4), added after the advisor
  consult and cut at plan review. The pre-Terraform mint fails on the same condition the loader's
  legacy arm keys on. Both read one project, and `main.tf` ignores the legacy pair whenever the infra
  key is set, so P3 and P4 are already structural.
- A new census row G4g (P6): G4e's exact pin plus a five-line tier clause cover the same property.
- A Terraform-side `validation` or precondition on the legacy key (advisor): it needs an
  `infra/github/*.tf` edit, whose merge auto-applies. It belongs to the P1 follow-up, which removes
  the legacy arm outright.
- Widening soleur-infra with `issues:write` (P5): covered by the job's `github.token`.
- A pre-apply `manifest_write_blocked_bypass_gap` refusal: the 409 is already loud, and the
  follow-up removes the gap.
- A new composite input for the installation id source: the literal `166065653` matches both
  sibling consumers. *Correction from plan review:* in this job the loader masks
  `166065653`, because it is a Tier-B project value, so the notice prints `installation=***`
  either way. AC12 does not grep for the number.

**Value-proposition measurement (0.6c):** not applicable. This is a restore-to-working fix, not a
saving.

**Relevant files** (content anchors, not line numbers):

- `.github/workflows/apply-github-infra.yml`, steps `Fetch GitHub App credentials from Doppler`,
  `Post-apply verify (ruleset required check counts …)`, `First-apply import` (the soleur-ai scope
  comment), and the header `Auth:` bullet.
- `.github/workflows/apply-web-platform-infra.yml`, job `entrypoint_audit`: env `INSTALLATION_ID`,
  and step `Run entrypoint drift audit (read-only) and post findings to #6767`.
- `.github/actions/mint-infra-app-token/action.yml`: the exact-grant and exact-repositories checks,
  revoke on a refused grant, the `app-token` notice. Its fixture suite lives in
  `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh` (`comp.*` rows).
- `.github/actions/infra-credentials/action.yml`: Tier-B arm exports every project name plus its
  `TF_VAR_` twin; the "exported-empty name wins under `--preserve-env`" pattern (`export_gar ""`,
  Guard 8).
- `infra/github/main.tf`: the `dynamic "app_auth"` three-mode selector. Not edited.
- `infra/github/ruleset-marketplace-pr-required.tf`: `bypass_actors` names `Integration 3261325`,
  the deferred gap.
- `scripts/verify-marketplace-ruleset.sh`: `.bypass_actors // []` set equality, so a missing key
  fails.
- `tests/scripts/test-infra-privileged-tier-census.sh`: G4e (`APP_PEM_READ`, `SENTINEL_TEST`, floor
  `3 if CHECK_GIT`), fixture `appkey.yml` (a `pull_request` job with no `environment:`), mutants
  `g4-e1` / `g4-e2`, `g6_tier_b()`, `TIER_B_ENVIRONMENTS`, `CENSUS_ROWS=38`.
- `plugins/soleur/test/workflow-file-size.test.ts`: `WORKFLOW_FILE_GATE_BYTES = 490_000`.
  `apply-web-platform-infra.yml` is 483,707 bytes.
- `scripts/lint-workflow-local-action-checkout.py`: a `uses: ./…` step needs a prior usable
  checkout. `apply-github-infra`'s first step is the checkout.

**Institutional learnings applied:**

- `2026-05-25-app-jwt-inline-mint-for-workflow-gh-api-administration-read.md`: why the verify
  needs an App token at all (`GITHUB_TOKEN` lacks administration). This plan replaces that
  learning's inline recipe with the composite.
- `2026-05-20-github-app-installation-grant-vs-manifest-three-plane-drift.md`: check the
  *installation* grant, not the manifest. The composite's exact-grant check does exactly that.
- `2026-03-19-github-ruleset-stale-bypass-actors.md`: bypass actors are not auto-pruned. This is
  why the deferred swap removes 3261325 rather than adding 5118911 beside it.
- `2026-05-18-composite-action-extraction-inline-on-multi-file-rollout.md`: reuse the composite;
  do not add a fourth inline JWT copy.
- `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` plus #7493's `${mp_checked}` incident: the
  edited verify step stays under `set -euo pipefail`, so every variable it reads must be bound.
  Sweep for `APP_ID`/`APP_PEM_FILE`/`JWT` leftovers.

**Related issues:**

- #8209 (parent).
- #9262 (sibling re-tier; the composite rename).
- #7512 (apply-github-infra has no alert channel).
- #7524 (no structural harness for apply-github-infra.yml).
- #7493 (marketplace ruleset and reconcile).
- #6767 (entrypoint audit target).
- #8385 (split apply-web-platform-infra.yml; byte budget).

**Conventions (CLAUDE.md / AGENTS.md):**

- `hr-github-app-auth-not-pat`.
- `hr-menu-option-ack-not-prod-write-auth`: only the one post-merge dispatch is authorized.
- `hr-dispatch-async-must-arm-watch`.
- `hr-monitor-not-run-in-background-for-polling`.
- `wg-defer-only-after-inline-triage`: the bypass swap was triaged inline and deferred with
  reasons.
- `cq-cite-content-anchor-not-line-number`.

**External:** GitHub REST, "Get a repository ruleset": "To prevent leaking sensitive information,
the bypass_actors property is only returned if the user making the API request has write access to
the ruleset." (<https://docs.github.com/en/rest/repos/rules#get-a-repository-ruleset>, fetched
2026-10-01).

**Functional overlap (1.5b):** no community skill or agent overlaps. In-repo reuse is the
composite. **Community discovery (1.5):** skipped; no uncovered stack.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-241** with a dated section, `2026-10-01 (#<PR>)`. It is not a new ADR: the decision (D5:
Tier-B infra App for the `infra/github` root) is unchanged. This PR completes D5's implementation for
two consumers that were missed. The section records:

- the apply path's GitHub identity is soleur-infra end to end, including the verify;
- the verify mint is the composite, run before Terraform;
- `entrypoint_audit` uses `github.token`;
- G4e moves from a floor of 3 to an exact 1, plus the tier clause;
- the marketplace bypass-actor known gap, with the follow-up issue link;
- after merge, the proof run URL.

The D5 Statuses row is not edited. D5 stays `adopting`, because a no-op apply exercises no write
scope.

### C4 views

All three model files were checked (`model.c4`, `views.c4`, `spec.c4`).

- **External human actors:** none new. The operator and maintainers are already modeled.
- **External systems:**
  - `github` and `soleurMarketplace` are already modeled. `views.c4` already includes
    `soleurMarketplace` and documents the App-write edge.
  - `doppler` is already modeled.
  - No new system.
- **Containers or stores touched:** none new.
- **Relationships whose description becomes false:**
  1. `github -> soleurMarketplace`. These phrases are edited:
     - the opener "as the soleur-ai App";
     - "three remaining inline readers … (apply-github-infra, board-status-sync and
       apply-web-platform-infra; census row G4e)";
     - "NOT the soleur-ai credential named above";
     - "legacy mode (today's soleur-ai key …)";
     - "THE IDENTITY ON BOTH WRITES CHANGES".

     The known-gap clause is added.
  2. The `soleurMarketplace` element description, "bypassed only by … the soleur-ai App", is still
     true. Append a known-gap clause naming the follow-up.
- `github -> doppler` was checked. Its claim about the two inngest jobs ("do NOT load the project
  through infra-credentials") stays true, so it is not edited.
- `spec.c4` carries no identity text and needs no change.
- Regenerate with `bash scripts/regenerate-c4-model.sh`, then run
  `bash plugins/soleur/test/c4-model-freshness.test.sh` and
  `bash plugins/soleur/test/c4-count-parity.test.sh` (edge prose cardinalities).

### Sequencing

No soak gate. The ADR note is written in the same PR, stating the post-merge state. The follow-up
(bypass swap) gets its own ADR-241 dated note when it lands.

## Observability

```yaml
liveness_signal:
  what: "apply-github-infra.yml run conclusion, plus its per-run annotations: the loader's `source=tier_b` notice and the composite's `app-token` notice (app=soleur-infra installation=*** — the loader masks the id in this job)"
  cadence: "per run — push to main on infra/github/**, workflow_dispatch, and the daily scheduled-marketplace-drift reconcile dispatch"
  alert_target: "GitHub run-failure notification to the triggering actor; the unattended reconcile path has no alert channel of its own (#7512, acknowledged), while the dispatching scheduled-marketplace-drift.yml keeps its Sentry cron check-in (org jikigai-eu)"
  configured_in: ".github/workflows/apply-github-infra.yml; .github/actions/mint-infra-app-token/action.yml; .github/workflows/scheduled-marketplace-drift.yml"
error_reporting:
  destination: "GitHub Actions annotations on the run (this workflow carries no Sentry SDK; #7512 tracks adding a channel)"
  fail_loud: "`::error::mint-infra-app-token: …` naming the cause (empty Tier-B token, unreadable GITHUB_INFRA_APP_*, non-PEM key, GitHub's own 422 text for a repository outside the installation, or the exact-grant refusal), all BEFORE any Terraform step"
failure_modes:
  - mode: "DOPPLER_TOKEN_INFRA_PRIVILEGED missing from the infra-privileged environment"
    detection: "the loader's `source=legacy verdict=privileged_source_missing` warning, then the composite's `doppler-token is empty` error; run red before terraform init"
    alert_route: "run-failure notification; for the reconcile path, the drift issue stays open and the next daily drift check re-reports"
  - mode: "soleur-infra installation no longer covers soleur or soleur-marketplace"
    detection: "the token exchange returns 422; the composite relays GitHub's sanitized message; run red before any write"
    alert_route: "run-failure notification"
  - mode: "marketplace manifest write refused because the bypass actor is still soleur-ai (the known gap)"
    detection: "terraform apply error `Repository rule violations found` on github_repository_file.marketplace_manifest; scheduled-marketplace-drift keeps reporting the drift"
    alert_route: "the drift issue filed by scheduled-marketplace-drift.yml; the P1 follow-up issue"
  - mode: "a future edit re-adds a soleur-ai key read to a Tier-B job"
    detection: "census row G4e RED on the PR, via its exact pin and its tier clause (tests/scripts/test-infra-privileged-tier-census.sh)"
    alert_route: "required CI check blocks merge"
logs:
  where: "GitHub Actions run logs and step summary for apply-github-infra.yml"
  retention: "repository Actions log retention (GitHub default 90 days)"
discoverability_test:
  command: "curl -s --max-time 10 https://api.github.com/repos/jikig-ai/soleur/actions/workflows/apply-github-infra.yml/runs?per_page=1"
  expected_output: "success or failure"
```

## Guard Contract

### Guard 1 — G4e: the evicted soleur-ai key has exactly one reader, outside Tier B

**Property.** Exactly one step in the scanned tree reads `GITHUB_APP_PRIVATE_KEY` from Doppler.
That reader refuses the `EVICTED_SEE_ADR_241` sentinel by name with
`verdict=legacy_app_key_evicted`, and no reading site sits in a job bound to a Tier-B environment.

**Assembly.** Every `run:` body in every file the census already scans:

- `git ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml' '.github/actions/**/action.yml'`,
  with totality checked against the filesystem walk;
- composites are scanned directly as files, via `runs.steps`, so a read inside a composite is
  counted without following `uses:`.

Reads are matched in command position by `cmd_sites` with `APP_PEM_READ`. Tier-B membership is
the site's job `env_arms` intersecting `TIER_B_ENVIRONMENTS`; composites count as job-less.

*Out of the assembly, stated:* scripts under `scripts/` and `.github/scripts/`. Zero members read
the key today (grep, 2026-10-01). A future script reader is a known blind spot, shared with the
pre-existing row.

**Mutation matrix:**

| # | Mutation (on the synthetic fixture tree, which pins `== 1`) | Expected |
|---|---|---|
| 1 | Existing `g4-e1`: delete the sentinel `if`, keep the comment | RED |
| 2 | Existing `g4-e2`: keep the guard, drop the verdict word | RED |
| 3 | `g4-e3` (second member): add a second reading step, refusal included, to `appkey.yml` after the compliant first | RED (count 2 != 1) |
| 4 | `g4-e4` (tier clause): give `appkey.yml`'s job `environment: infra-privileged` and a non-PR trigger | RED |
| 5 | Own dispatch: delete `appkey.yml`'s read, so the row examines 0 sites | RED (count 0 != 1; the exact pin is the anti-vacuity floor) |

**Harness rows:**

| # | Edit | Expected |
|---|---|---|
| H1 | Delete the `g4-e3` mutate/`mutant_red` block from the suite | RED (`FAIL MUTANT FLOOR`, which is exact) |
| H2 | Must-PASS: the pristine fixture's `appkey.yml` (`pull_request`, no `environment:`, one refusing read) | G4e GREEN |
| H3 | Must-PASS: a step using `./.github/actions/mint-infra-app-token`, which reads `GITHUB_INFRA_APP_PRIVATE_KEY` | not counted (the `\bGITHUB_APP_PRIVATE_KEY\b` anchor; checked by the live-tree count of 1, since two workflows use the composite) |

Row 5 is written as a mutant only if `mutate()` can express it (a one-line delete). Otherwise it is a
design row, measured once at work time.

**Anchor.** An exact pin is a stored count, and one diff can move it together with the population,
so the pin proves consistency, not integrity. The tier clause is not a count: it binds a property of
each site, and `TIER_B_ENVIRONMENTS` is cross-checked against Terraform by G1d. A diff that adds a
Tier-B reader must therefore edit the clause or the environment set itself. Reviewers see either one.

*Sunset:* the row retires when `board-status-sync`'s legacy arm and the Doppler name are deleted
(a scope question raised in `decision-challenges.md`).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing at runtime, because this is CI-only.
  The plugin's marketplace manifest and the repo's required-check rulesets stay frozen at their
  last-applied state. A tampered `soleur-marketplace` manifest would not be auto-reconciled,
  though it would still be detected daily. Plugin installers could then resolve whatever the
  marketplace repo serves until a human intervenes. This is the same exposure as today, where
  every run fails.
- **If this leaks, the user's workflow is exposed via:** the scoped soleur-infra installation
  token, which carries `administration:write` on `soleur` and `soleur-marketplace`. A leak could
  rewrite rulesets: drop required checks, or add a bypass on the marketplace that is the plugin's
  only distribution channel. Mitigations:
  - it is masked;
  - it is minted only in a `main`-only environment job;
  - it is revoked at job end.

  It adds little exposure: in Tier-B mode the loader already puts the full soleur-infra **private
  key** (`TF_VAR_github_infra_app_private_key`) into `$GITHUB_ENV` for every later step. An in-job
  compromise therefore already holds a superset, and revocation does not mitigate it. The
  controls that matter are the `main`-only environment and the ref and tree assertions that run
  before any credential step.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: CI-only identity swap that removes a dependency on an already-evicted
  key and narrows token scope; no user data, runtime path, or customer-reaching credential changes,
  and the failure mode (a red apply run) is the status quo it fixes.`

## Open Code-Review Overlap

None with the `code-review` label touches the planned files; the check ran over 87 open issues.
Related open issues found by search, with dispositions:

- **#7512** (apply-github-infra failures reach no alert channel): **Acknowledge.** It is a
  different concern, an on-failure filer for the unattended reconcile path. This PR changes
  failure *causes*, not the alert route.
- **#7524** (no structural harness for apply-github-infra.yml): **Acknowledge.** The
  mint-before-Terraform placement is exactly the kind of property that harness would pin. That
  stays its scope.

## Dependencies & Risks

- **R1: the installation does not actually cover `soleur-marketplace`.** The evidence is indirect
  (the 2026-09-29 INFRA-mode refresh). Mitigation: the pre-Terraform mint fails closed with
  GitHub's own message, so the proof run is red with a named cause and nothing is written. The
  remedy is then a GitHub App installation repository grant. That needs explicit operator
  authorization, and a rerun proves it.
- **R2: `{"administration":"write"}` is refused by the exact-grant check** (for example, GitHub
  returns an extra permission). The composite revokes the token and errors. The fix is a
  workflow-only scope adjustment.
- **R3: the merge's self-triggered `apply-web-platform-infra` push apply.** Mitigation: the
  `[skip-web-platform-apply]` token goes in a branch commit message, not the PR body. Phase 5.0
  verifies that the merge commit carries it and that preflight skipped `apply`. If the token was
  lost, the push apply runs main's already-applied declarations, which is the routine path. It is
  still reported as an unauthorized production run.
- **R4: the byte gate.** The edit removes bytes from `apply-web-platform-infra.yml`. The
  `workflow-file-size` test re-verifies it.
- **R5: a manifest change merges before the P1 follow-up.** The apply is refused at the file
  write (409 `Repository rule violations`). If the same apply also carried ruleset changes, those
  apply first, so the state is partially applied. This is not destructive: every applied change
  is a reviewed declaration, and a rerun after the swap completes the rest. The follow-up issue
  blocks manifest and combined edits until it lands.
- **R6: the census tier clause misreads a composite as a Tier-B job.** Composites have no
  `environment:`, so they are classified as job-less and not Tier-B. The fixture's `appkey.yml` is a
  `pull_request` job with no environment and stays green; mutant `g4-e4` proves the clause can go
  RED.
- **Dependency:** the post-merge proof needs the infra-privileged environment secret (present
  since O3, 2026-09-29) and an unchanged soleur-infra installation.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** No command-position use of the soleur-ai identity or the deleted mint remains in
  `apply-github-infra.yml`. The check
  `grep -nE '^[^#]*(doppler secrets get GITHUB_APP_(ID|PRIVATE_KEY)|122213433|soleur-ai-app-pem|APP_PEM_FILE|\$\{?(APP_ID|JWT|INSTALLATION_ID)\b)' .github/workflows/apply-github-infra.yml`
  prints nothing. Today it prints matches, so the check is falsifiable.
- [ ] **AC2** `apply-github-infra.yml::apply` has one step that `uses: ./.github/actions/mint-infra-app-token`
  with `installation-id: "166065653"`, `permissions: '{"administration":"write"}'` and
  `repositories: soleur,soleur-marketplace`. It sits after `Load infra credentials (tiered)` and
  before `Extract backend credentials` and `Terraform init`.
- [ ] **AC3** At least one branch commit **body** carries a line that is exactly
  `[skip-web-platform-apply]`. The check is
  `git log origin/main..HEAD --format=%b | grep -cx '\[skip-web-platform-apply\]'` returning
  `>= 1`. It uses `%b`, not `%B`: a subject match would pass here and fail after the squash. The
  auto-merge is armed with `--body-file` carrying the same line.
- [ ] **AC4** The post-apply verify reads its token only from `steps.mint.outputs.token` through
  `env:`, never from `$GITHUB_ENV`, and fails closed on an empty value. Its Steps 3–5
  **assertions** are unchanged; comments that became false are rewritten. A final
  `if: always() && steps.mint.outcome == 'success'` step revokes the token, with the token in `env:`.
- [ ] **AC5** `apply-web-platform-infra.yml::entrypoint_audit` meets all of these:
  - it contains no App-key read, no `122213433` and no `$INSTALL_TOKEN`;
  - it posts with `GH_TOKEN="$AUDIT_POST_TOKEN" gh issue comment "$AUDIT_ISSUE" --body-file /tmp/audit-body.md`,
    where step `env:` sets `AUDIT_POST_TOKEN: ${{ github.token }}`, and no step-level `GH_TOKEN`;
  - `wc -c` stays `< 490000`, and `plugins/soleur/test/workflow-file-size.test.ts` passes;
  - `bash tests/scripts/test-preapply-entrypoint-gate.sh` passes.
- [ ] **AC6** `bash tests/scripts/test-infra-privileged-tier-census.sh` is green on the PR head:
  - G4e reports `[1 reading steps]` under the exact pin, with no Tier-B reader;
  - mutants `g4-e1` to `g4-e4` (and `g4-e5` if mechanized) are each RED;
  - `CENSUS_ROWS=38`, `MUTANT_FLOOR` equals the measured exact count, and `FLOOR` has been raised to
    the measured assertion count.
- [ ] **AC7** RED-first evidence: before Phase 2, G4e fails on the live tree with 3 sites and names
  both workflows in its tier clause. This is recorded in the PR body.
- [ ] **AC8** Checked against the merge-base, the PR diff touches none of these, so the merge fires
  no `apply-github-infra` push:
  - `infra/github/*.tf`;
  - `infra/github/.terraform.lock.hcl`;
  - `infra/github/soleur-marketplace-manifest.json`;
  - `tests/scripts/lib/destroy-guard-filter.jq`.

  The check is
  `git diff --name-only origin/main...HEAD | grep -E '^infra/github/[^/]*\.(tf|hcl)$|^infra/github/soleur-marketplace-manifest\.json$|destroy-guard-filter\.jq$'`,
  and it must print nothing.
- [ ] **AC9** These records are all in place:
  - the ADR-241 dated section;
  - the two runbook one-line dated notes;
  - the README updates;
  - the mint composite description fix;
  - the `model.c4` edits plus a regenerated `model.likec4.json`.

  `c4-model-freshness.test.sh` and `c4-count-parity.test.sh` are green.
- [ ] **AC10** The P1 follow-up issue is filed and linked from ADR-241's note, the README and the PR
  body. Its title contains "Repository rule violations". Its body carries the `depends_on` / ordering
  requirement, the expected plan, and the production-apply authorization request. The PR body:
  - uses `Ref #8209`, not `Closes #8209`;
  - answers "does merging this alone mutate production?" on its first line with **No** (Phase 4.1).
- [ ] **AC11** Required checks pass by name on the exact head SHA. Merge is auto-merge only
  (UNTRUSTED-CI).

### Post-merge (the one authorized production dispatch)

- [ ] **AC12** Both Phase 5.0 prechecks pass: the kill switch held on the merge's push run, and
  there is no push-filter diff since `38d64df696`. Then one `main`-dispatched
  `apply-github-infra.yml` run concludes `success`, and its log contains all of:
  - `source=tier_b`;
  - `app=soleur-infra installation=`;
  - `permissions={"administration":"write","metadata":"read"}`;
  - `No changes.` **or** `Apply complete! Resources: 0 added, 0 changed, 0 destroyed.`;
  - `Ruleset 14145388 (CI): required_status_checks count = 24` (a different live count is accepted
    only if a required-check change merged in between, which 5.0 would have flagged);
  - `Ruleset 13304872 (CLA): required_status_checks count = 2`;
  - `matches its declaration`;
  - `Published manifest is byte-identical`.

  The log contains no `legacy_app_key_evicted`. The run URL is recorded on #8209 and in the ADR-241
  note.

  **Automation:** `gh workflow run`, the bounded run-id loop, then a Monitor until-loop on
  `gh run view`. There is no operator step.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO endorsed this approach and settled each fork:

- **`entrypoint_audit`:** use `github.token` (B1). It is low risk: no consumer filters #6767
  comments by author.
- **Marketplace bypass swap:** defer as P1 and **swap, not add**. Deferring is fail-loud and
  non-destructive. It must be the next `infra/github` PR, and it bundles the `commit_author` fix,
  the legacy-arm removal and the comment refresh.
- **Verify token:** accept `{"administration":"write"}`. A read scope would make `bypass_actors`
  vanish, and the assertion would fail open. Revoke after use, and use one mint for both
  repositories.
- **ADR-241 and C4:** a dated ADR-241 section and the C4 edge and element edits, with the JSON
  regenerated.
- **Reshapes:** these were applied:
  - sweep every `INSTALL_TOKEN` site;
  - update the header comment;
  - confirm that the diff touches no `infra/github/**` apply-trigger path.

  Two reshapes were superseded at plan review. Neutralizing the legacy `TF_VAR_github_app_*` was
  cut as structural redundancy. The G4g mechanics became a tier clause plus a mutant inside G4e.
- **Considered and cut:** an optional pre-apply `manifest_write_blocked_bypass_gap` verdict
  (see the Cut List).

**Scoped advisor consult (Step 4.5):** the strong-model consult made two recommendations. Both
were weighed against the plan and the codebase.

1. *Fail closed on identity where the provider reads it.* This was applied first as an
   assert-and-pin step, then **cut at plan review**, where DHH and code simplicity converged on
   cutting it:
   - The mint fails before Terraform on the exact condition the loader's legacy arm keys on, an
     empty `DOPPLER_TOKEN_INFRA_PRIVILEGED`.
   - The mint and the loader read the same Tier-B project.
   - `main.tf` ignores the legacy pair whenever the infra key is set.
   - The consult's "falls back to ambient GITHUB_TOKEN" case does not arise: `for_each` resolves
     `app_auth` even with empty keys, and the provider then errors rather than going ambient.
   - The empty-value precedence it doubted is in any case measured (`infra-credentials.test.sh`
     row 8.8).
2. *Gate the plan on a `github_repository_file` change while the bypass gap stands.* **Cut**, as
   for the CTO's optional verdict:
   - a content-drift reconcile changes only that resource, so it gets a clean 409 with nothing
     partially applied;
   - a combined ruleset-plus-manifest PR is blocked by the follow-up issue's policy until the
     swap lands.

   The partial-apply semantics are recorded in R5.

Smaller points:

- the token is already a step output, never `$GITHUB_ENV`, and AC4 now says so;
- G4e uses an exact pin (applied).

### Plan review (DHH, Kieran, code simplicity, CTO devex), consolidated

**Mechanical (auto-applied):**

- **Kieran P0:** `apply-web-platform-infra.yml` self-triggers on push. Fix: the kill-switch commit
  token (AC3), the Phase 5.0 check and R3, and the merge-side-effect paragraph.
- **Kieran and CTO P0/P1:** 5.0's path scope included the README this PR edits, so the precheck
  could never pass. It is now limited to the push filter.
- **Kieran P1:** the installation id is masked in this job. AC12 now greps
  `app=soleur-infra installation=` plus the permissions JSON.
- **Kieran P1:** edit B would leave an unbound `$INSTALL_TOKEN`. The rewritten `gh issue comment`
  line is now explicit.
- **All four:** cut G4g and fold a tier clause plus two mutants into G4e (`CENSUS_ROWS` stays 38).
  Raise the exact `MUTANT_FLOOR` and the assertion `FLOOR`.
- **DHH and code simplicity:** cut the assert-and-pin step (see above).
- **DHH:** align AC12 with 5.2 (`No changes.` or `0/0/0`, the CI count 24, the permissions JSON).
- **DHH and code simplicity:** trim the records. Drop the D5 row note, the O10 history note, the
  `github -> doppler` edit and the #7524 comment task. Runbooks get one dated line each.
- **CTO:** the follow-up issue gets a searchable title, a `depends_on`/ordering requirement, the
  expected plan, and an authorization request. The run-id resolution is filtered on actor and time.
  The runbook gets a 422 remedy line.
- **Kieran P2:** AC1 also catches `APP_ID`/`JWT`/`INSTALLATION_ID` leftovers; AC4 allows comment
  edits; the mint composite's stale description is fixed.

**Kept against one dissent:** the always-run revoke step. CTO and DHH kept it; code simplicity would
cut it, because the job already holds the PEM. It costs one step, and the token carries
`administration:write`.

**User-Challenge (headless, persisted to `knowledge-base/project/specs/feat-one-shot-retier-apply-github-infra-app/decision-challenges.md`):**
DHH P0 proposes deleting `board-status-sync.yml`'s now-dead legacy arm, which would make G4e
"zero readers". It adds a third workflow the operator did not scope, so this plan does not
decide it.

No Product, Marketing, Legal, Finance, Sales, Operations or Support implications: this is a CI
credential-source fix with no user-facing surface, no data processing change and no vendor or
cost change.

## Test Scenarios

- **Given** the live tree before Phase 2, **when** the census runs, **then** G4e is RED: 3 sites
  against the exact pin, with the tier clause naming `apply-github-infra.yml` and
  `apply-web-platform-infra.yml`. This is the reproduction.
- **Given** the PR head, **when** the census runs, **then** all 38 rows are GREEN, G4e reports 1 site,
  and mutants g4-e1 to g4-e4 are each RED.
- **Given** the pristine fixture's `appkey.yml` (a Tier-A reader), **then** G4e stays GREEN (H2).
- **Given** two workflows that use `mint-infra-app-token`, **then** they add no G4e sites (H3: the
  live count stays exactly 1).
- **Given** the composite fixture suites (the `comp.*` rows in `test-mint-inngest-bootstrap-tag.sh`
  and `test-bump-inngest-bootstrap-pin.sh`), **then** they are unchanged and green. Only the
  composite's `description:` text is edited.
- **Given** `apply-web-platform-infra.yml` after edit B, **then** all of these pass:
  - `workflow-file-size.test.ts`;
  - the `test-preapply-entrypoint-gate.sh` D2 shape test;
  - the workflow lints, with no new findings.
- **Given** the merge, **then** the `apply-web-platform-infra` push run logs `Kill switch detected`
  and skips `apply`, and no `apply-github-infra` push run starts.
- **Given** the post-merge `main` dispatch, **then** AC12 holds.
- **Regression:** the verify's marketplace probe still fails closed on an absent `bypass_actors`.
  The existing `verify-marketplace-ruleset.test.sh` rows stay green and unchanged.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting
  deepen-plan or `soleur:work`.
- **Do not touch any `infra/github/*.tf` file**, even for a comment fix. The push filter would
  turn the merge into an unauthorized production apply. Stale `.tf` comments go to the P1
  follow-up.
- **`APP_PEM_READ` is anchored with `\b`.** `GITHUB_INFRA_APP_PRIVATE_KEY` does not contain
  `GITHUB_APP_PRIVATE_KEY`, because of the `INFRA_` infix. H3 (a live count of exactly 1 while two
  workflows use the composite) is the proof.
- **The loader masks every Tier-B value, including `166065653`.** Any log line in this job that
  contains the installation id prints `***`. Never write an AC or a log grep that expects the
  number from this job.
- **`[skip-web-platform-apply]` must live in a COMMIT message.** A token placed only in the PR
  body is dropped from the squash message (PR #7617, run 32293304282).
- **The G4e tier clause needs the site's job.** `step_bodies(doc)` is flat, so walk `doc["jobs"]`
  for the clause and keep `step_bodies` for the count. A composite has no job and is not Tier-B.
- **`steps.mint.outputs.token` in an `if:`** is evaluated by the runner. The value stays masked in
  logs. Do not echo it in the revoke step.
- **The composite's `revoke()` runs only on a refused grant.** The success-path revoke is this
  PR's own final step; do not assume the composite does it.
- **`set -u` in the edited verify step:** after deleting Steps 1–2, no reference to `JWT`,
  `APP_ID` or `APP_PEM_FILE` may remain. That is the #7493 `${mp_checked}` class, and
  `lint-workflow-step-env-refs.py` is blind to lowercase names.
