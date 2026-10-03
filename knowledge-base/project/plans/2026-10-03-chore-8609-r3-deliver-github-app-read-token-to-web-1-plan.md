---
title: "chore(infra): #8609 R-step 3 — bump github_app_runtime_token_generation to deliver the isolated-key read token to web-1"
type: chore
date: 2026-10-03
slug: 8609-r3-deliver-github-app-read-token-to-web-1
branch: feat-one-shot-8609-r3-token-generation
issue: 8609
pr: 9452
lane: cross-domain
---

# chore(infra): #8609 R-step 3 — deliver the isolated-key read token to web-1

## Enhancement Summary

**Deepened on:** 2026-10-03
**Method:** direct verification against `origin/main` and live GitHub state (no agent fan-out: the scope is one literal, and every claim that matters was checkable by a command; the plan-review panel is deliberately left to the PR's own review).

### Key improvements
1. Pass condition tightened from bare `source=tier_b` to `github_app_runtime_token=delivered`, because the loader prints `source=tier_b` with `=absent` too (run 36922225571, 2026-10-01, printed exactly `github_app_runtime_token=absent`).
2. Run selection keyed on the merge `headSha` rather than "newest run after mergedAt".
3. Found that the merge fires three workflows, one of which (`web-platform-release.yml`) auto-cuts a release: not R4, but R4's operator must know.
4. Encryption Posture made schema-shaped (it had been prose); PAT, scope-check, observability, user-brand and guard-contract gates re-verified.

### New considerations discovered
- A malformed or wrong-shape token fails at `terraform plan` (the `github_app_token_shape_ok` precondition on `terraform_data.deploy_pipeline_fix` and `hcloud_server.web`), before the push provisioner runs, so a bad Tier-B value cannot reach web-1.
- Baseline for the fallback state is already on record: the 2026-10-01 run's deploy state reads `github_app_key_source=prd`, `github_app_key_fetch=no_token` (the `ci-deploy.sh` fallback this change begins to retire).


Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists for this
branch; the one-line scope is fully specified by the runbook row below.

**Reference, never closure.** The PR body says `Refs #8609`. #8609 stays open until PR-B (the ADR-241
D2/D10 flip, `Closes #8609`) after R-steps 7 and 8. A `Closes` here would auto-close the security
issue with the old key still live at GitHub.

## Overview

