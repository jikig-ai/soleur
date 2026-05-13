---
title: Multi-agent review catches load-bearing redaction-primitive bypasses that single-pass implementation missed
date: 2026-05-12
category: security-issues
module: soleur-plugin
component: linear-fetch
problem_type: security_issue
severity: high
tags: [multi-agent-review, regex, case-sensitivity, allowlist, redaction, single-user-incident, brand-survival-threshold, linear-fetch]
related_pr: "#3631"
related_issues: ["#3635", "#3643", "#3644", "#3646", "#3647"]
source_session: PR #3631 multi-agent review with 11 agents
---

# Multi-agent review catches load-bearing redaction-primitive bypasses

## Problem

PR #3631 shipped `/soleur:linear-fetch` — a skill that fetches Linear issues and pipes screenshots into the model conversation. The single load-bearing safety rail (brand-survival threshold: `single-user incident` on a public-GitHub repo) is a bash redaction primitive that strips `uploads.linear.app/*` signed URLs from any text persisted to disk.

The redaction primitive was developed with TDD: 22 fixture tests (raw URL, markdown image, HTML img tag with both quote styles, autolink, URL-encoded paths, multi-URL multi-line, zero-URL pass-through, trailing `]` and `)`). All green. The CI grep gate (`pii-grep` job in `pr-quality-guards.yml`) was a second layer. The plan's User-Brand Impact section named "2-layer defense, no shared bypass."

The 11-agent review on the PR found **two confirmed P1 bypasses** that the 22-fixture test suite missed:

1. **Case-sensitive hostname.** The redactor regex was `uploads\.linear\.app` (case-sensitive). DNS is case-insensitive, so `https://Uploads.Linear.App/x.png` resolves to the same CDN host and serves the same signed bearer credential. The CI grep used the same case-sensitive pattern. The 22 fixtures only tested lowercase. Bypass: a Linear comment author writes the URL in mixed case (intentionally or accidentally via OCR/sloppy paste); both defense layers miss it.

2. **Allowlist-token substring abuse.** The CI grep allowlisted any line containing `TEST-FIXTURE-NOT-REAL` (the synthesized fixture token). A Linear user uploading a screenshot with filename `screenshot-TEST-FIXTURE-NOT-REAL.png` produces a real signed URL `https://uploads.linear.app/<uuid>/screenshot-TEST-FIXTURE-NOT-REAL.png?sig=...` that the CI gate allowlists. Layer 2 silently passes the leaked URL.

Additionally, `user-impact-reviewer` (triggered by `brand_survival_threshold: single-user incident` per `plugins/soleur/skills/review/SKILL.md` conditional-agent block) named a **scope-of-redaction gap** that no other agent surfaced: the plan's threat model named "Linear issue images" as the artifact, but the implementation persists the full markdown body (description + comment bodies) verbatim. Customer PII pasted as prose ("my password is X", account numbers, free-text complaints) flows through the persist-safe summary path unredacted. Workspaces using `customer@domain.com` as `displayName` have those identities inlined in the comment delimiter and persisted.

## Investigation

The 11-agent review fanned out across diff inspection (`git-history-analyzer`), pattern conformance (`pattern-recognition-specialist`), architecture (`architecture-strategist`), security (`security-sentinel`), performance (`performance-oracle`), data-integrity (`data-integrity-guardian`), agent-native parity (`agent-native-reviewer`), code quality (`code-quality-analyst`), test design (`test-design-reviewer`), deterministic SAST (`semgrep-sast`), and user-facing-outcome enumeration (`user-impact-reviewer`).

The bypasses were caught by different agents:

- **P1-A (mixed case)** was caught by `security-sentinel`. Verified with a reproduction: `printf 'See https://Uploads.Linear.App/X.png' | bash redact-linear-urls.sh` returned the URL unredacted. The smoking gun was the inconsistency between the redactor (case-sensitive) and the sibling telemetry wrapper `assert-no-linear-telemetry.sh` which DOES use `grep -iE` correctly.
- **P1-A bonus (Unicode separators)** was independently caught by both `security-sentinel` (citing `cq-regex-unicode-separators-escape-only`) and `test-design-reviewer` (noting POSIX `[:space:]` does not cover U+2028/U+2029/NBSP).
- **P1-B (allowlist abuse)** was caught by `security-sentinel`. The reproduction: a Linear-uploaded file named with the fixture token in its name produces a real URL containing the substring.
- **Scope-of-redaction (FINDING 1+2)** was caught EXCLUSIVELY by `user-impact-reviewer`. `security-sentinel` and `data-integrity-guardian` both verified the redaction was *correct as designed* but neither flagged that the design's threat model was narrower than the implementation's persistence surface. Only the agent prompted to "name artifact + name vector" enumerated body text + displayName as artifacts.

