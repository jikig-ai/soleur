# Brainstorm: skill-security-scan (issue #2719)

**Date:** 2026-05-10
**Participants:** Founder, CPO, CTO, CLO, CMO, Explore (implicit via parent brainstorm)
**Status:** Complete; ready for `/soleur:plan`.
**Parent:** [2026-04-21 claude-skills-audit brainstorm](./2026-04-21-claude-skills-audit-brainstorm.md), spec [feat-claude-skills-audit](../specs/feat-claude-skills-audit/spec.md), umbrella issue #2718.

## What We're Building

A dedicated `skill-security-scan` skill that runs an advisory static-analysis gate at two write-side checkpoints — `skill-creator` post-scaffolding and `agent-finder` post-fetch / pre-write — emitting a tri-state verdict (`LOW-RISK | REVIEW | HIGH-RISK`) across **five** detection categories:

1. Shell/Python code-execution anti-patterns (dynamic `eval`, `exec`, raw shell invocations, obfuscation).
2. Prompt-injection attempts in SKILL.md frontmatter (system-prompt overrides, role hijacking, safety-bypass text).
3. Supply-chain risk (unpinned deps, typosquats, known CVEs via osv.dev primary, GitHub Advisory fallback).
4. Filesystem boundary violations (path traversal, symlinks outside designated dirs).
5. **Third-Party Telemetry Surface** (utm-tagged links, vendor-controlled redirect URLs, "powered by" footers in third-party SKILL.md) — surfaces *de facto* sub-processor risk, not malice. Two-tier severity: `HIGH-RISK` on outbound-beacon patterns, `WARN` on branding-only. **First-party allowlist mandatory** (`social-distribute` and `brainstorm` SKILL.md self-trip on `utm_` today).

`HIGH-RISK` blocks install by default. Override = `Skill-Security-Ack: <skill-name> <reason>` git commit trailer + structured artifact at `knowledge-base/security/skill-overrides/<date>-<skill-slug>.md` (GDPR Art. 32 evidence record).

Existing installed skills run scan-on-demand (no breaking change, no retroactive blocks).

## Why This Approach

**User-brand-critical tag set in Phase 0.1.** Operator selected three brand-survival outcomes simultaneously: credential leak (Doppler / GitHub PATs / BYOK) | cross-tenant data exposure | trust-breach via false-negative. EU jurisdiction in play. Brand-survival threshold: `single-user incident`.

**Convergence of four leaders (CPO, CTO, CLO, CMO) on the engineering shape:** semgrep + targeted regex (no LLM at install-time, deterministic for CI), osv.dev primary supply-chain source (Snyk free tier rejected — commercial-CI ToS no-go per CLO), dedicated skill mirroring the `gdpr-gate` advisory-gate pattern, commit-trailer override capture.

**Critical re-framing from CTO grep finding:** `agent-finder.md:108-115` is `curl > local-file` — there is **no `npm install`, no `git clone`, no postinstall hook surface today**. Blast radius is "untrusted markdown lands in repo," not arbitrary code-exec on install. This dissolves the pre-clone vs. post-clone debate: scan post-fetch into a temp buffer; write to disk only on `LOW-RISK | REVIEW-with-ack`.

**Critical liability framing from CLO:** emitting `PASS` is a representation a regulator/plaintiff can lean on. False-negative shipping `PASS` ships a warranty. Verdict names changed to `LOW-RISK | REVIEW | HIGH-RISK` to blunt the warranty implication, paired with mandatory advisory-output disclaimer.

