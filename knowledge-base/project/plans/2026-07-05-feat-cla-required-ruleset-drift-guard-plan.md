---
title: "feat: CLA Required ruleset drift guard — mirror the CI-Required SSOT/audit chain"
issue: 6061
branch: feat-one-shot-6061-cla-ruleset-drift-guard
date: 2026-07-05
lane: cross-domain
brand_survival_threshold: aggregate pattern
status: draft
---

# feat: CLA Required ruleset drift guard 🔐

Closes #6061. Deferred follow-up to the #6049 synthetic-check `CHECK_NAMES` fix
(merged 2026-07-05).

> **No spec.md** exists for this branch; `lane:` defaulted to `cross-domain`
> (TR2 fail-closed). This plan is the SSOT.

## Overview

The GitHub **"CI Required"** ruleset (id `14145388`) is protected by a full
drift-guard chain: canonical JSON mirrors (bypass-actors + required-status-checks),
a daily live↔canonical audit that pages via a compliance issue, and a
synchronous file-vs-file parity test. The **"CLA Required"** ruleset
(id `13304872`) has **none** of this — no canonical JSON, no audit-cron coverage.
A live drift there (a dropped CLA gate, a widened bypass actor, a suspended
enforcement, a 3rd required context added live but never mirrored) is caught by
**no synchronous test and no daily cron**. A human PR could merge without the
CLA-signature / CLA-evidence gate, or bot PRs could silently deadlock.

This plan extends the drift-guard chain to the CLA Required ruleset, **mirroring
the CI-Required chain in full** — the exact framing of the issue title.

### ⚠ Two load-bearing decisions vs. the issue's fix-steps (see Research Reconciliation + decision-challenges.md)

1. **Paging path retarget (DC-1).** The issue says *"extend
   `scripts/audit-ruleset-bypass.sh` … so drift pages via the same daily cron."*
   **That script no longer pages.** Its workflow
   (`.github/workflows/scheduled-ruleset-bypass-audit.yml`) was **deleted in
   #4483 (TR9 Phase 2)** and the audit was reimplemented as the pure-TypeScript
   Inngest function `apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts`
   (cron `13 6 * * *`). The bash script is orphaned — its `RULESET_URL` is
   hardcoded to `14145388`, and its only live consumer is its own test in
   `scripts/test-all.sh` (verified: zero workflow/Inngest invocation). **The
   paging fix therefore targets the TS Inngest function.** The named bash *test*
   file is still used — for a file-vs-file CLA canonical↔SSOT sync gate (where
   the existing T-rsc-9 terraform-sync gate lives) — not for exercising the
   orphaned bash runtime (dead code).

2. **Scope: full mirror incl. `bypass_actors` (DC-2).** The issue's fix-steps
   narrow to *"context + integration_id per CLA context"* (required-status-checks
   only). That contradicts the issue **title** ("mirror the CI-Required chain")
   and leaves the **stealthiest** CLA defeat vector unguarded: a widened
   `bypass_actors` entry lets a named actor merge around the CLA gate while
   enforcement stays `active` and both contexts stay required — an eyeball check
   sees a healthy gate. Both the CLO (compliance-material hole) and CTO
   (`fetchRulesetDetail` fetches bypass_actors either way; discarding them to
   defer the comparison is "the worst of both", and minting the bypass canonical
   is *less* code than an RSC-only workaround) independently required folding it
   in. **This plan audits CLA enforcement + bypass_actors + required_status_checks**
   — a true mirror.

## Research Reconciliation — Issue Body vs. Codebase