The 22 unit-test fixtures were all valid threat models; they just didn't cover the full surface. Adding mixed-case, UPPERCASE, U+2028 follow-up, and NBSP follow-up fixtures grew the suite to 33 assertions (plus 3 hostname-injection negative-space checks).

## Solution

Applied inline on the PR (commits `3ce14434` + `b677cd28`):

### 1. Case-insensitive hostname matching (P1-A)

Replaced the redactor's `https?://uploads\.linear\.app/` with a bracketed case-class hostname:

```bash
LINEAR_CDN_PATTERNS=(
  $'[Hh][Tt][Tt][Pp][Ss]?://[Uu][Pp][Ll][Oo][Aa][Dd][Ss]\\.[Ll][Ii][Nn][Ee][Aa][Rr]\\.[Aa][Pp][Pp]/[A-Za-z0-9._~:/?#@!$&*+,;=%-]+'
)
```

Why bracket-classes instead of a flag: bash `sed -E` does not portably support a case-insensitive flag (`s///gI` is GNU-only; BSD/macOS rejects). The bracket form works identically on bash 5.x (Linux) and bash 3.2 (macOS).

The CI workflow uses `grep -iE` (flag-based) since grep's case-insensitive flag is portable.

### 2. ASCII-only URL path (P1-A bonus)

Replaced the negated character class `[^]<>"'\)\]]+` with a positive RFC-3986-derived class `[A-Za-z0-9._~:/?#@!$&*+,;=%-]+`. The positive class stops at the first non-ASCII byte, so Unicode separators (U+2028 = `\xe2\x80\xa8`, U+2029, NBSP) terminate the match at the leading `\xe2`. Markdown/HTML terminators (`< > " ' ) ]`) are not in the set, so URLs end correctly inside autolinks, attribute quoting, and link-reference shapes.

### 3. Anchored allowlist token (P1-B)

Tightened the CI workflow's allowlist from `grep -vE 'TEST-FIXTURE-NOT-REAL'` to:

```bash
grep -ivE 'https?://uploads\.linear\.app/TEST-FIXTURE-NOT-REAL'
```

The token must appear immediately after the hostname slash. Real Linear paths cannot satisfy this positional constraint — any path containing the token elsewhere (e.g., as filename suffix) fails the allowlist and is correctly flagged.

### 4. Scope-of-redaction explicit scope-out (P1-C)

Added to the plan's `## User-Brand Impact` section an explicit paragraph naming the out-of-scope artifacts (comment body text, `author.displayName`, operator-facing stdout identifier, Anthropic conversation retention). This converts the implicit threat-model narrowing into a documented design decision, so future reviewers and operators see exactly which artifacts are guarded vs. acknowledged-as-risk.

### 5. Cross-artifact parity test

Added `parity.test.sh` asserting the redactor and the CI workflow cover the same `CANONICAL_HOSTS` set (currently `uploads.linear.app`). When the array grows (e.g., a hypothetical `cdn.linear.app`), both files must update or the test fails. The orphan-host check verifies no hostname appears in the workflow that isn't in `CANONICAL_HOSTS`.

## Key Insight

**Multi-agent review reliably finds bypasses that TDD with comprehensive fixtures misses.** The TDD discipline produces tests against the threat models you imagined. The multi-agent review independently enumerates threats from different prompted-perspective lenses (security agent thinks bypass; user-impact agent thinks "what artifacts persist"; architecture agent thinks "what cross-file contracts can drift"). Each lens finds different bugs.

The case-sensitive regex bypass is the canonical example: every fixture I wrote used lowercase URLs because that's what Linear emits and what real markdown contains. I tested every markdown/HTML shape I could imagine. But I never tested "what if an attacker writes the URL in mixed case." The security-sentinel agent, prompted to think adversarially, did. The reproduction was 3 characters of edit and a one-line bash command.

