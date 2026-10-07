---
title: "feat: agent-dispatchable, approval-gated reboot of one named web host (web-2 first)"
date: 2026-10-07
slug: web-host-reboot-workflow
branch: feat-one-shot-web-host-reboot-9372
issue: 9372
type: feat
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Add a dispatch-only workflow plus two small scripts so that a soft reboot of the web-2 standby, and the graded reboot proof that follows it, can be run end to end by an agent. The Hetzner write credential stays behind the Tier-B environment reviewer gate. The post-reboot evidence is read from Better Stack through the existing rows helper and reported as rows only.

## Research Insights

### Premise validation (Phase 0.6, run 2026-10-07)

Checked by `gh issue view` and by reading `origin/main`'s tree. #9372 is OPEN (the issue this work refs, never closes), #9669 is OPEN (the `v`-prefix `image_tag` defect), #9572 is OPEN (the ledger flip, a separate later PR, out of scope here), #6931 is OPEN (the soak-gated follow-through, the actual grader), #8209 is OPEN (the Tier-B credential tiers; this workflow is a new Tier-B consumer). `cmd_reboot` exists in `scripts/web2-rebirth.sh` and the classifier it sits behind exists in `tests/scripts/lib/web2-rebirth-classify.sh`. What held: every cited path and symbol. What was stale or incomplete is in the Research Reconciliation table: the rebirth workflow is not "inert" any more (it was dispatched on 2026-10-06), the brief's refusal list omits one of `cmd_reboot`'s refusals (the never-pooled proof), and the brief's "use the rows helper" instruction collides with a census that bars write verbs from any file naming that helper. No ADR rejects the mechanism: ADR-263 (guest-side fresh-boot LUKS) and ADR-241 (credential tiers) are the two ADRs touched, and neither lists an agent-dispatched reboot among its rejected alternatives.

### Property list (Phase 0.6b)

1. Only the environment reviewer's approval releases the Hetzner write credential; the dispatching agent can start a run and can never approve it.
2. Exactly one named host can be rebooted (web-2 today); web-1 cannot be reached under any input.
3. The target is the server that Terraform state holds AND the id the dispatcher typed, so a replace that lands between dispatch and approval cannot redirect the reboot.
4. The reboot request is made to Hetzner and the action's result is reported (accepted is a request, not a result).
5. The pre-request boot_id context is printed, and a boot that BEGAN after the request is read directly from the host's own journald rows, so a later row can be told from an earlier one by an invariant and not a proxy.
6. Post-request evidence is read from Better Stack rows only and reported as PASS / FAIL / NOT YET, and no output line states what the volume is.
7. No SSH, no Doppler write, no token mint, no Terraform plan or apply, no ledger edit, no dispatch inside this change.
8. The evidence outlives the run: it can be re-read later with no second reboot and no second approval.
9. The capability has an explicit end of life (kept or retired by name in the closing change).

### Cut list (Phase 0.6b)

| Mechanism | Property it would buy | What already covers it, or why it is cut |
|---|---|---|
| a `plan_only` / dry-run input (siblings default to it) | 4, 7 | The reboot POST is the last fallible step; every config failure (loader, backend credentials, init, state read, snapshot) lands before it. A dry run costs a second reviewer approval for no write it prevents. Cut. |
| a shared `hapi`/`errcode`/`fail` library extracted from `web2-rebirth.sh` | none new | `web2-rebirth.sh` is a dispatcher that executes at source time (its trailing `case` exits 2 with no verb), so it cannot be sourced; both files retire together. Duplicate ~25 lines and pin the duplicated bodies equal with one test row while both exist. |
| forcing the daily probe to run now | 6 | No existing path starts `luks-monitor.service` on web-2 without SSH. Enumerated over the whole family (`luks-monitor`, `.service`, `.timer`, the suffixless binary) with an untruncated `git grep` outside docs and tests: the ONE starter in the tree is the last `inline` entry of the `remote-exec` block in `terraform_data.luks_monitor_install` (`workspaces-luks.tf`), an SSH provisioner on web-1; `workspaces-luks-verify.yml` runs the probe script over SSH on web-1 too; `luks-monitor-install.test.sh` (G1) pins that exactly one line anywhere starts the unit; `ci-deploy.sh` and the infra-config helpers name no luks unit; `workspaces-luks-provision.sh` documents that web-2's unit is deliberately never kicked. Forcing a probe on web-2 would be SSH by another name. Cut; NOT YET is the honest answer. |
| Hetzner CPU metrics, or a `host_metrics` freshness line, as the liveness signal | 6 | Needs a second API read path, or a signal that cannot tell a restarted host from a running one (`vector.toml` collects cpu, memory, disk, filesystem and load only, no boot-time metric). The journald `_BOOT_ID` per-boot list through the same query function answers "did a boot begin after the request" directly and replaces the earlier telemetry line. |
| a `status == running` refusal | 4 | Hetzner's own 4xx names a stopped or locked server and nothing is written before it; reviewers (DHH, simplicity) found it buys no stated property. Cut. |
| carrying a pre-request boot id across the job boundary | 5 | A boot that began after the request is its own proof; the snapshot is context only and crosses no boundary. Cut. |
| a credential-free `validate` job ahead of the approval gate | 4 | Would stop a typo from spending an approval; recorded as a taste option in `decision-challenges.md` and not adopted, because the live-state refusals need the credentials anyway and print the corrected value. |
| a workflow-level `terraform-apply-web-platform-host` lock | 3 | The job only reads state (`state pull`), and an observe poll must not hold the apply serializer for ~45 minutes. The host-lifecycle mutex `web-1-swap` (held by host create/replace/rebirth and the release deploy) is the one that matters. |
| a Sentry heartbeat or cron monitor for this workflow | none | A one-off dispatch has no cadence to miss, and `actions/sentry-heartbeat` would move four counts in `model.c4` (c4-count-parity C1 to C3 and C5). |
| posting the verdict to an issue comment | 8 | Needs an issue-write scope on a job that also holds a Tier-B credential. The re-readable local command (property 8) and the #6931 follow-through cover it. The runbook says to copy the summary, as the rebirth runbook already does. |
| a separate read-only "grade" dispatch mode | 8 | A dispatch costs a reviewer approval. The same read-only script runs locally under `doppler run`, exactly as `web2-rebirth-emptiness.sh` does. |

### Files and symbols this plan leans on (verified present)

- `scripts/web2-rebirth.sh` (`cmd_reboot`, `hapi`, `errcode`, `fail`, `need_token`, `out`, `clean`, `write_hint`, `STATE_JQ`/`state_ident`; constants `WEB1_SERVER_ID=123931471`, `WEB2_NAME=soleur-web-2`).
- `.github/workflows/web2-luks-rebirth.yml` (shape template: `environment: web-platform-infra-apply`, job `concurrency: web-1-swap`, `if: github.ref == 'refs/heads/main'`, the loader step, the backend-credential extraction step, the never-pooled step, the approvals lookup in the summary).
- `.github/actions/infra-credentials/action.yml` (Tier-B loader; the legacy arm exports the READ-ONLY Hetzner token first, which is why a write verb answering 403 names that arm).
- `scripts/lib/web2-luks-rows.sh` (`w2l_fetch_probe`, `w2l_fetch_ready`, `w2l_query`, `_W2L_JQ_DEFS`, `classify_probe`, `classify_ready`, `bid`; row contract in its header), `scripts/web2-rebirth-ready-poll.sh` (precedent for a separate read-only file that uses `_W2L_JQ_DEFS` directly), `scripts/web2-rebirth-never-pooled.sh`.
- `scripts/followthroughs/web2-luks-live-6931.sh` (the grader; exit 2 NOT YET, exit 1 FAIL once `earliest + 4 d` passes; `w2l_reboot_seen`).
- `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` (the G3 census: `READERS` set, `KEY` and `VERB` regexes).
- `apps/web-platform/infra/luks-monitor.timer` (`OnCalendar=daily`, `RandomizedDelaySec=1800`, `Persistent=true`), `luks-monitor.service` (`SyslogIdentifier=luks-monitor`), `luks-monitor.sh` (the OK row carries `boot_id=`; FAIL rows carry none), `workspaces-luks-provision.sh` (enables the timer, never starts the service).
- `plugins/soleur/test/terraform-target-parity.test.ts` (`MAIN_ROOT_TF_WORKFLOWS`, the census regexes), `plugins/soleur/test/c4-count-parity.test.sh`, `apps/web-platform/infra/nic-wait-gate.test.sh` (greps every workflow for `-target=hcloud_server.web`).
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (`BASELINE_DECLARED_PROBES = 47`, bumped by one per plan that declares `credentials_required`).

### Timer analysis: does a plain reboot produce a probe row soon? (the brief asked for this to be verified from code)