| Issue-body claim | Reality (verified) | Plan response |
|---|---|---|
| "daily Inngest cron-ruleset-bypass-audit … hardcodes only the CI-Required ruleset" | ✅ TRUE. `cron-ruleset-bypass-audit.ts` hardcodes `RULESET_NAME = "CI Required"`. Cron `13 6 * * *`. | Extend this TS function to also audit "CLA Required". |
| "extend `scripts/audit-ruleset-bypass.sh` … so drift pages via the same daily cron" | ❌ STALE. Bash script pages nothing — workflow deleted #4483; TS fn does not shell out. `RULESET_URL` hardcoded `14145388`; only its **test** runs. (CTO verified: zero runtime invocation.) | Retarget paging fix to the TS fn. Use the bash *test* file for a file-vs-file CLA sync gate only. (DC-1) |
| CLA canonical = "context + integration_id per CLA context" (RSC-only) | ❌ Under-specifies the issue **title** ("mirror the CI-Required chain"). CLA ruleset has `bypass_actors` (incl. an `Integration:1236702/always` bot). `fetchRulesetDetail` **throws if bypass_actors missing** (`:237-242`) — CLA fetch loads bypass either way. | Mirror in full: mint **both** CLA canonicals (bypass + RSC); audit all three dimensions. (DC-2) |
| Mint `scripts/ci-cla-required-ruleset-canonical.json` (single file) | CI canonical is split `…-bypass-actors.json` + `…-required-status-checks.json`. Full mirror ⇒ two files. | Mint two files using the CI suffixed convention (supersedes the single-file name). (DC-2) |
| CLA canonical values | Live inline in `scripts/create-cla-required-ruleset.sh` (RSC: `cla-check`/`cla-evidence` @ `15368`; bypass: OrgAdmin/pull_request, RepoRole:5/pull_request, Integration:1236702/always). | Mint canonicals == create-script inline values; sync gate locks them. |
| CI canonical SSOT is Terraform (`ruleset-ci-required.tf`), synced by T-rsc-9 | ✅ for CI. **CLA has NO `.tf`** — SSOT is the imperative `create-cla-required-ruleset.sh`. | CLA sync gate asserts canonicals == create-script inline blocks. Terraform-ifying CLA is a deferred, tracked follow-up (Phase 6.1). |
| Parity test `CLA_EXCLUDE` hardcoded `("cla-check" "cla-evidence")` | ✅ `required-checks-canonical-parity.test.sh:59`; comment block (25-36) defers to #6061. | Derive `CLA_EXCLUDE` from the RSC canonical (with a non-empty guard); add SSOT↔canonical parity; rewrite the comment block truthfully. |
| Extending the audit adds a new Inngest function | ❌ We extend the **existing** fn — `function-registry-count.test.ts` + cron-manifest unaffected. | No new registration. |

## User-Brand Impact

**If this lands broken, the user experiences:** the CLA Required ruleset drifts
(a gate is un-required, a bypass actor is widened, or enforcement is suspended)
and **nothing detects it** — a PR merges without the CLA-signature / CLA-evidence
gate, or bot PRs silently deadlock on a phantom required context. The operator (a
non-technical founder) never sees a compliance issue because none is filed.

**If this leaks, the user's legal/IP posture is exposed via:** unsigned external
contributions merged to `main` without a recorded CLA, creating IP-ownership
ambiguity in the codebase the brand ships. The CLA gate is the legal safeguard;
its silent absence is an IP-provenance hole. Bypass-widening is the quietest form
(the gate looks intact while a named actor merges unsigned).

**Brand-survival threshold:** aggregate pattern. Rationale: a *single* missed CLA
is *usually* retroactively remediable (request the signature post-hoc from an
identifiable contributor); a *pattern* of unguarded drift → systematic unsigned
merges is what erodes the IP position into an un-auditable state. The daily
cadence bounds the exposure window. Not `single-user incident` (no code-execution
/ per-user data blast radius like the CI-Required bypass); not `none` (concrete
legal/IP exposure). (CLO-confirmed; "usually" softens the non-remediable-tail
case of an anonymous/adversarial author.)

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)

0.1 Confirm CLA ruleset identity from `scripts/create-cla-required-ruleset.sh`:
name `"CLA Required"`; RSC contexts `cla-check` + `cla-evidence`, both
`integration_id 15368`; bypass_actors `OrganizationAdmin/null/pull_request`,
`RepositoryRole/5/pull_request`, `Integration/1236702/always`. (id `13304872`
cited in `knowledge-base/project/learnings/2026-03-19-content-publisher-cla-ruleset-push-rejection.md`;
the TS audit resolves by **name** — keep name-based resolution.)

0.2 Confirm `cla-check` is produced by `.github/workflows/cla.yml` and
`cla-evidence` by `.github/workflows/cla-evidence.yml` (both exist).

