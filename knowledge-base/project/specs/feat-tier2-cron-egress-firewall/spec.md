---
title: "Tier-2: Cron Egress Firewall + Least-Privilege Token + Restore Paused Crons"
status: draft
issue: "#5046"
related: "#5018"
branch: feat-tier2-cron-egress-firewall
created: 2026-06-09
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tier-2: Cron Egress Firewall + Least-Privilege Token + Restore Paused Crons

## Problem Statement

Tier-1 (PR #5018, merged 2026-06-08) shipped a deny-by-default `PreToolUse` hook +
`sandbox.enabled:false` and **paused** 11 claude-spawning crons (`TIER2_DEFERRED_CRONS`) to
avoid a fail-closed alert storm. Two gaps remain:

1. The 11 paused crons (the founder's autonomous marketing/ops surface — growth audit,
   competitive analysis, bug-fixer, etc.) are **dark**, with no durable boundary to restore them.
2. Four `spawn("bash")` crons (`content-publisher`, `content-vendor-drift`, `rule-prune`,
   `weekly-analytics`) bypass the #5018 hook entirely (ADR-033 invariant I7) and are **running
   live, uncontained today** — registered in `cron-manifest.ts` with no defer guard — holding
   `GH_TOKEN` + 12 social-API secrets with unrestricted egress. A network boundary is their
   ONLY possible containment.

Additionally, `generateInstallationToken` mints a token with the GitHub App's full default
grant (POSTs no `permissions`/`repositories` body, `github-app.ts:729-732`).

## Goals

1. Restore the 11 hook-containable crons in output-quality-gated waves (top-3 first:
   bug-fixer, competitive-analysis, growth-audit) via the existing #5018 hook +
   per-cron `CRON_BASH_ALLOWLISTS`.
2. Contain the 4 live `spawn("bash")` crons via a hybrid: host egress firewall
   (SNI-allowlist proxy + nftables kernel default-drop) AND move `content-publisher`
   to an ephemeral GitHub Actions runner (ADR-033 Option C).
3. Narrow the cron-path installation token to one repo-scoped
   `contents:write`+`issues:write` token at `mintInstallationToken` (`_cron-shared.ts:119`).
4. Surface every firewall block LOUD (Sentry `egress_blocked` + Inngest throw + output canary),
   never fail green.

## Non-Goals

- Per-cron least-privilege tokens (YAGNI — single repo-scoped token; defer to a follow-up if
  multi-tenant cron isolation materializes).
- Editing `generateInstallationToken`'s ~10 non-cron call sites (scope the change to the cron
  mint path only).
- Touching repo-root `.claude/settings.json` or `server/workspace.ts` (dev/user-workspace
  sandbox stays enabled — runtime overlay `DEFAULT_CLAUDE_SETTINGS` is the cron write site).
- Hetzner Cloud Firewall for egress (IP/port only — CDN-IP allowlisting is brittle).
- **Moving `content-publisher` to an ephemeral GHA runner** (former hybrid scope) — **deferred**
  per plan-review: PR-2's container egress boundary already closes the exfil path, so the GHA move
  is a second mitigation for an already-closed threat. Tracked as a follow-up; revisit only if the
  allowlist proves insufficient for `content-publisher` specifically.
- **SNI forward proxy** up front — allowlist-first; proxy is an evidence-gated escalation only.

## Functional Requirements

- **FR1** — Restore the 11 `TIER2_DEFERRED_CRONS` in waves of 2-3, gated on a per-cron
  output-quality check, removing each from the set + populating `CRON_BASH_ALLOWLISTS` (or
  classifying it as needs-firewall). First wave: bug-fixer, competitive-analysis, growth-audit.
