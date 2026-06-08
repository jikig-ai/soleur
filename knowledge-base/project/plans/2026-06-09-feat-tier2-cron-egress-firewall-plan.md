---
title: "Tier-2: Cron Egress Firewall + Least-Privilege Token + Restore Paused Crons"
type: feat
issue: "#5046"
related: "#5018"
branch: feat-tier2-cron-egress-firewall
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
created: 2026-06-09
---

# Tier-2: Cron Egress Firewall + Least-Privilege Token + Restore Paused Crons

🛡️ Follow-up to Tier-1 PR #5018 (MERGED 2026-06-08). Brainstorm + decisions:
`knowledge-base/project/brainstorms/2026-06-09-tier2-cron-egress-firewall-brainstorm.md`.
Spec: `knowledge-base/project/specs/feat-tier2-cron-egress-firewall/spec.md`.
**Plan-review applied (2026-06-09):** firewall-only containment (content-publisher→GHA deferred);
allowlist-first egress mechanism (no SNI proxy up front); token narrowing folded into PR-1; restore
re-triage owned explicitly. See `## Plan-Review Resolution`.

## Overview

Two cron populations need different containment:

- **11 paused claude-crons** (`TIER2_DEFERRED_CRONS`, `_cron-shared.ts:196`) — *candidates* for
  restoration via the existing #5018 `PreToolUse` hook (`cron-bash-allowlist-hook.mjs`) + per-cron
  `CRON_BASH_ALLOWLISTS` (`_cron-claude-eval-substrate.ts:139`), **only for the subset that PR-1's
  triage proves finitely-allowlistable** (see the re-triage note below).
- **4 live `spawn("bash")` crons** (`content-publisher`, `content-vendor-drift`, `rule-prune`,
  `weekly-analytics`) — bypass the hook (ADR-033 I7), running **uncontained today**. Contained by a
  container-scoped (`DOCKER-USER` chain) egress allowlist (PR-2).

**Re-triage note (Kieran C1).** The defer-set's recorded rationale (`_cron-shared.ts:183`) is "bash
that *cannot* be expressed as a finite allowlist." So restoring any of the 11 *via allowlist*
necessarily **re-triages** the original Tier-1 classification — asserting it was too coarse for the
read-heavy audit crons. This plan owns that: PR-1 produces bash-surface evidence **before** any
restore commitment (AC1). Restore is therefore "independent of the firewall" **only for the subset
proven allowlistable**; the rest wait for PR-2.

Operator decisions: **firewall-only containment** (content-publisher→GHA deferred — see `## Deferred`)
+ **restore-first sequencing** + **allowlist-first egress mechanism**. Two PRs. PR-1 (restore + token)
is this branch; PR-2 (firewall) is a sequenced follow-on branch, deepen-planned when reached.

## Research Reconciliation — Spec vs. Codebase