Runbook row R3 of `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`
§Runtime App key (#8609) says: deliver the Tier-B Doppler read token
(`GITHUB_APP_RUNTIME_DOPPLER_TOKEN` in `soleur-infra-privileged/prd`, minted at R2 on 2026-10-03,
verified) to web-1 by bumping the committed generation literal in
`apps/web-platform/infra/server.tf`:

```text
apps/web-platform/infra/server.tf:2041   "github_app_runtime_token_generation=0",   ->   "...=1",
```

That literal is the only element of `terraform_data.deploy_pipeline_fix`'s `triggers_replace` that is
allowed to change when the token is delivered (the other element is the KEYLESS render, census row
G6o). Merging the bump to `main` fires `apply-deploy-pipeline-fix.yml` (its `paths:` filter lists
`server.tf`). That job is Tier B (`environment: infra-privileged`) and passes
`github-app-runtime-token: true` to `.github/actions/infra-credentials`, so the loader exports the
token as `TF_VAR_github_app_runtime_doppler_token` for this job only. The provisioner then pushes the
FULL render (which now carries the one conditional `GITHUB_APP_DOPPLER_TOKEN=` line) to web-1's
`/etc/default/soleur-doppler-token` through the existing HTTPS webhook channel.

The operator has explicitly authorised R3 including the merge. The plan stops after R3 is verified:
**R4 (the `web-platform-release` dispatch) needs its own acknowledgement and is not part of this
plan.**

## Research Insights

### Premise Validation (Phase 0.6)

- #8609: OPEN (title confirmed). #9394, #9361, #9362: all OPEN and out of scope (not touched).
- `git show origin/main:apps/web-platform/infra/server.tf` carries the literal at line 2041 and
  nowhere else except two comments (lines 108 and 142). `local.github_app_key_isolated = false`
  (line 128): PR-B has not flipped it, so this PR changes delivery only, not the host's key source.
- Draft PR #9348 (web-1 plaintext wipe PR B) is OPEN, draft, held. Its `server.tf` hunks are at
  lines 536 and 2613-2671 of its own numbering. **A three-way `git merge-file` of
  (base = origin/main, ours = origin/main plus the one-line bump, theirs = #9348's head) exits 0
  with no conflict markers**, and the merged result carries `generation=1`. The hunks are 500+
  lines apart from line 2041, so there is no textual conflict in either merge order. Whichever PR
  merges second needs no hand resolution. #9348 also edits `apply-deploy-pipeline-fix.yml` (not
  relevant to the literal).
- Draft PR #9453 (scoped app-token switch, `feat-one-shot-9321-pr2-infra-app-token-switch`) touches
  no `apps/web-platform/infra` file (checked), so it cannot conflict.
- ADR corpus check (mechanism = a committed generation literal): ADR-241 §D10 records exactly this
  delivery mechanism ("delivery, re-delivery and roll-back are each a one-line PR bumping N"). It is
  the chosen decision, not a rejected alternative.
- The bootstrap script named by the runbook EXISTS on `main`:
  `knowledge-base/project/specs/feat-one-shot-8609-evict-runtime-app-key-prd/bootstrap.sh`, stage
  `stage_r3` (run as stage 6 of 13). See the Cut List for why it is reused as a recipe rather than
  executed.

### Property List (Phase 0.6b)

1. web-1's `/etc/default/soleur-doppler-token` gains the `GITHUB_APP_DOPPLER_TOKEN=` line (digest
   changes) and nothing else changes on web-1.
2. The change reaches web-1 through the Terraform-declared, hash-bound push, so every plan context
   still computes the same trigger afterwards (no perpetual drift).
3. No secret value is printed, committed, or placed in a PR body, a plan artifact or a log.
4. There is read-only evidence, from CI and the observability layer, that the property in (1) holds.
5. The change is reversible without SSH.

### Cut List

| Mechanism | Property | Disposition |
|---|---|---|
| Execute the whole `bootstrap.sh` (13 stages) | audit trail for the 13-stage sequence | **Cut.** R0-R2 are done; its `.env` state file (gitignored) is not in this worktree, so a run would re-walk R0 to R2 with their own prompts and, at R1, could be steered toward generating a key. `stage_r3` also creates its own branch `ops-8609-github-app-token-gen-N` and a second PR beside the already-open draft #9452. Reuse its exact edit (sed pattern, post-edit `grep -c == 1` guard, commit subject) and its three checks on this branch instead. |
| Re-run `stage_r3` after merge for verification | property 4 | **Cut as the primary check.** It selects the run with `--json ... | first` over a newest-first list filtered by `createdAt >= mergedAt`, which picks the NEWEST run after the merge, not the run for the merge commit. It also counts a bare `source=tier_b` line, which is printed with `github_app_runtime_token=absent` too (the run before R2 printed exactly that). Verification below keys on `headSha` and on `github_app_runtime_token=delivered`. |
| Any `workflow_dispatch` | none needed | **Cut by instruction.** A dispatch is only a fallback to a cancelled merge run and needs its own ack (see Risks). |
| A new test or guard | none | **Cut.** `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` and the tier census already cover the literal's shape. The census's `...=0` string at `tests/scripts/test-infra-privileged-tier-census.sh:2068` is a synthetic fixture inside a heredoc, not a read of the real `server.tf`, so the bump does not touch it. |

### Institutional learnings applied

- `knowledge-base/project/learnings/security-issues/2026-09-30-isolating-a-secret-onto-a-host-is-bounded-by-every-channel-that-can-change-the-host.md`
  (the keyless-trigger plus generation-literal design this step exercises).
- `hr-menu-option-ack-not-prod-write-auth`: the operator's R3 authorisation is explicit, but it is
  scoped to R3. It does not carry to R4, to a hand dispatch, or to the rollback.

