---
title: "infra(github): swap the soleur-marketplace ruleset bypass actor from soleur-ai to soleur-infra"
date: 2026-10-04
slug: marketplace-ruleset-bypass-actor-swap-to-soleur-infra
branch: feat-one-shot-9361-marketplace-ruleset-bypass-swap
issue: 9361
type: fix
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
closes: none   # PR body carries `Refs #8209` and `Refs #9361` only; #9361 is closed after the post-merge apply is verified
---

# infra(github): swap the soleur-marketplace ruleset bypass actor from soleur-ai to soleur-infra

Spec lacks a valid `lane:` (no `spec.md` exists for this one-shot branch) — defaulted to `cross-domain` (TR2 fail-closed).

CPO sign-off: obtained at plan review (2026-10-04) as **SIGN-OFF WITH CONDITIONS**; the four conditions are folded into Phase 5, Post-Merge Verification and Deferrals below.

## Overview

`apply-github-infra.yml` runs Terraform as the soleur-infra App (5118911, installation 166065653).
The `Marketplace PR Required` ruleset on `jikig-ai/soleur-marketplace` still names the soleur-ai App
(3261325) as its only App bypass actor, so any `github_repository_file.marketplace_manifest` write
made by that apply is refused with `409 Repository rule violations`. The run goes red, nothing is
published, nothing is damaged (it fails loudly), but ADR-241 D5's write limb has no evidence until
this lands.

This plan swaps the bypass actor in place (keeping its position in the block list), changes the
file resource's commit identity, orders the file write after the ruleset write with a `depends_on`,
removes the dead legacy-mode arm of the provider block in `infra/github/main.tf`, and refreshes the
stale `122213433` / soleur-ai prose in `infra/github/*.tf`. The merge IS the production apply
(push filter `infra/github/*.tf`); the owner authorized it explicitly on 2026-10-04 ("ack for all",
covering #9361).

## Premise Validation (Phase 0.6, carried forward)

- #9361 OPEN, titled as quoted; #9360 MERGED (its post-apply verify no longer reads the soleur-ai
  key); #8209 OPEN; #8211 OPEN (never closed by this PR); PR #9466 is this branch's draft (no files yet);
  PR #9455 OPEN (a sibling, see below).
- Live state (read-only, 2026-10-04): ruleset `20802604` bypass actors are
  `[OrganizationAdmin null, RepositoryRole 5, Integration 3261325]`;
  `gh api apps/soleur-infra` returns `id 5118911`, `gh api apps/soleur-ai` returns `id 3261325`;
  the soleur-infra installation (166065653, `repository_selection: selected`) holds
  `administration:write` and `contents:write`; the marketplace repo's HEAD `0fb0e43276` is a
  Terraform-authored `soleur-ai[bot]` commit whose tree (`3df1424cb3`) equals its parent's, i.e. the
  "re-commit of identical content" behavior the issue predicts has already happened once.
- The issue's `grep depends_on infra/github/*.tf` claim holds (no `depends_on` anywhere in that root).
- ADR corpus: ADR-241 D5 already names #9361 as a Statuses-row condition and records the known gap
  (Amendment log 2026-10-01); ADR-182 / ADR-032 describe the ruleset. No ADR rejects "swap, not add".
