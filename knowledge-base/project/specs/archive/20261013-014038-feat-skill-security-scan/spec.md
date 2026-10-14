# Feature: skill-security-scan (issue #2719)

**Brand-survival threshold:** `single-user incident` (per brainstorm Phase 0.1, user-brand-critical tag set).
**Parent:** brainstorm [2026-05-10-skill-security-scan-brainstorm.md](../../brainstorms/2026-05-10-skill-security-scan-brainstorm.md), umbrella issue #2718.
**Roadmap:** Phase 4 item 4.11 (P1, gated before 4.3 guided onboarding).

## Problem Statement

`agent-finder` and `skill-creator` write skills to disk with zero security vetting today. `agent-finder.md:108-115` does `curl > local-file`, and `skill-creator` post-scaffolding produces SKILL.md content that may contain (a) shell/Python code-execution anti-patterns, (b) prompt-injection in frontmatter, (c) supply-chain risk in declared deps, (d) filesystem-boundary violations, or (e) third-party telemetry surface (utm-tagged links, vendor-controlled redirects, "powered by" footers) that turns operator prompt context into an undeclared sub-processor flow under GDPR Art. 28.

A solo founder using either surface is one bad community-skill install away from credential exfiltration (Doppler / GitHub PAT / BYOK API keys), cross-tenant KB exposure, or trust-breach via an undisclosed third-party processor. The brand-survival threshold is `single-user incident`: one credential-leak event ends Soleur's brand-trust position in the founder market.

No current Soleur skill performs pre-install static analysis on SKILL.md content. Closest analog (`semgrep-sast` review agent) runs at PR-review time, not at skill-install time, and has no rule pack tuned for SKILL.md content.

## Goals

- Ship an advisory static-analysis gate at `skill-creator` (post-scaffolding) and `agent-finder` (post-fetch / pre-write) that emits `LOW-RISK | REVIEW | HIGH-RISK` across five detection categories.
- Block install on `HIGH-RISK` by default; require `Skill-Security-Ack:` git commit trailer + structured override artifact (GDPR Art. 32 evidence record) for any override.
- Reuse existing `semgrep-sast` infrastructure + `gdpr-gate` skill pattern; no new architectural surface beyond the dedicated `skill-security-scan` skill itself.
- Promote brand-survival narrative ("agent-native sub-processor surfacing") via the Third-Party Telemetry Surface category as a category-creation moat.
- Self-defense: scanner itself cannot become a supply-chain attack vector (pinned pattern SHAs, untrusted-input handling for osv.dev responses, fail-loud self-test).

## Non-Goals

