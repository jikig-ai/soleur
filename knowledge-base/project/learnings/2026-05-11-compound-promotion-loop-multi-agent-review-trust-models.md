---
title: "Multi-agent review of a self-modifying CI loop — LLM-trust gaps, broken-by-design catches, CONCUR/DISSENT validation"
date: 2026-05-11
type: learning
issue: "#2720"
pr: "#3559"
tags:
  - multi-agent-review
  - llm-trust-boundary
  - agent-native
  - scope-out-gate
  - code-simplicity-reviewer
component: scripts/compound-promote.sh, .github/workflows/scheduled-compound-promote.yml
related:
  - knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md
  - knowledge-base/project/learnings/2026-05-03-user-impact-reviewer-catches-runtime-content-tamper-vectors.md
  - knowledge-base/project/learnings/2026-05-05-agent-native-recommendation-vs-prior-security-removal.md
---

# Multi-agent review of a self-modifying CI loop — LLM-trust gaps, broken-by-design catches, CONCUR/DISSENT validation

## Problem

PR #3559 (Compound Promotion Loop, Layer 2 of the self-healing-workflow design) was implemented through a structured plan→work pipeline that already passed: a 5-agent plan-review panel on the v1 plan, a /soleur:gdpr-gate plan-time scan, and a TDD-driven /work pass with 12 GREEN test assertions. The feature looked done.

The /soleur:review pass with 11 agents in parallel surfaced 25+ additional findings, including 4 P1-class issues the prior gates missed. Each P1 was a distinct *class* of failure that explains why parallel review is load-bearing on features that wrap LLM output with security-critical decisions.

## Solution

The four P1 classes the 11-agent panel caught:

### 1. LLM-trust hash divergence (data-integrity-guardian)

The workflow re-derived `cluster_hash` from `source_learnings` and refused on mismatch — superficially the right pattern. But the LLM was instructed to compute `sha256(sorted(source_learnings))` with **unspecified separator, unspecified trailing newline, unspecified sort locale**. The workflow used `jq -r '.source_learnings | sort | join("\n")' | sha256sum`, which produces a specific shape (trailing `\n` from `jq -r`, locale-dependent sort). An LLM that emits `sha256(sorted.join(""))` produces a different digest. Result: silent 100% rejection rate, indistinguishable from "Anthropic returned no clusters" — undetectable without log-grepping for `cluster-hash mismatch`.

**Fix:** stop trusting the LLM-supplied hash entirely. The workflow now computes the hash itself and uses it for branch naming, audit log, and commit trailer. The LLM-supplied `cluster_hash` field is ignored.

### 2. LLM-trust diff binding (security-sentinel + user-impact-reviewer)

Both agents independently flagged the same root cause from different angles: cluster_hash binds only `source_learnings`, NOT `proposed_diff_unified` or `target_path`. An adversarially-prompted (or jailbroken via PII-regex-evading content in a learning file) Anthropic response can return a valid hash over real source_learnings while supplying a diff that rewrites `.github/workflows/secret-scan.yml` or adds an exfil step to any workflow. Manual confirm was the SOLE barrier.

**Fix:** target_path allowlist (`AGENTS.core.md` + `plugins/soleur/skills/*/SKILL.md` only) + diff-path scan (every `+++ b/<path>` must match the allowlist) + 16k diff-size cap + post-apply byte-budget verification with revert-on-overflow.

### 3. Broken-by-design opt-in (agent-native-reviewer)

This finding was unique to `agent-native-reviewer`. No other agent noticed it. The plan and runbook called `promotion-config.yml` "operator-controlled" and gitignored it — but the cron's `actions/checkout` of `main` never sees gitignored files. `[[ ! -f "$CONFIG" ]]` was always true; the loop was dead-on-arrival. Five other reviewers (security, architecture, performance, pattern-recognition, data-integrity) read the same files and missed it.

The pattern: tracked-vs-gitignored decisions for CI-consumed config files are agent-native-reviewer scope. Security and architecture reviewers default-assume the file exists. **Mitigation for future plans:** any plan with "config file the workflow reads" MUST explicitly answer "is this file tracked?" in the Files-to-create table, AND agent-native-reviewer should be invoked whenever a feature has both (a) a CI-consumed file and (b) operator-facing opt-in semantics.

**Fix:** un-gitignored `promotion-config.yml`; tracked with default `enabled: false`. Opt-in is now a committed flip via PR — reviewer can veto before the cron picks it up.

### 4. Retired-rule extractor matches nothing (data-integrity-guardian)

The plan claimed the loop "respects retired rules" via `scripts/retired-rule-ids.txt`. The implementation extracted path tokens from the breadcrumb column via regex `knowledge-base/project/learnings/[^ ]+\.md`. But `scripts/rule-prune.sh`'s `--propose-retirement` (the **producer** in the only system that auto-writes retirement rows) emits breadcrumbs like `scheduled by rule-prune (first_seen=..., fire_count=0, hook_enforced=...)` — NEVER containing a `knowledge-base/project/learnings/` path. Manual retirement entries point to constitution.md or skill files — also never to `learnings/`. **The extractor's regex matched zero rows in the live file.**

The "no re-promotion of demoted rules" guarantee was silently a no-op. AC-level invariant violated.

**Fix:** broadened regex from `knowledge-base/project/learnings/...` to `knowledge-base/[^ |]+\.md` so any kb path in any breadcrumb format catches.

