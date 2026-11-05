---
branch: feat-one-shot-11923-11920-rotation-gates
created: 2026-11-05
---

# Decision Challenges — feat-one-shot-11923-11920-rotation-gates

Rulings for the plan at
`knowledge-base/project/plans/2026-11-05-feat-rotation-approval-gate-egress-restart-plan.md`
(issues #11923 + #11920).

This session is a one-shot planning subagent with **no Task/subagent spawn tool**:
`soleur:engineering:cto` could not be invoked, so every technical row carries
`pending - assumed: <default>` per the technical-ruling-delegation contract. The
defaults below were derived from repo evidence (cited per row); the work phase
should upgrade any row the implementer finds contested.

| Item | Class | Ruling |
|------|-------|--------|
| Approval mechanism shape for #11923: dedicated no-secret `approve` job bound to a NEW reviewer-gated environment `key-rotate-approval`, vs rebinding the apply job's `environment:` (which would force operator-seeding `DOPPLER_TOKEN_INFRA_PRIVILEGED` onto a second environment — the TF App cannot write environment secrets, ADR-100 fix-forward, and Tier-B values are operator-seeded out-of-band, ADR-241) | technical | pending - assumed: dedicated `approve` job + new env `key-rotate-approval` (reviewers.users=[54279], custom branch policy `main`, `prevent_destroy` on the policy). Zero new secret material; mirrors the `inngest-cutover` job-level gate precedent (inngest-arm-write-token.tf); `infra-privileged` stays reviewerless because unattended apply-on-merge needs it (infra-privileged-environment.tf:32-49). |
| No-SSH vector restart lever for #11920: extend `ci-deploy.sh`'s existing `restart` action to accept component `vector` (running `sudo /usr/bin/systemctl try-restart vector.service` — the EXACT argv of the already-live `DROPIN_TRY_RESTART` sudoers grant) + `fan_out_to_peers`, vs a dedicated `/hooks/vector-restart` hook + new script, vs a new sudoers alias | technical | pending - assumed: extend the `restart` action with `vector`, reusing `DROPIN_TRY_RESTART` (deploy-inngest-bootstrap.sudoers:133). A dedicated hook is cut (new file, new FILE_MAP row, no free status-frame machinery); a new sudoers alias is cut (the file is root-managed — infra-config-apply.sh:217 — and only reaches running hosts via the SSH `terraform_data.deploy_pipeline_fix` provisioner, which is the thing the issue wants to avoid). `try-restart` (not `restart`): an inactive vector must stay inactive; the verify step fails loudly instead. |
| `EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS` lifecycle: `doppler_secret` fed by sensitive `variable "egress_audit_ingest_token_previous"` (default `""`) + `lifecycle { ignore_changes = [value] }`, written by `-replace` (set = old token, clear = `""`) vs a `doppler_secrets` data-source-driven value | technical | pending - assumed: TF_VAR + `ignore_changes=[value]` + `-replace`-to-write — the exact pattern the four `inngest_*` secrets already use (KR_GATE_TABLE flag=replace). The data-source form cannot express "clear" (it tracks CURRENT with a one-apply lag) and produces perpetual drift noise during every grace window; `ignore_changes` suppresses routine-apply diffs so a merge apply can neither drift-flag nor early-clear PREVIOUS. The var name ends `_previous`, never `_token`/`_pat` (deepen-plan Phase 4.8 PAT-shaped halt). |
| Where the "clear PREVIOUS" apply runs: new `clear` job after `redeploy`+vector-restart vs folding into an existing job | technical | pending - assumed: new `clear` job (`environment: infra-privileged`, `terraform-apply-web-platform-host` group). It must run AFTER the fleet's Vector restart is verified (the grace-window close needs the ordering), and only the Terraform jobs hold Tier-B creds, so it cannot fold into `redeploy` (no creds) or `notify` (issues-only). |
| `approval_environment_missing` rung once the env is bound: repurpose `kk_chk_approval` into a LIVE verify of `protection_rules` via `gh api .../environments/key-rotate-approval` (fail closed on API error; verdict renamed `approval_environment_unprotected`) vs deleting the rung | technical | pending - assumed: live-verify, renamed verdict. Covers the vacuous-gate window: a referenced-but-unapplied environment auto-creates UNPROTECTED (#6780 learning), so structural binding alone can silently degrade; the live read makes the guard self-reporting. |
| `authorization_stale` baseline once an approval wait exists: reset the epoch to the approve job's output (`approval_epoch`) vs keep `guard_epoch` | technical | pending - assumed: approval_epoch. `KK_AUTH_MAX_AGE_S=3600` measures from guard; an approval queue can sit for hours — measuring from approval preserves the "fresh human go" invariant without making every slow approval self-refuse. The sibling's `reboot` job already has an `admit` re-check designed for "an approval wait of any length" (inngest-key-rotate.yml:224). |
| Approval scope: all `mode=rotate`/`converge` dispatches vs only the formerly-refused key set (`inngest_manual_trigger_secret_prd`, `kb_drift_ingest_signing_key`, `github_webhook_secret`) | technical | pending - assumed: all rotate dispatches (uniform gate). `mode=plan` never gates (writes nothing). Uniform is simpler than a per-key `if` and exercises the gate on every dev-shakedown rehearsal; the extra click is the feature, not a cost. |
| Vector-restart verification shape: per-host `deploy-status` frame (`component=vector`, `reason=success`, `start_ts` > baseline, merged peer view) + in-handler `is-active` + `ActiveEnterTimestamp` delta vs a Better Stack journald poll | technical | pending - assumed: deploy-status frames as primary (same mechanism as restart-inngest-server.yml), journald `SUCCESS: restart vector` markers + post-clear ingest-reject silence as corroboration, not the blocking read. |
| Brand-survival threshold | taste | `single-user incident` — matches the parent key-rotation plan's ruled threshold (its Domain Review recorded CPO advisory at single-user-incident). A botched rotation route change can wedge credential rotation mid-incident and an unprotected-environment regression converts the sole human authorization into none; both are operator-facing blast radius, though no end-user data path depends on the egress token itself (issue #11920: "best-effort observability; a same-host hop"). |

## Not Yet Specified

None.