0.3 **Prove the DC-1 premise** (advisor: must be a checked fact, not narrative):
`git grep -n 'audit-ruleset-bypass\.sh' -- .github/workflows apps/web-platform/server`
returns no invocation (only a comment ref in the TS file); confirm
`.github/workflows/scheduled-ruleset-bypass-audit.yml` does not exist and the
cron `13 6 * * *` in `cron-ruleset-bypass-audit.ts` is the daily path. Record the
grep output in the PR body.

### Phase 1 — Mint the CLA canonical JSONs  *(Files to Create)*

Create **two** files, mirroring the CI split (supersedes the single-file name in
the issue — DC-2):

`scripts/ci-cla-required-ruleset-canonical-required-status-checks.json`:
```json
[
  { "context": "cla-check", "integration_id": 15368 },
  { "context": "cla-evidence", "integration_id": 15368 }
]
```

`scripts/ci-cla-required-ruleset-canonical-bypass-actors.json`:
```json
[
  { "actor_id": null, "actor_type": "OrganizationAdmin", "bypass_mode": "pull_request" },
  { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "pull_request" },
  { "actor_id": 1236702, "actor_type": "Integration", "bypass_mode": "always" }
]
```

- Shapes == the CI canonicals; RSC sorted by `context`. Values MUST equal the
  inline blocks in `scripts/create-cla-required-ruleset.sh` (enforced by Phase 4).
- The `Integration:1236702/always` actor is the **CLA bot** — it legitimately
  needs `always` to update CLA status. It is IN the canonical, so the audit flags
  only *additional* bypass actors (widening), never this one.

### Phase 2 — Extend the TS Inngest audit (the paging fix, load-bearing)

**File to edit:** `apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts`

2.1 Add CLA constants: `CLA_RULESET_NAME = "CLA Required"`,
`CANONICAL_CLA_BYPASS_ACTORS_PATH`, `CANONICAL_CLA_REQUIRED_STATUS_CHECKS_PATH`,
`CLA_DRIFT_ISSUE_TITLE = "[Ruleset Audit] CLA Required ruleset drift"`.

2.2 **Reuse `buildFindings` UNCHANGED** (CTO/advisor). It is already
ruleset-agnostic `(detail, canonicalBypassActors, canonicalRequiredChecks)`. By
minting a real CLA bypass canonical, there is **no** empty-canonical trap and
**no** `buildRscFindings` split. Drop the R1/`buildRscFindings` idea entirely.

2.3 Parameterize the per-ruleset audit. Extract
`auditOneRuleset(octokit, { rulesetName, canonicalBypassPath, canonicalRscPath, driftTitle, sourceHint })` →
returns `{ findings, criticalCount }`. It: fetches the ruleset detail by name,
fetches both canonicals, **validates each canonical at read-time** (non-empty
array of the expected shape; on failure emit a `guard-broken` finding — do NOT
treat an empty/corrupt canonical as green — G5.1), then `buildFindings`.
Parameterize `findOpenDriftIssue`/`fileDriftIssue`/`closeDriftIssue`/
`renderIssueBody` by `{ driftTitle, sourceHint }`; the auto-close green-comment
body and `renderIssueBody` prose must be per-ruleset (G1.5 — no hardcoded
"CI Required"/`ruleset-ci-required.tf` in the CLA path; CLA's source hint is
`scripts/create-cla-required-ruleset.sh`).

2.4 **Per-ruleset isolation (G1.1/G1.2):** run the CI audit and the CLA audit in
**separate `step.run` steps** (not one shared `Promise.all`) so a fetch/throw on
one ruleset cannot abort the other, and each memoizes independently on the
`retries: 1` replay. In each step, wrap the fetch in try/catch:
- `fetchRulesetDetail`'s "no required_status_checks rule — gate missing entirely"
  throw is the **most catastrophic drift** (the whole CLA gate is gone) — catch
  it and file a **critical** `required_status_checks` finding (the actionable
  drift issue), NOT an uncaught throw that files nothing (G1.2).
- The "missing bypass_actors" throw → `guard-broken` finding (token scope), same
  as CI.

