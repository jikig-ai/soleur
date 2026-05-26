---
date: 2026-05-10
issue: 2719
parent_brainstorm: knowledge-base/project/brainstorms/2026-05-10-skill-security-scan-brainstorm.md
spec: knowledge-base/project/specs/feat-skill-security-scan/spec.md
branch: feat-skill-security-scan
worktree: .worktrees/feat-skill-security-scan/
draft_pr: 3524
roadmap_row: 4.11
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
detail_level: A LOT
---

# Plan: skill-security-scan implementation (#2719)

## Overview

Build a dedicated `skill-security-scan` Soleur skill that runs an advisory static-analysis gate at two write-side checkpoints — `skill-creator` post-scaffolding (between Step 4 and Step 5) and `agent-finder` post-fetch / pre-write (between §4b validation and §4c provenance) — emitting `LOW-RISK | REVIEW | HIGH-RISK` across five detection categories (code-execution anti-patterns, prompt-injection in SKILL.md frontmatter and body, supply-chain risk via osv.dev, filesystem boundary violations, Third-Party Telemetry Surface). `HIGH-RISK` blocks install by default; override = `Skill-Security-Ack: <slug> <reason>` git commit trailer + structured artifact at `knowledge-base/security/skill-overrides/YYYY-MM-DD-<slug>.md` (GDPR Art. 32 evidence). The implementation reuses `plugins/soleur/skills/review/scripts/ensure-semgrep.sh` (semgrep bootstrap), mirrors the `gdpr-gate` advisory-gate pattern (skill structure, lefthook plumbing, telemetry emit), and lifts the three-tier enforcement vocabulary from `ADR-011`. Brand-survival threshold: `single-user incident`. CPO sign-off required at plan time before `/work`.

This plan implements all decisions in the brainstorm + spec while reconciling five inaccuracies surfaced by repo-research-analyst (see Research Reconciliation below). It introduces three net-new conventions (`knowledge-base/security/`, `LICENSES/`, `Skill-Security-Ack:` git trailer) and requires a Phase 0 budget reclamation (current skill-description budget is 1799 / 1800 — adding any new skill is mathematically blocked without trim).

**Documentation-pattern note:** Concrete dangerous-pattern token sequences (specific dynamic-evaluation primitives, OS-shell-invocation API names, etc.) are listed in the rule pack files (YAML), NOT inlined in this plan prose. Inlining triggers the repo's `security_reminder_hook.py` PreToolUse guard. Phase 2.x descriptions paraphrase pattern *categories*; the authoritative pattern list lives in `plugins/soleur/skills/skill-security-scan/references/regex-patterns.md` and the per-category semgrep rule files.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Reality (verified) | Plan response |
|---|---|---|
| `agent-finder.md:108-115` does `curl > local-file` (brainstorm + spec FR3) | Lines 108-113 stream `curl` to stdout (no file redirect). Validation runs in-memory at 117-127, frontmatter mutation at 129-146, `Write` tool fires at 148-153. | Phase 9 inserts the scan call between line 127 (post-validation) and line 129 (pre-mutation). The "scan post-fetch into temp buffer" framing remains correct conceptually — content is in-memory by step 4b — but the implementation is "scan the in-memory string before frontmatter mutation," not "buffer to a temp file." |
| TR9 says cumulative skill-description must "remain under 1800 words after addition" | `bun test plugins/soleur/test/components.test.ts` reports **1799 / 1800 words used**. | Phase 0 reclaims ≥30 words from top offenders (`heal-skill` 36w, `gemini-imagegen` 35w, `discord-content` 35w, `skill-creator` 35w, `changelog` 34w) BEFORE adding the new skill. AC asserts post-trim headroom ≥30 words, post-addition still under 1800. |
| TR1/TR10 says scanner mirrors `gdpr-gate` skill structure verbatim, including `test/` directory for self-tests | `plugins/soleur/skills/gdpr-gate/` has NO `test/` directory; only one skill (`compound/test/phase-16.test.sh`) ships a per-skill bash test. Dominant pattern is bun test under `plugins/soleur/test/<name>.test.ts`. | Phase 5 self-test fixture lives at `plugins/soleur/test/skill-security-scan.test.ts` (bun test, dominant convention) plus a `references/test-fixtures/` dir of known-malicious + known-clean SKILL.md fixtures. NOT a per-skill `test/` dir. |
| TR4 says `Skill-Security-Ack:` git-trailer override (assumes existing precedent) | `git grep -n "interpret-trailers" .` returns zero hits. No `Skill-` prefixed trailer exists. The `knowledge-base/security/` directory does not exist. The `LICENSES/` directory does not exist. | Phase 1 creates `knowledge-base/security/skill-overrides/` + `LICENSES/`. Phase 4 introduces `Skill-Security-Ack:` as a net-new repo trailer convention with documentation in `references/override-mechanism.md`. Plan body explicitly flags these as greenfield additions, not "reuse." |
| Spec implies semgrep handles markdown natively | Semgrep does NOT natively support markdown. Use `languages: [generic]` mode. Frontmatter (YAML) and body (prose) need separate rule files for ≥2x precision. | Phase 2 splits rule pack into `references/rules/frontmatter.yaml` (high-precision YAML rules) and `references/rules/body.yaml` (generic-mode rules + targeted regex for prompt-injection patterns). Phase 7 calibrates against `plugins/soleur/skills/**/SKILL.md` and asserts <5% REVIEW, 0% HIGH-RISK on first-party content before merge. |
| Spec FR3 implies osv.dev returns deterministic `vulns` array for "no vulns" | Confirmed for **known** ecosystems. Unknown ecosystems return empty `vulns` silently — indistinguishable from "no known vulns." This is the load-bearing CLO concern about "treat osv.dev responses as untrusted input." | Phase 2.3 validates ecosystem against the OSV ecosystem allowlist (`PyPI`, `npm`, `Go`, `crates.io`, `RubyGems`, `Maven`, `NuGet`, `Packagist`, `Hex`, `Pub`) BEFORE sending the query. Unknown ecosystem → emit `REVIEW` with reason "ecosystem not in OSV allowlist," never `LOW-RISK`. Network/5xx → REVIEW (never silent LOW-RISK). HTTP timeout 8s + retry-once-on-5xx + ≤10 concurrent batch calls (defensive parallelism cap). |
| `agent-finder` is described as having no scanner today | Lines 117-127 already do basic validation (frontmatter parse, 100KB cap, path traversal warn) and "warn but don't block" on destructive bash blocks. | Phase 9 supersedes the existing destructive-bash-warn path with the full `skill-security-scan` invocation; the existing checks become a subset of category 1 (code-execution anti-patterns). No regression — same checks, plus the rest. |
| Eleventy docs auto-discovers new skills | `plugins/soleur/docs/_data/skills.js:12-82` has an explicit `SKILL_CATEGORIES` map. Uncategorized skills fall through to `"Uncategorized"` bucket (lines 180-188) — visible but mis-grouped. | Phase 11 adds `"skill-security-scan"` to the `"Review & Planning"` category in `SKILL_CATEGORIES` map. AC verifies the docs build groups it correctly. |
| Spec does not address squash-merge implications for git-trailer override | All Soleur PRs are squash-merged. Trailers on individual feature commits are collapsed into the squash message. The CI gate must validate the **merge commit**, not feature commits. | Phase 4 documents the squash-merge invariant in `references/override-mechanism.md` and the CI gate (Phase 10 lefthook + GH Actions check) parses `git log --format=%B -1 HEAD` for the trailer on the squash merge commit. PR template prompt directs the operator to add the trailer to the PR description (which becomes the squash body). |

## User-Brand Impact

**If this lands broken, the user experiences:** A solo founder using `agent-finder` or `skill-creator` to install a third-party community skill receives no warning when the SKILL.md contains a credential-exfiltration pattern, a prompt-injection that hijacks downstream Claude sessions into reading `.env` / Doppler secrets, a typosquatted dep with a known CVE, or outbound-beacon URLs leaking operator prompt context to an undisclosed third-party analytics endpoint. The skill installs cleanly, runs in the next agent invocation, and exfiltrates Doppler / Supabase / GitHub PAT / BYOK tokens before the founder notices.

**If this leaks, the user's credentials / KB content / private workflow context is exposed via:** (a) silent `LOW-RISK` verdict on a malicious skill that should have been `HIGH-RISK` (false-negative — Soleur's verdict creates a representation the founder relied on; liability shifts from skill author to Soleur), (b) self-trip on Soleur first-party SKILL.md that trains override-fatigue and stops the gate from working on actually-malicious cases (loud failure that disables the load-bearing defense), (c) override mechanism that doesn't survive squash-merge (trailer lands on feature commit, gets dropped on merge, CI gate accepts the merge with no override evidence — auditability collapse), (d) prompt-injection regex with high false-positive rate against legitimate Soleur content, leading operators to disable the gate entirely.

**Brand-survival threshold:** `single-user incident`. One credential-leak event, one cross-tenant KB exposure, one false-`LOW-RISK` on a known-malicious skill — any of these ends Soleur's brand-trust position in the founder market. EU jurisdiction in play.

**Mitigation summary:**
- Verdict naming `LOW-RISK | REVIEW | HIGH-RISK` (not the conventional `PASS | WARN | FAIL`) + mandatory advisory disclaimer footer (CLO Decision 1) — blunts warranty implication.
- First-party allowlist mandatory for category 5 (CMO Decision 5) — prevents self-trip.
- Calibration phase against `plugins/soleur/skills/**/SKILL.md` (Phase 7) before merge — asserts <5% REVIEW, 0% HIGH-RISK on first-party content.
- Squash-merge-aware override gate (Phase 4 + Phase 10) — CI parses the merge commit, not feature commits.
- Self-defense: SHA-pinned rule pack manifest, OSV untrusted-input handling, fail-loud self-test fixture (Phase 5 + CPO Decision 11).
- `/plan`-aware skip-and-warn mode (Phase 6) — prevents mid-plan derailment that trains override-fatigue.
- `.scan-meta.json` versioning (Phase 3 + CTO Decision 13) — rule-pack updates do NOT retroactively re-classify previously-scanned skills.

