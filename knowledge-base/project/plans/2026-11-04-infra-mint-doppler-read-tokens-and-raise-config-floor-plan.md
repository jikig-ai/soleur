---
title: "infra: mint read tokens for prd_git_data, prd_workspaces_luks_marker, prd_workspaces_luks_web and raise DOPPLER_CONFIGS_FLOOR to 16"
type: infra
date: 2026-11-04
slug: mint-doppler-read-tokens-and-raise-config-floor
branch: feat-one-shot-11857-doppler-read-tokens
issue: 11857
closes: []
refs: [11857, 10205]
lane: cross-domain
domain: engineering
priority: p2
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# infra: mint read tokens for three more Doppler configs and raise the config floor to 16

## Enhancement Summary

**Deepened on:** 2026-11-04
**Sections enhanced:** User-Brand Impact, Observability, Encryption Posture, Files to Edit (3, 4, 5), Guard Contract, Dependencies & Risks
**Review agents used:** security-sentinel, user-impact-reviewer, observability-coverage-reviewer, terraform-architect, learnings-researcher, a verify-the-negative/attribution pass (Sonnet), plus the earlier plan-review pair (code-simplicity-reviewer, architecture-strategist) and the CTO and CPO rulings.

### Key Improvements

1. The worst case is now stated as it is: the published map is already a master key (its `prd` token reads the bypass-RLS Supabase service-role key, the Terraform GitHub App key and the proxy TLS key), this change widens the same class by three configs, and the tokens read values directly through the Doppler API; the "names only" wording described only what the scan prints. The emergency revocation route (revert PR plus `[ack-destroy]`, no dispatch route) is named.
2. Failure semantics are corrected: a failed apply blocks only later merges that touch `apps/web-platform/infra/**` (until retried or `[skip-web-platform-apply]`), not all merges; the merge-to-republish `degraded 13/16` is an expected transient filed as a coverage issue, with no email except the channel-failure backstop.
3. Edit sites are now exact: nine fixture lines by number and name, the T6/T20/T17 sites, and the four cited line anchors (`:3`, `:55`, `:56`, `:1218`) that make every test-file edit line-count-neutral.
4. The discoverability probe is a `grep -c` (no shell-active character) and the encryption-posture evidence for the Actions secret is a retrieved GitHub REST citation.

### New Considerations Discovered

- The per-merge apply has no rollback; a crash after a Doppler token create but before the state write is an unverified orphan risk (recorded in Dependencies & Risks).
- The `infra-validation.yml` `pull_request` plan job and `web-platform-release.yml` (push to `main` on `apps/web-platform/**`) also match the changed paths; Phase 0.3 reads both before any push.
- Repo-level Actions secrets are reachable by any workflow file a writer pushes on any branch; a census AC pins that only the drift workflow references `DOPPLER_TOKEN_DRIFT_MAP`.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). This is a single-subsystem infra change in practice.

## Overview