2.5 Handler aggregation: `ok = (ciCriticalCount + claCriticalCount) === 0`
(re-derive the sum — a leftover CI-only `criticalCount` would silently keep the
heartbeat green on a CLA-only critical — G1.3). Extend the return shape with a
deterministic per-ruleset breakdown (`ci: {...}`, `cla: {...}`; ADR-033 I5).
Sentry heartbeat degrades if **either** ruleset has a critical finding.

**File to edit:** `apps/web-platform/test/server/inngest/cron-ruleset-bypass-audit.test.ts`

2.6 Source-shape anchors (existing `it.each` `SUT_SOURCE.toContain` style):
`"CLA Required"`, both CLA canonical paths, `"[Ruleset Audit] CLA Required ruleset drift"`.

2.7 Pure-function cases (CLA canonicals as inline fixtures):
`compareRequiredStatusChecks` dropped `cla-evidence` → critical `removed`;
`compareBypassActors` a 4th widened actor → `drift: true`;
`buildFindings` with CLA canonicals + `enforcement:"disabled"` → critical
`enforcement`; `buildFindings` green CLA detail → 0 findings.

2.8 **MANDATORY Octokit-mocked handler test** (advisor + CTO + spec-flow
G1.3/G4.1 — promoted from optional). The current file has **zero** handler
behavioral coverage. Add a mock (rulesets list → per-ruleset detail → canonical
`contents` GETs → issues list/create/patch) asserting:
(a) a CLA-only critical drift ⇒ handler returns `ok === false`, files **exactly**
the CLA-titled issue, leaves the CI issue untouched;
(b) CLA green after prior drift ⇒ closes **only** the CLA issue;
(c) an empty/corrupt CLA canonical ⇒ `guard-broken` finding + `ok === false`
(not silently green — G5.1).

### Phase 3 — Rewire the parity test

**File to edit:** `plugins/soleur/test/required-checks-canonical-parity.test.sh`

3.1 Derive `CLA_EXCLUDE` from the RSC canonical, with an explicit jq-exit check
and a **non-empty guard** (G2.1 — `mapfile` under `set -euo pipefail` does NOT
reap a jq failure inside process substitution; an empty derive would silently
make the CI parser exclude nothing and misattribute CLA leakage as CI drift):
```bash
CLA_CANONICAL="$REPO_ROOT/scripts/ci-cla-required-ruleset-canonical-required-status-checks.json"
assert_file_exists "$CLA_CANONICAL" "CLA RSC canonical exists"
CLA_EXCLUDE=()
while IFS= read -r c; do CLA_EXCLUDE+=("$c"); done < <(jq -e -r '.[].context' "$CLA_CANONICAL")
(( ${#CLA_EXCLUDE[@]} >= 2 )) || { echo "FAIL: CLA_EXCLUDE derived < 2 contexts"; exit 1; }
```

3.2 Add **Test 7 — SSOT CLA subset == CLA canonical (⊆ and ⊇, non-vacuous ≥2)**.
Parse the CLA section of `scripts/required-checks.txt`:
- **Exact-anchor** the section start on `^#[[:space:]]*CLA Required ruleset[[:space:]]*$`
  (G2.2 — a loose `CLA Required.*ruleset` match would hit the line-6 header
  comment `#   - "CLA Required" ruleset: cla-check` and slurp the whole CI
  section).
- **Bound the end** on the next `^#[[:space:]]*[A-Za-z].*ruleset[[:space:]]*$`
  header OR EOF (not just EOF — a future section appended after CLA would
  otherwise be slurped).
- Apply the leading-`#`-only comment rule + quote-strip, but **do NOT inherit the
  `CLA_EXCLUDE` filter loop** (G2.3 — the Test-7 parser wants the CLA lines; a
  cloned `parse_ci_required` with the exclude loop passes vacuously).
- Assert the parsed set == CLA canonical contexts (⊆ and ⊇), non-vacuous ≥2.

3.3 Rewrite the comment block (25-36). The "KNOWN GAP (entirely unguarded)" text
is now **false** for all three dimensions — replace it with the resolved state:
CLA now has canonical JSONs (bypass + RSC), daily live↔canonical coverage via the
`cron-ruleset-bypass-audit` Inngest fn (enforcement + bypass_actors + RSC), and
file-vs-file parity here + canonical↔create-script sync gates in
`test-audit-ruleset-bypass.sh`. Note `CLA_EXCLUDE` is now derived. Reference #6061.