**CPO sign-off required:** This plan inherits the brand-survival threshold from the brainstorm. Per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`, CPO sign-off must be confirmed before `/work` begins. Brainstorm-time CPO assessment is on file in the brainstorm document; plan-time confirmation = explicit CPO acknowledgment that the implementation phases below correctly carry forward the framing. `user-impact-reviewer` will be invoked at review time per `plugins/soleur/skills/review/SKILL.md` conditional-agent block.

## Open Code-Review Overlap

1 open scope-out touches files this plan modifies:

- **#3322** — `review: extend lint-fixture-content.mjs glob to cover knowledge-base/project/learnings/`
  - **File:** `lefthook.yml`
  - **Disposition:** **Acknowledge** — this plan adds a new `skill-security-scan` lefthook stanza; #3322's concern is extending the existing `lint-fixture-content` hook's glob to cover `knowledge-base/project/learnings/`. The two changes are orthogonal (different hooks, different glob scopes, different waiver concerns). #3322 remains open as `Post-MVP / Later`.

## Files to Create

| Path | Purpose | Phase |
|---|---|---|
| `plugins/soleur/skills/skill-security-scan/SKILL.md` | Skill entry point, ~30-word description, name=skill-security-scan, MIT attribution comment in body | 1 |
| `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh` | Main entry: orchestrates 5 category scripts, aggregates verdicts, emits disclaimer footer, writes `.scan-meta.json` | 3 |
| `plugins/soleur/skills/skill-security-scan/scripts/check-codeexec.sh` | Category 1: shell/Python code-exec anti-patterns via semgrep generic + targeted regex | 2.1 |
| `plugins/soleur/skills/skill-security-scan/scripts/check-prompt-injection.sh` | Category 2: frontmatter (high-precision regex) + body (regex with proximity gate + Soleur prose allowlist) | 2.2 |
| `plugins/soleur/skills/skill-security-scan/scripts/check-supply-chain.sh` | Category 3: osv.dev batch query with ecosystem allowlist, REVIEW-on-unknown, network-error-as-REVIEW, defensive parallelism cap | 2.3 |
| `plugins/soleur/skills/skill-security-scan/scripts/check-filesystem-boundary.sh` | Category 4: path traversal, symlink-out-of-bounds, write attempts to `.env`/Doppler paths via semgrep generic | 2.4 |
| `plugins/soleur/skills/skill-security-scan/scripts/check-telemetry-surface.sh` | Category 5: utm/redirect/branding regex + first-party allowlist + two-tier severity | 2.5 |
| `plugins/soleur/skills/skill-security-scan/scripts/parse-override.sh` | Override gate: scans `git diff <base>...<head>` for newly-committed structured artifacts under `knowledge-base/security/skill-overrides/`, validates frontmatter schema + findings_json freshness vs. current scanner output | 4 |
| `.claude/hooks/skill-security-scan-write.sh` | **PreToolUse hook on Write** to `.claude/skills/**` and `.claude/agents/**` — runs scanner on the in-memory content before the Write tool commits to disk. Returns `{permissionDecision: deny}` on HIGH-RISK without override artifact present. THIS is the load-bearing gate; agent-finder prose is the cooperative-fast-path advisory only. | 9, 10 |
| `plugins/soleur/skills/skill-security-scan/scripts/run-self-test.sh` | Fail-loud self-test runner: feeds known-malicious + known-clean fixtures through scanner, asserts deterministic verdicts | 5 |
| `plugins/soleur/skills/skill-security-scan/references/rules/frontmatter.yaml` | Semgrep YAML-mode rules for SKILL.md frontmatter (high-precision, scoped to known fields) | 2.2 |
| `plugins/soleur/skills/skill-security-scan/references/rules/body.yaml` | Semgrep generic-mode rules + targeted regex for body prose | 2.2 |
| `plugins/soleur/skills/skill-security-scan/references/rules/manifest.yaml` | SHA-pinned rule-pack manifest (per-rule-file `sha256` + `version: <semver>`) — no first-class semgrep lockfile exists | 5 |
| `plugins/soleur/skills/skill-security-scan/references/regex-patterns.md` | Authoritative regex pattern list + provenance + Soleur prose allowlist + first-party domain allowlist (concrete patterns live HERE, not in plan prose) | 2.2, 2.5 |
| `plugins/soleur/skills/skill-security-scan/references/first-party-allowlist.yaml` | Soleur-owned domains, utm campaigns, brand glyphs (allowlist for category 5) | 2.5 |
| `plugins/soleur/skills/skill-security-scan/references/disclaimer.md` | Mandatory advisory-output disclaimer text per CLO Decision 1 | 3 |
| `plugins/soleur/skills/skill-security-scan/references/override-mechanism.md` | Operator docs for `Skill-Security-Ack:` trailer + structured artifact pairing + squash-merge invariant | 4 |
| `plugins/soleur/skills/skill-security-scan/references/test-fixtures/malicious-codeexec.skill.md` | Known-malicious fixture: shell-eval pattern in body | 5 |
| `plugins/soleur/skills/skill-security-scan/references/test-fixtures/malicious-prompt-injection.skill.md` | Known-malicious fixture: role-hijack in frontmatter | 5 |
| `plugins/soleur/skills/skill-security-scan/references/test-fixtures/malicious-telemetry-beacon.skill.md` | Known-malicious fixture: outbound-beacon URL pattern | 5 |
| `plugins/soleur/skills/skill-security-scan/references/test-fixtures/clean-soleur-style.skill.md` | Known-clean fixture mirroring Soleur first-party SKILL.md style (must NOT trip allowlist) | 5 |
| `plugins/soleur/skills/skill-security-scan/references/test-fixtures/clean-third-party.skill.md` | Known-clean third-party fixture: passes all 5 categories with no findings | 5 |
| `plugins/soleur/test/skill-security-scan.test.ts` | Bun test suite: per-category fixture assertions + E2E + calibration corpus check | 5, 7 |
| `LICENSES/skill-security-auditor.MIT.txt` | Verbatim MIT license text from alirezarezvani/claude-skills (TR8 attribution) | 1 |
| `knowledge-base/security/skill-overrides/.gitkeep` | Net-new directory for structured override artifacts (CLO GDPR Art. 32 evidence) | 1 |
| `.claude/hooks/skill-security-scan.sh` | Lefthook commit-time advisory hook: detects SKILL.md/community-skill commits, runs scanner, emits telemetry, exit 0 (advisory) | 10 |
| `.claude/hooks/skill-security-scan-write.sh` | PreToolUse hook on Write tool — load-bearing gate. Returns deny/ask/allow per scanner verdict + override-artifact presence. | 9, 10 |
| `references/override-artifact-schema.json` | JSON schema for override artifact frontmatter (skill, source, findings_json, justification, approver, scanner_version, rule_pack_sha256, verdict, timestamp) | 4 |
| ~~`references/first-party-skill-exceptions.yaml`~~ | REMOVED in review pass — was unwired scaffolding. Allowlist (regex-patterns.md + first-party-allowlist.yaml) is sufficient at current corpus size (0 HIGH / 3 REVIEW on 69 skills). Re-introduce only when a calibration regression cannot be resolved via prose-level allowlist expansion. | — |
| `.github/workflows/skill-security-scan-pr-trailer.yml` | CI pre-merge required check (Layer C) — runs on pull_request_target synchronize, validates override artifact presence + freshness | 10 |
| `.github/workflows/skill-security-scan-postmerge.yml` | CI post-merge audit (Layer D) — re-validates on push to main, auto-files compliance/critical on bypass | 10 |
| `.github/workflows/skill-security-scan-corpus.yml` | CI continuous calibration — runs Phase 7 corpus check on every push to main + every PR modifying rule pack files | 7, 10 |

## Files to Edit

| Path | Change | Phase |
|---|---|---|
| `plugins/soleur/skills/heal-skill/SKILL.md` | Trim description from 36w → ≤30w (budget reclamation) | 0 |
| `plugins/soleur/skills/gemini-imagegen/SKILL.md` | Trim description from 35w → ≤30w (budget reclamation) | 0 |
| `plugins/soleur/skills/discord-content/SKILL.md` | Trim description from 35w → ≤30w (budget reclamation) | 0 |
| `plugins/soleur/skills/skill-creator/SKILL.md` | Trim description 35w→≤30w; add Step 5 hook to invoke `skill-security-scan` against newly-scaffolded SKILL.md before packaging | 0, 8 |
| `plugins/soleur/skills/changelog/SKILL.md` | Trim description from 34w → ≤30w (budget reclamation) | 0 |
| `plugins/soleur/agents/engineering/discovery/agent-finder.md` | Insert `skill-security-scan` invocation between line 127 (§4b end) and line 129 (§4c start). On `HIGH-RISK`: abort write, surface verdict + override instructions. On `REVIEW`: prompt operator to acknowledge before write. | 9 |
| `lefthook.yml` | Add new stanza `skill-security-scan-advisory` with priority 7 (after gdpr-gate's priority 6), array-of-globs path matching, `{staged_files}` pass-through. Per `2026-03-21-lefthook-gobwas-glob-double-star.md`. | 10 |
| `plugins/soleur/docs/_data/skills.js` | Add `"skill-security-scan"` entry to `SKILL_CATEGORIES["Review & Planning"]` array | 11 |
| `plugins/soleur/README.md` | Update skill count + add row in skill table | 11 |
| `knowledge-base/legal/compliance-posture.md` | Append Active Compliance Item: "Skill-install advisory gate (#2719) — single-user incident threshold, EU jurisdiction, advisory disclaimer mandatory" | 11 |
| `docs/legal/disclaimer.md` | Append automated-tooling clause per CLO requirement | 11 |
| `knowledge-base/product/roadmap.md` | Update Phase 4 row 4.11 status: `Brainstormed` → `Planned` | 11 |
| `plugins/soleur/test/components.test.ts` | No edit if Phase 0 reclamation succeeds; otherwise raise `SKILL_DESCRIPTION_WORD_BUDGET` (line 12) with documented justification | 0 |

## Implementation Phases

### Phase 0: Token-budget reclamation (PRECONDITION — blocks all subsequent phases)

**Sequencing AC (SpecFlow Gap 8):** Phase 0 trim commits MUST land in the same commit as (or earlier than) Phase 1 scaffold. If batched, both Phase 0 trims AND new skill description appear in one atomic commit. CI runs `bun test plugins/soleur/test/components.test.ts` against the committed tree; partial trim or partial scaffold = budget violation. Implementer plan: stage all 5 trim edits + the new skill SKILL.md + the new skill registration in one commit, run `bun test` locally before committing.

**Why first:** `bun test plugins/soleur/test/components.test.ts` currently reports 1799 / 1800 words. Adding any new skill description fails the test. This phase reclaims headroom before anything else.

**Steps:**
1. Read each of the 5 top-offending SKILL.md files. Identify trim targets (redundant phrases, "this skill" preambles, parenthetical examples).
2. Trim each from current word count to ≤30 words while preserving routing intent. Per `plugins/soleur/AGENTS.md` Skill Compliance Checklist: descriptions are for routing, not instruction. Target ~30 words per skill.
3. Re-run `bun test plugins/soleur/test/components.test.ts` and verify cumulative count decreased by ≥30 words (i.e., ≤1769 / 1800 before adding `skill-security-scan`).
4. **Acceptance:** Post-Phase-0 budget headroom ≥ 30 words; post-Phase-1 budget (with new skill description added) still ≤ 1799 / 1800.
5. **Fallback:** If Phase 0 cannot reclaim 30 words without losing routing fidelity, raise `SKILL_DESCRIPTION_WORD_BUDGET` in `plugins/soleur/test/components.test.ts:12` from 1800 → 1850 with a comment citing `#2719` and the brainstorm decision. Document the budget raise in the PR `## Changelog` section.

**Test:** `bun test plugins/soleur/test/components.test.ts` passes with both pre-trim and post-add states.

### Phase 1: Skill scaffold + LICENSES + knowledge-base/security/

**Steps:**
1. Create directory tree:
   ```
   plugins/soleur/skills/skill-security-scan/
     SKILL.md
     scripts/
     references/
       rules/
       test-fixtures/
   LICENSES/
   knowledge-base/security/skill-overrides/
   ```
2. Write `SKILL.md` with frontmatter (`name: skill-security-scan`, third-person description ≤30w), MIT attribution comment in body (NOT frontmatter), and `[references/rules/manifest.yaml](./references/rules/manifest.yaml)` link convention per skill-compliance checklist.
3. Write `LICENSES/skill-security-auditor.MIT.txt` with verbatim MIT license + Copyright (c) 2025 Alireza Rezvani.
4. Write `knowledge-base/security/skill-overrides/.gitkeep` to create the directory under git tracking.
5. Initialize all script files as `#!/usr/bin/env bash\nset -euo pipefail\n# TODO Phase 2.x` stubs so Phase 2 can run scripts in parallel without import-not-found errors.

**Test:** `find plugins/soleur/skills/skill-security-scan/ -type f | wc -l` returns expected count; `bun test plugins/soleur/test/components.test.ts` passes (description registered, budget OK).

### Phase 2: Detection scripts (5 sub-phases, parallelizable after Phase 1 completes)

Each sub-phase produces ONE category script + its rules + its fixture. Each script's contract: stdin = SKILL.md content, stdout = JSON `{verdict, findings, category}`, exit code = 0 always (advisory). Verdict aggregation lives in Phase 3.

**Concrete pattern lists live in `plugins/soleur/skills/skill-security-scan/references/regex-patterns.md` and the per-category rule YAML files (Phase 2 deliverables).** Plan prose paraphrases pattern *categories*; the work-time implementer is the source of truth for literal token sequences.

#### Phase 2.1: check-codeexec.sh (Category 1)

**Pattern categories to detect (concrete tokens in `references/rules/code-exec.yaml`):**
- Dynamic-evaluation primitives in body code blocks (the well-known eval / exec / Function-constructor variants across JavaScript and Python).
- Shell-spawn calls that pipe concatenated user-controlled arguments into the system shell. Covers the dangerous shell-true variants in Python's subprocess module, the Node child-process spawn-into-shell variants, the POSIX shell-with-flag-c form, and the OS-level shell-invocation helper. Does NOT cover the corresponding execFile-style / spawn-file-style sibling APIs that bypass the shell.
- Obfuscation signatures: base64-decode-then-execute pipelines; hex-encoded payloads ≥40 chars; backtick-pipe-execute patterns.
- Shell expansions inside string interpolations spanning 2+ tokens that resolve to user-controllable values.

**Implementation:**
- Run `semgrep --config references/rules/code-exec.yaml --json --no-git-ignore -` on stdin (semgrep generic mode for prose; bash mode for fenced code blocks).
- Augment with targeted regex for obfuscation signatures (semgrep generic mode is weak on multi-token semantic patterns).
- Output JSON: `{verdict: "LOW-RISK"|"REVIEW"|"HIGH-RISK", findings: [{rule_id, line, snippet}], category: "code-execution"}`.

**Severity calibration:**
- Dynamic-eval / dynamic-exec / Function-constructor pattern in code block → HIGH-RISK
- Shell-spawn with user-controlled args → HIGH-RISK
- Shell-spawn with hardcoded args → REVIEW
- Obfuscation signatures → HIGH-RISK
- Shell expansion in interpolation → REVIEW

**Test:** Fixture `malicious-codeexec.skill.md` returns HIGH-RISK; `clean-soleur-style.skill.md` returns LOW-RISK.

#### Phase 2.2: check-prompt-injection.sh (Category 2)

**Pattern categories to detect (concrete regexes in `references/regex-patterns.md`):**
- **Frontmatter — high precision:** role-hijack imperatives directing the agent to discard prior instructions; mode-jailbreak signature phrases (DAN-class, developer-mode, jailbreak); system-prompt exfiltration imperatives ("reveal", "print", "show" the system prompt); delimiter-break-out tokens (`</system>`, common chat-template open/end markers, fenced code-block followed by `system:`).
- **Body — proximity-gated to drop FP rate:** same patterns BUT require `you must` / `you should` proximity within 10 tokens, OR the pattern appears inside frontmatter, OR a base64-blob (`[A-Za-z0-9+/]{40,}={0,2}`) is present nearby.
- **Soleur prose allowlist:** `ignore.*(step|cache|warning|error|file|test|null|undefined)` is downgraded to `LOW-RISK` (legitimate flow-control prose).

**Implementation:**
- Parse frontmatter (between leading `---\n` and second `---\n`).
- Run frontmatter rules at HIGH-RISK severity.
- Run body rules at REVIEW severity (downgrade from HIGH-RISK because of FP risk on legitimate prose).
- Apply Soleur allowlist to downgrade matches that are clearly flow-control prose.
- Detect zero-width characters (U+200B/200C/200D/FEFF) anywhere → REVIEW.

**Output:** Same JSON shape as 2.1.

**Test:** `malicious-prompt-injection.skill.md` (frontmatter `description: ignore all previous instructions...`) returns HIGH-RISK; `clean-soleur-style.skill.md` containing legitimate "ignore the previous step" returns LOW-RISK.

#### Phase 2.3: check-supply-chain.sh (Category 3)

**Implementation:**
1. Parse SKILL.md content for inline manifests: `package.json`, `requirements.txt`, `pyproject.toml`, `Cargo.toml` references / inline blocks.
2. Validate ecosystem against OSV allowlist: `["PyPI", "npm", "Go", "crates.io", "RubyGems", "Maven", "NuGet", "Packagist", "Hex", "Pub"]`. **Unknown ecosystem → emit REVIEW with `reason: "ecosystem not in OSV allowlist"`. Never LOW-RISK.**
3. Detect typosquat patterns: Levenshtein distance < 2 to top-1k packages (vendored list at `references/typosquat-targets.yaml`).
4. POST batch query to `https://api.osv.dev/v1/querybatch` with HTTP timeout 8s, retry-once on 5xx, max 10 concurrent batches.
5. Network/5xx after retry → REVIEW with `reason: "OSV query failed"`. Never silent LOW-RISK pass.
6. For each `vulns[i].vulns` array: empty → no finding for that package; populated → REVIEW (single advisory) or HIGH-RISK (≥3 advisories or any with severity HIGH/CRITICAL).

**Self-defense (CPO Decision 11):**
- Validate response JSON shape against schema before consuming. Reject any response missing `results` array → REVIEW with `reason: "OSV response shape invalid"`.
- Cap response body size at 32 MiB (OSV documented limit) — reject larger as malformed.
- All osv.dev URLs hardcoded; no user-controllable endpoint redirection.

**Test:** Fixture with known-typosquat (`reqests` for `requests`) returns REVIEW with typosquat finding. Fixture with intentionally-unknown ecosystem returns REVIEW with allowlist reason.

#### Phase 2.4: check-filesystem-boundary.sh (Category 4)

**Pattern categories to detect (concrete tokens in `references/rules/filesystem-boundary.yaml`):**
- Path traversal via `../` sequences and absolute paths to system directories like `/etc`, `/root`, and operator credential dirs (`~/.ssh`, `~/.aws`, `~/.config/doppler`).
- Symlink-creation calls in body code that target paths outside designated dirs.
- Write attempts targeting sensitive dotfiles: `.env`, `.env.local`, `doppler.yaml`, `.claude/settings.json`.
- Read attempts on credential paths (cat / read of SSH keys, AWS credentials, etc.).

**Implementation:** semgrep generic mode + targeted regex.

**Severity:**
- Write to dotfile-credential paths → HIGH-RISK
- Read from credential paths → HIGH-RISK
- Path traversal in declarative paths → REVIEW
- Symlink-out → REVIEW

**Test:** Fixture with credential-path read in body code → HIGH-RISK; fixture with `cat ./config.json` → LOW-RISK.

#### Phase 2.5: check-telemetry-surface.sh (Category 5)

**Pattern categories to detect:**
- utm-tagged links: `utm_(source|medium|campaign|term|content)=`
- Vendor redirect/tracking domains: `*.bit.ly`, `*.lnkd.in`, `*.t.co`, `trk.*`, `track.*`, `r.*`, branded short-domains list at `references/redirect-domains.yaml`
- Vendor logos / brand glyphs: image tags whose attributes or URLs include `logo`/`brand`/`sponsor`.
- "Powered by" / "brought to you by" / "sponsored by" footers (case-insensitive)
- Outbound beacon patterns in code blocks: HTTP fetch/post calls (any of `fetch`, `axios.post`, equivalent) targeting non-allowlisted domains.

**First-party allowlist (`references/first-party-allowlist.yaml`):**
```yaml
domains:
  - soleur.ai
  - soleur.dev
  - "*.soleur.ai"
  - "*.soleur.dev"
  - github.com/jikig-ai
  - "*.jikig-ai.com"
utm_campaigns:
  - <enumerated from social-distribute SKILL.md>
  - <enumerated from brainstorm SKILL.md>
```

**Two-tier severity:**
- Outbound-beacon in postinstall hook / install-time content → HIGH-RISK
- Redirect-tracking URLs in install-time content → HIGH-RISK
- utm-tagged link to non-allowlisted domain → REVIEW
- Branding-only ("powered by", logos) → WARN (informational, downgrade to REVIEW for aggregation, never HIGH-RISK on its own)

**Test:** Fixture `malicious-telemetry-beacon.skill.md` with outbound-beacon to non-allowlisted domain → HIGH-RISK. `clean-soleur-style.skill.md` containing `utm_campaign=soleur-launch` (allowlisted) → LOW-RISK. Same fixture with `utm_campaign=sprinto-launch` (not allowlisted) → REVIEW.

### Phase 3: Verdict aggregator + disclaimer + .scan-meta.json

**run-scan.sh contract:**
- Accept SKILL.md content via stdin or file argument.
- Run all 5 category scripts in parallel via `xargs -P 5` (each writes to a temp JSON in `$XDG_RUNTIME_DIR/skill-security-scan-$$/`).
- Aggregate: max-severity wins. Any HIGH-RISK → HIGH-RISK. Else any REVIEW → REVIEW. Else LOW-RISK.
- **WARN-tier semantics (SpecFlow Gap 1):** `WARN` is a finding-level metadata tag for category 5 branding-only findings (logos, "powered by" footers). The verdict-aggregation enum is strictly `LOW-RISK | REVIEW | HIGH-RISK` — `WARN` findings contribute `REVIEW` to the verdict aggregation max, never escalate to HIGH-RISK on their own. JSON schema for per-script output: `verdict: "LOW-RISK"|"REVIEW"|"HIGH-RISK"` (enum), with optional per-finding `severity: "WARN"|"REVIEW"|"HIGH-RISK"` for finding-level tagging.
- Emit findings table in markdown to stdout with disclaimer footer (CLO Decision 1).
- Write `.scan-meta.json` next to input file (or to `$XDG_RUNTIME_DIR/...` if input is stdin) with: `{rule_pack_version, rule_pack_sha256, verdict, timestamp, scanner_version, findings_summary}`. **PII redaction (per gdpr-gate `GDPR-DataMin-1`):** before serializing `findings_summary`, run snippets through email/IP/IBAN-shape redaction.

**Disclaimer footer (mandatory, non-removable):**
```
---
Advisory static analysis only. LOW-RISK does not constitute a security audit,
certification, or warranty of safety. The skill executes in your environment
under your account; you remain responsible for review.

Scanner version: <version>  Rule pack: <sha-prefix>  Scanned: <ISO-8601>
```

**Acceptance:** Verdict deterministic given identical input + identical rule-pack SHA. `.scan-meta.json` schema validates against `references/scan-meta-schema.json`.

### Phase 4: Override mechanism (structured artifact alone — trailer dropped per plan review)

**Plan-review change (simplicity HIGH-confidence + Kieran P0-2 resolution):** The `Skill-Security-Ack:` git trailer is removed. The structured artifact alone is sufficient audit evidence. CI gate detects overrides by greping `git diff <base>...<head> --name-only --diff-filter=A` for new files matching `^knowledge-base/security/skill-overrides/\d{4}-\d{2}-\d{2}-.+\.md$`. This eliminates: R3 (squash-merge collapse), Kieran P0-2 (trailer case-folding), SpecFlow Gap 7 (post-edit trailer removal at merge), and Sharp Edge #4 (squash-merge invariant). Single mechanism, single parser, no merge-commit parsing.

**Structured artifact:** `knowledge-base/security/skill-overrides/YYYY-MM-DD-<skill-slug>.md`
```yaml
---
skill: <slug>
source: <url-or-skill-creator>
findings_json: <inline-or-file-reference>
justification: <free-text>
approver: <git-config-user.email>
scanner_version: <semver>
rule_pack_sha256: <sha256-prefix>
verdict: HIGH-RISK | REVIEW
timestamp: <ISO-8601>
---

# Override: <skill-slug>

## Findings (verdict: <verdict>)
<inline JSON or reference to scan-meta.json>

## Justification
<free-text rationale>
```

**parse-override.sh contract:**
- Accepts `--base <ref>` (default `main`) and `--head <ref>` (default `HEAD`).
- Run `git diff <base>...<head> --name-only --diff-filter=A` and filter to paths matching `^knowledge-base/security/skill-overrides/\d{4}-\d{2}-\d{2}-.+\.md$`.
- For each matched override artifact, validate:
  1. Frontmatter schema validates against `references/override-artifact-schema.json` (yamllint + jsonschema).
  2. `findings_json.rule_pack_sha256` matches HEAD's current `manifest.yaml` SHA — if mismatch, output `stale_findings` with operator instruction to re-run scan + update artifact.
  3. `verdict` field is one of `HIGH-RISK | REVIEW`.
  4. `skill` slug is non-empty and matches `^[a-z][a-z0-9-]*$`.
- Output: `{matched: [...], invalid_schema: [...], stale_findings: [...]}`.
- Exit 0 if all matched artifacts validate; exit 1 otherwise (advisory enforcement happens in caller — pre-commit hook + post-merge CI workflow).

**Override flow for operator:**
1. Operator hits HIGH-RISK on a third-party skill they want to install.
2. Scanner output prints findings JSON + override instructions referencing `references/override-mechanism.md`.
3. Operator creates `knowledge-base/security/skill-overrides/YYYY-MM-DD-<slug>.md` with `verdict: HIGH-RISK`, embeds findings_json from `.scan-meta.json`, writes free-text justification.
4. Operator commits the artifact in the same PR as the skill install.
5. CI pre-commit and post-merge gates run `parse-override.sh`; valid artifact = override accepted.

**Multiple overrides per PR:** A single PR may install multiple skills. Each skill's override = one artifact file. `parse-override.sh` enumerates all matched artifacts independently; no shared state.

**Acceptance:** Test fixture with valid artifact in `git diff main...HEAD --diff-filter=A` → parse-override.sh exits 0. Artifact with mismatched `rule_pack_sha256` → exits 1, names stale artifact. Missing artifact for a HIGH-RISK skill install → caller (PreToolUse hook) blocks the Write before commit.

### Phase 5: Self-defense

**SHA-pinned rule-pack manifest** (`references/rules/manifest.yaml`):
```yaml
version: "1.0.0"
files:
  - path: rules/frontmatter.yaml
    sha256: <hex>
  - path: rules/body.yaml
    sha256: <hex>
  - path: rules/code-exec.yaml
    sha256: <hex>
  - path: rules/filesystem-boundary.yaml
    sha256: <hex>
  - path: first-party-allowlist.yaml
    sha256: <hex>
  - path: redirect-domains.yaml
    sha256: <hex>
  - path: typosquat-targets.yaml
    sha256: <hex>
```

**run-scan.sh self-check:** Before running any rule, recompute sha256 of each rule file and compare to manifest. Mismatch → fail-closed with REVIEW + reason "rule pack tampered." This prevents a poisoned rule pack from silently passing malicious skills.

**OSV untrusted-input handling:** Already specified in Phase 2.3 — schema validation, body-size cap, ecosystem allowlist, network-error-as-REVIEW.

**Fail-loud self-test fixture (run-self-test.sh):**
- Iterate through `references/test-fixtures/malicious-*.skill.md` and assert each returns HIGH-RISK.
- Iterate through `references/test-fixtures/clean-*.skill.md` and assert each returns LOW-RISK.
- If ANY known-malicious returns LOW-RISK or ANY known-clean returns HIGH-RISK, exit 1 with diagnostic. Wired into CI per Phase 10.

**Order-of-operations (SpecFlow Gap 4 — circular dependency resolution):** `run-self-test.sh` invokes `run-scan.sh` which performs the SHA-pin self-check FIRST. During rule-pack development (when rule files are edited but `manifest.yaml` SHAs haven't been recomputed), every self-test run would otherwise return REVIEW + reason "rule pack tampered" — masking the real fixture mismatch. Fix: `run-self-test.sh` accepts a `--regenerate-manifest` flag that recomputes manifest SHAs from current rule file contents BEFORE running fixtures. Without the flag (default in CI), strict SHA pin enforcement holds. Document the dev workflow: "edit rule, run `run-self-test.sh --regenerate-manifest`, commit both rule + manifest in the same commit." `run-self-test.sh` exits non-zero if `--regenerate-manifest` is used in CI (env `CI=true`) — guards against accidental CI-time bypass.

**Test:** Self-test passes locally and in CI on every `plugins/soleur/skills/skill-security-scan/**` change.

### Phase 6: REMOVED per plan-review (DHH + simplicity HIGH-confidence cut)

The original `/plan`-aware skip-and-warn mode (env flag + `.scan-blockers/` markers + `/soleur:work` Phase 2 exit consumer) is removed. Rationale: `/soleur:plan` exploration does not scaffold or fetch skills — those code paths live in `skill-creator` and `agent-finder` only. The scanner therefore fires only at install-time (those two integrations) plus the PreToolUse hook on `.claude/skills/**` Writes. There is no mid-plan derailment to defer because there is no mid-plan invocation.

If a future plan-time scaffolding workflow emerges, re-evaluate this design with a tracking issue. CTO Decision 12 carry-forward survives in spirit: HIGH-RISK should never derail an exploratory phase. Today, the simplest realization of that goal is "don't invoke during /plan." The `SKILL_SECURITY_SCAN_PLAN_MODE` env-flag idea is preserved in `references/override-mechanism.md` as documented future-extension guidance only — not implemented in v1.

### Phase 7: Calibration against existing Soleur skills (CRITICAL) + escape valve for new first-party skills

**Why critical:** Prompt-injection regex has high FP risk on legitimate Soleur SKILL.md (e.g., "ignore the previous step", "override the default"). Without calibration, the gate becomes noise on day 1.

**Steps:**
1. Run `run-scan.sh` over every `plugins/soleur/skills/**/SKILL.md` (currently ~70 skills).
2. Aggregate results. Assert:
   - 0% of files return HIGH-RISK (fail the build if any do — either the file is genuinely problematic, or the rules need fixing).
   - <5% of files return REVIEW (warn if exceeded; fold matches into Soleur prose allowlist or first-party allowlist; iterate).
3. For each REVIEW match on a known-clean Soleur skill, decide:
   - **False positive:** Add to allowlist (`references/regex-patterns.md` Soleur prose allowlist for category 2; `references/first-party-allowlist.yaml` for category 5).
   - **True positive:** Filed as a separate issue (this means the Soleur skill itself has a problem; do not allowlist).
4. Re-run until first-party calibration passes.

**Failure-message format (SpecFlow Gap 9):** `bun test` failure output:
```
[skill-security-scan calibration] FAIL: <N> first-party skill(s) returned HIGH-RISK; expected 0.
  - <path>: verdict=HIGH-RISK, findings=<inline-json>
  - <path>: verdict=HIGH-RISK, findings=<inline-json>