## Research Reconciliation — Spec vs. Codebase

| Brief / runbook claim | Reality | Plan response |
|---|---|---|
| "Merging fires the opted-in apply" (one run) | Three workflows fire on the merge: `apply-deploy-pipeline-fix.yml` (`paths:` lists `server.tf`), `apply-web-platform-infra.yml` (`paths: apps/web-platform/infra/**`), and `web-platform-release.yml` (`paths: apps/web-platform/**`; its `check_changed` path filter `apps/web-platform/` also matches `infra/`). | Verify the right run (below). The first two share concurrency group `terraform-apply-web-platform-host` (see Risks). The third is a normal auto-release, NOT R4: it is not a hand dispatch and is not the R4 pass condition. Do not read the web-1 key-source state during R3 as an R3 verdict. |
| "its log shows the loader at `source=tier_b`" | The loader prints `source=tier_b` on every Tier-B run, including with `github_app_runtime_token=absent` (the 2026-10-01 run 36922225571 did). | Pass condition tightened to `source=tier_b ... github_app_runtime_token=delivered`. |
| "web-1's infra-config state shows ... a changed digest" | The workflow's own gate already byte-compares the host's file digest to the rendered one when it can compute it (`rendered credential digest exported — tier-2 byte compare ACTIVE`). A "changed" digest needs a before-value. | Capture the baseline BEFORE merge with the read-only signed `infra-config-status` GET; also require the tier-2 line in the run log. |
| "a bare dispatch replaces nothing" | True BEFORE the bump (state and committed literal agree). After the bump merges, state still holds the `=0` hash until an apply lands, so a dispatch from `main` WOULD replace. | Do not dispatch (standing instruction). Documented only as the operator-acknowledged fallback if the merge run is cancelled. |

## User-Brand Impact

- **If this lands broken, the user experiences:** web-1 (the only web host serving app.soleur.ai
  today; web-2 is standby) cannot read its own boot config at its next deploy or restart if the
  pushed credential file is malformed. The running site keeps serving; a restart would not come
  back until rolled back. A push that merely fails leaves web-1 on its previous file, so users see
  nothing and R-step 4 later reports `fallback` rather than `isolated`.
- **If this leaks, the user's workflow is exposed via:** the read token (read-only on the isolated
  `soleur-github-app/prd` config, which holds the GitHub App private key that mints installation
  tokens for every connected user's repositories). Vectors: a public Actions log (this repository is
  public; the loader masks the value and the render step registers `::add-mask::` on the base64),
  a PR body or plan artifact, or a Terraform state read. This PR commits no secret; the token
  travels only in the provisioner's `environment {}` and `hcloud` stores `user_data` as a hash.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** The blast radius is a host-config file on the existing
  host, with no new access to user data and the running site unaffected by a failed push; a wrong
  outcome degrades every connected user at once only after a later restart, which makes it an
  aggregate pattern rather than a single-user incident. Pre-merge baseline capture and the
  rollback below bound it.

## Observability

