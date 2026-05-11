---
module: gdpr-gate / vendor-drift workflow
date: 2026-05-11
problem_type: integration_issue
component: ci_workflow
symptoms:
  - "Inline Python regex with non-greedy `+?` silently no-ops every NOTICE SHA bump"
  - "Classifier exit-code priority under-labels co-occurring security + license drift"
  - "Cron auto-PR opens against attacker-controlled upstream bytes before human review"
  - "NOTICE co-edit bypasses self-consistency integrity check (working-tree hash + frontmatter SHA can be updated together)"
root_cause: trust_model_gaps_in_vendored_content_pipeline
severity: critical
tags: [vendor-pinning, supply-chain, classifier, regex, gdpr-gate, multi-agent-review, single-user-incident]
synced_to: [review]
---

# Multi-Agent Review Catches Vendor-Pipeline Trust-Model Gaps (PR #3521)

## Problem

PR #3521 introduced a content-vendoring pin policy + scheduled drift workflow for the gdpr-gate skill. The PR passed unit tests (86/86 green) and was structurally coherent. An 11-agent review (8 always-on + test-design + semgrep-sast + user-impact-reviewer) surfaced four classes of defect that none of the existing tests caught.

## The four defects

### 1. Inline-Python silent no-op (data-integrity)

The drift workflow's NOTICE bump step ran Python via heredoc:

```python
pattern = re.compile(
    r'(- path: ' + re.escape(rel) + r'\n(?:    .+\n)+?)',
    re.MULTILINE,
)
# two re.sub calls on local-blob-sha and upstream-blob-sha against m.group(1)
```

`+?` (non-greedy) captured only the first indented line (`upstream-path:`). Both subsequent `re.sub` calls ran against a block that did not contain their targets — silent no-op. Every weekly auto-PR would have shipped with stale `*-blob-sha` values, then failed the lefthook integrity gate for any subsequent human commit to those files. The bug only manifests on the second run; unit tests asserted structure of the YAML, not the runtime result of the Python block.

**Fix:** greedy `+` plus a post-condition `subn` count check that fails the workflow loudly if either substitution misses.

### 2. Classifier under-labeling (multi-category contract)

`vendor-drift-classify.sh` used first-match-wins priority over a single exit code: rollback > archived > renamed > license > security > batched. Co-occurring Art. 9 add + LICENSE edit in one upstream commit routed to `vendor/license-changed,compliance/critical` — silently dropping the `security` signal. The exit-code-as-result contract was the implicit cause.

**Fix:** classifier now emits `category=<name>` on stdout for **every** match (multi-category contract). Exit code retains priority for routing (auto-PR vs issue). Workflow consumer accumulates labels across all emitted categories via a bash associative-array dedupe.

### 3. Auto-PR-of-untrusted-upstream-bytes (security)

The workflow ran `git merge-file --diff3` on bytes fetched from `gh api .../git/blobs/<sha>` and opened a bot-authored PR on **every** drift class, including security/license/rollback/archived/renamed. A compromised upstream (or a poisoned commit, no signed-commit gate) could land attacker-controlled bytes into the gdpr-gate's regulated-content references in a weekly bot PR, where review fatigue beats vigilance.

**Fix:** classifier `route` output added — exit ∈ {10, 11, 12, 15, 16} routes to **issue-only** (no merge, no auto-PR). Auto-PR remains for exit 13 (batched non-security) where the human re-vendor decision is low-risk.

### 4. NOTICE co-edit bypasses self-consistency check

`vendor-pin-integrity.sh` compared `git hash-object --no-filters <file>` against the NOTICE-declared `local-blob-sha`. A PR can edit both the file AND the frontmatter SHA in one diff — the check is tautological. No CI-side verification confirmed `upstream-blob-sha` against the live upstream repository.

**Fix:** new `.github/workflows/vendor-pin-verify.yml` runs at PR time, calls `vendor-pin-integrity.sh --verify-upstream`, which iterates NOTICE `upstream-blob-sha` values and asserts each is fetchable via `gh api repos/<upstream>/git/blobs/<sha>`. An attacker would need both a matching real upstream blob AND a matching working-tree file — the upstream commit history constrains the first.

## Key insight

**The defects share a pattern: single-source-of-truth contracts that look fine in isolation but compose badly with adjacent contracts.**

- Defect 1: the Python block looked fine in isolation. Composed with the surrounding `paste | while` subshell, the silent no-op + the absence of a post-condition assertion left no visible failure.
- Defect 2: the exit-code-as-result contract looked fine for the single-category case. Composed with co-occurring upstream drift classes (which the spec did consider — see `vendor-drift-classify.sh` priority comment), it under-labels.
- Defect 3: the auto-PR routing looked fine for low-risk classes. Composed with security-relevant classifier exits, it converted a detection signal into a write primitive.
- Defect 4: the integrity check looked fine for the typical case (one side moves). Composed with adversary-aware editing (both sides move together), it's tautological.

Multi-agent review with **distinct reviewer mandates** caught these where a uniform code review would not have. `user-impact-reviewer` named the attacker model. `data-integrity-guardian` ran the Python regex against the real NOTICE and produced the falsifying input. `security-sentinel` traced the supply-chain path. `pattern-recognition-specialist` flagged the brittle awk tokenization (which had the same composition smell — `tok[1] == path_key ":"` works only because YAML happens to not insert a space before colons).

