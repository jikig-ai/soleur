---
title: hr-rule retirement guard
date: 2026-04-24
status: complete
related_issues: [2871]
related_prs: [2862, 2754]
related_learnings:
  - knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md
---

# hr-rule retirement guard

## What We're Building

A hard-block in `scripts/lint-rule-ids.py` that refuses any `hr-*` id appearing in `scripts/retired-rule-ids.txt`. Retiring a hard-rule becomes a two-step, visible-in-diff operation: edit the linter, then edit the allowlist. The enforcement-script edit is the reviewer's signal that a one-way door is being opened on a security-critical contract.

## Why This Approach

**Threat model (from security-sentinel on PR #2862, CWE-284):** a future PR adds an `hr-<critical>` entry to `retired-rule-ids.txt` with a plausible breadcrumb. Reviewer skims, approves. Retirement is permanent — `cq-rule-ids-are-immutable` + the linter block reintroduction under the same id. Hard-rules at risk include `hr-never-fake-git-author`, `hr-menu-option-ack-not-prod-write-auth`, `hr-all-infrastructure-provisioning-servers`, `hr-ssh-diagnosis-verify-firewall`.

**Why hard-block over the issue's three options:**

- **Option A (CODEOWNERS)** was attractive but adds a governance surface (first-ever CODEOWNERS file, branch-protection coupling, future ownership-policy decisions) for a single-file protection. Overkill for a solo-founder repo.
- **Option B (commit-trailer)** relies on developer discipline — a hostile or careless PR can fabricate `Retires-HR-Rule:` trailers. The guard's strength is only as good as the trailer check, which itself is developer-visible.
- **Option C (signed manifest)** is highest-overhead, no proportional benefit for this threat model.
- **Option D (hard-block)** requires editing the linter — a code change, visible in `git diff`, tests to break, zero-config escape. The linter edit IS the review gate.

**No escape valve.** Retiring a hard-rule should be extraordinarily rare (none so far; 32 days of allowlist operation). When it happens, editing the linter is a ~3-line change that will get proper scrutiny precisely because it's outside the normal rule-lifecycle path. An "allowlist file" would re-introduce the "plausible breadcrumb" attack surface we're closing.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Guard location | `scripts/lint-rule-ids.py` `load_retired_ids()` | Minimal diff; existing script already owns retired-ids logic |
| Scope of block | Any id matching `^hr-` | Section prefix is already canonical per `cq-rule-ids-are-immutable` |
| Escape hatch | None — edit the linter | Maximum PR-diff visibility; rare-by-design |
| Test coverage | Unit test with synthetic retired-ids fixture containing `hr-*` | Regression gate against future refactors that accidentally drop the check |
| AGENTS.md update | `cq-rule-ids-are-immutable` gains one-clause note | Agents discover the block when drafting migrations; points them at pointer-preservation |
| Learning-file update | Append hr-* caveat to 2026-04-21 pointer-preservation learning | Future readers of the migration pattern learn the constraint |
| Retroactive remediation | None needed — no hr-* currently retired | Gate fix IS the remediation per `wg-when-fixing-a-workflow-gates-detection` |

## Non-Goals (Explicit)

- **CODEOWNERS scaffolding.** Defer until a second protection surface justifies a CODEOWNERS file. Close that door in this PR's `Non-Goals` so the next retirement-protection brainstorm doesn't re-litigate.
- **Commit-trailer parsing.** Rejected — weaker than hard-block and requires commit-msg hook wiring.
- **Separate allowlist file.** Rejected — reintroduces the "plausible breadcrumb" attack surface.
- **Extending the block to other prefixes (`wg-`, `cq-`, etc.).** Hard-rules are uniquely load-bearing (security, data integrity, blast radius). Workflow gates and code-quality rules already have lower retirement stakes and are routinely retired via the discoverability-litmus pass (PR #2865). Scope creep deferred.
- **CI-side re-verification.** The pre-commit lefthook runs `lint-rule-ids.py` already; no separate CI job needed. Lefthook is the enforcement point.

## Open Questions

1. **Does `cq-rule-ids-are-immutable` need a `**Why:**` pointing at the security-sentinel finding?** Current rule already references `scripts/retired-rule-ids.txt`. Adding a one-line note about hr-* is ~20 bytes; weigh against the 600-byte per-rule cap. Decide during plan.
2. **Should the error message suggest pointer-preservation as the alternative migration path?** Lean yes — the learning file (#2754) already documents the pattern, and an agent hitting the block benefits from a direct pointer. Decide during plan.

## Domain Assessments

**Assessed:** Engineering (CTO — architectural implications on enforcement layer).

Other domains (Marketing, Operations, Product, Legal, Sales, Finance, Support) have no signal: the feature is internal tooling, zero user surface, zero vendor touch.

### Engineering

**Summary:** Small, self-contained linter extension. Architectural concern is avoiding drift between `load_retired_ids()` and `scripts/rule-prune.sh` (which has its own `_RULE_ID_RE`). Plan must verify both paths and sync if the block changes the parse contract. Risk is low — the block fires after parsing, so regex contract is unaffected. No new hook needed; lefthook already runs `lint-rule-ids.py` pre-commit.