**Critical roadmap re-tier:** parent issue at `priority/p3-low` / Post-MVP/Later was a roadmap defect. Promoted to `Phase 4: Validate + Scale`, P1, as item 4.11. Brand-survival precondition for any third-party skill-install surface ever reaching external users (4.3 guided onboarding).

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Verdict names: `LOW-RISK \| REVIEW \| HIGH-RISK` (not `PASS \| WARN \| FAIL`), with mandatory advisory-output disclaimer footer | CLO: `PASS` is a representation that can be construed as a warranty; false-negative ships a duty-of-care our static analysis cannot back. Tri-state names without "PASS" + disclaimer ("Advisory static analysis only. LOW-RISK does not constitute a security audit, certification, or warranty of safety.") blunt the liability shift. |
| 2 | Five detection categories shipped in #2719 (4 security + Third-Party Telemetry Surface) | Operator chose unified ship over splitting. Brand-survival framing makes vendor-attribution detection a category-defining moat ("agent-native sub-processor surfacing" per CMO), not a follow-up nice-to-have. |
| 3 | Third-Party Telemetry Surface label (NOT "Marketing Surface") | CMO + CLO: the actual harm is GDPR Art. 28 sub-processor leakage of operator prompt context to undeclared third parties; "Marketing Surface" reads as aesthetic complaint and conflates marketing with malice. Maps cleanly to existing `gdpr-gate` vocabulary. |
| 4 | Two-tier severity for category 5: `HIGH-RISK` on outbound-beacon patterns (postinstall hooks calling external endpoints, redirect-tracking URLs in install-time content), `WARN` on branding-only (logos, "powered by" footers without telemetry) | CLO: outbound-beacon = active sub-processor + Art. 13 transparency failure; branding-only = disclosure gap, not exploit. CPO's INFO-only call rejected to preserve the brand-survival floor on the beacon class. |
| 5 | First-party allowlist for Soleur-owned domains (`soleur.ai`, `soleur.dev`, `github.com/jikig-ai`, our own utm campaigns in `social-distribute`) — non-negotiable | CMO sanity-grep (`git grep -l "utm_" plugins/soleur/skills/` ) confirms `social-distribute` and `brainstorm` SKILL.md self-trip on `utm_`. Without allowlist, the gate fails on every Soleur skill on day one — credibility-killer. |
| 6 | Supply-chain data source: osv.dev primary (cached daily), GitHub Advisory fallback. Snyk free tier rejected. | osv.dev: free, no auth, batched, OSS-aggregating, EU-friendly (CLO clears it). GitHub Advisory: complementary recall, no new sub-processor (we already process GitHub data). Snyk free tier: commercial-CI ToS no-go per CLO; rate-limited and authn-blocked per CTO. Cache invalidates daily via lefthook to keep CI deterministic. |
| 7 | Detection layer: semgrep (reusing `plugins/soleur/skills/review/scripts/ensure-semgrep.sh` + a new `semgrep-skill-rules.yaml` rule pack) + targeted regex for SKILL.md frontmatter prompt-injection. **No LLM second-pass at install-time.** | Determinism is mandatory at install-time gates. LLM second-pass adds 3-8s latency + nondeterminism — both fatal. Regex/semgrep are reviewable by founders, deterministic in CI, and reuse our existing `semgrep-sast` review-agent infrastructure. LLM second-pass reserved for opt-in `/scan-on-demand` deep-mode (future). |
| 8 | Scanner location: dedicated `plugins/soleur/skills/skill-security-scan/` skill with SKILL.md, `scripts/run-scan.sh`, `references/semgrep-skill-rules.yaml`, `references/regex-patterns.md`. Both `skill-creator` and `agent-finder` invoke via `Skill` tool. | Discoverability via `/soleur:help` and `find-skills`; single source of truth (script-under-skill-creator forks into divergent copies). Mirrors `gdpr-gate` advisory-gate pattern verbatim. Token-budget impact contained to a single ~30-word skill description. |
| 9 | Override mechanism: `Skill-Security-Ack: <skill-slug> <reason>` git commit trailer + mandatory structured artifact at `knowledge-base/security/skill-overrides/YYYY-MM-DD-<skill-slug>.md` (frontmatter: skill, source, findings JSON, justification, approver, scanner version, timestamp) | Trailer is `git interpret-trailers`-parseable, survives squash-merge, grep-able in `git log`. PR body lines drift across edits and are invisible post-merge — insufficient for GDPR Art. 32 evidence per CLO. The artifact under `knowledge-base/security/skill-overrides/` is the durable audit record; trailer is the trigger. |
| 10 | `agent-finder` blast-radius: scan post-fetch into temp buffer, write to `.claude/agents/` or `.claude/skills/` ONLY on `LOW-RISK \| REVIEW-with-ack`. No retroactive blocks on already-installed skills (TR7 preserved). | CTO grep confirms agent-finder is `curl > local-file` today; no `npm install`/`git clone`/postinstall surface. Pre-fetch scan is impossible (no content yet); post-write scan leaves the artifact on disk on FAIL. Temp-buffer is the only correct shape. |
| 11 | Self-defense: pin pattern-file SHAs; treat osv.dev responses as untrusted input; ship a self-test fixture that fails loud if the scanner fails open | CPO: the scanner itself is a supply-chain attack surface. Poisoned rule pack or malicious advisory response could turn scanner into the exploit vector. Belt-and-suspenders required at user-brand-critical tier. |
| 12 | `/plan`-aware skip-and-warn mode: when scanner runs mid-`/plan` workflow, `HIGH-RISK` does NOT block; emits a TODO that gates `/work` exit. Otherwise blocks at install-time directly. | CTO: hard block mid-plan derails feature-dev and trains override-fatigue. Plan-aware deferral keeps the gate honest at the install-time checkpoint without weaponizing it against in-flight feature work. |
| 13 | Stale-state class: scanner emits `.scan-meta.json` next to scanned SKILL.md recording rule-pack version + verdict + timestamp; rule-pack updates do NOT retroactively re-classify | CTO: semgrep rule updates without versioned scan results spam new failures on previously-PASSed skills. Version-pinned scan-result is the only path that prevents alert-fatigue from rule churn. |
| 14 | Roadmap promotion: #2719 moves from Post-MVP/p3-low to Phase 4 (Validate + Scale) item 4.11, P1, gated before 4.3 (guided onboarding) exposes any third-party skill-install surface | CPO + CMO: the original p3-low classification was a roadmap defect given the user-brand-critical tag. Single-user-incident threshold + EU jurisdiction makes this a brand-survival precondition for external user exposure to skill-install UX. |
| 15 | GDPR-gate fires at plan time per `hr-gdpr-gate-on-regulated-data-surfaces` | CLO: SKILL.md is user-authored content potentially containing PII (author emails, internal hostnames, customer-name examples). Scanner reads, parses, emits findings on it = processing under Art. 4(2). Likely outcome: minor (data-minimization in findings output, no raw SKILL.md content in telemetry/Sentry). |
| 16 | MIT attribution string for inspiration source: `<!-- Portions adapted from alirezarezvani/claude-skills (MIT License, Copyright (c) 2025 Alireza Rezvani). See LICENSES/skill-security-auditor.MIT.txt. -->` in `skill-security-scan/SKILL.md` body. Verbatim MIT text committed under `LICENSES/skill-security-auditor.MIT.txt`. | TR3 from parent spec satisfied per CLO. Attribution in skill body, not in launch copy (per parent CMO call). |

