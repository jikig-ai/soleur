# Tasks — #7095 host-pull leg (revoked web-host Doppler token)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 reviewed; the plan carries a complete ## Infrastructure (IaC) section. Zero operator
  steps: every host artifact below is delivered by an existing Terraform resource
  (terraform_data.deploy_pipeline_fix / .cron_egress_firewall / .container_restart_monitor_install)
  through the CF-Tunnel webhook channel. The scanner-flagged unit paths are DESTINATIONS of those
  Terraform-driven deliveries and pre-existing ReadWritePaths entries — not manual actions.
-->

Plan: [`2026-07-30-fix-web-host-doppler-token-revocation-broke-host-pull-leg-plan.md`](../../plans/2026-07-30-fix-web-host-doppler-token-revocation-broke-host-pull-leg-plan.md)

`lane: cross-domain` — no `spec.md` exists for this branch (entered directly from the one-shot
pipeline), so the lane defaults to `cross-domain` fail-closed per TR2.

> **Read the plan's `## Plan Review Revisions (R1–R38)` section first.** It supersedes the phase
> text where they conflict. Five reviewers found three P0s that would have made the merge run fail
> with the credential undelivered (R21 filename, R22 first-apply, R23 release/apply race), plus a
> P0 that would have left four units broken behind a green AC (R1).

---

## Phase 0 — Preconditions (no writes, no commits)

