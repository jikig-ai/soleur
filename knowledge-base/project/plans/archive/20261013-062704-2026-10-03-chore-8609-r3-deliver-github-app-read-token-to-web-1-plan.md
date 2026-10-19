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
  today; web-2 is standby, but its SSH leg is a hard dependency of the apply) keeps serving on its
  running container in every case below; what degrades is deploys and restarts. A malformed token
  cannot reach the host (`github_app_token_shape_ok` fails the plan before any push), and the
  credential file is read tolerantly (`EnvironmentFile=-`, empty values skipped in `ci-deploy.sh`),
  so a bad render does not stop web-1 booting. The real vectors, found at review: (1) delivering the
  token activates the already-merged isolated-key overlay on the next deploy
  (`ci-deploy.sh` `no_token` gate, then the fetch); a fetched-but-rejected key makes the canary refuse
  promotion, so every web-1 deploy, including a user-facing hotfix, stays blocked until rollback,
  while the old container keeps serving (a deploy outage, not a site outage); (2) the boot overlay
  (`soleur-host-bootstrap.sh`) has no acceptance gate, so between R3 and a proven R4 a web-1 reboot is
  the one unguarded path: a wrong key would start the container and fail every connected user's
  GitHub-App features until a deploy or rollback; (3) a push that merely fails leaves web-1 on its
  previous file and R-step 4 later reports `fallback` rather than `isolated`.
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
  - mode: "delivery job waits behind the release deploy (job-level group web-1-swap, shared by the apply job and the release deploy, up to about 90 minutes) or is replaced there by a newer pending entrant"
    detection: "no apply-deploy-pipeline-fix run for the merge SHA reaches completed, or it shows cancelled"
    alert_route: "wait within the Monitor timeout; if cancelled, report and ask for a fresh ack (state still holds =0, so a later filtered run also delivers)"
  - mode: "web-2 leg fails closed before plan (web-2 SSH bridge down)"
    detection: "run red at the web-2 leg step"
    alert_route: "report to the operator; delivery is blocked until web-2 is reachable"
logs:
  where: "GitHub Actions logs for the run (public repository; values masked)"
  retention: "GitHub default Actions log retention"
discoverability_test:
  command: "curl -fsS --max-time 10 https://app.soleur.ai/health"
  expected_output: "ok"
```

Note on the probe: Check 10 of preflight runs the command in a sandbox with no credentials and
rejects pipes, shell variables and non-allowlisted verbs, so the delivery itself (a workflow run
for the merge SHA) cannot be the probe: reading it needs `gh`, a jq filter and the merge SHA. The
probe above is the unauthenticated site-health read (the plan's Phase 3.5), a regression check that
a host-config push did not take the site down. An earlier draft anchored a `gh run list` probe to
the merge SHA and, before that, read the latest run's conclusion on `main`, which already printed
`success` before this change and proved nothing. The delivered-state notice, the step verdicts and
the digest read are the evidence of delivery and are verified in Phase 3 as acceptance criteria.

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
    live_verification: "partial - the signed infra-config-status read reports the sha256 the last handler run recorded (a state record, not a live read of the file on disk), and the run's tier-2 byte compare checks the host file against the render"
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

0.1. Run `git fetch -q origin main`, then confirm `origin/main` carries the literal at the expected shape:
`git show origin/main:apps/web-platform/infra/server.tf | sed -n 's/^[[:space:]]*"github_app_runtime_token_generation=\([0-9][0-9]*\)",[[:space:]]*$/\1/p'`
prints `0`. If it prints another number, N is that value and the bump is N+1 (re-derive; do not
assume 0).

0.2. Confirm the Tier-B name is present without reading the value:
`doppler secrets --only-names -p soleur-infra-privileged -c prd | grep -c GITHUB_APP_RUNTIME_DOPPLER_TOKEN`
prints `1`. (R2's own verification already proved the value; this only guards against a deletion
since.)

0.3. Capture web-1's current `/etc/default/soleur-doppler-token` sha256 with the same signed read-only
GET as `_hook_get` / `credential_file_digest` in
`knowledge-base/project/specs/feat-one-shot-8609-evict-runtime-app-key-prd/bootstrap.sh`: an HMAC-SHA256
over an EMPTY body keyed with `WEBHOOK_DEPLOY_SECRET`; the headers `X-Signature-256: sha256=<hmac>`,
`CF-Access-Client-Id` and `CF-Access-Client-Secret` fed to curl on stdin (never argv, never printed);
run under `doppler run -p soleur -c prd_terraform --`; against
`https://deploy.soleur.ai/hooks/infra-config-status` (`soleur.ai` is the script's `DEPLOY_BASE`). Then
`jq -r '[.files[]? | select(.file == "/etc/default/soleur-doppler-token") | .sha256][0] // "absent"'`.
Print only the 64-hex digest. A non-200, an empty value or `absent` is UNREADABLE, never "unchanged":
stop and report. Baseline captured in the work phase on 2026-10-03:
`69cc2b49f20aacc357189bf381c9c60fa026e1d3d985f622c9e9a107274589fd`. Record it in the PR body.