## Key Insight

**When a feature wraps LLM output with a security-critical decision, the workflow must re-derive every gating value itself OR explicitly bind multiple fields into the trust boundary.** The single-source-hash-of-multiple-fields pattern (where the LLM-supplied hash covers field A but the security decision depends on field B) is a false-confidence trap. data-integrity-guardian and security-sentinel approached this from different angles (algorithm divergence vs binding scope) but caught the same root cause: trust-boundary scope mismatch.

**Tracked-vs-gitignored decisions for CI-consumed config files are agent-native-reviewer scope.** No other reviewer agent reasons about "what does actions/checkout see vs not see" by default. If a feature has (a) a config file the workflow reads AND (b) operator-facing opt-in semantics, agent-native-reviewer is load-bearing — not optional.

**Multi-agent parallel review reliably catches the failure modes single reviewers miss not because the agents are smarter individually, but because their differing default questions enumerate orthogonal vectors.** data-integrity asks "what if the producer changes format?", security asks "what if the input is adversarial?", agent-native asks "can an agent execute this from a fresh clone?". The 5-agent plan-review panel that pre-cleared this PR did not include agent-native or data-integrity — and missed all 4 classes.

## Cost-of-Filing Gate + CONCUR/DISSENT Validation

The /review skill's cost-of-filing gate produced a target outcome of "Filed as scope-out: 0" or 1 — and the actual outcome was 1 issue filed (#3593). On a 25-finding review, 24 went inline. The gate worked correctly under pressure: every finding ≤30 lines was fixed in the same PR.

The CONCUR/DISSENT second-reviewer gate validated its own value in one cycle: on Item 1 (CORPUS_JSON O(n²) build), I attempted to scope-out under `contested-design`. `code-simplicity-reviewer` DISSENTED with two concrete grounds:

1. "performance-oracle didn't recommend a design cycle — it recommended the slurp fix."
2. "The cited rule-prune.sh precedent uses O(n) bash-array accumulation, not the O(n²) jq-rebuild pattern — the 'matches sister-script style' argument is factually wrong."

Both grounds were correct. Without the DISSENT gate I would have filed a scope-out, shipped the bug, and absorbed 600s of cron wall-time at 5000 learnings (above the 15-min workflow timeout). The bash-array precedent in rule-prune.sh is the canonical example of why the gate exists: agents (including the primary reviewer) generalize from similarity that doesn't hold under inspection.

**Pattern for future filings:** when claiming `contested-design`, the second-reviewer must verify that the cited "competing approach" actually exists in repo precedent in the form claimed. A precedent-name without a line-range is a flag for hallucinated similarity.

## Session Errors

1. **Workflow YAML heredoc broke parse** — unindented heredoc `chore(self-healing):` line in `scheduled-compound-promote.yml` `run: |` block terminated the literal block scalar. Recovery: rewrote as `printf '%s\n%s\n...' "$VAR1" "$VAR2"`. **Prevention:** when emitting multi-line strings from inside a YAML `run: |` block, prefer `printf` with explicit `\n` separators over unindented heredocs.

2. **Pre-existing branch test failure** — `plan/SKILL.md` had `` `scripts/X.sh:Y` `` backtick placeholders (added in 437e0267) that tripped `components.test.ts` skill-references regex `\`(references|assets|scripts)/[^\`]+\``. Recovery: switched to `<script-file>:<line>` angle-bracket form. **Prevention:** when writing skill SKILL.md placeholder examples for file-shaped values, use angle-bracket form — never backtick-quoted forms matching the skill-references regex.

3. **CWD lost between Bash calls** — `bash scripts/test-all.sh` exited 127 because the Bash tool's shell state does not persist CWD across calls. **Prevention:** AGENTS.md `cq-test-all-from-worktree-abs-path` (existing) already covers this; always chain `cd <abs-worktree-path> && <cmd>` for any multi-step shell invocation.

4. **Background task truncated output** — TaskOutput on `bash scripts/test-all.sh` returned a partial stdout slice (`exit_code=0` but the suite still had a failing test). **Prevention:** for short tasks (<2min), prefer foreground Bash; reserve `run_in_background: true` for genuinely long jobs where parallel work is possible.

5. **ADR-021 numbering conflict** — plan prescribed `ADR-021-stateless-self-modifying-cron.md` but that number was already taken by `ADR-021-kb-binary-serving-pattern.md` (shipped 2026-04-29). Recovery: renumbered to ADR-027; rewrote 5 plan refs. **Prevention:** any plan that prescribes an ADR number MUST grep `knowledge-base/engineering/architecture/decisions/ADR-*.md` at /work Phase 0 to confirm availability — adopt the next-unassigned number on conflict.

6. **Runbook path divergence from convention** — plan specified `knowledge-base/engineering/runbooks/` (new dir) but the existing convention is `knowledge-base/engineering/ops/runbooks/`. Recovery: relocated runbook + updated 4 references. **Prevention:** plan Phase 1 (and /work Phase 0) should verify every new directory path against existing repo conventions via `find` or `ls -d` before creation — adopt the existing pattern by default.

7. **GitHub API 504 transient** — `gh issue create` returned HTTP 504 on first attempt. Recovery: re-ran the same command. **Prevention:** tolerate transient `gh` API 5xx errors with one automatic retry; escalate to the user only on second failure.

## Tags

```text
category: best-practices
module: review, work, knowledge-management
issue: #2720
pr: #3559
```