## Reviewer takeaway

When a PR establishes a new trust contract (vendored content, pinned blob SHAs, integrity-gated registry, classifier output → label set):

1. Name the adversary model in the plan's `## User-Brand Impact` block. If `brand_survival_threshold: single-user incident` is declared, `user-impact-reviewer` will enumerate concrete artifact + vector pairs — read those, do not let the plan's mitigation column hand-wave them.
2. Ask each integrity check: "what other thing must move to bypass this?" A check that the PR author can update in the same diff is tautological.
3. For every classifier / categorizer, ask: "what does the multi-class case do?" Exit-code-as-result hides this.
4. Pin-time-of-fetch vs verify-time-of-execution is the canonical runtime-content-tamper class (see `2026-05-03-user-impact-reviewer-catches-runtime-content-tamper-vectors.md`).

## Inline fixes landed on PR #3521

- `data-integrity P1` regex no-op (greedy match + `subn` count assertion)
- `pattern P1` awk `key : value` (space-before-colon) tokenization brittleness
- `pattern P1` duplicate-PR guard (idempotent on existing open `ci/vendor-drift-*`)
- `pattern P1` NOTICE markdown table → frontmatter SHA drift (covered by broader lefthook glob + integrity script reading from NOTICE at runtime)
- `pattern P2` LICENSE regex basename anchor (no false-positive on `LICENSE-DISCUSSION.md` etc.)
- `pattern P2` `Apply labels to drift PR` scoped by exact branch instead of highest-number prefix-search
- `data-integrity P2` `last-verified` strict-ISO regex + UTC anchor on `date -u -d` (closes natural-language `date -d "now"` bypass; closes UTC+N TZ off-by-one)
- `architecture P1` lefthook glob broadened from per-file list to `references/*.md` + `references/layers/*.md` (catches new-file additions via the integrity script's "not in NOTICE" branch)
- `security P1-1 + user-impact #3` auto-PR routing restricted to classifier exit 13; exit ∈ {10,11,12,15,16} → issue-only
- `user-impact #3` classifier emits multi-category stdout; workflow accumulates labels via bash associative-array dedupe
- `security P1-2` new PR-time CI workflow `.github/workflows/vendor-pin-verify.yml` calls `--verify-upstream` to assert NOTICE upstream-blob-sha values fetch from upstream
- `user-impact #7` new `/ship` Phase 5.5 gate auto-applies `compliance/critical` label when PR touches `plugins/soleur/skills/gdpr-gate/**` or plan declares `single-user incident` threshold

## Filed as scope-out (cross-cutting-refactor, co-signed)

- #3535 — bind NOTICE `last-verified` to last successful `scheduled-content-vendor-drift` workflow run (current strict-ISO + UTC anchor closes malformed-date class; back-date-to-today class remains)
- #3536 — persistent CI self-test for gdpr-gate scripts against a deliberately-stale fixture NOTICE (current PR closes the primary auto-PR-of-untrusted-bytes vector; this defends against future PRs editing both the gate script and its test in lockstep)

## Session Errors

- **TS11 p95 timing budget exceeded (50ms → 55-80ms range) after adding strict-ISO regex + UTC-anchor on `date -u -d`** — Recovery: widened TR2 from <50ms to <100ms across `notice-frontmatter.test.sh`, spec.md, plan.md with the rationale documented inline. **Prevention:** when adding security-critical validation to an advisory-path script, expect 5-15ms per additional `date(1)` or regex call and budget timing tests with ≥2× headroom to avoid coupling correctness fixes to perf-budget tuning.
- **First scope-out co-sign request bundled 6 findings under one `architectural-pivot` criterion** — Recovery: agent DISSENTed, returned a per-finding decomposition with 2 fix-inline + 4 separable cross-cutting-refactor; applied both inline-required fixes and re-filed remaining 2 (after a second per-finding co-sign cycle that dissented again on #2 and #6). **Prevention:** the co-sign protocol is per-finding by design — bundling under one criterion obscures that PR-introduced P1 gaps in files the PR already edits cannot be deferred regardless of criterion.
- **Edit hook security_reminder_hook fired (advisory) on workflow YAML edits** — Recovery: re-issued edit; hook allowed it through. **Prevention:** none needed — hook is advisory and the edits did not introduce `${{ github.event.* }}` interpolation in `run:` blocks. Future: when adding `gh issue create` to a workflow, default to `--body-file` (the new issue-only path follows this).

## Cross-references

- `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — pattern catalogue this learning extends
- `2026-05-03-user-impact-reviewer-catches-runtime-content-tamper-vectors.md` — runtime-content-tamper pattern (this PR's auto-PR-of-untrusted-bytes is the canonical case)
- `2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md` — handshake schema drift class (this PR's NOTICE table-vs-frontmatter SHA drift is the same shape)
- `best-practices/2026-04-19-verify-reviewer-prescribed-cli-flags-before-applying.md` — co-sign agent dissents are not friction; they're load-bearing
