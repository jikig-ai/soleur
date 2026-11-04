---
title: "Audit findings for #11294 — per-job verdict on random_id [id=] lines in retained public logs"
branch: feat-one-shot-11294-11711-rotation-audit
created: 2026-11-04
issue: 11294
---

# Audit findings — #11294

Per-job verdict on whether `random_id` `[id=...]` lines (the key material in base64url) reached a
retained public log, through which sink, and under which retention window. **Counts, addresses, run
ids, dates and verdicts only — no key value appears or was read for this record.**

## Sources (all read for this record, not paraphrased)

- Census + deletion/redaction record: `knowledge-base/legal/audits/2026-10-31-11294-run-log-evidence-preservation.md`
- CLO determination: `knowledge-base/legal/audits/2026-10-29-clo-determination-11294-random-id-log-exposure-art-4-12.md`
- CTO rulings: `decision-challenges.md` in this spec directory (all six rows ruled 2026-11-04)
- The eight workflows and two rotation scripts cited per row, cited `file › symbol/step-name` (line numbers drift)

## The mechanism (why every job printed every key)

`terraform plan -target=X` and `terraform apply` refresh the **whole state**, not the target set —
the target only filters the diff. Every job on the `apps/web-platform/infra` root that streamed
`terraform plan`/`apply` therefore printed `random_id.<name>: Refreshing state... [id=<key>]` for
**all twelve** `random_id` resources in state on every run, regardless of its `-target` list.
Post-#11551 every streaming invocation pipes `2>&1 | tf_redact_random_ids`
(`tests/scripts/lib/tf-redact-random-ids.sh › tf_redact_random_ids`).

## 1. Job inventory — every terraform-invoking job across the eight workflows