### Phase 4 — CLA canonical↔SSOT sync gates

**File to edit:** `tests/scripts/test-audit-ruleset-bypass.sh` (honors the
issue-named file; co-locates with the existing T-rsc-9 terraform-sync gate)

4.1 `t_cla_rsc_canonical_matches_create_script` (T-cla-1): the CLA **RSC**
canonical must equal `create-cla-required-ruleset.sh`'s inline
`required_status_checks` — compare full `(context, integration_id)` **pairs**,
not contexts only (G3.1 — the integration_id is load-bearing; CLA's SSOT is the
create-script, so the id belongs in the gate). Slice the heredoc with the exact
`$payload` sentinel + `<< 'EOF'` delimiter the create-script uses
(`cat > "$payload" << 'EOF'`) — NOT the T-mq-1 `$skeleton` precedent (G3.2) — and
`jq -e .` the sliced payload first (fail `guard-broken` if malformed, per R2).

4.2 `t_cla_bypass_canonical_matches_create_script` (T-cla-1b): same for the CLA
**bypass_actors** canonical vs the create-script's inline `bypass_actors`
(compare `(actor_id, actor_type, bypass_mode)` triples).

4.3 `t_cla_canonical_shape` (T-cla-2): RSC canonical == exactly 2 entries
`{cla-check, cla-evidence}` both `15368`, no dup contexts; bypass canonical == 3
entries with the expected triples. (Mirror T-rsc-7.)

4.4 Register all in the dispatch list under a `# CLA ruleset canonical sync gates (#6061)`
banner. **Do NOT** touch T19 (asserts exactly 3 `$GITHUB_OUTPUT` lines) — the
bash script runtime is unchanged.

### Phase 5 — Docs / metadata

5.1 `apps/web-platform/server/inngest/routine-metadata.ts:81` — update the
`cron-ruleset-bypass-audit` description to name **both** rulesets and both
dimensions (currently "who can bypass … 'CI Required' ruleset"; shipping CLA
without bypass would read as a regression against the fn's own stated purpose —
CTO). E.g. "Daily audit of bypass actors + required checks on the GitHub
'CI Required' and 'CLA Required' rulesets; files a compliance issue on drift."

5.2 `knowledge-base/engineering/operations/runbooks/ruleset-bypass-drift.md` —
add a CLA Required triage subsection. Name the drift classes (dropped
`cla-check`/`cla-evidence`; widened bypass actor; suspended enforcement) AND the
**remedy the `domain/legal` recipient must action**: chase the contributor's CLA
signature post-hoc / revert the unsigned contribution — not just "reconcile the
canonical" (CLO Q4). Reconcile via `create-cla-required-ruleset.sh` + the
canonicals together.

5.3 (Minor) `scripts/required-checks.txt` header comment (~line 5) lists only
`cla-check` for the CLA ruleset; add `cla-evidence`.

### Phase 6 — Deferred follow-ups (file tracking issues as plan tasks)

6.1 **File a tracking issue** (wg-when-deferring — CTO): Terraform-ify the CLA
ruleset (`infra/github/ruleset-cla-required.tf`) to match the CI IaC pattern;
then repoint the Phase 4 sync gate at the `.tf`. Re-eval: next infra-hardening
cycle. Label with an existing label (verify via `gh label list`; e.g.
`domain/engineering`, `chore`).

## Files to Create