0.4. Advisory (a point-in-time check cannot hold the group closed; Phase 3.2 is the real control).
List in-flight work that could replace the pending delivery run. `gh run list --status` takes ONE
value, so call it once per status and always name the workflow (measured at review: repeating the flag
keeps only the last value):
`for wf in apply-web-platform-infra.yml apply-deploy-pipeline-fix.yml web-platform-release.yml; do for st in in_progress queued; do gh run list -R jikig-ai/soleur --workflow "$wf" --status "$st" --limit 20 --json databaseId,status --jq '.[]|"\(.databaseId) \(.status)"' | sed "s|^|$wf |"; done; done`
(the release workflow is included because its deploy job shares the `web-1-swap` group with the apply
job), and bound the PR query to numbers:
`gh pr list -R jikig-ai/soleur --state open -L 100 --json number,autoMergeRequest,files --jq '[.[]|select(.autoMergeRequest!=null)|select(any(.files[].path; startswith("apps/web-platform/infra/")))|.number]'`.
Merge only when none of them lists a run or a PR (an unrelated workflow, for example the sentry-infra
apply, does not count).

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

3.1. Wait for the merge, then resolve its SHA:
`gh pr view 9452 -R jikig-ai/soleur --json state,mergeCommit --jq '"\(.state) \(.mergeCommit.oid // "")"'`
must print `MERGED <40-hex>` (merge is asynchronous with `--auto`; `mergeCommit` is null until it
lands, and an empty SHA must never be fed to 3.2). Set `MERGE_SHA` to that value.

3.2. Find the run for exactly that commit (not "the newest after mergedAt"):
`gh run list -R jikig-ai/soleur --workflow apply-deploy-pipeline-fix.yml --branch main --event push --limit 30 --json databaseId,headSha,status,conclusion --jq ".[]|select(.headSha==\"$MERGE_SHA\")"`.
An empty result means "not created yet or still queued behind web-1-swap": wait and retry; it is
never a pass and never a fail. Wait for `status=completed` with the `Monitor` tool, with a timeout
sized for the `web-1-swap` queue (up to about 90 minutes behind a release deploy), never a bare
background poll (`hr-monitor-not-run-in-background-for-polling`). Required: `conclusion == success`
(not `cancelled`) AND the `apply` job itself ran (a kill-switch skip also leaves the run `success`):
`gh run view <id> -R jikig-ai/soleur --json jobs --jq '.jobs[]|"\(.name) \(.conclusion)"'` shows the
apply job `success`, not `skipped`.

