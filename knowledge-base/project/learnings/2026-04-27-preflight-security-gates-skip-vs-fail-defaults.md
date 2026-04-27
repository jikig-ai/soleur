---
category: security-issues
module: preflight, ship-pipeline
date: 2026-04-27
issue: 2887
pr: 2903
tags: [security, preflight, fail-open, fail-closed, dns, doppler, supabase, isolation]
---

# Preflight security gates: SKIP-vs-FAIL defaults and the "I don't know" trap

## Problem

While shipping enforcement scaffolding for #2887 (P0 — dev/prd Doppler configs both
targeted the same Supabase project), the first draft of preflight Check 4
(`Environment Isolation`) had two security-gate fail-open holes that all looked
like reasonable defaults at first read:

1. **A-record-only custom domains returned SKIP.** The check's CNAME-deref
   branch said: "If `dig +short CNAME <host>` returns empty, return SKIP."
   That conflates "this host has no CNAME" (legitimately impossible to compare
   project refs) with "this host uses A-record-based Supabase routing"
   (operator chose a different domain configuration, isolation invariant
   still applies). Returning SKIP silently disabled the entire isolation
   gate for that case — exactly the failure mode #2887 was filed to prevent.

2. **`dig … || true` masked DNS failures as "no record."** Strict-mode
   resilience under `set -euo pipefail` is necessary, but `|| true` swallows
   non-zero exit codes from `dig` — SERVFAIL, network errors, DNSSEC
   validation failures, all become indistinguishable from NXDOMAIN.
   Combined with hole #1, a transient DNS issue → empty output → SKIP →
   gate silently disabled.

Both holes were caught by `security-sentinel` during multi-agent review of
PR #2903, before the security gate ever ran in CI.

## Root Cause

