---
date: 2026-07-09
topic: T3MP3ST security-tooling evaluation
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm: T3MP3ST for Soleur security hardening

## Origin

Operator asked: *"Shall we consider [T3MP3ST](https://github.com/elder-plinius/T3MP3ST)
for hardening Soleur Security and also in the future for Soleur Users?"*

**T3MP3ST** is an autonomous **offensive** red-team meta-harness (AGPL-3.0) by
elder-plinius. It orchestrates AI coding agents (Claude Code, Codex, Hermes, local
models) through a full recon→exploitation kill chain against web apps, source, cloud
infra, smart contracts, CTFs, and IoT. ~35 tools default / ~83 full arsenal; keyless
(drives a locally-running agent); claims 90.1% XBEN, 8/10 CVE accuracy.

Two use cases were on the table: (1) hardening Soleur's **own** security; (2) a future
capability **for Soleur Users**. This brainstorm scoped internal use; the AGPL-copyleft
+ user-facing-liability threshold was assessed in parallel by the CLO.

## What We're Building

**NOT** adopting T3MP3ST. Two decisions:

1. **Internal (Approach B — GO-NARROW):** Build a small, deterministic **runtime
   authz / RLS-fuzz harness** that drives one tenant's JWT against another tenant's
   rows (IDOR / cross-tenant / role-confusion) against a **local disposable Postgres
   with production RLS policies loaded**. It *borrows T3MP3ST's kill-chain taxonomy
   and technique library as concepts* — no AGPL code is copied. It doubles as runtime
   proof of the tenant-isolation work already in flight (verify/068 jti-deny per-table).