- `scripts/ci-cla-required-ruleset-canonical-required-status-checks.json`
- `scripts/ci-cla-required-ruleset-canonical-bypass-actors.json`
- `knowledge-base/project/specs/feat-one-shot-6061-cla-ruleset-drift-guard/decision-challenges.md` (DC-1 + DC-2)

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts` — audit CLA ruleset (paging fix; per-ruleset step isolation; read-time canonical validation).
- `apps/web-platform/test/server/inngest/cron-ruleset-bypass-audit.test.ts` — CLA anchors + pure-fn cases + **mandatory** Octokit handler test.
- `plugins/soleur/test/required-checks-canonical-parity.test.sh` — derive+guard `CLA_EXCLUDE`, add Test 7, rewrite comment block.
- `tests/scripts/test-audit-ruleset-bypass.sh` — T-cla-1/1b/2 sync gates + dispatch.
- `apps/web-platform/server/inngest/routine-metadata.ts` — description update.
- `knowledge-base/engineering/operations/runbooks/ruleset-bypass-drift.md` — CLA triage + remedy.
- `scripts/required-checks.txt` — header comment fix.

## Observability

```yaml
liveness_signal:
  what: cron-ruleset-bypass-audit Inngest fn daily run (audits CI + CLA rulesets, each in its own step.run)
  cadence: daily 06:13 UTC (cron "13 6 * * *")
  alert_target: Sentry cron monitor "scheduled-ruleset-bypass-audit" (heartbeat degrades if EITHER ruleset has a critical finding)
  configured_in: apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts (postSentryHeartbeat)
error_reporting:
  destination: Sentry via reportSilentFallback (issue file/close failures); a filed compliance/critical GitHub issue is the primary operator-facing drift alert
  fail_loud: yes — drift files "[Ruleset Audit] CLA Required ruleset drift" (labels ci/auth-broken, compliance/critical, priority/p1-high, domain/legal); failure to file mirrors to Sentry
failure_modes:
  - mode: CLA required_status_checks dropped (cla-check/cla-evidence un-required, incl. whole RSC rule gone)
    detection: buildFindings removed>0 OR caught "gate missing" throw → critical finding
    alert_route: CLA-titled compliance/critical issue + heartbeat degrade
  - mode: CLA bypass_actors widened (new actor can merge around the CLA gate)
    detection: compareBypassActors drift=true → critical finding
    alert_route: CLA-titled compliance/critical issue + heartbeat degrade
  - mode: CLA enforcement suspended (whole gate off)
    detection: detail.enforcement != "active" → critical finding
    alert_route: CLA-titled compliance/critical issue + heartbeat degrade
  - mode: CLA canonical empty/corrupt on main (would silently read live gates as benign "extra")
    detection: read-time canonical validation in auditOneRuleset → guard-broken finding
    alert_route: heartbeat degrade (ok=false); NOT treated as green
  - mode: audit token lacks administration:read (bypass_actors redacted) — affects BOTH rulesets now (CLA audits bypass)
    detection: caught fetch throw → guard-broken finding
    alert_route: heartbeat degrade
  - mode: CLA canonical stale vs create-cla-required-ruleset.sh
    detection: T-cla-1/1b sync gates (CI, synchronous, block PR)
    alert_route: red CI check
  - mode: SSOT (required-checks.txt) CLA subset diverges from CLA canonical
    detection: Test 7 (CI, synchronous)
    alert_route: red CI check
logs:
  where: Inngest fn logs (logger.info/warn, fn:"cron-ruleset-bypass-audit"); Sentry breadcrumbs
  retention: Inngest + Sentry defaults
discoverability_test:
  command: "gh issue list --label compliance/critical --search '[Ruleset Audit] CLA Required ruleset drift in:title'"
  expected_output: "the auto-filed CLA drift issue when the live CLA ruleset diverges; empty on green"