3.3. Log evidence for that run id, with anchors that the echoed script source cannot satisfy (the log
holds both the `echo` line from the action source and the rendered `##[notice]` line):
`gh run view <id> -R jikig-ai/soleur --log | grep -acE '##\[notice\]source=tier_b.*github_app_runtime_token=delivered'`
must be at least 1; `grep -aF 'tier-2 byte compare ACTIVE'` must match (its failure branch prints a
`::warning::` instead); and the step `Verify infra-config apply succeeded` must be `success`, not
`skipped`: `gh run view <id> -R jikig-ai/soleur --json jobs --jq '.jobs[].steps[]|select(.name=="Verify infra-config apply succeeded")|.conclusion'`
(a pass-2 sibling step with a similar name exists; read both).

3.4. Repeat Phase 0.3's signed read. The digest MUST be a 64-hex value that differs from the baseline,
and the entry must report `status == "ok"` and `changed == true`; an entry with `"sha256":""` is
UNREADABLE. Differing alone is necessary and not sufficient (any later apply that re-renders the file
differs too), and the state record reflects the last handler run, not a live disk read. If a read
fails or shows a gap right after the push, retry once after a minute: `infra-config-apply.sh`
try-restarts `vector.service` when this file changes, which briefly interrupts log shipping. Record
both digests (digests only) in a comment on PR #9452 and on #8609 (a progress comment; do not close).

3.5. Also confirm, read-only, that no deploy-state regression occurred:
`curl -sf https://app.soleur.ai/health | jq -r .status` prints `ok`. Then observe, report-only, the
auto-cut release: if its deploy ran after the delivery it is the first serving release on the isolated
key (`ci-deploy.sh` reads the token from the file with no further flag), so run
`doppler run -p soleur -c prd_terraform -- bash apps/web-platform/scripts/github-app-key-status.sh` and
report `github_app_key_source`, `_fetch` and `_probe` verbatim. This is an observation and is NOT R4's
verdict or ack: R4's remaining checks (installations superset, one `201` mint, cron probes, Sentry
silence) still need the operator's ack.

3.6. **STOP.** Report to the operator: R3 pass or fail with the evidence from 3.2 to 3.4, the new
release the merge auto-triggered and what 3.5 observed, and that R4 awaits its own ack. Do not
dispatch `web-platform-release.yml`, do not run `git-data-cutover.yml`, do not touch #9394, #9361,
#9362, any ruleset, any key rotation or any host replace.

### Rollback (not part of the happy path; needs a fresh ack)