2. **User-facing (reshape & park):** The offensive-capability-for-users idea is
   **dropped**. The legitimate adjacent user need ("is the app I shipped with Soleur
   secure?") is reshaped into a **defensive, read-only posture check on the user's own
   Soleur-managed assets** and filed as a validation-gated Post-MVP issue (needs
   `business-validator` before any build).

## Why This Approach

- **Borrow, don't adopt (unanimous CTO + license precedent).** ~95% of T3MP3ST's
  83-tool arsenal targets surfaces Soleur does not own (smart contracts, IoT, rented
  cloud). Standing up an autonomous exploitation agent buys blast-radius, supply-chain,
  and cost for a thin slice of value. Soleur already has a standing policy —
  MIT/BSD/Apache-2.0 only, **"no GPL/AGPL contagion"** (`feat-behavior-harness-uplift/spec.md`);
  a July 2026 brainstorm already rejected AGPL tools (Relaticle/Twenty/Corteza). Copying
  AGPL source would violate that policy and (per CLO) risk viral copyleft on the plugin.

- **The gap is real and narrow (CTO + repo-research).** Soleur's entire security stack
  is static/diff-time (`security-sentinel` LLM OWASP/CWE, `semgrep-sast` deterministic
  SAST, `infra-security` config-audit, `gdpr-gate`). Nothing drives a hostile
  authenticated client at runtime. The one runtime harness that exists (ADR-064
  live-verify) is a benign post-merge check. Runtime RLS/authz-bypass is the single
  highest-value class the static stack structurally cannot prove.

- **Local-only is the only safe *and* only available target (CLO + CTO + repo-research).**
  Pointing an exploitation harness at "our own" dev/staging app also tests the **rented
  infra underneath** (Hetzner abuse desk, Supabase/Cloudflare/Vercel AUPs forbid
  automated attack tooling even against your own account; CF scans hit the edge, not the
  origin → useless data + suspension risk). And there is **no dev/staging environment** —
  all non-prod is operator-local; the dark host runs prod secrets. So a local disposable
  Postgres with prod RLS policies loaded is both the safest and the only viable target.

- **User-facing offensive is a hard no (CLO + CPO).** CLO: potential **criminal**
  exposure (UK CMA §3A tool-supply, EU Directive 2013/40, CFAA origination on a hosted
  service) *and* it contradicts Soleur's own Acceptable Use Policy §7(e)
  (`docs/legal/acceptable-use-policy.md:75`), which forbids users from unauthorized
  scanning. CPO: severe foot-gun for non-technical founders ("the platform that got a
  founder a CFAA letter" = brand-survival severity). The defensive reshape serves the
  real need without the foot-gun.

## Key Decisions

| # | Decision | Rationale | Source |
|---|----------|-----------|--------|
| 1 | Do **not** adopt T3MP3ST as tooling | Over-tooling (~95% inapplicable) + blast radius + AGPL + supply-chain | CTO |
| 2 | **Borrow** kill-chain taxonomy/techniques as concepts, never copy AGPL source | Preserves "no GPL/AGPL contagion" policy; avoids viral copyleft | CTO, CLO, repo-research |
| 3 | Build a **scoped, deterministic RLS/authz-fuzz harness** (tenant-B JWT → tenant-A rows) | Fills the one real gap; reproducible; validates verify/068 isolation work | CTO |
| 4 | Target = **local disposable Postgres + prod RLS policies**, egress default-deny, zero real creds, synthetic secrets, token/wall-clock cap | Only safe + only available target; no provider-ToS exposure; no blast radius | CLO, CTO, repo-research |
| 5 | Harness must **pin scope by identity (workspace_id = tenant), not session state** | Cross-tenant-leak vectors hide behind session-inferred scope | learnings `2026-05-29-identity-pinned-workspace...` |
| 6 | **Drop** user-facing offensive capability | Criminal exposure + AUP §7(e) self-conflict + foot-gun | CLO, CPO |
| 7 | **Reshape** to defensive "posture check on your own Soleur-managed assets"; **park** behind `business-validator` (Post-MVP) | Serves the real user need safely; premature to build pre-beta | CPO |
| 8 | If GO-NARROW proceeds to a build, capture an ADR for the harness + sandbox topology | New security surface + infra pattern = architecture decision | CTO (ADR detection) |

## Open Questions

1. **Timing of the harness build.** CPO flags 0 beta users → the current-stage security
   ROI is finishing the in-flight defensive isolation work (#673 container isolation,
   #2719 skill security scan). The harness (Decision 3) is not offensive tooling — it is
   a *test* of that same isolation work — so it reconciles, but the operator chose to
   build it; sequence it alongside the active verify/068 work rather than as separate
   speculative tooling.
2. **Sandbox-provisioning prerequisite.** No ephemeral-throwaway + egress-allowlist +
   credential-free-env harness exists (CTO capability gap 2). Decide whether the harness
   runs in CI (deterministic, per-PR-cheap slice) or as an operator-run pre-launch check.
3. **How much taxonomy to harvest.** Full kill-chain taxonomy vs. only the
   authz/IDOR/RLS technique subset relevant to a Next.js + Supabase app.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** GO-NARROW. Real but narrow gap — the static stack cannot prove runtime
exploitability; runtime RLS/authz bypass is the highest-value missing class. Borrow the
technique library into a small deterministic harness on a local disposable stack; do NOT
stand up the full autonomous harness. Top risks: provider-ToS prod-suspension, autonomous
blast radius, supply-chain + AGPL. Two capability gaps: runtime-authz harness; disposable-
sandbox provisioning pattern.

### Product (CPO)

**Summary:** Internal — park as conceived; the honest altitude is "continuous security
assurance," and current-stage ROI is finishing in-flight defensive isolation work at 0
beta users. User-facing offensive — actively discourage (severe foot-gun for non-technical
founders); reshape into a defensive posture-check on the user's own Soleur-managed assets,
gated behind `business-validator`. "Adopt T3MP3ST" is the wrong frame; decide on the
capability, let CTO choose the instrument.

### Legal (CLO)

**Summary:** Internal — GO-WITH-GUARDRAILS: AGPL is clean for genuine internal-only use
(no §13 trigger); remaining risks are provider-pentest-policy checks (own systems only,
isolated rig, contained egress, preserve notices). User-facing — STOP, consult cyber/
criminal counsel (US+UK+EU) before any build: AGPL §13 source-disclosure + contamination,
CFAA/CMA §3A/EU-Directive criminal exposure, Anthropic Usage-Policy collision, supplier
duty-of-care — and it contradicts Soleur's own AUP §7(e)/CFAA clause. Threshold catalog:
`oss-license-classification` (both), `ai-vendor-terms` (user-facing).

## Capability Gaps

Both gaps are the concrete deliverables of the GO-NARROW path, not blockers.

1. **Runtime authz/RLS-fuzz capability** — domain: engineering/review (or a new
   engineering/security-dynamic). Evidence: grep of
   `plugins/soleur/agents/engineering/review/` confirms `security-sentinel` and
   `semgrep-sast` are static and `infra-security` is config-only; ADR-064 live-verify is
   benign/post-merge. No agent drives a hostile authenticated client at runtime. This is
   the borrow-target for T3MP3ST's technique library.

2. **Disposable-sandbox provisioning pattern** — domain: engineering/infra. Evidence: no
   ephemeral-throwaway-VM + egress-allowlist + credential-free-env harness exists in
   `apps/web-platform/server/` (readiness/canary patterns are isolation + liveness, not
   attack sandboxes). Prerequisite for any live run.

## User-Brand Impact

- **Artifact:** the runtime RLS/authz-fuzz harness (and the deferred user-facing
  defensive posture-check surface).
- **Vector:** a harness that mis-reports tenant isolation as sound when a cross-tenant
  read/write path is actually open would let a real cross-tenant data breach ship
  undetected — a single-user data-exposure incident. (For the deferred user surface: a
  posture check that runs against anything beyond the user's own Soleur-managed assets, or
  that a non-technical user mis-points, is a trust/legal breach.)
- **Threshold:** single-user incident.

## Non-Goals

- Adopting, vendoring, or running T3MP3ST itself.
- Copying any AGPL-licensed source into Soleur.
- Pointing any scan/exploit traffic at Hetzner / Supabase / Cloudflare / Vercel / GHCR /
  Doppler (rented/shared infra) — even our own accounts.
- Any offensive/red-team capability exposed to Soleur Users (hard-dropped; counsel-gated).
- Building the user-facing defensive posture-check now (parked behind `business-validator`).