```

## Architecture Decision (ADR/C4)

**No new ADR required.** This extends an existing, ADR-documented pattern
(ADR-032 GitHub branch-protection-as-IaC; ADR-033 Inngest crons) to a **second
instance** of the same ruleset-audit mechanism. No new ownership/tenancy
boundary, no new substrate, no new trust boundary; the audit already reads GitHub
rulesets via an installation-scoped token and files compliance issues.

**C4 completeness check (all three `.c4` files read/grepped).** External human
actor: the CTO/operator who receives the compliance issue — **already** the
recipient, unchanged. External system: the GitHub API (rulesets + issues) —
**already** used by this and sibling crons; not newly introduced. Data stores:
none touched. Access relationships: none change.
`git grep -niE 'ruleset|branch.protection|cla|drift.guard|github.*audit'` over
`model.c4`/`views.c4`/`spec.c4` returns **zero** — the CI-tooling ruleset-audit
surface is not modeled in the product-level C4 at all, and adding a second
ruleset to an unmodeled audit changes no modeled element/relationship.
**Conclusion: no C4 impact** (checked: CTO actor = pre-existing recipient; GitHub
API = pre-existing external system; no new store; no access-relationship change).

## Infrastructure (IaC)

**Skip — no new infrastructure.** The CLA Required ruleset already exists
(`create-cla-required-ruleset.sh`); the Inngest fn already runs daily. This plan
adds JSON files + extends existing function/test logic against already-provisioned
surfaces. No new server/secret/vendor/persistent process. (CLA being imperatively
managed rather than Terraform-managed is pre-existing; Terraform-ifying it is
deferred + tracked — Phase 6.1.)

## Acceptance Criteria

### Pre-merge (PR, checkable post-conditions)

- [ ] Both CLA canonicals exist and are valid. RSC:
  `jq -e 'length==2 and (map(.context)|sort)==["cla-check","cla-evidence"] and all(.[];.integration_id==15368)'`.
  Bypass: `jq -e 'length==3 and any(.[]; .actor_type=="Integration" and .actor_id==1236702 and .bypass_mode=="always")'`.
- [ ] `bash tests/scripts/test-audit-ruleset-bypass.sh` passes, incl. T-cla-1
  (RSC canonical `(context,integration_id)` pairs == create-script), T-cla-1b
  (bypass canonical triples == create-script), T-cla-2 (shapes); T19 still asserts
  exactly 3 output lines.
- [ ] `bash plugins/soleur/test/required-checks-canonical-parity.test.sh` passes:
  `CLA_EXCLUDE` is jq-derived with a `>=2` non-empty guard (grep confirms no
  hardcoded `CLA_EXCLUDE=("cla-check" "cla-evidence")` remains); Test 7 asserts
  SSOT CLA subset == CLA canonical (⊆ and ⊇, non-vacuous), with an exact-anchored
  section parser.
- [ ] Parity comment block no longer contains "KNOWN GAP (entirely unguarded)";
  describes the resolved 3-dimension state; references #6061.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-ruleset-bypass-audit.test.ts`
  passes, **including** the mandatory Octokit handler test asserting: CLA-only
  critical ⇒ `ok===false` + files exactly the CLA-titled issue + CI issue
  untouched; CLA-green ⇒ closes only the CLA issue; empty CLA canonical ⇒
  guard-broken + `ok===false`.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/function-registry-count.test.ts` passes (no new fn registered).
- [ ] CI and CLA audits run in **separate `step.run` steps** (grep source) so one
  fetch-throw cannot abort the other; the "RSC rule entirely missing" throw is
  caught and converted to a critical finding (not an uncaught throw).
- [ ] `decision-challenges.md` records DC-1 (bash→TS retarget) + DC-2 (bypass scope + filename).
- [ ] DC-2 tracking issue for Phase 6.1 (Terraform-ify CLA) filed with a verified-existing label.
- [ ] Every new `knowledge-base/*.md` citation in this plan resolves.

### Post-merge (operator / automated)

- [ ] Next daily `cron-ruleset-bypass-audit` run (or manual trigger
  `cron/ruleset-bypass-audit.manual-trigger`) completes green against the live CLA
  ruleset (no false-positive CLA drift issue). Automatable via the manual-trigger
  event — bake into `/soleur:ship` post-merge verification, not an operator step.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO). Product/UX: NONE (no
UI-surface file in Files-to-Create/Edit — infra/tooling change).

### Engineering (CTO)

**Status:** reviewed. **Assessment:** Architecture right (extend existing fn, no
new ADR). Retarget bash→TS verified complete (zero residual paging path).
Decisive finding folded in: reuse `buildFindings` + mint the CLA bypass canonical
(*less* code than the `buildRscFindings` split) — resolves the token-scope
inconsistency, closes the stealthiest drift class, and makes the "resolved"
comment truthful. `fetchRulesetDetail` hard-requires bypass_actors → CLA fetches
it anyway. Per-ruleset `step.run` isolation adopted. Terraform-ify deferral valid
but must file the tracking issue. ADR-033 I1/I5 preserved.

### Legal (CLO)

**Status:** reviewed. **Assessment:** `aggregate pattern` threshold correct
(softened "usually retroactively remediable"). Bypass_actors deferral was a
material compliance hole (the quiet defeat vector) — folded into scope. No
Article 30 / DPA / GDPR implication (repository-config metadata only; no personal
data; `bypass_actors` are role/team/App identifiers, not data-subject data).
Issue routing (compliance/critical, domain/legal, priority/p1-high) approved as
the established drift-issue-family convention. Runbook must name the
contributor-signature-chase remedy (Phase 5.2). No legal-doc artifact touched →
no CLO-attestation gate, no specialist delegation.

## Test Scenarios

1. CLA RSC canonical stale vs create-script → T-cla-1 fails (blocks merge).
2. CLA bypass canonical stale vs create-script → T-cla-1b fails.
3. SSOT gains a 3rd `cla-*` not in canonical → Test 7 ⊆-violation.
4. CLA canonical gains a context not in SSOT → Test 7 ⊇-violation.
5. Live CLA drops `cla-evidence` (rule still present) → cron files critical `required_status_checks` finding + `ok=false`.
6. Live CLA RSC **rule entirely removed** → caught throw → critical finding + CLA issue filed (NOT an uncaught throw; CI audit unaffected — separate step).
7. Live CLA bypass widened (4th actor) → cron files critical `bypass_actors` finding + `ok=false`.
8. Live CLA enforcement suspended → critical `enforcement` finding + `ok=false`.
9. Live CLA gains an extra context → non-critical divergence; heartbeat stays ok.
10. CLA green after prior drift → cron auto-closes ONLY the CLA issue; CI issue untouched.
11. Empty/corrupt CLA canonical on main → guard-broken finding + `ok=false` (not silently green).

## Risks & Mitigations

- **R1 — CLA fetch throw aborts the CI audit.** `fetchRulesetDetail` throws on
  missing bypass/RSC. Mitigation: separate `step.run` per ruleset + per-step
  try/catch (Phase 2.4); the "gate missing" throw becomes a filed critical finding.
- **R2 — heredoc parse for T-cla-1/1b is brittle.** Mitigation: pin the exact
  `$payload` sentinel + `<< 'EOF'` delimiter the create-script uses; `jq -e .` the
  slice first (fail guard-broken if malformed); compare full pairs/triples.
- **R3 — empty canonical reads live gates as benign.** Mitigation: read-time
  canonical validation (Phase 2.3, G5.1) → guard-broken, not green.
- **R4 — two same-labelled drift issues share one un-paginated `findOpenDriftIssue`
  query (100-item ceiling).** Pre-existing latent risk this plan doubles.
  Mitigation: title-keyed find/close keeps them independent; note the ceiling in
  the PR body as an accepted pre-existing limitation (a >100 open
  `compliance/critical` backlog is not a current state).
- **R5 — filename convention change.** Using the CI suffixed convention (two
  files) supersedes the issue's single-file name. Recorded in DC-2; all three
  reference sites (TS path constants, parity test, sync gate) use the suffixed names.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no issue whose
body names any file in `## Files to Edit` / `## Files to Create`.

## Sharp Edges

- The bash `audit-ruleset-bypass.sh` is a **decoy** — extending its runtime tests
  dead code (it pages nothing post-#4483). The paging fix is the TS Inngest fn.
- Keep all outbound IO inside `step.run` (ADR-033 I1); CI and CLA in **separate**
  steps for replay isolation. Return deterministic shapes (I5).
- T19 in `test-audit-ruleset-bypass.sh` asserts exactly 3 `$GITHUB_OUTPUT` lines —
  the bash runtime is unchanged, leave it.
- Parse the CLA section of `required-checks.txt` with an EXACT header anchor
  (`^#…CLA Required ruleset$`) bounded by the next `…ruleset$` header or EOF — a
  loose match hits the line-6 comment; use the leading-`#`-only rule (no
  `${var%%#*}` truncation that #6049 fixed) and do NOT inherit the `CLA_EXCLUDE`
  filter (vacuous pass).
- `mapfile`/`while-read` deriving `CLA_EXCLUDE` under `set -euo pipefail` does not
  reap a jq failure in process substitution — add the `>=2` non-empty guard.
- T-cla-1 must compare `(context, integration_id)` pairs (not context-only) — the
  integration_id is load-bearing and CLA's SSOT is the create-script.