[skill-security-scan calibration] FAIL: <M>% of first-party skills returned REVIEW; threshold 5%.
  - <path>: verdict=REVIEW, findings=<inline-json>
  ...
```
List ALL offenders, not just first. Include findings JSON inline so operator can decide allowlist-vs-issue without re-running the scanner.

**Continuous CI smoke (per simplicity reviewer #4):** A separate CI workflow `skill-security-scan-corpus.yml` runs the calibration check on every push to `main` AND on every PR that modifies `plugins/soleur/skills/skill-security-scan/references/rules/**`. This catches rule-pack-update-induced regressions on first-party content continuously, not just at #2719 merge time.

**Escape valve for new first-party skills (SpecFlow Gap 5):** When a future PR adds a new Soleur skill that legitimately needs a pattern that trips category 1 (e.g., a future security/docs skill that documents shell-spawn for legitimate ops use), the escape valve is: (a) operator adds the new skill's slug to a `references/first-party-skill-exceptions.yaml` with explicit per-category exception annotation + justification; (b) CI smoke test reads the exceptions file and downgrades HIGH-RISK to REVIEW for those slugs only; (c) any addition to the exceptions file requires a CODEOWNER review. Exceptions are NOT a general bypass — they're per-skill, per-category, with documented rationale. Reviewer responsibility: "is this exception load-bearing or a workaround for a real bug?"

**Test:** `bun test plugins/soleur/test/skill-security-scan.test.ts` includes a corpus check that asserts the calibration AC.

### Phase 8: Integration into skill-creator

**Edit `plugins/soleur/skills/skill-creator/SKILL.md`:**
- Trim description to ≤30 words (Phase 0).
- In Step 5 ("Validate the skill automatically", line 179-203), add post-validation hook:
  > After `package_skill.py` validates the new SKILL.md structure, invoke `skill: skill-security-scan` against the new SKILL.md. On HIGH-RISK: present findings, prompt operator for override (trailer + artifact) or revision. On REVIEW: present findings as informational, proceed. On LOW-RISK: proceed silently.
- Reference `references/override-mechanism.md` for override flow.

**Test:** Manually scaffold a deliberately-malicious test skill via skill-creator workflow → scanner blocks the package step. Manually scaffold a clean skill → scanner passes silently.

### Phase 9: Integration into agent-finder (cooperative-fast-path) + PreToolUse hook (load-bearing gate)

**Plan-review change (Kieran P0-1, agent-prose-as-gate is a category error):** Agent prose alone is insufficient — a malicious prompt-injected skill could persuade the agent to skip the scan call. The load-bearing gate is a PreToolUse hook on the `Write` tool with target paths under `.claude/skills/**` and `.claude/agents/**`. Agent-finder prose remains as the cooperative-fast-path that surfaces findings to the operator early — but the actual block-on-HIGH-RISK enforcement happens at the tool layer.

**Two-layer integration:**

**9a. Cooperative-fast-path (agent-finder prose, advisory):**

Edit `plugins/soleur/agents/engineering/discovery/agent-finder.md`. Insert between line 127 (end of §4b validation) and line 129 (start of §4c provenance):

> **§4b.5: Security scan (cooperative).** Before frontmatter mutation, invoke `skill: skill-security-scan` against the in-memory SKILL.md content. On HIGH-RISK: print findings + override instructions; the PreToolUse hook will block the actual Write regardless of whether you proceed. On REVIEW: print informational findings, proceed. On LOW-RISK: proceed silently. **Note:** This is the operator-friendly fast-path. The load-bearing gate is the PreToolUse hook on the Write tool.

The existing destructive-bash-warn at lines 117-127 stays in place (subset of category 1; graceful degradation when scanner is unavailable for any reason).

**9b. Load-bearing PreToolUse hook (`.claude/hooks/skill-security-scan-write.sh`):**

Hook fires on `tool_name == "Write"` with `tool_input.file_path` matching `^\.claude/(skills|agents)/.+\.md$`. Reads the proposed `tool_input.content` from the hook stdin payload, runs `bash $CLAUDE_PROJECT_DIR/plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh < <(echo "$content")`. On HIGH-RISK:
- Check if a valid override artifact exists in the current branch via `parse-override.sh`.
- If no override: emit `{hookSpecificOutput: {permissionDecision: "deny", permissionDecisionReason: "BLOCKED: skill-security-scan HIGH-RISK without override artifact under knowledge-base/security/skill-overrides/. See <skill-link>."}}` and exit 0.
- If override valid: allow Write to proceed, emit informational `{hookSpecificOutput: {permissionDecision: "allow"}}` plus `emit_incident skill-security-scan applied "high-risk-with-override"`.

On REVIEW: allow Write but emit `{hookSpecificOutput: {permissionDecision: "ask", permissionDecisionReason: "skill-security-scan REVIEW finding(s); see scan output above"}}` to surface the finding for operator confirmation.

On LOW-RISK: silent allow.

**9c. Verifying the in-memory framing actually holds (SpecFlow Gap 6):**

The agent-finder integration assumes no disk writes occur between line 117-127 validation and line 148-153 Write. Verify at implementation time: read agent-finder.md lines 117-148 carefully and assert (a) telemetry emits in this range are stdout-only or in-memory, NOT persistent sinks; (b) the frontmatter mutation at 129-146 builds an in-memory string, not a temp file. If either is false, lift the offending side effect to AFTER §4b.5 scan.

**Test:** Manually invoke `agent-finder` against a fixture URL serving `malicious-codeexec.skill.md` → both layers fire: agent prints findings, PreToolUse hook blocks the Write with the deny reason. Same against `clean-third-party.skill.md` → silent allow. Test fixture with malicious content + valid override artifact → PreToolUse hook allows the Write.

### Phase 10: Hook plumbing (two layers) + CI gates (pre-merge + post-merge)

**Layer A — PreToolUse hook (`.claude/hooks/skill-security-scan-write.sh`, load-bearing):**

This is the layer that actually blocks writes of malicious skills. Wired via `.claude/settings.json` PreToolUse matchers (Phase 10 includes the settings.json edit):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write",
        "filePathMatchers": ["^\\.claude/(skills|agents)/.+\\.md$"],
        "command": "bash ${CLAUDE_PROJECT_DIR}/.claude/hooks/skill-security-scan-write.sh"
      }
    ]
  }
}
```

The hook reads the proposed `tool_input.content` from stdin, runs `run-scan.sh`, and emits `{hookSpecificOutput: {permissionDecision: "deny"|"ask"|"allow", permissionDecisionReason: "<text>"}}`. Per Phase 9b above.

**Layer B — Lefthook commit-time advisory (`.claude/hooks/skill-security-scan.sh`):**

Belt-and-suspenders for `git commit` paths that bypass Claude Code's tool layer (manual edits, IDE commits, `git commit --no-verify` opt-out). Always exit 0; emit warning to stderr on HIGH-RISK without override artifact. New `lefthook.yml` stanza:

```yaml
pre-commit:
  commands:
    skill-security-scan-advisory:
      priority: 7  # after gdpr-gate-advisory (priority 6)
      run: bash {root}/.claude/hooks/skill-security-scan.sh {staged_files}
      glob:
        - "plugins/soleur/skills/**/SKILL.md"
        - ".claude/skills/**/SKILL.md"
        - ".claude/agents/**/*.md"
