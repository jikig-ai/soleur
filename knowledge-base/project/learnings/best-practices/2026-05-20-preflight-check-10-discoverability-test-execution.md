---
title: Preflight Check 10 — Discoverability Test Execution
date: 2026-05-20
category: best-practices
tags: [preflight, observability, plan-quality-gate, discoverability-test]
issue: 4162
pr: 4164
related: [2026-05-20-hr-observability-as-plan-quality-gate-why-and-how.md, 2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md]
---

# Preflight Check 10 — Discoverability Test Execution

## What

Preflight Check 10 (`plugins/soleur/skills/preflight/SKILL.md` §"Check 10")
EXECUTES the `discoverability_test.command` declared in the plan body's
`## Observability` section. Path-gated on the canonical sensitive-path regex
(SSOT with Check 6 + `deepen-plan` Phase 4.6); FAILs on DNS failure, timeout,
or output mismatch; SKIPs when no sensitive paths touched, no PR available,
no plan link, or the probe is auth-gated without operator creds.

## Why

`hr-observability-as-plan-quality-gate` was static. Plan Phase 2.9 and
`deepen-plan` Phase 4.7 verify the field is **present** and non-placeholder.
Neither runs the command. PR #4148 shipped a plan whose Observability block
declared `curl https://web-platform.soleur.ai/api/inngest` — typo'd hostname
that fails DNS resolution. Five gates passed (plan → deepen-plan → work →
review → ship); the operator caught it live. Fix landed in #4159; the
runbook on `main` carried the wrong hostname until then.

Pattern class: **a fact copied verbatim from an issue body becomes binding
once it lands in a plan, spec, or runbook — even when the fact is a bare
URL that takes 5 ms of `curl` to falsify**. Static gates produce
*declared-verifiable*, which is strictly worse than no declaration because
they generate false confidence.

## How to apply

### Triggers

Check 10 runs when ALL of:

1. `git diff --name-only origin/main...HEAD` contains a path matching
   `SENSITIVE_PATH_RE` (shared with Check 6 + `deepen-plan` Phase 4.6).
2. A PR exists for the branch (`gh pr view --json body` succeeds).
3. The PR body links a `knowledge-base/project/plans/*.md` file.
4. That plan has a `## Observability` section with a parseable
   `discoverability_test.command` (Form A YAML key OR Form B prose + fenced
   block).

### Outcomes

- **PASS** — command ran and stdout matched `expected_output`.
- **FAIL** — missing block, missing command, SSH command, command-substitution
  in command, DNS failure (curl rc=6), timeout (curl rc=28 OR timeout rc=124),
  or output mismatch.
- **SKIP** — no sensitive paths, no PR, no plan link, or auth-gated probe
  without operator creds.

### Form A vs Form B

The canonical schema (`plan-issue-templates.md:60-62`) uses YAML:

```yaml
discoverability_test:
  command: curl -fsS ... https://app.soleur.ai/api/inngest
  expected_output: "200"
```

PR #4148 used a looser prose form:

```markdown
- **discoverability_test.command:**
  ```bash
  curl -fsS ... https://web-platform.soleur.ai/api/inngest
  ```
  Expected output: `200` (or `401`).
```

The parser accepts BOTH. Without dual support, Check 10 would silently SKIP
on every plan written in Form B (which is currently valid). Future
template-harmonization may collapse to one form; until then, dual support
is load-bearing.

### Invariant gate, not advisory

Per `2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`, Check 10
SKIPs only when **truly indeterminate** (no diff, no PR, no plan link,
auth-gated probe). It FAILs when the invariant
("the documented command actually works against the live world") is
**contradicted** — DNS failure, timeout, output mismatch. The asymmetry is
deliberate: an over-eager SKIP would let the next typo'd hostname through.

### Triple-SSOT regex

`SENSITIVE_PATH_RE` lives in three places that MUST stay byte-identical:

1. `plugins/soleur/skills/preflight/SKILL.md` Check 6 Step 6.1
2. `plugins/soleur/skills/preflight/SKILL.md` Check 10 Step 10.1
3. `plugins/soleur/skills/deepen-plan/SKILL.md` Phase 4.6 Step 2

AC2's grep (`grep -cF "SENSITIVE_PATH_RE='^(apps/web-platform"`) asserts
≥2 hits in `preflight/SKILL.md` — substring-based to tolerate the 2-space
indentation difference between top-level (Check 6 + Check 10) and
markdown-bullet (deepen-plan) contexts. Anchoring with `^` would break the
deepen-plan match; keep AC2 un-anchored.

## Cross-references

- `hr-observability-as-plan-quality-gate` (the static parent rule)
- `2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md` (SKIP vs FAIL invariants)
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (regression test)
- `plugins/soleur/test/lib/discoverability-test-parser.ts` (TS reference impl)
- PR #4148 (the plan that surfaced the gap)
- PR #4159 (the hostname fix that landed before this check)
