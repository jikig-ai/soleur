---
date: 2026-06-09
topic: tier2-cron-egress-firewall
issue: 5046
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Tier-2: Cron Egress Firewall + Least-Privilege Token + Restore Paused Crons

Brainstorm for #5046 — the durable containment boundary that follows Tier-1 PR #5018
(MERGED 2026-06-08). Tier-1 shipped a hook-primary deny-by-default `PreToolUse` hook +
`sandbox.enabled:false` and **paused** the broad-bash claude crons to avoid a fail-closed
alert storm. This brainstorm answers WHAT the durable boundary is and in what order it ships.

## What We're Building

A two-population containment story for the Inngest cron fleet:

1. **Restore the 11 paused claude-spawning crons** (`TIER2_DEFERRED_CRONS`) — contained by the
   existing #5018 `PreToolUse` hook (`cron-bash-allowlist-hook.mjs`) + per-cron
   `CRON_BASH_ALLOWLISTS`. No host firewall dependency for the allowlistable ones. Restored in
   **output-quality-gated waves**, not big-bang (CPO).
2. **Contain the 4 currently-LIVE `spawn("bash")` crons** (`content-publisher`,
   `content-vendor-drift`, `rule-prune`, `weekly-analytics`) — these bypass the hook entirely
   (ADR-033 invariant I7), so a **network boundary is their ONLY possible containment**. Via a
   **hybrid**: a host egress firewall (SNI-allowlist proxy + nftables kernel default-drop) as
   defense-in-depth for the whole box, PLUS moving the highest-credential cron
   (`content-publisher`, 12 social-API secrets + live `*_ALLOW_POST`) to an **ephemeral GitHub
   Actions runner** (ADR-033 Option C — "creds too dangerous to park on the long-lived host").
3. **Narrow the GitHub-App installation token** to least privilege at the cron-only mint path.

### Reframe surfaced during research (load-bearing)

The issue title says "restore the paused crons," but the **urgent** exposure is inverted: the 4
`spawn("bash")` crons are **registered in `cron-manifest.ts` with no defer guard and no pause —
running live, uncontained, today**, holding `GH_TOKEN` + 12 social secrets with unrestricted
egress. The 11 "paused" crons are the *safe-because-paused* population. The operator chose
**restore-first** sequencing with this exposure made explicit (see User-Brand Impact).

## Why This Approach

- **Restore-first (operator choice):** the 11 are already hook-contained and low-risk to restore;
  restoring them ends the autonomous-surface blackout fast (CPO: "founder surface is dark now").
  Restoring the 11 does **not** depend on the firewall — they are separable workstreams.
- **Hybrid containment (operator choice):** the firewall gives one durable on-box boundary for
  the other 3 spawn-crons + the restored 11; moving `content-publisher` off-box additionally
  removes the broadest credential surface (12 social secrets) from the long-lived host entirely.
- **SNI-allowlist proxy + nftables, not Hetzner Cloud Firewall:** anthropic/github sit behind
  rotating CDN IPs — IP allowlisting of CDN-fronted endpoints is brittle (promoted to rule
  `hr-ssh-diagnosis-verify-firewall`, learning 2026-03-19). Hostname/SNI allowlisting survives
  rotation; nftables kernel default-drop makes the proxy unbypassable by a `spawn("bash")`
  process that ignores `HTTPS_PROXY`.
- **Token narrow at `mintInstallationToken` (`_cron-shared.ts:119`), not `generateInstallationToken`:**
  the latter has ~10 call sites (cross-consumer signature change); the cron-only mint path scopes
  the blast radius. YAGNI: one repo-scoped `contents:write`+`issues:write` token, not per-cron.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Containment substrate (4 spawn-crons) | **Hybrid** — host firewall + content-publisher→GHA | Operator choice; defense-in-depth + off-box highest-credential cron |
| Sequencing | **Restore-first (value-led)** | Operator choice; ends blackout fast, 11 are hook-contained & low-risk |
| Egress mechanism | SNI-allowlist proxy + **nftables default-drop backstop** | CDN-IP brittleness; nftables non-bypassable for spawn-crons |
| Firewall apply path | **SSH `terraform_data` provisioner** (NOT cloud-init) | `hcloud_server.web` has `ignore_changes=[user_data]` (server.tf:57-59) — cloud-init edit lands dead on running host |
| Egress allowlist MUST include | Sentry ingest domain + Discord webhook + social-write hosts | Else heartbeats POST-fail silently (monitors go dark) + content-publisher/weekly-analytics break |
| Silent-over-block surfacing | proxy 403 → Sentry `egress_blocked` tag + Inngest **throws** (heartbeat misses) + per-cron output canary | `hr-no-dashboard-eyeball`, `observability-as-plan-quality-gate` — never fail green |
| Restore order (first wave) | bug-fixer, competitive-analysis, growth-audit | CPO value-density top-3; output-quality gate per cron |
| Token scope | single repo-scoped `contents:write`+`issues:write` (additive `permissions?` opt) | YAGNI cut from per-cron least-priv |
| Dark-launch | firewall/restore gates ship **log-only first**, observed on ≥1 real run, then promoted | learning 2026-06-04 (never validate a gate with the run it gates) |
| Visual design (Phase 3.55) | N/A — no UI surface | pure infra/CI/security |
| Productize Candidate | `cron-containment-classify` check when adding a new cron (spawn-bash? hook-allowlist vs firewall) | recurring as fleet grows; pairs with 2026-06-05 five-registry-lockstep learning |

## User-Brand Impact

**Threshold:** single-user incident (USER_BRAND_CRITICAL=true; operator endorsed ALL three failure modes at Phase 0.1).