A security gate's three-state result (PASS / FAIL / SKIP) carries an implicit
contract: SKIP means "I cannot determine the answer; don't block on me." That
contract is correct for *informational* checks (e.g., "no migrations to verify
in this PR — SKIP"). It is **wrong** for *invariant* checks where the gate's
job is to refuse merge unless an explicit safety condition holds.

For invariant gates, the choice between SKIP and FAIL on missing data is
load-bearing:

- **SKIP on missing data = fail-open.** The gate disables itself silently.
  Attackers and accidents both benefit; defenders never learn the gate
  didn't run.
- **FAIL on missing data = fail-closed.** The gate refuses to certify
  anything it can't prove. Operators see friction; the invariant is
  preserved.

The first draft of Check 4 used SKIP for "ambiguous DNS state" because the
adjacent informational checks (DB Migration Status, Security Headers) use
SKIP for "no relevant files in PR." The pattern was copied; the semantic
difference was missed.

## Solution

Three changes landed in PR #2903 review pass (commit 76113220):

1. **Single chokepoint regex.** Both branches of project-ref extraction
   (canonical-host fast path, custom-domain CNAME path) MUST converge on
   a hostname matching `^[a-z0-9]{20}\.supabase\.co$` before comparison.
   Step 4.2 step (4) is the load-bearing check, not an optional
   defense-in-depth.

2. **A-record-only → FAIL, not SKIP.** When `dig +short CNAME` returns
   empty, fall back to `dig +short A`. If A-record resolves into Supabase's
   IP range, FAIL with: "Custom domain uses A-record-only Supabase routing.
   Check cannot prove project ref. Configure CNAME-based custom domain or
   set Doppler URL to bare `<ref>.supabase.co` for the isolation check."
   Operator friction is acceptable; silent disablement is not.

3. **rc-aware `dig` invocation.** Capture `dig`'s exit code separately from
   stdout. Branch on rc:
   - `rc == 0` + non-empty output → CNAME target.
   - `rc == 0` + empty output → no CNAME exists (proceed to A-record check).
   - `rc != 0` → DNS failure (return SKIP with diagnostic; this IS the
     legitimate "I don't know" case where SKIP is correct).

   `|| true` is gone; the rc branches make the strict-mode resilience
   explicit and preserve the SERVFAIL-vs-NXDOMAIN distinction.

## Key Insight

For every preflight or pre-deploy gate that enforces a security invariant,
ask **"if this check returns SKIP, would I be comfortable shipping a PR?"**
- If the answer is "yes, because SKIP only fires for not-applicable cases":
  SKIP is correct.
- If the answer is "no, because SKIP could fire when the invariant is
  unprovable but the merge would still violate it": redesign so the gate
  FAILs in that case, with operator friction as the explicit price.

The reflex is to copy SKIP semantics from neighboring checks. The discipline
is to ask, per-check, whether SKIP is "I don't apply" (informational) or
"I can't prove it" (invariant). Only the first is safe.

## Prevention

- **Skill instruction:** preflight/SKILL.md `Check 4: Environment Isolation`
  documents the three-state contract explicitly: SKIP only for genuinely
  inapplicable cases (Doppler unavailable, key unset, DNS rc != 0); FAIL
  for any case where the invariant cannot be proven (A-record-only,
  non-canonical hostname, ref equality).
- **Review-time check:** when reviewing any PR that adds a preflight
  check or pre-deploy gate, grep the new check's result block for SKIP.
  For each SKIP case, audit whether the missing data is "irrelevant"
  (informational gate) or "unprovable" (invariant gate). Reject the
  latter and require FAIL.
- **Cross-reference:** this learning extends
  `2026-03-20-middleware-error-handling-fail-open-vs-closed.md` to the
  pre-merge gate layer. Same dichotomy, different surface.

## Session Errors

This session encountered eight process errors worth tracking:

1. **Plan subagent created spec dir at `feat-fix-supabase-env-vars/`** instead
   of `feat-one-shot-2887-supabase-env-isolation/` (the work skill's exact-
   branch-name convention). Recovery: kept the existing dir, documented the
   divergence in `session-state.md`.
   **Prevention:** plan skill should construct the spec dir name from
   `git branch --show-current` rather than naming-by-content. Issue worth
   filing if recurrence observed.
2. **Initial preflight Check 5 numbering skipped Check 4** — inserted at "5"
   instead of next free integer. Caught by 3 of 4 review agents. Recovery:
   renamed to Check 4, swept references in 4 files.
   **Prevention:** when adding a new step to a numbered sequence, grep the
   target file for the existing maximum number first; never assume.
3. **Initial Check 5 SKIPped on empty CNAME** (security gate fail-open).
   Recovery: changed to FAIL after security-sentinel review.
   **Prevention:** see Key Insight above; route into a skill instruction
   in preflight/SKILL.md.
4. **Initial Check 5 used `dig … || true`** (masked SERVFAIL/network errors).
   Recovery: rc-aware branching after security-sentinel review.
   **Prevention:** AGENTS.md cq-rule already covers strict-mode pitfalls
   (`2026-04-23-hostname-prefix-guard-and-strict-mode-pipefail`); ensure
   plan/work review against that learning before prescribing `|| true`.
5. **ADR-023 had non-standard `## Enforcement` section + operator runbook
   duplicated in Consequences.** Recovery: folded Enforcement into Decision
   and collapsed Operational sequence to plan pointer.
   **Prevention:** when writing an ADR, read the most recent existing ADR
   (in this case ADR-022) before composing; mirror its section structure
   unless intentionally diverging.
6. **PR body was placeholder text** (no operator post-merge checklist visible
   from PR). Caught by code-quality-analyst. Recovery: rewrote body via
   `gh pr edit` with full operator checklist and Ref #2887 linkage.
   **Prevention:** ship skill should require non-placeholder body text
   before transition from draft → ready.
7. **Context7 MCP returned "Monthly quota exceeded" for Supabase library
   query** during plan-time research. Recovery: graceful fallback to
   WebSearch on supabase.com docs. (Forwarded from session-state.md.)
   **Prevention:** none — vendor quota is out of our control; the fallback
   pattern is correct.
8. **Supabase MCP unauthenticated** during plan-time, so project provisioning
   could not be automated via MCP. Recovery: documented operator CLI fallback
   in plan Phase 1.1. (Forwarded from session-state.md.)
   **Prevention:** if Supabase MCP gains support for project-creation
   commands, revisit plan Phase 1.1 to upgrade automation.

## References

- Issue: #2887 (P0 — single-DB blast radius)
- PR: #2903 (enforcement scaffolding ships pre-merge; remediation post-merge)
- Follow-up issues: #2910 (staging Supabase project), #2911 (run-migrations.sh
  `--bootstrap=skip` flag)
- Adjacent learnings:
  - `2026-03-20-middleware-error-handling-fail-open-vs-closed.md` (same
    dichotomy at runtime layer)
  - `2026-04-23-hostname-prefix-guard-and-strict-mode-pipefail.md` (the
    `|| true` strict-mode trap and the canonical-hostname regex pattern)
  - `2026-03-29-doppler-service-token-config-scope-mismatch.md` (token-scope
    rule that scoped tokens but not data — adjacent to the isolation
    invariant)
- ADR: ADR-023 (Supabase Environment Isolation)
- AGENTS.md rules: `hr-dev-prd-distinct-supabase-projects` (new),
  `wg-when-a-pr-includes-database-migrations` (strengthened)