```

Both hooks use `$CLAUDE_PROJECT_DIR` for path resolution. Both source `.claude/hooks/lib/incidents.sh` with no-op fallback. Both emit telemetry: `emit_incident skill-security-scan applied "<verdict>"`.

**Layer C — CI pre-merge required check (`.github/workflows/skill-security-scan-pr-trailer.yml`):**

Runs on `pull_request_target` synchronize events. Steps:
1. Fetch base + head refs.
2. Run `parse-override.sh --base <merge-base> --head HEAD` against the PR diff.
3. For every new SKILL.md / agent MD added in the diff, run `run-scan.sh` — if HIGH-RISK, assert a corresponding override artifact is also in the diff.
4. Fail the check if any HIGH-RISK skill lacks a valid override artifact OR `parse-override.sh` reports `invalid_schema` / `stale_findings`.

This workflow file is required as a status check on `main` branch protection (above). Combined with Layer A, this addresses R15 (all-three-layer bypass).

**Layer D — CI post-merge audit (`.github/workflows/skill-security-scan-postmerge.yml`):**

Runs on push to `main`. Re-runs `parse-override.sh` against the merged diff. If the pre-merge gate was bypassed (admin merge, force-push), auto-files `compliance/critical` issue with the merge commit SHA.

**Test:** Local commit of malicious fixture without override → lefthook prints warning + Claude Code Write tool call denies via PreToolUse. PR with malicious skill but no artifact → CI pre-merge gate fails. Same PR with valid artifact → CI passes.

### Phase 11: Documentation site + roadmap + compliance posture

**Eleventy `_data/skills.js`:** Add `"skill-security-scan"` entry to `SKILL_CATEGORIES["Review & Planning"]` array.

**`plugins/soleur/README.md`:** Update skill count + add row in skill table.

**`knowledge-base/legal/compliance-posture.md`:** Append to Active Compliance Items:
> **Skill-install advisory gate (#2719)** — single-user incident threshold, EU jurisdiction. Verdict naming `LOW-RISK | REVIEW | HIGH-RISK` with mandatory advisory disclaimer (CLO requirement). Override = git trailer + structured artifact (GDPR Art. 32 evidence). Self-defense: SHA-pinned rule pack, OSV untrusted-input handling, fail-loud self-test.

**`docs/legal/disclaimer.md`:** Append automated-tooling clause:
> Soleur skills may include automated static-analysis tools that emit advisory verdicts (e.g., `LOW-RISK | REVIEW | HIGH-RISK`) on third-party content. These verdicts are advisory only and do not constitute a security audit, certification, or warranty of safety. Users remain responsible for reviewing third-party content before installation and execution.

**`knowledge-base/product/roadmap.md`:** Update Phase 4 row 4.11 status `Brainstormed` → `Planned`.

### Phase 12: Acceptance verification + smoke tests

**Pre-merge AC verification (every item must pass):**
1. Phase 0: `bun test plugins/soleur/test/components.test.ts` passes.
2. Phase 1: skill structure on disk; `LICENSES/skill-security-auditor.MIT.txt` contains MIT text; `knowledge-base/security/skill-overrides/.gitkeep` exists.
3. Phase 2.1-2.5: each `check-*.sh` script passes its fixture-driven test.
4. Phase 3: aggregator returns deterministic verdict; `.scan-meta.json` validates against schema.
5. Phase 4: `parse-override.sh` correctly enforces trailer + artifact pairing on test fixtures.
6. Phase 5: rule-pack SHA pinning enforced; OSV failure modes correctly map to REVIEW; `run-self-test.sh` passes.
7. Phase 6: `SKILL_SECURITY_SCAN_PLAN_MODE=1` correctly skips blocking on HIGH-RISK.
8. Phase 7: calibration corpus check asserts <5% REVIEW, 0% HIGH-RISK on first-party SKILL.md.
9. Phase 8 + 9: manual scaffolding + agent-finder integration fixtures pass.
10. Phase 10: lefthook hook fires on staged SKILL.md changes; post-merge CI workflow passes synthetic fixtures.
11. Phase 11: Eleventy build groups `skill-security-scan` correctly; README counts updated; compliance-posture + disclaimer landed.
12. Verdict-name grep guard: `git grep -nE "PASS\|WARN\|FAIL" plugins/soleur/skills/skill-security-scan/` returns zero matches in operator-facing files (sanity check that the rename was complete).

**Post-merge AC (operator):**
- None. This PR ships everything; no terraform apply, no migration, no infra change. CI gate (Phase 10 post-merge workflow) validates trailer + artifact pairing on the merge commit; if missing, follow-up issue is auto-filed.

## Test Scenarios

### Per-category fixture tests

| Fixture | Cat 1 | Cat 2 | Cat 3 | Cat 4 | Cat 5 | Aggregate |
|---|---|---|---|---|---|---|
| `malicious-codeexec.skill.md` | HIGH-RISK | LOW-RISK | LOW-RISK | LOW-RISK | LOW-RISK | HIGH-RISK |
| `malicious-prompt-injection.skill.md` | LOW-RISK | HIGH-RISK | LOW-RISK | LOW-RISK | LOW-RISK | HIGH-RISK |
| `malicious-telemetry-beacon.skill.md` | LOW-RISK | LOW-RISK | LOW-RISK | LOW-RISK | HIGH-RISK | HIGH-RISK |
| `clean-soleur-style.skill.md` (legit `ignore the previous step` + first-party utm) | LOW-RISK | LOW-RISK | LOW-RISK | LOW-RISK | LOW-RISK | LOW-RISK |
| `clean-third-party.skill.md` | LOW-RISK | LOW-RISK | LOW-RISK | LOW-RISK | LOW-RISK | LOW-RISK |

### E2E scenarios

1. **skill-creator scaffolding pipeline:** Operator scaffolds new skill → SKILL.md draft → invokes `skill-security-scan` → on HIGH-RISK PreToolUse hook denies the package step + presents override prompt → on REVIEW presents informational findings + asks confirmation → on LOW-RISK proceeds silently.
2. **agent-finder fetch pipeline:** Operator runs `agent-finder` against fixture URL → curl fetches in-memory → validation passes → cooperative scan in §4b.5 emits findings → PreToolUse hook fires on the Write tool call → HIGH-RISK denies the Write before frontmatter mutation; LOW-RISK allows.
3. **Override flow (artifact-only):** Operator commits feature branch with structured artifact at `knowledge-base/security/skill-overrides/YYYY-MM-DD-<slug>.md` in same PR as the skill install → `parse-override.sh` validates artifact schema + freshness → PreToolUse hook allows the Write → CI pre-merge gate passes.
4. **Override stale findings:** Operator commits override artifact, then rule pack updates (manifest SHA changes) before merge → CI gate detects `rule_pack_sha256` mismatch → fails with `stale_findings` instruction.
5. **Override missing artifact:** PR introduces a HIGH-RISK skill install with NO matching artifact under `knowledge-base/security/skill-overrides/` → PreToolUse hook denies the Write at scan time; if somehow committed, CI pre-merge `parse-override.sh` blocks merge.
6. **Self-defense rule-pack tampering:** Modify `references/rules/frontmatter.yaml` without updating manifest → `run-scan.sh` returns REVIEW with `reason: rule pack tampered`.
7. **OSV network failure:** Mock osv.dev to return 503 → `check-supply-chain.sh` retries once → still 503 → emits REVIEW with `reason: OSV query failed`. Never silent LOW-RISK.
8. **OSV unknown ecosystem:** Pass package with `ecosystem: "FakeEcosystem"` → emits REVIEW with `reason: ecosystem not in OSV allowlist`.
9. **Calibration corpus:** `bun test plugins/soleur/test/skill-security-scan.test.ts` runs scanner over all `plugins/soleur/skills/**/SKILL.md` → asserts 0% HIGH-RISK, <5% REVIEW.
10. **Adversarial host-spoofing (R14):** Fixture with `https://attacker.com/redirect?ref=soleur.ai` in body → category 5 detects host=`attacker.com` (NOT in allowlist) → HIGH-RISK. Same fixture with `https://soleur.ai/foo` → host=`soleur.ai` → LOW-RISK. Confirms allowlist matches URL host after parse, not raw substring.
11. **All-5-categories simultaneously:** Fixture triggering each category at HIGH-RISK independently → aggregate verdict is HIGH-RISK (single verdict, all 5 findings present in `findings_summary`).
12. **Regex meta-character in skill slug:** Override artifact filename contains `<slug>` with regex meta-chars (e.g., `foo.*bar`) → `parse-override.sh` rejects with `invalid_schema` reason "slug must match `^[a-z][a-z0-9-]*$`."
13. **Disclaimer footer round-trip:** Scanner output piped through `tee | jq | markdown-renderer` → disclaimer footer survives intact (no escape-quote breakage, no whitespace collapse).
14. **PII redaction in persisted output:** Fixture containing `author@example.com` → `.scan-meta.json` `findings_summary` contains `<email>` placeholder, NOT literal email. Sentry mirror payload (mocked) also contains `<email>`.
15. **Adversarial agent-prose-injection:** Malicious fixture includes prompt-injection in body designed to make the agent skip the §4b.5 scan call → cooperative-fast-path may be skipped, but PreToolUse hook on Write fires regardless → HIGH-RISK denies. Demonstrates load-bearing layer is hook, not prose.
16. **Multiple overrides in one PR:** Operator installs 2 third-party skills, both HIGH-RISK, both with valid artifacts → both Writes pass; `parse-override.sh` outputs `matched: [<slug-a>, <slug-b>], invalid_schema: [], stale_findings: []`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **Phase 0:** Cumulative skill description budget post-Phase-0 ≥ 30 words headroom; post-Phase-1 (with `skill-security-scan` description added) under 1800 words. `bun test plugins/soleur/test/components.test.ts` passes.
- [ ] **Phase 1:** `plugins/soleur/skills/skill-security-scan/` exists with SKILL.md, scripts/, references/, no test/ subdir. `LICENSES/skill-security-auditor.MIT.txt` contains verbatim MIT text. `knowledge-base/security/skill-overrides/.gitkeep` exists.
- [ ] **Phase 2:** All five `check-*.sh` scripts produce JSON output with `{verdict, findings, category}`. Each script's fixture-driven test passes.
- [ ] **Phase 3:** `run-scan.sh` aggregator emits markdown findings + mandatory disclaimer footer. `.scan-meta.json` validates against `references/scan-meta-schema.json`.
- [ ] **Phase 4:** `parse-override.sh` correctly accepts (trailer + artifact) pair, rejects either alone. Squash-merge invariant documented in `references/override-mechanism.md`.
- [ ] **Phase 5:** Rule-pack manifest SHA-pins all rule files. Tampering triggers REVIEW. OSV failure modes (network, malformed response, unknown ecosystem, oversized response) all map to REVIEW. `run-self-test.sh` passes.
- [ ] **Phase 6:** REMOVED — `/plan` does not invoke the scanner. `references/override-mechanism.md` documents the future-extension hook for plan-time scaffolding workflows.
- [ ] **Phase 7:** Calibration corpus check asserts 0% HIGH-RISK and <5% REVIEW on `plugins/soleur/skills/**/SKILL.md`. Any FP discovered during calibration is allowlisted with documented justification.
- [ ] **Phase 8:** `skill-creator` Step 5 invokes scanner; HIGH-RISK blocks packaging. Test fixture confirms.
- [ ] **Phase 9a (cooperative):** `agent-finder` §4b.5 invokes scanner before frontmatter mutation; emits findings to operator. Test fixture confirms cooperative emit on HIGH-RISK + REVIEW + LOW-RISK.
- [ ] **Phase 9b (load-bearing PreToolUse hook):** `.claude/hooks/skill-security-scan-write.sh` blocks Write on HIGH-RISK without override artifact. Test fixture demonstrates: malicious fixture in `agent-finder` flow with NO override artifact → hook returns `permissionDecision: deny`; same fixture WITH valid override artifact → hook returns `allow`.
- [ ] **Phase 9 invariant:** No disk writes occur between `agent-finder` line 117 (validation start) and line 148 (Write tool call). Telemetry emits in this range are stdout-only or in-memory buffers; persistent sink emits move to AFTER §4b.5 scan + Write success.
- [ ] **Phase 10:** `lefthook.yml` stanza fires on staged SKILL.md changes. `.claude/hooks/skill-security-scan.sh` (lefthook commit-time advisory) and `.claude/hooks/skill-security-scan-write.sh` (PreToolUse load-bearing) both use `$CLAUDE_PROJECT_DIR`. Pre-merge GH Actions workflow `skill-security-scan-pr-trailer.yml` runs on every `pull_request_target` synchronize event and validates: (a) any new HIGH-RISK skill install in the diff has a matching override artifact, (b) override artifact `rule_pack_sha256` matches HEAD's `manifest.yaml` SHA. Post-merge workflow `skill-security-scan-postmerge.yml` re-validates on push to main and auto-files `compliance/critical` issue if pre-merge gate was bypassed via admin merge.
- [ ] **Branch protection:** `main` branch requires `skill-security-scan-pr-trailer` pre-merge status check. Verified via `gh api repos/jikig-ai/soleur/branches/main/protection --jq '.required_status_checks.contexts'` → contains `skill-security-scan-pr-trailer`. Mitigates R15 (all-three-layer bypass). [Updated 2026-05-11 (#3542): the repo uses GitHub Rulesets, not classic branch protection — the active control is ruleset `#14145388` ("CI Required"), and the canonical check-run name is the job name `skill-security-scan PR gate`, not the workflow filename `skill-security-scan-pr-trailer`. Verify via `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.rules[0].parameters.required_status_checks[].context'`. R15 mitigation lands via `scripts/update-ci-required-ruleset.sh` per `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md`.]
- [ ] **Manifest SHA computation algorithm specified** (Kieran P1 #4): `references/rules/manifest.yaml` header documents: SHA = `sha256sum <file>` of raw bytes, files normalized to LF line endings via `.gitattributes text=auto`. Cross-platform check: `git ls-files | xargs -I{} sh -c 'sha256sum {} | head -c 64'`.
- [ ] **Phase 11:** Eleventy docs build categorizes `skill-security-scan` under "Review & Planning". `plugins/soleur/README.md` skill count + table updated. `compliance-posture.md` Active Items appended. `docs/legal/disclaimer.md` automated-tooling clause appended. `roadmap.md` row 4.11 status `Brainstormed → Planned`.
- [ ] **Verdict-name guard:** `git grep -nE "\bPASS\b|\bFAIL\b" plugins/soleur/skills/skill-security-scan/ knowledge-base/legal/ docs/legal/` returns zero matches in non-comment lines (sanity check the rename was fully applied). `WARN` in test/code blocks acceptable; check excludes `references/test-fixtures/`.
- [ ] **Tests:** `bun test plugins/soleur/test/skill-security-scan.test.ts` passes. `bun test plugins/soleur/test/components.test.ts` passes (no budget regression).
- [ ] **PR body:** Includes `## Changelog` section per `plugins/soleur/AGENTS.md` Pre-Commit Checklist; semver:minor label per "MINOR: New agents, commands, or skills" rule.
- [ ] **Issue link:** PR body uses `Closes #2719` exactly once on its own line (per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] **GDPR-gate:** `/soleur:gdpr-gate` invoked at plan Phase 2.7 (this plan); 0 Critical, 0 Important, 5 Suggestion findings. All Suggestion findings folded into Sharp Edges items 17-20 below + Phase 3 redaction requirement.
- [ ] **PII redaction in scanner output:** `run-scan.sh` redacts email-shaped tokens, IP addresses, IBAN-shaped tokens from `findings_summary` / `findings_json` before persisting to `.scan-meta.json` or override artifacts (per `GDPR-DataMin-1`). Test: SKILL.md fixture with `author@example.com` → persisted snippet contains `<email>` placeholder, not the literal email. Optional `--no-redact` env flag for forensic mode (lawful basis Art. 6(1)(f)) is OUT-OF-SCOPE for #2719; defer to follow-up if requested.
- [ ] **Override-artifact retention policy:** `references/override-mechanism.md` includes a "Retention" section stating override artifacts are retained for repository lifetime as Art. 32 evidence (Art. 6(1)(c) + Art. 6(1)(f) lawful basis) with PII redacted per `GDPR-DataMin-1`.
- [ ] **osv.dev Vendor DPA row:** `knowledge-base/legal/compliance-posture.md` Vendor DPAs section gets a new row: `osv.dev | Google LLC | Package metadata only — no operator identifier | SCC-equivalent (Google Cloud DPA)`.
- [ ] **Sentry payload redaction parity:** Scanner error mirrors to Sentry via `reportSilentFallback(err, { feature: 'skill-security-scan', extra: { ...redacted } })`. Test: simulated Sentry event from a category-2 finding on a fixture containing `author@example.com` does NOT contain the literal email in the payload.
- [ ] **CPO sign-off:** Confirmed at plan time via brainstorm carry-forward. `requires_cpo_signoff: true` in plan frontmatter.

### Post-merge (operator)

- [ ] None. CI post-merge workflow auto-validates trailer+artifact pairing on the merge commit; any gap auto-files a follow-up `compliance/critical` issue.

## Risks

| # | Risk | Likelihood | Impact | Mitigation | Phase |
|---|---|---|---|---|---|
| R1 | False-positive rate on legitimate Soleur SKILL.md exceeds 5%; operators learn override-fatigue | Medium | High (gate becomes noise, disabled in practice) | Calibration phase + Soleur prose allowlist + first-party domain allowlist; iterate until <5% REVIEW, 0% HIGH-RISK on first-party | 7 |
| R2 | Self-trip on existing `social-distribute` + `brainstorm` SKILL.md (utm_) | High | High (gate fails on day 1) | First-party allowlist mandatory in Phase 2.5; calibration verifies | 2.5, 7 |
| R3 | Squash-merge collapses trailer; CI gate validates feature commit instead of merge commit | High | High (override evidence drops on merge, audit trail breaks) | CI gate parses `git log --format=%B -1 HEAD` (merge commit only); operator instructions emphasize PR description as the trailer surface | 4, 10 |
| R4 | osv.dev unknown ecosystem returns silent empty; supply-chain category emits LOW-RISK on a real risk | Medium | High (false-negative class) | Ecosystem allowlist; unknown → REVIEW (never LOW-RISK) | 2.3 |
| R5 | osv.dev rate-limits or 5xx in CI; supply-chain category becomes flaky | Low (no documented limit) | Medium (CI flake) | HTTP timeout 8s + retry-once + ≤10 concurrent batches; network failure → REVIEW | 2.3 |
| R6 | Rule-pack drift: semgrep rule update silently re-classifies previously-PASSed skills | Medium | Medium (alert-fatigue) | `.scan-meta.json` per-skill records rule-pack SHA at scan time; rule updates do NOT retroactively re-classify | 3, 5 |
| R7 | Token-budget reclamation in Phase 0 cannot recover 30 words without losing routing fidelity | Low | Medium (blocks Phase 1) | Fallback: raise `SKILL_DESCRIPTION_WORD_BUDGET` 1800→1850 with documented justification | 0 |
| R8 | `/plan`-mode env detection is bypassed by manual override during /work; operator unaware they're skipping the gate | Low | Medium (process-level skip) | Env flag is grep-able in CI logs; documented in override-mechanism.md; CI post-merge workflow flags any HIGH-RISK SKILL.md merged without override evidence | 6, 10 |
| R9 | Scanner itself becomes attack surface (poisoned rule pack, malicious osv.dev response) | Medium | Critical (gate becomes the exploit) | SHA-pinned manifest validated at every run; OSV response schema-validated; fail-loud self-test fixture detects fail-open | 5 |
| R10 | Test fixtures contain real-shape secrets, tripping `cq-test-fixtures-synthesized-only` | Medium | Medium (CI fails on fixture lint) | Use `@example.com`/`@test.local`, synthesized UUIDs, no real Doppler/JWT/PAT tokens; waiver `# gitleaks:allow # issue:#2719 <reason>` if a real-shape pattern is essential to the test | 5 |
| R11 | MIT attribution not legally sufficient for some lifted text | Low | Medium (compliance gap) | CLO Decision 16 attribution string verbatim; verbatim MIT text under `LICENSES/skill-security-auditor.MIT.txt`; no verbatim code copies | 1 |
| R12 | Disclaimer footer omitted from one of the 5 category scripts; verdict ships without warranty disclaimer | Low | Critical (CLO liability shift) | Disclaimer is appended by `run-scan.sh` aggregator only — single point of insertion, not per-script; verdict-rename guard in AC asserts presence | 3 |
| R13 | Rule-pack format backward-incompatibility — semgrep upgrade changes rule schema; manifest SHA-pin freezes pack at old format that newer semgrep rejects; scanner fail-closes to REVIEW on every scan | Medium | High (gate becomes noise once semgrep upgrades) | Pin semgrep version in `references/rules/manifest.yaml` alongside per-file SHAs. Document upgrade procedure: bump semgrep + re-author rules + recompute SHAs in one commit. Self-test fixture catches the format break before merge. | 5 |
| R14 | Adversarial first-party allowlist abuse — malicious skill embeds `soleur.ai`-shaped tokens in beacon URLs to bypass category 5 detection (substring/glob match) | Medium | High (load-bearing allowlist becomes load-bearing bypass) | Allowlist matches URL **host** segment after parsing, not raw substring. Use `URL.host` extraction; reject patterns that span more than the host segment. Test fixture: `https://attacker.com/redirect?ref=soleur.ai` must trip detection (host is attacker.com, NOT soleur.ai). | 2.5, 7 |
| R15 | All-three-layer enforcement bypass — admin merge / force-push to main / merge-queue rewrite / direct push (uncommon but not impossible) | Low | Critical (no enforcement remains) | Branch protection rule on `main` requires `skill-security-scan-pr-trailer` pre-merge status check (Phase 10 CI workflow). Rule blocks force-push to main + admin-merge-bypass attempts. Documented in `references/override-mechanism.md` "Defense-in-depth" section. | 10 |

## Domain Review

**Domains relevant:** Product, Engineering, Legal, Marketing (carry-forward from brainstorm Phase 0.5)

### Product (CPO)

**Status:** reviewed (carry-forward)
**Assessment:** Brand-survival-critical given user-brand-critical tag. CPO decisions in brainstorm: `LOW-RISK|REVIEW|HIGH-RISK` verdict naming (now CLO Decision 1), pin pattern SHAs + treat osv.dev as untrusted (Decision 11), promote out of Post-MVP/p3-low (now Phase 4 row 4.11). CPO sign-off required at plan time per `requires_cpo_signoff: true`.

### Engineering (CTO)

**Status:** reviewed (carry-forward)
**Assessment:** Markdown-only static analyzer; no runtime sandboxing required. Reuse `semgrep-sast` agent + `ensure-semgrep.sh` bootstrap + `gdpr-gate` skill structure (with Research Reconciliation correction: gdpr-gate has no test/ dir; bun test convention applies). Critical grep finding (carry-forward): `agent-finder` does NOT do `npm install` / git clone today. Architectural risks: stale-state from rule-pack updates (Decision 13 → Phase 3 .scan-meta.json), `/plan`-aware skip-and-warn (Decision 12 → Phase 6 env flag), rule-pack as attack surface (Decision 11 → Phase 5 SHA pinning).

### Legal (CLO)

**Status:** reviewed (carry-forward + plan-time augmentation)
**Assessment:** Verdict-rename to `LOW-RISK | REVIEW | HIGH-RISK` + advisory disclaimer is non-negotiable (Decision 1 → Phase 3 disclaimer footer). Override = trailer + structured artifact (Decision 9 → Phase 4). Two-tier vendor severity (Decision 4 → Phase 2.5 outbound-beacon HIGH-RISK, branding WARN). Snyk free tier rejected (Decision 6). MIT attribution string locked (Decision 16 → Phase 1). GDPR-gate fires at plan Phase 2.7 (Decision 15). `compliance-posture.md` Active Items append (Phase 11). `docs/legal/disclaimer.md` automated-tooling clause append (Phase 11).

### Marketing (CMO)

**Status:** reviewed (carry-forward)
**Assessment:** "Third-Party Telemetry Surface" framing locked (Decision 3). ON by default (Decision 5b). First-party allowlist mandatory (Decision 5 + verified self-trip on `social-distribute` + `brainstorm` SKILL.md). Brand position: announce as "agent-native sub-processor surfacing" — defensible category claim. Override-justification artifacts re-positioned as exportable consent receipts.

**Brainstorm-recommended specialists:**
- CLO recommended `legal-document-generator` for `docs/legal/disclaimer.md` automated-tooling clause → covered by Phase 11 (manual edit per CLO Decision 1 disclaimer text already drafted in brainstorm; specialist invocation deferred unless plan-review flags need).
- CLO recommended update to `knowledge-base/legal/compliance-posture.md` Active Compliance Items → covered by Phase 11.

### Product/UX Gate

**Tier:** none (no `components/**/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx` in Files to Create. CLI-only skill.)

## Sharp Edges

1. **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is fully populated; do not strip or generalize during edits.
2. **Verdict naming is load-bearing.** Do NOT revert `LOW-RISK | REVIEW | HIGH-RISK` to the conventional alternatives during refactoring. CLO liability framing requires the renamed semantics + disclaimer footer.
3. **First-party allowlist self-trip is the day-1 failure mode.** `social-distribute` and `brainstorm` SKILL.md contain `utm_` patterns. Phase 7 calibration AC asserts 0% HIGH-RISK on first-party — if it fails, the allowlist is misconfigured, not the rule pack.
4. **Squash-merge collapses trailers.** The `Skill-Security-Ack:` trailer must land in the **PR description body** (which becomes the squash commit body), not just on a feature commit. CI gate parses the merge commit — if parsing the wrong commit, override evidence will look missing.
5. **OSV unknown-ecosystem returns silent empty.** Validate ecosystem against allowlist (`PyPI`, `npm`, `Go`, `crates.io`, `RubyGems`, `Maven`, `NuGet`, `Packagist`, `Hex`, `Pub`) BEFORE querying. Unknown ecosystem → REVIEW, never LOW-RISK.
6. **lefthook gobwas globs require array form for `**` patterns.** Per `2026-03-21-lefthook-gobwas-glob-double-star.md`, single `glob: "plugins/**/SKILL.md"` silently matches zero files. Use `glob: ["plugins/soleur/skills/**/SKILL.md", ".claude/skills/**/SKILL.md"]`.
7. **Hook paths must use `$CLAUDE_PROJECT_DIR`.** Never assume `pwd` or relative paths from the hook script — `$CLAUDE_PROJECT_DIR` is the only stable anchor across worktrees + bare repos.
8. **Test fixtures must use synthesized data per `cq-test-fixtures-synthesized-only`.** No real `@gmail.com` emails, prod-shape UUIDs, JWTs, Doppler tokens, BYOK keys. Use `@example.com` / `@test.local`. Waive a line with `# gitleaks:allow # issue:#2719 <reason>` if a real-shape pattern is essential.
9. **Disclaimer is appended by aggregator, not per category script.** Single point of insertion in `run-scan.sh`. If a script emits findings without disclaimer (e.g., debug mode), the wrapper still appends. Verdict-rename guard verifies presence.
10. **Calibration corpus check is non-skippable.** Phase 7 must run before merge — skipping it ships rules that may fire on every Soleur skill operation.
11. **Scanner self-defense includes the rule pack itself.** SHA-pinned manifest validated at every run; tampering = REVIEW + reason "rule pack tampered." Do not silence this check during /work for "convenience."
12. **`/plan`-mode env flag is grep-able in CI logs.** Operators cannot silently disable the gate without leaving a trace.
13. **`agent-finder` integration changes a hot path.** Phase 9 inserts the scan call between line 127 and 129. Edit conflicts with concurrent PRs touching this file are likely; rebase carefully.
14. **MIT attribution lives in skill body, not frontmatter, not launch copy.** Per CLO Decision 16. Frontmatter is for routing only.
15. **Token-budget reclamation in Phase 0 must preserve routing intent.** Cuts that lose discoverability semantics are worse than raising the budget cap. If trim is impossible, raise the cap with documented justification.
16. **Documenting bad-pattern token sequences in plan/learning prose trips the security_reminder PreToolUse hook.** Plan/learning files must paraphrase pattern *categories*; concrete literal token sequences live in the per-category rule YAML files (`references/rules/code-exec.yaml`, `references/rules/filesystem-boundary.yaml`, `references/regex-patterns.md`). When editing, do not inline pattern names like the OS-level shell-invocation helper or the Node child-process spawn-into-shell variants — the hook substring-matches and rejects.
17. **PII redaction is non-optional in persisted scanner output** (per gdpr-gate `GDPR-DataMin-1`). Findings persisted to `.scan-meta.json` and override artifacts MUST run through email/IP/IBAN-shape redaction before write. Snippets at scan-time stdout for operator review are unredacted; persisted forms are redacted. Reference learning `2026-04-17-pii-regex-scrubber-three-invariants.md` for the regex invariants (ReDoS bounds, structural-shape over version-restricted, replace-not-test).
18. **Override-artifact retention is intentional** (per gdpr-gate `GDPR-Retention-1`). `knowledge-base/security/skill-overrides/` artifacts are retained for the repository lifetime as Art. 32 evidence. Future operators must NOT bulk-delete them. Document the retention policy in `references/override-mechanism.md` with explicit lawful basis citation.
19. **osv.dev is a Chapter V cross-border vendor** (per gdpr-gate `GDPR-ChapterV-1`). Add a Vendor DPAs row to `compliance-posture.md` in Phase 11 alongside the Active Items append. Package metadata only (name, ecosystem, version) — never operator-identifying data — is sent to osv.dev.
20. **Sentry mirrors of scanner errors must redact** (per gdpr-gate `GDPR-Art32-1` + AGENTS.md `cq-silent-fallback-must-mirror-to-sentry`). Use the existing `reportSilentFallback(err, { feature: 'skill-security-scan', extra: { ...redacted } })` shim from `2026-04-28-sentry-payload-pii-and-client-observability-shim.md`. Test redaction by simulating a Sentry event from a fixture containing `author@example.com` and asserting the payload has no literal email.
21. **Agent prose alone cannot enforce a security gate** (Kieran P0-1). agent-finder.md is read by an LLM that may be persuaded to skip the scan call by an attacker-authored prompt-injection in the very fixture being scanned. The load-bearing layer is the PreToolUse hook on Write. Cooperative agent prose is the operator-friendly fast-path only. Treat any future "let the agent decide" framing as a category error.
22. **Override = artifact alone, no git trailer** (per plan-review HIGH-confidence cut). Detect via `git diff --name-only --diff-filter=A | grep '^knowledge-base/security/skill-overrides/'`. No squash-merge invariant to document; no commit-message parsing. Single mechanism keeps the audit-trail simple.
23. **First-party allowlist matches URL host segment after parsing, not raw substring** (R14). Adversarial `https://attacker.com/redirect?ref=soleur.ai` MUST trip detection (host = `attacker.com`, not in allowlist). Use a real URL parser, not `grep -F "soleur.ai"`.
24. **`run-self-test.sh` SHA recompute order** (SpecFlow Gap 4): rule-pack edits + manifest re-sign go in the SAME commit. Dev workflow uses `--regenerate-manifest` flag locally; CI strict-mode rejects the flag (env `CI=true`).
25. **`parse-override.sh` slug regex `^[a-z][a-z0-9-]*$`** (SpecFlow Gap 12 + Kieran P1 #6). Skill slugs that contain regex meta-chars or capital letters are rejected. Prevents bash interpolation hazards in the override-artifact filename match.
26. **Branch protection on `main` requires `skill-security-scan-pr-trailer` status check** (R15). Verified via `gh api repos/jikig-ai/soleur/branches/main/protection`. Bypassing requires explicit admin action that auto-files a `compliance/critical` issue post-merge.

## Alternative Approaches Considered

| Approach | Why rejected | Reference |
|---|---|---|
| Inline scanner script under `plugins/soleur/skills/skill-creator/scripts/` (no dedicated skill) | Discoverability via `/soleur:help` and `find-skills` requires a skill name; script-under-skill-creator forks into divergent copies as `agent-finder` adds its own copy | Brainstorm Decision 8 |
| LLM second-pass detection at install-time | Adds 3-8s latency + nondeterminism; both fatal at install-time gates. Reserved for future opt-in `/scan-on-demand` deep-mode | Brainstorm Decision 7, CTO assessment |
| Snyk free tier as supply-chain source | Commercial-CI ToS no-go (CLO); rate-limit + auth-blocked (CTO) | Brainstorm Decision 6, CLO assessment |
| Conventional verdict naming (the standard 3-state set) | "PASS" is a representation a regulator/plaintiff can lean on; false-negative ships a warranty | Brainstorm Decision 1, CLO assessment |
| Vendor-attribution as separate FR3 sibling issue | Operator chose unified ship; brand-survival framing makes this a category-creation moat | Brainstorm Decision 2 |
| Per-skill `test/*.test.sh` directory mirroring imagined gdpr-gate convention | gdpr-gate has no `test/` dir; bun test under `plugins/soleur/test/` is dominant | Research Reconciliation row 3 |
| Parent-process detection for /plan-mode | Fragile across shell wrappers (`xargs`, `bun run`, GH Actions runners); explicit env flag is robust | Phase 6 |
| Wholesale port of alirezarezvani/claude-skills/engineering/skill-security-auditor | Off-strategy (CPO), dilutes positioning (CMO), blows token budget (CTO); pattern-extract instead | Parent brainstorm Decision 1 |

## Out-of-scope deferrals (tracking issues to file)

The following are explicitly out of scope for #2719 and will be filed as follow-up issues during plan execution per Step 6 deferral-tracking check:

1. **LLM second-pass deep-mode for opt-in `/scan-on-demand`** — Future enhancement when LLM cost / latency drops or when a separate post-install audit surface emerges. Re-evaluation: when Soleur ships a skill-update workflow that re-scans installed skills.
2. **Runtime sandbox for installed skills** — Orthogonal capability (this is install-time static analysis; sandbox is runtime). Re-evaluation: when first credential-exposure-class incident occurs OR when container-isolation work (Phase 4 row 4.6) is in flight.
3. **Cross-skill dependency graph analysis (skill-of-skills risk)** — A skill that internally calls another community skill compounds risk. Re-evaluation: when first composite-skill case appears in `agent-finder` discovery.
4. **SARIF output format support** — Industry-standard format for security scanner output; useful for CI integration with third-party platforms. Re-evaluation: when we ship a CI surface that consumes scan results outside Soleur (e.g., GitHub Code Scanning).
5. **Telemetry/SIEM integration for scan-result aggregation** — Aggregate verdicts across all skills + all repos for trend analysis. Re-evaluation: when we ship Soleur Cloud (web platform) and have multi-tenant operators.
6. **Soleur Cloud (web platform) UX surfaces for scan results** — This plan covers CLI/local-repo gate only. Web surfaces deferred to Phase 4.x cloud workstream.
7. **`/soleur:scan-on-demand` skill for manual rescans of already-installed skills** — Spec FR5 says scan-on-demand is via explicit `Skill: skill-security-scan` invocation; a dedicated convenience skill is deferred until usage patterns emerge.
8. **`.github/workflows/skill-security-scan-postmerge.yml`** to validate trailer+artifact on push to main — included in Phase 10. If implementation reveals this is too complex to ship in the same PR, defer to follow-up issue with rationale.

For each deferred item, file a GitHub issue per `wg-when-deferring-a-capability-create-a` with milestone `Post-MVP / Later` (or appropriate phase if a more specific re-evaluation trigger applies).