| Workflow | Job | Root | Terraform invocations | Class |
|---|---|---|---|---|
| apply-web-platform-infra.yml | `apply` | apps/web-platform/infra | init, plan `-out=tfplan`, `show` to files, `apply tfplan`, `output -raw` (captured) | streamed (now `tf_redact_random_ids`) |
| apply-web-platform-infra.yml | `inngest_host` | apps/web-platform/infra | init, plan, show to files, apply | streamed |
| apply-web-platform-infra.yml | `inngest_host_replace` | apps/web-platform/infra | init, plan, show, apply | streamed |
| apply-web-platform-infra.yml | `registry_host_replace` | apps/web-platform/infra | init, plan, show, apply | streamed |
| apply-web-platform-infra.yml | `registry_region_migrate` | apps/web-platform/infra | init, plan, show, apply | streamed |
| apply-web-platform-infra.yml | `registry_luks_recut` | apps/web-platform/infra | init, plan, show, apply, `show -json` to file | streamed |
| apply-web-platform-infra.yml | `git_data_host_replace` | apps/web-platform/infra | init, plan, show, apply, `output -raw` | streamed |
| apply-web-platform-infra.yml | `workspaces_luks_cutover` | apps/web-platform/infra | init, plan, show, apply | streamed |
| apply-web-platform-infra.yml | `workspaces_luks_recut` | apps/web-platform/infra | init, plan, show, apply | streamed |
| apply-web-platform-infra.yml | `web_host_create` | apps/web-platform/infra | init, `console` (captured hash), plan, show, apply | streamed |
| apply-web-platform-infra.yml | `web_host_replace` | apps/web-platform/infra | init, `console` (captured), plan, show, apply | streamed |
| apply-web-platform-infra.yml | `git_data_host_create` | apps/web-platform/infra | init, plan, show, apply | streamed |
| apply-web-platform-infra.yml | `ci_ssh_token_replace` | apps/web-platform/infra | init, plan, `show -json` to file, apply, `output -raw` | streamed |
| apply-web-platform-infra.yml | `inngest_link_flag` | apps/web-platform/infra | init, plan, `show -json` to file, apply | streamed |
| apply-web-platform-infra.yml | `vector_redeliver` | apps/web-platform/infra | init, plan, `show` to files, apply | streamed |
| apply-web-platform-infra.yml | `inngest_backstop_retire` (RETIRED — inputs retired; removed by #9784/#9877 commits) | apps/web-platform/infra | init, plan, apply | streamed (no longer exists) |
| apply-web-platform-infra.yml | `preflight`, `notify-apply-failure`, `registry_pull_path_gate`, `registry_store_restore`, `git_data_birth_disclosure`, `entrypoint_audit` | — | none (`registry_store_restore` is a data-engine restore, not terraform) | no-terraform |
| apply-deploy-pipeline-fix.yml | `apply` | apps/web-platform/infra | init, `show -json` (captured), plan `-target=`, `show` to files, `console` (captured), apply, re-push plan+apply | streamed |
| apply-deploy-pipeline-fix.yml | `preflight` | — | none | no-terraform |
| scheduled-terraform-drift.yml | `drift-check (apps/web-platform/infra)` | apps/web-platform/infra | init, `terraform plan -detailed-exitcode` captured in `PLAN_OUTPUT=$(...)` (`drift-check › Terraform plan (drift detection)`) | captured → filtered → public issue body/comment + private email |
| scheduled-terraform-drift.yml | `drift-check (infra/github)`, `drift-check (apps/web-platform/infra/sentry)` | other roots | same capture shape | captured (roots declare no `random_` resources) |
| scheduled-terraform-drift.yml | `heartbeat-live-reconcile`, `sole-copy-protection-check`, `rung2-rehearsal-orphan-sweep`, `inngest-rehearsal-orphan-sweep`, `orphan-sweeps-checkin` | — | none (Doppler/Hetzner API reads only) | no-terraform |
| infra-validation.yml | `plan` (matrix over `plan_directories`) | apps/web-platform/infra + others | `terraform plan -refresh=false` captured in `PLAN_OUTPUT=$(...)` (`plan › Terraform plan`) | captured → redacted → public PR sticky comment |
| infra-validation.yml | `detect-changes`, `validate`, `infra-validate-required`, `deploy-script-tests`, `deploy-script-tests-fixed`, `deploy-script-tests-done`, `registry-userdata-budget`, `inngest-userdata-budget`, `check-secrets`, `notify-main-failure` | — | `fmt -check`, `console` renders, `init -backend=false` only — no live-state plan/apply/refresh/show | no-terraform (no refresh output exists) |
| inngest-provision-rehearsal.yml | `rehearse` | apps/web-platform/infra/inngest-provision-rehearsal | init, destroy, plan a/b, `show -json` to files, apply a/b | streamed |
| inngest-provision-rehearsal.yml | `teardown` | apps/web-platform/infra/inngest-provision-rehearsal | init, destroy | streamed |
| cf-lb-overlay.yml | `ga_overlay`, `ga_monitor_fix`, `ga_pool_update` | apps/web-platform/infra (`INFRA_DIR`) | init, plan, `show -json` to file, `show` greps to stderr, apply | streamed |
| cf-lb-overlay.yml | `staging_record`, `staging_overlay`, `staging_teardown` | apps/web-platform/infra/lb-staging (`REHEARSAL_DIR`) | init, plan, `show -json` to file, `show` greps to stderr, apply | streamed (root declares no `random_` resources) |
| key-rotate.yml | `guard`, `apply`, `redeploy`, `notify` | apps/web-platform/infra | no terraform in the YAML; `scripts/key-rotate.sh › kr_tf` sends every Terraform stream to a private file | none reaches a log by construction |
| inngest-key-rotate.yml | `guard`, `apply1`, `reboot`, `apply2`, `redeploy`, `notify` | apps/web-platform/infra | no terraform in the YAML; `scripts/inngest-key-rotate.sh › kr_tf` sends every Terraform stream to a private file | none reaches a log by construction |

## 2. Per-job verdicts

Census hit counts are job-rows from the preservation record (a run can hit in more than one job;
job-rows sum to 692 over 686 hit runs). Per-address splits and run-sample counts derive from the preservation record's per-job table and the uncommitted `census-11294.tsv` — the same bounded-evidence class as the §3 attribution item. Retention windows are in §4; the closing-PR timestamps are
verified live: **#11551 merged 2026-10-30T20:42:34Z** (streamed `tf_redact_random_ids` coverage),
**#11674 merged 2026-10-31T11:58:49Z** (ANSI colour-sequence strip — the `ESC[1m` `m` ended the
address anchor mid-line), **#11930 merged 2026-11-03T10:00:31Z** (tainted / deposed-object / drift
plan-block shapes).