- Runtime sandboxing of installed skills. The gate is static analysis only.
- LLM-based detection at install-time. (Reserved for opt-in `/scan-on-demand` deep-mode in a future issue.)
- Retroactive blocking of already-installed skills on rule-pack updates (`.scan-meta.json` versioning prevents this).
- A general-purpose security scanner (this is SKILL.md-targeted; non-skill code paths remain `semgrep-sast`'s domain).
- Replacement of the `semgrep-sast` review-time agent. The two coexist: `semgrep-sast` at PR-review time on the broader codebase, `skill-security-scan` at skill-install time on SKILL.md content.

## Functional Requirements

### FR1: Five detection categories with tri-state verdict

The scanner detects:

1. **Code-execution anti-patterns** — dynamic `eval`, `exec`, raw shell invocations (`bash -c`, `sh -c`, `subprocess.shell=True`), known obfuscation patterns (base64-decode-and-exec, hex-encoded payloads).
2. **Prompt-injection in SKILL.md frontmatter and body** — system-prompt overrides, role-hijacking phrases ("ignore previous instructions", "you are now..."), safety-bypass text, jailbreak signatures.
3. **Supply-chain risk** — unpinned deps in any declared `package.json` / `requirements.txt` / `pyproject.toml`, typosquat patterns (Levenshtein <2 to top-1k packages), known CVEs via osv.dev primary + GitHub Advisory fallback.
4. **Filesystem boundary violations** — path traversal (`../`, absolute paths to `/etc`, `~`), symlink creation outside designated dirs, write attempts to `.env`, `.claude/settings.json`, Doppler config paths.
5. **Third-Party Telemetry Surface** — utm-tagged links, vendor-controlled redirect URLs (e.g., `*.bit.ly`, `*.lnkd.in`, branded short-domains), referrer-tracking redirects, "powered by" / "brought to you by" footers in third-party SKILL.md. Two-tier severity: `HIGH-RISK` on outbound-beacon patterns (postinstall hooks calling external endpoints, redirect-tracking URLs in install-time content), `WARN` on branding-only.

Verdict output: `LOW-RISK | REVIEW | HIGH-RISK`. Mandatory advisory-output disclaimer footer:

```
Advisory static analysis only. LOW-RISK does not constitute a security audit,
certification, or warranty of safety. The skill executes in your environment
under your account; you remain responsible for review.
```

### FR2: First-party allowlist for Soleur-owned domains

Hard requirement (sanity-grep verified `social-distribute` + `brainstorm` SKILL.md self-trip on `utm_`). Allowlist covers:

- `soleur.ai`, `soleur.dev`, `*.soleur.ai`, `*.soleur.dev`
- `github.com/jikig-ai`, `*.jikig-ai.com`
- Soleur-owned utm campaigns (declared in `references/first-party-allowlist.yaml`)

Allowlist applied at category 5 (Third-Party Telemetry Surface) only. Categories 1-4 do not have allowlists.

### FR3: Two integration surfaces

- `skill-creator` post-scaffolding: scanner runs on every newly-scaffolded SKILL.md before commit. `HIGH-RISK` blocks the scaffolding flow with override.
- `agent-finder` post-fetch: scanner runs on the `curl`-fetched SKILL.md content in a temp buffer. Write to `.claude/agents/` or `.claude/skills/` only on `LOW-RISK | REVIEW-with-ack`.

Both surfaces invoke `skill-security-scan` via the `Skill` tool — no inlined logic, no script duplication.

### FR4: Override mechanism

Override path: `Skill-Security-Ack: <skill-slug> <reason>` git commit trailer + mandatory structured artifact at `knowledge-base/security/skill-overrides/YYYY-MM-DD-<skill-slug>.md`. Artifact frontmatter:

```yaml
---
skill: <slug>
source: <url-or-skill-creator>
findings_json: <inline-or-referenced>
justification: <free-text>
approver: <git-config-user>
scanner_version: <semver-or-rule-pack-sha>
timestamp: <ISO-8601>
---
```

Trailer is the trigger; artifact is the durable audit record (GDPR Art. 32 evidence). No installation proceeds without both.

### FR5: Scan-on-demand for already-installed skills

Existing skills (any SKILL.md not scaffolded or fetched via the new gate) run scan-on-demand via explicit invocation (`Skill: skill-security-scan`). Never retroactively block. Backwards-compatibility per parent spec TR7.

### FR6: `/plan`-aware skip-and-warn mode

When the scanner runs inside an active `/plan` invocation (detected via parent-process env or explicit flag), `HIGH-RISK` does NOT block install — instead emits a TODO that gates `/work` exit. Outside `/plan` (e.g., direct skill-install via `agent-finder` or `skill-creator` standalone), `HIGH-RISK` blocks with override required.

### FR7: Stale-state protection via `.scan-meta.json`

Scanner writes `.scan-meta.json` next to scanned SKILL.md (or in a side-channel directory `.claude/scan-meta/<skill-slug>.json` — plan decision Q2). Contents: rule-pack version, verdict, timestamp, findings JSON. Rule-pack updates do NOT retroactively re-classify previously-scanned skills.

### FR8: Self-defense

- Pin pattern-file SHAs in `references/semgrep-skill-rules.yaml` and `references/regex-patterns.md`.
- Treat osv.dev API responses as untrusted input (validate JSON shape, reject malformed responses, fail-closed if osv.dev returns a verdict the scanner cannot parse).
- Ship a self-test fixture at `plugins/soleur/skills/skill-security-scan/test/` that fails loud if the scanner fails open (e.g., a known-malicious SKILL.md returning `LOW-RISK`).
- Rule-pack updates require a PR with `Skill-Security-Rule-Update:` trailer; bypass-prevention via `scripts/retired-rule-ids.txt` precedent.

## Technical Requirements

### TR1: Scanner location and skill structure

Dedicated skill at `plugins/soleur/skills/skill-security-scan/`:

```
SKILL.md                              # ~30-word description, name: skill-security-scan
scripts/run-scan.sh                   # main entry point
scripts/check-codeexec.sh             # FR1 category 1
scripts/check-prompt-injection.sh     # FR1 category 2
scripts/check-supply-chain.sh         # FR1 category 3 (osv.dev + GH Advisory)
scripts/check-filesystem-boundary.sh  # FR1 category 4
scripts/check-telemetry-surface.sh    # FR1 category 5
references/semgrep-skill-rules.yaml   # semgrep rule pack (SHA-pinned)
references/regex-patterns.md          # regex patterns for frontmatter prompt-injection
references/first-party-allowlist.yaml # FR2 Soleur-owned domains + utm campaigns
references/disclaimer.md              # mandatory advisory-output text
test/fixtures/                        # known-malicious + known-clean SKILL.md fixtures
test/fail-loud.test.sh                # FR8 self-test
```

Mirrors `plugins/soleur/skills/gdpr-gate/SKILL.md` structure verbatim. Single source of truth; both `skill-creator` and `agent-finder` invoke via `Skill` tool.

### TR2: Detection layer — semgrep + targeted regex, no LLM at install-time

- semgrep via reused `plugins/soleur/skills/review/scripts/ensure-semgrep.sh` bootstrap.
- New rule pack: `references/semgrep-skill-rules.yaml` (extends not replaces existing `semgrep-custom-rules.yaml`).
- Targeted regex for SKILL.md frontmatter prompt-injection (markdown frontmatter not natively typed by semgrep).
- LLM second-pass explicitly out of scope for install-time gate. Reserved for future opt-in `/scan-on-demand` deep-mode.

### TR3: Supply-chain data source — osv.dev primary, GH Advisory fallback

- osv.dev: free, no auth, batched. Daily rule-pack refresh via lefthook hook.
- GitHub Advisory: complementary recall on osv.dev cache miss; we already process GitHub data, no new sub-processor.
- Snyk free tier: explicitly rejected (CLO: commercial-CI ToS no-go; CTO: rate-limit + auth-blocked).
- No persistent cache of third-party advisory bodies (CLO: caching turns us into a controller for the derived dataset).

### TR4: Override capture — `Skill-Security-Ack:` git commit trailer + structured artifact

- Trailer name: `Skill-Security-Ack:` (matches `Co-Authored-By:` muscle memory).
- Artifact location: `knowledge-base/security/skill-overrides/YYYY-MM-DD-<skill-slug>.md` (plan decision Q1: confirm vs. alternative locations).
- Both required; either alone is non-compliant. CI gate via `git interpret-trailers` + artifact-exists check.

### TR5: GDPR-gate integration

`/soleur:gdpr-gate` fires at plan Phase 2.7 per `hr-gdpr-gate-on-regulated-data-surfaces`. SKILL.md is user-authored content potentially containing PII (author emails, internal hostnames, customer-name examples). Likely outcome: minor (data-minimization in findings output, no raw SKILL.md content in telemetry/Sentry). Out of #2719 scope: validate at plan time and respond to findings before `/work`.

### TR6: User-impact-reviewer + CPO sign-off at review time

Per `hr-weigh-every-decision-against-target-user-impact`, brand-survival threshold `single-user incident` requires CPO + `user-impact-reviewer` agent sign-off. Wire into `/soleur:review` for this PR.

### TR7: Backwards-compatibility for already-installed skills

Existing skills (FR5) scan-on-demand only. No automatic retroactive scans on rule-pack updates. `.scan-meta.json` versioning (FR7) prevents alert-fatigue from rule churn. Existing `skill-creator` and `agent-finder` invocations behave unchanged when no scan is requested.

### TR8: MIT attribution

Per parent spec TR3 + CLO Decision 16:

```markdown
<!-- Portions adapted from alirezarezvani/claude-skills (MIT License, Copyright (c) 2025 Alireza Rezvani). See LICENSES/skill-security-auditor.MIT.txt. -->
```

Attribution comment in `skill-security-scan/SKILL.md` body (not in frontmatter, not in launch copy). Verbatim MIT text committed at `LICENSES/skill-security-auditor.MIT.txt`.

### TR9: Token-budget compliance

- New `skill-security-scan` SKILL.md description ≤ ~30 words.
- Cumulative skill-description total must remain under 1800 words after addition (verify via `bun test plugins/soleur/test/components.test.ts`).
- Rule-pack contents (`semgrep-skill-rules.yaml`, `regex-patterns.md`) are references, not in description.

### TR10: Self-test fixture (FR8)

- `test/fail-loud.test.sh` runs in CI on every `/plugins/soleur/skills/skill-security-scan/**` change.
- Fixture corpus: ≥3 known-malicious SKILL.md (one per categories 1, 2, 5), ≥3 known-clean (including a Soleur first-party SKILL.md to confirm allowlist works).
- Test fails the build if any known-malicious returns `LOW-RISK` or any known-clean returns `HIGH-RISK`.

## Success Criteria

- Scanner emits `LOW-RISK | REVIEW | HIGH-RISK` deterministically across the five categories.
- `agent-finder` post-fetch / pre-write integration writes only on `LOW-RISK | REVIEW-with-ack`.
- `skill-creator` post-scaffolding integration blocks on `HIGH-RISK` without override.
- Override flow produces both git commit trailer AND structured artifact; CI gate verifies both.
- Self-test fixture passes in CI; fail-loud test fails the build on tampering.
- Cumulative skill-description budget remains under 1800 words.
- Phase 4 (4.3 guided onboarding) cannot ship until this scanner is in production.
- Disclaimer footer present on every scan output.

## Out-of-Scope (deferred to follow-up issues)

- LLM second-pass deep-mode for opt-in `/scan-on-demand` (not at install-time).
- Runtime sandbox for installed skills (orthogonal capability).
- Cross-skill dependency graph analysis (skill-of-skills risk).
- Telemetry/SIEM integration for scan-result aggregation.
- Soleur Cloud (web platform) UX surfaces for scan results — this spec covers the CLI/local-repo gate only.