```yaml
liveness_signal:
  what: "the apply-deploy-pipeline-fix push run for the merge SHA concludes success, and its Load infra credentials step notice reads github_app_runtime_token=delivered"
  cadence: "once per merge to main touching the workflow's paths filter"
  alert_target: "GitHub Actions run conclusion; terraform-drift (scheduled-terraform-drift.yml, Inngest-dispatched twice daily) opens a drift issue if the trigger ever differs per context"
  configured_in: ".github/workflows/apply-deploy-pipeline-fix.yml (infra-credentials step, tier-2 digest step, Verify infra-config apply succeeded gate)"
error_reporting:
  destination: "GitHub Actions run annotations (::error::/::warning::) plus the apply job's own infra-config verify gate verdict"
  fail_loud: "a failed push fails the job red; the keyless-push guard provisioner exits 1 if github_app_key_isolated is true and the render is keyless"
failure_modes:
  - mode: "merge run cancelled (a newer pending run in terraform-apply-web-platform-host replaced it)"
    detection: "gh run list for the merge SHA shows conclusion cancelled, or no apply-deploy-pipeline-fix run for that SHA"
    alert_route: "report to the operator; fallback dispatch needs a fresh ack"
  - mode: "run green but the token was withheld or absent (Tier-B name empty or opt-in lost)"
    detection: "loader notice shows github_app_runtime_token=absent or withheld"
    alert_route: "treat as R3 FAIL; do not proceed to R4"
  - mode: "host file digest unchanged after a green run"
    detection: "signed infra-config-status read of /etc/default/soleur-doppler-token equals the pre-merge baseline"
    alert_route: "treat as R3 FAIL; compare against the run's tier-2 digest line"
logs:
  where: "GitHub Actions logs for the run (public repository; values masked)"
  retention: "GitHub default Actions log retention"
discoverability_test:
  command: "curl -s 'https://api.github.com/repos/jikig-ai/soleur/actions/workflows/apply-deploy-pipeline-fix.yml/runs?branch=main&event=push&per_page=1' | jq -r '.workflow_runs[0].conclusion'"
  expected_output: "success"
```

Note on the probe: it is unauthenticated (public repository) and finishes well inside the 15 second
cap. It reads only the latest run's conclusion. The delivered-state notice and the digest read need
an authenticated `gh` and a Doppler-held webhook secret, so they are verified in Phase 3 as
acceptance criteria rather than as the discoverability probe.

## Infrastructure (IaC)

### Terraform changes

One existing file, no new resource, no provider or version change, no new variable:
`apps/web-platform/infra/server.tf` (the `triggers_replace` list of
`terraform_data.deploy_pipeline_fix`). The sensitive input
(`TF_VAR_github_app_runtime_doppler_token`) already exists and is supplied only by the infra-credentials
loader from Tier B.

### Apply path

Existing path (b): the merge-triggered, Tier-B `apply-deploy-pipeline-fix` apply. It replaces
`terraform_data.deploy_pipeline_fix` (HTTPS push through the CF tunnel to `/hooks/infra-config`) and
re-runs the targets it pulls in (`docker_seccomp_config`, `apparmor_bwrap_profile`,
`infra_config_handler_bootstrap`, `deploy_pipeline_fix_web2`). Expected downtime: none. The
"Redeploy to load applied profile" swap only fires on a seccomp or apparmor profile difference,
which this change does not introduce.

### Distinctness / drift safeguards

The generation literal is deliberately identical in every plan context, so after the opted-in apply
records the new trigger in state, the Tier-A PR plan, the drift job and the keyless push apply all
compute the same value (census G6o). A hand edit of the literal in one context only would reproduce
the perpetual-replace defect that design removed.

### Vendor-tier reality check

Not applicable: no vendor resource is created.

## Encryption Posture

This change introduces no new persistent store and no new connection: it re-triggers an existing push
over the existing CF-tunnel HTTPS webhook channel to an existing file. The posture below restates
(does not change) what the PR-A plan declared and reviewed for the one line being delivered
(`knowledge-base/project/plans/2026-09-30-security-evict-runtime-app-key-from-prd-reachability-plan.md`
§Encryption Posture), so the `.tf` detection is answered with fields rather than a bare pointer.

