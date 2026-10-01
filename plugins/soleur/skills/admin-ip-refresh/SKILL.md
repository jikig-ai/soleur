---
name: admin-ip-refresh
description: "This skill should be used to refresh the prod SSH allowlist (Doppler ADMIN_IPS) after operator IP rotation. Detects drift, mutates Doppler with explicit ack."
disable-model-invocation: true
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# admin-ip-refresh

Detects drift between the operator's current public IP and the Hetzner Cloud Firewall allow-list (`Doppler prd_terraform/ADMIN_IPS`), proposes a corrective Doppler mutation with explicit operator ack, and emits the exact `terraform apply` invocation for the operator to run. Does NOT call Terraform directly -- per AGENTS.md `hr-all-infrastructure-provisioning-servers`, infra apply stays operator-initiated.

## When to use

- Reactive: operator can no longer SSH into `soleur-web-platform`, and `admin-ip-drift.md` diagnosis points to a firewall-layer drop (no `journalctl -u ssh` entry for the operator IP).
- Proactive: operator notices their IP may have rotated (router reboot, travel, ISP change). Run pre-emptively to update `ADMIN_IPS` before the next SSH attempt fails.

## Arguments

<arguments> #$ARGUMENTS </arguments>

Accepted flags:

- `--dry-run` -- run detect/read/diff/warn steps (1-4) only. No writes. Useful for pre-incident hygiene checks.
- `--verify` -- re-run the diff step only (no mutation). Useful after an operator has run `terraform apply` to confirm the firewall rule matches.
- `--fast` -- emit the narrow-target `terraform apply -target=hcloud_firewall.web` form alongside the full-graph form. Default output emits the full-graph form only, per HashiCorp guidance that `-target` is for rare/recovery cases.

## Prerequisites

- `doppler` CLI authenticated (`doppler configure get token --plain` returns a token).
- `hcloud` CLI authenticated (for post-apply verification; optional for steps 1-6).
- `curl` on PATH.
- `terraform` on PATH (skill prints the invocation; operator runs it).

If `doppler` or `curl` is missing, abort with an install hint. Do not attempt to install them from the skill -- per AGENTS.md, the Bash tool runs without sudo.

## Procedure

Read [admin-ip-refresh-procedure.md](./references/admin-ip-refresh-procedure.md) for the full step-by-step procedure, including the egress-IP detection fallback chain, Doppler mutation pattern, and `terraform apply` emission. The sequence below is the abbreviated form.

1. **Detect egress IP** via three-service fallback (`ifconfig.me` -> `api.ipify.org` -> `icanhazip.com`) with strict timeouts (`--connect-timeout 5 --max-time 10`) and IPv4 regex + octet-range validation. Abort with exit 3 if all three fail.
2. **Read current `ADMIN_IPS`** via `doppler secrets get ADMIN_IPS -p soleur -c prd_terraform --plain`. Parse as JSON list. Abort if the secret is missing.
3. **Diff.** If `<current-egress>/32` is in the list, print "No drift." and exit 0. If absent, show the pre-image list and the proposed post-image list (current list with `<egress>/32` appended).
4. **Warn on list-length invariants.** Post-image length == 1 triggers a P1 warning (no rotation margin). Post-image length > 10 triggers a P2 warning (stale residue, review-and-prune recommended).
5. **Operator ack.** Print the exact `doppler secrets set` invocation the skill will run. Wait for literal `yes` per-command ack -- no `--yes`, no `-auto-approve`, per AGENTS.md `hr-menu-option-ack-not-prod-write-auth`. Under the length-1 warning in Step 4, also require a literal `understood` ack before reaching this step.
6. **Write Doppler.** Stdin-piped from a 0600 temp file (no CLI-arg value, no `ps auxf` leak), `--silent` to prevent value echo per Doppler's setting-secrets guide. Re-read the secret and compare byte-for-byte. Print the Doppler dashboard activity URL.
7. **Emit `terraform` invocations.** Print the exact `terraform plan` and `terraform apply` commands (and, under `--fast`, the `-target=hcloud_firewall.web` variants) for the operator to run. Do NOT execute them.
8. **Verify prompt.** Ask whether the operator ran `terraform apply`. On "no", record the gap in the session output and suggest a follow-up `--verify` invocation.

## Exit codes

The skill exits non-zero on failure so cron/one-shot invocations do not silently no-op. Full contract in [admin-ip-refresh-procedure.md](./references/admin-ip-refresh-procedure.md) §"Exit codes".

- `0` -- success (no drift OR drift corrected + operator acked + invocation emitted).
- `3` -- all three IP-detection services failed.
- `4` -- Doppler read or write failed.
- `5` -- operator refused the mutation (rejected the `yes` prompt OR the `understood` single-entry prompt).

## Sharp Edges

- **Never run `terraform apply` from the skill.** Per AGENTS.md `hr-all-infrastructure-provisioning-servers`, infra writes are operator-initiated. The skill's job is detection + Doppler mutation + command emission.
- **Nested `doppler run` when running Terraform.** The `apps/web-platform/infra/` root uses `doppler run --name-transformer tf-var` to hydrate `TF_VAR_*` variables from Doppler. The skill's emitted commands match this pattern (see AGENTS.md `cq-when-running-terraform-commands-locally`).
- **The emitted apply fails three ways on this root unless prepared.** (1) The S3 backend sets `use_lockfile`, so the local binary must be the workflows' `TERRAFORM_VERSION` (≥1.10; a 1.9.x errors at `init`). (2) `--name-transformer tf-var` renames `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` too, so the R2 backend sees no credentials; export those two from `prd_terraform` directly, then run the single `tf-var` `doppler run` (a nested `doppler run` inherits a token that cannot read `prd_terraform`). (3) Run from a clean `origin/main` checkout, save a `-target=hcloud_firewall.web` plan with `-out`, and confirm its only change is the added port-22 rule before applying that saved plan. **Why:** #8511 — all three hit in one session.
- **VPN / Cloudflare WARP:** `ifconfig.me` returns the egress IP the internet sees, which IS what the firewall sees. If the operator is on a VPN, adding the VPN egress to `ADMIN_IPS` is the correct behavior -- do not attempt to detect the "real" home IP behind the VPN.
- **Doppler value echo protection.** Every `doppler secrets set` uses `--silent` and stdin-piped values. Temp files are 0600 and `shred -u`'d on exit. `ADMIN_IPS` is a list of operator egress IPs -- PII-adjacent under most interpretations, and log aggregators must not capture it.
- **IP-detection spoofing.** The three-service fallback defends against upstream-routing anomalies where one provider returns stale or non-IPv4 content. Validate every response against `^([0-9]{1,3}\.){3}[0-9]{1,3}$` AND octet-range (<= 255) before accepting.
- **Single-entry allow-list.** A post-image list of length 1 has no rotation margin. The skill requires the operator to type `understood` to proceed, nudging toward 2-3 known-good CIDRs (home + mobile hotspot + travel).

## Related

- Runbook: `knowledge-base/engineering/operations/runbooks/admin-ip-drift.md`
- Plan: `knowledge-base/project/plans/2026-04-19-ops-admin-ip-drift-prevention-plan.md`
- Institutional learning: `knowledge-base/project/learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`
- AGENTS.md rules: `hr-ssh-diagnosis-verify-firewall`, `hr-all-infrastructure-provisioning-servers`, `hr-menu-option-ack-not-prod-write-auth`.
