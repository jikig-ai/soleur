---
date: 2026-05-14
tags: [multi-agent-review, security, regex-sentinels, push-protection, test-fixtures, skill-budget, plan-review-vs-impl-review, brand-survival-threshold]
severity: medium
category: best-practices
related_pr: 3721
related_issues: [2725, 2718]
brand_survival_threshold: single-user incident
---

# Learning: post-impl multi-agent review catches regex-breadth gaps that plan-review misses; Push Protection vs synthesized fixtures requires defang-from-first-commit

## Problem

`/soleur:incident` (#2725) added a load-bearing redaction sentinel with 9 regex classes spec'd in plan FR3. Plan was reviewed by 5 agents at plan time (DHH + Kieran + code-simplicity + SpecFlow + user-impact-reviewer); reviewers caught direction-reversal of the D1 rename, YAGNI cuts (public-PIR deferred, single COMMIT-PIR token, Ctrl-C abort), and Stripe-regex expansion (`whsec_` added — Kieran P1). All five reviewers approved the regex set at 9 classes.

Post-implementation review with a focused 3-agent slice (pattern-recognition + security-sentinel + code-simplicity) plus mandatory `user-impact-reviewer` (brand-survival-threshold: single-user incident) and `semgrep-sast` (mandatory for source code) **caught 5 P1 missing high-likelihood-for-Soleur-PIRs regex classes** (`ghp_`/`github_pat_`, `sk-ant-`, `sk-`/`sk-proj-`, `sbp_`/`sb_secret_`, PEM `BEGIN ... PRIVATE KEY`), 2 P2 (sed-injection on free-form `title`/`symptom` via template substitution, agent-parity failure on the COMMIT-PIR token due to whitespace canonicalization), and 1 P1 (operator-supplied `symptom`/`suspected_change` echoed to transcript BEFORE Phase 6's draft-sentinel scan in dry-run mode).

Separately: GitHub Push Protection blocked the initial push twice — once on the Stripe `sk_test_FAKE<padding>00000` (realistic-entropy synthesized form) synthesized fixture, then again on the Supabase `sbp_000...` defanged form — forcing a rebase-and-rewrite cycle each time.

## What plan-review caught vs what impl-review caught

The two phases catch **different defect classes**:

| Defect class | Plan-review caught | Impl-review caught | Why |
|---|---|---|---|
| Direction of a mechanical rename | ✓ (Kieran P1 → operator reversed D1 direction) | n/a | Plan-time `git grep` count is the cheapest verification — must run before draft. |
| YAGNI scope cuts | ✓ (DHH + code-simplicity converged on public-PIR deferral, no max-iter, single token) | n/a | Plan-review's bias is "do less"; impl-review's bias is "is what we did sound." |
| Greppable AC fixes | ✓ (Kieran P0 → `--dry-run` mode for AC8-AC13 ungreppability) | n/a | ACs are visible to plan readers as the spec's contract. |
| Inline-emit ordering (sentinel-before-emit) | ✓ (SpecFlow Critical #2) | refined (P1 — operator-supplied fields echoed pre-sentinel in dry-run) | Plan covered draft-emit; impl-review found the input-capture echo gap. |
| Art. 33/34 parity blocking | ✓ (SpecFlow Important #4) | n/a | Compliance contract is plan-level. |
| Regex-set **breadth** | ✗ (5 P1 classes missed) | ✓ (security-sentinel + user-impact-reviewer concur) | Plan reviewers approved the set as-spec'd; only impl-review against a Soleur-stack adversary model surfaced the bare-token shapes (`ghp_`, `sk-ant-`, `sbp_`). |
| sed-injection on free-form prose | ✗ | ✓ (security-sentinel P2) | Plan named FR7 LLM-trust validation for `incident_pr`/`detected_at` numeric/ISO-8601; `title`/`symptom` flowing into `sed -e "s/{{TITLE}}/${title}/"` was implicit. |
| Agent-user parity on operator-input tokens | ✗ | ✓ (user-impact-reviewer P2) | Plan said "literal COMMIT-PIR, case-sensitive" — silent on `\r`/whitespace. |

**Generalizable rule:** plan-review catches **shape** (direction, scope, ordering, contracts); impl-review catches **coverage** (regex breadth, input-validation gaps, parity failures across delivery modes). Both phases are needed. Skipping impl-review on a security-primitive PR because "plan was 5-agent reviewed" loses the breadth axis.

**Cheapest trigger for impl-review breadth gaps:** when the PR introduces a producer-side primitive (regex sentinel, sanitizer, validator, scrubber) whose adversary model is "what does this exclude," spawn `security-sentinel` with an explicit prompt: *"name the absent classes that real-world content for this stack would plausibly include — don't restate what's covered."* Without that framing, the agent echoes the spec's set as approved.

## Push Protection vs synthesized fixtures

`cq-test-fixtures-synthesized-only` mandates synthesized fixtures with no real production credentials. The plan's positive-corpus added entries like `sk_test_FAKE<padding>00000` (realistic-entropy synthesized form). GitHub Push Protection's Stripe detector treats this shape as a real Stripe Test API Secret Key (entropy-shape match, not entropy-content match) and blocks the push. Same outcome for `sbp_<40 zeros>` (Supabase PAT detector — apparently length+prefix only, not entropy).

The defang cycle requires two coordinated changes:

1. **Fixture entries use low-entropy padding** — `sk_test_0000000000000000`, `pk_live_1111111111111111`, `sbp_zzzzzzzzzzzzzzzzzzzzzzzzz`. Repeated chars / non-hex chars stay below the producer's entropy / character-class threshold.
2. **Producer regex must accept the defanged shape too** — Supabase real PATs are `sbp_<40 hex>`. To allow a defanged fixture `sbp_zzzz...` to trigger the regex, the regex must accept any `[a-z0-9]` (not just `[a-f0-9]`) at length ≥ 20 (not ≥ 40). Real PATs still match; defanged fixtures match too. Producer-side broadening is acceptable because the regex is for **detection**, not **validation** — a false-positive on a 20-char `sbp_<random alphanumerics>` string in a real PIR is a redaction (cheap correction) rather than an under-block (load-bearing miss).

This is the same trade-off as the IPv4 `0.0.0.0` / version-string false-positive that pattern-recognition flagged in this PR — broadening the regex catches more real secrets at the cost of more false-positives on prose. For a redaction sentinel where false-positive = "operator iterates to redact" and false-negative = "PII commits to public repo," the asymmetry favors broadening.

## Key insight: synthesized fixtures MUST defang from the first commit

`cq-test-fixtures-synthesized-only` should be extended (or this learning consulted at PR time) to add an explicit rule: **synthesized regex-class fixtures must use low-entropy padding (repeated chars, all-zeros, or non-class chars) so the producer-shape matches without tripping GitHub Push Protection's secret detectors**. Filing a fixture with realistic-entropy values like `FAKESyntheticFixtureDoNotUse00000` triggers a force-push rewrite cycle that wastes ~5 minutes per detected secret per push attempt. The cheaper path is to defang from the first commit.

A pre-push hook running an offline detector (gitleaks, trufflehog, or even a minimal awk script that flags `sk_(live|test)_[A-Za-z0-9]{20,}` with high entropy) would catch this at commit time. This is the same enforcement pattern as the existing skill-security-scan but applied to test fixtures.

## Tertiary insight: skill-description budget hits zero headroom around 70 skills

`plugins/soleur/test/components.test.ts` `SKILL_DESCRIPTION_WORD_BUDGET = 1800` was set when the repo had fewer skills. At 72 skills with descriptions averaging ~25 words, baseline was 1798/1800 — no headroom for ANY new skill. Adding the `incident` skill required either trimming existing descriptions or bumping the budget. The PR bumped to 1850 (+50 words = one skill at average) with a comment referencing this PR.

**Recurring constraint:** every new-skill PR will face this. Two sustainable paths:
1. Per-PR budget bump of ~25 words (one skill's worth) as part of the PR — accepted overhead.
2. Auto-scale the budget to `(skill_count × 30) + 100` headroom — code change but eliminates the per-PR friction.

Path (2) is the right structural answer; path (1) is the right per-PR fix until someone files it.

## Session Errors

1. **GitHub Push Protection blocked `sk_test_FAKE<padding>00000` (realistic-entropy synthesized form)** — Recovery: defanged Stripe entries to `sk_test_0000000000000000` etc. Prevention: synthesized fixtures must use low-entropy padding from first commit (this learning).
2. **GitHub Push Protection blocked `sbp_<40 zeros>`** — Recovery: defanged to `sbp_zzzzzzzzzzzzzzzzzzzzzzzzz` AND broadened producer regex from `[a-f0-9]{40,}` to `[a-z0-9]{20,}` so the defanged form still matches. Prevention: same as above; consider an offline pre-push fixture scan.
3. **Skill description budget exceeded (1798/1800 → 1819/1800)** — Recovery: bumped to 1850 with PR-referencing comment. Prevention: plugin AGENTS.md skill-compliance checklist should note "expect to bump the budget when adding a new skill," OR auto-scale the budget. File follow-up for structural fix.
4. **PEM regex `grep -oE` leading-dash flag-bleed** — `'-----BEGIN ((RSA|EC|OPENSSH|PGP|DSA) )?PRIVATE KEY-----'` was parsed as grep flags. Recovery: `grep -oE -e "${pattern}"` separator. Prevention: when grep patterns are variable-sourced and may start with `-`, always use `-e` or `--` separator. Same class as `gh ... --jq` flag-forwarding bug (separate learning).
5. **Multi-agent review surfaced 5 P1 regex-breadth gaps** the 5-agent plan-review approved — Recovery: extended regex set inline (github_token, anthropic_key, openai_key, supabase_pat, pem_private_key), corpus + tests grew to 19/19. Prevention: when spawning impl-review on a producer-side sentinel/validator/scrubber, the security agent prompt MUST be framed as "name absent classes for this stack" not "audit coverage of the spec's set."

## Cross-references

- Parent feature: #2725 (incident-commander)
- Parent PR (this work): #3721 (D2+D3 bundled)
- D1 prerequisite (merged): #3737 / Closes #3724
- Related learnings:
  - [[2026-05-13-d1-rename-reversed-direction-and-self-referential-skip]] — plan-review caught direction; this learning caught coverage
  - [[2026-04-15-multi-agent-review-catches-bugs-tests-miss]] — the general pattern; this is a stack-specific instance
  - [[2026-05-12-multi-agent-review-catches-load-bearing-redaction-primitive-bypasses]] — closest prior art (same class — load-bearing redaction primitive review)
  - [[2026-04-15-gh-jq-does-not-forward-arg-to-jq]] — same flag-forwarding class as the `grep -oE -e` fix