**The user-impact-reviewer agent is load-bearing for the single-user incident threshold class.** The plan's `## User-Brand Impact` section forced "name artifact + name vector" framing, and the review-time conditional-agent block (`requires_cpo_signoff: true` + `Brand-survival threshold: single-user incident`) automatically invoked `user-impact-reviewer`. Without it, the scope-of-redaction gap (body text + displayName) would have shipped — and only surfaced when a real customer's `email@customer.com` displayName landed in a public-GitHub PR body. The agent's mandate to reject generic boilerplate forced the artifact enumeration past "Linear images" into the full persistence surface.

**The plan-time Research Reconciliation was load-bearing for FR9/FR10/TR1.** Three claims in the spec didn't match the codebase: TR1 referenced `canUseTool` in `apps/web-platform/server/agent-runner-query-options.ts` (a different sandbox); FR10 said "Phase 1.1 invocation feeds Phase 0.5 leaders" (impossible — 0.5 fires before 1.1); FR9 prescribed parent-fetch with subagent inheriting images (Task subagents inherit prompt text only). All three would have surfaced mid-implementation if `/work` hadn't done the reconciliation at plan time. The Research Reconciliation table in the plan is now a documented pattern — see `2026-04-15-plan-skill-reconcile-spec-vs-codebase.md` for the general principle.

## Prevention

For load-bearing security primitives (any rail named in a User-Brand Impact section):

1. **Mirror case-sensitivity across all defense layers.** If one layer uses `grep -iE` (security-sentinel, telemetry assertion), every other layer touching the same threat must also be case-insensitive. The asymmetry between the redactor's case-sensitive regex and the telemetry wrapper's `-iE` flag was the smoking gun.

2. **Allowlist tokens must be anchored, not substring-matched.** Any synthesized-fixture allowlist token must appear at a fixed positional slot in the protected pattern that real-world inputs cannot reproduce. Substring-match allowlists are subject to filename-injection attacks.

3. **Add adversarial test fixtures alongside happy-path fixtures.** For every shape the primitive must handle, add a sibling fixture for the case variant, the Unicode-separator-adjacent variant, and the prefix/suffix-injection-attack variant. The 11 P3 fixtures added in `redact-linear-urls.test.sh` extend the suite from 22 → 33 assertions and would have caught all three bypasses at TDD time.

4. **Require multi-agent review for `single-user incident` threshold features.** The brand-survival threshold metadata in plan frontmatter (`brand_survival_threshold: single-user incident`) auto-invokes `user-impact-reviewer` at PR review time. This is now codified in `plugins/soleur/skills/review/SKILL.md` conditional-agent block (lines around the `user-impact-reviewer` invocation). Do NOT manually skip multi-agent review for "small feature" PRs that cross the single-user incident threshold — the review consistently catches bugs the implementer missed.

5. **Add a cross-artifact parity test for any literal replicated across ≥2 enforcement layers.** Three reviewers (pattern-recognition, architecture, data-integrity) independently flagged the regex-replication risk on this PR. The new `parity.test.sh` converts the "update all sites in the same PR" process-convention into a mechanical CI gate. Generalize: when a literal `X` appears in both a code path AND a CI gate (or any defense-in-depth pair), add a meta-test that greps both files and asserts presence. See learning `2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md` and `2026-05-11-multi-agent-review-catches-cross-artifact-contract-drift.md`.

6. **CI grep gates must scope to URL shape, not bare hostname strings.** The initial pii-grep regex was `uploads\.linear\.app` which flagged 63 prose mentions of the pattern in the same PR's own documentation. Tightened to `https?://uploads\.linear\.app/` (URL shape) + `TEST-FIXTURE-NOT-REAL` allowlist. Generalize: content-grep gates protecting against URL leaks must match URL shape (`scheme://host/path`), not just the host string, because docs/comments legitimately mention the host string when explaining the protection.

## Session Errors

**Word-budget grep miscount** — Initial `grep -h 'description:'` quoted 1836/1800 (over cap). Reality: `components.test.ts` parses YAML and counts only the field value (1791/1800 — within cap). Recovery: re-ran with a bun script matching the test's tokenizer. **Prevention:** when measuring against a CI gate, run the gate locally before quoting numbers. The plan's sharp edge on "Plan-quoted numbers are preconditions to verify" applies in reverse here — quote the gate's measurement, not your own approximation.