- The unit is `OnCalendar=daily` (00:00 UTC) plus `RandomizedDelaySec=1800` with `Persistent=true`. `man systemd.timer` on this machine states for `Persistent=`: the service is triggered immediately on timer activation "if it would have been triggered at least once during the time when the timer was inactive", and "Such triggering is nonetheless subject to the delay imposed by RandomizedDelaySec=".
- So a catch-up row after a reboot exists only when a 00:00 UTC elapsed since the service's last trigger while the timer was down, and then it lands up to 30 minutes after boot. A reboot between two midnights with the last trigger after the earlier midnight produces no catch-up: the next row is the next daily fire, up to about 24.5 hours away. A host whose timer has never fired has no stored trigger time to compare against, so by the same sentence nothing is owed (inferred from the man page text, not measured on web-2).
- `workspaces-luks-provision.sh` enables the timer with `--now` and states the service is deliberately not kicked (the first probe row "arrives with the timer's first daily fire"); `luks-monitor-install.test.sh` G1 pins one starter in the whole tree. No SSH-free starter exists: the tree's one starter is web-1's SSH installer (`terraform_data.luks_monitor_install`), and `ci-deploy.sh` and the infra-config helpers name no luks unit (checked with an untruncated `git grep` over the whole family, not a sampled one).
- Therefore the probe row is the SLOW evidence: the in-run poll is bounded to about 40 minutes (a catch-up lands inside it), and the expected result otherwise is "a boot began, probe pending" (NOT YET), which the journald `_BOOT_ID` signal makes distinguishable from "no boot began". This is stated in the run summary and the runbook, and the follow-through on #6931 stays the grader.
- **Measured at planning time (2026-10-07 07:48 UTC, read-only, through the repo's own helper and a read-only Hetzner GET).** The live web-2 is server 169095540, `status` running, created 2026-10-06T19:32:09Z (so younger than the rebirth classifier's 72 h window until 2026-10-09). The helper's newest readiness row is 43,933 s old with `luks_arm=opened` on boot `479cd3f3-18da-4a5d-8506-8d3382a8723f`; the newest probe row is 26,986 s old (about 00:19 UTC today), OK class, on the SAME boot (two journal copies of the one row). So the timer has fired once on this instance and left a stored trigger time, no midnight will have been missed by a reboot before 2026-10-08 00:00 UTC, and no catch-up row is owed: the first probe row on a new boot would arrive in the 2026-10-08 00:00 to 00:30 UTC window. A dispatch this morning therefore ends the in-run poll at NOT YET with high probability, and that is the designed outcome, not a defect. (The values are re-measured at work time and are never copied from this plan into code or docs.)
- **Cadence of the joined rows (the join key is the boot id).** The readiness row is emitted once per instance (cloud-init), the probe row once per boot per day (timer), and journald rows continuously per boot. The verdict joins the probe row's `boot_id` to the boots that began after the request, so the key legitimately changes on the more frequent side after any reboot; the fixtures carry a probe row on a new boot over an unchanged readiness row, and a probe row on the readiness boot, so a reader that treated equality as the normal state would be RED.
- **Measured journald boot signal (2026-10-07, read-only, through the helper's `w2l_query`).** Over the last 30 h the host showed four distinct journald `_BOOT_ID` values (32 hex characters, no dashes; the probe row's boot id has dashes), one of them current with about 3,000 rows and a newest row 60 s old. The field is set by journald, shipped by Vector inside `raw`, and present on every boot seen. This is what lets the workflow report "a boot began after the request" within minutes instead of waiting up to about 24.5 h for the probe.
- **Marker state (measured 2026-10-07).** `WORKSPACES_LUKS_CUTOVER_AT` is absent from `soleur/prd_workspaces_luks_marker` (exact-name count 0) and the daily `web2_marker` verify job has been failing, as expected for a host without a post-reboot probe row, so the never-pooled gate reads `absent` today. The first verify run after a reboot that leaves a green readiness row and a probe row on a different boot can earn the marker; from then on the gate refuses every reboot by design, which the runbook states.
- A new `SOLEUR_FRESH_BOOT_READY` row is NOT produced by a plain reboot: the rows helper's header says it is emitted once per instance (cloud-init runcmd), and `scripts/web2-rebirth-ready-poll.sh` anchors on the server's creation time for that reason. In this workflow the readiness row is the BASELINE boot_id; a readiness row newer than the request means the instance was re-created, and the run says so instead of grading a reboot.

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-10-06-a-dispatch-can-fail-after-its-approval-and-my-state-claim-was-my-own-earlier-action.md`: an accepted reboot action is a request, not a result; the replaced web-2 once went dark after a soft reboot (CPU 0%, no telemetry), so the run prints a continuous-telemetry line; a pre-approval validator must reject exactly what a later step rejects (the `v` spelling, #9669); read live workflow state before writing a claim about it.
- `knowledge-base/project/learnings/2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md`: probe rows are isolated on `host_name`, `SYSLOG_IDENTIFIER` and `_SYSTEMD_UNIT`, never a bare substring; test fixtures model the real emitted JSON. The helper already does this; the new reader must not re-implement the query.
- `knowledge-base/project/learnings/2026-07-17-workflow-env-gate-references-unprovisioned-environment-auto-approves.md`: the `web-platform-infra-apply` environment is Terraform-managed with reviewer 54279 and a `main` branch policy (`web-host-birth-environment.tf`); reuse it, never re-declare.
- `knowledge-base/project/learnings/workflow-patterns/2026-07-19-real-cutover-routes-to-workflow-dispatch-and-failclosed-gate-must-self-report.md`: a fail-closed gate must print its evidence before it exits.
- Repo-wide hygiene already encoded in `web2-rebirth.sh` and reused: token on stdin (`--config -`), never argv; `-w` not `-f` so a 404 is an answer; `%`/CR/LF escaping of annotations; single-line `GITHUB_OUTPUT` values; xtrace refusal.

### Domain assessments carried into Phase 2.5

CTO: design sound; keep the two-job split; the never-pooled refusal must not be dropped; `observe` needs a structural test (no environment, no Hetzner token, no Doppler); the census traps (reader allow-list, `KEY`/`VERB`) are the highest-probability red; no `-target` text anywhere in the workflow. CLO: low risk if wording is pinned: no row contents echoed, a fixed verbatim footer on every exit path, a denylist of claim words enforced statically and per fixture, nothing touching the ledger, Article 30 record or posture doc. COO: name the dispatch watch, put the dark-host path (web-host-replace, bare `image_tag`) in the runbook, add the workflow to closing-checklist row 5, and keep the run summary free of anything an approval prompt cannot show.

## Research Reconciliation: brief vs. codebase

| Brief or spec claim | Reality (measured 2026-10-07) | Plan response |
|---|---|---|
| "the only hcloud reboot code is `cmd_reboot` ... which is pinned to the already-deleted plaintext volume and cannot be dispatched for a plain reboot" | True that `cmd_reboot` is the only POST site: `grep -rln 'actions/reboot' scripts .github apps` (shell, YAML and Python) finds only `scripts/web2-rebirth.sh` and its test. Not quite true that it cannot reach a reboot: the classifier's `resume:post_apply` verdict (server younger than 72 h, pinned volume gone) runs it, but only behind a resume plan, a Terraform apply, a readiness poll and a recovery check, and it becomes `refuse:already_reborn` after 72 h. | New workflow; the rebirth workflow is not edited. The new one has no apply path at all. |
| runbook status line: "the workflow is merged and inert until dispatched; nothing here has been run" | Stale. `gh run view` on 2026-10-07 shows `web2-luks-rebirth.yml` runs 37508997529 and 37516716515 (2026-10-06) completed `success` with the delete, forget, apply, readiness and reboot steps all `success`. | A dated correction in the rebirth runbook (an inferred item, justified in the Scope Check). The facts are re-read from `gh run view` at work time, never copied from this plan. |
| refusals to reuse from `cmd_reboot`: "exactly one server by name, refuse web-1's id, refuse if the id differs from the terraform state id" | `cmd_reboot` has further gates: `require_apply`, and `NEVER_POOLED == absent` ("with the soak marker present web-2 may already hold data"), and `state_ident` also asserts the state holds `web-1` (a wrong-state-object check). The brief's list omits these. | Keep the never-pooled gate (own step, same names-only reader) and the wrong-state-object check. `require_apply` has no analogue (no `plan_only` mode, see the Cut List). Measured 2026-10-07: the soak marker name is absent from `soleur/prd_workspaces_luks_marker`, so the gate reads `absent` today. |
| "poll Better Stack through the existing helper scripts/lib/web2-luks-rows.sh" | A census in `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` flags any non-test file whose code names the helper unless it is in `READERS`, and flags a reader that carries a write verb (`-X POST`, `curl ... -d`, and more). That is why `web2-rebirth-ready-poll.sh` is a separate file from `web2-rebirth.sh`. | Two scripts: `web-host-reboot.sh` (Hetzner write, never names the helper) and `web-host-reboot-evidence.sh` (read-only, added to `READERS`). The workflow YAML names only the evidence script. |
| "poll ... for a SOLEUR_FRESH_BOOT_READY row and a probe row on a boot_id different from the previous one" | The readiness row is once per instance (cloud-init), so a plain reboot cannot produce a new one; the helper's header says so. The probe row is once per boot per day. | The readiness row is read as context and as the "instance re-created" detector. The "different boot" proof is stronger than a boot-id set difference: journald rows for the host carry a trusted `_BOOT_ID` (measured: four boots in 30 h, 32-hex ids, newest row 60 s old), so a boot that BEGAN after the request is read directly, and the probe row only has to sit on such a boot (see the evidence contract). |
| "MAIN_ROOT_TF_WORKFLOWS ... respected only if this workflow touches that root" | The workflow runs `terraform init` and `terraform state pull` in `apps/web-platform/infra`, so `INFRA_DIR: apps/web-platform/infra` appears. `terraform-target-parity.test.ts` lists planners (`terraform (plan\|apply)`) and state writers (`state (rm\|mv\|push)`); `state pull` is neither. | Not added to `MAIN_ROOT_TF_WORKFLOWS` (adding a non-planner breaks the exact-equality census). `TERRAFORM_VERSION` is pinned equal to `apply-web-platform-infra.yml`'s anyway (a client newer than the state's last writer can refuse the state). The strings `terraform plan` and `terraform apply` stay out of every non-comment line (an `echo` would trip the planner census). |
| "closing checklist Step 8 cleanup" | The runbook's closing checklist is a table of six rows with no "Step 8"; the deletion step is row 5. | Row 5 is edited; task wording says "row 5 (the brief's Step 8)". |
| "luks-monitor timer is daily with Persistent=true, so the workflow may need to report NOT YET" | Confirmed, with the exact catch-up rule in Research Insights: a catch-up row needs a missed midnight and lands within 30 minutes of timer start; otherwise up to about 24.5 h. The probe row is therefore the SLOW evidence; the journald boot signal is the FAST one. | In-run poll bounded to about 40 min; "a boot began, probe pending" is the expected result and is reported as such; local re-grade command; the follow-through stays the grader of the soak. |
| "no SSH fallback" | No SSH-free way to start the probe exists (Cut List). The reboot itself is an API call. | No SSH anywhere; the dark-host path is `web_host_replace`, an API-driven dispatch. |

## Problem Statement

The graded reboot proof for the web-2 rebirth (#9372, acceptance criterion 2) needs a host reboot and a later read of Better Stack. Today the only reboot code path is welded to the single-use rebirth workflow, so the agent's options are to dispatch a Terraform-applying workflow it does not need, or to ask the owner to use the Hetzner web UI. The second option is the one this work removes, and it is also an unaudited production write.

## Proposed Solution

One new dispatch-only workflow with two jobs, two scripts, two test suites and a runbook. Everything the existing rebirth path already proved safe (by-name resolution, web-1 refusal, state-id equality, the never-pooled gate, the Tier-B environment, the `web-1-swap` mutex) is reused by copy; the genuinely new part is the claim-free evidence reader.

```text
dispatch (agent)  gh workflow run web-host-reboot.yml --ref main -f host=web-2 -f confirm=REBOOT-web-2-<server id> -f reason=...
   |
   v