```yaml
at_rest:
  - store: "web-1 /etc/default/soleur-doppler-token (root disk, 0640 root:deploy) - gains one KEY=VALUE line"
    mechanism: "plaintext-exception"
    evidence: "apps/web-platform/infra/infra-config-install.sh dest map and apps/web-platform/infra/soleur-doppler-token.tmpl (unchanged posture; one conditional line); declared in the PR-A plan"
    defends_against: "other unprivileged host users (file mode 0640 root:deploy)"
    does_not_defend: "root on the host, the units that load the file, a disk image or snapshot of the host, the provider metadata endpoint serving user_data to host processes"
    disclosed_as: "not-publicly-claimed"
    live_verification: "available - the signed infra-config-status read reports the file's sha256 and the run's tier-2 byte compare checks it"
in_transit:
  - connection: "GitHub Actions runner -> deploy.<domain>/hooks/infra-config via the Cloudflare tunnel (existing push channel)"
    tls: "HTTPS, TLS 1.2+, HMAC-signed body plus CF Access service-token headers"
    cert_verification: "on"
    does_not_defend: "a compromised runner or a leaked webhook secret (both already hold the full credential file content)"
    disclosed_as: "not-publicly-claimed"
exception:
  justification: "A host boot credential must be readable by the deploy user at boot without an operator; the file already carries the host's full-prd token under the same posture"
  tracking_issue: "#7103"
  reevaluate_when: "#7103 hardens the host credential path, or the workplace moves to Doppler service-account identities (ADR-241 A1)"
  expires_on: "2026-12-29"
```

## Architecture Decision (ADR/C4)

None. ADR-241 D10 (amended by PR-A, #9263) already records the generation-bump delivery mechanism
and this runbook step. The plan neither makes nor changes an architectural decision, so no ADR or C4
edit is a deliverable of this PR.

## Open Code-Review Overlap

One open `code-review` issue's body names `apps/web-platform/infra/server.tf`: #2197 (billing
`SubscriptionStatus` refactor). **Acknowledge:** a billing-type concern with no relation to a
one-literal infra bump; it remains open.

## Implementation Phases

### Phase 0 — Pre-merge baseline (read-only, no secret printed)

0.1. Confirm `origin/main` still carries the literal at the expected shape:
`git show origin/main:apps/web-platform/infra/server.tf | sed -n 's/^[[:space:]]*"github_app_runtime_token_generation=\([0-9][0-9]*\)",[[:space:]]*$/\1/p'`
prints `0`. If it prints another number, N is that value and the bump is N+1 (re-derive; do not
assume 0).

0.2. Confirm the Tier-B name is present without reading the value:
`doppler secrets --only-names -p soleur-infra-privileged -c prd | grep -c GITHUB_APP_RUNTIME_DOPPLER_TOKEN`
prints `1`. (R2's own verification already proved the value; this only guards against a deletion
since.)

0.3. Capture web-1's current `/etc/default/soleur-doppler-token` sha256, using the same signed
read-only GET that `credential_file_digest` / `_hook_get` use in the bootstrap script (HMAC plus CF
Access headers fed to curl on stdin, never argv; `doppler run -p soleur -c prd_terraform`):
`GET https://deploy.<APP_DOMAIN_BASE>/hooks/infra-config-status`, then
`jq -r '[.files[]? | select(.file == "/etc/default/soleur-doppler-token") | .sha256][0] // empty'`.
Print only the 64-hex digest; record it in the PR #9452 body under "Baseline". A non-200 or empty
result is UNREADABLE, never "unchanged": stop and report.

0.4. List in-flight infra-path work that could queue a third run in group
`terraform-apply-web-platform-host` during the merge window:
`gh run list -R jikig-ai/soleur --status in_progress --status queued --json workflowName,headSha`
for `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml`, and open PRs with auto-merge
enabled touching `apps/web-platform/infra/**` (`gh pr list --json number,autoMergeRequest,files`).
Merge only when none is running or queued.

### Phase 1 — The one-line edit (work phase; this planning run does not edit `server.tf`)

1.1. On this branch, reproduce `stage_r3`'s edit exactly:
`sed -i 's/"github_app_runtime_token_generation=0",/"github_app_runtime_token_generation=1",/' apps/web-platform/infra/server.tf`,
then assert `grep -c '"github_app_runtime_token_generation=1",' apps/web-platform/infra/server.tf`
prints `1` and `git diff --stat` shows `1 file changed, 1 insertion(+), 1 deletion(-)`.

