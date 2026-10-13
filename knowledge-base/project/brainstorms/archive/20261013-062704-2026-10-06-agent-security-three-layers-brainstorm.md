---
title: Agent security — three layers (AlphaSignal article review)
date: 2026-10-06
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-agent-security-three-layers
---

# Agent security — three layers: article review and Soleur improvements

## What We're Building

An umbrella epic that turns the AlphaSignal article "The three layers of AI agent security" into sequenced, Soleur-specific hardening work. It is mostly **not** greenfield: Soleur already ships most of layers 1 and 3 for the web runtime. The epic closes the gaps the article exposes and fixes sequencing against the roadmap's own "security/HITL first" principle.

## Article Review (claims vs. evidence, 2026-10-06)

Sources are primary where marked; incidents are secondary press.

| Claim | Verdict | Note |
|---|---|---|
| Meta/OpenClaw mass-deleted 200+ emails | Verified (secondary) | Feb 2026; context compaction dropped the "don't act until I say" instruction |
| Claude Code wiped a prod DB + 2.5 yrs | Verified | `terraform destroy`; AWS restored data in ~1 day (article omits) |
| Opus "staging cleanup" outage | Partial / vague | Likely PocketOS (Cursor + Opus 4.6, Apr 2026): deleted a volume holding prod DB + backups; match is inferred |
| NemoClaw/OpenShell: Landlock, seccomp, netns, placeholder creds, operator approval | Verified (primary docs) | Omits alpha status and Aug 2026 CVE-2026-65093 sandbox escape (secondary source) |
| NanoClaw: >1M → few thousand LOC, Echo "continuous" CVE strip | Partial | OpenClaw ≈ 400k LOC per press; Echo rebuilds on a CVE cadence with human review |
| CrabTrap: LLM judge on POST/high-risk, human-in-the-loop | **Wrong** | README: "does not provide human-in-the-loop approval"; judge runs only when no static rule matches (verified against raw README) |
| Thesis: prompts are not a boundary; defense in depth | Sound | Anthropic `sandbox-runtime`, Cloudflare Outbound Workers follow the same pattern; article omits both |

## Existing-Primitive Audit (article concept → Soleur)

| Concept | Soleur primitive (read) | Enforcement | Gap |
|---|---|---|---|
| FS confinement | `server/agent-runner-sandbox-config.ts` (bwrap, `denyRead` siblings, ADR-075) | Hard, fail-closed | No Landlock ruleset (only `landlock_*` in seccomp allowlist); sibling deny-list not allowlist |
| seccomp / AppArmor | `infra/seccomp-bwrap.json`, `apparmor-soleur-bwrap.profile`, canary (ADR-079/122) | Hard, CI-verified | None material |
| Netns / per-session egress | `--unshare-net`, `allowedDomains: []` default, widened only with GitHub token (ADR-051) | Hard | No per-session audit log, no approve-new-host path |
| Container egress | `infra/cron-egress-*` nftables (ADR-052) | Hard, shared allowlist | One allowlist for all tenants |
| No creds in agent env | `server/agent-env.ts` env allowlist | **Partial** | BYOK `ANTHROPIC_API_KEY`/OAuth token, `GH_TOKEN`, service tokens ARE injected into the CLI subprocess; regex deny on `env`/`printenv` is the only barrier. `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` unused (semantics unverified) |
| Ephemeral per-session runtime | None (ADR-075: one shared container) | None | Large; ADR territory |
| CVE-minimized runtime | `node:22-slim@sha` pin; PR `dependency-review` only | Advisory | No image scan (Trivy/Grype) in CI |
| Egress approval / escalation | Scope Grants tiers, `permission-callback.ts`, `BLOCKED_BASH_PATTERNS` | Hard for MCP writes; regex for bash | Nothing for outbound network writes |
| Destructive guards — customer plugin | `plugins/soleur/hooks/hooks.json`: 2 PreToolUse hooks only | Soft | `guardrails.sh` / `prod-write-defer-gate.sh` are repo-local, not shipped |

## Why This Approach

Umbrella epic, quick wins first: slice 1 needs no new infrastructure and closes the two most user-visible exposures; slice 2 does the architectural fix (credential broker) and fixes sequencing; slice 3 is ADR/messaging work gated on measured controls. Rejected: broker-first (10–15 days with quick wins waiting) and triage-only (leaves env-credential exposure open).

## Key Decisions