- [ ] 0.1 `git fetch origin main && git rebase origin/main` (worktree is behind `d95344622`)
- [ ] 0.2 Re-assert the infra-config channel is alive: `betterstack-query.sh --since 12h --grep infra-config-apply` shows `complete: N/N files written, 0 failed`
- [ ] 0.2b **(R34)** Confirm the last green run of `apply-deploy-pipeline-fix.yml` — this proves the co-targeted root-SSH `infra_config_handler_bootstrap` leg is alive. If it is not, the apply cannot land and the fallback must be wired first.
- [ ] 0.3 Re-read `doppler configs tokens --project soleur --config prd --json`; confirm the token state has not moved since 11:19:30Z
- [ ] 0.4 Verify prescribed CLI forms; **(R35e)** assert the rendered token matches `^DOPPLER_TOKEN=dp\.st\.[A-Za-z0-9._-]+$` with no CR/`#`/trailing space
- [ ] 0.5 `git grep -n 'webhook-deploy'` + `git grep -n 'DOPPLER_TOKEN' -- apps/web-platform/infra/` — every hit fixed or scoped out with a reason
- [ ] 0.6 Confirm Phase 1 is not chicken-and-egg (`ci-deploy.sh` is FILE_MAP entry #1, delivered by the webhook channel, not the container deploy)
- [ ] 0.7 **(R36)** Decide web-2's role NOW, not at implementation time: `curl https://web-2.app.soleur.ai/health` + CF/DNS read → selects Phase 3.2's branch
- [ ] 0.8 Resolve which env file each failing unit reads (answered by R1: `/etc/default/inngest-server`, a copy made at `inngest-bootstrap.sh:586`) — confirm against the live host via the status endpoint

---

## PR-A — Restore production (R0)

### A1 — The credential file

- [ ] A1.1 **(R21 — BLOCKING)** Create `apps/web-platform/infra/soleur-doppler-token.tmpl` — the basename **must** equal the dest basename + `.tmpl`, or `infra-config-gate.sh:46-62` classes it `missing` and reds the whole apply
- [ ] A1.2 Contents: `DOPPLER_TOKEN=${doppler_token}` **plus (R5)** the three Sentry DSN params (`SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY`). **No `DOPPLER_CONFIG_DIR`** (#6536)
- [ ] A1.3 **(R8)** Render once in `server.tf`; inject the string into `cloud-init.yml` via `templatefile(...)` so the two renderings cannot drift
- [ ] A1.4 **(R3.1)** `variable "doppler_token"` gains a `validation { condition = can(regex("^dp\\.st\\.", ...)) }` — fails at `terraform plan`, before a byte reaches the host
- [ ] A1.5 `server.tf`: base64 into `terraform_data.deploy_pipeline_fix`'s `environment {}`; add rendered content + `var.doppler_token` into the existing `sha256(join(...))` `triggers_replace`
- [ ] A1.6 `push-infra-config.sh`: add the payload key. `hooks.json.tmpl`: add the `pass-file-to-command` entry
- [ ] A1.7 `infra-config-apply.sh` `FILE_MAP` **and** `infra-config-install.sh` `DEST_SPEC`: add the new `/etc/default` dest at `640 root:deploy`. **(R8)** State inline why `640 root:deploy` and not the existing file's `600 deploy:deploy`
- [ ] A1.8 **(R6)** Extend `infra-config-gate.sh` to compare `host_sha` against the sha256 of the **rendered payload** (not a repo file) for `.tmpl`-backed dests; **(R35d)** restate AC23 accordingly
- [ ] A1.9 **(R3.3)** `infra-config-install.sh`: reject `/etc/default/*` payloads unless every non-blank line matches `^[A-Za-z_][A-Za-z0-9_]*=` (`reject "envfile_shape"`)
- [ ] A1.10 **(R1)** `infra-config-install.sh`: add a guarded `mkdir -p "$dest_dir"` for allow-listed dests, or drop-in *directory* dests fail at `mktemp`

### A2 — Wire the consumers (the part the draft got wrong)

- [ ] A2.1 **(R3 — supersedes the second-`EnvironmentFile` design for the deploy leg)** Add a guarded source of the new credential file to `ci-deploy-wrapper.sh` (already FILE_MAP → `/usr/local/bin/`). **The webhook unit definition is then never modified, so the self-restart cannot fail to start.**
- [ ] A2.2 **(R2 — highest priority)** `vector.service` drop-in carrying the new `EnvironmentFile`. It is one restart from a total telemetry blackout on web-1, and every post-merge AC reads through it
- [ ] A2.3 **(R1)** `cron-egress-resolve.service`, `cron-egress-alarm@.service`: add the new `EnvironmentFile=-` line **after** the `inngest-server` line. Delivered by `terraform_data.cron_egress_firewall` (`server.tf:1513`)
- [ ] A2.4 **(R1)** `container-restart-monitor.service`: same. Delivered by `terraform_data.container_restart_monitor_install` (`server.tf:442`)
- [ ] A2.5 **(R1)** `inngest-heartbeat.service`: heredoc, not a repo file → deliver a drop-in. **Do NOT rewrite `/etc/default/inngest-server`** (`inngest-bootstrap.sh:616-617` fail-closes the host)
- [ ] A2.6 **(R7)** Lockstep edits: `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` (`TRIGGER_FILES`), `plugins/soleur/skills/ship/SKILL.md` (`DEPLOY_PIPELINE_FIX_TRIGGERS` + `DPF_REGEX`), `postmerge/references/deploy-status-debugging.md`, `cron-egress-firewall.test.sh:467` (**add**, do not replace, the assertion)
- [ ] A2.7 `apply-deploy-pipeline-fix.yml` `paths:` filter — **(R11)** host-delivered artifacts only; `server.tf` stays deliberately excluded

### A3 — Stop the dark branch lying (minimum Phase 1)

- [ ] A3.1 Write the failing test FIRST. **(R26)** Add a `MOCK_DOPPLER_GET_FAIL` seam (download OK, `get` non-zero) — the existing `MOCK_DOPPLER_FAIL` aborts *before* `zot_gate_and_login` is reached, so the required fixture does not exist today
- [ ] A3.2 Pair every negative assertion with a **positive control** — a negative-only AC passes on unmodified code
- [ ] A3.3 `ci-deploy.sh:1359/1361/1374-1377` + `ghcr_prelude_and_login`: emit `SOLEUR_DEPLOY_CRED_FAIL rc=<n> empty=<0|1> err="<=200B, control-stripped, dp.st.-redacted>"`. **Observation, not a five-value taxonomy**
- [ ] A3.4 **(R25)** Keep the branch fail-**open** for a transient/network shape (retry-then-degrade); terminal only for a credential-shaped failure. `zot_gate_and_login` is documented "never aborts the deploy" (`ci-deploy.sh:1344`) and `cloud-init.yml:424-426`'s cold-boot path depends on it
- [ ] A3.5 **(R3.4)** `systemd-analyze verify` gate before `infra-config-apply.sh` schedules its self-restart
- [ ] A3.6 **(R3.5)** systemd-in-container rehearsal (`TEST_DESTDIR` + `systemd-analyze verify`), reusing the `fresh-boot-parity.test.sh` / rung-2 precedent — proof, not belief

### A4 — Close the notification hole + records

- [ ] A4.1 `web-platform-release.yml`: terminal `release-outcome` job, `if: always()`, `needs:` every upstream. Fires on the **first** failure — 3 of 8 never reached `deploy`. **(R27)** No edit needed for the reason enum: the `case` at `:706` is on `$EXIT_CODE` and already echoes reason at `:728-732`
- [ ] A4.2 Update issue #7095's title/body to name the real cause

### A5 — Prove it

- [ ] A5.1 **(R22)** Second `terraform apply` + verify pass in the same job; first pass's `missing_env` recorded as **expected**
- [ ] A5.2 **(R23)** AC25's subject is the apply workflow's **own post-apply redeploy** (`apply-deploy-pipeline-fix.yml:526`, gated on `reason ∈ {ok, ok_peer_fanout_degraded}`), not "the next release" — the release and the apply race on the same push
- [ ] A5.3 **(R37)** Zero `doppler run` unit failures on **either** web host in Better Stack 30 min post-apply — the one AC that would have caught R1
- [ ] A5.4 **(R2)** Positive control: restart the log shipper post-apply and assert rows still arrive
- [ ] A5.5 **(R34)** Verify step distinguishes 404 (no endpoint) from 000/502 (webhook down); names the `server.tf:564/615` fallback as recovery

---

## PR-B — Harden (after prod is deploying again)

### B1 — Telemetry off the box

- [ ] B1.1 `vector.toml` Source-4 entries **and** `SyslogIdentifier=` stamps on `container-restart-monitor`, `cron-egress-resolve`, `cron-egress-alarm` — an allowlist entry without a stamp is a dead no-op
- [ ] B1.2 Two-sided drift guard for `ci-deploy` ↔ `vector.toml:154` (none exists today)
- [ ] B1.3 `doppler_read_failed` terminal reason + **(R27)** the canonical taxonomy row in `postmerge/references/deploy-status-debugging.md:43-79` and the `apply-deploy-pipeline-fix.yml:771` hardcoded string

### B2 — Continuous credential liveness (reuse, do not build — R17)

- [ ] B2.1 ~10 lines in `web-zot-consumer-probe.sh`: read the deploy token into a **local var**, `doppler secrets get ... --token "$t"`, emit `SOLEUR_DEPLOY_CRED ok=0|1 rc= empty=`. **Do NOT add the file to the unit's `EnvironmentFile`** — that silently widens the probe from read-scoped to full-`prd`
- [ ] B2.2 **(R17)** No new `betteruptime_heartbeat`, no manifest row, no `-target=`, no `arm_one` — all deleted. Dissolves the arming-order hazard that could red the fix merge
- [ ] B2.3 **(R19)** Sentry field set gains `home` + `config_dir` (the H7a-vs-H8 discriminators)

### B3 — Alerting

- [ ] B3.1 **(R12)** Inngest dispatch-hybrid, not a raw GHA `schedule:` — documented jitter up to **339 min** forces a 480-min margin that a 2h cadence cannot carry
- [ ] B3.2 Watcher condition A (consecutive failures). **(R30)** `--json` must include `status`; filter `status == "completed"`; `failure`/`timed_out` count, `cancelled`/`skipped`/`neutral` do not
- [ ] B3.3 Condition B (prod behind latest tag). **(R33)** Poll **both** per-host origins; fire if either is behind. **(R13)** Staleness window must be < the poll interval
- [ ] B3.4 **(R32)** `ops/prod-stale-ack` suppression for intentional rollbacks; comment only on **state change**
- [ ] B3.5 **(R12)** Route the page through Resend email — a GitHub issue is not a page. **(R35f)** `gh label create --force` idempotently on first fire; no operator step
- [ ] B3.6 **(R19)** Embed the last `SOLEUR_DEPLOY_CRED` + `ZOT_GATE` lines in the issue body — Better Stack retains 3 days; this is the only durable transcription
- [ ] B3.7 **(R31)** AC26a (first run DOES fire — the missing positive control) + AC26b (healthy after AC25) + a fixture-driven streak-counter unit test

### B4 — web-2 and the fleet generalisation

- [ ] B4.1 **(R9)** Pre-decided as option (b): a guarded `terraform_data` sibling with `connection.host = hcloud_server.web["web-2"]`. Option (a) invents a new full-`prd` credential transit path
- [ ] B4.2 `vector.toml` to web-2 (unconditional — "web-2 is silent" is currently indistinguishable from "web-2 is fine")
- [ ] B4.3 **(R9)** Follow-up issue: **19 of 19** host installers are pinned to web-1; `for_each` over `var.web_hosts` is the invariant
- [ ] B4.4 **(R28)** Static pre-merge test that the new `for_each` uses the siblings' existence predicate; move the plan-output grep into the apply workflow
- [ ] B4.5 **(R9)** Correct the plan's blanket "no SSH" claim — true for web-1 only

### B5 — Records

- [ ] B5.1 **(R4)** `schedule: 0 */12 * * *` on `apply-deploy-pipeline-fix.yml`, **and** state in ADR-154 that self-heal holds only for rotations that write back to `soleur/prd_terraform`
- [ ] B5.2 ADR-154, incl. **(R14)** the copy invariant: *no secret may be copied into a second host file without the copy inheriting the original's re-delivery path*
- [ ] B5.3 ADR-096 clause (f-4) amendment + the three `model.c4` edits (`:182`, `:423`, `:433`)
- [ ] B5.4 Correct the 07-29 PIR (it genuinely recovered at 21:29:48); write the 07-30 PIR carrying §Root Cause Evidence
- [ ] B5.5 **(R16)** The guard worth writing: every `betteruptime_heartbeat` has a matching `arm_one` line or an `arming_pending` manifest row — the worst silent-rot pair in the repo

---

## AC hygiene (R20, R35) — apply to both PRs

- [ ] Cut AC2 (fold into AC1), AC3, AC6, AC9, AC12, AC13, AC18, AC19, AC20, AC21, AC26, Phase 7.4
- [ ] Keep and prioritise AC10 + AC11 — an omitted `-target=`/`paths:` entry fails **silently**, the exact bug class that produced this outage
- [ ] **(R29)** AC14 uses `bash -n`, never `bash -c` (which would execute `gh issue create` in CI)
- [ ] **(R24)** Every file in §Files to Create has a row in §Files to Edit that installs it, or it is a dead artifact