| Issue-body / spec claim | Reality (verified) | Plan response |
|---|---|---|
| `CRON_BASH_ALLOWLISTS` in `_cron-shared.ts` | `_cron-claude-eval-substrate.ts:139` (`Record<string,string[]>`, consumed `:316` `?? []` → fail-closed). `TIER2_DEFERRED_CRONS` is `_cron-shared.ts:196`. | Edit the substrate file for allowlists; the defer-set in `_cron-shared.ts`. |
| Restore the 11 "via allowlist" is independent of the firewall | Defer-set *definition* = "cannot be finitely allowlisted" (`_cron-shared.ts:183`). | Re-triage explicitly; evidence-before-restore (AC1); independence holds only for the allowlistable subset. |
| Egress allowlist = "anthropic + github + community **read** APIs" | `content-publisher` does social **writes** (`*_ALLOW_POST:"true"`, 12 secrets); `weekly-analytics` POSTs Discord. **Inngest control plane** is also required (the fail-loud heartbeat throw must reach it). | Allowlist must cover Anthropic, `github.com` (git) + `api.github.com` (token-mint), Sentry-ingest, **Inngest**, Supabase, Doppler, Flagsmith, Better Stack (if Vector ships from the container), social-write hosts, Discord webhook. |
| Host "provisioned outside this IaC" | Host IS Terraform-managed: `hcloud_server.web` (`server.tf:21`), `hcloud_firewall.web` (`firewall.tf:1`, inbound-only). | Egress added via the SSH-provisioner path (`docker_seccomp_config` template, `server.tf:573`). |
| `generateInstallationToken` "broadly scoped" | POSTs no body (`github-app.ts:708-733`) → full default grant; narrowing params unused. ~10 call sites incl. interactive routes. | Narrow at the **cron-only** `mintInstallationToken` (`_cron-shared.ts:119`); folded into PR-1. |
| Firewall "on the cron worker" (host-level implied) | Host outbound is the control plane: cloudflared tunnel (app + CI-deploy SSH route #4829), GHCR, Doppler, apt, Sentry. Container runs on the default Docker bridge (`ci-deploy.sh:457,635`, no `--network`). | Scope egress to the **container** via `DOCKER-USER` — NOT host OUTPUT. |

## Hypotheses — Egress-firewall self-lockout (L3→L7 discipline)

The Network-Outage gate fired on `firewall` + SSH-provisioner `terraform apply`. This plan **adds** a
firewall, so the discipline is applied to the outage it could *cause*. Unverified layers first:

1. **L3 — host control-plane egress (cloudflared tunnel).** Host dials OUT to CF edge for the tunnel
   serving ALL app traffic + the CI-deploy SSH route (#4829, `server.tf:346`). Host-level OUTPUT
   default-drop severs this → full outage + un-deployable host. **Mitigation: `DOCKER-USER` scoping
   (container only); never touch host OUTPUT.** [Kieran verified: container on default bridge, so
   DOCKER-USER catches container egress incl. `spawn("bash")` children, leaves host OUTPUT untouched.]
2. **L3 — container required egress (allowlist).** Must reach: `api.anthropic.com`, `github.com` +
   `api.github.com`, the Sentry ingest cluster host (else heartbeats POST-fail silently → monitors
   dark, `_cron-shared.ts:126`), **Inngest** (the fail-loud heartbeat throw must reach the Inngest
   control plane — if darked, fail-loud itself fails), Supabase, Doppler, Flagsmith, Better Stack (if
   Vector ships from the container vs the host — confirm at PR-2), social-write hosts, Discord webhook.
   Each entry verified reachable in PR-2's deny-list AC.
3. **L3 — the apply path.** nftables applied via SSH `terraform_data` provisioner (admin_ips-gated :22,
   or CF-tunnel in CI). DOCKER-USER scoping leaves host :22 untouched, so the provisioner's return path
   survives. A `connection reset` on apply = admin-IP drift (`/soleur:admin-ip-refresh`), NOT firewall —
   `hr-ssh-diagnosis-verify-firewall`. [verified: SSH:22 ingress admin_ips-only, `firewall.tf:5`]
4. **L7 — fail-loud on block.** A denied egress surfaces (Sentry `egress_blocked` + Inngest throw →
   missed heartbeat), never green. [Observability + PR-2 AC]

## User-Brand Impact

**If this lands broken, the user experiences:** a restored cron silently fails (allowlist gap) and the
founder loses weekly output with monitors green; OR (PR-2) the cloudflared tunnel is severed and the
whole app + deploy path goes dark.

**If this leaks, the user's data/credentials are exposed via:** an over-broad installation token
(cross-repo write) or an egress gap on a `spawn("bash")` cron exfiltrating agent-context
(`ANTHROPIC_API_KEY`, `GH_TOKEN`, KB/operator-prompt content) to an attacker endpoint. KB/prompt
content can contain personal data → conditional GDPR Art. 33 72h clock (CLO; gdpr-gate confirmed no
schema/Chapter-V finding, CLO carry-forward sufficient).

**Brand-survival threshold:** single-user incident. → CPO sign-off carried forward from brainstorm
Phase 0.1; `user-impact-reviewer` runs at PR review.

## Implementation Phases

### Phase 1 — PR-1: Restore allowlistable crons + narrow the cron token (THIS branch)

**1.0 Per-cron containment re-triage (evidence-first; AC1 gates on this).** For each of the 11 in
`TIER2_DEFERRED_CRONS`, read its prompt's actual bash surface and classify with cited evidence:
- **allowlistable** → add a `CRON_BASH_ALLOWLISTS[<cron>]` entry modeled on the proven
  `cron-roadmap-review` entry (`_cron-claude-eval-substrate.ts:139`); remove from `TIER2_DEFERRED_CRONS`.
- **needs-firewall** (broad/dynamic bash — e.g. likely `bug-fixer` (creates PRs, runs tests),
  `growth-execution`, `content-generator`) → stays deferred; restored in PR-2.

  ⚠️ Do NOT pre-commit the split. The named candidates are hypotheses; the evidence decides. If
  `bug-fixer` (CPO's #1 restore priority) is needs-firewall, wave-1 becomes the proven-allowlistable
  audit crons and `bug-fixer` waits for PR-2 — surface this in the PR body, don't silently reshuffle.

**1.1 Restore the allowlistable subset; un-pause operationally in waves.** Land all proven-allowlistable
crons' allowlist entries + defer-set removals in PR-1 (one code change). The "waves of 2–3,
output-quality-gated" cadence (CPO) is **operational pacing of the un-pause**, not separate PRs or a
code-safety gate — roll out via the trigger schedule so the solo founder isn't re-flooded with 11
producers at once. Validate each via `/soleur:trigger-cron <event>`: output issue appears +
`runHookSelfTest` passes.

**1.2 Interim stopgap for the live 4 (decide IN this PR — Kieran).** Restore-first *adds* autonomous
surface while the firewall (PR-2) lags. Decide the cheap interim mitigation here, not at "PR-2 start":
flip `content-publisher`'s `X_ALLOW_POST`/`LINKEDIN_ALLOW_POST`/`BSKY_ALLOW_POST` to dry-run, OR accept
the bounded window (first-party prompts/scripts) with PR-2 expedited. Record the choice + rationale.

**1.3 Narrow the cron token (folded from former PR-4 — DHH).** Same `_cron-shared.ts` file PR-1 already
edits: add an additive `permissions?` option on `mintInstallationToken` (`:119`), defaulted to
`{ contents: "write", issues: "write" }` repo-scoped to soleur, passed as the POST body
`generateInstallationToken` (`github-app.ts:708-733`) currently omits. Do NOT touch the ~10 non-cron
call sites. Test the override (seed bogus ambient `GH_TOKEN`, assert subprocess sees the minted token).

### Phase 2 — PR-2: Container egress firewall (separate branch; deepen-plan first)

**Mechanism: allowlist-first (operator-chosen).** nftables rules in the **`DOCKER-USER` chain**,
default-drop + a hostname/IP allowlist with **periodic IP re-resolve** for the ~10 first-party SaaS
hosts (a small systemd timer re-resolving the allowlist hostnames into the nftables set). NO SNI
forward proxy up front — escalate to one only if a specific host's IP churn is observed in production to
defeat re-resolve (evidence-gated; YAGNI). Applied via a **9th `terraform_data` SSH provisioner**
modeled exactly on `docker_seccomp_config` (`server.tf:573`): `triggers_replace = { rules_hash,
server_id }` (the `server_id` fold is mandatory — `hr-fresh-host-provisioning`), `connection{type="ssh"}`
per the 8 siblings, positive post-apply assertions (`fail2ban_tuning` pattern). Mirror the rule file
into `cloud-init.yml` for fresh hosts. Restores the needs-firewall crons from Phase 1.0 once proven.

## Deferred

- **content-publisher → ephemeral GHA runner (former PR-3).** Deferred per plan-review (DHH +
  code-simplicity): once PR-2's container egress boundary exists, the 12 social secrets cannot
  exfiltrate off-allowlist, so the GHA move is a second mitigation for an already-closed threat.
  **Re-evaluation criterion:** revisit only if PR-2's allowlist proves insufficient for
  `content-publisher` specifically (e.g., it needs an unbounded/dynamic egress set the allowlist can't
  express). Tracked as follow-up **#5073**. The Option-C pattern is ready when
  needed (`trigger-workflow.ts` precedent: `cron-terraform-drift`, `cron-dev-migration-drift`,
  `cron-main-health-monitor`, `cron-review-reminder`).

## Files to Edit

**PR-1 (this branch):**
- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — remove restored crons from `TIER2_DEFERRED_CRONS` (`:196`); add `permissions?` to `mintInstallationToken` (`:119`).
- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — add `CRON_BASH_ALLOWLISTS` entries (`:139`).
- `apps/web-platform/server/github-app.ts` — thread the `permissions`/`repositories` POST body into `generateInstallationToken` (`:708-733`), additive + defaulted (cron path only).
- `apps/web-platform/test/server/inngest/cron-shared.test.ts` — assert defer-set/allowlist for restored crons + the token override (bogus ambient `GH_TOKEN` → minted narrowed token).
- (PR-1.2) `apps/web-platform/server/inngest/functions/cron-content-publisher.ts` — *only if* the dry-run stopgap is chosen.

**PR-2 (separate branch):** `apps/web-platform/infra/server.tf` (new `terraform_data` egress provisioner), `apps/web-platform/infra/cloud-init.yml` (fresh-host mirror), new `apps/web-platform/infra/cron-egress-nftables.sh` + a re-resolve timer unit, `apps/web-platform/infra/sentry/issue-alerts.tf` (`egress_blocked` alert).

## Files to Create

- `apps/web-platform/infra/cron-egress-nftables.sh` + re-resolve timer (PR-2)

## Open Code-Review Overlap

None (checked `gh issue list --label code-review --state open` against PR-1 files; no open scope-out names `_cron-shared.ts` / `_cron-claude-eval-substrate.ts` / `github-app.ts`).

## Acceptance Criteria

### PR-1 — Pre-merge
- AC1 — Each of the 11 classified allowlistable | needs-firewall in the PR body **with cited bash-surface evidence per cron** (evidence precedes any restore commitment).
- AC2 — Restored (allowlistable) crons removed from `TIER2_DEFERRED_CRONS`; each has a `CRON_BASH_ALLOWLISTS` entry; `cron-shared.test.ts` asserts both.
- AC3 — Minted cron token `permissions` = `contents:write`+`issues:write` only (asserted); override test (bogus ambient `GH_TOKEN` → minted token) passes.
- AC4 — Interim-stopgap decision for the live 4 recorded in the PR body with rationale.
- AC5 — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean + `./node_modules/.bin/vitest run test/server/inngest/cron-shared.test.ts` green.

### PR-1 — Post-merge (operator-automatable)
- AC6 — Each restored cron validated via `/soleur:trigger-cron <event>`; output issue appears; `runHookSelfTest` passes. (Automatable via the trigger-cron skill.)

### PR-2 (summarized; full ACs at deepen-plan)
- `curl` to a non-allowlisted host from inside the container fails; every allowlisted host (incl. Inngest + Sentry-ingest) succeeds; host egress (cloudflared/GHCR/Doppler/apt) verifiably unaffected; a simulated block → Sentry `egress_blocked` event AND a missed heartbeat.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from brainstorm `## Domain Assessments`).

### Engineering (CTO)
**Status:** reviewed (carry-forward + plan-review)
**Assessment:** DOCKER-USER-scoped egress (allowlist-first per operator; proxy is the evidence-gated escalation), fail-loud on block; YAGNI token cut at the cron mint path; validate deny via trigger-cron before live. Host/firewall ARE Terraform-managed; egress applies via the `docker_seccomp_config` SSH-provisioner template.

### Product (CPO)
**Status:** reviewed (carry-forward)
**Assessment:** Restore blocks the founder's autonomous surface. Restore allowlistable crons first, un-paused in operational waves (top-3 = bug-fixer, competitive-analysis, growth-audit — subject to the bash-surface triage); defer content-generation/campaign-calendar.

### Legal (CLO)
**Status:** reviewed (carry-forward + gdpr-gate)
**Assessment:** No legal gate — engineering-owned; no DPA/sub-processor disclosure moves with it. Conditional GDPR Art. 32/33 named in brand-survival; the #5018 hook stays load-bearing (firewall does not subsume the `gh issue create --body $secret` → public-repo path). gdpr-gate: no schema/Chapter-V finding, CLO carry-forward sufficient.

### Product/UX Gate
**Tier:** none — no UI surface (no `components/**`, `app/**/page.tsx`, modal/banner files). Pure infra/CI/server change.

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/server.tf` — new `terraform_data "cron_egress_firewall"` (PR-2), SSH provisioner, `triggers_replace = { rules_hash = sha256(file("cron-egress-nftables.sh")), server_id = hcloud_server.web.id }`. Provider: existing `hetznercloud/hcloud` pin. No new sensitive vars (rules are non-secret).
- `apps/web-platform/infra/cloud-init.yml` — fresh-host mirror (base64 `write_files`), per the sibling pattern.
- `apps/web-platform/infra/sentry/issue-alerts.tf` — `egress_blocked` issue alert (PR-2).

### Apply path
(b) cloud-init + idempotent SSH provisioner. `hcloud_server.web` carries `ignore_changes=[user_data]`
(`server.tf:58`) → cloud-init-only edit lands dead; the SSH `terraform_data` provisioner is the sole
live-prod apply path. Blast-radius: **container egress only** (DOCKER-USER) — host OUTPUT untouched, no
app downtime. PR-2 only — added to `apply-web-platform-infra.yml`'s `-target=` set.

### Distinctness / drift safeguards
`server_id` folded into `triggers_replace` so a replaced VM re-runs the provisioner
(`hr-fresh-host-provisioning`; exact `docker_seccomp_config` precedent). Shows as "will be created" in
CI drift reports — expected, like the 8 sibling SSH provisioners.

### Vendor-tier reality check
N/A — nftables/Docker are host-native; no paid-tier gate.

## Observability

```yaml
liveness_signal:
  what: per-restored-cron Sentry Crons heartbeat (postSentryHeartbeat, _cron-shared.ts:126) + output issue appears
  cadence: each cron's schedule
  alert_target: existing Sentry cron-monitors.tf monitor per cron
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry (reportSilentFallback/warnSilentFallback, observability.ts:183)
  fail_loud: true — PR-2 egress block throws (non-zero) so the heartbeat misses (requires Inngest in the allowlist); proxy/drop 403 logged to Sentry tagged egress_blocked
failure_modes:
  - {mode: firewall over-block (restored cron denied a needed host), detection: Sentry egress_blocked event + missed heartbeat, alert_route: Sentry issue alert (PR-2)}
  - {mode: Sentry-ingest OR Inngest host blocked → monitors/fail-loud dark, detection: monitor missed-check-in, alert_route: cron-monitors.tf (allowlist MUST include both)}
  - {mode: restored cron output not produced (allowlist too tight), detection: output-issue-absent canary per cron, alert_route: trigger-cron validation (PR-1) + missed heartbeat}
logs:
  where: journald → Vector → Better Stack; Sentry for errors
  retention: per journald-soleur.conf cap + Better Stack retention
discoverability_test:
  command: gh issue list --search "Growth Audit in:title" --json number,createdAt  # output-issue presence, no ssh
  expected_output: a recent issue for each restored cron after its first post-restore fire
```

## Risks

- **R1 (HIGH) — host vs container egress scope.** Host-level default-drop severs the cloudflared tunnel.
  Mitigation: DOCKER-USER scoping (Kieran-verified). PR-2 must prove "host egress unaffected" explicitly.
- **R2 (HIGH) — Sentry-ingest AND Inngest in the allowlist.** Blocking Sentry darks monitors; blocking
  Inngest darks the fail-loud throw itself (the silent-green failure inverts twice). Both MUST be in the
  allowlist; assert in PR-2.
- **R3 (MED) — restore re-triage may shrink PR-1.** If few of the 11 are cleanly allowlistable (incl.
  bug-fixer = CPO #1), PR-1's restore scope shrinks and more crons wait for PR-2. AC1 surfaces this with
  evidence rather than discovering it mid-build.
- **R4 (MED) — live 4-cron exposure during restore-first.** Bounded (first-party prompts/scripts);
  interim stopgap decided IN PR-1 (Phase 1.2); expedite PR-2 immediately after PR-1.

## Plan-Review Resolution

DHH + Kieran + code-simplicity, single-user-incident threshold. Applied: **(operator)** defer
content-publisher→GHA to firewall-only (`## Deferred`); allowlist-first egress (no SNI proxy up front);
**(Kieran)** own the restore re-triage + evidence-before-restore (AC1), soften "no firewall dependency",
add Inngest + github.com/api.github.com split + Better Stack to the allowlist (Hypothesis 2 / R2),
decide interim stopgap in PR-1 (Phase 1.2); **(DHH)** fold token narrowing into PR-1 (Phase 1.3);
**(code-simplicity)** wave-gating reframed as operational un-pause pacing, not separate-PR ceremony.
Kept (all reviewers): restore-first sequencing + DOCKER-USER-not-host scoping (the load-bearing insight).

## Sharp Edges

- A `## User-Brand Impact` section that is empty/`TBD`/threshold-less fails `deepen-plan` Phase 4.6.
  This plan's is filled (single-user incident). Run deepen-plan before `/work`.
- nftables applied via cloud-init alone is **dead** on the running host (`ignore_changes=[user_data]`).
  PR-2 MUST use the SSH `terraform_data` provisioner — verified vs `server.tf:226`/`:573`.
- Token narrowing at `generateInstallationToken` (not the cron `mintInstallationToken`) would change ~10
  call sites incl. interactive routes (`POST /api/kb/upload`, `kb/sync`, agent `pushBranch`) — keep the
  change at the cron-only mint path.
- Restore-via-allowlist re-triages the Tier-1 defer classification by definition (`_cron-shared.ts:183`).
  PR-1 must produce per-cron bash-surface evidence; do not assume the "likely allowlistable" candidates.