- **FR2** — Container egress firewall: nftables rules in the **`DOCKER-USER` chain** (container-scoped,
  NOT host OUTPUT — host control plane / cloudflared tunnel must stay reachable), default-drop +
  hostname/IP allowlist with **periodic IP re-resolve** (allowlist-first; no SNI proxy up front —
  evidence-gated escalation only). Allowlist: `api.anthropic.com`, `github.com` + `api.github.com`,
  Sentry ingest, **Inngest**, Supabase, Doppler, Flagsmith, Better Stack (if container-shipped),
  social-write hosts (X/LinkedIn/Bluesky), Discord webhook. Deny everything else.
- **FR3** — Narrow the cron token: additive `permissions?` opt on `mintInstallationToken`
  (`_cron-shared.ts:119`), defaulted to `contents:write`+`issues:write` repo-scoped to soleur.
  **Folded into PR-1** (same file as the restore edit).
- **FR5** — A blocked egress request emits a Sentry event tagged `egress_blocked` (with
  destination host), the Inngest function throws (heartbeat misses), and a per-cron post-run
  output canary pages on missing artifact.

## Technical Requirements

- **TR1** — Firewall provisioned via SSH `terraform_data` provisioner (NOT cloud-init):
  `hcloud_server.web` has `ignore_changes=[user_data]` (server.tf:57-59). Key on
  `{file-hash, server_id}` so a fresh VM re-runs it (`hr-fresh-host-provisioning`). Apply path
  reachable from `terraform apply` (`hr-every-new-terraform-root`, `hr-all-infrastructure-provisioning`).
- **TR2** — The egress allowlist MUST include the Sentry ingest domain, or heartbeat POSTs fail
  silently and monitors go dark.
- **TR3** — Dark-launch: firewall + restore gates ship log-only first, observed passing on ≥1
  real run, then promoted (`wg-dark-launch-deploy-gates`). Validate deny-behavior via
  `/soleur:trigger-cron` while crons stay paused.
- **TR4** — The #5018 `PreToolUse` hook remains load-bearing (the firewall does NOT subsume the
  allowlisted-but-abusable `gh issue create --body $secret` → public-repo path). Preserve the
  spawn-time `runHookSelfTest`.
- **TR5** — Token-override test seeds a bogus ambient `GH_TOKEN` and asserts the subprocess sees
  the minted narrowed token (test the override, not just presence).

## Acceptance Criteria

- AC1 — All 11 deferred crons either restored (removed from `TIER2_DEFERRED_CRONS`, validated via
  `/soleur:trigger-cron`, output issue appears) or explicitly classified needs-firewall.
- AC2 — `curl`/`fetch` to a non-allowlisted host from inside the cron container fails (kernel-level
  drop verified); allowlisted hosts succeed.
- AC3 — A simulated egress block produces a Sentry `egress_blocked` event AND a missed heartbeat
  (not green).
- AC4 — `content-publisher` runs on an ephemeral GHA runner; no social secrets on the host env.
- AC5 — Minted cron token's `permissions` are `contents:write`+`issues:write` only (asserted),
  repo-scoped.

## Sequencing (operator: restore-first, value-led; firewall-only post-plan-review)

- **PR-1** (this branch) — Restore the **allowlistable subset** of the 11 (per PR-1 bash-surface
  re-triage; un-paused in operational waves) **+ narrow the cron token** (folded). Fast founder value;
  firewall-independent for the proven-allowlistable subset only.
- **PR-2** — Container egress firewall (DOCKER-USER allowlist-first). Contains the live 4 + restores the
  needs-firewall crons. *Expedite immediately after PR-1; interim stopgap for the live 4 decided in PR-1.*
- **Deferred** — `content-publisher` → ephemeral GHA (re-evaluate only if PR-2's allowlist is
  insufficient for it).

## Open Questions

See brainstorm `knowledge-base/project/brainstorms/2026-06-09-tier2-cron-egress-firewall-brainstorm.md`
(per-cron bash-allowlist triage; exact egress host set; GHA migration shape; interim stopgap for
the live 4 during the restore-first gap; nftables SSH-provisioner keying).