The twice-daily Cloudflare-token-drift scan reads every Doppler config named in one committed file,
`apps/web-platform/infra/doppler-config-inventory.txt`. `apps/web-platform/infra/token-drift-read-tokens.tf` reads that
file with `file()`, derives `local.token_drift_configs`, and mints one config-scoped read token per name under
`doppler_service_token.token_drift`; the tokens are published as ONE repo Actions secret, `DOPPLER_TOKEN_DRIFT_MAP`.
The inventory lists 13 names. Live Doppler holds 16 (issue #11857). Three configs are declared in this same Terraform
root and deliberately left out of the inventory until this change: `prd_git_data`, `prd_workspaces_luks_marker` and
`prd_workspaces_luks_web`. This PR lists them, raises the declared coverage floor from 13 to 16 in the same change, and
updates every pin, comment and record that counts or names the inventory.

When the owner later merges this PR, the per-merge infra apply (`apply-web-platform-infra.yml`, whose `-target` list
already contains `doppler_service_token.token_drift` and `github_actions_secret.doppler_token_drift_map`) creates THREE
Doppler read tokens and republishes the map with 16 entries. The PR ends as an UNARMED DRAFT (#12100); nothing in this
planning run or in the later work run mints, reads or applies anything.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #11857 / brief) | Reality (measured this session) | Plan response |
|---|---|---|
| "the for_each key set in token-drift-read-tokens.tf" | The `.tf` holds no name list. `local.token_drift_configs` is `distinct([for _l in split("\n", file("${path.module}/doppler-config-inventory.txt")) : _l if can(regex("^[a-z0-9_]+$", _l))])`. The name lines of the `.txt` ARE the key set. | Edit the `.txt` (three appended lines). The `.tf` gets a `depends_on` and comment rewrites only. |
| "the inventory lists 13" | `grep -E '^[a-z0-9_]+$' apps/web-platform/infra/doppler-config-inventory.txt \| sort -u \| wc -l` prints 13; the raw `grep -c` also prints 13 (no duplicate). | After the edit the same expression must print 16; that integer is hand-written into the floor (CTO R3). |
| "13 -> 16: three names" | `name = "prd_git_data"` (git-data-luks.tf, `doppler_config.git_data_prd`), `name = "prd_workspaces_luks_web"` (workspaces-luks-fresh-boot.tf, `doppler_config.workspaces_luks_web`) and `name = "prd_workspaces_luks_marker"` (same file, `doppler_config.workspaces_luks_marker`) all exist verbatim; none is in the inventory. Union with the 13 existing names is 16 distinct names. Whether live Doppler has exactly these 16 is NOT re-read here (Doppler reads are forbidden); the first post-merge scan reading `16/16` by name is the live proof, and a name that does not exist fails closed as an unread config. | Names come from Terraform declarations, not memory. |
| "`prd_git_data` needs `depends_on = [doppler_config.git_data_prd]`" | The inventory header and the `.tf` header (SE-4 paragraphs) say the same. But `doppler_config.git_data_prd` is a per-merge `OPERATOR_APPLIED_EXCLUSION` (`plugins/soleur/test/terraform-target-parity.test.ts`, the exclusion set, and the #9438 test "the host heartbeat secret reaches ONLY its heartbeat"). `git-data.tf` uses string literals precisely so the per-merge closure never pulls it in: if state ever lacked it, the plan would try to create it and Doppler would answer 400 "Name is already in use" on every merge to main. A `depends_on` from the per-merge-targeted `token_drift` would pull it in. | CTO R2: NO edge to `git_data_prd`. `depends_on` = the two configs that ARE per-merge targets and in state: `doppler_config.workspaces_luks_web`, `doppler_config.workspaces_luks_marker`. This DIFFERS from the issue text; it is recorded in `decision-challenges.md` and the PR body. Flip evidence: a state listing showing `doppler_config.git_data_prd` present. |
| (not in the brief) the other two names are also Terraform-declared in the same root | True; `config = each.key` is a string, so the same create-ordering race exists for them on a fresh root. They are already in the per-merge `-target` list (`-target=doppler_config.workspaces_luks_web`, `-target=doppler_config.workspaces_luks_marker`), so the edge adds nothing to the closure. | Include them in `depends_on` (CTO R2). |
| "DOPPLER_CONFIGS_FLOOR ... with a comment saying it deliberately stays 13" | The comment (token_drift step `env:` block, "DOPPLER_CONFIGS_FLOOR deliberately STAYS 13. Do NOT \"fix\" a red by lowering it") was written to hold the floor until this PR. The inventory header (RE-VERIFIED paragraph) says the same and names #11857 as the raiser. | Reconcile: delete "deliberately STAYS 13", keep the "do not lower it to fix a red" sentence, state the floor is pinned by F2/F3 with no number in the prose (CTO R4). |
| "the inventory stamp crossing 90 days reddened test-scripts; a stamp refresh already merged on 2026-11-02" | Confirmed: commit `ccd20a53b0` (#11858); line 1 reads `# generated: 2026-11-02T09:05:23Z`, so the age is 2 days against the detector's >90-day caveat. | No time-bomb in this PR. The header stamp is refreshed with honest wording (see Phase 3): it records a repo-evidence verification, not a regeneration. |
| "check the affected-index accept file if a new test or script is added" | No new test file or script is added; the one new test row lives inside the existing `terraform-target-parity.test.ts` suite (in the `plugins/soleur` bun directory suite). The accept file keys suite->path pairs by a hash of the mentioning line, so a new row that quotes a path literal could create a new unaccepted pair. | Phase 2 runs the read-only ratchet; the row reuses existing path constants instead of new literals (see Guard 1). |
| "three `13`s move together plus a set ratchet" (inventory header checklist) | Actual movers: (1) token_drift step `DOPPLER_CONFIGS_FLOOR: 13`; (2) the same step's run-time `(( 10#$cfg_floor < 13 ))` re-assertion and its warning text; (3) test `FLOOR_MINIMUM=13`; (4) `RUNG2_CONFIGS_FLOOR: 13` in the rung2-rehearsal-orphan-sweep job (S4 requires it to equal the main floor); (5) ~9 fixtures in `token-drift-workflow-causes.test.sh` with `"configs_floor":13`; (6) T17's lowered floors. The F4b set ratchet needs no edit (it only checks superset growth). | All in Files to Edit. |
| sibling WIP PR #12064 also edits `scheduled-terraform-drift.yml` | Its hunks start near lines 738, 995, 1128, 1220, 1622, 1728, 2757, 2866 and 3229 (measured with `gh pr diff 12064`, read-only); ours are the three comment+literal regions near 266-293, 485-498 and 2512-2530. No overlapping hunk or 3-line context. | Keep exactly those three hunks, zero whitespace churn; whichever PR merges second rebases. |

## Research Insights

**Premise Validation (Phase 0.6).** Cited: issue #11857 (OPEN, `closedByPullRequestsReferences` empty), epic #10205 (OPEN),
PR #12100 (this draft), sibling PR #12064 (OPEN draft). Collision pre-check: PRs naming #11857 are #12100 (this) and #12061
(an unrelated Cloudflare read-only wrapper PR that matched on text); foreign `test-all.sh` processes belong to other
worktrees. Cited files and symbols all exist on this branch: `apps/web-platform/infra/token-drift-read-tokens.tf`,
`doppler-config-inventory.txt`, `.github/workflows/scheduled-terraform-drift.yml`, `plugins/soleur/test/token-drift-workflow-causes.test.sh`.
ADR corpus check: ADR-164 and ADR-168 define the inventory/floor design and name this exact growth path; ADR-149 declares
`prd_git_data`; ADR-263 says the inventory is "deliberately not edited" (becomes stale, amended). The proposed mechanism (add
names, raise a hand-written literal) is not in any rejected-alternatives table; deriving the floor at run time IS rejected
(inventory header: "a shrinking list would lower its own alarm threshold").

**Property List (Phase 0.6b).**

- P1. The drift scan reads, by name and with that config's own token, all 16 Doppler configs.
- P2. The declared floor equals the inventory's distinct name count, and a later PR cannot lower it or shrink the inventory without a visible edit.
- P3. The create of any new token can never fail or wedge unrelated merges because of resource ordering.
- P4. Nothing is minted, read or applied before the owner merges.
- P5. No live comment, test message or doc asserts the old count or the old "not in the inventory" reasoning.

**Cut List.**

- Derive the floor at run time from the inventory -> buys no property P2 lacks; rejected by the inventory header and F2/F3 (a list must not set its own alarm threshold).
- `depends_on = [doppler_config.git_data_prd]` (issue text) -> buys P3 only on a fresh root, while creating a merge-wedge risk (the config is a per-merge exclusion, #9438); cut by CTO R2.
- A new test suite file -> a row inside the existing parity suite buys the same property and needs no accept-file, duration-table or affected-index registration.
- Regenerating the inventory from live Doppler -> needs a Doppler read (forbidden) and adds nothing: the three names are Terraform-declared.
- A clause in `scripts/encryption-posture-ledger.json` naming the new reader -> serves none of P1-P5, and the existing `doppler.secrets` entry already states that "a leaked Doppler service token ... the LUKS passphrases themselves live here", which covers the new reader class (review finding).
- Rewriting every "13" in ADR-164/ADR-168 and archived plans -> point-in-time records stay; one dated amendment instead.

**Institutional learnings applied.** `2026-08-04-a-count-framed-ratchet-cannot-see-a-rename.md` (why F4b is a set ratchet and the
three literals are counts); `2026-07-07-doppler-branch-config-does-not-isolate-secrets.md` (branch configs inherit `prd`, so the new
reach is names-only on the runner); `cq-assert-anchor-not-bare-token` and `cq-cite-content-anchor-not-line-number` (the
new row anchors on resource blocks, not numerals or line numbers).

**Deepen-pass findings and dispositions (2026-11-04).**

- security-sentinel (no blocker): all three configs are `prd` branch configs inheriting the whole `prd` root; branch-only keys are `GIT_DATA_LUKS_KEY`, `BETTERSTACK_LOGS_TOKEN`, `WORKSPACES_LUKS_KEY`, the header bucket and endpoint and the deferred R2 access pair; the detector reads values only for `CF_API_TOKEN*` and `ACCESS_TOKEN_(ID|SECRET)` names and masks them, and none of the new branch-only names match. Only `scheduled-terraform-drift.yml` references the secret. Applied: User-Brand Impact and Dependencies wording, census AC.
- user-impact-reviewer: applied the master-key worst case, the narrower blocked-merge scope, the transient-degraded wording and the revocation route.
- observability-coverage-reviewer: applied layer citations (run log, `token-drift verdict:` line, apply workflow failure email), removed the unsupported "ops email" claims; the declared probe is valid under Check 10 and now uses `grep`.
- terraform-architect (no change required): `depends_on` on the for_each token is valid and cycle-free, adds no attribute diff to the 13 existing instances, and the plan stays 3 creates plus 1 in-place map update with a redacted sensitive value; put the `depends_on` block last, after `access`, separated by a blank line so `terraform fmt` does not realign. Offline `terraform validate` is unverified (no `.terraform` directory); `terraform fmt -check` is the mandatory local check and CI covers validate.
- learnings-researcher: `2026-08-04-a-count-framed-ratchet-cannot-see-a-rename.md` confirms the F4b set ratchet must be exercised; the 2026-07-03 dark-launch learning confirms CTO R2 (a targeted resource drags in its dependencies, so an operator-excluded address must not be referenced); `-target` selects dependencies never dependents, and the map secret is explicitly in the per-merge list, so the dependent is covered.
- verify-the-negative pass: every absolute claim held (only the `apply` job targets `token_drift`; the secret is bound only in the drift workflow; the parity suite has no inventory literal; the four line cites hold). Corrections applied: fixture names and the exact edit-site table, the three regions of `scheduled-terraform-drift.yml` (git may count more hunks), and taking the `token_drift` block from `allTf` inside the describe that owns the #9438 test.

**Technical rulings.** All eight forks were ruled by the CTO agent on 2026-11-04 and are recorded verbatim in
`knowledge-base/project/specs/feat-one-shot-11857-doppler-read-tokens/decision-challenges.md`. The CPO agent confirmed no
sign-off beyond the owner's merge decision is required.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open --json number,title,body --limit 200` is re-run in Phase 0 of the work
run against the final Files-to-Edit list; no open scope-out named these paths at plan time.)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "adds prd_git_data, prd_workspaces_luks_marker and prd_workspaces_luks_web to the inventory" | Files to Edit 1 (inventory) | mapped |
| 2 | "prd_git_data needs depends_on = [doppler_config.git_data_prd]; verify every name against the live repo files" | Files to Edit 2 (`depends_on` on the two per-merge configs; `git_data_prd` edge withheld by CTO ruling R2, flagged as a deviation) | mapped |
| 3 | "raises DOPPLER_CONFIGS_FLOOR ... derived from the new inventory length rather than carried forward" | Files to Edit 3 (floor, run-time assertion, RUNG2) with the count measured by the F3 expression | mapped |
| 4 | "updates every test/pin/baseline/doc that counts or names the inventory" | Files to Edit 4-10 | mapped |
| 5 | "note the merge-conflict risk and keep your hunk minimal" | Research Reconciliation row on #12064; three-hunk discipline in Files to Edit 3 | mapped |
| 6 | "do NOT dispatch or run any workflow ... do NOT read any Doppler secret value or mint any token" | Hard Limits section; Phase 0 trigger read before any push | mapped |
| 7 | "PR body ... Needs you ... exact merge command (gh pr merge 12100 --squash)" | Phase 5 PR body | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| New scan-derived parity row (Guard 1) | "whether tests need a new row" (technical fork delegated to the CTO agent) | asked (ruled in) |
| ADR-168 amendment and ADR-263 superseded note | "updates every test/pin/baseline/doc that counts or names the inventory" | asked |
| `depends_on` on the two already-targeted configs | "prd_git_data needs depends_on = [doppler_config.git_data_prd]; verify every name against the live repo files" | asked (verification showed the same race exists for the other two names) |

### Split Assessment

- Subsystems touched: 1 - `apps/web-platform/infra` plus its CI pins and docs
- Planned files: 10 | Estimated changed lines: ~200
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (the owner asked for ONE pull request)

## User-Brand Impact

- **If this lands broken, the user experiences:** the next drift scan after the merge reports `degraded 13/16` (the floor is 16 while the published map still holds 13 entries) as a standing GitHub coverage issue, which is an EXPECTED transient: it appears at the next scan (up to about 12 hours) and auto-closes once the map is republished. No email is sent for coverage; the ops email is only the backstop when the issue channel itself fails. If the apply fails or applies partly (it has no rollback and "leaves behind whatever it had already created"), the issue stays until a retry, and the failed apply blocks every later merge that touches `apps/web-platform/infra/**` (the push trigger) until it is retried or the merge carries `[skip-web-platform-apply]`; merges that touch nothing under that path are not blocked. No end-user page or workflow is touched.
- **If this leaks, the user's data is exposed via:** `DOPPLER_TOKEN_DRIFT_MAP`, a repo-level Actions secret (reachable by any workflow file a repository writer pushes on any branch; CODEOWNERS gates merges to `.github/workflows/`, not branch runs; a census confirms only `scheduled-terraform-drift.yml` references it) with a second copy inside Terraform state on the R2 backend. The map is ALREADY a master key to production secrets: its `prd` token reads `SUPABASE_SERVICE_ROLE_KEY` (bypass-RLS read of all user data), the Terraform GitHub App private key and the proxy TLS key, and its `prd_workspaces_luks` token reads web-1's LUKS passphrase, header bucket and R2 pair. This change is a marginal widening of that same class, not a new class: three more branch configs of `prd`, each inheriting the whole `prd` root (the token reads values directly through the Doppler API; "names only" describes only what the scan prints). The new branch-specific keys are `GIT_DATA_LUKS_KEY` and `BETTERSTACK_LOGS_TOKEN` (`prd_git_data`) and `WORKSPACES_LUKS_KEY`, the header bucket and endpoint and, once minted, the bucket-scoped R2 header-escrow access pair (`prd_workspaces_luks_web`, which weakens "a passphrase alone does not open a volume without the header" because the escrow credentials sit in the same config); `prd_workspaces_luks_marker` is created empty and adds a credential with no unique secret (floor bookkeeping only). Emergency revocation: a revert PR that deletes the three tokens, which the destroy guard requires `[ack-destroy]` for; there is no dispatch rotation route (#7263).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** a credential mint that widens what one leaked secret reaches is single-user-incident class even though the change is small, because the failure shape is "one operator secret exposes customer-volume keys", not "some users see a glitch".

`requires_cpo_signoff: true` is set. The CPO agent reviewed on 2026-11-04 (no sign-off needed beyond the owner's merge; no product surface). Review time must run `soleur:engineering:review:user-impact-reviewer`.

## Does merging THIS alone mutate production?

Yes. `apply-web-platform-infra.yml` (its `apply` job, which is the only job that targets `token_drift`, also reachable via `apply_target=manual-rerun`) triggers on `push` to `main` for `apps/web-platform/infra/**` (excluding the other
roots' subtrees), so the merge click is itself the production authorization: the apply creates three Doppler read tokens and
republishes the map secret. The PR body's first line says so. Every other workflow whose `paths:` match a file this diff edits
was enumerated: `infra-validation.yml` (static gates on push; a read-only `plan -refresh=false` job on `pull_request` with
stand-in Doppler/R2 credentials and a PR comment, no apply), `web-platform-release.yml` (`push` to `main` on
`apps/web-platform/**`, so the merge also fires the normal release path for any `apps/web-platform` change; Phase 0.3 reads it
and the PR body states what it does), and NOT `apply-deploy-pipeline-fix.yml` (its path list names no file this diff edits;
re-check in Phase 0.3 because it reaches `hcloud_server.web`). Comment-only edits to `git-data.tf` and
`workspaces-luks-fresh-boot.tf` still match the apply trigger; the plan they produce is a no-op for those resources.

## Hard Limits (carried from the owner, binding on the work run)

- The run ends at a DRAFT PR (#12100), UNARMED: no ready, no merge, no auto-merge.
- Run or dispatch no workflow (apply, drift, any `mode=plan`). Run no terraform apply/plan/init against remote state or Doppler; local `terraform fmt -check` and (if providers are already cached) `terraform validate` are fine. Read no Doppler secret value; mint nothing.
- Edit no tracker; sign nothing. Use `Ref #11857` and `Ref #10205`, never a closing keyword. Verify `closingIssuesReferences` is `[]` before saving the PR body.
- Before any push, read the `on:` / `paths:` / `types:` blocks of every workflow in `.github/workflows/` and match the changed paths (Phase 0). Observed at plan time: every `apply-*` workflow triggers on `push` to `main` only (plus `workflow_dispatch`); `scheduled-terraform-drift.yml` has no `push`/`pull_request` trigger (Inngest dispatches it); `apply-sentry-infra.yml` plans on `pull_request` only when its `apps/web-platform/infra/sentry/**` filter matches (not our paths); `infra-validation.yml` runs validate/fmt/plan jobs on `pull_request` for ~84 listed paths and must be read in full in Phase 0 to confirm its `plan` job is read-only and credential-free before pushing.

## Proposed Solution

One PR, five moves:

1. Append the three names to the inventory (sorted position) and rewrite its header paragraphs that become false.
2. Add `depends_on = [doppler_config.workspaces_luks_web, doppler_config.workspaces_luks_marker]` to `doppler_service_token.token_drift`; no edge to `git_data_prd`.
3. Raise the four floor numbers to 16 (declared floor, run-time re-assertion, RUNG2 floor, test `FLOOR_MINIMUM`) and rewrite the "STAYS 13" comment.
4. Make the fixtures follow `FLOOR_MINIMUM` (hoist and interpolate) and add the one scan-derived parity row.
5. Amend ADR-168, supersede-note ADR-263, and rewrite the live comments that would otherwise lie.

## Files to Edit

1. `apps/web-platform/infra/doppler-config-inventory.txt`
   - Append `prd_git_data`, `prd_workspaces_luks_marker`, `prd_workspaces_luks_web` as bare lines in the existing sorted order (`prd_git_data` after `prd_ghcr`; the two `_workspaces_luks_*` after `prd_workspaces_luks`). Keep name lines bare: no comment, no trailing space (F5 and the detector grep per raw line).
   - Rewrite the header paragraphs that become false: the "RAISING THE FLOOR: THREE `13`s MOVE TOGETHER" block (numbers become "the declared floor"), the "ADDING `prd_git_data` NEEDS A `depends_on`" SE-4 paragraph (replace with: `git_data_prd` is deliberately NOT depended on; see `git-data.tf` and #9438; the two workspaces configs are), the "EXPECTED to drift" paragraph, and the `RE-VERIFIED 2026-11-02 ... stays as-is on purpose` paragraph (the names are now listed; record that this change is #11857's).
   - Leave the `# generated:` stamp and `# command:` line UNCHANGED (review finding, mechanical): the stamp is 2 days old, `scripts/check-cloudflare-token-drift.sh` turns it into `inventory_age_days`, so bumping it without running the live command would falsify the age signal; the header paragraph instead records that these three names were added from Terraform declarations in #11857.
2. `apps/web-platform/infra/token-drift-read-tokens.tf`
   - In `resource "doppler_service_token" "token_drift"`, add `depends_on = [doppler_config.workspaces_luks_web, doppler_config.workspaces_luks_marker]` with a comment citing the ordering race (string `config = each.key` builds no edge) and why `git_data_prd` is absent (per-merge exclusion, #9438). Do NOT touch `config = each.key`, `for_each = toset(local.token_drift_configs)` or the locals block (C-a and F5 pin them).
   - Rewrite the SE-4 comment (the paragraph mentioning `git-data-luks.tf` and "MUST add `depends_on`") to say `git_data_prd` is deliberately not depended on (per-merge exclusion, #9438). For the roughly fourteen hard-coded `13`/`thirteen` mentions in the header, add ONE dated sentence at the top ("counts written below are as of 2026-08-03; the live count is the number of name lines in the inventory") instead of editing each line (review finding: one hunk satisfies P5 and keeps the diff small). Comment-only; the dated measurements stay as history.
   - `terraform fmt -check` must pass.
3. `.github/workflows/scheduled-terraform-drift.yml` (comment and literal edits confined to THREE regions - the token_drift `env:` block, the run-time re-assertion with its adjacent comments, and the RUNG2 block - nothing else; git may report 4-5 hunks because the regions are not adjacent, none near line 738 or later)
   - token_drift step `env:` block: replace the comment sentence beginning "DOPPLER_CONFIGS_FLOOR deliberately STAYS 13" with a statement that the floor is pinned equal to the inventory's distinct name count by F2/F3 in `plugins/soleur/test/token-drift-workflow-causes.test.sh`, keeping the "Do NOT fix a red by lowering it" sentence; rewrite the "asserts this parses, is >= 13, and equals the inventory's name count" sentence without the number; change `DOPPLER_CONFIGS_FLOOR: 13` to `DOPPLER_CONFIGS_FLOOR: 16` (value measured by the F3 expression after Files-to-Edit 1).
   - Run-time re-assertion: `(( 10#$cfg_floor < 13 ))` -> `< 16`, the `::warning::` text "below the pinned minimum of 13" -> 16, and the adjacent comment "re-checked here against the literal 13" and "at a floor of 13 it collapses" accordingly.
   - rung2-rehearsal-orphan-sweep job: `RUNG2_CONFIGS_FLOOR: 13` -> 16 (S4 requires equality); update the "Three literals, one number" comment minimally.
   - Leave illustrative ratio examples in comments (`2-of-13`, `0/13`, `13/13` in prose at ~lines 256, 259, 719, 944) untouched: they are narrative examples, not pins, and touching them invites a conflict with #12064.
4. `plugins/soleur/test/token-drift-workflow-causes.test.sh`
   - Keep every edit LINE-COUNT-NEUTRAL: `scripts/lib/test-affected-paths.sh` cites this file at `:3`, `:55`, `:56` and `:1218`. So NO hoist: set `FLOOR_MINIMUM=16` where it already is defined (F2 block), and change the literal `"configs_floor":13` to `16` in place at the nine fixture sites, by current line: 323 `two`, 344 `clean` (also the T6 fixture), 357 `nocause`, 399 `degraded` (also the T20 fixture), 404 `grown`, 445 `badcov` and 468 `retired` (both escaped as `\"configs_floor\":13`), 496 `shifted`, 988 `stale_inv`; every `configs_expected:13` and the `unk_lowfloor` floor-0 fixture stay. This replaces the CTO R4 suggestion to hoist and interpolate; the review showed it forces re-quoting seven single-quoted fixtures, moves a comment block and shifts the cited lines, and the CTO's intent (the next raise is cheap) is kept by the F3 equality message naming every site.
   - Expectations that depend on the floor: the T6 expectation (the `[[ "$got" == "at-floor 13/13 13 13" ]]` test, plus its pass line "floor 13, expected 13" and the failure text that quotes the string) becomes `at-floor 13/13 16 13` (the fields are coverage, ratio, configs_floor, configs_expected, so only the third moves); the T20 grep `token-drift verdict: clean .*floor: 13.*ratio: 7/13` becomes `... floor: 16.*ratio: 7/13`. `- 13 clean -` and `at-floor 14/13` read `configs` and the ratio, not the floor, and stay. Every degraded-ratio fixture (`2/13`, `7/13`) keeps its ratio but carries `configs_floor` 16, or the raised run-time assertion re-grades it.
   - T17: the loop `for lowered in 12 0` becomes `for lowered in 15 0` (one line stays one line); reword the text sites that assert the old minimum - the T17 title (~line 892), the failure echo (~906), the pass message (~908, which says a floor of 13 "does not" downgrade - now false) and the failure text (~911, `< 13 -> degraded, >= 13`). No separate old-floor-13 case (it exercises the same `< 16` branch as 15).
   - Rewrite only comments that assert a CURRENT fact: header line ~22 ("floor against the pinned minimum of 13"), the F2 comment ~1077 (`configs_floor >= 13`) and the T17 comments; leave historical narrative numbers alone.
5. `plugins/soleur/test/terraform-target-parity.test.ts` - ONE new row inside the describe that holds the #9438 test "the host heartbeat secret reaches ONLY its heartbeat" (that describe has `planTargets`, `tf()`, `block()`, `allTf` and `missingFrom` in scope). See the Guard Contract. Take the `token_drift` block from `allTf` by matching its resource header (no new `token-drift-read-tokens.tf` literal; `allTf`, `tf()`, `block()` and `missingFrom` are in scope only inside the describe "#8754 PR-B standing tail converges on the per-merge saved plan"). Capture the inventory file name from the `file("${path.module}/...")` call in `token-drift-read-tokens.tf` rather than writing a new path literal in the suite (the suite has none today).
6. `apps/web-platform/infra/workspaces-luks-fresh-boot.tf` - rewrite the two comments "Deliberately NOT in doppler-config-inventory.txt" (the web-class config block and the marker config block): both configs are now listed; keep the surrounding rationale about per-config scoping.
7. `apps/web-platform/infra/git-data.tf` - rewrite the sentence in the comment above `local.git_data_liveness_doppler_cfg` that says `prd_git_data` "is not in that inventory today (adding it means minting a drift read token, which is the owner's credential change, not this PR's)"; KEEP the local itself and the literal reasoning: the #9438 test pins it.
8. `knowledge-base/engineering/architecture/decisions/ADR-168-per-config-read-tokens-for-the-token-drift-scan.md` - one dated 2026-11-04 amendment under `## Known limitations`: 16 tokens, the new floor, `depends_on` on the two per-merge configs, the deliberate absence of an edge to `git_data_prd` (per-merge exclusion, #9438). ADR-164 and the ADR-168 body stay as history.
9. `knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md` - append a `> **Superseded 2026-11-04**` blockquote after the sentence "`doppler-config-inventory.txt` is deliberately not edited ...", following the file's existing Superseded-note pattern.
10. `scripts/check-cloudflare-token-drift.test.sh` - comment-only: the P17 comment "the scheduled step declares 13" becomes number-free. P16 reads the real inventory and workflow dynamically and needs no change.

## Files to Create

None in the repo (no new suite, no new script, so no entry in `scripts/ci-pr-affected-audit.accept.tsv`, `scripts/lib/test-affected-paths.sh`, `scripts/suite-durations.tsv` or `scripts/suite-shard-legs.tsv`). Plan artifacts only: this plan, `tasks.md`, `decision-challenges.md`.

## Implementation Phases (test-first, per `cq-write-failing-tests-before`)

### Phase 0 - read-only preflight (no push yet)

- 0.1 Re-measure: `grep -E '^[a-z0-9_]+$' apps/web-platform/infra/doppler-config-inventory.txt | sort -u | wc -l` prints 13 before the edit.
- 0.2 Re-run the code-review overlap query (two-stage `gh issue list --json` then `jq --arg`) over the final file list; record the result in `## Open Code-Review Overlap`.
- 0.3 Read the `on:`/`paths:`/`types:` blocks of every workflow in `.github/workflows/` (the programmatic list in Hard Limits is the starting point; read `infra-validation.yml` and `apply-sentry-infra.yml` bodies in full) and record, per workflow, whether any job applies infrastructure or spends money from a feature-branch `push`/`pull_request`. Push only if none does.
- 0.4 Confirm `closingIssuesReferences` for #12100 is `[]`.
- 0.5 Read-only: confirm the body of issue #11857 lists the three names literally and quote that sentence in the PR body (the live-Doppler claim of 16 configs rests on it; no Doppler read is permitted).

### Phase 1 - RED (tests first)

- 1.1 In `token-drift-workflow-causes.test.sh`: set `FLOOR_MINIMUM=16` in place, move the nine `configs_floor` literals to 16, fix the T6/T20 expectations and T17 per Files to Edit 4 (line-count-neutral). Run the suite: it MUST fail (F1/F2/F3, floor 13 against the new minimum). Record the failing assertions.
- 1.2 In `terraform-target-parity.test.ts`: add the Guard 1 row. Run it: it MUST fail because the `token_drift` block has no `depends_on` yet (and, with the inventory still at 13 names, the non-vacuity floor of three inventory-named Terraform-declared configs also fires).

### Phase 2 - GREEN

- 2.1 Inventory: append three names. 2.2 `token-drift-read-tokens.tf`: add `depends_on`. 2.3 Workflow: the three regions. 2.4 Measure the floor with the F3 expression (expect 16) and hand-write it.
- 2.5 Run, all expected green: `bash plugins/soleur/test/token-drift-workflow-causes.test.sh`, `bash scripts/check-cloudflare-token-drift.test.sh`, `bun test plugins/soleur/test/terraform-target-parity.test.ts`, `bash scripts/check-web-host-escrow-config.test.sh`, `bash scripts/cf-tunnel-liveness-gate-mutations.test.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`, `terraform -chdir=apps/web-platform/infra fmt -check`.
- 2.6 Read-only affected-index ratchet: `python3 scripts/ci-pr-affected-replay.py ratchet` (it never writes tracked files). If the new row created an unaccepted suite->path pair, first remove the new path literal (reuse an existing constant), and only then add an accept row with a specific false-positive reason.
- 2.7 Run the F4b set-ratchet manually against the merge base: it must report the 13 baseline names still present.

### Phase 3 - comments and records

- 3.1 Files-to-Edit 6, 7, 10; inventory header; `.tf` header (one dated sentence plus the SE-4 paragraph). 3.2 ADR-168 amendment, ADR-263 note. 3.4 `rg -n '\b13\b|thirteen'` over the edited files: every remaining hit must be history, an illustrative ratio, or an unrelated number; list the survivors in the PR body under "What the agents already decided".
- 3.5 Line-anchor check: `scripts/lib/test-affected-paths.sh` cites `token-drift-workflow-causes.test.sh` at `:3`, `:55`, `:56` and `:1218`; confirm each cited line still holds the cited text (no inserted or removed line above them).

### Phase 4 - review and ship prerequisites

- 4.1 Review gates include `soleur:engineering:review:user-impact-reviewer` (threshold `single-user incident`) and the observability reviewer.
- 4.2 Commit; push only after Phase 0.3 passes; the PR stays DRAFT.

### Phase 5 - PR body (owner-facing, plain language)

Lead with what it does and its worst case. Then **Needs you**, every item tagged `(operator: production-mutating)`; the only item is the merge: `gh pr merge 12100 --squash`, with the plain statement that merging triggers the infra apply that creates three Doppler read tokens (so it is not reversible by closing the PR). Then **What the agents already decided** (the eight CTO rulings, the CPO advisory, the `git_data_prd` deviation from the issue text, and the survivors list from 3.4). `Ref #11857`, `Ref #10205` only.

## Acceptance Criteria

- [ ] `grep -E '^[a-z0-9_]+$' apps/web-platform/infra/doppler-config-inventory.txt | sort -u | wc -l` prints 16 and the raw `grep -c` prints 16 (no duplicate).
- [ ] The inventory contains exactly the three new names in addition to the original 13 (set superset check; F4b green).
- [ ] The token_drift step's `env.DOPPLER_CONFIGS_FLOOR` is 16, the run-time re-assertion compares against 16, `RUNG2_CONFIGS_FLOOR` is 16, and `FLOOR_MINIMUM` is 16 (F1, F2, F2b, F3, S4 green).
- [ ] The comment "deliberately STAYS 13" no longer appears in `.github/workflows/scheduled-terraform-drift.yml`; the "do not lower it to fix a red" sentence is kept.
- [ ] `doppler_service_token.token_drift` has `depends_on` containing exactly `doppler_config.workspaces_luks_web` and `doppler_config.workspaces_luks_marker`, and does NOT contain `doppler_config.git_data_prd` (Guard 1 asserts both).
- [ ] Every hunk of `scheduled-terraform-drift.yml` lies inside the three listed regions (token_drift `env:` block, run-time re-assertion and its adjacent comments, RUNG2 block) and none starts at or after the line-738 region #12064 edits; `git diff --stat -- .github/workflows/` shows one file; no `apply-web-platform-infra.yml` change (no new `-target` is needed).
- [ ] `token-drift-workflow-causes.test.sh`, `check-cloudflare-token-drift.test.sh`, `terraform-target-parity.test.ts`, `check-web-host-escrow-config.test.sh`, `cf-tunnel-liveness-gate-mutations.test.sh`, `c4-count-parity.test.sh` and `terraform fmt -check` all pass locally.
- [ ] The read-only affected-index ratchet reports no new unaccepted pair (or each added accept row carries a specific reason).
- [ ] Lines 3, 55, 56 and 1218 of `token-drift-workflow-causes.test.sh` still hold the text `scripts/lib/test-affected-paths.sh` cites (the edits there are line-count-neutral).
- [ ] ADR-168 carries the dated amendment; ADR-263 carries the Superseded note; the live comments in the `.tf`/`.txt` files no longer say the three names are absent from the inventory.
- [ ] PR #12100 body: `closingIssuesReferences` is `[]`; contains `gh pr merge 12100 --squash` and the plain sentence that merging triggers the apply that creates three Doppler read tokens; "Needs you" holds only `(operator: production-mutating)` items; the PR is a DRAFT, auto-merge not armed.
- [ ] Census: `git grep -l DOPPLER_TOKEN_DRIFT_MAP -- .github` lists only `.github/workflows/scheduled-terraform-drift.yml` (no second workflow binds the secret).
- [ ] No workflow was dispatched, no Doppler value read, no token minted, no terraform command run against remote state (verifiable from the session transcript).

## Test Scenarios

- Floor/inventory equality: inventory 16 distinct names, floor 16 -> F3 passes; set the floor to 15 or 17 -> F3 reds.
- Floor ratchet: floor 13 against `FLOOR_MINIMUM=16` -> F2 reds and T17's "old floor downgrades" case reds the run-time assertion path.
- Ordering row (Guard 1): remove either `depends_on` entry -> RED; add `doppler_config.git_data_prd` -> RED.
- Set ratchet: delete `prd_git_data` from the inventory -> F4b names it.
- Detector end to end: P16 grades the real 16-name inventory at the real floor as `at-floor 16/16` with nothing unread.
- Post-merge (owner-triggered, not run here): apply creates 3 tokens, republishes the map; next scan prints `ratio: 16/16`.

## Observability

```yaml
liveness_signal:
  what: the twice-daily token-drift scan step prints "token-drift verdict: ... floor: 16, coverage: at-floor, ratio: 16/16" and writes coverage_ratio to the job outputs
  cadence: twice daily (dispatched by Inngest into scheduled-terraform-drift.yml)
  alert_target: the standing token-drift coverage GitHub issue (filed by the coverage_issue arm, auto-closed by the coverage_close arm); the ops email fires only if the issue channel itself fails
  configured_in: .github/workflows/scheduled-terraform-drift.yml (id token_drift step and its coverage issue/email arms)
error_reporting:
  destination: the workflow run log (the "token-drift verdict:" line and the ::warning:: annotations) and the standing coverage issue; the job-level Sentry cron check-in covers workflow liveness only, not coverage
  fail_loud: "::warning::Cloudflare token drift read <n>/16 Doppler config(s), below its declared floor of 16" and coverage=degraded
failure_modes:
  - mode: the apply fails or applies partly, so the map stays at 13 entries
    detection: the workflow run log "token-drift verdict:" line and ::warning:: annotation on the next scan read 13 of 16 and grade degraded, naming the three unread configs in configs_unread
    alert_route: standing coverage issue (an expected transient between merge and republish); for a failed apply also the apply workflow's own failure email in apply-web-platform-infra.yml, because the scan runs only twice a day; auto-closes when coverage returns to at-floor
  - mode: a listed config does not exist live, so its token create is refused or its read fails
    detection: apply error naming the config, or that config appears in configs_unread on the scan
    alert_route: same coverage issue; the apply workflow's failure email names the failing create
  - mode: a later PR lowers the floor or shrinks the inventory
    detection: F2/F2b/F3 and the F4b set ratchet red before merge
    alert_route: failed required CI check in the PR checks list on that PR
logs:
  where: GitHub Actions run logs for scheduled-terraform-drift.yml (token_drift step)
  retention: GitHub Actions default log retention (90 days)
discoverability_test:
  command: grep -c -e '^prd_git_data' -e '^prd_workspaces_luks_marker' -e '^prd_workspaces_luks_web' apps/web-platform/infra/doppler-config-inventory.txt
  expected_output: 3
```

(The command reads the repo-side half of the signal - the three new names are listed - because the run-log half needs a
GitHub credential, and it carries no shell-active character so preflight Check 10 accepts it. It prints nothing before the
inventory edit and `3` after it. The `token-drift-workflow-causes.test.sh` F3 row enforces floor == inventory count in CI.)

## Encryption Posture

No new persistent store and no new connection is introduced; two EXISTING stores each gain three more credentials, and
this section states their posture rather than leaving it implied.

```yaml
at_rest:
  - store: r2.terraform_state_backend (Terraform state, which holds each token's write-once key and the map secret's plaintext_value)
    mechanism: provider-managed:Cloudflare-R2-SOC2-Type-II
    evidence: scripts/encryption-posture-ledger.json, the store entry "r2.terraform_state_backend" (already attested there)
    defends_against: a seized disk or a raw object-store snapshot of the bucket
    does_not_defend: anyone holding the R2 access key or the Terraform state read path reads every token key in state, now 16 instead of 13, plus the concatenated map; the passphrases for git-data and web-class volumes already sit in the same state as random_password values
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:this change may not read remote state
  - store: github_actions_secret.doppler_token_drift_map (repo-level Actions secret)
    mechanism: app-layer-envelope:libsodium-public-key-encryption-by-the-terraform-github-provider
    evidence: GitHub REST docs, page "REST API endpoints for GitHub Actions Secrets", section "Create or update a repository secret" (https://docs.github.com/en/rest/actions/secrets, retrieved 2026-11-04): the value is "encrypted with LibSodium using the public key retrieved from the Get a repository public key endpoint"; the provider does that before the API call. GitHub's own at-rest storage encryption is not attested on that page and is not relied on here
    defends_against: reading the secret value from a repository export, a fork, or the GitHub UI
    does_not_defend: any workflow on main that binds the secret, and anyone able to merge under .github/workflows (CODEOWNERS pins that to the operator); a runner that is compromised during the scan reads the whole 16-token map
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:Actions secret values are write-only by design
in_transit:
  - connection: Terraform runner -> api.doppler.com and api.github.com (token create, map publish) and scan runner -> api.doppler.com (per-config reads)
    enforced_at: provider and CLI defaults (HTTPS only); no insecure flag is set anywhere in token-drift-read-tokens.tf or the token_drift step
    tls: TLS 1.2+ via the Doppler provider, GitHub provider and the doppler CLI
    cert_verification: on
    does_not_defend: a compromised runner process or a leaked environment variable; TLS protects the wire, not the endpoint
    disclosed_as: not-publicly-claimed
```

## Infrastructure (IaC)

### Terraform changes

Files: `apps/web-platform/infra/doppler-config-inventory.txt` (the key set), `apps/web-platform/infra/token-drift-read-tokens.tf`
(`depends_on`, comments). Existing resources only: `doppler_service_token.token_drift` (for_each over the inventory) and
`github_actions_secret.doppler_token_drift_map` (in-place update to hold 16 entries). Providers unchanged (`dopplerhq/doppler`
1.21.2, the pinned GitHub provider); no new variable or sensitive input - the apply already runs with `DOPPLER_TOKEN_TF` and
the Terraform GitHub App in CI.

### Apply path

The per-merge `apply-web-platform-infra.yml` job; both addresses are already in its default `-target` allow-list and
`-target=` on a for_each resource expands to every instance (ADR-168), so no workflow edit is needed. Plan shape: 3 creates
(`doppler_service_token.token_drift["prd_git_data"]`, `["prd_workspaces_luks_marker"]`, `["prd_workspaces_luks_web"]`) and 1
in-place update (the map secret). No host, volume or server is touched; downtime and blast radius: none for runtime services.
The destroy guard sees 0 deletes; `host_creates` (scoped to `hcloud_server`) and `luks_rotations` (passphrase resources
only) do not count these resources.

### Host fan-out

Not applicable: no `terraform_data` SSH provisioner is added or edited.

### Distinctness / drift safeguards

Each token is bound `config = each.key` (C-a); the read itself is the binding assertion (a config-scoped token errors on a
wrong `-c`). No `lifecycle.ignore_changes` is added (a `-replace` rotation must still propagate into the map). The
per-merge exclusion of `doppler_config.git_data_prd` is preserved and now pinned by Guard 1.

### Vendor-tier reality check

No tier gate applies; Doppler service-token count is not limited at this scale.

## Architecture Decision (ADR/C4)

No new architectural decision: this executes the growth path ADR-164 and ADR-168 already define. The one design
judgment (do not add a `git_data_prd` edge) is recorded as a dated amendment to ADR-168 (Files to Edit 8) and a
Superseded note on ADR-263 (Files to Edit 9) in THIS PR, not a follow-up.

### C4 views

No C4 impact. Checked by reading `knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`: (a) external
human actors - the founder->doppler approval edges are about staged operator scripts, unchanged; (b) external systems -
`doppler` ("Centralized secrets management with runtime injection") and `github` exist, and no model element or edge
describes the drift scan, the map secret or a token count; (c) containers/data stores touched - none (Terraform state is
not a modeled store for this); (d) actor-to-surface access relationships - none change. `plugins/soleur/test/c4-count-parity.test.sh`
was run on this branch and passes (`ALL TESTS PASSED`); no derived cardinality in `model.c4` counts Doppler tokens.

## Guard Contract

### Guard 1 - token_drift ordering and closure guard (#11857)

**Property.** For every `doppler_config` resource in the infra root whose `name` appears in the inventory, either it is both listed in `doppler_service_token.token_drift`'s `depends_on` and on the per-merge `-target` list, or it is an `OPERATOR_APPLIED_EXCLUSION` and absent from `depends_on`; and the reference closure of `token_drift` contains no `OPERATOR_APPLIED_EXCLUSIONS` member.

**Assembly.** The population is every `resource "doppler_config"` block in `apps/web-platform/infra/*.tf` (derived by scanning, never a hand list; three are in the inventory today: `workspaces_luks_web`, `workspaces_luks_marker`, `git_data_prd`; `github_app_runtime_prd_retired` drops out because its name is not in the inventory), crossed with three independently maintained sets: the token block's `depends_on`, `planTargets` (the suite's exact `extractAllTargets(savedPlan)` set, already in scope in the describe that holds the #9438 test), and `OPERATOR_APPLIED_EXCLUSIONS`. The closure half uses the module-scope `refClosure(["doppler_service_token.token_drift"])`. The chokepoint is the one `token_drift` block (a single `depends_on` attribute), and the extractor must accept the multi-line, trailing-comma and comment-between-entries forms. The inventory path is captured from the `file("${path.module}/...")` call in `token-drift-read-tokens.tf`, so the suite gains no new path literal (it has none today) and the affected-index ratchet sees no new pair.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete `doppler_config.workspaces_luks_web` from the token block's `depends_on` | RED |
| 2 | Dispatch: make the scanner see zero `doppler_config` blocks (point the reader at a wrong file or break its block regex) while the inventory still names three | RED via a non-vacuity floor (at least 3 inventory-named configs discovered) |
| 3 | Add `doppler_config.git_data_prd` to `depends_on` (the excluded address) | RED |
| 4 | Second member after a compliant first: add a fixture `doppler_config` whose name is in the inventory and which is neither depended on nor excluded, beside the compliant ones | RED |
| 5 | Remove `doppler_config.workspaces_luks_marker` from the per-merge `-target` list while it stays in `depends_on` | RED (condition (a) needs both halves) |
| 6 | Closure half: add `git_data_prd` to `depends_on` through a different syntax (a single-line list) so only the closure check can see it | RED via `refClosure` containing an exclusion member |

**Harness rows.** Edit to the suite: replace the extractor with one that returns an empty list -> RED through the non-vacuity floor (row 2's floor, asserted separately). Must-PASS non-canonical input: a fixture `token_drift` block whose `depends_on` lists the same two addresses in the opposite order, spread over several lines with a trailing comma, plus a `#` comment between entries -> PASS.

**Anchor.** The row compares derived sets, so it proves consistency, not integrity: one diff could edit `OPERATOR_APPLIED_EXCLUSIONS` and `depends_on` together. What must also move for a weakening to pass: the per-merge target list lives in `.github/workflows/apply-web-platform-infra.yml` (CODEOWNERS pins `.github/workflows/` to the operator) and the existing test that pins `doppler_config.git_data_prd` as a birth-job-only target (it asserts the address is outside the per-merge set and inside the birth job) - a weakening has to defeat that test too.

## Dependencies & Risks

- **Unverified: `doppler_config.git_data_prd` in state.** Withholding the edge makes the PR independent of that fact (CTO R2). Cost of the other branch if the edge were added and state lacked it: every merge to main fails the apply with HTTP 400 "Name is already in use".
- **A listed config absent live.** If `prd_git_data` (or another listed name) did not exist in Doppler, its token create would fail and, because the apply is a push-triggered gate on `main`, every per-merge apply would fail until fixed (`[skip-web-platform-apply]` skips all infra). The evidence that it exists: issue #11857 states live Doppler has 16 configs, and ADR-149 records the git-data host born and fed; Phase 0.5 quotes the issue sentence into the PR body. Loud and retry-fixable either way.
- **Partial apply.** 2 of 3 tokens may be created; the map does not republish; the scan stays `degraded 13/16` until a retry. Loud, never silently green. The owner-facing statement: closing the PR does not undo a merged apply.
- **Orphaned token on a crashed apply (unverified).** A crash after Doppler creates a token but before the state write could leave a `token-drift-ci-tf-<name>` in Doppler that blocks the retry with a name conflict; the work run records whether the repo documents a recovery, and the plan's answer if not is a retry after deleting that one token through the reviewed route (never an ad-hoc dashboard step).
- **Merge-to-publish window.** Between merge and the map republish the scan grades `degraded 13/16` (CTO R7), then recovers by itself.
- **New reach.** Marginal widening of an existing class, spelled out in User-Brand Impact: three more `prd` branch configs, whose tokens read values directly through the Doppler API (the scan itself prints only names, counts and failure labels, and reads values only for `CF_API_TOKEN*` and keys matching `ACCESS_TOKEN_(ID|SECRET)`; inherited `prd` keys that match will now also be read through the three new configs, same values, more probes). Passphrases are already in Terraform state, so holders of the R2 key gain nothing; holders of the repo Actions secret are the widened surface.
- **Rotation obligations grow from 13 to 16**, with no dispatch route (tracked as #7263 for the whole family); unchanged by this PR.
- **Merge conflicts with #12064** in `scheduled-terraform-drift.yml`: none today; three-hunk discipline keeps it that way.
- **Fixture churn** in `token-drift-workflow-causes.test.sh` is the largest edit by line count; hoisting `FLOOR_MINIMUM` makes the next raise one edit.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only unfilled text, or omits the threshold fails `deepen-plan` Phase 4.6. This one declares `single-user incident`.
- `depends_on` on a `for_each` resource is static across all instances; it is harmless for the already-targeted configs but would have dragged `git_data_prd` into every per-merge plan.
- The floor is a declared literal read from nowhere at run time; do not "derive" it in the workflow. "Derived from the inventory length" means measure, then type the number.
- Do not insert or remove any line above line 1218 of `token-drift-workflow-causes.test.sh`; `scripts/lib/test-affected-paths.sh` cites lines 3, 55, 56 and 1218 of it by number.
- Do not refresh the inventory stamp: running the `# command:` line needs a Doppler read (forbidden here), and bumping the stamp without it would falsify `inventory_age_days`.

## References

- Issue #11857, epic #10205, PR #12100 (this draft), sibling PR #12064.
- ADR-164, ADR-168, ADR-149, ADR-263; `knowledge-base/project/learnings/2026-08-04-a-count-framed-ratchet-cannot-see-a-rename.md`.
- `apps/web-platform/infra/token-drift-read-tokens.tf`, `doppler-config-inventory.txt`, `git-data-luks.tf`, `workspaces-luks-fresh-boot.tf`, `git-data.tf`.
- `.github/workflows/scheduled-terraform-drift.yml`, `.github/workflows/apply-web-platform-infra.yml`.
- `plugins/soleur/test/token-drift-workflow-causes.test.sh`, `plugins/soleur/test/terraform-target-parity.test.ts`, `scripts/check-cloudflare-token-drift.test.sh`.
- `knowledge-base/project/specs/feat-one-shot-11857-doppler-read-tokens/decision-challenges.md`.