## User-Brand Impact

**Artifact:** `plugins/soleur/skills/skill-security-scan/` (new skill); `plugins/soleur/skills/skill-creator/SKILL.md`, `plugins/soleur/agents/engineering/discovery/agent-finder.md` (integration points); `knowledge-base/security/skill-overrides/` (new override-record directory).

**Vector:** A solo founder uses `agent-finder` or `skill-creator` to install a third-party community skill that contains (a) shell/Python code-exec anti-pattern, (b) prompt-injection in frontmatter that hijacks a downstream Claude session into reading `.env` / Doppler secrets / cross-tenant KB content, (c) a typosquatted dep with a known CVE, or (d) outbound-beacon URLs that leak operator prompt context to a third-party analytics endpoint. The skill installs cleanly, runs in the next agent invocation, and exfiltrates Doppler / Supabase / BYOK tokens before the founder notices. Brand-ending in EU jurisdiction (Art. 32, Art. 28, Art. 13).

**Threshold:** `single-user incident`. One credential-leak event ends Soleur's brand-trust position in the founder market.

**Worst silent-failure mode:** scanner emits `LOW-RISK` (or, worse, `PASS` under the rejected naming) on a malicious skill. The Soleur-emitted verdict creates a representation the founder relied on; liability shifts from the third-party skill author to Soleur. CLO disclaimer + rename mitigate but do not eliminate this — any false-negative on a known-pattern category is catastrophic.

**Worst loud-failure mode:** scanner emits `HIGH-RISK` on every Soleur first-party skill (self-trip via unallowlisted `utm_` patterns). Founders override-fatigue, learn to bypass, and the gate stops working on the actually-malicious case. Self-allowlist is non-negotiable.

**Mitigations baked into Decisions 1, 4, 5, 11, 12, 14, 15.**

## Open Questions