1.2. Commit subject (matches the script's): `chore(8609): deliver the soleur-github-app read token to web-1 (generation 1)`.
The commit message MUST NOT contain the kill-switch string `[skip-deploy-fix-apply]` (the preflight
job would skip the apply). The squash-merge message must not either.

1.3. Run the suites that read `server.tf`: `bash tests/scripts/test-infra-privileged-tier-census.sh`
and `bun test plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts plugins/soleur/test/terraform-target-parity.test.ts`
(they exist on `main`; failures of a suite this edit cannot affect are triaged per
`wg-when-tests-fail-and-are-confirmed-pre`). Run `terraform fmt -check` and `terraform validate`
in `apps/web-platform/infra` only if the local toolchain has the providers; CI's
`infra-validation` job is the authority.

### Phase 2 — PR

2.1. Update draft PR #9452 (it already exists): title
`chore(8609): github_app_runtime_token_generation 1 (R-step 3)`, body begins with
`Refs #8609` and carries the runbook link, the Phase 0.3 baseline digest, the merge-conflict note for
#9348, the three-workflows-fire note, the rollback and "STOP before R4". Never `Closes`.
End the body with the attribution line from the session reminder.

2.2. Mark ready, let required checks pass, merge through the repository's normal merge path
(`gh pr merge 9452 --squash --auto` after checks). This is the authorised "merge to main that fires
the opted-in apply". Skip `soleur:ship`'s generic post-merge `workflow_dispatch` step; no
workflow is dispatched by hand.

### Phase 3 — Post-merge verification (read-only; the R3 pass condition)

3.1. `MERGE_SHA=$(gh pr view 9452 -R jikig-ai/soleur --json mergeCommit --jq .mergeCommit.oid)`.

3.2. Find the run for exactly that commit (not "the newest after mergedAt"):
`gh run list -R jikig-ai/soleur --workflow apply-deploy-pipeline-fix.yml --branch main --event push --limit 15 --json databaseId,headSha,status,conclusion --jq ".[]|select(.headSha==\"$MERGE_SHA\")"`.
Wait for `status=completed` with the `Monitor` tool on that run (never a bare background poll,
`hr-monitor-not-run-in-background-for-polling`). Required: `conclusion == success`, **not**
`cancelled`.

3.3. Log evidence for that run id: `gh run view <id> --log | grep -a 'source=tier_b'` shows a line
containing `github_app_runtime_token=delivered`; and
`grep -a 'tier-2 byte compare ACTIVE'` matches (so the in-run gate byte-compared the host file to the
render that includes the token line); and the `Verify infra-config apply succeeded` step is green.

3.4. Repeat Phase 0.3's signed read; the digest MUST be a 64-hex value that differs from the
baseline. Record both digests (digests only) in a comment on PR #9452 and on #8609
(`Refs`-style progress comment; do not close).

3.5. Also confirm, read-only, that no deploy-state regression occurred:
`curl -sf https://app.soleur.ai/health | jq -r .status` prints `ok`.

3.6. **STOP.** Report to the operator: R3 pass or fail with the three pieces of evidence, the new
release the merge auto-triggered (see Risks), and that R4 awaits its own ack. Do not dispatch
`web-platform-release.yml`, do not run `git-data-cutover.yml`, do not touch #9394, #9361, #9362,
any ruleset, any key rotation or any host replace.

### Rollback (not part of the happy path; needs a fresh ack)

Per runbook R3: set the Tier-B name empty (`GITHUB_APP_RUNTIME_DOPPLER_TOKEN` in
`soleur-infra-privileged/prd`), then bump the generation again (`1` to `2`) in a new PR; the file
re-renders without the line, no SSH. If a rollback is needed because web-1 cannot read its file, say
so to the operator first: the empty-name write and the second PR each need their own ack.

## Files to Edit

- `apps/web-platform/infra/server.tf` (line 2041, one literal; done in the work phase, not in this
  planning run)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-8609-r3-token-generation/tasks.md`

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "open a one-line PR bumping \"github_app_runtime_token_generation=0\" to \"=1\" at apps/web-platform/infra/server.tf" | Phase 1, Files to Edit | mapped |
| 2 | "Use Refs #8609, never Closes" | Overview, Phase 2.1 | mapped |
| 3 | "The operator has explicitly authorised R3, including the merge to main" | Phase 2.2 | mapped |
| 4 | "Do NOT dispatch any workflow by hand" | Cut List, Phase 2.2, 3.6, Risks | mapped |
| 5 | "R3 pass condition to verify after merge: the first apply run after the merge concludes success ... loader at source=tier_b ... changed digest" | Phase 3.2-3.4 (tightened to the merge SHA and to `delivered`) | mapped |
| 6 | "Check whether the runbook's bootstrap script ... exists and use it if so" | Premise Validation, Cut List (exists; its R3 recipe is reused, not the full 13-stage run) | mapped |
| 7 | "Rollback if needed: set the Tier-B name empty and bump the generation again in a new PR" | Rollback | mapped |
| 8 | "STOP and report to the operator before R4" | Phase 3.6 | mapped |
| 9 | "check that a one-line bump does not hunk-conflict with it and note it in the plan" | Premise Validation (merge-file exit 0) | mapped |
| 10 | "Do not touch #9394, #9361, #9362 or any ruleset, key rotation, or host replace" | Phase 3.6 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Pre-merge baseline digest (Phase 0.3) | "web-1's infra-config state shows /etc/default/soleur-doppler-token with a changed digest" | asked (a change needs a before-value) |
| Tighten to `github_app_runtime_token=delivered` | "its log shows the loader at source=tier_b" | asked, sharpened: `source=tier_b` also prints with `=absent` |
| Select the run by merge `headSha` | "the first apply run after the merge concludes success" | asked, sharpened: "first after" by timestamp can match a later unrelated run |
| In-flight third-run check (Phase 0.4) | "not cancelled; concurrency group terraform-apply-web-platform-host keeps only the newest pending run" | asked |
| `/health` check (3.5) | — | inferred — justification: one read-only line confirming the site still serves after a host-config push; zero cost |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform/infra`
- Planned files: 1 edited (plus plan and tasks) | Estimated changed lines: 2 (1 insertion, 1 deletion)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `git diff origin/main...HEAD -- apps/web-platform/infra/server.tf` is exactly one removed and
      one added line, the literal changing from `=0` to `=1` (`git diff --stat` shows
      `1 insertion(+), 1 deletion(-)`); no other repo file is changed by the PR except the plan and
      `tasks.md` under `knowledge-base/project/{plans,specs}/`.
- [ ] The PR body contains `Refs #8609` and no `Closes`/`Fixes`/`Resolves` keyword;
      `gh pr view 9452 --json body --jq .body | grep -ciE '(closes|fixes|resolves) +#8609'` prints `0`.
- [ ] Neither the commit message nor the PR title/body contains `[skip-deploy-fix-apply]`.
- [ ] The Phase 0.3 baseline digest is recorded in the PR body (digest only).
- [ ] CI is green; the three-way merge with #9348's head is conflict-free (recorded above).

### Post-merge (read-only verification; no dispatch)

- [ ] The `apply-deploy-pipeline-fix.yml` push run whose `headSha` is the merge commit concludes
      `success` (not `cancelled`).
- [ ] That run's log contains `source=tier_b` and `github_app_runtime_token=delivered` on the same
      line, and `tier-2 byte compare ACTIVE`.
- [ ] web-1's `/etc/default/soleur-doppler-token` sha256 (signed `infra-config-status` read) is a
      64-hex value different from the Phase 0.3 baseline.
- [ ] No secret value appears in any command output, PR body, comment or artifact (digests only).
- [ ] The session ends by reporting to the operator and stopping before R4.

## Domain Review

**Domains relevant:** Engineering (infrastructure/security) only.

### Engineering

**Status:** reviewed
**Assessment:** The security architecture (CTO), the legal assessment (CLO, no notification duty
from a reachability-only exposure) and the product framing (CPO) for #8609 were recorded in the PR-A
plan and ADR-241 D10; R3 executes a decided runbook step and adds no new surface. No marketing,
sales, finance, support or product (UI) implication: no user-facing page or component is created or
changed (`## Files to Edit` lists no UI-surface path). No GDPR-regulated schema, auth or API surface
is touched, and none of the four cross-controller data-movement triggers (new LLM/external API
processing, single-user-incident threshold, learnings-reading cron, new distribution surface) fires.

## Test Scenarios

- Given `origin/main` with `=0`, when the sed edit runs, then exactly one line changes and the
  post-edit `grep -c` guard prints `1` (a second match or zero aborts the edit).
- Given #9348's head, when merged with the edit by `git merge-file`, then exit status is 0.
- Given the merge run completes `success` but the loader printed `github_app_runtime_token=absent`,
  then R3 is FAIL (nothing delivered).
- Given the merge run is `cancelled`, then R3 is not met; report and wait for an acknowledged
  decision (no self-dispatch).
- Given the post-merge digest equals the baseline, then R3 is FAIL even if the run was green.

## Risks and Sharp Edges

- **Concurrency: a cancelled delivery run.** `apply-deploy-pipeline-fix.yml` and
  `apply-web-platform-infra.yml` both fire on this merge and share group
  `terraform-apply-web-platform-host` (`cancel-in-progress: false`). One runs, one waits. If a THIRD
  run for either workflow enters the group while one waits, the waiting one is replaced and shows
  `cancelled`. Phase 0.4 guards against queuing it; Phase 3.2 detects it. If the delivery run is the
  cancelled one, state still holds the `=0` trigger, so a `workflow_dispatch` of
  `apply-deploy-pipeline-fix.yml --ref main` WOULD deliver (the earlier "replaces nothing" caveat
  applies only before the bump merges). That dispatch is a hand dispatch and needs its own explicit
  ack; this plan reports instead of doing it.
- **The merge also auto-cuts a release.** `web-platform-release.yml` triggers on `apps/web-platform/**`
  and its inner path filter includes `infra/`, so this merge starts a normal patch release and
  deploy, in a different concurrency group from the apply (the `web-1-swap` mutex serializes only
  the container swap). Either ordering is safe: before delivery, `ci-deploy.sh` falls back to the
  still-valid `prd` key (`fetch=no_token`); after, it overlays the isolated key. It is not R4 and
  authorises nothing: R4's pass condition (a serving release proven `isolated/ok/ok`, installation
  superset, cron probes, Sentry silence) is a separate verification the operator still must ack.
  Report the release's tag so R4 starts from a known state.