job reboot   [environment web-platform-infra-apply = the owner's approval | concurrency web-1-swap | main only]
   validate inputs -> checkout -> setup-terraform -> tiered credential loader (HCLOUD_TOKEN write)
   -> backend credentials -> terraform init -> never-pooled reader (names only, marker config)
   -> evidence snapshot (read-only, env allow-list: prints the pre-request context)
   -> web-host-reboot.sh reboot  (allow-list -> typed id -> by name -> not web-1 -> == state id -> anchor -> POST -> poll action)
   -> summary (always)      outputs: server_id, anchor_epoch (written BEFORE the POST)
   |
   v
job observe  [needs reboot, runs when the anchor exists | no environment | no Hetzner token | no Doppler | BETTERSTACK_QUERY_* only]
   evidence grade: poll <= 40 min -> PASS | FAIL | NOT YET (rows only) -> summary + next-action line + fixed footer
   |
   v
later (no approval, no dispatch): the agent re-grades with the same read-only script under `doppler run`;
scripts/followthroughs/web2-luks-live-6931.sh grades the soak.
```

### The contracts

**Workflow `.github/workflows/web-host-reboot.yml`**

| Item | Value |
|---|---|
| trigger | `workflow_dispatch` only |
| inputs | `host` (choice, options: `web-2`), `confirm` (string; must equal `REBOOT-<host>-<digits>`, the digits being the server id), `reason` (string, required; 1 to 200 characters of `[A-Za-z0-9 ._,:#/()-]`, so it cannot carry a newline, a pipe or a workflow command) |
| `run-name` | `web-host-reboot <confirm>: <reason>`: the pending run's title is what the approver sees, so it names the host and the server id first and the free text last |
| permissions | top level `contents: read`, `actions: read` (the approvals lookup); the `observe` job re-declares `contents: read` only |
| job `reboot` | `if: github.ref == 'refs/heads/main'`; `environment: web-platform-infra-apply`; job `concurrency: {group: web-1-swap, cancel-in-progress: false}` (byte-identical literal); `timeout-minutes: 25`; outputs `server_id`, `anchor_epoch` (from the reboot step's own outputs) |
| job `observe` | `needs: reboot`; `if: ${{ always() && needs.reboot.outputs.anchor_epoch != '' }}` (the anchor exists only once the POST was about to be sent, so a refusal skips it and a post-POST failure does not); `concurrency: {group: web-host-reboot-observe, cancel-in-progress: false}`; no `environment`; `timeout-minutes: 55`; never uses the credential action; env holds `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` only |
| exit mapping in `observe` | grade exit 0 (PASS) green; exit 2 (NOT YET) green with a `::notice::` (the expected outcome must not read as a failure); exit 1 (FAIL) red; exit 3, 78 or anything else red |
| env | `TERRAFORM_VERSION` equal to `apply-web-platform-infra.yml`'s (`1.10.5` today), `INFRA_DIR: apps/web-platform/infra` |
| `reboot` steps, in order | 1 validate inputs; 2 checkout (`persist-credentials: false`); 3 setup-terraform (`terraform_wrapper: false`); 4 `./.github/actions/infra-credentials` with both Doppler tokens; 5 backend credentials (`AWS_*` from the loader or `prd_terraform`, heredoc-delimited `GITHUB_ENV` writes, presence check of the repo secret); 6 `terraform init -input=false -lockfile=readonly`; 7 never-pooled reader (step-scoped marker token, writes `verdict=absent`); 8 evidence snapshot (a subshell with an `env -i` allow-list of `PATH`, `HOME`, `TMPDIR` and the three `BETTERSTACK_QUERY_*`; never fails the run on a read fault); 9 `bash scripts/web-host-reboot.sh reboot "$HOST" "$CONFIRM"` (the only step with a Hetzner call); 10 summary (`if: always()`) |
| `observe` steps | validate the two job outputs by regex (`server_id` digits, `anchor_epoch` at most 10 digits); checkout; `bash scripts/web-host-reboot-evidence.sh grade ...`; summary (`if: always()`) |
| forbidden text (non-comment lines) | `-target`, `terraform plan`, `terraform apply`, `curl`, `api.hetzner.cloud`, any SSH client call, any Doppler write verb, `web2-luks-rows`, the claim denylist below |
| input validation sits inside the gated job | accepted deliberately: a typo spends one approval. The mitigation is that the refusals that depend on live state print the live id and the exact corrected `confirm` value (see refusals 7 and 8), and the runbook takes the id from a read-only Hetzner GET, never from state. A separate credential-free `validate` job ahead of the gate is recorded as a taste option in `decision-challenges.md`. |

**`scripts/web-host-reboot.sh reboot <host> <confirm>`** (Hetzner write; never names the rows helper; no write verb other than the one POST; the only other verb is `summary`, which makes no Hetzner call). Refusals, in this order, each a named `::error::` and each proven to write nothing:

| # | Refusal | Message anchor (the test pins it) |
|---|---|---|
| 1 | xtrace on, or `HCLOUD_TOKEN` empty | `refusing to trace`, `exported no HCLOUD_TOKEN` |
| 2 | `host` not on the allow-list (`web-2` only) | `is not on the reboot allow-list` |
| 3 | `confirm` is not `REBOOT-<host>-<digits>` | `confirm must be` |
| 4 | `NEVER_POOLED` is not `absent` | `no never-pooled evidence` |
| 5 | the server lookup is not HTTP 200 with exactly one server, or the server's name differs from the allow-list's name for that host | `could not resolve exactly one server` |
| 6 | the resolved id is not numeric, or equals web-1's id `123931471` | `has web-1's id` |
| 7 | the resolved id differs from the typed id (the message prints the live id and the corrected `confirm`) | `differs from the id typed in confirm` |
| 8 | `terraform state pull` does not hold `hcloud_server.web["web-1"]` (a wrong state object), or its `hcloud_server.web["<host>"]` id is missing or differs from the resolved id (the message prints both) | `differs from the id in the Terraform state` |
| 9 | the POST is not HTTP 201, or returns no numeric action id (a 403 adds the read-only-token hint; Hetzner's own error code names a stopped or locked server) | `reboot ->` |
| 10 | the action ends `error`, or has not ended after 24 polls | `reboot request outcome unconfirmed` |

Order inside the script: the anchor epoch is read and written to `GITHUB_OUTPUT` immediately before the POST (never earlier, never after), so a post-POST failure still hands `observe` an anchor. Refusal 10's message says the request was sent, the reboot may still happen, DO NOT re-dispatch, and grade the rows with the printed command. On success it prints the server id, name, created time, the action result, the anchor epoch and the sentence "reboot request accepted by Hetzner (action <id> success). That means the request was sent; it does not show that the host restarted or came back."

**`scripts/web-host-reboot-evidence.sh`** (read-only; sources the rows helper; no write verb of any spelling):

| Subcommand | Behaviour | Exit |
|---|---|---|
| `snapshot` | prints `pre-request context:` with the newest readiness row's boot_id and age, the newest probe row's class, boot_id and age, and the newest journald boot (id, row count, age of its newest row); a read fault prints `unavailable` and still exits 0 | 0; 3 when credentials are absent |
| `grade --anchor <epoch> [--window-min <n>] [--poll-s <n>]` | loops until a wall-clock deadline (never an iteration count) or a PASS/FAIL; each iteration reads the runner clock BEFORE issuing its queries; prints the baseline, the boots seen after the request, the latest probe row (class, boot_id, age), one `verdict:` line, a `next:` line and the fixed footer; `--window-min 0` is a single read (the local re-grade form) | 0 PASS, 1 FAIL, 2 NOT YET, 3 cannot establish, 78 xtrace |

Loading mirrors the grader: the script checks the three `BETTERSTACK_QUERY_*` variables are non-empty (exit 3 before any query), then sources the helper and requires `declare -F` for every helper function it calls (`w2l_fetch_probe`, `w2l_fetch_ready`, `w2l_query`); a missing function is exit 3 `CANNOT ESTABLISH`, because a bare presence check after `source` is satisfied by an inherited environment value.

Three reads per iteration, all through the helper's `w2l_query` (the same hot-plus-cold union):

1. the newest well-formed readiness row for the host, of ANY verdict (`classify_ready` with `kind == "row"` and `host` equal), for its boot_id and age;
2. the probe rows (`w2l_fetch_probe`, 48 h lookback), reduced with `classify_probe` to the newest row's class, boot_id and age, ignoring rows whose `age_s` did not parse (a `junk` row is a read-shape fault, never evidence);
3. one new query over the host's journald rows: per distinct `_BOOT_ID` over the last 48 h, the row count, the age of the first row and the age of the newest row. The `_BOOT_ID` journald field is set by journald itself (an underscore-prefixed trusted field a local process cannot forge), is shipped by Vector in `raw`, and was measured present on all four boots the host showed in the last 30 h on 2026-10-07. A host with no readable `_BOOT_ID` rows yields a read fault, never a verdict. The probe row's `boot_id` has dashes and the journald id has none; both are compared lowercased with dashes removed.

The verdict is a pure function over (newest readiness row, newest probe row, the boot list, seconds since the request measured at the START of the iteration), so it is tested without the network. A boot BEGAN after the request when the age of its first row is below the seconds since the request. Order, first match wins:

| Condition | Verdict |
|---|---|
| a well-formed readiness row is younger than the request | `NOT YET reason=instance_recreated_after_request` (the host was re-created, not rebooted; the run says to re-run after the new instance) |
| any of the three reads faulted and no verdict was reached | `NOT YET reason=read_fault` (a read fault never FAILs, mirroring the grader; the summary's first line says nothing was measured) |
| no boot began after the request | `NOT YET reason=no_new_boot_seen` (keeps polling until the deadline; at the deadline the `next:` line says the request was ignored or the host is dark and points at the runbook's dark-host path) |
| a boot began after the request AND the newest probe row is FAIL-shaped or malformed AND it is younger than that boot's first row | `FAIL reason=probe_fail_row_after_new_boot` (the comparison uses ages from back-to-back reads with the clock read first; a margin of 120 s is resolved toward NOT YET). FAIL rows carry no boot_id, so "younger than the new boot's first row" is what rules out a late row from the pre-request boot. |
| a boot began after the request AND the newest probe row is OK-shaped, younger than the request, and its boot_id equals a boot that began after the request | `PASS reason=probe_row_on_a_boot_that_began_after_the_request` |
| a boot began after the request, otherwise | `NOT YET reason=new_boot_seen_probe_pending` (the expected result most days; the `next:` line gives the next probe window, 00:00 to 00:30 UTC, and the filled-in local re-grade command) |

PASS, FAIL and NOT YET are row-presence states and are worded so: the PASS line says "a probe row of the OK class was seen on a boot that began after the request" and is printed as `PASS (row presence only)`. The stricter grading (device type, mapper path, escrow, three soak days) stays in `web2-luks-live-6931.sh`, and the word PASS here is never evidence for that grading. A FAIL row also spoils the #6931 soak by the grader's own rule (any non-green probe row at or after the readiness row), which the runbook states with its recovery.

**Fixed footer, printed on every exit path of both scripts and in both summaries (verbatim, pinned by test):**

`This run reports rows only. It makes no statement about the volume or its encryption; grading belongs to scripts/followthroughs/web2-luks-live-6931.sh.`

**Claim denylist** (case-insensitive, over the output of every fixture scenario in both suites, footer included, AND over the print statements of the workflow and both scripts: lines that call `echo`, `printf`, `say`, `fail`, a `::notice::`, `::warning::` or `::error::` annotation, or append to a summary): `LUKS-backed`, `encrypted`, `reborn`, `reopen`, `proof`, `verified`, `confirmed`, `proves`, `crypto_LUKS`, `/dev/mapper`, `luks=1`, `escrow=ok`. Row contents are never echoed; only class, boot ids, ages and counts are. Error wording uses "evidence" where a denylisted word would otherwise read naturally.

## Technical Considerations

- **Why two jobs.** A 40-minute poll must not hold the Tier-B credential or the `web-1-swap` mutex, and the poll needs no Hetzner token (the brief asks that the workflow poll; the one-job alternative is recorded as a user-challenge and not adopted). Cost: two values cross the job boundary as outputs, each re-validated by regex before use.
- **Concurrency while waiting for approval (unverified, so verified at work time).** Job-level concurrency is claimed when the job is queued, which may be BEFORE the environment approval wait ends. If so, an unapproved reboot run holds `web-1-swap` and a release deploy or host job queues behind it, and a newer pending run displaces an older pending one in both directions. Phase 0 reads GitHub's concurrency and environment documentation and records the verified behaviour in the runbook; if the documentation is silent the runbook states it as unverified and says to cancel an unapproved dispatch promptly. The mutex stays because a web-2 create, replace or rebirth and the release deploy are the writers a reboot must not interleave with.
- **Why `web-1-swap` and not the apply serializer.** It is the mutex every host create, replace and rebirth job and the release deploy hold. The job reads state but writes none, so the lockless-state serializer is not needed and would queue the reboot behind long applies.
- **Credential posture, stated at its real width.** The loader exports the WHOLE Tier-B project into `GITHUB_ENV` for every later step of the `reboot` job, not just `HCLOUD_TOKEN`. So the job's steps all hold Tier-B values, the marker token (read/write today, #9358) shares a job with the Hetzner write token in the never-pooled step exactly as in the rebirth workflow (the G3 census, not the token, constrains it), and the snapshot step is wrapped in an `env -i` allow-list subshell so the Better Stack reader receives only its own three variables (an allow-list, never an `env -u` deny-list). The `observe` job never uses the loader and receives no Tier-B value. The loader's legacy arm exports the read-only Hetzner token first, and the POST then answers 403, which the script names.
- **Token handling.** The Hetzner token travels on curl's stdin config only, never argv; `::add-mask::` goes to stderr; every annotation is `%`, CR and LF escaped; every `GITHUB_OUTPUT` value is one line; the free-text `reason` is charset-restricted at validation and passes through `clean()` before it reaches the summary table.
- **Terraform client.** The `state pull` output is piped straight into one field-selecting `jq` program (the state holds passphrases) and nothing from it is printed or written, as in `state_ident`; the wrong-state-object check (`web-1` present) is ported with it.
- **What a run does not show.** Hetzner's `success` for the reboot action means the ACPI request was sent. A guest that ignores ACPI produces `no_new_boot_seen`, and a host that restarts and then goes dark produces `new_boot_seen_probe_pending` followed by silence; the `next:` lines and the runbook distinguish them by the boot list.
- **The brief's "never claim" rule and the boot signal.** The boot list is rows (journald rows already shipped to Better Stack), read through the same query function as every other read; it adds no host access and forces nothing. Its output is a count and ids, never a statement about the volume.
- **Hetzner response shape.** The curl shim replays the real server object (`id`, `name`, `status`, `created`, `volumes`, `rescue_enabled`, `locked`; measured `running` for web-2 on 2026-10-07 through the read-only token) and the real action object (`action.id`, `action.status` in `running`, `success`, `error`), not a reduced one.
- **Marker consequences.** The soak-marker writer (`workspaces-luks-verify.yml` job `web2_marker`) can earn `WORKSPACES_LUKS_CUTOVER_AT` once a green readiness row and a probe row on a different boot exist. After that the never-pooled gate refuses every later reboot by design. The runbook says so and the refusal message from the never-pooled reader (present versus unreadable) is shown verbatim in the job log.
- **Retirement coupling.** The workflow depends on `scripts/web2-rebirth-never-pooled.sh` and copies helpers from `scripts/web2-rebirth.sh`; both retire in the closing change, so this workflow retires with them. A self-expiring tombstone row in the workflow suite makes a half-retirement fail CI: if either of those two scripts is absent, every `web-host-reboot*` file must be absent too.
- **Doc linter.** `scripts/lint-infra-no-human-steps.py` scans plans, specs and runbooks and flags a human-actor word within a line of a reboot or mount word. This plan and the runbooks use "agent", "owner" and "dispatcher" instead, and the work phase runs the linter (the CI form) over every changed doc.

## Implementation Phases

Order is test-first (`cq-write-failing-tests-before`): the suites are written and seen RED against absent subjects before the subjects exist.

### Phase 0: read-before-write (no edits)

1. Read all three C4 files in full: `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`.
2. Re-read live state before writing any sentence about it: `gh run view 37508997529` and `gh run view 37516716515` (step conclusions), `gh api repos/jikig-ai/soleur/actions/workflows/<file> --jq .state` for the two push-apply workflows and the rebirth workflow, `gh issue view 9372 6931 9669 9572 --json state`, the marker's name membership (`doppler secrets --only-names --json -p soleur -c prd_workspaces_luks_marker`, count of the exact name only), and a read-only Hetzner GET for the live server.
3. Re-run the assembly census: `grep -rln 'actions/reboot' scripts .github apps --include='*.sh' --include='*.yml' --include='*.py'`; record the exact set in the suite as the expected set.
4. Confirm the loader still exports `AWS_*` from the Tier-B pair (`grep -n 'AWS_ACCESS_KEY_ID' .github/actions/infra-credentials/action.yml`) and that `web-platform-infra-apply` still carries a `main`-only branch policy and a required reviewer (`gh api repos/jikig-ai/soleur/environments/web-platform-infra-apply`).
5. Verify the concurrency-versus-approval behaviour from GitHub's documentation (WebFetch of the concurrency and deployment-environment pages) and record the verified sentence, or the explicit "unverified", for the runbook.
6. Re-measure the journald boot list and the readiness and probe rows through the helper (the same read-only queries the evidence script will run) and keep the output as the fixture shapes; the fixtures model the real emitted JSON (quoted-integer ages, `[luks-monitor]`-prefixed copies).

### Phase 1: RED

1. `scripts/web-host-reboot.test.sh`: a fake world (curl shim for Hetzner and Better Stack, terraform shim, gh shim) driving both scripts; scenarios in Test Scenarios; a mutation battery run on COPIES.
2. `apps/web-platform/infra/web-host-reboot-workflow.test.sh`: parses the YAML and executes extracted step bodies under `bash --noprofile --norc -e`.
3. Run both: every row is RED because the subjects are absent. Record the count of RED rows in the PR notes.

### Phase 2: scripts

1. `scripts/web-host-reboot.sh` (helpers copied from `web2-rebirth.sh`; one `cmd_reboot`; `summary`).
2. `scripts/web-host-reboot-evidence.sh` (`snapshot`, `grade`; the pure verdict function; the footer constant; the boot-list query).
3. Add `scripts/web-host-reboot-evidence.sh` to `READERS` in `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` (and to its synthetic-root control if that lists readers).

### Phase 3: workflow

1. `.github/workflows/web-host-reboot.yml` per the contract table; the file header states what it never claims, the retirement rule and the dispatch rule (every dispatch needs the owner's separate go-ahead).
2. `bash scripts/lint-workflows.sh .github/workflows/web-host-reboot.yml` and the repo's `lint-workflow-*` linters over it.

### Phase 4: registration and censuses

1. `scripts/test-all.sh`: one `run_suite "scripts/web-host-reboot"` line beside the `web2-rebirth` lines; `python3 scripts/regenerate-shard-manifest.py --incremental --write` and the `--group infra` form for the four TSV files.
2. `scripts/guard-vacuity-floor.test.sh`: the `apps/web-platform/infra/` directory is in its deferred set with a shrink-only ledger, so a floor-bearing infra suite either gets a per-file `PROMOTED_FILES` entry (the established remedy; never a raise of `MAX_DEFERRED`) or is written without a counter-versus-threshold conditional opener; the `scripts/` suite's floor is shaped so the gate can build a mutant (a literal bound beside the check, reported by a direct `printf` and `exit 1`, not through `fail()`).
3. `apps/web-platform/infra/run-registered-suites.sh`: a `_SUITE_BOUNDS` pin only if the measured runtime of the workflow suite exceeds the 360 s default.
4. `scripts/lib/test-affected-paths.sh`: only if `scripts/lint-orphan-test-suites.sh` reports the new suite unclassified (derivation by argv literals and the `<x>.test.sh -> <x>.sh` stem should cover it).
5. `plugins/soleur/test/preflight-discoverability-test.test.ts`: `BASELINE_DECLARED_PROBES` 47 to 48 with a dated PLACEMENT / TRUTH / NO SUBSTITUTE comment in the established shape (this plan declares `credentials_required`; the corpus already counts it, so the G1 row is red until the bump; re-read the constant at work time because a sibling PR may have moved it).
6. `plugins/soleur/test/fixture-relative-assert.baseline.txt`: only if its lint names a new suite.

### Phase 5: documentation and architecture records

1. New runbook `knowledge-base/engineering/operations/runbooks/web-host-reboot.md` (dispatch inputs and the id lookup from a read-only Hetzner GET, the watch, reading PASS/FAIL/NOT YET and the `next:` lines, the local re-grade command, the FAIL branch, the dark-host path with a bare `image_tag` and its consequences, the marker consequence, the concurrency note, the wording rules, retirement).
2. `web2-luks-rebirth-9372.md`: a dated status correction, a pointer section, and the row-5 edit.
3. `infra-credential-tiers-8209.md`: two inventory rows and a dated note.
4. ADR-263: a short dated addendum paragraph (capability, claim discipline, retirement rule; no new Alternatives rows). ADR-241: a one-line dated entry in its amendment or consumer log if it carries one.
5. `model.c4`: extend the `github -> hetzner` and `github -> betterstack` edge prose by a half-sentence each (cited by edge text, never by line number); `bash scripts/regenerate-c4-model.sh`; run the C4 tests.

### Phase 6: verification (all local, no dispatch)

Run both new suites; `bash plugins/soleur/test/c4-count-parity.test.sh`; `bun test plugins/soleur/test/terraform-target-parity.test.ts`; `bash apps/web-platform/infra/nic-wait-gate.test.sh`; `bash apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh`; `bash scripts/guard-vacuity-floor.test.sh`; `bash tests/scripts/test-infra-privileged-tier-census.sh`; `bash scripts/lint-orphan-test-suites.sh`; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`; `python3 scripts/lint-guard-contract.py`; `bash scripts/lint-workflows.sh`; the repo's workflow linters; the `apps/web-platform/test/c4-*.test.ts` pair.

### Phase 7: PR

The PR body's FIRST line answers "does merging this alone mutate production?": no, the workflow is dispatch-only (no push or schedule trigger), there is no `.tf` change, and nothing was dispatched. It carries `Ref #9372` (never `Closes`) and records the dispatch as the owner's separate go-ahead tracked on #9372. No label or milestone change on #9372. A new workflow cannot be dispatched from a feature branch before it exists on the default branch, so no pre-merge dispatch is planned or possible; the shape suites and the shim worlds are the pre-merge evidence.

## Files to Create

- `.github/workflows/web-host-reboot.yml`
- `scripts/web-host-reboot.sh`
- `scripts/web-host-reboot-evidence.sh`
- `scripts/web-host-reboot.test.sh`
- `apps/web-platform/infra/web-host-reboot-workflow.test.sh`
- `knowledge-base/engineering/operations/runbooks/web-host-reboot.md`
- `knowledge-base/project/specs/feat-one-shot-web-host-reboot-9372/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-web-host-reboot-9372/decision-challenges.md`

## Files to Edit

- `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` (`READERS`: add the evidence script; leave the census otherwise untouched)
- `scripts/test-all.sh` (one `run_suite` line)
- `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv`, `apps/web-platform/infra/suite-shard-legs.tsv`, `apps/web-platform/infra/suite-durations.tsv` (regenerated, incremental)
- `scripts/guard-vacuity-floor.test.sh` (per-file promotion, only if the infra suite carries a floor of the shape it measures)
- `apps/web-platform/infra/run-registered-suites.sh` (a timeout pin, only if measured above the default)
- `scripts/lib/test-affected-paths.sh` (only if the orphan census asks)
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (`BASELINE_DECLARED_PROBES`)
- `knowledge-base/engineering/operations/runbooks/web2-luks-rebirth-9372.md`
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`
- `knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md`, and `ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md` (one dated line)
- `knowledge-base/engineering/architecture/diagrams/model.c4` and the generated `model.likec4.json`

Path verification (`hr-when-a-plan-specifies-relative-paths-e-g`): every Edit path above was confirmed present with `git ls-files` during planning, and every Create path was confirmed absent (`git ls-files | grep web-host-reboot` is empty).

## Open Code-Review Overlap

Open `code-review` issues whose body names a planned file: #8659 (test suites replace test-helpers' composed EXIT trap) and #7942 (two mutation batteries named `*.mutation.sh` run in no gate) name `scripts/test-all.sh`; #8800 (census sandbox shares inodes with the live repo) names `scripts/lib/test-affected-paths.sh`. Disposition for all three: **Acknowledge**. The new suites install their own `trap` and do not source `test-helpers.sh`, they are named `*.test.sh` and registered, and none clones a sandbox from the live tree. None is folded in or deferred; they stay open.

## User-Brand Impact

- **If this lands broken, the user experiences:** the live origin (web-1, the one host serving every customer's session and workspace) is soft-rebooted: every in-flight agent session drops, and the reboot exercises a LUKS reopen on the production host that has never been rehearsed there, so a failed reopen leaves every customer's workspace unavailable. A broken evidence reader instead produces a false belief (a "PASS" read as "web-2 is encrypted") that reaches a compliance record or a customer-facing sentence.
- **If this leaks, the user's workflow and data are exposed via:** the Tier-B Hetzner write token (root-equivalent over the production project: it can delete every server and volume that holds customer workspaces). Vectors: an `HCLOUD_TOKEN` value in argv, in a log line or in the step summary; a job that is reachable from a branch other than `main`; a free-text `reason` or API field that injects a workflow command into the run log or the approval prompt; the marker-config token (read/write today) sharing a job with the Hetzner token; the whole Tier-B project exported to every step of the gated job.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one mis-targeted reboot of web-1, or one leaked Tier-B token, costs the brand outright, and this change adds a new consumer of that token, so it is not `aggregate pattern`; CPO signed off on this framing at plan time (advisory 2026-10-07: the blast radius of a mis-target and the new consumer of a root-equivalent token set the tier, and the roadmap already treats comparable items as P1 single-user incidents).

`requires_cpo_signoff: true` is set in the frontmatter; `soleur:engineering:review:user-impact-reviewer` runs at review time. The approval prompt names the target: `run-name` carries the host, the typed server id and, last, the charset-restricted reason.

## Observability

```yaml
liveness_signal:
  what: "the run's own job conclusions and step summaries (reboot job: the Hetzner action result; observe job: the verdict line, the next line and the fixed footer) plus the Better Stack journald boot rows, probe rows and readiness rows the observe job reads"
  cadence: "per dispatch; the evidence is re-readable at any time with the same read-only script, and the daily luks-monitor probe row is the long-cadence signal"
  alert_target: "the dispatching agent (a Monitor on the run) and the owner's environment approval notification; the soak-gated closure on #6931 flags a never-arriving probe through its needs-attention label"
  configured_in: ".github/workflows/web-host-reboot.yml, scripts/web-host-reboot.sh, scripts/web-host-reboot-evidence.sh, scripts/followthroughs/web2-luks-live-6931.sh"

error_reporting:
  destination: "GitHub Actions annotations (::error::) and the job summary; no Sentry (a one-off dispatch has no cadence to miss, and a heartbeat would move the model.c4 count claims)"
  fail_loud: "a named ::error:: line per refusal (the ten anchors in the contracts table), a red job on refusal, FAIL and exit 3, and a verdict: line plus a next: line on every observe exit path"

failure_modes:
  - mode: "approval never given, or the queued run is displaced from the web-1-swap pending slot"
    detection: "gh run list shows the run waiting, or absent; the runbook's watch step names both and says to cancel an unapproved dispatch"
    alert_route: "the dispatching agent, via the Monitor it arms on the run"
  - mode: "the Hetzner write verb answers 403 because the loader exported the read-only token"
    detection: "the reboot step's ::error:: names the 403 and the read-only-token cause"
    alert_route: "job failure on the dispatching agent's Monitor"
  - mode: "the request is accepted but the action poll times out, or the POST errors after being sent"
    detection: "refusal 10's message says the outcome is unconfirmed and not to re-dispatch; observe still runs because the anchor was written first"
    alert_route: "the run summary; the agent grades the rows"
  - mode: "no boot began after the request (the guest ignored the request, or the host is dark before shipping rows)"
    detection: "verdict NOT YET reason=no_new_boot_seen at the deadline with a next: line naming the dark-host path"
    alert_route: "the dispatching agent reads the summary and follows the runbook's web_host_replace path; the owner approves it"
  - mode: "a boot began but the host then goes dark, or the probe never arrives"
    detection: "verdict NOT YET reason=new_boot_seen_probe_pending, then scripts/followthroughs/web2-luks-live-6931.sh later reports NOT YET and FAIL once earliest plus four days passes"
    alert_route: "the follow-through sweeper's tracker on #6931 (needs-attention label on SLA breach)"
  - mode: "Better Stack cannot be read (transport, 5xx, 429, credentials)"
    detection: "verdict NOT YET reason=read_fault with the summary's first line saying nothing was measured; never FAIL"
    alert_route: "the run summary; re-grade locally later"
  - mode: "a replace of web-2 lands between dispatch and approval"
    detection: "refusal 7 or 8 before any write, printing the live id and the corrected confirm"
    alert_route: "job failure; re-dispatch with the printed value"

logs:
  where: "GitHub Actions run logs and step summaries; Better Stack Logs warehouse for the rows themselves"
  retention: "GitHub run logs about 90 days (copy the summary into the closing change, as the rebirth runbook already instructs); Better Stack hot table plus the cold archive for the rows"

discoverability_test:
  command: bash scripts/web-host-reboot-evidence.sh snapshot
  expected_output: "pre-request context:"
  credentials_required: "BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD (Doppler soleur/prd_terraform) - web-2's journald boot, probe and readiness rows land only in the Better Stack Logs warehouse, which has no unauthenticated read path"
```

Layer citation (`hr-observability-layer-citation`): the reboot job's failures surface at the CI layer (GitHub Actions annotations and summaries); the host's own behaviour surfaces at the Better Stack Logs layer (journald rows shipped by Vector) and is read from outside the host with no SSH; the grader is the follow-through sweeper. The new reader emits its evidence before it exits on every path (a fail-closed gate must report first).

## Guard Contract

### Guard 1 — Reboot target gate

**Property.** A reboot request can reach only a server that is on the allow-list, is not web-1, has the id the dispatcher typed and the id Terraform state holds, and only while the never-pooled evidence reads `absent`; every refusal happens before the one write.

**Assembly.** The single POST site is `cmd_reboot` in `scripts/web-host-reboot.sh`; the chokepoint every request flows through is its refusal sequence (xtrace and token, allow-list, typed confirm, never-pooled, by-name lookup, web-1 id, typed id, state id), which runs before the POST. Other places a reboot could be issued, enumerated at plan time: `scripts/web2-rebirth.sh` (the rebirth workflow's own step, retiring), the new workflow's run bodies (must hold no Hetzner call at all), and the infra scripts (`grep -rln 'actions/reboot'` over scripts, `.github` and apps finds no other POST site). The suite carries that grep as a census row with the expected set recorded at work time, so a third site is RED. The allow-list is named in three places that must agree: the script's `case`, the workflow's `host` options and the suite's expected set.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | drop the web-1 id refusal | RED |
| 2 | drop the typed-id comparison | RED |
| 3 | drop the Terraform-state id comparison | RED |
| 4 | drop the never-pooled requirement | RED |
| 5 | REORDER: move the POST above the state-id comparison (a delete-only mutation would also red the happy path; this one reds only a scenario that observes the write at POST time, the state-mismatch scenario) | RED |
| 6 | add a SECOND POST site after the compliant first (a loop over every allow-listed host, or a retry that re-POSTs) | RED (one-write assertion and the census row) |
| 7 | the guard's own dispatch: skip half the refusal scenarios (the suite carries a floor on the count of refusal scenarios that ran and asserted "nothing written") | RED |
| 8 | widen the allow-list in the script only (`web-1` added) while the workflow options and the suite's expected set stay | RED |
| 9 | write the anchor to `GITHUB_OUTPUT` after the POST instead of before | RED (the post-POST-failure scenario finds no anchor) |

**Harness rows.** (a) Neuter the curl shim so a POST records nothing: the happy-path row (exactly one recorded write, to the right id) must go RED. (b) A must-PASS input that is not the canonical world: a nine-digit id shaped like the live one (`169095540`), a creation time with a non-UTC offset, and a typed confirm built from the same id; the gate must let it through.

**Anchor.** The id comparison is live Hetzner against live Terraform state, and the state object lives in R2 outside the commit, so a diff cannot move both. The allow-list and the web-1 constant are in-commit by design; a widening is the reviewable diff, and it must edit the script, the workflow options and the suite's expected set together.

### Guard 2 — Claim-free output

**Property.** No byte the change prints or writes to a job summary asserts or implies what the volume is, and every exit path ends with the fixed footer.

**Assembly.** Every sink: stdout and stderr of both scripts, every `GITHUB_STEP_SUMMARY` append from either script, every print statement in the workflow's run bodies, and `run-name`. The chokepoint is a static scan of the print statements of the workflow and both scripts plus a dynamic scan of the combined output of every fixture scenario in both suites. The runbook is prose and is covered by review and one acceptance-criteria grep for its fixed sentences, not by the denylist (it must be allowed to say what the run does NOT show).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | add a line asserting the volume state to the PASS path of the evidence script | RED |
| 2 | reword PASS to use a denylisted word (`verified`, `confirmed`) | RED |
| 3 | add a `::notice` carrying a denylisted word to the workflow | RED (static scan) |
| 4 | drop the footer from the NOT YET exit path only | RED (per-path footer assertion) |
| 5 | echo the raw row message in the latest-row line (the fixture rows carry the denylisted tokens) | RED (dynamic scan) |
| 6 | the guard's own dispatch: the dynamic scan runs over zero scenarios | RED (floor on scenarios scanned) |

**Harness rows.** A positive control: the same scan over a copy of an output with one planted denylisted token must report it. A must-PASS input that is not the canonical: output wording that uses the words "volume" and "encryption" only inside the footer, and the words `PASS (row presence only)`, passes the scan.

**Anchor.** None stored. The denylist lives in both suites, so weakening it means editing two files in one diff; the acceptance criteria repeat the list so a reviewer sees a weakening against a third copy.

### Guard 3 — Reader and writer stay separate (the census allow-list edit)

**Property.** The file that can issue the Hetzner write never names the rows helper, and every file that names the helper is on the reader allow-list and carries no write verb of any spelling.

**Assembly.** The census in `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` walks the whole tree; its `READERS` set is the allow-list this change widens by exactly one entry. Files in play: `scripts/web-host-reboot.sh` (writer: must not name the helper), `scripts/web-host-reboot-evidence.sh` (reader: on the list, no verb), the workflow YAML (must name neither the helper nor a verb-bearing reader), and every existing reader.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | source the helper from `scripts/web-host-reboot.sh` | RED (census flags it) |
| 2 | add `curl -X POST` to the evidence script | RED (a reader carrying a verb) |
| 3 | remove the evidence script from `READERS` (the guard's own dispatch: the new reader becomes unlisted) | RED |

**Harness rows.** The existing planted-census battery already plants each shape; this change adds one row planting the evidence script's real path with a verb. A must-PASS input that is not the canonical: the evidence script mentioning `POST` only in a comment passes (the census drops comment lines).

**Anchor.** `READERS` is in-commit. The independent anchor is the census suite's own planted battery plus review of the one-line diff; no stored hash is involved.

### Guard 4 — The observe job holds no credential, and the write step is last and single

**Property.** The Hetzner write credential and the marker-config token are reachable only by steps of the environment-gated job, the one Hetzner-calling step runs only after every read-only refusal step, and the `observe` job holds neither.

**Assembly.** Every step of both jobs, found by parsing the YAML (not by grep); every `uses:`; every `env:` at workflow, job and step scope; the job list. The chokepoint is the suite's step classification: every step with a run body is on the read-only list or the write list, so a new step cannot arrive unclassified.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | use the credential action in `observe` | RED |
| 2 | REORDER: move the reboot step above the never-pooled step | RED |
| 3 | add a Hetzner call (a `curl` or the API host) to a run body other than through the script | RED |
| 4 | add a third job | RED (the job list is exactly `reboot`, `observe`) |
| 5 | add a SECOND write-capable step after the compliant first | RED (exactly one step may call the reboot subcommand) |
| 6 | the guard's own dispatch: a step list of length zero | RED (floor on classified steps) |

**Harness rows.** A planted unclassified step must be reported by the classification; a must-PASS input that is not the canonical: a new read-only validation step inserted before the credential loader (allowed by the contract) passes.

**Anchor.** None stored; the environment's reviewer set and `main` branch policy are Terraform-managed (`web-host-birth-environment.tf`) and guarded by the DP-11 F8 test, which is outside this diff.

## Architecture Decision (ADR/C4)

Detection: this change adds a new consumer of the Tier-B credential boundary and a new agent-dispatchable production write capability, with a stated end of life. That is an extension of ADR-263 and a consumer of ADR-241, not a new decision of its own.

### ADR

Amend ADR-263 (guest-side fresh-boot LUKS for web hosts) with a short dated addendum (no new ordinal, so no ordinal-collision exposure): "2026-10-07: an agent-dispatchable, reviewer-gated soft reboot of the allow-listed web-2 standby (`web-host-reboot.yml`) is the sanctioned path for the graded reboot evidence; it reports rows only and states nothing about the volume; it depends on the never-pooled reader and is retired in the rebirth closing change with its tests, or kept only by a recorded owner decision". No new Alternatives rows (the two rejected routes live in the runbook and the Cut List). ADR-241 gets a one-line dated entry naming the new Tier-B consumer if it carries an amendment or consumer log. These are tasks in Phase 5, not follow-ups.

### C4 views

Container-level relationships: the `github -> hetzner` edge (its prose names which workflows write through the edge) gains the reboot job's single environment-gated soft reboot of the allow-listed web-2 server, and the `github -> betterstack` edge (the polling edge) gains the observe job's read. No new element, no new tag, no `views.c4` include change; both edges are cited by their prose, never by line number. Phase 0 reads all three `.c4` files in full and records the enumeration the completeness mandate requires: (a) human actors: the owner as environment reviewer and the dispatching agent (the owner actor already has an approval edge into `github`; the environment reviewer approval is covered by prose on the `github -> doppler` Tier-B edge, which the work phase re-reads and extends by half a sentence only if it names the host environments); (b) external systems: Hetzner Cloud API, Better Stack Logs, Doppler (Tier-B project), GitHub (all four already modeled); (c) data stores touched: the Terraform state object in R2 (read only; already implicit in every apply edge); (d) actor-to-surface changes: none. After the edit: `bash scripts/regenerate-c4-model.sh`, then `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`, then `bash plugins/soleur/test/c4-count-parity.test.sh` (expected unchanged: the workflow uses neither `actions/sentry-heartbeat` nor an email emitter).

### Sequencing

The ADR addendum describes the final state and lands in the same PR; nothing here waits on a later slice.

## Infrastructure (IaC)

No new infrastructure resource: the workflow file is the only new deployable, the `web-platform-infra-apply` environment is already Terraform-managed (reviewer set guarded by the DP-11 F8 test), the credentials already live in Doppler, and no `.tf` file, secret, vendor account, systemd unit, DNS record or firewall rule is touched. The detection scan of the plan text found no manual-provisioning phrasing, so `soleur:engineering:infra:terraform-architect` was not invoked. The run needs no secret that does not already exist; any Doppler write, token mint or Terraform apply would be a separate change.

## Domain Review

**Domains relevant:** Engineering, Legal, Operations, Product (advisory only: the single-user-incident sign-off; no UI surface)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The design is sound and the two-job split is justified. Findings applied: keep the never-pooled refusal (High); the census traps (reader allow-list and the `KEY`/`VERB` regexes) are the highest-probability red, so the helper is named only by the read-only file; no `-target` text anywhere in the workflow (`nic-wait-gate.test.sh` greps every workflow); `observe` needs a structural test (no environment, no Hetzner token, no Doppler); job-level `web-1-swap` is the right mutex, with the pending-slot eviction documented; validate the cross-job outputs by regex. Not applied: the CTO's preference to source `cmd_reboot` instead of copying it, because `web2-rebirth.sh` runs its dispatcher at source time and both files retire together (a parity row pins the copied helper bodies equal while both exist).

### Legal (CLO)

**Status:** reviewed
**Assessment:** Low risk if the wording is pinned. Findings applied: no row contents echoed (class, ids, ages and counts only), a fixed verbatim footer on every exit path, a claim-word denylist enforced statically and per fixture, nothing touching the ledger, the Article 30 record, the posture document or `hcloud_volume.workspaces` (#9572 owns those), and a runbook sentence that a run summary is not evidence for any record. One recommendation is adapted: the CLO suggested not using the word PASS at all; the brief asks for PASS/FAIL/NOT YET, so the words stay but are printed as `PASS (row presence only)`, are never called a proof, and the footer names the real grader.

### Operations (COO)

**Status:** reviewed
**Assessment:** No cost change (about 45 runner minutes a dispatch). Findings applied: name the dispatch watch (a Monitor, never a foreground watch), put the dark-host path in the runbook (`web_host_replace` with a bare `image_tag` until #9669 lands, the tag taken from web-1's `/health` `.version`), state that `new_boot_seen_probe_pending` is the expected result and must not be retried to force a row, add the workflow to closing-checklist row 5, and name the approver context (the run title carries host and id). Not applied: a `plan_only` default (Cut List: it would cost a second approval for no write it prevents).

### Product (CPO)

**Status:** reviewed
**Assessment:** Signs off on `single-user incident`. Failure modes in priority order: web-1 rebooted (layered refusals, fail-closed, tested); an approval racing a replace of web-2 (typed id plus state id); a false PASS reaching a belief or record (rows-only wording, footer, denylist); an approver who cannot see the target (run title names it). Product concern recorded: the published data protection disclosure already states, in the present tense, that the serving host's volume is LUKS-encrypted; that is a claim about web-1, a web-2 PASS is not evidence about web-1, and nothing here feeds public wording. No UI surface, so no wireframe and no spec-flow UX run: the tier is NONE for the Product/UX gate and the CPO input above is the sign-off, not a UX review.

## Plan Review Disposition (2026-10-07, six reviewers)

Reviewers: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, and a CTO devex lens. Consolidated by class per ADR-084.

Applied (mechanical, one right answer):

- PASS rested on a proxy (a boot id absent from a known set): replaced by the journald `_BOOT_ID` signal, so PASS needs a probe row on a boot that BEGAN after the request, and a pre-request snapshot read fault can no longer yield a PASS (spec-flow P0, architecture P1).
- The anchor is written before the POST and `observe` runs on it (spec-flow, Kieran, architecture): a post-POST failure no longer strands the run, and the failure message says not to re-dispatch.
- NOT YET exit 2 maps to a green job with a `::notice::`; every verdict prints a `next:` line with the filled-in local re-grade command (CTO, Kieran, spec-flow).
- The verdict function filters `kind == "row"`, takes the readiness baseline from the newest well-formed row of any verdict, and reads the runner clock before each query (Kieran P1).
- The `status == running` refusal was cut (DHH, simplicity: Hetzner's own 4xx names a stopped or locked server and nothing was written yet); the wrong-state-object check was ported (architecture).
- FAIL is judged against the new boot's first row, which removes the late-pre-reboot-row false FAIL (Kieran, spec-flow).
- The census list in Phase 6 gained `guard-vacuity-floor.test.sh` and `test-infra-privileged-tier-census.sh`; a suite-timeout pin is conditional on a measurement (Kieran, architecture).
- The snapshot step runs in an `env -i` allow-list subshell; the credential-posture paragraph states the real width of the loader's export (architecture).
- `run-name` leads with host and id and ends with a charset-restricted reason; refusals 7 and 8 print the live id and the corrected confirm (architecture, spec-flow).
- The mutation batteries were trimmed to the rows that test a property (Guard 1 from 10 to 9, Guard 2 from 7 to 6, Guard 3 from 5 to 3, Guard 4 from 7 to 6) (DHH, simplicity).
- Retirement: row 5 is a literal deletion list, sequenced after the #6931 PASS, with tombstone rows in the workflow suite and the helper-parity row tied to the rebirth scripts' presence (CTO, architecture, spec-flow). The ADR addendum lost its Alternatives rows and C4 edges are cited by text, not line number (DHH, Kieran).
- The measured marker state, the journald boot list and the concurrency-versus-approval question are recorded (architecture P1).

Persisted as decisions for the owner, not silently applied: see `knowledge-base/project/specs/feat-one-shot-web-host-reboot-9372/decision-challenges.md` (keeping the `observe` job and the `host` allow-list against DHH, simplicity and CTO; keeping in-job input validation; keeping the C4 and ADR records against the CTO's lighter-touch taste; keeping `credentials_required`).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "a new workflow_dispatch workflow (e.g. web-host-reboot.yml) with a typed confirm input, a required reason, and the same Tier-B environment reviewer gate as the sibling host workflows; the agent dispatches it, the environment approval stays with the owner" [brief] | Workflow contract table; Phase 3; `.github/workflows/web-host-reboot.yml` | mapped |
| 2 | "Reuse the by-name server resolution and refusals from web2-rebirth.sh cmd_reboot: resolve exactly one server by name, refuse web-1's id, refuse if the id differs from the terraform state id; allow only web-2 initially via an explicit allowlist" [brief] | `scripts/web-host-reboot.sh` refusals 2 to 8; Guard 1 | mapped |
| 3 | "Issue POST /servers/{id}/actions/reboot (soft ACPI), poll the action, and print the pre-reboot boot_id context" [brief] | refusals 9 and 10; evidence `snapshot` (the pre-request context) | mapped |
| 4 | "After the reboot, poll Better Stack through the existing helper scripts/lib/web2-luks-rows.sh for a SOLEUR_FRESH_BOOT_READY row and a luks-monitor probe row on a boot_id different from the previous one, and report PASS/FAIL/NOT YET as measured. It must never claim the volume is LUKS-backed, reborn or encrypted; it only reports rows" [brief] | `scripts/web-host-reboot-evidence.sh grade`; the verdict table; Guard 2; the readiness-row reconciliation row | mapped |
| 5 | "do not invent a way to force the probe unless the existing unit allows it" [brief] | Cut List row 3 and the timer analysis (the unit does not allow it without SSH) | mapped |
| 6 | "No SSH fallback in the design (hr-no-ssh-fallback-in-runbooks), no Doppler writes, no token mint, no Terraform apply, and no dispatch inside this work" [brief] | forbidden-text row; Guard 4; PR body statement; the diff-scope acceptance criteria | mapped |
| 7 | "Tests following the sibling pattern (a suite registered like the web2-rebirth tests, parity-census and MAIN_ROOT_TF_WORKFLOWS rules respected only if this workflow touches that root)" [brief] | Phases 1 and 4; the two suites; the MAIN_ROOT reconciliation row | mapped |
| 8 | "plus a runbook section stating the dispatch inputs and that a dark host after a reboot is recovered with web-host-replace passing image_tag without a leading v (open defect #9669)" [brief] | `web-host-reboot.md` (new runbook) and the pointer section in the rebirth runbook | mapped |
| 9 | "update knowledge-base/engineering/operations/runbooks/web2-luks-rebirth-9372.md closing checklist so the Step 8 cleanup keeps or retires this workflow explicitly" [brief] | row 5 edit (retire, with the keep alternative and its conditions) | mapped |
| 10 | "PR body uses Ref #9372 and never Closes. Do not flip the hcloud_volume.workspaces ledger row and do not touch the encryption-posture exception" [brief] | Phase 7; the diff-scope acceptance criteria | mapped |
| 11 | "the plan must verify from the code whether a plain reboot produces a probe row soon after boot and whether the workflow can trigger the probe by an existing, non-SSH mechanism" [brief] | Research Insights, timer analysis | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `web-host-reboot.yml` | "a new workflow_dispatch workflow (e.g. web-host-reboot.yml)" | asked |
| `scripts/web-host-reboot.sh` | "Reuse the by-name server resolution and refusals from web2-rebirth.sh cmd_reboot" | asked |
| `scripts/web-host-reboot-evidence.sh` | "poll Better Stack through the existing helper scripts/lib/web2-luks-rows.sh" | asked (split from the writer by the census; see reconciliation) |
| two-job split (`reboot`, `observe`) | "the agent dispatches it, the environment approval stays with the owner" | inferred: a 40-minute poll would hold the Tier-B credential and the host mutex; the split keeps the write credential's window short and the poll credential-free. Reviewers (DHH, simplicity, CTO) proposed one job; kept because ask 4 says the workflow polls (recorded as a user-challenge) |
| typed server id inside `confirm` | "a typed confirm input" | asked (the id inside it is inferred: the approval can wait hours and a replace in between changes the target; the id costs no extra input) |
| the never-pooled gate | "Reuse the by-name server resolution and refusals from web2-rebirth.sh cmd_reboot" | asked (it is one of `cmd_reboot`'s refusals the brief's list omits) |
| journald `_BOOT_ID` boot list in the verdict | "a luks-monitor probe row on a boot_id different from the previous one" | inferred: a boot-id set difference is a proxy that can pass with no reboot; a boot that began after the request is the invariant, and the same read tells a restarted host from a dark one without waiting for the daily probe |
| the pre-request `snapshot` | "print the pre-reboot boot_id context" | asked |
| `run-name` naming host and id | "the same Tier-B environment reviewer gate" | inferred: the CPO's failure mode 4 (an approver who cannot see the target) |
| `READERS` edit in the G3 census | "through the existing helper scripts/lib/web2-luks-rows.sh" | inferred: the census otherwise flags the evidence script; the allow-list widening is the minimum edit and is itself guarded (Guard 3) |
| `BASELINE_DECLARED_PROBES` bump | "Tests following the sibling pattern" | inferred: this plan declares `credentials_required`, and that baseline test fails otherwise |
| `guard-vacuity-floor.test.sh` per-file promotion | "Tests following the sibling pattern" | inferred: a floor-bearing suite under `apps/web-platform/infra/` grows a shrink-only ledger and reds that gate unless promoted per file |
| `infra-credential-tiers-8209.md` inventory rows | "the same Tier-B environment reviewer gate as the sibling host workflows" | inferred: the runbook is the canonical consumer inventory and says it is derived job by job; a new Tier-B job left out makes it lie |
| ADR-263 addendum, ADR-241 line and `model.c4` edge prose | "closing checklist so the Step 8 cleanup keeps or retires this workflow explicitly" | inferred: `wg-architecture-decision-is-a-plan-deliverable` and the C4 completeness mandate; the capability and its end of life must be recorded where architecture is read |
| dated status correction in the rebirth runbook | "update knowledge-base/engineering/operations/runbooks/web2-luks-rebirth-9372.md closing checklist" | inferred: the file being edited carries a measured-false status sentence; leaving it would make the new pointer section contradict its own header |
| fixed footer and claim denylist | "It must never claim the volume is LUKS-backed, reborn or encrypted; it only reports rows" | asked (the footer and denylist are the enforcement) |
| tombstone rows in the workflow suite | "so the Step 8 cleanup keeps or retires this workflow explicitly" | inferred: the workflow depends on two scripts that retire; without a self-expiring row a half-retirement rots |

### Split Assessment

- Subsystems touched: 5 roots (`.github/workflows`, `scripts`, `apps/web-platform/infra`, `plugins/soleur/test`, `knowledge-base`)
- Planned files: 8 created, about 18 edited (4 are generated or regenerated) | Estimated changed lines: about 1,300 (about 750 of them in the two suites, which carry the mutation batteries)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The thresholds trip on test volume and breadth of small edits, not on separable behaviour. The workflow, its scripts and its gating suites are one unit (a Tier-B write path without its tests, or tests without a subject, is the unsafe intermediate), and the documentation and registration edits are each a few lines that only make sense next to the capability they record. A docs-first split would document a capability that does not exist; a code-first split would merge an untested write path.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `.github/workflows/web-host-reboot.yml` parses; its only trigger is `workflow_dispatch`; `jobs` is exactly `reboot` and `observe`; `reboot` carries `environment: web-platform-infra-apply`, `if: ${{ github.ref == 'refs/heads/main' }}` and job-level `concurrency.group: web-1-swap` with `cancel-in-progress: false`; `observe` has no `environment`, no use of `./.github/actions/infra-credentials` and no reference to `HCLOUD`, `doppler` or `DOPPLER_TOKEN`, and is gated on `always()` plus a non-empty `anchor_epoch` output (`apps/web-platform/infra/web-host-reboot-workflow.test.sh`, rows S1 to S12).
- [ ] The workflow's only inputs are `host` (a choice of exactly `web-2`), `confirm` and `reason`; the validate step rejects (with nothing after it running) a `host` other than `web-2`, a `confirm` that is not `REBOOT-<host>-<digits>`, an empty, multi-line, over-200-character or out-of-charset `reason`.
- [ ] `scripts/web-host-reboot.sh reboot` passes every row of the refusal table against the fake world, each refusal leaves the world's write log empty, and the happy path records exactly one write: `POST /servers/<id>/actions/reboot` for the id in the world; the anchor appears in `GITHUB_OUTPUT` before the POST is recorded and survives a failing action poll (`bash scripts/web-host-reboot.test.sh`).
- [ ] The census row over `actions/reboot` finds exactly the recorded set of files (the rebirth script and the new script, tests excepted).
- [ ] `scripts/web-host-reboot-evidence.sh` returns each verdict row of the table for fixtures built from the real emitted JSON shape (age as a quoted integer, probe messages with and without the `[luks-monitor]` stdout-copy prefix, journald boot rows with 32-hex ids against probe rows with dashed ids), with the exit codes 0, 1, 2, 3 and 78, a read fault never yielding FAIL, a junk row never counting as evidence, and a probe row on the OLD boot never yielding PASS.
- [ ] Every fixture scenario's combined output contains the fixed footer and none of the denylisted tokens; the static scan of the print statements of the workflow and both scripts finds none (Guard 2).
- [ ] The evidence script is in `READERS` and the G3 census suite is green with the planted rows; `scripts/web-host-reboot.sh` and the workflow name neither `web2-luks-rows` nor `workspaces_luks_cutover` (Guard 3).
- [ ] Mutation batteries: each row of the four guard contracts goes RED on a COPY of the subject, and each battery prints the count of mutants it ran (a floor, not a pass count).
- [ ] The never-pooled step is the only step with the marker token, the Better Stack credentials are bound only to the snapshot step (inside the `env -i` allow-list subshell) and the observe job's grade step, and no step env or run body carries `HCLOUD_TOKEN` except through the loader's export and the one reboot step.
- [ ] `TERRAFORM_VERSION` equals `apply-web-platform-infra.yml`'s; `terraform-target-parity.test.ts` is green with `MAIN_ROOT_TF_WORKFLOWS` unchanged and its exact-equality census still `found.length == 4`; `nic-wait-gate.test.sh` is green (no `-target` text in the workflow); `tests/scripts/test-infra-privileged-tier-census.sh` and `scripts/guard-vacuity-floor.test.sh` are green.
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` is green with its counts unchanged; the C4 syntax and render tests are green after the two edge-prose edits and the regeneration.
- [ ] The `discoverability_test` command was executed once against live read-only data in the work phase (`doppler run -p soleur -c prd_terraform -- bash scripts/web-host-reboot-evidence.sh snapshot`) and printed the literal `pre-request context:`; its output (boot ids and ages only) is pasted in the PR notes.
- [ ] Cost: each new suite finishes in under 120 s on a quiet box (measured and recorded; the duration TSV rows are seeded from that measurement; a timeout pin is added only if the measurement exceeds 360 s).
- [ ] Registration: `bash scripts/lint-orphan-test-suites.sh` is clean once both suite files are tracked (a registration claim is verified by the census, not inherited from prose); both TSV pairs were regenerated incrementally; `BASELINE_DECLARED_PROBES` is 48 (or one more than its value on `origin/main` at merge time).
- [ ] The gates' OWN invocations are clean, not a hand-listed reconstruction of their inputs: `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (the CI form; it scans every changed plan, spec and runbook), `python3 scripts/lint-guard-contract.py` with no arguments (the registered `scripts/lint-guard-contract-live` form, which walks every plan), `npx markdownlint-cli2` over this plan and `tasks.md`, and the repo's workflow linters (`scripts/lint-workflows.sh` and the `lint-workflow-*` set) with no new finding on the new workflow.
- [ ] Documentation: the new runbook states the dispatch inputs, the id lookup from a read-only Hetzner GET (never from state), the watch, how to read PASS, FAIL and NOT YET and each `next:` line ("do not re-dispatch to force a row"), the local re-grade command, the FAIL branch (a FAIL row also spoils the #6931 soak by the grader's rule; recovery is a `web_host_replace` and a re-grade from the new instance's readiness row), the dark-host path (`apply_target=web-host-replace` with `image_tag` WITHOUT a leading `v`, referencing #9669, the tag taken from web-1's `/health` `.version`, and its consequences: a new server id, the host-key pin re-capture of closing row 3, the `earliest` re-set of row 4, a restarted soak, and a second reboot dispatch), the marker consequence, the concurrency note (verified or explicitly unverified), the false-positive-free FAIL rule, and the retirement rule; the rebirth runbook's row 5 names every file and census entry to delete, is sequenced after the graded #6931 PASS, and states retire-versus-keep explicitly; the dated status correction is present.
- [ ] Diff scope (`git diff --name-only origin/main...HEAD`): no `*.tf` file, not `scripts/encryption-posture-ledger.json`, not `scripts/lint-encryption-posture.py`, nothing under `knowledge-base/legal/` or `docs/legal/`, and no Doppler or token change anywhere; the PR body says `Ref #9372` and does not say `Closes`.
- [ ] No workflow was dispatched and no `gh workflow run` for `web-host-reboot.yml` appears in any commit, comment or CI step of this change.

### Post-merge (separate, owner-authorized; not part of this work)

- The first dispatch needs the owner's explicit go-ahead naming the production write (`hr-menu-option-ack-not-prod-write-auth`); it is tracked as the next step on #9372 and is not performed by this change. Automation: the dispatch is a single `gh workflow run` by the agent once authorized; only the environment approval is human. Because the dispatch is a distinct, deferred owner action tracked on an open issue, the PR does not hold an undeferred operator step (`wg-block-pr-ready-on-undeferred-operator-steps`).
- After a dispatch: copy the run summary (run id, SHA, dispatcher, approver, anchor epoch, boot ids, verdict) into the closing change, and rely on `scripts/followthroughs/web2-luks-live-6931.sh` for the soak grade.

## Test Scenarios

Given/When/Then, each also a row in `scripts/web-host-reboot.test.sh` unless it names the workflow suite.

- Given a world where web-2 is `soleur-web-2`, id 169095540, state id equal, never-pooled `absent`, when `reboot web-2 REBOOT-web-2-169095540` runs, then exactly one `POST /servers/169095540/actions/reboot` is recorded after the anchor was written, the output carries the accepted-request sentence and the anchor epoch, and the footer is present.
- Given host `web-1`, `web-3`, an empty host, or `web-2` followed by a trailing space, then the run refuses with the allow-list message and the write log is empty.
- Given a `confirm` of `REBOOT-web-2-`, `REBOOT-web-2-12x`, `reboot-web-2-1`, `REBOOT-web-1-123931471` or an id that differs from the live one by one digit, then it refuses (refusals 3 and 7) and the latter prints the live id.
- Given the server lookup returns zero servers, two servers, a different name, or HTTP 500, then it refuses (refusal 5).
- Given the resolved id is 123931471 (web-1's), then it refuses with the web-1 message even when the typed id matches it.
- Given the state holds a different id, no id, no `web-1` entry, or the pull fails, then it refuses and the write log is empty (the REORDER guard row).
- Given `NEVER_POOLED` is empty, `present` or unset, then it refuses before any API call.
- Given the POST answers 403, then the message names the read-only-token cause; given 422 or 423, then it fails with Hetzner's code; given 201 with no action id, then it fails.
- Given the action ends `error` or stays `running` past 24 polls, then it fails with the unconfirmed-outcome message, the anchor is already in the output, and nothing claims success.
- Given xtrace is on, or no token is set, then it exits 78 or refuses before any call.
- Given the token value, then it never appears in any recorded argv or in any output (the shim records stdin separately and the suite greps for the sentinel).
- Evidence verdicts (each from a real-shape fixture): a readiness row younger than the request gives NOT YET `instance_recreated_after_request`; no boot after the request gives NOT YET `no_new_boot_seen` and keeps polling to the deadline; a new boot with no probe row gives NOT YET `new_boot_seen_probe_pending`; a new boot with an OK probe row on the OLD boot gives NOT YET; a new boot with an OK probe row on that new boot gives PASS; a new boot with a FAIL row younger than that boot's first row gives FAIL; a FAIL row older than the new boot's first row does not; a malformed probe row after the new boot gives FAIL; a probe row with an unparseable age is a read fault, not a verdict; a 503 or a timeout on any of the three reads gives NOT YET `read_fault`; absent credentials give exit 3; a helper function that failed to load gives exit 3.
- Boot cadence: a probe row whose boot differs from the readiness row's boot on a boot that began BEFORE the request is not evidence of this request.
- Deadline: the grade loop ends at the wall-clock window with a fake clock, however many iterations that took (a loop bounded by an iteration count is the defect), and the clock is read before each iteration's queries.
- Footer and denylist: every scenario above ends with the verbatim footer and no denylisted token; a planted token is caught.
- Workflow suite: the YAML rows (S1 to S12 and the step-order and classification rows), the validate-step behaviour under `bash -e` with the real inputs (accepts the canonical input, refuses each bad one, refuses a `reason` carrying a newline or a pipe), the `observe` structural row, the exit-2-is-green mapping, the tombstone rows (a missing rebirth script or never-pooled reader with a present `web-host-reboot*` file is RED), and the parity rows (`TERRAFORM_VERSION`, allow-list agreement, helper-body parity against `web2-rebirth.sh` while it exists).
- **Browser:** none (no UI). **API verify:** none against production; the suites run against shims only.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `single-user incident` and sets `requires_cpo_signoff: true`.
- The G3 census keys on the helper's file name and the marker's name in ANY non-test file's code lines (comment lines are dropped, `.yml` is in scope). The workflow YAML and `scripts/web-host-reboot.sh` must not contain `web2-luks-rows` anywhere outside a comment, and no reader may contain a write verb; a harmless `echo "... -X POST ..."` in the evidence script reds the census.
- `terraform-target-parity.test.ts` strips `#` comments but not `echo` text: the strings `terraform plan` and `terraform apply` must not appear in any run body, or the planner census finds a fifth planner and fails its exact-equality row.
- `apps/web-platform/infra/nic-wait-gate.test.sh` greps every workflow for `-target=hcloud_server.web`; this workflow carries no `-target` at all.
- The `BASELINE_DECLARED_PROBES` bump collides with any sibling PR that also declares `credentials_required`; re-read the constant at work time and again after the last sync with `main`, and write the dated comment in the established shape. A commit made with the bun-test hook excluded skips that suite, so the red would surface a commit later.
- `scripts/guard-vacuity-floor.test.sh` treats `apps/web-platform/infra/` as a deferred directory with a shrink-only ledger: promote the new infra suite per file, never by raising `MAX_DEFERRED`.
- `lint-infra-no-human-steps.py` flags a human-actor word within a line of a reboot or mount word. New prose in the runbooks, the ADR addendum and the edge prose uses "agent", "owner" and "dispatcher"; run the linter in its CI form (`--changed --base origin/main`) over every changed doc.
- The approvals lookup needs `actions: read`; the `observe` job must re-declare `contents: read` only.
- A quoted-integer `age_s` and the `[luks-monitor]` stdout-copy prefix are the real row shapes (`web2-luks-rows.sh` header); a probe `boot_id` has dashes and a journald `_BOOT_ID` has none. Fixtures that use bare numbers, bare messages or one id spelling would pass a reader that fails live.
- A negated grep (`! grep -q`) folds "the pattern did not compile" (rc 2) into "no match"; every absence assertion in the two suites uses a count (`grep -c`) or an explicit `rc == 1` test, with a compile pre-check.
- A mutation battery must run on COPIES and print the number of mutants it ran; a battery that exits 0 on "0 ran" is the vacuous shape the Guard Contract exists to prevent.
- The brief's "Step 8" does not exist by that name in the rebirth runbook; the edit lands in closing-checklist row 5.
- Do not write "LUKS-backed", "encrypted" or "reborn" about web-2 in the new runbook except in the sentence that says no such claim is made before the graded follow-through reports PASS (closing row 2 of the rebirth runbook already forbids it).
- The measured values in Research Insights (server id, ages, boot ids, marker absence) are a 2026-10-07 snapshot; none of them is copied into code or docs.

## References

- Issues: #9372 (Ref only), #6931 (the soak-gated grader), #9669 (the `v`-prefix defect), #9572 (the ledger flip, out of scope), #8209 (credential tiers), #9358 (read-only marker token prerequisite).
- ADR-263 (guest-side fresh-boot LUKS, addendum 2026-10-05), ADR-241 (Terraform credentials are tiered), ADR-148 (web-host replacement is a distinct gated dispatch), ADR-145 (host birth is a guarded capability).
- Runbooks: `web2-luks-rebirth-9372.md`, `web-host-replace.md`, `infra-credential-tiers-8209.md`.
- Prior plans: `2026-10-05-feat-web2-luks-rebirth-workflow-plan.md`, `2026-10-06-fix-web2-rebirth-emptiness-gate-field-paths-plan.md`.
- Learnings: `knowledge-base/project/learnings/2026-10-06-a-dispatch-can-fail-after-its-approval-and-my-state-claim-was-my-own-earlier-action.md`, `knowledge-base/project/learnings/2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md`.