- **Q1:** Where exactly does the structured override artifact live in repo layout? Top-level `knowledge-base/security/skill-overrides/` (proposed) vs. `knowledge-base/project/security/` vs. inside the relevant feature spec directory? Decide during plan.
- **Q2:** Should `.scan-meta.json` (Decision 13) live next to SKILL.md (intrusive but co-located) or in a side-channel directory like `.claude/scan-meta/`? Plan decision.
- **Q3:** What's the rule-pack daily refresh cadence — lefthook on commit, GH Action cron, or on-demand only? Plan decision.
- **Q4:** For `/plan`-aware skip-and-warn mode (Decision 12), what's the exact CLI affordance — env var, flag passed by `/plan`, or auto-detected via parent-process env? Plan decision.
- **Q5:** ~~Should the missing learning file `2026-05-09-evaluating-vendor-branded-claude-code-skills.md` be created or de-referenced?~~ **Resolved at compound time:** the file exists at `knowledge-base/project/learnings/2026-05-09-evaluating-vendor-branded-claude-code-skills.md` (verified). CLO's mid-brainstorm verification was a false negative (likely path-resolution issue from subagent CWD). The brainstorm SKILL.md Phase 1.0 #7 citation resolves correctly.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Brand-survival-critical given the user-brand-critical tag. Recommends `skill-security-scan` dedicated skill, osv.dev primary, semgrep+regex (no LLM at install-time), commit-trailer override, INFO-tier vendor-attribution (rejected in favor of CLO's two-tier in Decision 4). Critical under-weighting flagged: scanner itself is supply-chain attack surface — pin pattern SHAs, treat osv.dev responses as untrusted (Decision 11). Roadmap re-tier required: Post-MVP/p3-low is a defect.

### Engineering (CTO)

**Summary:** Markdown-only static analyzer; no runtime sandboxing required. Reuse `semgrep-sast` agent + `ensure-semgrep.sh` bootstrap + `gdpr-gate` skill structure. Critical grep finding: `agent-finder` does not `npm install` / `git clone` today — re-frames Q4 entirely. Architectural risks under-weighted: stale-state from rule-pack updates (Decision 13), `/plan`-aware skip-and-warn mode (Decision 12), and rule-pack itself as attack surface (Decision 11). No new capability gaps.

### Legal (CLO)

**Summary:** Defensive control with material brand-survival reduction, but converts an undifferentiated install flow into a verdict-emitting gatekeeper. Liability shift via false-negative is the highest-risk finding; mitigated by verdict-rename + advisory disclaimer (Decision 1). Override paper trail must be a structured artifact, not a PR body line, for GDPR Art. 32 evidence (Decision 9). Vendor-attribution = sub-processor risk under Art. 28 + Art. 13 transparency, two-tier severity warranted (Decision 4). Snyk free tier rejected on commercial-CI ToS grounds (Decision 6). MIT attribution string locked (Decision 16). GDPR-gate must fire at plan Phase 2.7 (Decision 15).

### Marketing (CMO)

**Summary:** "Marketing Surface" framing rejected — conflates marketing with malice. Re-labeled to "Third-Party Telemetry Surface" / sub-processor lens (Decision 3). ON by default mandatory; opt-in defeats category-creation. Self-trip confirmed on `social-distribute` and `brainstorm` SKILL.md → first-party allowlist non-negotiable (Decision 5). Brand position: announce loudly as "agent-native sub-processor surfacing" — defensible category claim, pairs with `gdpr-gate` / `compliance-posture.md` story. Override-justification artifacts re-positioned as exportable consent receipts (SOC2/GDPR evidence packs).

## Capability Gaps

None. `semgrep-sast` agent + `ensure-semgrep.sh` + `gdpr-gate` skill template + `lefthook` hook plumbing + `scripts/retired-rule-ids.txt` discipline + `LICENSES/` precedent cover the full execution surface. Verified via CTO assessment grep: `plugins/soleur/skills/review/scripts/ensure-semgrep.sh`, `plugins/soleur/skills/review/references/semgrep-custom-rules.yaml`, `plugins/soleur/skills/gdpr-gate/SKILL.md` all exist.

## Attribution

External repo: `https://github.com/alirezarezvani/claude-skills` — MIT License, Copyright (c) 2025 Alireza Rezvani. Pattern only; no verbatim file copies. Per CLO, attribution string for `skill-security-scan/SKILL.md` body (not frontmatter, not launch copy):

```markdown
<!-- Portions adapted from alirezarezvani/claude-skills (MIT License, Copyright (c) 2025 Alireza Rezvani). See LICENSES/skill-security-auditor.MIT.txt. -->
```

Verbatim MIT text committed at `LICENSES/skill-security-auditor.MIT.txt` as part of #2719 ship.

## Workflow Gap Surfaced (resolved at compound time)

CLO's mid-brainstorm assessment claimed `knowledge-base/project/learnings/2026-05-09-evaluating-vendor-branded-claude-code-skills.md` did not exist on disk. Compound-time verification found the file exists. CLO's check was a false negative (likely worktree path-resolution from subagent CWD). The brainstorm SKILL.md Phase 1.0 #7 citation resolves correctly; no action required on #2719. Real session error captured at compound time: orchestrator should independently verify subagent existence-check claims rather than treating them as authoritative.