| Job | Census job-rows with hits | Reached a retained public log? | Sink | Retention | Residual gap window |
|---|---|---|---|---|---|
| `apply` (apply-web-platform-infra) | 482 | YES — streamed refresh lines; the census's value-shaped counter measured nine of the twelve `random_id`s' lines (`egress_audit_ingest_token` in 102 runs) — a line-shape under-count of the print mechanism (§6 Known gap), not three keys never printed; `apply` job-rows across both apply workflows total 570 | Actions step logs | 90 d (measured `days: 90` 2026-10-29) | ANSI-shaped lines until #11674 (10-30→10-31); tainted/deposed/drift-block shapes until #11930 (10-30→11-03). All hit logs deleted 10-31/11-01 |
| `apply` (apply-deploy-pipeline-fix) | 88 | YES — census measured `tunnel_secret` lines only (97 lines) | Actions step logs | 90 d | same gap windows; hit logs deleted |
| `inngest_host` | 3 | YES — the dedicated pair only | Actions step logs | 90 d | same; deleted |
| `inngest_backstop_retire` (RETIRED) | 3 | YES — dedicated pair plus nine others | Actions step logs | 90 d | exposure window closed by job retirement + log deletion |
| `web_host_replace` | 13 | YES — `tunnel_secret` | Actions step logs | 90 d | same; deleted |
| `vector_redeliver` | 2 | YES — `tunnel_secret` | Actions step logs | 90 d | same; deleted |
| `inngest_host_replace` (28 runs read), `registry_host_replace` (19), `git_data_host_replace` (16), `git_data_host_create` (2), `registry_luks_recut` (1) | 0 | streamed `[id=` lines present but **no** value-shaped `random_id` line measured (inference from job scopes, not a tested cause) | Actions step logs | 90 d | same coverage today |
| `registry_region_migrate`, `workspaces_luks_cutover`, `workspaces_luks_recut`, `web_host_create`, `ci_ssh_token_replace`, `inngest_link_flag` | 0 measured | streamed, same mechanism — no hit runs in the census window | Actions step logs | 90 d | same coverage today |
| `drift-check (apps/web-platform/infra)` | 89 | YES via a **different** surface: the captured plan is filtered into `plan-output.txt` and `cat`ed into public `infra-drift` issue bodies/comments (`drift-check › Create or update drift issue` — the `cat` sits inside `{ } > /tmp/issue-body.md` groups feeding `gh issue comment`/`gh issue create`, never stdout). Step-log hits themselves are the unresolved signal in §3 | `infra-drift` issue bodies + comments (public); ops email snippet (private) | indefinite until edited/deleted; edit history survives | 74 bodies + 234 comments redacted in place 11-01; 218 of the redacted comments sat under `infra-drift` issues, 16 on #10835; edit-history residual |
| `drift-check (infra/github)`, `drift-check (apps/web-platform/infra/sentry)` | 0 | no — those roots declare no `random_` resources | — | — | — |
| `plan` (infra-validation, `apps/web-platform/infra` leg) | 0 in sampled run logs (14 sampled: `[id=` lines, no `random_*` address — `-refresh=false` prints no refresh lines) | YES via the public PR sticky comment: a replaced `random_id` diffed its old value into `marocchino/sticky-pull-request-comment` (`plan › Post plan comment`); E4 measured 498 PR bot comments carrying value-shaped lines | PR sticky comments | indefinite until deleted; deletion removes edit history | 498 PR bot comments deleted 2026-11-01; comment path had self-stopped 2026-09-23; now redacted pre-post |
| `rehearse`, `teardown` (inngest-provision-rehearsal) | 6 each (same 6 runs) | YES — but the **rehearsal root's own throw-away keys**, not production values | Actions step logs + 90 d evidence artifact | logs 90 d; artifact `retention-days: 90` (`rehearse › Upload the evidence artifact`) | artifact surface never scanned (endpoint HTTP 500 — Known gap) |
| `cf-lb-overlay` `ga_*` / `staging_*` jobs | 0 — workflow created 2026-10-31 (commit d1fa52f922), after the census window closed 2026-10-29 | no pre-redaction runs exist; every run has streamed through `tf_redact_random_ids` since birth | Actions step logs | 90 d | none — post-fix by construction |
| `key-rotate.yml` all jobs, `inngest-key-rotate.yml` all jobs | 0 | NO — `kr_tf` routes every Terraform stream to a private file on the runner; the workflow YAML holds no terraform command and uploads nothing; only verdict/boolean/state lines are printed | none (private runner file, discarded) | — | clean by construction; first dispatches ran 2026-11-02 — post-#11551/#11674, pre-#11930 (#11287 merged 10-29T23:57Z, #11918 merged 11-03T16:45Z) |
| all `no-terraform` jobs (per §1) | — | no terraform output exists to carry the vector | — | — | — |

## 3. The `drift-check` 89-hit attribution — ruled by CTO 2026-11-04

