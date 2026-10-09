---
title: "fix: argv-bearer sweep S4, push-triggered production-class files off the process command line"
date: 2026-10-09
slug: argv-bearer-sweep-s4-push-triggered-production-class
branch: feat-one-shot-argv-bearer-sweep-s4-push-triggered
issue: 9597
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

Spec lacks valid lane: defaulted to cross-domain (TR2 fail-closed).

## Overview

Slice S4 of the argv-credential sweep (tracker #9597, parent #7797). S1 (#9674) widened Rule E to workflow, composite-action and cloud-init YAML; S2 (#9753)
converted the ops, runner and plugin scripts; S3 (#9811, merge `ca5295d712`) added `scripts/lib/bearer-curl.sh` (ADR-280) and converted the workflows that cannot
fire production on merge. S4 converts the **push-triggered, production-class** files: the deploy-webhook callers (HMAC signature plus the Cloudflare Access pair), the
Supabase, GitHub App, Resend and Hetzner bearer sites, the `openssl dgst -hmac` keys that sit on the same calls, one `x-access-token:` push URL, and the two sites
S3 deliberately held back (`workspaces-luks-cutover.yml`, and the `probe` step of `scheduled-inngest-health.yml`).

The PR carries `Ref #9597` and `Ref #7797` (never `Closes`; only S5 closes #9597). S5 (`apply-web-platform-infra.yml`, `cloud-init-registry.yml`) is not planned here.

**What the measurements changed (details in "Research Reconciliation", "Census" and "Stub holders").**

1. **15 files change, not 14.** The tracker's S4 list names 14 entries. Re-derived on `origin/main` (`5485dffdaf`): `ci-deploy.sh` is **already done** (its fan-out HMAC key moved to a python3 child
   in #9805, `8729cc0dfa`; Rule E reads it clean), so it leaves the slice. Two files the lint cannot see join it: `verify-tunnel-ingress-origin.sh` (the second call signs with `openssl -hmac`) and
   `bump-inngest-bootstrap-pin.sh` (the push URL carries the token). The 13 baseline-E files of S4 hold **31 sites**; baseline E goes from **17 files / 42 sites to 4 files / 11 sites**
   (`apply-web-platform-infra.yml` 5, `cloud-init-registry.yml` 4, the two cla-evidence files 1 each: the S5 and #9756 residue).
2. **20 production `openssl dgst -hmac "$KEY"` sites** are in S4 files (track.sh 2, apply-deploy-pipeline-fix 5, deploy-inngest-image 2, restart-inngest-server 3, scheduled-inngest-health 1,
   web-platform-release 3, infra-config-verify 1, push-infra-config 1, verify-tunnel-ingress-origin 1, github-app-key-status 1). Rule E does not see them (the key is on openssl's argv, not curl's). The only other
   production holders are the two held-back arms in `scripts/cutover-inngest.sh` (#9757 item 1) and two agent-executed Markdown files, which stay out of S4 (D10).
3. **The merge fires production workflows.** Three S4 files and four S4-edited suites sit under `apps/web-platform/infra/**`, one more file under `apps/web-platform/scripts/`, and `push-infra-config.sh` is
   hashed into `terraform_data.deploy_pipeline_fix`'s `triggers_replace`. Merging therefore fires the production apply, the deploy-pipeline-fix apply (which **replaces** `deploy_pipeline_fix` and re-runs the
   converted `push-infra-config.sh` against web-1), the web release and deploy (whose `deploy` job is itself converted), and `apply-inngest-rls` against the Inngest production database. See MERGE EFFECTS.
   The brief requires explicit lead notice before ship and a verified apply outcome afterwards; Phase 11 is that stop.
4. **Three refusal mappings would have been wrong if converted mechanically** (D2): the post-re-push liveness probe would read a refused credential as `listener_state=down` ("the re-push bricked the only no-SSH remediation channel"),
   `infra-config-verify.sh` would print "the webhook listener is DOWN" for a refused credential, and the `pre_frame` step would label it `unreachable`. Each gets an explicit pre-guard that lands in the honest existing class.
5. **Nine of the 31 sites take the S2 inline wrapper, not the sourced library** (D3, D4), each because a pinned property of the job or its suite rules out sourcing a repo file: the Hetzner read in `workspaces-luks-cutover.yml` (its suite's census bans any
   repo script executed in the token-holding step), `infra-config-verify.sh` (its suite's actuation sweep pins a read-only command allowlist) and the seven sites of the three **checkout-free** jobs (`web-platform-release` `deploy` and `release-outcome`, `deploy-inngest-image` `deploy`),
   whose documented design (ADR-072, ADR-217, the file's own comments, `workflow-run-deploy-invariants`) is that they carry no checkout. The other 22 sites use the library. The alternative for the checkout-free jobs (a one-file sparse checkout plus the library) is recorded for the lead.
6. **#9877 is larger than first read.** It is 57 files and also edits `apply-web-platform-infra.yml` (S5's file) and several `.tf` files, so it fires the same production apply; see MERGE EFFECTS (Collision).

### MERGE EFFECTS (read first)

Evaluated by parsing every workflow's `on.push.paths` against the planned file set (the 15 production files, the four infra suites, the battery, the lints and the docs), not from memory.

| Trigger | Fires on merge? | Why | Plan response |
|---|---|---|---|
| `apply-web-platform-infra.yml` (push `apps/web-platform/infra/**`) | **Yes** | `push-infra-config.sh`, `infra-config-verify.sh`, `scripts/verify-tunnel-ingress-origin.sh` and four edited infra suites are under the prefix. It is the production Terraform apply (SSH-provisioned installs, tunnel verify, the verify-tunnel step is converted). | Lead notice before ship (Phase 11); outcome read after merge (post-merge table). Kill-switch choice offered. |
| `apply-deploy-pipeline-fix.yml` (push, lists `push-infra-config.sh`) | **Yes, and it replaces a resource** | `push-infra-config.sh` is hashed in `terraform_data.deploy_pipeline_fix.triggers_replace` (read in `server.tf`; `deploy_pipeline_fix_web2` does **not** hash it, and a suite pins that). The apply re-creates the resource and runs the converted script as a local-exec provisioner: an HTTPS POST of ~20 base64 files through the Cloudflare tunnel to `/hooks/infra-config`. | Same notice. This is the **live first run** of the converted `push-infra-config.sh`. A `cancelled` run is not a pass: `apply-deploy-pipeline-fix` and `apply-web-platform-infra` share the group `terraform-apply-web-platform-host` with `cancel-in-progress: false`, so a running apply is never killed, but GitHub keeps one running and one pending run and **drops an older pending run when a third arrives** (two were dropped this way today). If the merge's run is dropped, the `deploy_pipeline_fix` replacement and the first live run of the converted push script are undelivered until a later qualifying push or an approved dispatch; Phase 11 checks whether a later push already carried it. |
| `web-platform-release.yml` (push `apps/web-platform/**`) | **Yes** | `apps/web-platform/scripts/github-app-key-status.sh` and every `apps/web-platform/infra/**` edit match. Its `deploy` job (converted here) runs for the merge itself. | The release's own deploy is the first live run of five converted sites; read the run, grep the log for the marker. Revert plan in Phase 11. |
| `apply-inngest-rls.yml` (push, lists **its own file**) | **Yes** | The workflow file is edited, so it applies `0001_enable_rls_lockdown.sql` (a schema-wide REVOKE-all, idempotent) to `soleur-inngest-prd`, then runs the catalog gate with the real token. | Self-exercise of the four converted calls against the real vendor. Expected: success, `violations=0`. |
| `restart-inngest-server.yml`, `deploy-inngest-image.yml` (push, list their own file) | Registers a run; **the job is skipped** (`if: github.event_name == 'workflow_dispatch'`, pinned by `restart-inngest-workflow-guard.test.sh`) | The push trigger exists only to register the workflow in the UI (#6425). | No production effect. Not a live proof of the conversion either. |
| `mint-inngest-bootstrap-tag.yml` (push `apps/web-platform/infra/inngest*`) | Yes (the edited `inngest-dedicated-host-classify.test.sh` matches) | The decision is hash-based over image carriers, so the run decides `noop` and mints nothing. | Read the run: `result=noop`. |
| `infra-validation.yml` (`apps/*/infra/**`), `validate-vector-config.yml` (`apps/web-platform/infra/*.sh`) | Yes | CI gates, no deploy. | Part of the pre-merge proof. |
| `apply-github-infra.yml`, `apply-sentry-infra.yml`, `cutover-inngest.yml` | No | `apply-github-infra` lists only `infra/github/*.tf` and its jq filter, not itself. | None. |
| `version-bump-and-release.yml` (`plugins/soleur/**`) | **No** | No file under `plugins/` is planned (Phase 0 re-checks; a plugin edit adds a plugin release run). | Acceptance row: diff contains no `plugins/` path. |
| Unfiltered push workflows (`ci`, `secret-scan`, `codeql-main-alert-gate`, skill-security-scan, `tenant-integration`, `vendor-pin-verify`) | Yes, by design | CI gates. | None. |
| Runtime reach without a trigger | **Next use** | `mint-infra-app-token` is called by `apply-github-infra`, `build-inngest-bootstrap-image` and `mint-inngest-bootstrap-tag`; `dispatch-web-redeploy/track.sh` by two git-data jobs in `apply-web-platform-infra` and by `git-data-cutover`. | Battery rows drive the real bodies; first live run is tracked by a follow-through (Phase 10). |

**Collision.** Open draft PR #9877 (retires the wipe apparatus; 57 files, including `apply-web-platform-infra.yml` and several `.tf` files, so it **also fires the production apply** and S5 will conflict with it on that workflow file) edits, among them, `apply-deploy-pipeline-fix.yml` (one `echo` line near the first `::error::ROUTING` message, about 110 lines above the first S4 hunk),
`cutover-inngest.yml`, `scripts/cutover-inngest.sh` and `cutover-inngest-workflow.test.sh`. Two PRs that each fire the apply serialize in the merge queue and share the `terraform-apply-web-platform-host` group; the lead notice names both. S4 plans **no** edit to the last three, and its `apply-deploy-pipeline-fix.yml` hunks begin at the `pre_frame` step
(about line 590), so the two diffs do not overlap by hunk; whichever PR merges second runs `git merge origin/main`, never a rebase of an armed PR. If Phase 0's coupled-suite run shows S4 must edit
`cutover-inngest-workflow.test.sh`, stop and report: that suite is in #9877's diff (+25/-18) and the edit would conflict.

## Decisions

**D1. One library, five conversion shapes.** Reuse `scripts/lib/bearer-curl.sh` unchanged (`bc_curl`, `bc_hmac_sha256_hex`, `bc_ok_var`, `bc_refuse`; the single `_bc_send` chokepoint). No library change is planned: every real call
argument list is **replayed** through `_bc_tail_ok` in Phase 0 (binding lesson 3) and any refusal turns that site into a plan amendment, not a library edit. The replay must use the real bodies, not synthetic ones: `_bc_body_from_stdin`
judges a `--data` body by content (`/proc/`, `/dev/(stdin|fd/|.)`, a trailing `-`), so the Supabase SQL payload, the Resend HTML bodies and the mint `scope_body` are each replayed (read-only check on the SQL file: zero matches today).

**D2. A refusal must land in the same verdict class as the old failure, and never in a class that asserts a cause nobody measured.** Default rule (ADR-280 decision 3): a library return of 2 is a curl failure; where the old failure was a red step the
refusal is a red step with the marker visible (no `2>/dev/null` on a converted call). An explicit pre-guard (`bc_ok_var` / `bc_refuse` before the call) is written only where a bare rc 2 would fold into a **different** verdict arm.
The sink table (the review anchor for Guard 2) is in "Census and per-site contract". The load-bearing rows:

- `scheduled-inngest-health.yml` `probe`: pre-guard (HMAC key shape, both Cloudflare Access values) before the `for attempt` loop; a refusal records `secret_unset`, which routes to the liveness-probe issue class with no restart.
  Phase 0 re-verifies that routing in the live file (the S3 plan asserted it; the S3 suite did not execute it). The `probe` step keeps its `set -uo pipefail` shape and `CODE=$(... || echo "000")` fallback.
- `apply-deploy-pipeline-fix.yml` `webhook_liveness`: today `401|403` -> `listener_state=probe_error` (our credential), anything else -> `down`. A refused credential must reach `probe_error`, so the pre-guard sits next to the
  existing credential-read check and writes `listener_state=probe_error` with an `::error::` naming the refusal.
- `apply-deploy-pipeline-fix.yml` `pre_frame` ("degrades loudly, never blocks"): a refusal records `PRE_STATUS=secret_unavailable` (an existing value, already the "credential unusable" class), not `unreachable`.
- `infra-config-verify.sh`: `HTTP_CODE=000` prints "the webhook LISTENER ITSELF IS DOWN ... do NOT re-run with allow_missing_status_endpoint". A refused credential must not produce that sentence. A pre-guard before the poll prints its own
  `::error::` ("credential unusable, says nothing about the listener") and exits 1.
- `apply-inngest-rls.yml`: the four calls all carry `2>/dev/null` (the marker would be invisible). A bare refusal would surface as `identity_unreachable` ("HTTP  for ref ..."). A pre-guard records `secret_unset` with a
  detail naming the shape guard (existing vocabulary; the tracking-issue step is unchanged), and `2>/dev/null` is dropped from the converted calls.
- Poll loops (`restart-inngest-server`, `deploy-inngest-image`, `web-platform-release` verify): **no pre-guard** (plan review cut them: the verdict is the old terminal red either way, the only gain was one marker instead of one per attempt). The marker repeats per attempt and stays visible. `infra-config-verify.sh` is the exception because its 000 arm asserts a cause (above).
- `track.sh`: reuse the existing `redeploy_credential_absent` verdict and exit 2 for an unusable credential (no new verdict vocabulary; Phase 0 greps every consumer of `verdict=redeploy_*`).
- rc 2 collides with curl's own exit 2: no converted site branches on `rc == 2`; the marker is the discriminator.

**D3. Library where the job has a checkout and nothing pins the step's tool set; the S2 inline wrapper where a pinned property of the job or its suite rules out sourcing a repo file (the inline-wrapper clause of ADR-280, bounded mechanically by the S2 parity audit).** Holder analysis (two read-only reports, see "Stub holders") found:

| Site | Form | Why |
|---|---|---|
| `restart-inngest-server`, `apply-inngest-rls`, `apply-github-infra`, `apply-deploy-pipeline-fix`, `mint-infra-app-token`, `track.sh`, `push-infra-config.sh`, `github-app-key-status.sh`, the inngest-health `probe` (22 sites) | library | A checkout exists in the job; no suite pins the step against a sourced file. |
| `web-platform-release` `deploy` and `release-outcome`, `deploy-inngest-image` `deploy` (7 sites) | **inline** (D4) | The jobs are checkout-free by documented design. |
| `workspaces-luks-cutover.yml` Hetzner read | **inline** | `workspaces-luks-cutover-workflow.test.sh` B3 census (`RUNNER_SCRIPT`) forbids any repo script executed on the runner in the token-holding step; a line-leading `source scripts/lib/...` is red and weakening the census to admit it is a worse trade than one inline `printf` wrapper. |
| `infra-config-verify.sh` | **inline** | `infra-config-verify.test.sh`'s actuation sweep pins the script to a read-only allowlist (`source` only of `./infra-config-gate.sh`); its mutation harness builds a skeleton with no `scripts/lib`. Inline needs `python3` added to `ALLOWED`, not a library into a read-only proof. |
| `verify-tunnel-ingress-origin.sh` | inline (already) | Only the `HMAC=` line changes, to the S2 canonical python3 snippet. |

Seven new inline HMAC copies (`web-platform-release` 3, `deploy-inngest-image` 2, `infra-config-verify.sh` 1, `verify-tunnel-ingress-origin.sh` 1) join the S2 parity audit (`hm_audit`: copies 17 -> 24, held-back unchanged at 2), each pinned byte-equal to the canonical snippet; that audit is the mechanical bound on the inline-wrapper exception.

**D4. Checkout-free production jobs stay checkout-free and take the inline wrapper (default; User-Challenge).** `web-platform-release` `deploy` and `release-outcome`, and `deploy-inngest-image` `deploy`, have no checkout by documented design: the comments in the file (about the lock-holding runner and the silent-alert composite), ADR-072 and ADR-217, and
`workflow-run-deploy-invariants` (G3 bars a bare `github.sha`, G13 puts a `superseded` condition on any step after the ordering guard) pin that area. Four review seats (architecture, DHH, CTO and simplicity) read the sparse-checkout alternative as the higher-blast-radius change for the lock-holding deploy job, so the default is the S2 inline wrapper: a step-local shape guard and
`curl --disable --noproxy '*' ... --config -` fed by a process substitution, with the HMAC from the canonical python3 snippet (the Resend steps have no HMAC). Each of the seven sites carries the guard copy; the parity audit pins the HMAC snippet and a battery row pins the guard function's text to `_bearer_ok` byte for byte.
Accepted residual: seven more inline guard copies (the 68-copy problem ADR-280 names), bounded by the parity audit.
**Alternative recorded for the lead:** a one-file sparse checkout (`actions/checkout` pinned, `persist-credentials: false`, `sparse-checkout: scripts/lib/bearer-curl.sh`, `sparse-checkout-cone-mode: false`, the shape `codeql-main-alert-gate.yml` uses and the lint accepts) as an unconditional first step **before** the ordering guard (no `ref:`, no differing `if:`), then the library. Its costs: a checkout outage fails the deploy job at step 0 even for a run that would have exited as `superseded`,
and a `release-outcome` checkout failure suppresses that job's operator email (its Sentry event is independent).

**D5. HMAC keys move with the headers on the same call.** `bc_hmac_sha256_hex KEY < body` replaces `openssl dgst -sha256 -hmac "$KEY"` at every library site, always as `SIG="$(... )" || SIG=""` so an empty key or missing python3 reaches the
call's shape check and the marker instead of aborting mute under `set -e` (the 2026-10-08 learning). `push-infra-config.sh` signs the payload **file**: `HMAC=$(bc_hmac_sha256_hex WEBHOOK_SECRET < "$PAYLOAD_FILE") || HMAC=""`.

**D6. Rule A and D come with the touch.** `push-infra-config.sh` and `infra-config-verify.sh` are in baselines A (no xtrace refusal) and D (curl confinement), and CI runs the lint with `--changed --base origin/main`, which bypasses baselines: editing them requires full A to E remediation
in the same change (xtrace refusal first after `set`, confinement via the library or the inline wrapper). The A baseline also carries a **stale** row for `verify-tunnel-ingress-origin.sh` (it is clean by explicit path); S4 drops it with the file's rewrite.

**D7. The token on a git push moves from the URL to an environment-scoped header.** `bump-inngest-bootstrap-pin.sh` builds `https://x-access-token:${GH_TOKEN}@github.com/<repo>.git` and passes it to `git ls-remote` and `git push`, so the token
is on `git`'s and `git-remote-https`'s argv. Replace with the remote `https://github.com/<repo>.git` and a per-command environment prefix on those two git calls only:
`GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.https://github.com/.extraheader GIT_CONFIG_VALUE_0="Authorization: basic <base64 of x-access-token:TOKEN>"` (the form `actions/checkout` uses; git 2.31+; Phase 0 measures it on the runner image, where git is 2.43, against a **local HTTP git server that records the `Authorization` header** (value-free compare), not only a bare file remote, and checks that the header is scoped to `https://github.com/` and not re-sent to a redirect target; `BUMP_PUSH_URL` skips the header entirely, so the real path has no suite proof and the first live run of `build-inngest-bootstrap-image` is tracked by the follow-through).
The token passes a shape guard (`[A-Za-z0-9_]`, the `ghs_` class) before the header is built, refusing with the same marker (`script=bump-inngest-bootstrap-pin`). `BUMP_PUSH_URL` (fixture seam, a bare repo) keeps its current path and gets no header.
The suite's `g2.script:token-from-env` row greps the old URL and is rewritten; `g1.gittrace` (GIT_TRACE/GIT_CURL_VERBOSE output holds no token) stays and gains the header form.

**D8. Held-back S3 sites.** (a) `scheduled-inngest-health.yml` `probe`: library form (the same job's later census step already sources it); the infra suite `inngest-dedicated-host-classify.test.sh` gets one `mkdir -p`/`cp` line putting `scripts/lib/bearer-curl.sh` beside the classifier it already copies
into `$PROBE_WS`, no assertion count moves (floor 134 stays); its stub curl ignores unknown flags and its stub openssl becomes unused. Edit placed so the `source` is inside the `if [[ -z "$fail_mode" ]]` arm **and** a missing library is a visible `::error::` (a top-level `source` would also redden the
three "secrets unset" rows). (b) `workspaces-luks-cutover.yml`: inline wrapper (D3) plus two arms in the suite's curl stub (`--disable) shift`, `--noproxy) shift 2`); its `--config` arm already reads stdin into `$CURL_CFG`. Measured by the holder report: 5 rows plus the 107-assertion floor red before the stub edit.
The step keeps `HCLOUD_TOKEN_READONLY` first with the read/write fallback until ADR-241 O10 (unchanged semantics; the inline guard judges whichever value was read).

**D9. Population-derived guards, not counts.** The sweep battery gains a stage S4 whose population is derived from the tree: every tracked non-test, non-doc file with an `openssl dgst ... -hmac` operand must be in an explicit allow-list of exactly the held-back set (Guard 1), the S3 stage's `S3_MANIFEST`
and `S3_HELD_BACK` expectations are updated 1:1 (the inngest-health file now leaves its held-back state), and `scripts/lint-workflow-local-action-checkout.py` learns that a `run:` naming a script that itself sources the library is a library consumer (Guard 3; `track.sh` is invoked by `run:`, the lint's documented blind spot).

**D10. Not in S4 (each with its owner).** #9757 item 1 (the two held-back HMAC arms of `scripts/cutover-inngest.sh`): converting them needs the census regexes in `cutover-inngest-workflow.test.sh` edited, which is in #9877's diff and the brief's S4 list does not name them (stays on #9757; owner after #9877 merges).
#9757 item 2 (heartbeat-URL path secrets in `inngest-bootstrap.sh`, `web-git-data-probe.sh`, `luks-monitor.sh`): not in the S4 list. #9755 (`op=backup` environment gate; edits `cutover-inngest.yml`, also in #9877's diff) and #9756 (two cla-evidence `--user` sites): own issues. #9757 items (d) (agent-executed Markdown teaching the argv HMAC form in `ship/SKILL.md`
and `postmerge/references/deploy-status-debugging.md`): plugin files, which would add a plugin release run and the skill-body budget gates to an already heavy merge. All of these stay tracked; the S4 tracker comment restates the owner of each with a **re-evaluation date of 2026-10-23** (two weeks; the cutover arms are taken then if #9877 has merged, otherwise re-dated on the issue). Past exposure has its visible owner in #9294 (move `WEBHOOK_DEPLOY_SECRET` and the CF Access pair out of branch-nameable storage, then rotate; ADR-241 D10 G1/O13): S4 reduces argv exposure and does not rotate.

**D11. ADR-280 is amended, not superseded.** Status stays `adopting`. The amendment records: the held-back sites closed; the inline-wrapper exceptions and their reasons (D3); the inline-wrapper clause (D3, D4: allowed only where a pinned property of the job or suite rules out sourcing a repo file, bounded by the parity audit); the HMAC-key movement now covering 20 production sites; the git-credential-by-environment form (D7).
The amendment also cites ADR-280 decision 3's own sentence that the restart-mapping pre-guard of the held-back `probe` step is an S4 obligation (delivered by D2), and notes that under `workflow_run` the sourced library is the default branch's head and can be newer than the deployed SHA. No ADR-241 change: S4 names no new `secrets.*` in any job and changes no tier classification.

**D12. Commits are separable by blast radius** (Phases): (1) lint and battery scaffolding; (2) composites and `track.sh`; (3) dispatch-only and self-fire workflows; (4) `apply-deploy-pipeline-fix.yml`; (5) `web-platform-release.yml`; (6) infra scripts and their two suites; (7) held-back sites and their suites;
(8) `bump-inngest-bootstrap-pin.sh`; (9) battery completion, lint docstring, ADR amendment; (10) baseline-only commit last, after the merge-from-main commit exists. Commits 6 and 7 are the infra-path commits; reverting either leaves 1 to 5 coherent.

## Research Reconciliation: brief and tracker text vs. codebase

| Brief / tracker claim | Reality (`origin/main` `5485dffdaf`, measured 2026-10-09) | Plan response |
|---|---|---|
| S4 lists `ci-deploy.sh (python3-on-host row)` | Done in #9805 (`8729cc0dfa`): `fan_out_to_peers` signs with `HMAC_KEY="$secret" python3 -I -c ...` and refuses an unsigned forward; Rule E on the file reports `0 site(s)`. The only `-hmac` text left is in `ci-deploy.test.sh`. | Dropped from S4. No edit to `ci-deploy.sh` (it is also a `deploy_pipeline_fix` trigger file). |
| 14 S4 entries | 13 baseline-E files (31 sites) + `verify-tunnel-ingress-origin.sh` (1 HMAC site, not in the baseline) + `bump-inngest-bootstrap-pin.sh` (token URL, not seen by the lint) = **15 files**. Both held-back files are among the 13. | Census below. |
| Tracker: `apply-web-platform-infra.yml` "6 sites" | Baseline E says 5; the ceiling table says 6. | S5's; recorded, not touched. |
| Tracker unchecked boxes for S2 and S3 | Both merged (#9753 `d0707d3fa3`, #9811 `ca5295d712`). | The S4 tracker comment ticks S2, S3 and (after merge) S4. |
| "The push-triggered infra apply did not fire after the Tier 2 merge; the next qualifying push is the check" | It has fired since, repeatedly: `apply-web-platform-infra` succeeded on pushes `5485dffdaf`, `d7dfd05aac`, `48d5144cf4`, `aa4221a32e`, `87eaaf18e1` (all 2026-10-09); `apply-deploy-pipeline-fix` succeeded on `5e75548373` and `8729cc0dfa`, with two superseded runs `cancelled` by concurrency. | Open item closed by evidence; S4's merge is one more data point, and a **cancelled** run is recorded as not-a-pass. |
| "web-2 still carries pre-Tier-2 monitors until its next recreation" | The #9597 comment of 2026-10-08 says web-2 was rebuilt after the Tier 2 merge and treated as resolved; on-host content cannot be read without SSH. | Stated as a residual in the PR; not checked (SSH-free reads cannot see it). |
| "`.mcp.json` in the MAIN checkout was reported modified" | `git diff HEAD -- .mcp.json` in the main checkout prints nothing now. | Never touched. |
| "#9872 earliest check 2026-10-16; #9875 holds seven S3 default choices" | Both open (read). | Not S4's; S4's own follow-through and decision-challenge are separate (Phase 10). |
| "First content-publisher Bluesky/X run and the 08:00Z community-monitor row unchecked" | The two scheduled GitHub workflows last ran in May; these crons now run as hosted Inngest functions, so the check is a Better Stack read. | One read-only marker count over the window since the S2 merge rides the S4 post-merge query (post-merge table, row 6). |
| Rule E baseline "17 files / 42 sites" | Confirmed by `--census` (`offenders_e=17`) and by explicit-path lint runs: the 13 S4 files report 31 E sites (35 findings with A and D on two files). | S4 target 4 / 11. |
| "`scripts/lib/bearer-curl.sh` (70 rows), lint suite 99, battery 468" | Counts quoted from the brief; Phase 0 re-runs each suite and records its own number. | Floors set to realized counts only. |
| Brief: "run the repo-wide transport-stub grep over the whole repo" | Done: the vocabulary `-u)`, `--user`, `Authorization`, `x-api-key` matches **239** test-ish files (181 shell suites); **69** of those define a curl stub (function, shim, or `exit 64`), **30** under `apps/web-platform/infra/`. Cross-referenced with the S4 file names and distinctive step strings by two read-only reports. | "Stub holders". |

## Stub holders (the whole-repo transport grep for S4's vocabulary)

Method: `git grep -l -E -- '(-u\)|--user|Authorization|x-api-key)'` over `*.test.sh`, `tests/**`, `.github/scripts/test/**`, `.github/actions/**/*.test.sh`, `plugins/**/test/**`, `apps/**/test*`; stub definitions found with
`curl\(\)|shim/curl|/curl <<|bin/curl|exit 64|UNMODELLED`; then every hit whose text names an S4 file or a distinctive step string was read. Two read-only reports (workflow side, script side) classified each holder as EXECUTES / GREPS-TEXT / PINS-STRUCTURE / PATH-ONLY.
They ran no suite; every red count below is **derived by reading** and Phase 0 re-measures each on a scratch conversion (S3 did, and the numbers moved).

| Holder | Class | Verdict after conversion | Edit | Under `infra/**`? |
|---|---|---|---|---|
| `scripts/lint-shell-trace-credential-refusal-e.baseline.txt`, `scripts/fixtures/shell-trace-refusal/rule-e-census-ceiling.tsv` | PINS (equality, both directions) | RED until 13 rows leave both | baseline-only commit (Phase 10) | no |
| `scripts/lint-shell-trace-credential-refusal-d.baseline.txt`, `...refusal.baseline.txt` (A) | PINS (enumerated lists) | stale rows for the two remediated scripts (+ the stale verify-tunnel row) | drop rows | no |
| `tests/scripts/test-argv-bearer-sweep.sh` S3 stage (`S3_MANIFEST`, `S3_HELD_BACK`, the held-back `-hmac` grep, the held-back Rule E count) | GREPS / PINS | RED: 7 new library users are "unclassified"; the held-back expectation flips; stage 3 `VT_STUBS` has no `python3` so 2 of 7 verify-tunnel rows go red | S4 stage; `ln -s python3` into `VT_STUBS`; `scripts/lib/test-affected-paths.sh` edge | no |
| `tests/scripts/test-dispatch-web-redeploy.sh` | EXECUTES `track.sh` | row P2 (reads `-H X-Signature-256` from the recorded argv) RED; others green | read the signature from recorded stdin; library found by `BASH_SOURCE` (suite runs `env -i`, no `GITHUB_WORKSPACE`) | no |
| `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh` ("Composite" block) | EXECUTES the mint composite | anchor `INSTALL_RESP=$(curl -sS --max-time 30 -X POST \` RED; `run_comp` sets no `GITHUB_WORKSPACE` | update anchor, pass `GITHUB_WORKSPACE="$REPO_ROOT"` | no |
| `scripts/lint-workflow-step-env-refs.test.sh` Part B | EXECUTES `release-outcome` `id: email` under `env -i` | RED: `${GITHUB_WORKSPACE:?}` aborts every arm | add `GITHUB_WORKSPACE` to `envargs` and the mirror arm; a new step env key needs a value in `env_value_for` | no |
| `scripts/lint-workflow-local-action-checkout.py` (+ `.test.sh`) | PINS (third surface) | the new library users need an earlier usable checkout (every one of the 22 library sites has one) | Guard 3 extension | no |
| `apps/web-platform/infra/infra-config-verify.test.sh` | EXECUTES the real script under a curl stub that requires an **argv** `X-Signature-256:` element | RED: about 23 `#7104 I*` rows; actuation sweep `ALLOWED` lacks `python3` | teach the stub `--disable`, `--noproxy`, `--config -` and stdin headers; add `python3` to `ALLOWED` and its control copy | **yes** |
| `apps/web-platform/infra/infra-config-repush-mutation.test.sh` | EXECUTES + literal `sub()` mutations | RED: mutation S3 anchors on `X-Signature-256: sha256=${HMAC}` | re-anchor S3 on the new `printf` literal | **yes** |
| `apps/web-platform/infra/workspaces-luks-cutover-workflow.test.sh` | EXECUTES the step under a stub that `exit 64`s unmodelled flags; B3 census | RED: 5 rows + the 107-assertion floor; the census also forbids a library `source` | two stub arms; inline wrapper (D3) | **yes** |
| `apps/web-platform/infra/inngest-dedicated-host-classify.test.sh` rows (g) | EXECUTES the `probe` step in `$PROBE_WS` (no `scripts/lib`) | RED 15 to 18 of 18 executed asserts with a library `source` | one `mkdir -p`/`cp` line; floor 134 unchanged | **yes** |
| `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` | EXECUTES (real git, bare remote via `BUMP_PUSH_URL`) + GREPS | `g2.script:token-from-env` (greps `x-access-token:\$\{?GH_TOKEN`) RED | rewrite row; keep `g1.gittrace` | no |
| `apps/web-platform/infra/push-infra-config` readers (`infra-config-apply.test.sh`, `inngest.test.sh`, `cutover-inngest-workflow.test.sh` greps) | GREPS-TEXT | GREEN unless the edit adds `"x_b64":` strings or touches flip-trio names | none; no suite executes the script | n/a |
| `restart-inngest-workflow-guard.test.sh`, `ci-deploy.test.sh` (`MAX_POLLS=`, `POLL_INTERVAL=`), `web-hosts-fanout-parity.test.sh`, `web-1-swap-concurrency-parity.test.sh`, `workflow-run-deploy-invariants.test.sh`, `ship-deploy-pipeline-fix-gate.test.ts`, `deploy-arm.sh` (step name "Deploy via webhook") | PINS-STRUCTURE / GREPS | GREEN if step names, job set, `MAX_POLLS`/`POLL_INTERVAL` single lines and the two `web-1-swap` groups are untouched | constraints recorded for Phases 3 to 5 | some |
| `apply-inngest-rls-workflow.test.sh` | PINS (parsed YAML: `/v1/projects/`, `identity_mismatch`, gate substrings, floor 17) | GREEN | none | yes (unedited) |
| `apps/web-platform/test/resend-sender-domain.test.ts` | GREPS (`api.resend.com/emails`, `--arg from`) | GREEN if both literals stay | none | no |

Net: the infra-path edits S4 cannot avoid, beyond the scripts themselves, are **four suites** (`infra-config-verify`, `infra-config-repush-mutation`, `workspaces-luks-cutover-workflow`, `inngest-dedicated-host-classify`). All four are already inside a merge that fires the apply
because of `push-infra-config.sh`, so the held-back sites add no new class of exposure; they add one `mint-inngest-bootstrap-tag` run that decides `noop`.

## Research Insights

**Premise Validation (Phase 0.6).** Cited by reference and read live: #9597 (open; body and all 8 comments read), #7797, #9755, #9756, #9757 (open; bodies read), #9877 (open draft; file list and the `apply-deploy-pipeline-fix.yml` and `scripts/cutover-inngest.sh` patches read),
#9872 and #9875 (open), #9799 (open; item 3 records the `ci-deploy.sh` HMAC as delivered), ADR-241 (proposed; D4 Tier-A `HCLOUD_TOKEN_READONLY`, the O10 eviction, the 2026-10-08 `op=backup` amendment), ADR-280 (adopting; read in full), ADR-072/ADR-217 (the checkout-free deploy job), the archived S3 plan,
spec and the S3 learning. Cited paths verified on `origin/main`: all 15 files exist; `scripts/lib/bearer-curl.sh` exists (241 lines). Mechanism against the ADR corpus: no ADR rejects the git `GIT_CONFIG_*` environment header and none rules on a sparse checkout of one library file (recorded as the alternative); ADR-072's
prohibition is scoped to the git-ancestry guard, not to a checkout. What held: the library, the marker, the Rule E structure, the apply-fire model. What was stale: the `ci-deploy.sh` row, the S2/S3 checkboxes, the "apply did not fire" item, and the assumption that the held-back sites are the only infra-suite edits.

**Property List (Phase 0.6b).**

1. After S4 no S4 file places a credential (header value, webhook signature, Cloudflare Access pair, bearer token, the HMAC key that produces a signature, a git remote's userinfo token) on any process's argument list.
2. A malformed, empty or unset credential makes zero requests, prints one value-free marker, and lands in the verdict class the old failure produced (or the honest existing class where the old class would assert an unmeasured cause: never `down`, never `inngest_down`, never `unreachable`).
3. Every converted request keeps its method, URL, non-credential headers, body and timeouts; the transport change (`--disable --noproxy '*'`, environment hygiene) is the recorded ADR-280 one.
4. The converted files and their suites are exercised on the runner's userland (ubuntu:24.04, bash 5.2, curl 8.5), not only the dev host (bash 5.3, curl 8.22).
5. Production behavior after the merge is observed without SSH: the apply provisioners, the release deploy, the RLS apply and the inngest-health probe all ran on converted code and printed no refusal marker.

**Cut List (Phase 0.6b).** (i) A new Rule E arm for `openssl -hmac` (buys property 1 for the HMAC key; the battery's derived census buys it for the same population at a fraction of the cost and without a new baseline row; recorded, not built). (ii) Per-site fingerprint keying for baseline E
(ADR-280 consequence: S4 and S5 delete the population). (iii) A library change (no call needs one; the replay proves it). (iv) A sparse checkout plus the library in the three checkout-free jobs (D4 alternative; the default is inline). (v) A new `track.sh` verdict word (reuse `redeploy_credential_absent`). (vi) Converting the two held-back cutover arms and the heartbeat URLs
(D10). (vii) A hand-kept hermetic/slice taxonomy in the battery (reuse the derived-population mechanism). (viii) Rewriting the agent-executed Markdown (D10).

**Learnings applied (read, not recalled).** `2026-10-09-a-guard-keyed-on-option-spellings...` (replay every call through the guard on curl 8.5; one row per alternative; delete-each-alternative mutants); `2026-10-08-a-pipe-tail-swapped-for-a-command-substitution-aborts-mute...` (`|| VAR=""`, arm-level rows with the key empty, unset and python3 absent, run on ubuntu:24.04);
`2026-10-09-...no-openssl-flag-reads-an-hmac-key-from-stdin` (the python3 form, byte-identity matrix; do not implement the tracker's "stdin/fd" wording); `2026-10-06-a-refuse-before-send-guard-turned-a-paging-401-into-a-silent-skip` (name the old and new sink per site); `2026-10-06-one-credentialed-curl-was-uneditable-alone...` (grep the exact line across the repo before editing);
`2026-06-02-deploy-pipeline-fix-false-success-202...` (the push path must not map a refusal, a 401/403 or a 404 to pass); `2026-10-09-a-rollback-recipe-nobody-had-run-and-a-baselined-file-touched-without-its-changed-lint` (run the revert recipe in a scratch tree through every gate; run the lint with `--changed --base origin/main` by hand);
`2026-10-05-a-reader-that-exits-early-flipped-three-suites-and-the-stub-had-to-read-too` (stubs drain stdin; credentials via `< <(...)`); `2026-09-18-local-composite-action-needs-checkout...` (a composite needs a prior checkout; `continue-on-error` hides the resolution error); `2026-09-20-the-deploy-arm-that-said-success-had-deployed-someone-elses-commit`
(identify the arm by the commit it deploys, not `head_sha`).

## Hypotheses

The network-outage gate fires on the keyword `SSH` and on the apply's provisioners, but this change addresses **no connectivity symptom**: it moves credentials between transports on calls that already work. The L3 to L7 checklist is therefore recorded as not applicable to diagnosis, with the one place it does bind:
the apply that the merge fires reaches web-1 through the Cloudflare tunnel (HTTPS `/hooks/infra-config`, replacing SSH since #3756) and web-2 through the CF tunnel SSH bridge. If that apply reports `ssh: handshake failed` or `connection reset`, the diagnosis order is firewall allow-list and egress IP first, then DNS and routing, then the tunnel and
Access layer, then the service (`hr-ssh-diagnosis-verify-firewall`), and it is **not** attributed to the credential conversion until `SOLEUR_CREDENTIAL_REFUSED` appears in that run's log (the marker is the discriminator).

## Census and per-site contract

Measured with `python3 scripts/lint-shell-trace-credential-refusal.py <path>` (Rule E) and `git grep -nE 'openssl dgst.*-hmac'`; locate every site by its **anchor** (step name or id), never by line number. "Sink" columns are the review anchor for Guard 2.

| # | File (job) | Step / anchor | E sites | `-hmac` | Form | Old failure of a bad credential | Refusal sink (new) |
|---|---|---|---|---|---|---|---|
| 1 | `restart-inngest-server.yml` (restart) | Trigger restart via webhook | 1 | 1 | library | HTTP 4xx -> `::error::Restart webhook rejected`, exit 1 | rc 2 aborts under `set -e`: red, marker visible |
| 2 | same | Verify restart completion (poll, final STATE re-read, liveness) | 3 | 2 | library | non-JSON body retried 120 times, red at the 600 s budget | same retry loop, marker per attempt, same terminal red |
| 3 | `deploy-inngest-image.yml` (deploy) | Trigger deploy via webhook / Verify deploy completion | 2 | 2 | **inline** (D4) | as rows 1 and 2 | as rows 1 and 2 |
| 4 | `apply-inngest-rls.yml` (apply) | Apply lockdown + authoritative verification: identity GET, POST (retry loop), `query()` helper, advisor | 4 | 0 | library (checkout exists) + pre-guard | 401 -> `identity_unreachable` | pre-guard: `secret_unset` (existing), no request; `2>/dev/null` dropped |
| 5 | `apply-github-infra.yml` (apply) | Revoke the soleur-infra token | 1 | 0 | library | best-effort `::warning:: ... HTTP 000` | same warning, marker visible (`2>/dev/null` dropped) |
| 6 | `mint-infra-app-token/action.yml` | Mint installation token: JWT exchange, `revoke()` | 2 | 0 | library (callers: 3 workflows, each with a step-0 checkout) | `::error:: ... curl rc=...` exit 1; revoke best-effort | exchange: same error (message gains the refusal hint), exit 1; revoke: stays best-effort, `2>&1` dropped |
| 7 | `dispatch-web-redeploy/track.sh` | GET status, POST dispatch | 2 | 2 | library (found by `BASH_SOURCE`) | HTTP != 200/202 -> `verdict=redeploy_*`, exit 1 | unusable credential -> `redeploy_credential_absent`, exit 2 (existing verdict) |
| 8 | `web-platform-release.yml` (deploy) | Pre-rerun lock probe | 1 | 1 | **inline** | degraded-permissive: proceed | same: proceed, marker visible |
| 9 | same | Deploy via webhook | 1 | 1 | **inline** | HTTP != 202 -> `::error::Deploy webhook rejected`, exit 1 | rc 2 abort: red before any request; prod stays on the previous build |
| 10 | same | Verify deploy script completion (poll) | 1 | 1 | **inline** | retried, then the poll-budget red | same loop, marker per attempt, same terminal red |
| 11 | same | Email notification (deploy FAILED) | 1 | 0 | **inline** | `::error::Deploy-failure email FAILED (HTTP 000)` (non-fatal) | same line, marker visible |
| 12 | same (release-outcome) | `id: email` Email the operator | 1 | 0 | **inline** | same as row 11 | same as row 11 |
| 13 | `apply-deploy-pipeline-fix.yml` (apply) | Capture pre-apply infra-config frame (`pre_frame`) | 1 | 1 | library | "never blocks"; HTTP != 200/404 -> `unreachable` | pre-guard: `PRE_STATUS=secret_unavailable`, step still exits 0 |
| 14 | same | Verify webhook is alive post-apply | 1 | 1 | library | `::error::Webhook did not respond with HTTP 200`, exit 1 | `HTTP_CODE=000` arm: same red, marker visible |
| 15 | same | Verify webhook is alive post-re-push (`webhook_liveness`, CF pair only) | 1 | 0 | library + pre-guard | 401/403 -> `listener_state=probe_error`; other -> `down` | pre-guard: `probe_error`, never `down` |
| 16 | same | Redeploy to load applied profile (`get_status()`, POST) | 2 | 2 | library | POST != 202 -> red | red, marker visible |
| 17 | same | Verify journald_storage no-SSH surface is live | 1 | 1 | library | retried, then `::error::`, exit 1 | red, marker visible |
| 18 | `scheduled-inngest-health.yml` (probe) | `id: probe` | 1 | 1 | library + pre-guard | 000/403 without sentinel -> `probe_unavailable`, no restart | pre-guard: `secret_unset`, no restart, no request |
| 19 | `workspaces-luks-cutover.yml` (cutover) | Run workspaces-luks cutover: Hetzner volumes GET | 1 | 0 | **inline** | `curl -f` fails -> `set -e` abort before any write | same abort; marker line printed by the inline guard |
| 20 | `push-infra-config.sh` | POST `/hooks/infra-config` | 1 | 1 | library (found by `BASH_SOURCE`) | non-zero exit; provisioner fails | rc 2 under `set -euo pipefail`: non-zero exit + marker |
| 21 | `infra-config-verify.sh` | status poll | 1 | 1 | **inline** + pre-guard | 000 -> "listener DOWN" message | own `::error::` ("credential unusable, says nothing about the listener"), exit 1 |
| 22 | `github-app-key-status.sh` | GET deploy-status | 1 | 1 | library | exit 6 ("deploy-status read failed") | `curl_rc=2` reaches the existing exit-6 arm with the marker visible (no new exit code; an operator-run diagnostic, no CI caller) |
| 23 | `verify-tunnel-ingress-origin.sh` | HMAC line only (curl already converted) | 0 | 1 | inline (S2 canonical snippet) | `_cfg_ok` refuses -> exit 1 | unchanged; `|| HMAC=""` reaches `_cfg_ok` |
| 24 | `bump-inngest-bootstrap-pin.sh` | `git ls-remote` / `git push` remote | 0 | 0 | env header (D7) | `die push` | `die args` + marker before any git network call |

Totals: E sites 31 (rows 1 to 22, 13 files), `-hmac` sites 20 (rows 1 to 23), plus the git remote (row 24). `ci-deploy.sh` is absent by design.

## User-Brand Impact

**If this lands broken, the user experiences:** a production deploy that does not happen or is mis-reported (the converted `web-platform-release` deploy job fails at its first step and prod stays on the previous build, with an operator email; or a mapping error makes the post-re-push probe report a bricked
remediation channel that is fine, or hides one that is not), an infra apply that fails at its provisioner and leaves the deploy pipeline on stale files (the `deploy_pipeline_fix` push is the only no-SSH remediation channel), the Inngest RLS self-heal silently not verifying the lockdown on the brand-survival database, the inngest health watchdog filing a false alarm
or, if a credential fault were mapped to `inngest_down`, restarting a healthy server, or the data-destructive LUKS cutover aborting at its precondition (a loud abort, never a silent pass). All are loud and revertible; none rewrites user data on its own. The one data-destructive path in the set, the LUKS cutover (`luksFormat` on a volume device), is protected by the converted read being its precondition: a refusal aborts under `set -e` **before** any write, and the battery row for that site asserts the abort happens with zero Hetzner writes recorded.

**If this leaks, the user's data is exposed via:** the failure the sweep removes: a deploy-webhook key plus Cloudflare Access pair, a Supabase management token for the Inngest project, a GitHub App installation token with `administration:write`, a Hetzner token and a Resend key readable in `/proc/<pid>/cmdline` and `ps` by any other process in the same job
(on hosted runners that means a compromised third-party action or dependency step; the apply runs inside the privileged `infra-privileged` environment). The webhook key can rewrite the production host and read its credential file (ADR-241 D1 amendment). New ways this change could add exposure and how each is closed: a credential echoed by a new diagnostic (the marker and the
`bc_curl: <VAR> unusable` line carry no value; a negative canary row searches every captured stream), a key written to a temp file (none: keys ride a child's environment), tracing left on while a credential binds (each library function refuses at rc 78; the two inline scripts and the git header carry their own xtrace refusal), the library sourced into a privileged step from a tampered workspace
(same trust as the script files those jobs already run from the same checkout; the closure lint requires the checkout and bars `pull_request_target`). Residual after S4: the key and tokens live in a child's environment (same-uid and root can read `/proc/<pid>/environ`), a reduction from world-readable `cmdline`, not elimination; the two held-back cutover HMAC arms, the heartbeat-URL path secrets and the
agent-executed Markdown stay on argv (D10); **past exposure is not remediated here**: rotation stays with ADR-241 O13.

- **Brand-survival threshold:** single-user incident

CPO sign-off is required at plan time (`requires_cpo_signoff: true`); the assessment is recorded under "Domain Review". `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-280** (status stays `adopting`) via `soleur:architecture` in Phase 9, as a plan task: add an amendment-log entry for S4 and extend the Consequences list with D3 (inline-wrapper exceptions: a suite that pins the step's tool set), D4 (sparse checkout for checkout-free jobs; the lint's accepted shape),
D5 (HMAC keys: 20 production sites now off argv, the allow-list of what remains), D7 (environment-scoped git header), and the closed hold-back. The alternatives table gains: "inline wrapper at checkout-free sites" (rejected as the default, kept as the recorded alternative). No new ADR: the decision is the same
contract applied to a new population, and the ordinal ladder is not touched. ADR-241 is not amended (no new `secrets.*` reference, no tier change; the `workspaces-luks-cutover` read keeps its `HCLOUD_TOKEN_READONLY`-first order).

### C4 views

No C4 impact. All three model files were read (`model.c4` 942 lines, `views.c4`, `spec.c4`). The actors and systems the converted calls touch are all modeled with their edges: GitHub (Actions runners and the Apps API), Hetzner Cloud, Cloudflare (tunnel and Access), Doppler, Supabase (the Inngest project), Resend, the Inngest server container and the deploy webhook behind the tunnel.
No external human actor, system, data store or actor-to-surface relationship changes: only the argv encoding of existing edges. `bash plugins/soleur/test/c4-count-parity.test.sh` was run on this branch: `ALL TESTS PASSED`. S4 adds no workflow and no monitor, so no embedded count moves (re-run in Phase 10).

### Sequencing

None. The amendment describes the state this PR ships.

## Scope Check

### Ask Mapping

| # | User ask (verbatim, from the brief) | Plan item | Status |
|---|---|---|---|
| 1 | "Do ONE slice per PR, starting with S4 and stopping there." | Whole plan; no S5 item | mapped |
| 2 | "The tracker's 'Remaining slices' section is the scope source of truth; re-derive every count" | Research Reconciliation, Census | mapped |
| 3 | S4 file list (restart-inngest-server ... bump-inngest-bootstrap-pin.sh) | Census rows 1 to 24 (`ci-deploy.sh` closed by #9805, with evidence) | mapped |
| 4 | "Plus the two sites S3 deliberately held back" | D8, rows 18 and 19, Phase 7 | mapped |
| 5 | "stop and get explicit operator notice before ship ... verify the apply outcome afterwards" | MERGE EFFECTS, Phase 11, post-merge table | mapped |
| 6 | "A production-apply dispatch needs explicit operator approval each time." | Phase 11 and the post-merge table (no dispatch is planned; a cancelled apply needs a fresh approval) | mapped |
| 7 | "read #9755, #9756, #9757, ADR-241 and ADR-280" | Research Insights, D10 | mapped |
| 8 | "run the repo-wide transport-stub grep over the WHOLE repo before planning" | Stub holders | mapped |
| 9 | Pipeline order, merge-queue rules, `deploy-arm.sh find --wait`, served from a detached worktree | Phase 11 and post-merge table | mapped |
| 10 | "The PR carries Ref #9597 and Ref #7797; only S5 carries Closes #9597" | Phase 10 | mapped |
| 11 | Binding lessons 1 to 8 | 1 Phase 8; 2 Guards; 3 Phase 0 replay; 4 Phase 9 gate list; 5 Phase 10; 6 Phase 11 (review); 7 Phase 10; 8 Phase 0 | mapped |
| 12 | "Collision note ... #9877 ... plan the merge-conflict handling" | MERGE EFFECTS (Collision) | mapped |
| 13 | "Open items to check, not assume" | Research Reconciliation rows; Phase 0 | mapped |
| 14 | "Mandatory post-merge check ... soleur:trigger-cron ... SOLEUR_CREDENTIAL_REFUSED = 0" | post-merge row 5 (applicability decided with evidence) | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|---|---|---|
| The 13 baseline files, the two held-back sites | S4 list in the brief and tracker | asked |
| `verify-tunnel-ingress-origin.sh`, `bump-inngest-bootstrap-pin.sh` | named in the tracker's S4 entry | asked |
| `openssl -hmac` keys on the same calls (20 sites) | "(second call signs with `openssl -hmac`)", "its `openssl -hmac` key, signature and Cloudflare Access pair" | asked for two sites; **inferred** for the rest: the key is on openssl's argv on the very call whose header is converted, so a header-only conversion is half a fix |
| Inline wrappers in three checkout-free jobs (D4) | - | inferred: dependency of the jobs' documented checkout-free design and ADR-280 decision 4 (sourced only from the job's own checkout) |
| Inline wrappers at two sites (D3) | - | inferred: dependency of the pinned suites (census, actuation sweep) |
| Guard 1 (HMAC census), Guard 3 (lint extension) | "a battery row that goes red for each rule" (lesson 2) | inferred: enforcement contract |
| Pre-guards with honest verdict classes (D2) | "a restart pre-guard that must map a credential fault to secret_unset, never inngest_down" | asked for the probe; **inferred** for `webhook_liveness`, `pre_frame` and `infra-config-verify.sh`, which carry the same defect class |
| Rule A and D remediation, baseline A/D rows (D6) | - | inferred: `--changed` CI lint requires it |
| Battery S3-stage edits, `scripts/lib/test-affected-paths.sh` edge | - | inferred: dependency (the S3 manifest and held-back expectations are derived from the tree) |
| ADR-280 amendment (D11) | - | inferred: enforcement contract (`wg-architecture-decision-is-a-plan-deliverable`) |
| Follow-through enrollment and the decision-challenge issue | "Declare Filed: #N ..." (lesson 5) | inferred: the PR body contract |

### Split Assessment

- Subsystems touched: 6 (`.github`, `apps/web-platform`, `scripts`, `tests`, `knowledge-base`, and the lint/baseline files) | Planned files: about 38 | Estimated changed lines: about 1,600 (workflows and actions 450, scripts 250, four infra suites 120, battery stage 500, lint extension and docstring 120, docs and ADR 160).
- Thresholds: >= 4 roots OR > 25 files OR > 800 lines: all exceeded.
- Recommendation: **single PR**, per the brief and the tracker (one slice per PR). The library, the battery and the sites are only meaningfully testable together, and the commit layering (D12) isolates the infra-path commits (6, 7) from the rest. The pre-agreed seam if CI shows two red cycles from the battery rows: land the battery
  stage as a separate commit series on the same PR, never a second slice. If the lead prefers to separate the apply exposure, the seam is commits 6 and 7 (which carry every file the apply keys on) moving to a follow-on PR; commits 1 to 5 and 8 fire only the web release and the RLS self-apply.

## Guard Contract

### Guard 1 — No production file puts an HMAC key or a credential header on an argument list (population derived from the tree)

**Property.** After S4, every tracked non-test, non-documentation file that signs with `openssl dgst ... -hmac <key>` is in an explicit allow-list of exactly the held-back set, and every S4 file places no credential header on curl's or openssl's argv; a new argv HMAC site or a re-added header in a converted file turns a row red.
**Assembly.** (a) Rule E (existing; the lint decides what an argv header is, equality baseline); (b) a battery census derived by `git grep -nE 'dgst .*-hmac'` over tracked files minus Markdown, `*.test.sh`, `tests/`, fixtures, `knowledge-base/`, comment-only lines and the lint's own docstring, compared by set identity (not count) to the allow-list
{`scripts/cutover-inngest.sh` x2 (registry-probe, doublefire-probe arms), `plugins/soleur/skills/ship/SKILL.md` and `.../postmerge/references/deploy-status-debugging.md` as documentation exceptions asserted separately}; (c) the S4 population of library users derived from steps and scripts that name `scripts/lib/bearer-curl.sh`, each judged structurally (library sourced in the step itself before its first `bc_*` call;
no credential header literal inside a `bc_curl` statement; no `2>/dev/null` on one; no branch on `rc == 2`; the marker name equals the file's basename); (d) the two inline scripts judged by the S2 parity audit (canonical snippet byte-equal, copies 17 -> 19, held-back 2).
**Mutation matrix.**

| # | Mutation (scratch copy; assert it landed with `diff -q`; run an unmutated control first) | Must go RED |
|---|---|---|
| 1 | restore `openssl dgst -sha256 -hmac "$WEBHOOK_SECRET"` in one converted workflow step | the derived HMAC census (set identity) and the structural D4 predicate |
| 2 | add a **second** argv HMAC after a compliant first in the same file (the second-member case) | the census compares sets by file and line count, not "at least one clean" |
| 3 | re-add `-H "X-Signature-256: ..."` to one converted `bc_curl` tail | the D2 predicate row and Rule E (explicit path) |
| 4 | empty the derived population (rename the library path in the grep) | the population floor (`-lt` literal, "anti-vacuity floor" wording per `guard-vacuity-floor.test.sh`) |
| 5 | add an unlisted production file with an argv HMAC | census: unclassified member |
| 6 | delete one allow-list row while the file still has the HMAC | census: unclassified member (the held-back set cannot shrink silently) |
| 7 | make the canonical snippet in one inline copy differ by one byte | parity audit |

**Harness rows.** (a) the census runs against a synthesized tree whose only HMAC is allowed (must-PASS, not the canonical repo) and against one with an extra member (must-FAIL); (b) the recording curl shim ignoring `--config -` makes the "credential reaches stdin" row red; (c) must-PASS realistic shapes: a 64-hex signature, a `<hex>.access` Cloudflare id, a Supabase `sbp_` token, a JWT with dots, a `ghs_` token, a Hetzner token, a Resend `re_` key;
(d) a negative canary: a distinctive fake credential planted and searched for in every captured stream on every refusal and error path; (e) the stage runs once in `ubuntu:24.04` with identical row counts (binding lesson 1).
**Anchor.** The allow-list lives in the battery and the merge-base diff is the independent review; a weakening edits the list and the file it excuses in one diff, so the CODEOWNERS rows on the library and its suites, and the reviewer gate on baseline shrink-only, are the anchor (stated: the guard proves the set, not that the set is right).

### Guard 2 — A refusal reaches the same verdict class as the old failure

**Property.** At every converted site a refused credential produces the site's old verdict class (red step, soft verdict, warning, degraded proceed) or the honest existing class named in D2, with the marker visible, makes zero requests, and never maps to a production action or a cause nobody measured.
**Assembly.** The 24 census rows. Structural coverage for every row (calls the library or inline wrapper, no credential on argv, argv-neutrality of the non-credential arguments, replay through `_bc_tail_ok`), and arm-level execution of the real step body (extracted from the YAML) for each row in the sink table whose bare rc 2 would land in another arm: rows 2, 4, 10, 13, 15, 18, 21, 22, 24, plus one representative each of the red, soft and warning classes (rows 9, 8, 11), each with the credential empty, unset and hostile, and for one HMAC site with `python3` absent. **Row 20 (`push-infra-config.sh`) is a script, not a workflow step, and no existing suite executes it:** the battery runs the real script under the recording shim with `INFRA_DIR` pointing at the real `apps/web-platform/infra`, and asserts (i) the HMAC on stdin equals an independent computation over the payload file bytes (the oracle is the real `openssl dgst -hmac` with a synthetic key), (ii) the three credentials arrive as header directives on stdin and in no argv, (iii) a refused or empty key, and `python3` absent, exit non-zero with the marker and **zero requests**, (iv) a 202 prints `infra-config push succeeded (HTTP 202)`; a refusal makes no request, so no partial delivery to web-1 is possible from the conversion (a POST that was sent and then fails is unchanged behavior: the handler is async behind the 202 and the verify step adjudicates).
**Mutation matrix.**

| # | Mutation | Must go RED |
|---|---|---|
| 1 | drop the `webhook_liveness` pre-guard (let a refusal reach the `*)` arm) | the row expecting `listener_state=probe_error`, got `down` |
| 2 | drop the inngest-health `probe` pre-guard | the row expecting `secret_unset` and no restart verdict |
| 3 | drop the `infra-config-verify.sh` pre-guard (refusal reaches the 000 arm) | the row expecting no "listener ... DOWN" sentence |
| 4 | restore `2>/dev/null` on one `apply-inngest-rls` call | the marker-visible row |
| 5 | a swapped `$(...)` tail without `|| SIG=""` at an HMAC site | the empty-key row: expects the marker and the arm's own verdict, got a mute abort |
| 6 | `pre_frame` records `unreachable` instead of `secret_unavailable` | the `pre_frame` row |
| 7 | a site branches on `rc == 2` | the D5 predicate |
| 8 | `track.sh` emits a new verdict word | the verdict-vocabulary row (consumers' greps) |

**Harness rows.** the extracted-step runner reads the step's own `::error::`/`::warning::` lines and `GITHUB_OUTPUT` (a harness that checks only the exit code cannot tell a mute abort from a refusal); a must-PASS well-formed run per representative proves the arm still succeeds; transport-failure rows use the real-curl oracle against a closed port (the `000000` quirk); the new inline copies and the library run on the runner userland.
**Anchor.** The sink table in "Census and per-site contract" (each row names the old and new sink); the executed rows pin it mechanically.

### Guard 3 — A script that sources the library on a step's behalf cannot run without a checkout that provides it

**Property.** Every job that runs a script which sources `scripts/lib/bearer-curl.sh` (directly, or through `run:` naming that script) has a usable earlier checkout that materializes `scripts/lib/`, is not triggered by `pull_request_target`, and under `workflow_run`, `issue_comment`, `pull_request_review*` and `issues` checks out only the default branch's own ref.
**Assembly.** The lint's existing third surface covers `run:` text that names the library and composites whose action file names it. The gap is a script file that sources the library and is invoked by `run:` (today `dispatch-web-redeploy/track.sh`, called from two jobs in `apply-web-platform-infra.yml` and one in `git-data-cutover.yml`; `github-app-key-status.sh` has no CI caller).
The extension derives the set of such script files from the tree (any tracked `.sh` containing the library path, outside `scripts/lib/`) and treats a `run:` naming one by repo-relative path as a consumer; terraform `local-exec` callers (`push-infra-config.sh`) are outside workflow YAML and covered by the apply's own checkout.
**Mutation matrix.**

| # | Mutation | Must go RED |
|---|---|---|
| 1 | remove the checkout from a job that calls `track.sh` | lint: no usable checkout |
| 2 | give that checkout `path: x` or a sparse cone excluding `scripts` | lint |
| 3 | a second caller added after a compliant first (second-member) | lint judges every job, not the first |
| 4 | a `workflow_run` job whose checkout names a head sha | lint (untrusted ref) |
| 5 | a `pull_request_target` trigger added to a caller | lint |
| 6 | the derived set emptied (rename the grep) | the set-size floor in the lint suite |
| 7 | the three new sparse checkouts name `scripts/lib-old` | lint (path-segment rule) |

**Harness rows.** synthesized fixture workflows: must-PASS (a script consumer with a full checkout; a sparse cone `scripts/lib/bearer-curl.sh`, `cone-mode: false`) that differ from the real files, and must-FAIL (above). The lint suite's count (99) is a floor re-derived, never lowered.
**Anchor.** the lint suite's fixtures plus the CODEOWNERS entry on the lint (existing).

## Implementation Phases

Order: scaffolding and RED rows first, then conversions by blast radius, then the battery, then docs, then the baseline-only commit. Write each phase's failing rows BEFORE its change (`cq-write-failing-tests-before`). Every command prints counts or exit codes only: no credential value is printed, echoed or compared in the clear
(compare with `[[ "$a" == "$b" ]]` or `cmp` and print the verdict only). Never `git stash`, never a pattern-matching process kill, never `rm` on a variable path (use `git ls-files -z` with `tar --null`). Poll with Monitor, never `run_in_background`. The repo-wide Rule E run is expected red from commit 2 until commit 10; the per-phase gate is the explicit-path run, and the baseline is
regenerated **only** after the merge-from-main commit exists.

### Phase 0: Gates, measure, replay, then RED

0. Record the lead's notice and choices (kill-switch option; D4 default; D3) in the decision file before any edit; the plan's CPO assessment goes into the PR draft.
1. `git fetch origin main`; read `gh pr view 9877 --json files` and `gh pr diff 9877`; `git merge origin/main` if anything touching S4 files landed. Re-run the census (17/42; 13 files/31 sites; 20 `-hmac`); record counts.
2. **Derive** the coupled-suite list on the real tree (`git grep -l` each S4 file name, step name and distinctive string across `apps/web-platform/{infra,test,scripts}`, `plugins/soleur/test`, `scripts`, `tests`, `.github/scripts/test`), and run every hit read-only against a scratch conversion (a copy of the tracked tree outside the worktree, made with `git ls-files -z | tar --null -T -`).
   Record every red row against the "Stub holders" table; any red row needing an edit **not** in that table is reported and the plan amended. `cutover-inngest-workflow.test.sh` is run, not edited.
3. **Replay** (binding lesson 3): extract each converted call's non-credential argument list and body from the real files (the SQL payload, the Resend bodies, the mint `scope_body`, the multi-file push payload is a file, so only its path is replayed) and run them through the library's real `_bc_tail_ok`; zero refusals required; record the count (`--url`, `--header`, `--request`, `--data`, `--silent`, `--show-error`, `-w $'\n%{http_code}'`, `-X DELETE` are expected to pass; `--data-binary @-` is refused and no site uses it).
4. **Credential-shape measurement, count only, never printing a value:** read each class into a variable and test with `case` globs against `[A-Za-z0-9._~+/=-]`: Cloudflare Access id and secret, `HCLOUD_TOKEN_READONLY` and `HCLOUD_TOKEN` (Doppler `prd_terraform`), `SUPABASE_ACCESS_TOKEN` and `RESEND_API_KEY` (Doppler `prd` where present; GitHub-only secrets are judged by vendor format and by the first live run), the deploy-webhook secret (HMAC key: only non-empty matters). A failed measurement stops that conversion until the class is widened with evidence.
5. `docker run ubuntu:24.04` (image `soleur-s3-runner`, `/var/tmp/s3-inner.sh`; rebuild if missing): record bash, curl, git and python3 versions; measure D7's `GIT_CONFIG_COUNT` header against a local bare remote.
6. Verify the inngest-health `secret_unset` routing, the `listener_state` consumers, the `PRE_FRAME_STATUS` consumers (infra-config-gate/verify tests) and every `verdict=redeploy_*` consumer by grep; record the revert trigger.
7. Write the RED rows (stage S4 skeleton, lint fixtures, suite edits) and record RED counts; run `bash plugins/soleur/test/c4-count-parity.test.sh`.

### Phase 1: lint extension and battery scaffolding (commit 1)

1.1 `scripts/lint-workflow-local-action-checkout.py`: derive script consumers (Guard 3), keep the existing messages; add fixtures and rows to `scripts/lint-workflow-local-action-checkout.test.sh` (floor re-derived). 1.2 `tests/scripts/test-argv-bearer-sweep.sh`: stage S4 skeleton (instrument controls, derived populations, manifests), initially red.

### Phase 2: composites and `track.sh` (commit 2)

2.1 `mint-infra-app-token/action.yml`: source after the input checks and before the JWT exchange; `bc_curl mint-infra-app-token 'Authorization:Bearer :JWT' -- -sS --max-time 30 -X POST -d "$scope_body" -H 'Accept: ...' -H 'X-GitHub-Api-Version: 2022-11-28' URL || curl_rc=$?`; keep every census needle line (`using: 'composite'`, the two `doppler secrets get` lines, `b64url()`, `openssl dgst -sha256 -sign`, `::add-mask::`); revoke without `2>&1`. 2.2 `track.sh`: after the xtrace refusal block (Rule A order), source by `BASH_SOURCE`; replace the presence loop with `bc_ok_var`; keep `curl` first in the tool loop; add `python3` to the tool list after it.
2.3 Fix `test-dispatch-web-redeploy.sh` P2 and `test-mint-inngest-bootstrap-tag.sh` ("Composite" anchor, `GITHUB_WORKSPACE`).

### Phase 3: dispatch-only and self-fire workflows (commit 3)

3.1 `restart-inngest-server.yml` (keep `MAX_POLLS=` and `POLL_INTERVAL=` single lines; no new job). 3.2 `deploy-inngest-image.yml` (inline wrapper, D4; no checkout added). 3.3 `apply-inngest-rls.yml` (pre-guard, drop `2>/dev/null`, keep `/v1/projects/` and `identity_mismatch` text). 3.4 `apply-github-infra.yml` Revoke step (keep `installation/token`, `DELETE`, the step's `if` and env). Explicit-path Rule E green on each; owning suites green.

### Phase 4: `apply-deploy-pipeline-fix.yml` (commit 4)

4.1 Seven sites per rows 13 to 17, library sourced per step (`${GITHUB_WORKSPACE:?}`), pre-guards of D2; keep step ids and `if:` lines the mutation harness anchors on (`id: webhook_liveness`); no `continue-on-error`. 4.2 Run `infra-config-gate.test.sh` and `ship-deploy-pipeline-fix-gate.test.ts` read-only.

### Phase 5: `web-platform-release.yml` (commit 5)

5.1 Five sites per rows 8 to 12 as **inline wrappers** (no checkout step is added to any job in this file); keep the step name "Deploy via webhook" (read by `deploy-arm.sh`), `WEB_HOST_PRIVATE_IPS` single line, the Resend URL and sender literals, `IN_FLIGHT_CEILING_S`, and the `superseded` conditions `workflow-run-deploy-invariants` G13 pins.

### Phase 6: infra scripts and their two suites (commit 6, infra path)

6.1 `push-infra-config.sh`: xtrace refusal first, library by `BASH_SOURCE`, D5 signing from the payload file, `bc_curl` with `--data-binary @"$PAYLOAD_FILE"`; no new `"x_b64":` string; bump nothing else (the redeploy nonce comment is untouched). 6.2 `infra-config-verify.sh`: xtrace refusal, inline wrapper and canonical python snippet, pre-guard; edit `infra-config-verify.test.sh` (stub, `ALLOWED`, control copy) and
`infra-config-repush-mutation.test.sh` (S3 anchor). 6.3 `verify-tunnel-ingress-origin.sh`: canonical snippet at the `HMAC=` line; `python3` symlink in the battery's `VT_STUBS`. 6.4 `github-app-key-status.sh`: library, exit-3 mapping.

### Phase 7: held-back sites (commit 7, infra path)

7.1 `scheduled-inngest-health.yml` `probe` per D8(a) and `inngest-dedicated-host-classify.test.sh` one `cp`; keep the `case "$MODE" in` block and the `/tmp/health-body` references the suite greps. 7.2 `workspaces-luks-cutover.yml` per D8(b) and the two stub arms.

### Phase 8: `bump-inngest-bootstrap-pin.sh` (commit 8)

D7, with the suite rows (`g2.script:token-from-env` rewritten; a new row that no recorded git argv holds the token or its base64; xtrace refusal retained; fixture `BUMP_PUSH_URL` path unchanged).

### Phase 9: battery completion, docs, ADR, lint docstring (commit 9)

9.1 Finish stage S4 (Guards 1 and 2 rows; the S3-stage manifest and held-back expectations updated 1:1; EXPECTED_TESTS set to the realized count). 9.2 `scripts/lib/test-affected-paths.sh` edges. 9.3 Rewrite the lint docstring's HMAC and held-back paragraphs (23 production sites measured earlier -> 2 remain plus the two Markdown files). 9.4 Amend ADR-280 (D11). 9.5 Runbook rows that quote the old form, if any (grep).

### Phase 10: verification on the runner userland, pre-push gates, baseline-only commit (commit 10), tracking

10.1 Every changed or new shell suite in `ubuntu:24.04` (`soleur-s3-runner`), recording row counts equal to the dev host's. 10.2 Mutation-check every new guard on a scratch copy (Guards 1 to 3, one row per alternative); realized floors.
10.3 Revert recipe dry-run in a scratch tree (tar over `git ls-files -z`), through the gates the revert PR would face, including `lint-shell-trace-credential-refusal.py --changed --base origin/main` run by hand; the recipe lists both kill-switch lines.
10.4 Gates (do not run `test-all.sh` locally): Rule E lint explicit-path and repo-wide, the sweep battery, `.claude/hooks/grep-q-pipe-guard.test.sh` (process substitution, never `| grep -q`), `scripts/lint-supabase-deprecated-endpoints.sh`, `scripts/lint-orphan-test-suites.sh`, `scripts/guard-vacuity-floor.test.sh`, `plugins/soleur/test/fixture-env-adoption.test.sh`, the fixture-relative and fixture-dir-operand ratchets,
`lint-skill-body-budget.py --base <merge-base>`, `lint-rule-bodies.py --check --base <merge-base>`, `tsc --noEmit` for any changed `.ts` (none planned), `gitleaks` over `origin/main..HEAD`, `lint-workflow-errexit-capture.py`, `lint-workflow-run-body-syntax.py`, `plugins/soleur/test/workflow-file-size.test.ts`, `plugins/soleur/test/c4-count-parity.test.sh`.
The gitleaks hook scans the staged index before a command runs: edit and `git commit` in separate Bash calls; build token-shaped fixtures from concatenated pieces.
10.5 `git fetch && git merge origin/main` (a merge commit, never a rebase), re-run ratchets, then `--write-baseline-e`, drop the 13 matching ceiling rows in the same change, update the A and D baselines (remove the two remediated scripts and the stale verify-tunnel row); expect E = 4 files / 11 sites.
10.6 PR: `Ref #9597`, `Ref #7797`; first body line names the pushes the merge fires (apply-web-platform-infra, apply-deploy-pipeline-fix with the `deploy_pipeline_fix` replacement, web release and deploy, apply-inngest-rls, mint tag decision, infra-validation, validate-vector-config); no plan or spec paths in the body; avoid the words soak, outage, "Pro", "subscription", "upgrade"; `Filed: #N` lines and the net-issue-flow override with one justification per issue.
10.7 Tracking: file the follow-through (first live runs of the rarely-run conversions) with a `scripts/followthroughs/bearer-curl-s4-first-runs-<issue>.sh` modeled on `bearer-curl-first-runs-9811.sh`, and the decision-challenge issue from the decision file; comment on #9597 (counts, ticks for S2, S3, S4, the `ci-deploy.sh` correction) and on #9757 (what S4 did not take and its owner).

### Phase 11: lead notice, review, ship, post-merge

11.1 **Stop before ship** with a factual `<stop>BLOCKED: ...</stop>` notice naming: the files under `apps/web-platform/infra/**` and `apps/web-platform/scripts/`; the workflows the merge fires (MERGE EFFECTS) including the `deploy_pipeline_fix` replacement and its first live run of the converted push script; the kill-switch choices (`[skip-web-platform-apply]` and `[skip-deploy-fix-apply]` each on its own line of the merge commit message: skipping loses the live proof and leaves the hash change
undelivered, and `scheduled-terraform-drift` reports drift until a sanctioned apply; not skipping is the default the brief asks for); the revert plan; and that a production-apply **dispatch** is a separate approval and is not planned. A menu acknowledgement is not that approval (`hr-menu-option-ack-not-prod-write-auth`). The notice also states: (a) skipping only one of the two tokens leaves the other apply firing (each token is matched only as an **exact own line** of the merge commit body, although the header comment of `apply-deploy-pipeline-fix.yml` says "anywhere"); (b) a revert fires the same applies again, replaces `deploy_pipeline_fix` a second time and runs the previous push script; (c) the merge should land in a **quiet window**: no in-flight `web-1-swap` run, no other infra-path PR armed behind it, and the lead is told the GitHub pending-run rule above; (d) the **pre-stated split trigger**: if the lead declines the apply exposure, commits 6 and 7 move to a follow-on PR and the held-back S3 sites wait there.
11.2 Review: report-only seats under `/var/tmp`, touch nothing until all return; fix-round capped at two plus a verification pass; `emit-review-trailer.sh`. 11.3 `soleur:archive-kb` after ship Phase 6 and before merge. 11.4 `gh pr merge --squash --auto`; never sync a BEHIND PR that is armed.

## Baseline and ceiling rows

Rule E baseline before: 17 files / 42 sites. Rows leaving both the baseline and the ceiling table (13): `.github/actions/dispatch-web-redeploy/track.sh` 2, `.github/actions/mint-infra-app-token/action.yml` 2, `apply-deploy-pipeline-fix.yml` 6, `apply-github-infra.yml` 1, `apply-inngest-rls.yml` 4, `deploy-inngest-image.yml` 2, `restart-inngest-server.yml` 4,
`scheduled-inngest-health.yml` 1, `web-platform-release.yml` 5, `workspaces-luks-cutover.yml` 1, `apps/web-platform/infra/infra-config-verify.sh` 1, `apps/web-platform/infra/push-infra-config.sh` 1, `apps/web-platform/scripts/github-app-key-status.sh` 1. Remaining: `apply-web-platform-infra.yml` 5 (ceiling 6), `cloud-init-registry.yml` 4, the two cla-evidence files 1 each.
Rule D baseline: drop `infra-config-verify.sh` and `push-infra-config.sh` (the other 9 rows stay). Rule A baseline: drop the same two and the stale `verify-tunnel-ingress-origin.sh` row.

## Test Scenarios

1. **Well-formed run, per representative**: the real extracted step body runs under the recording shim; the credential reaches stdin as exactly the expected `header = "..."` directives; no recorded argv holds it; the arm succeeds. 2. **Hostile and empty and unset** per credential position (second and third spec of the webhook triple included): zero recorded calls, one marker, the verdict of the sink table. 3. **python3 absent** at one HMAC site per form (library, inline): marker plus the arm's own verdict, not a mute abort.
4. **Transport failure** through real curl against a closed port: the old `000`/`000000` behavior is preserved. 5. **Negative canary** over stdout, stderr, step summary, `GITHUB_OUTPUT` and annotations on every refusal. 6. **Replay**: every real call's non-credential arguments pass `_bc_tail_ok` on curl 8.5. 7. **Infra suites** green after their edits (stub reads stdin; `ALLOWED`; skeleton; `cp`), counts equal to before.
8. **Derived populations**: the HMAC census, the library-user manifest and the script-consumer lint set equal their manifests; each has a floor. 9. **Git header**: the recorded git argv holds neither the token nor its base64; `GIT_TRACE=1` output holds neither. 10. **Runner userland**: every changed suite's row count in `ubuntu:24.04` equals the dev host's.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Rule E: explicit-path runs clean on all 13 baseline files; the repo-wide run reports exactly 4 files / 11 sites after the baseline-only commit; ceiling rows for the 13 files removed in the same change.
- [ ] No S4 file carries `openssl dgst ... -hmac "$KEY"` in non-comment text; the derived census equals the allow-list (cutover-inngest.sh x2 plus the two documentation files).
- [ ] The inngest-health `probe` row: a refused credential records `secret_unset`, makes no request, dispatches no restart; `webhook_liveness`: refusal yields `listener_state=probe_error`; `infra-config-verify.sh`: refusal prints no "listener ... DOWN" text.
- [ ] Every converted `bc_curl` call: no `2>/dev/null`, no credential header literal, no branch on `rc == 2`; the marker name equals the file's basename.
- [ ] The replay of every real call's argument list and body through `_bc_tail_ok` records zero refusals (count in the PR).
- [ ] Guards 1 to 3: each mutation row goes red on a scratch copy (mutation landed per `diff -q`, unmutated control green first); floors set to realized counts and visible to `guard-vacuity-floor.test.sh`.
- [ ] Changed shell suites pass in `ubuntu:24.04` (bash 5.2, curl 8.5) with row counts equal to the dev host's; the sweep battery passes (floor set to the realized count); `scripts/lib/bearer-curl.test.sh` and the lint suite unchanged or higher.
- [ ] The diff contains no path under `plugins/` and no `.tf` file (script-checked); the diff's `apps/web-platform/**` paths are exactly the files this plan lists.
- [ ] `workflow-file-size.test.ts` green (`web-platform-release.yml` stays under 490,000 bytes).
- [ ] The revert recipe was dry-run in a scratch tree through the gates; it names both kill-switch lines and states that a revert re-fires the same applies.
- [ ] The Phase 0.4 credential-shape counts (verdicts only, per class) and the Phase 0.3 replay count are recorded in the PR before Phase 11; a class judged only by vendor format has a recorded dry read or a widened alphabet with evidence.
- [ ] `push-infra-config.sh` is executed by the battery under the recording shim (Guard 2, row 20) with independent HMAC, stdin-only credentials and zero-request refusal rows.
- [ ] Accepted residual recorded in the PR: a `release-outcome` checkout failure suppresses that job's operator email (its Sentry event is independent); under `workflow_run` the sourced library is the default branch's head, which can be newer than the deployed SHA (same default-branch trust as the workflow file itself).
- [ ] The follow-through issue is filed **before the PR is marked ready**, with an owner, a dated maximum wait (merge + 30 days) and a revert trigger per site.
- [ ] CPO sign-off recorded; the lead's notice (Phase 11.1) recorded with the kill-switch decision; CLA-signed author; review trailer emitted.
- [ ] PR body: first line names the pushes the merge fires; `Ref #9597`, `Ref #7797`; no plan or spec paths; `Filed: #N` lines and the net-issue-flow override with one justification per issue.

### Post-merge (verification, no SSH)

Run `plugins/soleur/scripts/deploy-arm.sh find --wait <FULL 40-hex merge sha>`, then `deploy-arm.sh served` from a detached `origin/main` worktree, **before** any post-deploy action. Read each run's conclusion and its step list, not only the badge; a `cancelled` run is not a pass.

| # | Check | Expected | Source |
|---|---|---|---|
| 1 | `web-platform-release` deploy arm for the merge sha | `DEPLOY=success`; the "Deploy via webhook" and "Verify deploy script completion" steps succeeded; `/health` `build_sha` equals the merge sha | `deploy-arm.sh`, `gh run view` |
| 2 | `apply-web-platform-infra` push run | `success`; the summary's `SSH stage:` line says it ran (a green run that skipped the SSH stage delivered nothing); tunnel-ingress verify step green | `gh run view`, step summary |
| 3 | `apply-deploy-pipeline-fix` push run | `success` (not `cancelled`); the local-exec prints `infra-config push succeeded (HTTP 202)`; "Verify infra-config apply succeeded" emits `verdict=verified`; "Verify webhook is alive post-apply" green | run log |
| 4 | `apply-inngest-rls` push run (self-fire) and its next 4-hourly run | `success`, `violations=0`, authoritative gate PASS | run log |
| 5 | Marker count over every run above and over `scheduled-inngest-health` since the merge | `SOLEUR_CREDENTIAL_REFUSED` = 0 | `gh run view --log`, count only |
| 6 | Better Stack, read-only: `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since <merge ts> --grep SOLEUR_CREDENTIAL_REFUSED`, and the same over the window since the S2 merge (the two S2 open items: first content-publisher Bluesky/X run, the 08:00Z community-monitor row) | zero rows is the healthy state; any row names the script and reason | `scripts/betterstack-query.sh` |
| 7 | Live read of the converted `github-app-key-status.sh` under `doppler run -p soleur -c prd_terraform` | prints the `github_app_key_*` lines, exit 0 (a read-only GET through the tunnel) | the script |
| 8 | `scheduled-inngest-health` scheduled run after the merge, plus one read-only dispatch | `success`, no restart dispatched, no marker | `gh run list`, `gh workflow run` (read-only probe) |
| 9 | `mint-inngest-bootstrap-tag` push run | `result=noop` | run log |
| 10 | Repo-wide Rule E on `main` | 4 files / 11 sites | `lint-shell-trace-credential-refusal.py --census` |
| 11 | `soleur:trigger-cron` forced hosted run | **Not applicable by evidence**: no script a hosted Inngest cron executes is edited (grep over `apps/web-platform/server`, `app`, `lib` for every S4 file name returns only `watchdog-dispatch-table.ts`, which dispatches `scheduled-inngest-health.yml` by name through the GitHub API); row 6 reads the hosted-cron logs for the marker instead. If review finds a hosted-cron consumer, this row becomes mandatory. | grep recorded in the PR |
| 12 | Rarely-run conversions with no read-only live trigger (`restart-inngest-server`, `deploy-inngest-image`, `workspaces-luks-cutover`, `apply-github-infra` revoke, the mint composite, `bump-inngest-bootstrap-pin.sh`, `track.sh`) | no live proof at merge; the battery drives their real step bodies; the follow-through issue tracks each first real run: owner, a **maximum wait of merge + 30 days**, after which the item is either exercised by a sanctioned read-only dispatch (needs its own approval where it writes) or accepted explicitly on the issue. `workspaces-luks-cutover` is data-destructive but fails closed before any write (Guard 2 row), and `restart-inngest-server` gets an explicit first-real-run watch | follow-through |
| 13 | Tracker | #9597 comment with the S4 counts and the corrected checklist; #9757 comment naming the owner of each item S4 did not take | `gh issue comment` |

Revert trigger: any `SOLEUR_CREDENTIAL_REFUSED` line on a secret that is valid at the vendor (an alphabet gap), or a red release deploy attributable to the conversion, reverts the affected commit (commits 3 to 8 are separable) through a revert PR that carries both kill-switch lines when it touches commits 6 or 7.

## Observability

```yaml
liveness_signal:
  what: the converted workflows' own runs (scheduled-inngest-health every 15 minutes with its Sentry check-in; apply-inngest-rls every 4 hours; the release deploy and the deploy-pipeline-fix apply on every qualifying push) concluding success with no SOLEUR_CREDENTIAL_REFUSED line
  cadence: every 15 minutes (inngest health), every 4 hours (RLS), per merge (release and apply)
  alert_target: GitHub issues (ci/inngest-* classes), the Sentry cron monitor for scheduled-inngest-health, the ops email from the release workflows
  configured_in: .github/workflows/scheduled-inngest-health.yml, apply-inngest-rls.yml, web-platform-release.yml, apply-deploy-pipeline-fix.yml
error_reporting:
  destination: GitHub Actions run log (observability layer 6): the value-free marker SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char> and the ::error:: annotation of each site's sink; hosted-cron and host logs reach Better Stack (a refusal there is read by scripts/betterstack-query.sh)
  fail_loud: every refusal ends in a red step, a visible ::error:: or ::warning:: annotation, or the existing honest soft class (Guard 2 sink table); a refusal is never a silent skip, and it is not paged (stated)
failure_modes:
  - mode: the library is missing from a job's checkout (a sparse cone that drops scripts/lib, a checkout failure)
    detection: the step's source line fails with an ::error:: and exit 1 (never an argv fallback); the lint's third surface catches the cone statically
    alert_route: red job; the release workflow's operator email; the failed-run issue classes
  - mode: a stored credential falls outside the shape alphabet or carries a control byte
    detection: marker line in the run log; the follow-through probe counts it on first scheduled runs
    alert_route: red step or visible annotation per site; follow-through issue FAIL
  - mode: a refusal is mapped to a cause nobody measured (listener down, inngest down, unreachable)
    detection: Guard 2 rows executing the real arms
    alert_route: pre-merge CI red
  - mode: the apply's deploy_pipeline_fix provisioner fails on the converted push script
    detection: apply-deploy-pipeline-fix run red; the local-exec prints no "infra-config push succeeded (HTTP 202)" line
    alert_route: apply workflow failure issue and ops email; revert trigger
  - mode: a new argv HMAC site or header appears in a converted file
    detection: Rule E baseline equality and the derived HMAC census in the sweep battery
    alert_route: pre-merge CI red
logs:
  where: GitHub Actions run logs for workflow-side sites; Better Stack (soleur-inngest-vector-prd) for host and hosted-cron logs
  retention: GitHub run logs 90 days by default; Better Stack per the source's retention (read the connection's setting before relying on it past 30 days)
discoverability_test:
  command: python3 scripts/lint-shell-trace-credential-refusal.py .github/actions/dispatch-web-redeploy/track.sh .github/actions/mint-infra-app-token/action.yml .github/workflows/apply-deploy-pipeline-fix.yml .github/workflows/apply-github-infra.yml .github/workflows/apply-inngest-rls.yml .github/workflows/deploy-inngest-image.yml .github/workflows/restart-inngest-server.yml .github/workflows/scheduled-inngest-health.yml .github/workflows/web-platform-release.yml .github/workflows/workspaces-luks-cutover.yml apps/web-platform/infra/infra-config-verify.sh apps/web-platform/infra/push-infra-config.sh apps/web-platform/scripts/github-app-key-status.sh
  expected_output: "OK:"
```

(The probe runs in about 0.4 s: measured today it prints `35 violation(s) in 13 scanned file(s)` before the work and must print `OK:` after. Affected-surface note: the terraform local-exec provisioner is a blind surface; its in-surface signals are the run-log lines `infra-config push succeeded (HTTP 202)` and the marker, both named in failure_modes above.)

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering (CTO)

**Status:** reviewed
**Assessment:** sound and well-measured; the risk is concentration, not design. Blast radius rated high (the merge replaces the only no-SSH remediation channel in the same push that runs the converted script for the first time, beside a converted release deploy and RLS apply, so a red run is hard to attribute). Recommended a stronger default of splitting at the commit 6/7 seam; the plan keeps one PR per the brief, pre-states the split trigger in Phase 11 and records the alternative in the decision file. Required an executing row for `push-infra-config.sh` (added to Guard 2) and D7 measurement against a header-recording server (added). Verified true against the repo: the `triggers_replace` hashing of `push-infra-config.sh` (and its absence from the web-2 resource), `deploy-arm.sh` reading only `resolve-target`'s log, the token URL at the bump script, the sparse-checkout precedent. Asked that the `workflow_run` library-newer-than-deploy-sha note and the S4 obligation named in ADR-280 decision 3 be cited in the amendment (added to D11).

### Operations (COO)

**Status:** reviewed
**Assessment:** operationally sound on the lead-notice stop, the kill switches (own-line match verified at `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml`) and the no-SSH verification table. Gaps found and closed in this revision: the cancelled-run mechanism and recovery (shared concurrency group, one pending run kept), the single-skip and revert side effects in the lead notice, and a dated maximum wait with an owner for the follow-through on rarely-run workflows.

### Product (CPO)

**Status:** reviewed, **sign-off: yes-with-conditions**; all seven conditions applied in this revision (executing row for the push script; recorded shape-measurement counts; quiet-window merge and a pre-stated split trigger; the LUKS wording in User-Brand Impact; the follow-through filed before ready with owners and dates; dated owners for the D10 deferrals and the rotation issue link; Domain Review filled).

No Product/UX gate: the plan creates and modifies no user-facing page or component (no `components/**`, `app/**/page.tsx` or layout file in the file lists).

## Open Code-Review Overlap

1 open code-review issue touches a planned file: #8593 ("probe gate window is narrower than the silent-truncation property it names", about unbounded `gh ... list` enumerations in `scheduled-inngest-health.yml`). **Acknowledge:** a different concern (the `gh` listing limit gate) in later steps of the file; S4 edits only the `probe` step's credential transport. It stays open.
Checked 88 open code-review issues against 21 planned and candidate paths with two-stage `gh --json` plus `jq --arg`.

## Files to Edit

Production: `.github/actions/dispatch-web-redeploy/track.sh`, `.github/actions/mint-infra-app-token/action.yml`, `.github/workflows/apply-deploy-pipeline-fix.yml`, `.github/workflows/apply-github-infra.yml`, `.github/workflows/apply-inngest-rls.yml`, `.github/workflows/deploy-inngest-image.yml`, `.github/workflows/restart-inngest-server.yml`,
`.github/workflows/scheduled-inngest-health.yml`, `.github/workflows/web-platform-release.yml`, `.github/workflows/workspaces-luks-cutover.yml`, `.github/scripts/bump-inngest-bootstrap-pin.sh`, `apps/web-platform/infra/infra-config-verify.sh`, `apps/web-platform/infra/push-infra-config.sh`, `apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh`, `apps/web-platform/scripts/github-app-key-status.sh`.
Suites and gates: `apps/web-platform/infra/infra-config-verify.test.sh`, `apps/web-platform/infra/infra-config-repush-mutation.test.sh`, `apps/web-platform/infra/workspaces-luks-cutover-workflow.test.sh`, `apps/web-platform/infra/inngest-dedicated-host-classify.test.sh`, `tests/scripts/test-argv-bearer-sweep.sh`, `tests/scripts/test-dispatch-web-redeploy.sh`, `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh`,
`.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`, `scripts/lint-workflow-step-env-refs.test.sh`, `scripts/lint-workflow-local-action-checkout.py`, `scripts/lint-workflow-local-action-checkout.test.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/lint-shell-trace-credential-refusal.py` (docstring only), the four baseline files (`...-e.baseline.txt`, `rule-e-census-ceiling.tsv`, `...-d.baseline.txt`, `lint-shell-trace-credential-refusal.baseline.txt`).
Docs: `knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md` (amendment).
Not edited (constraints): `scripts/lib/bearer-curl.sh`, `apps/web-platform/infra/ci-deploy.sh`, `apps/web-platform/infra/cutover-inngest-workflow.test.sh`, `scripts/cutover-inngest.sh`, `.github/workflows/cutover-inngest.yml` (all in or near #9877), `apps/web-platform/infra/server.tf`, any `plugins/` file.

## Files to Create

`scripts/followthroughs/bearer-curl-s4-first-runs-<issue>.sh` (Phase 10.7; the issue number is known only after filing). Spec directory artifacts: `knowledge-base/project/specs/feat-one-shot-argv-bearer-sweep-s4-push-triggered/{tasks.md,decision-challenges.md,session-state.md}`.

## Risks and Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `single-user incident`.
- The merge is large and concentrated: the release's own deploy, two applies and the RLS self-apply run on the freshly converted code at once. The sparse-checkout default (D4) adds a step-0 dependency to the deploy job; if the lead rejects it, the inline alternative is five more guard copies.
- `deploy_pipeline_fix` is **replaced** by the apply (hash change). Its remediation channel is the thing being modified; a failed push leaves the resource tainted and the next apply re-runs it. The revert is ordinary but must carry both kill-switch lines if it touches commits 6 or 7.
- `[skip-web-platform-apply]` and `[skip-deploy-fix-apply]` match only as an exact line in the merge commit body. They skip, they do not deliver; using them to avoid notice is not an option, and they are the lead's call.
- Read-only holder reports were derived by reading, not by running (no suite was executed); every red count in "Stub holders" is a prediction until Phase 0.2 re-measures it. Two reports disagreed with the S3 plan in one place (the S3 plan did not run `cutover-inngest-workflow.test.sh`); the S4 plan runs it.
- `bc_body` judging is content-based: a legitimate JSON body containing `/proc/` or `/dev/stdin` text (an email body, a SQL comment) would be refused with rc 64 and must be replayed in Phase 0.3 on the real bodies, including the Resend HTML built at run time (replay with a representative failure message).
- The probe's `source` placement inside the `if [[ -z "$fail_mode" ]]` arm keeps the three "secrets unset" suite rows green but means a missing library is only discovered when secrets are present; the `::error::` on source failure is mandatory, and Phase 0 checks which placement the suite's rows need.
- Do not run ratchets during an unresolved merge (the 2026-10-09 learning); regenerate baselines only after the merge-from-main commit exists.
- No repository writes while a background gate run is reading the battery.