1. **Scope = all four areas** (operator-selected): credentials out of env, plugin destructive-action guard, resequence egress, runtime hardening + messaging.
2. **Package = umbrella epic, quick wins first.**
3. **Do not build a CrabTrap-style LLM-judge proxy now.** The article's proxy has no HITL; Soleur's tier model already supplies human approval. Revisit after the credential broker and audit log exist.
4. **Claims follow controls** (CLO): no public "isolated per session / all egress inspected" copy until measured; update Art. 30 TOMs, DPD and Privacy Policy security sections in the same PR as any shipped control.
5. **Judge vendor is the legal pivot**: self-hosted EU or Anthropic (existing DPA) avoids a new sub-processor; any other vendor needs DPA + transfer review first.
6. **Productize Candidate:** none (not a recurring work pattern).

## User-Brand Impact

- **Artifact:** the hosted agent runtime's credential and egress boundary, and the customer-side Soleur plugin's destructive-action guards.
- **Vector:** a prompt-injected or hallucinating agent exfiltrates one customer's BYOK key or tokens, or runs a destructive command on a customer's own machine/prod, with no boundary independent of the model's instructions.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Layers 1 and 3 are enforced for the web runtime; credentials in subprocess env and a near-empty customer plugin guard set are the real gaps. Top 3 increments: env scrub + least-injection, plugin PreToolUse guard, per-session egress audit log + approve-new-host. Per-tenant containers and Landlock are ADR-sized.

### Product (CPO)

**Summary:** About 80% of the work is already filed; the article is a prioritization signal. Infra layers stay quiet table stakes; the founder-visible control layer (approvals, activity/audit) is the trust story. Recommends resequencing (#4671, #4672, #9545 with #9534) then honest messaging; page overlap with #2004 to be checked before any new unified surface.

### Legal (CLO)

**Summary:** Stronger egress control strengthens the Art. 32 posture but public docs carry no agent-isolation claim and the Art. 30 TOM section lists none. A payload-inspecting proxy/judge is a new processing step (DPD §2.3, Art. 30, GDPR Policy balancing); judge-vendor choice drives sub-processor and transfer analysis. CrabTrap MIT, NemoClaw/OpenShell Apache-2.0 per web fetch (LICENSE texts unverified).

## Capability Gaps

- **Credential isolation from agent env** — evidence: `apps/web-platform/server/agent-env.ts` injects `ANTHROPIC_API_KEY`/`CLAUDE_CODE_OAUTH_TOKEN`, `GH_TOKEN`, `GIT_INSTALLATION_TOKEN`, service tokens; `git grep ANTHROPIC_BASE_URL -- apps/web-platform` and `git grep SUBPROCESS_ENV_SCRUB` return nothing.
- **Plugin destructive-action guard** — evidence: `plugins/soleur/hooks/hooks.json` PreToolUse = `browser-snapshot-credential-guard.sh`, `operator-stage-approval.sh` only.
- **Image CVE scan** — evidence: word-bounded grep for trivy/grype/snyk/anchore in `.github` and `apps/web-platform/Dockerfile` finds only `dependency-review`.

## Open Questions

- What does `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` actually scrub (SDK 0.3.284)? Verify empirically before relying on it.
- Should draft PR #9529 (open-web egress) merge be held until #4671/#4672/#9545 land? Operator decision.
- Credential broker design (placeholder-and-swap vs SDK base-URL gateway) — plan-time, with #9543.
- Judge vendor if an LLM judge is ever added (CLO pivot).
- Per-session ephemeral containers and Landlock — ADRs, `(out of scope)` for slice 1.
- Unwrapped Playwright-MCP registrations bypass the credential guard (#8286, deferred) `(out of scope)`.
- Security/control page copy and timing — gated on measured controls; check overlap with #2004.

## Session Errors

- The repo-research agent asserted BYOK keys are "not stored in the agent process"; `agent-env.ts` refutes it. The learnings agent asserted no approval-gate learnings exist; `prod-write-defer-gate.sh` and `hr-menu-option-ack-not-prod-write-auth` refute it. Both corrected here.
- The CTO report tripped the harness injection-pattern flag (it cites `.claude/settings.json` as a path); content was treated as data.

> **Correction (2026-10-06, measured):** this brainstorm said the OAuth token reaches sandboxed Bash. Measured on SDK 0.3.284 it does not (the CLI withholds it); the live exposure was `ANTHROPIC_API_KEY`. See ADR-272 and `knowledge-base/project/specs/feat-agent-security-three-layers/phase-0-measurements.md`.
