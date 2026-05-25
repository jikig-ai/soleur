---
date: 2026-05-20
category: security-issues
component: scripts/sweep-followthroughs.sh
problem_type: parser-consumer-invariant-mismatch
issue: 4193
pr: 4200
tags: [shell, awk, parser-consumer, security, defense-in-depth, multi-agent-review]
---

# Learning: parser-side first-wins is not sufficient when the consumer is last-wins

## Problem

PR #4200 closed `scripts/sweep-followthroughs.sh`'s "multi-directive last-wins" gap (Gap 2) by restructuring the awk parser to emit fields only inside the FIRST `<!-- soleur:followthrough -->` directive range, plus a synthetic `__sweeper_meta__ multi_directive_count <N>` warning line.

Multi-agent review (`security-sentinel`) then surfaced a strict-subset bypass the plan's Gap-2 framing missed:

**Within ONE directive line**, the awk for-loop `for (i = 1; i <= NF; i++)` emits one `print "script " $i` line per matching `^script=` token. A body containing:

```html
<!-- soleur:followthrough script=scripts/followthroughs/safe.sh script=scripts/followthroughs/evil.sh earliest=... -->
```

produces two `script ...` lines in the awk output. The bash consumer's `while read -r key val; do case "$key" in script) script="$val"; …` is **last-wins** — `evil.sh` overwrites `safe.sh`. Same bypass class as Gap 2 (last-wins where the docs claim first-wins), but at finer granularity (within-directive instead of across-directives).

Concrete impact: an attacker with `issues:write` who edits any open `follow-through` issue body can re-trigger any committed `scripts/followthroughs/*.sh` (e.g., `sentry-checkins-3859.sh`, which reads `SENTRY_AUTH_TOKEN`) at attacker-chosen cadence and secret allowlist subset.

## Root Cause

Two-layer pipeline (awk parser → bash consumer). The Gap-2 fix hardened ONLY the first layer — the awk parser enforces "emit fields from the first directive only." The second layer (bash `read` loop) was left at the original last-wins assignment shape. The invariant *first-wins* lives implicitly across the layer boundary, and neither layer fully enforces it on its own:

- Awk emits all matching tokens within the first directive (one line per matching field token).
- Bash assigns each emitted line, last-wins.

The plan author thought through multi-DIRECTIVE first-wins (closed correctly with `seen++` + `in_dir` flag) but missed multi-TOKEN within one directive — the awk's NF-loop fires once per matching field, not once per directive.

## Solution

First-wins at the consumer too. One-line bash change per field:

```bash
case "$key" in
  script)   [[ -z "${script:-}" ]]   && script="$val" ;;
  earliest) [[ -z "${earliest:-}" ]] && earliest="$val" ;;
  secrets)  [[ -z "${secrets:-}" ]]  && secrets="$val" ;;
```

Plus a regression test (T5 in `scripts/sweep-followthroughs.test.sh`) with two `script=` tokens in one directive, asserting only the first script is executed.

## Key Insight

**When a parser-side fix enforces an invariant (first-wins, deduplicated, unique-by-key, etc.), the consumer-side semantic MUST mirror it.** Audit every layer the data crosses, not just the parser.

The awk-NF-loop + bash-read-loop is one canonical example; others:

- JSON-array-parser + consumer for-loop that overwrites by key
- `grep --line-buffered` + downstream awk that picks the last match
- `xargs -L1` + a callable that aggregates by mutation rather than accumulation
- regex-extract loop + `Map.set` last-write-wins

The boundary class — "parser emits one line/event per matching token, consumer assigns by reference rather than appending" — is the bypass surface. Multi-agent review reliably catches it when the review prompt names the data flow explicitly. Plan-time review of the parser fix in isolation does not catch it because the bypass lives in the seam between layers.

## Prevention

1. **Plan-time:** when an AC reads "first X wins" / "deduplicated by Y" / "unique-by-key Z," enumerate every layer the parsed output crosses (awk → bash → env_args, JSON parse → for-loop → DB write, etc.) and assert the invariant holds at each transition. Treat the *seam* as a first-class artifact, not just the *parser*.

2. **Review-time:** for any PR whose plan claims a parser-side invariant, the review spawn prompt MUST instruct the agent to *"trace the data flow from raw input through every transformation layer and assert the claimed invariant holds at every consumer boundary."* This wording reliably surfaces seam-class bypasses in multi-layer pipelines.

3. **Test-time:** for any parser/consumer pair, write at least one test that injects N>1 matching tokens of the SAME key per record (e.g., two `script=` in one directive, two `id=` in one query string) and asserts the consumer's deduplication semantic. The single-token case is the happy path and tells you nothing about the dedup logic.

## Cross-References

- Issue #4193 (the hardening PR)
- PR #4200 (this PR)
- PR #4191 (issue #4190 — the rewrite-Phase-7-Step-3.5 PR whose multi-agent review surfaced the original three gaps)
- [Multi-agent review catches bugs tests miss (2026-04-15)](2026-04-15-multi-agent-review-catches-bugs-tests-miss.md)
- [Multi-agent review cross-reconcile catches false-positive HIGH findings (2026-05-12)](2026-05-12-multi-agent-review-cross-reconcile-catches-false-positive-high-findings.md)

## Session Errors

1. **Plan AC4 grep regex `[^,]*` over-captures awk program shape.** The plan's AC4 demanded `diff -u sweeper-awk-start vs ship-awk-start; exit 0` but the capture regex captured trailing ` {` from sweeper's separated-block awk form vs `, /-->/ {` from SKILL.md's range-based awk form, producing a one-line diff that's purely syntactic (both anchor identically at `^<!-- *soleur:followthrough`). **Recovery:** introduced a focused anchor-only regex (`/\^<!-- \*soleur:followthrough/`) for the verification block. **Prevention:** plan-time, prefer extraction patterns that normalize on the load-bearing semantic (the anchor) rather than the full program literal. The canonical load-bearing equivalence check is `plugins/soleur/test/ship-followthrough-directive.test.sh` assertion 5, which actually RUNS both parsers on a fixture and diff-checks output — not a source-regex diff.

2. **Pre-existing pdfjs cold-start flake in `apps/web-platform/test/pdf-text-extract.test.ts`.** `bash scripts/test-all.sh` reported 65/66 suites passed; the 1 failure was an unrelated `pdfjs-dist` lazy-import cold-start timeout (>15000ms). **Recovery:** `git diff --name-only origin/main...HEAD` confirmed zero `apps/web-platform/` files in this PR's diff; continued per `wg-when-tests-fail-and-are-confirmed-pre`. **Prevention:** apps/web-platform vitest config should pre-warm `pdfjs-dist` in a `beforeAll` per the existing work-skill pattern (cold-start `beforeAll` for heavy modules). This is a separate pre-existing issue, not a workflow error in this session.