Per runbook R3: set the Tier-B name empty (`GITHUB_APP_RUNTIME_DOPPLER_TOKEN` in
`soleur-infra-privileged/prd`), verify it is empty, THEN bump the generation again (`1` to `2`) in a
new PR; the file re-renders without the line, no SSH. The order matters: if the bump merges while the
name still holds the token, the apply delivers it again. Afterwards revoke the minted
`web-host-github-app-read` token (R2's rollback cell) so a live token does not outlive the file.
Scope: this rollback is valid only between R3 and R-step 6, and only while `soleur/prd`
`GITHUB_APP_PRIVATE_KEY` still holds a real key (not the `EVICTED_SEE_ADR_241` sentinel): once
`github_app_key_isolated` is flipped an empty name fails the precondition, and once R-step 6 evicts
the `prd` key a keyless file removes the only key source (`key_missing`). If a rollback is needed
because web-1 cannot read its file, say so to the operator first: the empty-name write and the second
PR each need their own ack.

## Files to Edit

- `apps/web-platform/infra/server.tf` (line 2041, one literal; done in the work phase, not in this
  planning run)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-8609-r3-token-generation/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-8609-r3-token-generation/session-state.md`

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
      `1 insertion(+), 1 deletion(-)`); no other repo file is changed by the PR except the plan,
      `tasks.md` and `session-state.md` under `knowledge-base/project/{plans,specs}/`.
- [ ] The PR body contains `Refs #8609` and no `Closes`/`Fixes`/`Resolves` keyword;
      `gh pr view 9452 --json body --jq .body | grep -ciE '(closes|fixes|resolves):? +#8609' || true` prints `0`.
- [ ] Neither the commit message nor the PR title/body contains `[skip-deploy-fix-apply]` on a line
      of its own (the preflight matches a whole line), and the squash title/body carry neither it nor
      `[skip-web-platform-apply]`.
- [ ] The Phase 0.3 baseline digest is recorded in the PR body (digest only).
- [ ] CI is green; the three-way merge with #9348's head is conflict-free (recorded above).

### Post-merge (read-only verification; no dispatch)

- [ ] The `apply-deploy-pipeline-fix.yml` push run whose `headSha` is the merge commit concludes
      `success` (not `cancelled`).
- [ ] That run's log contains `source=tier_b` and `github_app_runtime_token=delivered` on the same
      line, and `tier-2 byte compare ACTIVE`.
- [ ] web-1's `/etc/default/soleur-doppler-token` sha256 (signed `infra-config-status` read) is a
      64-hex value different from the Phase 0.3 baseline, with `status == "ok"` and `changed == true`.
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
- **The merge also auto-cuts a release, in the same `web-1-swap` group as the apply job.**
  `web-platform-release.yml` triggers on `apps/web-platform/**` and its inner path filter includes
  `infra/`, so this merge starts a normal patch release and deploy. The WHOLE `apply` job of
  `apply-deploy-pipeline-fix.yml` sits in job-level group `web-1-swap` (`cancel-in-progress: false`),
  as does the release's deploy job (up to about 90 minutes, drain up to about 70). So the delivery job
  can wait over an hour behind the release, and a newer `web-1-swap` entrant replaces a pending
  delivery job, a second cancellation path beside the workflow-level group. Phase 3.2 detects both.
  Ordering: before delivery `ci-deploy.sh` falls back to the still-valid `prd` key
  (`fetch=no_token`); after it, any deploy overlays the isolated key, so if the apply lands first the
  auto-release is the first serving release on the isolated key, which is R4's subject arriving
  without R4's ack (observed read-only in Phase 3.5; it authorises nothing).
- **A green run can deliver nothing.** While `github_app_key_isolated` is false an empty token is
  accepted, so a missing Tier-B name or a lost opt-in yields `github_app_runtime_token=absent`, a green
  run, and the `=1` hash latched in state; a bare dispatch would then plan no replace and recovery needs
  a bump to `=2`. Phase 3.3's `delivered` match and 3.4's digest comparison exist for this case.
- **A cancelled delivery run self-heals on the next filtered run.** State still holds `=0` while
  `main` carries `=1`, so any later `apply-deploy-pipeline-fix` run also delivers; only a later
  `apply-web-platform-infra` run does not. A hand dispatch still needs its own ack.
- **Effects on web-1 to expect.** The credential file's content and mtime change, so
  `infra-config-apply.sh` try-restarts `vector.service` once (a brief log-shipping gap, no end-user
  effect); between R3 and a proven R4 a web-1 reboot uses the boot overlay, which has no acceptance
  gate; and if the delivered key were rejected, the canary would refuse promotion and block web-1
  deploys (the old container keeps serving). Say so in the PR body so a vector blip right after merge
  is not misread.
- **Never `git add -A`; stage only the intended paths** (`hr-never-git-add-a-in-user-repo-agents`
  analogue): this worktree has an untracked scratch file `o13-path-test.txt` that must not be
  committed.
- **A plan whose `## User-Brand Impact` is empty fails deepen-plan Phase 4.6.** It is filled above.
- **Kill-switch string.** A line equal to `[skip-deploy-fix-apply]` in the head commit message makes
  the preflight skip the whole apply job, including web-2's leg, and a skipped job still leaves the run
  `success`; keep it out of every message, and verify the apply job ran (Phase 3.2).
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