- **Never `git add -A`; stage the two intended paths only** (`hr-never-git-add-a-in-user-repo-agents`
  analogue): this worktree has an untracked scratch file `o13-path-test.txt` that must not be
  committed.
- **A plan whose `## User-Brand Impact` is empty fails deepen-plan Phase 4.6.** It is filled above.
- **Kill-switch string.** `[skip-deploy-fix-apply]` anywhere in the head commit message skips the
  whole apply job, including web-2's leg; keep it out of every message.
- **The sed pattern is anchored on the full quoted literal with its trailing comma.** A `=0` inside
  a comment (lines 108, 142 mention the name, not a value) is never matched.
- **Non-goal:** the weaknesses noted in the bootstrap script's `stage_r3` verifier (newest-run pick,
  bare `source=tier_b` match) are left unedited here; the script is a frozen PR-A artifact and
  changing it is outside a one-line PR. They matter only if someone re-runs the script's stage 6.
- **A wrong-shape Tier-B value fails safe.** `local.github_app_token_shape_ok` is a precondition on
  both `terraform_data.deploy_pipeline_fix` and `hcloud_server.web`; with the opt-in set it requires
  `^(dp\.st\.[A-Za-z0-9._-]{20,})?$` (empty or a service token). A malformed value therefore fails the
  plan step, which is before any provisioner pushes, and web-1 keeps its previous file.
- **Test runner.** The two plugin suites use `bun:test` (`import ... from "bun:test"`), hence
  `bun test <path>` in Phase 1.3; `terraform-target-parity` and the gate suite contain no reference to
  the generation literal, so the bump cannot break them by value.