Ruling (`decision-challenges.md`, Item 4): **the plan stream is ruled out** by a full git-history
scan of `scheduled-terraform-drift.yml` over the census window. `PLAN_OUTPUT=$(terraform plan …)`
has been captured in a command substitution since the file's creation commit `e997bc5185`
(2026-03-21) — verified at both anchors: the creation revision shows
`PLAN_OUTPUT=$(doppler run … terraform plan -detailed-exitcode …) > plan-output.txt`; the current
revision captures at `drift-check › Terraform plan (drift detection)` and every
`cat ${RUNNER_TEMP}/plan-output.txt` sits inside `{ } > /tmp/issue-body.md` groups feeding
`gh issue comment`/`gh issue create`. Zero `terraform show|state|refresh|output|apply` reaches
stdout in any revision.

**Remaining attribution (bounded):** census-column counting (the `id_lines`/`random_addr_lines`
columns may have counted value-shaped non-key lines, or lines from a step other than the plan) vs
matrix-leg misattribution (output of the `infra/github` or `sentry` legs attributed to the wrong job
row). The settling evidence is `census-11294.tsv`'s `secret_shaped_random_id_lines` column — the TSV
(1,448 rows, sha256 `6ba16467…`) lives in the operator's scratch area, uncommitted, and was not
available to this work. **Corroborating signal:** the 89 job-row hits end 2026-09-24 while public
`infra-drift` comments carrying value-shaped lines continued to 2026-10-29T06:02Z — consistent with
the issue stream, not step logs, being the live sink after that date.

**Verdict:** `mechanism unresolved — bounded`. Every hit log is deleted (§5), so the open item is
attribution, not exposure. Recorded as resolved-to-bounded per the CTO ruling.

## 4. Sinks and retention windows

| Sink | Public? | Mechanism | Retention | Post-redaction state |
|---|---|---|---|---|
| Actions step logs | yes (public repo) | streamed `terraform plan/apply` unfiltered pre-#11551; ANSI-shaped lines passed through until #11674; tainted/deposed/drift-block shapes until #11930 | 90 days — measured `days: 90`, `maximum_allowed_days: 90` via the repo retention endpoint 2026-10-29 (public repos configurable only 1–90 d) | every streaming step pipes `2>&1 \| tf_redact_random_ids`; 686 hit runs deleted 10-31/11-01 |
| `infra-drift` issue bodies + comments | yes | `PLAN_OUTPUT=$(…)` → `tf_redact_random_ids` → `plan-output.txt` → `cat` into issue body/comment | indefinite until edited/deleted; **edit history stays public** | redacted in place 11-01 (74 bodies + 234 comments); edit-history residual |
| infra-validation PR sticky comments | yes | captured plan → `marocchino/sticky-pull-request-comment` | indefinite until deleted; deletion removes edit history | 498 deleted 11-01; now redacted before posting |
| Ops email (drift/error) | no (private) | `PLAN_SNIPPET` grep of `plan-output.txt` into email body (`drift-check › Prepare email content`) | private channel | not an exposure sink |
| Artifacts | yes | `inngest-provision-rehearsal` evidence artifact `retention-days: 90`; infra-validation suite logs `retention-days: 14`; cf-lb overlay artifact | per-upload `retention-days` | **never scanned** — the artifact-list endpoint returned HTTP 500 during the census (Known gap) |
| key-rotate.yml / inngest-key-rotate.yml logs | yes | `kr_tf` sends every Terraform stream to a private file; the plan is projected to five fields and the rest deleted | — | clean by construction |
| Step summaries | yes | `$GITHUB_STEP_SUMMARY` writes | run lifetime | static reading: only verdict/shape lines are written; no plan dump found (CLO determination §E4) |

## 5. Preservation-record deltas (carried forward, verified)

- **686 hit runs deleted**: 567 on 2026-10-31 (565 production + 2 rehearsal, each live-checked as a
  completed run of `jikig-ai/soleur` before deletion) + **119 held runs deleted 2026-11-01** (115
  production + 4 rehearsal, held because a committed document or open issue cited them; the
  preservation record merged first via PR #11721, merged 2026-10-31T21:52:02Z; all 119 deleted,
  0 skipped, each confirmed absent after). The held-run metadata table is preserved in the record.
- **498 PR bot comments deleted** 2026-11-01 (deletion removes edit history too).
- **74 issue bodies + 234 issue bot comments redacted in place** 2026-11-01 (232 comments verified
  by script, 2 flagged `verify-mismatch` then cleared by a separate rescan).
- **Rescan after the edits: 0** value-shaped lines in the 74 bodies, 0 in the 234 comments.
- Other surfaces scanned, nothing found: PR review comments (393 scanned, 0 hits), review summaries
  (0 hits). Commit comments and discussions do not exist in the repository.