**Test 4 regression on regex hardening** — Added single quote `'` to the new URL-character class per RFC 3986 sub-delim spec; HTML single-quoted attribute test broke. Recovery: removed `'` from the class. **Prevention:** when widening a regex's accepted character set, grep existing tests for terminator chars and reconcile before the edit. For URL contexts, exclude any character that markdown/HTML uses as a terminator regardless of whether RFC 3986 nominally allows it.

**Parity test hostname extraction too greedy** — First attempt grepped the entire LINEAR_CDN_PATTERNS line including the path character class. Recovery: rewrote with a `case_bracket_pattern` function that builds the case-class pattern from a canonical lowercase host. **Prevention:** for parity tests across files with different on-disk representations, start with canonical form (`uploads.linear.app`) + transform per-file rather than extract-and-normalize from each side independently.

**Bash backslash count mismatch in parity test** — Function generated `\.` (one backslash) via `out+="\\."`; the redactor file on disk has `\\.` (literal two backslashes — bash ANSI-C `$'...'` source representation). `grep -F` failed. Recovery: changed `"\\."` (double-quote interpreted) to `'\\.'` (single-quote literal). **Prevention:** when grep-F-matching against bash ANSI-C `$'...'` source, mirror the on-disk byte representation, not the runtime-parsed form. Single-quote literals are the safe default for "what bytes are in the file."

**persist-safe-integration.test.sh Test 7 wrong assertion** — Asserted telemetry wrapper would reject `$PERSIST_SAFE` because it "contains FEAT-1." Reality: `FEAT-1` was only in the DISCLOSURE variable, never in `$PERSIST_SAFE`. The wrapper correctly returned 0 (no forbidden patterns); my assertion expected 1. Recovery: replaced test with a fake-telemetry payload that genuinely contains an identifier shape. **Prevention:** when writing an assertion about content of a derived value, grep the derivation source first to confirm the asserted content is actually there.

**components.test.ts backtick-file-reference violation** — Used `` [`scripts/assert-no-linear-telemetry.sh`](./scripts/...) `` — the backticks inside the markdown link text matched the no-backtick-refs check at `plugins/soleur/test/components.test.ts:229`. Recovery: removed backticks. **Prevention:** when adding markdown links to `references/`, `scripts/`, or `assets/`, never wrap the link text in backticks; the regex `\`(?:references|assets|scripts)/[^\`]+\`` flags this regardless of surrounding markdown link syntax.

**PII-grep regex too broad on initial commit** — Original `uploads\.linear\.app` flagged 63 doc/prose mentions in the PR's own documentation when re-grepped. Recovery: tightened to `https?://uploads\.linear\.app/` URL-shape regex + swept 7 non-test files to use the `TEST-FIXTURE-NOT-REAL` allowlist token. **Prevention:** before deploying a content-grep CI gate, simulate against your own PR diff via `git diff main...HEAD | grep -E 'your-pattern'` to ensure the regex doesn't catch documentation that legitimately explains the very pattern being protected.

## Cross-References

- `2026-04-15-plan-skill-reconcile-spec-vs-codebase.md` — Research Reconciliation pattern
- `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — class of defect this review fits
- `2026-05-03-user-impact-reviewer-catches-runtime-content-tamper-vectors.md` — user-impact-reviewer's "name artifact + name vector" mandate
- `2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md` — replicated-literal parity testing
- `2026-05-11-multi-agent-review-catches-cross-artifact-contract-drift.md` — cross-file contract enforcement
- `2026-05-12-task-subagent-prompt-text-only.md` — Task subagent contract verification (this PR's load-bearing assumption)
- `cq-regex-unicode-separators-escape-only` (AGENTS.md) — Unicode separator regex coverage rule
- PR #3631 — implementation
- Issue #3635 — feature ask
- Issue #3643 — v1.1 bot-comment-filter deferral
- Issue #3644 — v2 plan+fix-issue extension
- Issue #3646 — v1.1 operational polish (cursor pagination, image-count gate, MCP parallelism, telemetry meta-test enforcement, operator-direct invocation)
- Issue #3647 — Soleur skill description word-budget refactor
