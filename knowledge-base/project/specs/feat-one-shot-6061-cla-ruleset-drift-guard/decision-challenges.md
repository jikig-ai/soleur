# Decision Challenges — feat-one-shot-6061-cla-ruleset-drift-guard

Recorded during planning (headless one-shot). Surface these to the operator via
the ship PR body + an `action-required` issue.

## DC-1 — Fix step (2) retargeted: bash script → TS Inngest function

**Operator's stated direction (issue #6061):** "extend
`scripts/audit-ruleset-bypass.sh` and `tests/scripts/test-audit-ruleset-bypass.sh`
to audit the CLA Required ruleset live↔canonical so drift pages via the same
daily cron."

**Challenge (session + premise-validation agree):** `scripts/audit-ruleset-bypass.sh`
**no longer pages.** Its workflow (`scheduled-ruleset-bypass-audit.yml`) was
deleted in #4483 (TR9 Phase 2); the daily audit is now the pure-TS Inngest
function `apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts`
(cron `13 6 * * *`), which does not shell out to the bash script. The bash
script's `RULESET_URL` is hardcoded to `14145388` and its only live consumer is
its own test in `test-all.sh`.

**Plan's response:** To meet the stated GOAL ("drift pages via the same daily
cron"), the paging fix targets the **TS Inngest function** (+ its vitest test).
The issue-named `tests/scripts/test-audit-ruleset-bypass.sh` is still used — for
a file-vs-file CLA canonical↔SSOT **sync gate** (co-located with the existing
T-rsc-9 terraform-sync gate) — but NOT for exercising the orphaned bash runtime
(that would test dead code). This honors the goal and both named files while
correcting a stale premise about which code path pages.

**Why not the literal path:** extending only the bash script would satisfy the
letter of step (2) but NOT the goal — CLA drift would still page nothing.

## DC-2 — Scope expanded to a full mirror (bypass_actors), superseding the RSC-only fix-step

**Operator's stated direction (issue #6061 fix-step 1):** mint a canonical with
"context + integration_id per CLA context" — i.e. required_status_checks only.

**Challenge (CLO + CTO independently, converging):** RSC-only leaves the
**stealthiest** CLA defeat vector unguarded — a widened `bypass_actors` entry lets
a named actor merge around the CLA gate while enforcement stays `active` and both
contexts stay required (an eyeball sees a healthy gate). This:
- contradicts the issue **title** ("mirror the CI-Required chain" — CI audits
  bypass_actors + RSC + enforcement);
- is a compliance-material hole for a `domain/legal` guard (CLO);
- is internally inconsistent — `fetchRulesetDetail` hard-requires `bypass_actors`
  (throws if missing), so the CLA path fetches them either way; discarding them to
  defer the comparison is "the worst of both", and minting the CLA bypass canonical
  + reusing `buildFindings` unchanged is *less* code than an RSC-only workaround (CTO).

**Plan's response:** Audit CLA enforcement + bypass_actors + required_status_checks
(a true mirror). Mint TWO CLA canonicals using the CI suffixed convention
(`ci-cla-required-ruleset-canonical-{bypass-actors,required-status-checks}.json`),
superseding the issue's single-file `ci-cla-required-ruleset-canonical.json` name.
Terraform-ifying the CLA ruleset remains deferred (tracked, Phase 6.1).

**Operator override path:** if the operator wants bypass_actors deferred, the plan
must (a) keep a bypass-tolerant CLA fetch honest about token scope and (b) NOT
declare the parity-test gap "resolved" (bypass would remain unguarded).