- Census base: 1,433 runs scanned 2026-10-29 across 17 workflows; 686 runs with ≥1 value-shaped
  `random_id` line (680 production, 6 rehearsal-only); 6,383 value-shaped lines total; per-run detail
  in `census-11294.tsv` (operator scratch, uncommitted, sha256 `6ba16467…`).

## 6. Known gaps carried forward (verbatim scope of the preservation record's `## Known gaps`)

- Commit comments and discussions do not exist in the repository. The **edit history** of issue/PR
  bodies and comments was not part of the census and survives on the 74+234 in-place items.
- The run **artifact list** endpoint returned HTTP 500 during the census — artifacts never scanned.
- The **oldest runs' logs expired** (90-day retention horizon 2026-07-31); not readable, cannot be
  shown clean or dirty.
- **16 runs had unreadable logs (`NOLOG`)** — status unknown, not clean.
- **175 runs had zero jobs (`NOJOBS`)** — no log exists by construction.
- The value-shaped test is a **line-shape match** on `random_*` id output — a value in another shape
  would not be counted.
- `gh run view --log` shows the **latest attempt only**: 11 in-scope multi-attempt runs' earlier
  attempts were not scanned (2 were later scanned clean; the rest are under the deletion decision,
  which is the owner's).
- Drift classifier live re-verdict was skipped (worktree path gone); the earlier dry run found all
  73 `infra-drift` verdicts identical — next scheduled drift run is the live test.

## 7. Housekeeping verdict — lingering-branch flag

Args flagged local branch `feat-one-shot-11294-redact-random-id-logs` as lingering from merged
#11551. **Verified stale:** `git for-each-ref --format='%(refname:short)' | grep -c '11294-redact'`
returns **0** in this worktree clone, and the plan verified absence in the `/home/jean` clone at
plan time. The branch was already deleted. **Stale flag — recorded, nothing to delete.**

## 8. Residual-exposure statement

1. **Edit history on edited-in-place items.** GitHub keeps earlier revisions of an edited body or
   comment publicly readable. The 74 bodies and 234 comments redacted in place 11-01 retain
   value-carrying history; only deletion removes it, and deletion was impossible for those items
   (the drift workflows read the newest bot "Plan output" comment). This is the unremovable
   residual — the owner's call, not this record's.
2. **Unrotated values.** Every key the census counted is live until the owner-run rotations land.
   Anyone who read a run log, comment or earlier revision before deletion/redaction may hold them;
   the records cannot show who did. Rotation is tracked in #11711 (`rotation-census-11711.md`);
   the CLO re-assessment trigger is **2026-11-08** if rotation is not recorded complete in #11294.
3. **Unscanned artifact surface.** The artifact-list endpoint returned HTTP 500 during the census;
   the 90-day rehearsal evidence artifact and the 14-day suite logs are UNVERIFIED for
   `random_id` content. Static reading says no infra workflow uploads plan/show output, but that is
   a reading, not a measurement.
4. CLO position carried forward: E3 (who viewed the logs) has no instrument and is INCONCLUSIVE by
   nature; E4 is contained, not erased, because edit history stays public; Art. 33/34 duties remain
   not engaged; evidence of use starts a fresh 72-hour clock.

## 9. Operator Holds (reproduced verbatim from the plan — never worked)

These are owner-gated acts. The plan records them; it does not schedule them.

- Dispatch `key-rotate.yml` `mode=rotate` for any key (owner's fresh typed go naming the exact command; `ROTATE-<KEY>-<YYYY-MM-DD>` confirm; `quiet_window`; `webhook_patch_ready` for the webhook key).
- Dispatch `inngest-key-rotate.yml` `mode=rotate|converge` for the dedicated pair (includes the one Hetzner control-plane reboot).
- Any `terraform -replace` / `terraform apply` against real state — including the `tunnel_secret` roll-forward (tunnel replacement + web-2 rebuild).
- Any Doppler secret write (the rotation routes perform them; no agent writes directly).
- Run-log deletion: 686 hit runs already deleted 2026-10-31/11-01 per the preservation record; any remaining deletion decision (the 16 NOLOG runs, the artifact surface) is the owner's.
- The 732 bot comments / 74 issue bodies decision: executed 2026-11-01 (498 deleted, 308 redacted); the residual edit-history posture is the owner's call.
- Closing or editing #11294 / #11711; the agent posts comments only.
- The `github_webhook_secret` post-rotation owner step (App webhook secret update + redelivery of failed deliveries, App private key required).
