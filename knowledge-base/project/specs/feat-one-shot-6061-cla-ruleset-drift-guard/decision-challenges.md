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

## DC-3 — Live CLA ruleset is MISSING `cla-evidence` (pre-existing drift the audit correctly flags on first run) — OPERATOR ACTION

**Discovered at review time** via a live probe (`gh api repos/jikig-ai/soleur/rulesets/13304872`),
per `hr-no-dashboard-eyeball-pull-data-yourself`. The live CLA Required ruleset
currently requires **only `cla-check`** — `cla-evidence` is NOT a required status
check on it. But `cla-evidence` was deliberately added to the SSOT
(`scripts/create-cla-required-ruleset.sh` + `scripts/required-checks.txt`) by PR
#3201 (the WORM-timestamped evidence layer), and `.github/workflows/cla-evidence.yml`
is an active workflow that posts a `cla-evidence` Check Run. So the **live ruleset
has drifted from the SSOT** — a pre-existing infra gap, NOT introduced by this PR.
(The unrelated todo-027 `Integration:262318` unknown-bypass-actor is already
resolved: live now shows `Integration:1236702`, matching the canonical.)

**Consequence for this PR (by design, not a bug):** the canonical correctly mirrors
the SSOT (both contexts), enforced by `T-cla-1`. So the audit's **first run will
file a TRUE-POSITIVE** `required_status_checks dropped a gate` critical drift issue
for the missing `cla-evidence`. This contradicts the plan's original post-merge AC
("first run green, no false-positive") — that AC's premise (live == SSOT) was
wrong. This is the feature working: the audit caught a real drift on day one.

**Deliberately NOT done in this PR:**
- Did NOT mutate the SSOT to match live (removing `cla-evidence` would reverse
  #3201's deliberate decision and break `T-cla-1`/`Test 7`).
- Did NOT run `create-cla-required-ruleset.sh` against production to add
  `cla-evidence` to the live ruleset — that is a production branch-protection
  write that could **block all merges** if `cla-evidence` is not reliably posted
  on every PR, and is an operator/CTO call, not a drift-guard PR side effect.

**Recommended operator action (default):** either (a) reconcile live by applying
`scripts/create-cla-required-ruleset.sh` **after** confirming `cla-evidence` posts
reliably on real PRs (closes the IP-provenance gap the evidence layer was built
for), OR (b) accept the audit's first-run drift issue as the tracking signal and
reconcile when convenient. Both are legitimate; the audit keeps flagging until
live == SSOT.