- **Stale claim found in the repo (not in the issue):** `infra/github/README.md` states the two
  resources "are coupled by the bypass actor, not by ordering ... a `depends_on` would buy nothing".
  True only for a fresh CREATE (bypass ships inside the ruleset's own POST). For an in-place UPDATE of
  an existing ruleset, which is this change, ordering is load-bearing. The README paragraph must be
  rewritten, not just refreshed. A second stale claim: the `.tf` comment says `122213433` "appears
  twice in apply-github-infra.yml"; it no longer appears there at all.
- **Sibling PR #9455** (`feat-one-shot-9454-merge-queue-advisory-codeql`) edits
  `infra/github/ruleset-ci-required.tf`, `infra/github/variables.tf`, `infra/github/README.md`,
  `tests/scripts/test-audit-ruleset-bypass.sh`, `ADR-032`, `article-30-register.md`,
  `scheduled-terraform-drift.yml` and others. This plan touches none of the first two; the README and
  the audit test overlap by file only, and this plan keeps those edits to small named hunks so a textual
  merge resolves cleanly. Both PRs trigger the same apply workflow (see Post-Merge Verification).

## Property List and Cut List (Phase 0.6b, carried forward)

Properties the issue asks for:

- P1. The marketplace ruleset's App bypass actor is the identity the apply authenticates as.
- P2. The canonical bypass JSON, the `.tf` declaration and the test fixtures state the same set (the
  post-apply verify stays green).
- P3. In a single apply, the file write cannot run before the bypass swap.
- P4. The provider block has no arm that no CI path can select.
- P5. Prose in `infra/github/*.tf` names the actor that is true after the change.
- P6. The merge apply provides D5's write-limb evidence, and that evidence is checkable afterwards.

Mechanisms already on `origin/main` that buy a property (grepped, authority named):

- P2 is already enforced by `T-mp-1b` in `tests/scripts/test-audit-ruleset-bypass.sh` (parses the
  `.tf` `bypass_actors` blocks and compares to the canonical, with an `== 3` floor) and by the post-apply
  verify. No new sync gate is needed; the plan re-uses both.
- P6's read side is already built: the workflow's own Step 5 (ruleset probe) and Step 6 (published-manifest
  byte compare) run on every apply, so the plan does not re-run them by hand.

Cut List (own cuts, then plan-review cuts):

- New suite or CI job for the swap: cut — `T-mp-1b`, the verifier suite and the post-apply verify cover it.
- A `commit_author`-equals-bypass-actor coupling lint: cut — bypass is decided by the token's identity, not
  the author field.
- Removing the `known-gap-9361` annotation in `.github/workflows/apply-github-infra.yml`: cut from this PR and
  tracked (Deferrals; see decision challenge DC-1). The PR then touches no workflow file.
- Deleting `var.github_app_id` / `var.github_app_private_key` from `variables.tf`: cut — sibling #9455 owns it.
- Plan-review cuts (DHH, CTO, simplicity, Kieran converged): the ordering guard shrinks from six rows to four and
  moves next to `T-mp-1b`; the "G1.2e old actor back" row is cut (G1.2a's set equality and G1.2f cover it); the
  post-merge re-runs of the verifier and the manifest byte-compare are cut (the workflow already asserts both); two
  Phase 5 suites the diff cannot affect are left to CI.

## Research Insights

- `infra/github/ruleset-marketplace-pr-required.tf` is the only file holding the bypass declaration and
  the file resource; the third `bypass_actors` block is the swap target. The block order is
  `0 OrganizationAdmin`, `5 RepositoryRole`, then the Integration; the swap keeps that position so the
  list-typed provider attribute shows one in-place element change, not a reorder.
- `T-mp-1b`'s awk extractor reads `actor_id`, `actor_type`, `bypass_mode` from each `bypass_actors {`
  block, strips `#` comments before slicing the value, and demands `exactly 3` entries; a comment
  that starts a line with `bypass_actors {` would be mis-parsed, so new prose must not.
- `tests/scripts/lib/destroy-guard-filter.jq` only counts `required_check` shrinkage on
  `github_repository_ruleset`; a bypass-actor swap on the marketplace ruleset (no
  `required_status_checks`) counts 0, so the merge needs **no** `[ack-destroy]` line. A ruleset or file REPLACE
  (`-/+`) would count as a resource delete, and a replace of `github_repository_file` would unpublish the plugin:
  that is the abort condition in Phase 5.
- `infra-validation.yml` runs `terraform plan -refresh=false` in TOKEN mode for `infra/github` on every
  PR that touches it, and posts the plan as a PR comment. That is the pre-merge evidence for the two in-place
  changes. It exercises only the `token` arm, so the INFRA-mode arm of the provider block is evidenced separately
  (Phase 3 step 5).
- Provider-block selection today: `token` = plan credential when set and no infra key; `app_auth`
  `for_each` is its exact complement. The legacy arm survives only in the `id`, `installation_id`
  (`"122213433"`) and `pem_file` ternaries. After removal, `id`/`installation_id`/`pem_file` read the infra variables
  directly; in INFRA mode (infra key set) the ternaries already resolved to those same values, so that arm is
  semantically unchanged.
- **Measured at plan time (scratch root, provider 6.12.1, `terraform plan` with no variables set and an ambient
  `GITHUB_TOKEN` exported):** the new shape fails with `app_auth.id must be set and contain a non-empty value` — it
  does NOT fall back to the ambient token. That is the property the existing comment protects.
- No CI path of this root selects legacy mode: `apply-github-infra.yml` refuses a loader legacy arm
  (`::error title=infra-app-installation::`), the PR plan job exports `TF_VAR_github_plan_actions_credential`,
  and `scheduled-terraform-drift.yml` uses the loader's infra mode (all read from the workflow files).
- No other writer uses the soleur-ai App against `soleur-marketplace` (grepped `.github/workflows` and `apps/`; only
  Terraform and the drift reader mention the repo), so swapping it out strands nothing.
- Commit identity: the existing `soleur-ai[bot]` commit uses the plain `<slug>[bot]@users.noreply.github.com` email and
  GitHub linked it to the bot login, so the same plain form for soleur-infra links (bot user id 335404629). Provider
  `commit_author` / `commit_email` set both author and committer, so they are informational, not proof of which token
  wrote; the proof is the apply's `app-token` notice (`app=soleur-infra`) plus a successful write with no 409.
- `gh api .../commits?path=<file>` omits empty-diff commits, so the post-merge check lists HEAD commits instead of
  filtering by path.
- Workflow concurrency group `terraform-apply-github-infra` has `cancel-in-progress: false`, but GitHub keeps one
  pending run per group and cancels an older pending one when a newer arrives. A queued run for this merge can be
  superseded by a later push's run, which applies this change as part of its own tree.
- Learnings applied: the 2026-08-13 guard-satisfiability learning (every RED row mutates the artifact, and a must-PASS row
  differs from the canonical); `2026-03-19-github-ruleset-stale-bypass-actors.md` (bypass_actors has array-replacement
  semantics, so the apply replaces the list wholesale and a stale entry cannot linger).
- Not touched, by design: `apps/web-platform/infra/main.tf` and `apps/web-platform/infra/git-data-root-key/main.tf` carry
  the same "legacy mode" literal; they are different roots, outside the issue.

## Files to Edit

- `infra/github/ruleset-marketplace-pr-required.tf` — swap the third bypass actor to `5118911`
  (`Integration`, `always`, same position); `commit_author = "soleur-infra[bot]"`,
  `commit_email = "soleur-infra[bot]@users.noreply.github.com"`; add
  `depends_on = [github_repository_ruleset.marketplace_pr_required]` to
  `github_repository_file.marketplace_manifest`; refresh the header table, the "HONEST STRENGTH CLAIM"
  paragraph (its "published through the `soleur-ai` bypass" sentence), the bypass-actor comment, and the
  `122213433` remark (dropping the false "appears twice" sentence).
- `infra/github/main.tf` — drop the legacy arm of the provider block and rewrite the two comments that
  describe soleur-ai auth (the header comment and the `# (#8209, ADR-241)` block, including its "same block" claim).
- `scripts/marketplace-ruleset-canonical-bypass-actors.json` — `3261325` to `5118911`.
- `scripts/verify-marketplace-ruleset.test.sh` — baseline fixture actor id; G1.2d re-pointed; one new row (G1.2f);
  `MIN_ASSERTIONS` raised from 27 to 28 (the literal stays directly above its `if`, which `guard-vacuity-floor.test.sh`
  mutates).
- `tests/scripts/test-audit-ruleset-bypass.sh` — new `T-mp-1d` (ordering guard) beside `T-mp-1b`/`T-mp-1c`, plus the
  one stale comment in `t_mp_bypass_canonical_matches_tf` ("soleur-ai Integration" becomes soleur-infra). Small hunks.
- `infra/github/README.md` — the "Known gap" paragraph (one-line "Resolved" note), the "coupled by the bypass actor, not
  by ordering" paragraph, the Phase 0 auth paragraph, and the two `TF_VAR_github_app_id` mentions. Localized hunks only.
- `knowledge-base/engineering/architecture/diagrams/model.c4` and the regenerated
  `knowledge-base/engineering/architecture/diagrams/model.likec4.json` — see the ADR/C4 section.
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`
  — a short Amendment-log entry (D5 row stays `adopting`).
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` — the dated #9360 note
  that says O4's bypass-list limb "stays open for the marketplace ruleset until #9361 lands".

## Files to Create

`knowledge-base/project/specs/feat-one-shot-9361-marketplace-ruleset-bypass-swap/{tasks.md,decision-challenges.md}` (plan artifacts only).

## Open Code-Review Overlap

None. (Queried open `code-review` issues against every path above; no hits.)

## Implementation Phases

Run RED first (`cq-write-failing-tests-before`): Phase 1 deliberately leaves `T-mp-1b` red until Phase 2
lands, which is the proof that the canonical-versus-`.tf` gate is live; `T-mp-1d` is written before the `depends_on`.

### Phase 1 — Canonical, fixtures, and guard rows (RED)

1. `scripts/marketplace-ruleset-canonical-bypass-actors.json`: third entry `actor_id` `3261325` to `5118911`.
2. `scripts/verify-marketplace-ruleset.test.sh`:
   - `baseline.json` third bypass actor `5118911`.
   - G1.2d keeps its meaning ("an Integration actor_id that is not the App id is rejected") with the value
     `166065653`, the soleur-infra INSTALLATION id, the typo class the `.tf` comment warns about.
   - New G1.2f: ADD `3261325` as a 4th actor beside the correct one must be rejected. This pins the CTO's
     "swap, not add" decision (an old actor cannot silently return as an extra). Every new row increments `ASSERTED`
     at its call site; `MIN_ASSERTIONS` becomes 28.
3. `tests/scripts/test-audit-ruleset-bypass.sh`: add `T-mp-1d` (see Guard Contract) and register it where `T-mp-1b`/`T-mp-1c`
   are registered. It is RED until Phase 2.
4. Run `bash tests/scripts/test-audit-ruleset-bypass.sh`: `T-mp-1b` AND `T-mp-1d` MUST fail here (canonical says
   5118911 while the `.tf` still says 3261325; no `depends_on` yet). Record that failure, then proceed.

### Phase 2 — The ruleset `.tf`

1. Third `bypass_actors` block: `actor_id = 5118911`, `actor_type = "Integration"`, `bypass_mode = "always"`.
   Comment: the soleur-infra App (5118911; installation 166065653); the APP id, not the installation id;
   it is the identity the apply authenticates as; the write is the reviewed path because content originates
   in this monorepo behind CI, CODEOWNERS and `marketplace-manifest-guard`.
2. Honest-claim text. Update the header table (keep the historical three-App snapshot, marked as the pre-ruleset
   state) and the "HONEST STRENGTH CLAIM" paragraph: the publish path now goes through the soleur-infra bypass. This
   `.tf` carries the ONE full statement of the residual (the ADR and README point here): soleur-ai's runtime key no longer
   has a push path to the default branch through the ruleset, but soleur-ai still holds `administration:write` there and
   could rewrite the ruleset; the NEW bypass identity, soleur-infra, also holds `administration:write` there, so it can both push
   and rewrite its own ruleset; its key is the one the loader exports into every `infra-privileged` job, so the exposure is
   "any Tier-B job" rather than "the web host" — smaller, not zero. Terraform reverts a rewrite on the next apply and
   Guard 1 reddens post-apply; neither prevents it. Narrowing is tracked (Deferrals 3 and 4).
3. `github_repository_file.marketplace_manifest`: add `depends_on = [github_repository_ruleset.marketplace_pr_required]`
   with a comment saying why ordering matters for an in-place bypass change (one saved plan updates both; without the edge a
   refused write can run before the swap); set the author/email. The author/email diff is deliberate: it is what makes the file
   an in-place update, hence the evidence commit, and the plan comment must list it.
4. Do not reorder the three blocks (no list-diff noise). Do not start a comment line with `bypass_actors {`.
5. `T-mp-1b` and `T-mp-1d` go green. Re-run the verifier suite.

### Phase 3 — `main.tf` legacy arm and the README

1. Provider block becomes (shape, comments aside):
   `token` unchanged; `app_auth` `for_each` unchanged; inside `content`: `id = var.github_infra_app_id`,
   `installation_id = var.github_infra_app_installation_id`, `pem_file = var.github_infra_app_private_key`.
   `var.github_app_id` and `var.github_app_private_key` are no longer referenced; they stay declared in
   `variables.tf` (sibling-owned) so an injected `TF_VAR_github_app_*` from `prd_terraform` is still accepted
   and inert.
2. Comments: replace the "soleur-ai App (id 3261325, org-wide installation 122213433)" provider-auth prose
   with soleur-infra (installation 166065653, loader-delivered key, ADR-241 D5) and say that two modes remain
   (INFRA, TOKEN) with "neither set" failing provider configuration loudly rather than falling back. Reword the "same
   block" pointer to "same modes minus legacy" (the two other roots keep theirs). Remove the `122213433` URL line.
3. README: rewrite (a) the Phase 0 auth paragraph (no legacy arm; the Doppler "verify/mirror" blocks stay marked
   superseded), (b) the "Known gap" paragraph into a one-line "Resolved 2026-10-04 (#9361)" note that points at the `.tf`
   for the residual, (c) the "coupled by the bypass actor, not by ordering" paragraph per the stale-claim finding, and
   (d) the two `TF_VAR_github_app_*` mentions. Keep one sentence saying the workflow's `known-gap-9361` annotation is stale
   and its removal is tracked.
4. `terraform -chdir=infra/github init -backend=false -input=false -lockfile=readonly && terraform -chdir=infra/github validate`
   and `terraform fmt -check` (provider download works from this machine; the plan-time scratch probe already initialized 6.12.1).
5. INFRA-mode evidence the PR plan job cannot give: in a scratch root with the same provider block, `plan` with dummy infra
   values must get past `app_auth` argument checks and fail only at PEM parsing (proving the arm reads the infra variables), and
   with nothing set must fail with `app_auth.id must be set and contain a non-empty value` (already measured once at plan time).
   Paste both outputs into the PR body.

### Phase 4 — ADR / C4 / runbook

See the ADR/C4 section. Regenerate the compiled model with `bash scripts/regenerate-c4-model.sh`.

### Phase 5 — Targeted verification and PR body

1. Targeted suites only (CI owns the battery): `bash scripts/verify-marketplace-ruleset.test.sh`,
   `bash tests/scripts/test-audit-ruleset-bypass.sh`, `bash plugins/soleur/test/c4-model-freshness.test.sh`,
   `bash plugins/soleur/test/c4-count-parity.test.sh`, `bash scripts/guard-vacuity-floor.test.sh`.
2. Pre-merge gate on the PR, read by the shipping agent from the `infra-validation` plan comment (never satisfiable by
   auto-merge) and **re-read after the last rebase onto `main`** (the plan is `-refresh=false`, so it can lag a sibling merge):
   exactly `github_repository_ruleset.marketplace_pr_required` and `github_repository_file.marketplace_manifest` appear as in-place
   updates, the file's `content` is unchanged and only `commit_author` / `commit_email` differ on it, and the destroy count is 0.
   **Any `-/+` or destroy, a `github_repository_file` replace, or a plan that does NOT update the file aborts the merge** (a replace
   unpublishes the plugin; no file update means no write evidence).
3. Record in the PR body, from live read-only calls made before PR-ready: `gh api orgs/jikig-ai/installations --jq '.installations[] | select(.app_slug=="soleur-infra") | {id, repository_selection, permissions}'`
   (expect `contents: write`, `administration: write`) and a pointer to the mint step's success in run 36885189302, which
   proves `soleur-marketplace` is among the installation's selected repositories.
4. PR body: `Refs #8209`, `Refs #9361`, never `Closes`/`Fixes`, never `#8211`. It quotes the owner's 2026-10-04 authorization for this
   production write verbatim ("ack for all", covering #9361), carries the `User-Impact:` line from the issue, and links the deferral
   issues. The PR touches no workflow file.
5. File the deferral issues (below) before PR-ready.

## Guard Contract

### Guard 1 — manifest write is ordered after the ruleset write (`T-mp-1d`)

**Property.** `github_repository_file.marketplace_manifest` declares `depends_on` on
`github_repository_ruleset.marketplace_pr_required`, so no single apply can write the file before the bypass swap.

**Assembly.** One resource block (`resource "github_repository_file" "marketplace_manifest"`) in
`infra/github/ruleset-marketplace-pr-required.tf`; the chokepoint is that block's own top-level `depends_on` attribute. The check is a
function in `tests/scripts/test-audit-ruleset-bypass.sh` taking the `.tf` path as an argument, called on the real file and on every
mutant; it reads only that block (from its `resource` line to the closing `^}`), ignores `#` comment lines, and accepts the edge
among other members, in single-line or multi-line list form (the supported forms are stated in a comment above it). It fails closed
(rc 1) when it finds no such block. There is exactly one file-publishing resource in the root today.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `depends_on` line from the file block | RED |
| 2 | Move the `depends_on` line into the ruleset block (the string is present in the file but in the wrong resource) | RED |
| 3 | Comment the line out (`# depends_on = [...]`) | RED |
| 4 | Run the function on an empty file (its own dispatch: zero blocks found must not report 0 checked and exit 0) | RED |

**Harness rows.** (a) The suite's own positive control: the real `.tf` must PASS, so a function that rejects everything is visible; and
the mutants are produced by `sed` into a temp copy with a check that the copy differs from the original (a no-op mutation is a failure,
not a pass). (b) Must-PASS input that is not the canonical: the edge written multi-line beside a second member
(`[github_repository_ruleset.marketplace_pr_required, github_branch_default.soleur_marketplace]`).

**Anchor.** None: this guard compares a declaration to a fixed expected edge, not a stored value to the thing it protects.

## Architecture Decision (ADR/C4)

The change falsifies recorded architecture text, so the update ships with it.

### ADR

Amend ADR-241 (no new ADR; `adopting` status unchanged). Add a short dated Amendment-log entry
"2026-10-04 (#9361): the marketplace ruleset bypass actor is soleur-infra" of 2-4 lines: the swap is declared (not yet evidence); D5's
write-limb evidence is the merge apply's manifest write, recorded on #8209/#9361 after the post-merge verification; the residual is stated
once, in `ruleset-marketplace-pr-required.tf`, and this entry points there; the legacy provider arm is removed. The D5 Statuses row is NOT edited
to claim the write limb is done.

### C4 views

Read all three of `model.c4`, `views.c4`, `spec.c4`. Actors, systems and relationships checked: the
`soleurMarketplace` element (external system, already modeled; its description states the ruleset is "bypassed
only by the org admin, the Admin repo role and the soleur-ai App" and carries "KNOWN GAP (#9360)"), the
`github -> soleurMarketplace` edge (already models the apply as the soleur-infra App; its prose ends with
"KNOWN GAP (#9360)" and describes "legacy mode ... no CI runner of this root selects it"), the founder actor and
the soleur-ai runtime-key edges (unchanged). No new element, relationship or view `include` is needed. Edit
`model.c4` only: (1) the `soleurMarketplace` description: bypass set is org admin, Admin role, **soleur-infra**
App; drop the KNOWN GAP sentence; (2) the `github -> soleurMarketplace` edge: drop its KNOWN GAP sentence and the
legacy-mode clause (modes are infra and token). The derived cardinalities on that edge are untouched, so
`c4-count-parity` must stay green. Then regenerate `model.likec4.json` and run `c4-model-freshness`.

### Sequencing

No later slice: the ADR/C4 text describes the declared target and is accurate once the merge apply succeeds. If the apply fails for a
reason that invalidates the swap itself, the doc edits are reverted with the code; on a transient write refusal they stay (the ruleset is
already on the desired actor).

## Infrastructure (IaC)

### Terraform changes

`infra/github/ruleset-marketplace-pr-required.tf` and `infra/github/main.tf` only. Provider pin unchanged
(integrations/github 6.12.1). No new variable, no new secret; `variables.tf` untouched.

### Apply path

(a) Existing root, applied by the merge push through `apply-github-infra.yml`. One saved plan, two in-place updates;
`depends_on` orders them (ruleset first). Downtime: none. Blast radius: the plugin's distribution manifest
(content identical; one new empty-diff commit).

### Distinctness / drift safeguards

Not applicable (no dev/prd pair). Drift: the post-apply verify (Step 5, `verify-marketplace-ruleset.sh`) asserts
the live bypass set equals the canonical; the daily marketplace drift check reads the published bytes. Expected, not a defect: between the merge
and the end of the apply, `main`'s canonical says `5118911` while the live ruleset still says `3261325`, so a drift plan that fires in that window
reports the pending change; close any such issue after the post-merge checks pass.

### Vendor-tier reality check

GitHub rulesets on a public repo: no tier gate. The soleur-infra installation is `selected` repos and its
mint step already succeeded against `soleur-marketplace` (run 36885189302), so the repo is covered.

## Observability

```yaml
liveness_signal:
  what: apply-github-infra.yml post-apply verify Step 5 (verify-marketplace-ruleset.sh, 14/14 assertions) and the published-manifest byte-compare
  cadence: per merge to main touching infra/github, plus the daily marketplace drift check
  alert_target: red apply-github-infra run and the scheduled-marketplace-drift issue
  configured_in: .github/workflows/apply-github-infra.yml (Step 5, Step 6) and .github/workflows/scheduled-marketplace-drift.yml
error_reporting:
  destination: GitHub Actions run annotations and the drift issue
  fail_loud: "::error::marketplace ruleset (...) does not match its declaration." or the refused-write 409 in the apply log
failure_modes:
  - mode: bypass swap applied but file write refused (installation lacks contents on the repo, or the swap had not taken effect yet)
    detection: apply step exits non-zero with "Repository rule violations"; the annotation list shows an error-level entry (the stale known-gap-9361 text says the actor is still soleur-ai, which is no longer the cause)
    alert_route: red run on main, and the daily drift issue
  - mode: live bypass set differs from canonical after apply
    detection: verify-marketplace-ruleset.sh exits 1 in Step 5 (it does not run if the apply step itself failed; Post-Merge check 4 covers that path by hand)
    alert_route: red run on main
logs:
  where: GitHub Actions run logs for apply-github-infra.yml
  retention: 90 days (GitHub default)
discoverability_test:
  command: bash scripts/verify-published-manifest.sh
  expected_output: MANIFEST_IN_SYNC
```

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Add soleur-infra as a 4th actor and keep soleur-ai | Rejected: the CTO recommendation in #9361 ("swap, not add"); soleur-ai's runtime key lives on the web host. G1.2f pins it. |
| Split the author change into a second PR instead of `depends_on` | Rejected: the issue offers both; `depends_on` is one line plus a guard, and two PRs would leave a window where the manifest write path is still broken. |
| `-target` ordering or two apply steps | Rejected: the apply is one saved plan; a resource edge is the Terraform-native fix. |
| Assert the ordering from `terraform show -json` instead of parsing the `.tf` | Considered (architecture review). Not chosen: it needs credentials and a plan; the text check is local, fast and fails closed. |
| Omit `commit_author`/`commit_email` so GitHub attributes the commit | Not chosen: the owner asked for them to change; the diff also guarantees the in-place file update (DC-3). |
| Remove the workflow `known-gap-9361` annotation here | Deferred (DC-1): makes the PR touch a workflow; the annotation fires only on a 409. |
| Move `main.tf` into its own PR | Not chosen (DC-2): asked for in this PR; the INFRA-mode arm is semantically unchanged and is evidenced in Phase 3 step 5. |

## User-Brand Impact

- **If this lands broken, the user experiences:** the published `soleur-marketplace` manifest, which
  `claude plugin marketplace add/update` reads, stays frozen (every update to it refused, today's behavior) or,
  worst case, a wrong bypass actor lets an unintended identity push to it.
- **If this leaks, the user's workflow is exposed via:** the published manifest decides which code lands on
  every installed user's machine; a bypass identity that can write it without review is a supply-chain push.
  The soleur-infra key becomes the bypass identity (reachable by any Tier-B job) and also holds `administration:write` there.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the control being edited gates what reaches every install, so a
  mistake here is a one-user-compromise class event even though this change narrows the exposure; `aggregate pattern`
  would understate it (the CPO review agreed).

`requires_cpo_signoff: true` — satisfied at plan review (SIGN-OFF WITH CONDITIONS, conditions folded in). The owner's 2026-10-04
authorization covers the production write; it is quoted in the PR body. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "swap the `soleur-marketplace` ruleset bypass actor from soleur-ai (3261325) to soleur-infra (5118911) in `infra/github/ruleset-marketplace-pr-required.tf` AND `scripts/marketplace-ruleset-canonical-bypass-actors.json` (same PR, plus `verify-marketplace-ruleset.test.sh` fixtures)" | Phase 1 and Phase 2 | mapped |
| 2 | "change `commit_author`/`commit_email` on `github_repository_file.marketplace_manifest` to `soleur-infra[bot]`" | Phase 2 step 3 | mapped |
| 3 | "add `depends_on = [github_repository_ruleset.marketplace_pr_required]` on that file resource (or split the author change per the issue's ordering requirement)" | Phase 2 step 3 | mapped |
| 4 | "remove the dead legacy-mode arm in `infra/github/main.tf`" | Phase 3 | mapped |
| 5 | "refresh stale `122213433`/soleur-ai comments in `infra/github/*.tf`" | Phase 2 and Phase 3 | mapped |
| 6 | "PR body uses `Refs #8209` and `Refs #9361` only, never `Closes #8211`; close #9361 only after the post-merge apply is verified" | Phase 5 step 4, Post-Merge Verification check 6 | mapped |
| 7 | "Do NOT dispatch git-data-cutover.yml or any workflow. No agent --admin merge on a PR touching .github/workflows." | Constraint: no workflow file edited, no dispatch (Deferrals, Post-Merge recovery) | mapped |
| 8 | "Run targeted suites only (no full local battery; CI owns it)." | Phase 5 step 1 | mapped |
| 9 | "the plan must include a post-merge verification section that checks its run, the live ruleset's bypass actors, and that the marketplace manifest write path works (run each verification command once against live read-only data before committing the plan)" | Post-Merge Verification | mapped |
| 10 | "Do not touch #9394." and "avoid touching those files" (`infra/github/ruleset-ci-required.tf`, `variables.tf`) | Non-Goals | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `ruleset-marketplace-pr-required.tf` edits | "swap the `soleur-marketplace` ruleset bypass actor from soleur-ai (3261325) to soleur-infra (5118911)" | asked |
| canonical JSON edit | "`scripts/marketplace-ruleset-canonical-bypass-actors.json` (same PR" | asked |
| `verify-marketplace-ruleset.test.sh` baseline + G1.2d | "plus `verify-marketplace-ruleset.test.sh` fixtures" | asked |
| G1.2f row | — | inferred — justification: pins the "swap, not add" decision the issue records; without it the suite proves only the new value |
| `depends_on` edge | "add `depends_on = [github_repository_ruleset.marketplace_pr_required]`" | asked |
| `T-mp-1d` ordering guard | — | inferred — justification: enforcement contract; the issue states the ordering as a requirement and a silent removal of the edge would reintroduce the partial-apply race with every suite green |
| `main.tf` edit | "remove the dead legacy-mode arm in `infra/github/main.tf`" | asked |
| Phase 3 step 5 scratch probe | — | inferred — justification: the PR plan job exercises only TOKEN mode, so the INFRA-mode arm and the "neither set" behavior have no other evidence before a production apply |
| `.tf` comment refresh | "refresh stale `122213433`/soleur-ai comments in `infra/github/*.tf`" | asked |
| README hunks | — | inferred — justification: the README states the opposite of the new behavior (known gap, "a depends_on would buy nothing") and the auth model; leaving it contradicts the code |
| comment edit in `test-audit-ruleset-bypass.sh` | "refresh stale `122213433`/soleur-ai comments" | inferred — justification: the same stale soleur-ai wording sits in the guard file that already receives `T-mp-1d`, so the extra hunk is one line |
| ADR-241 amendment, `model.c4`, regenerated JSON, runbook note | — | inferred — justification: ADR-241 D5 names #9361 as a gating condition and the C4/runbook text says "known gap"; Phase 2.10 makes recorded architecture a deliverable of the change that falsifies it |
| Post-Merge Verification section | "the plan must include a post-merge verification section" | asked |
| Deferral issues | — | inferred — justification: `wg-when-deferring-a-capability-create-a` — a deferral without a tracking issue is invisible |

### Split Assessment

- Subsystems touched: 4 — `infra`, `scripts`, `tests`, `knowledge-base`
- Planned files: 11 | Estimated changed lines: ~230
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the root-count threshold trips on documentation and test roots only; the issue's
  "Must ship together" rule forbids splitting the canonical JSON from the `.tf`, and the ADR/C4/runbook edits
  must land with the change that falsifies them.

## Acceptance Criteria

### Functional

- [ ] `infra/github/ruleset-marketplace-pr-required.tf` declares exactly three `bypass_actors`; the third is `5118911` / `Integration` / `always`; `3261325` no longer appears as an `actor_id` in the `.tf`, the canonical JSON or the test fixture (prose naming soleur-ai as the former actor is allowed in comments).
- [ ] `scripts/marketplace-ruleset-canonical-bypass-actors.json` third entry is `5118911`; `bash tests/scripts/test-audit-ruleset-bypass.sh` reports `T-mp-1b` and `T-mp-1d` ok (and both were observed RED after Phase 1 before Phase 2).
- [ ] `github_repository_file.marketplace_manifest` has `commit_author = "soleur-infra[bot]"`, `commit_email = "soleur-infra[bot]@users.noreply.github.com"` and `depends_on = [github_repository_ruleset.marketplace_pr_required]`.
- [ ] `infra/github/main.tf` contains no `122213433` and no reference to `var.github_app_id` or `var.github_app_private_key`; `grep -rn '122213433' infra/github/*.tf` returns nothing.
- [ ] `terraform -chdir=infra/github validate` and `terraform fmt -check` pass; the Phase 3 step 5 scratch-probe outputs are in the PR body.
- [ ] No change to `infra/github/ruleset-ci-required.tf`, `infra/github/variables.tf`, or any `.github/workflows/*` file (`git diff --name-only origin/main...HEAD` shows none).
- [ ] `bash scripts/verify-marketplace-ruleset.test.sh` passes with 28 assertions equal to `MIN_ASSERTIONS`; `bash scripts/guard-vacuity-floor.test.sh` passes.

### Pre-merge gates

- [ ] The PR's `infra-validation` plan comment for `infra/github`, re-read after the last rebase, lists exactly the ruleset and the file as in-place updates (file: only `commit_author`/`commit_email` differ), destroy 0, no `-/+` (Phase 5 step 2).
- [ ] `c4-model-freshness` and `c4-count-parity` pass; `model.c4` no longer says "KNOWN GAP (#9360)" or that the bypass includes the soleur-ai App.
- [ ] PR body carries `Refs #8209` and `Refs #9361`, no `Closes`/`Fixes` for either, no `#8211`; it quotes the owner authorization, carries the `User-Impact:` line and the installation-permission output (Phase 5 step 3).
- [ ] Deferral issues exist (below) and are linked from the PR body.
- [ ] CPO sign-off conditions satisfied (see header note).

### Post-merge (see Post-Merge Verification)

- [ ] Checks 1-5 below all pass; #9361 is closed only after that.

## Test Scenarios

- Verifier suite: the baseline passes with the new canonical (positive control).
- G1.2d: the soleur-infra installation id (166065653) in the actor slot is rejected.
- G1.2f: soleur-ai added as a 4th actor beside soleur-infra is rejected.
- `T-mp-1d`: mutants 1-4 RED; the real file and the multi-line extra-member form PASS.
- `T-mp-1b` and `T-mp-1d` RED between Phase 1 and Phase 2, green after.
- `infra-validation` plan comment shows the two in-place updates, 0 destroys.
- Scratch probe: "neither set" fails with `app_auth.id must be set...`; dummy infra values get past argument checks.

## Post-Merge Verification

The merge triggers `apply-github-infra.yml` on push; nothing is dispatched. Every command below was run once against live read-only
data on 2026-10-04 (pre-merge) to confirm it executes and to record the baseline. `<MERGE_SHA>` is
`gh pr view 9466 -R jikig-ai/soleur --json mergeCommit --jq .mergeCommit.oid`.

**Run selection.** PR #9455 also touches `infra/github/*.tf` and the workflow's concurrency group keeps only one pending run, so this merge's own
run can be cancelled and a later push run can apply this change within its own tree. Select a push run whose `headSha` is `<MERGE_SHA>` OR a
descendant of it on `main` (`gh api repos/jikig-ai/soleur/compare/<MERGE_SHA>...<RUN_SHA> --jq .status` is `ahead` or `identical`), and treat
"no matching run yet" as NOT YET, never as pass. Wait for completion with `gh run watch <RUN_ID> -R jikig-ai/soleur --exit-status`.

| # | Check | Command | Pre-merge baseline observed | Expected after merge |
|---|---|---|---|---|
| 1 | A push apply covering this merge ran and succeeded | `gh run list -R jikig-ai/soleur --workflow apply-github-infra.yml --branch main --event push --json databaseId,conclusion,status,headSha --limit 10 --jq '.[]'` then select per Run selection | latest push run 36181825127, `success`, headSha `0cf5451bc7` (2026-09-25) | a selected row, `status: completed`, `conclusion: success` |
| 2 | The two resources were updated in place, nothing else destroyed | `gh run view <RUN_ID> -R jikig-ai/soleur --log \| grep -E 'github_repository_ruleset.marketplace_pr_required\|github_repository_file.marketplace_manifest\|Apply complete\|No changes' \| grep -vF '[0m'` (the filter drops the workflow's own script text) | run 36885189302: `No changes` / `Apply complete! Resources: 0 added, 0 changed, 0 destroyed.` | both addresses listed as updated, `... 0 destroyed.`; if a later run applied it, this check is on that run |
| 3 | No error annotation on the apply job (the known-gap line is script text in the log, so grepping the log cannot show absence; annotations can) | `gh api repos/jikig-ai/soleur/check-runs/<APPLY_JOB_ID>/annotations --jq '[.[] \| select(.annotation_level=="error")] \| length'`, with `<APPLY_JOB_ID>` from `gh run view <RUN_ID> -R jikig-ai/soleur --json jobs --jq '.jobs[] \| select(.name=="apply") \| .databaseId'` (an empty id is a failure) | job 110446654588 of run 36885189302: 0 error annotations; the `app-token` notice reads `app=soleur-infra` | `0`, and the `app-token` notice still names `app=soleur-infra` |
| 4 | The live ruleset's bypass actors (the apply's own Step 5 asserts this too, but does not run when the apply step fails) | `gh api repos/jikig-ai/soleur-marketplace/rulesets/20802604 --jq .bypass_actors` | `[{null,OrganizationAdmin,always},{5,RepositoryRole,always},{3261325,Integration,always}]` | the same list with `5118911` in the third slot, `3261325` absent |
| 5 | The manifest write path worked: a new empty-diff commit by soleur-infra[bot] (HEAD listing, not a path filter, which omits empty-diff commits) | `gh api 'repos/jikig-ai/soleur-marketplace/commits?per_page=5' --jq '.[] \| {sha: .sha[0:10], author: .commit.author.name, email: .commit.author.email, date: .commit.author.date, tree: .commit.tree.sha[0:10], parent: .parents[0].sha[0:10], msg: (.commit.message\|split("\n")[0])}'` | HEAD `0fb0e43276`, `soleur-ai[bot]`, tree `3df1424cb3`, parent `d0dc506e9c`, "chore(terraform): reconcile marketplace manifest from jikig-ai/soleur" | one commit authored `soleur-infra[bot]`, dated after the run's `createdAt`, tree `3df1424cb3` (unchanged), same message; its parent is the previous HEAD. The author string is informational (Terraform supplies it); the write evidence is this commit existing plus checks 1-3 |
| 6 | Evidence recorded, then close | comment the run URL and the outputs of checks 2, 4 and 5 on #9361 and #8209; then `gh issue close 9361 -R jikig-ai/soleur` | open | #9361 closed; #8211 untouched |

**Recovery decision table** (this pipeline dispatches nothing; any `workflow_dispatch` re-run needs the owner's separate go-ahead, and the annotation
text "bypass actor is still soleur-ai" is STALE after the swap, so do not follow it):

| Observed | Meaning | Action |
|---|---|---|
| Plan or provider-configuration error before any write | `main.tf` hunk or credentials, nothing applied | revert the `main.tf` hunk alone; no ruleset change happened |
| `409 Repository rule violations` right after the swap, check 4 shows `5118911` | ruleset updated, write refused (propagation, or installation lacks contents) | do NOT revert; notify the owner; one owner-authorized `workflow_dispatch` re-run (or a no-op push to `infra/github/*.tf`) |
| `403`/`404` from the API | installation or permission fault | stop and report to the owner; no retry, no key changes |
| Check 4 still shows `3261325` | swap did not apply | investigate the run; revert only if the swap itself is wrong |

A revert after a successful swap restores the soleur-ai actor and author and the next apply refuses the file write again (a red run with nothing published and
nothing damaged). Never edit the ruleset outside Terraform.

## Deferrals (tracking issues to create before PR-ready)

1. **Legacy-mode residue after #9361** — delete `variable "github_app_id"` and `variable "github_app_private_key"` (their "LEGACY MODE ONLY" comments become false), refresh the soleur-ai provider-identity wording in `ADR-032` (two places) and `knowledge-base/legal/article-30-register.md` (the TOMs row), and note that `apps/web-platform/infra/main.tf` and `.../git-data-root-key/main.tf` still carry the legacy arm. Re-evaluate when PR #9455 merges (it owns `variables.tf`, `ADR-032` and the register).
2. **Remove the `known-gap-9361` annotation** from `.github/workflows/apply-github-infra.yml` and the stale header sentence. Touches a workflow, so it must not be agent `--admin`-merged. Hard trigger: immediately after post-merge check 6 closes #9361; until then the annotation is known-misleading (recovery table above).
3. **Narrow soleur-ai's `administration:write` on `soleur-marketplace`** (and the "claude"/"entire" org-wide `contents:write` residual already named in the `.tf` header). Re-evaluate when the App installations are narrowed to selected repositories.
4. **Narrow the loader's export of `GITHUB_INFRA_APP_PRIVATE_KEY`** to the steps that need it (named in #9361 as "a separate hardening"), so the bypass identity's key is not reachable by every Tier-B job. Re-evaluate after this change's post-merge verification.

Milestone for all: resolved from `knowledge-base/product/roadmap.md` at creation (default `Post-MVP / Later`).

## Non-Goals

- #9394, `git-data-cutover.yml`, #8211 (never closed here), any workflow dispatch.
- `infra/github/ruleset-ci-required.tf`, `infra/github/variables.tf` (sibling PR #9455).
- The other roots' "legacy mode" literals (`apps/web-platform/infra/main.tf`, `.../git-data-root-key/main.tf`).
- Flipping ADR-241 D5 to `accepted` (other conditions remain).

## Risks and Sharp Edges

- A wrong actor id silently matches no actor (a 404-shaped failure rather than a permission error): the id is the APP id 5118911 (verified live via `gh api apps/soleur-infra`), not the installation id 166065653; G1.2d pins the typo class.
- `T-mp-1b`/`T-mp-1d` parse the `.tf` with awk/sed: keep `actor_id`/`actor_type`/`bypass_mode` as separate `key = value` lines, put comments on their own lines or after `#`, never begin a comment line with `bypass_actors {`, and keep `depends_on` as a top-level attribute of the file block.
- `depends_on` orders the API calls, not GitHub's propagation of the new bypass actor; if the write is refused immediately after the swap, the recovery table applies (a retry needs the owner).
- The README and the audit test overlap file-wise with PR #9455; hunks are small, expect at most a trivial textual conflict.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6; this one is filled.