- **Artifact at risk:** GitHub-App installation token (`generateInstallationToken`, full default grant today), `GH_TOKEN` + 12 social-API secrets on the live spawn-crons, and agent-in-context data (`ANTHROPIC_API_KEY`, operator prompts, KB content — the spawn env is already a tight allowlist: no Doppler/Sentry/App-private-key).
- **Vectors:** (a) over-broad token / firewall gap → cross-repo write or credential abuse; (b) egress gap on a `spawn("bash")` cron → agent-context / secret exfil to attacker endpoint (the firewall is the ONLY guard — the hook does not cover these crons); (c) deny-by-default over-block → a restored cron silently fails green, founder loses weekly output.
- **Live-exposure tradeoff (conscious):** restore-first sequencing means the 4 already-live uncontained spawn-crons stay uncontained for a few more days until the firewall PR lands. Threat model is bounded — first-party in-repo prompts/scripts, so the realistic vector is compromised-dependency / prompt-injection-via-processed-content (e.g., the upstream repo `content-vendor-drift` clones, or social content), not open RCE. Recorded as accepted risk; the firewall PR should be expedited immediately after the restore PR.
- **GDPR conditional (CLO):** KB/operator-prompt content can contain personal data (names, `jean.deruelle@jikigai.com`, community handles). If exfiltrated context contains personal data, an Art. 33 72h notification obligation attaches; the firewall is a legitimate Art. 32 "security of processing" technical measure. A secret leaked into a public repo via `gh issue create --body $secret` (github.com is allowlisted) is a reportable-class event — which is why the #5018 hook stays **independently load-bearing** even after the firewall.

## Open Questions

1. **Which of the 11 are hook-allowlistable vs genuinely-need-arbitrary-bash?** `CRON_BASH_ALLOWLISTS` has only `cron-roadmap-review` today. Restoring each requires triaging its bash surface into a finite allowlist or accepting it needs the firewall too. Per-cron classification is a plan-time task.
2. **Egress allowlist exact host set.** Must enumerate: `api.anthropic.com`, `api.github.com`/`github.com`, Sentry ingest domain (cluster-specific, e.g. `o*.ingest.de.sentry.io`), Discord webhook host, X/Twitter + LinkedIn + Bluesky API hosts (content-publisher writes). Confirm DNS-resolution strategy for the proxy.
3. **`content-publisher`→GHA migration shape.** ADR-033 Option C = Inngest dispatches `workflow_dispatch`. Needs a new workflow, secret wiring into GHA environment, and the Inngest function becomes a dispatcher. Sizing TBD at plan time.
4. **Interim stopgap for the live 4 during the restore-first gap?** Cheapest option (e.g. temporarily flipping `*_ALLOW_POST` to dry-run, or a coarse nftables drop) — decide at plan time whether the gap warrants it.
5. **nftables on a host with `ignore_changes=[user_data]`** — confirm the SSH-provisioner pattern (sibling provisioners `journald_persistent`/`docker_seccomp_config` in server.tf) and key it on `{file-hash, server_id}` so a fresh VM re-runs it (`hr-fresh-host-provisioning`).

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO)

### Engineering (CTO)

**Summary:** Pick SNI-allowlist proxy + nftables kernel default-drop (the backstop is non-negotiable for `spawn("bash")` crons that ignore `HTTPS_PROXY`); blocked requests must throw + emit Sentry `egress_blocked`, never fail green; token narrowing is a YAGNI cut to one repo-scoped token at the cron mint path; ship as split increments, validate deny-behavior via `/soleur:trigger-cron` before crons run live. Flagged the host-provenance question (resolved by repo-research: host is in `server.tf`, firewall in `firewall.tf` inbound-only, edits need the SSH-provisioner path).

### Product (CPO)

**Summary:** The entire autonomous surface is dark; restore is blocking the founder. Restore hook-containable crons FIRST in waves of 2-3 gated on output-quality (did the founder act on last output?), not big-bang — restoring 11 producers at once re-floods a solo operator. Top-3 by value density: bug-fixer, competitive-analysis, growth-audit. Defer content-generation/campaign-calendar (low cost-of-delay, the low-signal offenders).

### Legal (CLO)

**Summary:** No legal gate — engineering-owned. No DPA/sub-processor disclosure moves with it (egress is restricted to *existing* declared sub-processors Anthropic + GitHub + read-only public endpoints). But name the conditional GDPR Art. 32/33 exposure in brand-survival (KB/prompt content can contain personal data → 72h clock if exfiltrated), and treat the #5018 hook as a load-bearing security control the firewall does NOT subsume (the allowlisted-but-abusable github.com path).

## Capability Gaps

None blocking. The host + firewall ARE Terraform-managed (`apps/web-platform/infra/server.tf:21-64` `hcloud_server.web`; `firewall.tf:1-94` `hcloud_firewall.web`, inbound-only) — verified by repo-research grep, no manual-step blocker. The only "gap" is additive: no `direction="out"` rule / nftables / iptables-OUTPUT exists anywhere today (verified across all `.tf` + `cloud-init.yml`), so Tier-2 adds the egress layer net-new via the SSH-provisioner apply path.

## Interaction note — SDK sandbox proxy env inheritance (added 2026-06-10, PR #5090 review)

`buildAgentEnv` forwards `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` from the server
`process.env` into the agent sandbox (agent-env.ts:43-48), and the SDK sandbox
uses `--unshare-net` + an in-process HTTP bridge. If Tier-2 ever sets
host-level proxy vars, in-sandbox clients inherit values unreachable inside
the unshared netns (or a `NO_PROXY=*.github.com` makes gh skip the sandbox
bridge and dead-end). Currently inert (no host proxy live). Design the
interaction explicitly before introducing a host-level egress proxy — see
ADR-051 for the token-derived sandbox allowlist this must compose with.
