---
title: "Handler-local cron liveness for the MIGRATED_PROMPT cohort"
type: chore
date: 2026-07-28
issue: 6750
lane: cross-domain
adr: ADR-126 amendment (no new ordinal)
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
plan_version: 2
---

# chore(cron): handler-local liveness for the 7 remaining `MIGRATED_PROMPT` crons

Closes #6750.

> Spec lacks valid `lane:` — no `spec.md` exists for this branch, so `lane` defaulted to
> `cross-domain` (TR2 fail-closed).
>
> **v2 after a 6-reviewer panel + a strong-model consult.** v1 shipped a defect of the exact class
> this plan exists to close: it ported **half** the ADR-126 remedy and every one of its ACs would
> have gone green. See §Review Revisions.

## Overview

ADR-126 (2026-07-20) closed the GREEN-with-no-artifact blind spot for **one** cron
(`cron-community-monitor`) and **deliberately declined** to widen to the cohort. The follow-up audit
(`knowledge-base/engineering/audits/2026-07-20-cron-liveness-cohort-audit.md`) measured the cohort
from an independent vantage and shipped a detector — but edited no handler, because widening carries
an accepted negative that must be recorded before it is applied.

This plan applies the widening and records the decision first.

**The ADR-126 remedy has two halves, and both must land.** v1 ported only the first:

1. **Consume `safeCommitAndPr`'s return value** (`livenessOk`) — closes "committed nothing, posted GREEN".
2. **Harden the dedup short-circuit** (`digestCommittedOnDefaultBranch`) — closes "run 1 filed the
   issue but lost its commit; run 2 dedups on that issue and posts GREEN with nothing landed."

The reference implementation says in-line that half 1 is **insufficient alone**
(`cron-community-monitor.ts`, anchor `#6714 Phase 3.4 — the dedup early-return used to post GREEN`):

> *"the exact 2026-07-14 → 07-19 state, and it **SURVIVES the captured-return and `livenessOk` fixes
> below unless closed here**."*

Measured across the cohort today: 7/7 carry `dedup-digest-check`, **0/7** carry
`dedup-digest-committed-check`. And the short-circuit `return`s **before**
`finalizeOutputAwareHeartbeat` (`cron-growth-audit.ts`, anchor `if (digestAlreadyExists) {`), so
neither `livenessOk` nor `retryEligible` is ever consulted on that path.

---

## Research Reconciliation — issue claims vs. codebase

Every row verified against this worktree. **Read the shallow-clone warning first — it invalidated
two reviewers' headline findings and would have invalidated v1's own evidence gate.**

> ### ⚠ This worktree is a SHALLOW clone (`git rev-parse --is-shallow-repository` → `true`, 227 commits).
> `bash scripts/cron-artifact-age.sh --all` reports **`NEVER`/`STALE` for 9 of 9** here — including
> `cron-roadmap-review`, which the audit measured at 13 days and PASS eight days ago. That is a
> **clone artifact, not a production fact**: `last_artifact_epoch()` runs `git log --grep` and cannot
> distinguish "never landed" from "outside the fetched depth", and `classify_age()` treats `NEVER`
> as STALE by construction. `.github/workflows/scheduled-cron-artifact-age.yml` checks out with
> `fetch-depth: 0` and its comment names this hazard verbatim: *"a shallow clone would report every
> producer as NEVER — a detector that is loud for a reason unrelated to the defect is as useless as
> one that is silent."*
>
> **Consequence for this plan:** every Phase 0 command that reads history MUST run after
> `git fetch --unshallow` (Phase 0.1). The audit's numbers stand and are NOT re-derived.

| # | Issue claim | Verified reality | Plan response |
|---|---|---|---|
| R1 | "three suites mock `safeCommitAndPr` with `{ok: true}`… expect fixture-reason REDs" | **STALE — already remediated.** All three spy sites return **union-valid** `SafeCommitResult` today, each carrying a `#6714` comment that a bare `{ok: true}` "was never a member of the union". The residual `{ ok: true }` literals are *handler return-value assertions*, not mocks. | Don't go looking for `{ok:true}` mocks. The predicted REDs still happen — see R2. |
| R2 | *(not in the issue)* | **The real fixture hazard.** `cron-cohort-dedup.test.ts` returns `status: "committed"` with **`paths` omitted and no `resumed`** → ADR-126 decision 3 reads that as NOT DETERMINED → RED, across the 6 cohort handlers that suite drives. Its own comment predicts this verbatim. | Phase 4 reconciles per class. |
| **R3** | "Class A ports only — `cron-growth-audit` and `cron-campaign-calendar`" | **The issue is RIGHT; the audit's table is WRONG.** v1 challenged this and was mistaken. Read from the prompts: `cron-content-generator` has **two explicit early-stops** — *"If no usable topic, create issue … and stop"* and *"If content-writer aborts due to FAIL citations, create issue and stop"* — both file the audit issue (so `heartbeatOk` stays true) and commit **nothing**. That is a legitimate no-diff run → **Class B**. The audit's table and `scripts/cron-artifact-age.sh`'s `class` column both say `A`. | Correct `cron-content-generator` **A → B** in `scripts/cron-artifact-age.sh`. Class A is exactly the two the issue names. DC-2 rewritten. |
| R4 | "4 of 8 handlers have no behavioural harness; `cron-architecture-diagram-sync` has no test file" | **Confirmed, and worse.** `cron-architecture-diagram-sync` is absent from `cron-cohort-dedup.test.ts`'s 7-row `ROWS` table **and** has no per-file suite → **zero executable coverage**, while being the one producer that has never landed an artifact. | Phase 4 adds it as a `ROWS` row — its first behavioural test. |
| R5 | "Do not add handler-side `emitCronPersistResult`" | **Confirmed exactly**: 1 definition, 1 import, **3 call sites**, all in `_cron-safe-commit.ts`, 0 handler sites. | Honoured. **But see R10** — a *different* marker is required. |
| R6 | "All nine inbound `kb` edges are intra-plugin local `File I/O`" | **Imprecise.** 4 declare `technology "File I/O"` (`hooks`, `api`, `skills`, `agents`); 5 are L3 component edges with no `technology`. `api -> kb` and `hooks -> kb` are not intra-plugin. The load-bearing part survives: all nine model a human-initiated in-session read/write. | Edge still missing. Element changes — R7. |
| **R7** | "The correct missing edge is `inngest -> kb`" | **Contradicted, and v1's own answer was also wrong.** `inngest` never opens a git workspace (Go queue/scheduler, dedicated host, ADR-100) — so `inngest -> kb` asserts a nonexistent path. But v1's `webapp -> kb` mixes altitudes: `webapp = system "Web Application"` while **all nine** inbound `kb` edges are container/component level. `webapp -> sentry` earns system altitude because it spans dashboard **and** server configs; the cron→kb path is single-container, server-only. The model's own note points at `api`: *"posted by the code `api` serves (the `api -> inngest "serves functions"` edge)"*. | Add **`api -> kb`** as a second relationship on that pair (duplicate pairs are already legal and present: `hetzner -> zotRegistry` ×2). |
| R8 | *(not in the issue)* | **`cron-growth-audit`'s artifact date is MODEL-computed.** Prompt: *"Compute today's date yourself… use that literal value as `<today>`"*, while `{{RUN_DATE}}` is injected only into the issue title. A date-anchored assertion would false-RED at a UTC-midnight boundary. | **Keep.** Pin the four report paths to `{{RUN_DATE}}`. This is net-**negative** prompt LOC — it deletes a fragile two-sentence instruction plus a containment-hook caveat — and is worth doing with no liveness work at all. |
| ~~R9~~ | *(v1: bump `last_updated` in `campaign-calendar.md`)* | **DELETED.** v1 proposed editing a production prompt to manufacture a diff so an assertion could hold — and that same reasoning *proves* the file is change-conditional, which would have pre-empted v1's own class gate. Unnecessary regardless: prompt STEP 3 **already** mandates an unconditional every-run write to `content-strategy.md`, and `CAMPAIGN_CALENDAR_ALLOWED_PATHS` is exactly those two files. | Class A predicate anchors on **allowlist membership**, not on `campaign-calendar.md`. No prompt change, no weekly churn commit. |
| **R10** | *(not in the issue)* | **The flagship new RED would be undiagnosable.** `status: "committed"` + artifact ∉ `paths` → RED, but `safeCommitAndPr` *succeeded*: no "PR withheld" comment fires, and `emitCronPersistResult` reports `status: "committed"` — which reads healthy. `cron-community-monitor` carries `emitCronDigestLiveness` for exactly this reason. v1's Observability section claimed "the existing three sites already discriminate every hypothesis" — **false**. | Wire `emitCronDigestLiveness` + `emitCronPersistSkipped` into the 7. **This is not the forbidden marker**: R5 forbids `emitCronPersistResult` (which double-emits); these are distinct exported emitters with zero handler sites today. |
| **R11** | *(not in the issue)* | **Lowering `heartbeatOk` silently triggers a GitHub write.** All 7 use `onBeforeHeartbeat: heartbeatOk ? undefined : async () => ensureScheduledAuditIssue(…)`, evaluated **after** `if (!livenessOk) heartbeatOk = false;`. Every liveness-RED run now attempts an issue write, saved from filing a spurious FAILED issue only by title dedup. v1's User-Brand Impact claimed the change "carries only a colour" — **false**. | Named as an accepted consequence in the ADR + asserted in Phase 4 (a liveness-RED run must not create a *second* issue for the same date). |
| **R13** | *(not in the issue)* | **R8 widens a documented contract.** `_cron-shared.ts`'s comment above `injectRunDate` states it *"Pins the issue-TITLE date ONLY — the sole input to the dedup key; secondary agent-derived dates (digest FILE names, publish_date frontmatter, **audit-report paths**) stay agent-derived."* R8 pins exactly the category that comment excludes. Mechanically fine (`replaceAll`; it throws only on a *missing* sentinel), but the comment would ship stale and actively misleading. `cron-content-generator.ts`'s STEP 3 note — *"only the issue TITLE date is pre-filled by the platform"* — also becomes false for the cohort. | Add `_cron-shared.ts` to Files to Edit and update the contract comment to name the growth-audit report paths as a **deliberate, enumerated** exception. Leave `cron-content-generator`'s STEP 3 note correct by scoping the widening to `cron-growth-audit` only. |
| **R12** | *(not in the issue)* | **Class B's gate would be one reachable bit.** `paths === undefined` occurs *only* on the replay-resume branch, which by construction sets `resumed: true` — so that RED cell is unreachable, leaving only `failed → RED`. And the detector cannot cover the gap: `last_artifact_epoch()` matches the **commit message** with **no pathspec**, so a Class B run committing anything under its allowlist resets the age clock with the consumed artifact never written. | Class B's committed arm asserts a **non-vacuous** predicate: `paths.length > 0 && paths.some(p => <ALLOWED_PATHS> prefix)`. Strictly weaker than Class A's, still falsifiable. |

**Premise Validation.** `#6750` OPEN; `#6737` CLOSED; `#4375` OPEN with `action-required` since 2026-05-24. All cited artifacts exist. The ADR corpus was grepped for the *mechanism*: ADR-126 is the only hit and it **defers** rather than rejects — a gap left open, not an alternative rejected.

---

## Review Revisions (v1 → v2)

| # | Finding | Source | Disposition |
|---|---|---|---|
| **V1** | **P0 — v1 ported half the remedy.** The dedup short-circuit posts GREEN and `return`s before `finalizeOutputAwareHeartbeat` in all 7; every v1 AC would have gone green while the dated incident shape stayed live ×7. | architecture-strategist | **Fixed** — new Phase 3.7 + AC6. |
| **V2** | **P0 — the new RED is undiagnosable** (R10). | spec-flow, architecture-strategist | **Fixed** — `emitCronDigestLiveness`/`emitCronPersistSkipped` in Phase 3.8. |
| **V3** | **P0 — v1's Phase 0.6 evidence gate was structurally incapable.** `git log --grep` cannot enumerate the *absence* of commits (a no-changes run leaves none), and in this shallow worktree it returns 0 for every anchor. It would have passed on the empty set. | DHH, CTO, spec-flow | **Replaced** — Phase 0.6 is now a *structural* (prompt-reading) rule, already executed, which decided all three classes. |
| **V4** | Two 509-line harness ports are the wrong unit — `cron-cohort-dedup.test.ts` already has `describe.each(ROWS)` over the cohort with the identical substrate mocks, the frozen clock, and `heartbeatUrls()`. | DHH, code-simplicity, CTO | **Adopted** — extend `Row`/`ROWS`; ~150 lines instead of ~1,018, covering 7 handlers instead of 2. |
| **V5** | R9 edits a production prompt so a test can pass. | code-simplicity | **Adopted** — R9 deleted. |
| **V6** | AC12b's source-text pin is vacuous: `retryEligible: false` appears **twice** in the reference (field + the comment Phase 2 mandates mirroring). Deleting the field keeps the suite green. | architecture-strategist, spec-flow | **Fixed** — pin anchored on the call-site shape. |
| **V7** | AC1/AC2/AC3/AC4 wrong: `git grep -c` prints per-file counts; directory scope catches 9 (`heartbeatOk`) and 12 (`safe-commit-pr`) files; the "unbound" regex also matches the **bound** form. | Kieran-class self-check, CTO, spec-flow | **Fixed** before the panel returned — `$MP` roster scoping + `^\s+` anchor. |
| **V8** | AC12's script reads `$sha:$f` (tree **after**) so a both-in-one-commit change passes the ordering check it exists to reject. | CTO | **Fixed** — `$sha^:$f` + a fourth fixture. |
| **V9** | `webapp` is a **system**; all nine `kb` edges are container-level. | architecture-strategist | **Adopted** — `api -> kb`. |
| **V10** | `MIGRATED_PROMPT` is a literal array; A1's "self-discovering" claim was false, and omission is the dangerous direction. | architecture-strategist | **Fixed** — roster derived from `cronFiles.filter(src => /finalizeOutputAwareHeartbeat\(/)`. |
| **V11** | The class table would be a **4th** roster. `scripts/cron-artifact-age.sh` already carries the canonical `name\|cron_expr\|interval_days\|class\|anchor_regex` table. | CTO | **Adopted** — single-source + a parity test; and R3 corrects its `content-generator` row. |
| **V12** | `DeployInProgressError` mid-spawn fires the exact hazard `retryEligible` exists to close, and v1 pinned it as *correct*. | architecture-strategist | **Recorded as a named residual** in the ADR; scenario 11's framing dropped. |
| **V13** | The detector — Class B's only ceiling — posts **no check-in of its own**, so its silence reads as healthy. | architecture-strategist | **Recorded as a named residual** + a follow-up issue. |
| **V14** | Operator comprehension load: a PR-body line and an ADR paragraph are read-once, at a moment the operator is not in. | CTO | **Adopted** — expected-RED roster into the #4375 comment and `soleur:operator-digest`. |
| **V15** | The runbook (`cloud-scheduled-tasks.md`) goes stale and is the target of the operator-facing comment. | spec-flow | **Adopted** — added to Files to Edit. |
| **V16** | Split the C4 edge into its own PR. | code-simplicity | **Rejected** — Item 4 of the issue, and `wg-architecture-decision-is-a-plan-deliverable` requires the C4 update to ship with the decision. |
| **V17** | Put the decision-challenges in the PR description instead of a committed file. | DHH | **Rejected** — the headless plan/ship contract (ADR-084) requires `decision-challenges.md`; `ship` Phase 6 reads it. |
| **V18** | New ADR-150 → make it an ADR-126 amendment. | DHH | **Adopted** — the issue sanctions either, and it removes the ordinal-collision + renumber-sweep failure mode entirely. |

---

## Proposed Solution

### The class-aware liveness rule

`heartbeatOk` keeps its name and role — `cron-safe-commit-parity.test.ts` pins it as **literal source
text** across all 8 files, so a rename breaks a cohort invariant to fix a colour bug. `livenessOk` is
added **beside** it, initialised **`false`**, set true only by an **observed positive**.

| Class | Producers | committed + artifact ∈ `paths` | committed, `paths` undetermined | committed, artifact ∉ `paths` | `no-changes` | `failed` |
|---|---|---|---|---|---|---|
| **A** (deterministic) | `growth-audit`, `campaign-calendar` | GREEN | GREEN **iff** `resumed` | **RED** | **RED** | **RED** |
| **B** (change-conditional) | `content-generator`, `seo-aeo-audit`, `growth-execution`, `competitive-analysis`, `architecture-diagram-sync` | GREEN | GREEN **iff** `resumed` | GREEN **iff** `paths.length > 0` and some path is under the allowlist (R12) | **GREEN** | **RED** |

**Cell completeness.** Six union cells × 2 classes = 12, all assigned, including `paths: []` (falls to
the artifact-absent column) and `paths` defined + artifact absent + `resumed` (RED for A — `resumed`
licenses only the *undetermined* column, matching the reference at `commitResult.paths === undefined`).

**Paths that do not enter the table**, stated so no reviewer re-derives them:

| Terminal state | Outcome | Assigned |
|---|---|---|
| dedup short-circuit hit | **Was** GREEN-with-no-artifact ×7 — closed by Phase 3.7 | ✅ new |
| `abortedByTimeout` (issue landed) | persistence skipped → `livenessOk` false → RED, marker `persistence-skipped` | ✅ |
| `heartbeatOk === false` | persistence skipped → already RED | ✅ |
| `safeCommitAndPr` **throws** | catch → `threw` → terminal RED | ✅ |
| `DeployInProgressError` mid-spawn | rethrown bare, no heartbeat → Sentry `missed`; **retry still fires and is still useless** | ⚠ **named residual** (V12) |
| throw before the main try (token mint, `setup-workspace`) | retries into a **fresh** workspace — correct, preserved | ✅ verified across 7 |
| Tier-2 defer | early return before the try; `TIER2_DEFERRED_CRONS` asserted empty | ✅ untouched |

### Per-producer artifact predicates

| Producer | Class | Predicate | Why sound |
|---|---|---|---|
| `cron-growth-audit` | A | `paths.some(p => p.startsWith("knowledge-base/marketing/audits/soleur-ai/" + runDate + "-"))` | Prompt Steps 1–4 write four `<RUN_DATE>-*.md` reports unconditionally; Step 3 even says *"If the audit fails, write a stub report and continue"*. Needs R8's date pin. |
| `cron-campaign-calendar` | A | `paths.some(p => CAMPAIGN_CALENDAR_ALLOWED_PATHS.includes(p))` | Prompt STEP 3 writes `content-strategy.md`'s `last_updated` **every run**; the allowlist is exactly two files. No prompt change (R9 deleted). |
| the five Class B | B | `paths.length > 0 && paths.some(p => <ALLOWED_PATHS> prefix)` | Non-vacuous without asserting a specific artifact (R12). |

Predicates import the module's existing `*_ALLOWED_PATHS` consts (exported where needed) so a rename
cannot desync the fixture — the `COMMUNITY_DIGEST_DIR` pattern.

### Ordering: `retryEligible` is a prerequisite

`const failed = threw && !heartbeatOk && retryEligible !== false;` — `!== false` is an identity test,
so omission is byte-identical to today, and **omission is the dangerous direction**. Consuming the
return value lowers `heartbeatOk`; on a run that also throws that yields `{retry: true}` → Inngest
replays and re-spawns the agent against a torn-down workspace.

`retryEligible: false` lands **first**. Because this merges atomically the ordering is a
**construction and reviewability discipline**, not a deployment-safety property — the property that
survives merge is the pair of test pins in A1.

### A1 — the pins that survive merge

1. **Cohort pin**, roster derived from behaviour, not a literal array (V10):
   `cronFiles.filter(f => /finalizeOutputAwareHeartbeat\(/.test(src))` — then assert each carries
   `retryEligible: false` **at the call site**, matching within the
   `finalizeOutputAwareHeartbeat({…})` argument object or after stripping `//` lines (V6).
2. **Behavioural pin** in `cron-shared.test.ts`: both arms of the identity test —
   `retryEligible: false` → `{retry: false}` + exactly one `?status=error`; **omitted** →
   `{retry: true}` + no heartbeat step.
3. **Class-table pin**: parse `scripts/cron-artifact-age.sh`'s `class` column and assert set-equality
   with the handlers' compiled class arms (V11), so a 9th cron cannot drift.

---

## Architecture Decision (ADR/C4)

### ADR — amend ADR-126, no new ordinal (V18)

The issue sanctions *"its OWN ADR (or an ADR-126 amendment)"*. The amendment is chosen: it removes
the provisional-ordinal collision risk and its renumber sweep, and the decision is literally ADR-126's
own deferred clause being discharged.

Append an `## Amendment 2026-07-28 (#6750) — the cohort widening` section recording:

- **The decision**: liveness is gated on the consumed artifact across the cohort, **parameterised by
  producer class**, and the class table is single-sourced in `scripts/cron-artifact-age.sh`.
- **The remedy is two halves** — return-value consumption *and* dedup hardening — with the
  reference's own "SURVIVES … unless closed here" quoted, so a future reader cannot port half again.
- **Accepted negative 1**: a trailing persistence throw on an output-present run posts **RED where it
  was previously GREEN** (#5728), now ×7. Noisier before quieter, deliberately.
- **Accepted negative 2**: a non-final no-output throw posts one terminal RED instead of retrying.
- **Accepted negative 3 (R11)**: every liveness-RED run now attempts a GitHub issue write via
  `onBeforeHeartbeat`. Bounded by title dedup; asserted in Phase 4.
- **Class-assignment evidence** — the *structural* rule and its per-producer quoted instruction,
  including the `cron-content-generator` **A → B** correction (R3) and why the audit's table was wrong.
- **Named residuals, with numbers**: `DeployInProgressError` mid-spawn (V12); a `sentry-heartbeat`
  step throw (outside `retryEligible`'s reach); the detector posts **no check-in of its own** so its
  silence reads as healthy (V13); and the Class B silent windows — **15d** (Class A weekly), **22d**
  (Class B weekly), **46d** (`growth-execution`), **75d** (`competitive-analysis`, the
  `MAX_THRESHOLD_DAYS` cap). A 75-day window under a `single-user incident` threshold is written down.
- **The C4 attribution decision** (below), noting honestly that the cited note's *headline* reason is
  network topology (the Inngest host has no Sentry path) and the attribution sentence is secondary.

### C4 views

All three model files read. **Enumeration** (completeness mandate): no new external human actor; no
new external system (`anthropic`, `github`, `sentry` already modelled with cron-path edges); no new
container or data store; **one** missing access relationship — unattended scheduled server-side
authorship of committed KB content. All nine inbound `kb` edges model a human-initiated in-session
local read/write.

**The edit** — a second `api -> kb` relationship, placed beside the existing one:

```likec4
  // #6750 — the ONLY inbound kb edge that is not an operator-attended session. Attributed to
  // `api` (container), matching the existing container-level `api -> kb` and the model's own
  // note that the Inngest-fired crons run in "the code `api` serves". NOT `inngest`: that host
  // is a Go queue/scheduler (ADR-100) and never opens a git workspace. NOT `webapp`: that is a
  // system, and every other inbound kb edge is container/component level.
  api -> kb "Scheduled UNATTENDED authorship: the 8 Inngest-fired claude-eval crons spawn an agent into an ephemeral server-side workspace and land committed KB content via safeCommitAndPr (branch → PR → auto-merge squash). Liveness of that landing is asserted handler-locally per producer class (ADR-126 amendment #6750)" { technology "Ephemeral git workspace → GitHub push/PR (safeCommitAndPr)" }
```

Note for the ADR (so it is not later filed as a regression): the `containers` view already renders
the existing `api -> kb`, so this adds a **second visual edge** between the same pair. That is the
intended, legal shape — the same as `hetzner -> zotRegistry` ×2 — and it is exactly why the altitude
had to be right: a system-level `webapp -> kb` would have drawn a *different-altitude* parallel edge.

Plus a 2-line annotation above `inngest -> github` marking it and `inngest -> doppler` as the same
mis-attribution (`cron-ghcr-token-minter` is an `api`-served Inngest function), referencing the
amendment. Zero behaviour change; converts a silent inconsistency into an annotated one — without it
the model is strictly *more* inconsistent than before, with the new convention in the minority.

**No `views.c4` edit** — verified: the `containers` view already includes `platform.webapp.api`
(anchor `platform.webapp.dashboard, platform.webapp.api, platform.webapp.auth,`) and
`platform.plugin.kb`. Duplicate source→target pairs are already legal and present
(`hetzner -> zotRegistry` ×2, `hetzner -> betterstack` ×2, `github -> sigstore` ×2).

**`model.likec4.json` MUST be regenerated** (`bash scripts/regenerate-c4-model.sh`) and committed in
the same commit. The freshness gate is an **orphan suite** — only red at the full-suite exit gate or
in CI; the `c4-model-regenerate` lefthook covers it unless the commit uses `LEFTHOOK=0`.

### Sequencing

Nothing deferred. The amendment is written in Phase 1, before any handler edit.

---

## Technical Approach

### Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/server/inngest/functions/cron-growth-audit.ts` | `retryEligible`; bind `commitResult`; **Class A** `livenessOk`; **dedup hardening**; liveness markers; R8 `{{RUN_DATE}}` pin |
| `.../cron-campaign-calendar.ts` | same, **Class A** (allowlist predicate; no prompt change) |
| `.../cron-content-generator.ts` | same, **Class B** (R3 correction) |
| `.../cron-seo-aeo-audit.ts` | same, **Class B** |
| `.../cron-growth-execution.ts` | same, **Class B** |
| `.../cron-competitive-analysis.ts` | same, **Class B** |
| `.../cron-architecture-diagram-sync.ts` | same, **Class B** |
| `apps/web-platform/server/inngest/functions/_cron-shared.ts` | **Contract comment only** (R13): the `injectRunDate` header must name the growth-audit report paths as an enumerated exception to "issue-TITLE date ONLY". No behaviour change |
| `apps/web-platform/test/server/inngest/cron-cohort-dedup.test.ts` | Add `producerClass` + `artifact` to `Row`; add the missing `cron-architecture-diagram-sync` row (R4); add `makeStep(throwOn)`; add the liveness `describe.each` block |
| `apps/web-platform/test/server/inngest/cron-safe-commit-parity.test.ts` | **ADD-ONLY**: A1 pins 1 + 3. Existing gate regex byte-identical |
| `apps/web-platform/test/server/inngest/cron-shared.test.ts` | A1 pin 2 (both arms) |
| `scripts/cron-artifact-age.sh` | **`cron-content-generator` class `A` → `B`** (R3) — the single source |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | `api -> kb` + the `inngest ->` annotation |
| `knowledge-base/engineering/architecture/diagrams/model.likec4.json` | Regenerated |
| `knowledge-base/engineering/architecture/decisions/ADR-126-*.md` | The amendment |
| `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` | New RED arms + the liveness-marker reasons in the stage table (V15) |

### Files to Create

`knowledge-base/project/specs/feat-one-shot-6750-cron-handler-local-liveness/{tasks.md,decision-challenges.md}`.
**No new test files** (V4). **No new ADR** (V18).

### Explicitly NOT edited

- **Handler-side `emitCronPersistResult`** (R5) — but `emitCronDigestLiveness` / `emitCronPersistSkipped`
  ARE added (R10); they are distinct emitters with zero handler sites today.
- **`views.c4`** — verified, not assumed.
- **The existing gate regex** in `cron-safe-commit-parity.test.ts`.
- **The audit `.md`** — a point-in-time record; its numbers stand (see the shallow-clone warning).

### Implementation Phases

**Phase 0 — Preconditions (no edits).**
0.1 **`git fetch --unshallow || git fetch --depth=1000000`** — mandatory first (see the warning), then `git rebase origin/main`.
0.2 Re-derive the roster from the parity test AND `scripts/cron-artifact-age.sh`; confirm they agree modulo the R3 correction.
0.3 `bash scripts/cron-artifact-age.sh --all` — baseline, **valid only after 0.1**.
0.4 Re-run the R1/R2/R5/V1 greps; paste output into the session log.
0.5 `./node_modules/.bin/vitest run test/server/inngest/cron-cohort-dedup.test.ts test/server/inngest/cron-safe-commit-parity.test.ts` — pre-change green.
0.6 **Class assignment is decided structurally, and is already done** (R3). The rule: a producer is Class A iff its prompt mandates the consumed-artifact write with **no** conditional or early-stop. Evidence = the quoted instruction. Empirical confirmation via `scripts/betterstack-query.sh --grep SOLEUR_CRON_PERSIST_RESULT` is **advisory only** — the marker shipped 2026-07-20, so for weekly/monthly producers the window holds ~1 fire and cannot support a "never" claim. If a future check observes a `no-changes` for a Class A producer, that demotes it to B (one line in `cron-artifact-age.sh`).

**Phase 1 — ADR-126 amendment.** Before any handler edit. Use `/soleur:architecture`.

**Phase 2 — `retryEligible: false` sweep (7). Own commit.** Field + scoped comment. No return-value binding here. RED-first via A1 pin 2.

**Phase 3 — Handler changes (7).** After Phase 2's commit.
3.1 Bind `const commitResult = await step.run("safe-commit-pr", …)`.
3.2 `let livenessOk = false;` beside `let heartbeatOk = false;` — addition, never rename.
3.3 Apply the class table; `if (!livenessOk) heartbeatOk = false;` **after** the persistence block.
3.4 (`growth-audit` **only**) R8: `{{RUN_DATE}}` in the four report paths; delete the "compute today's date yourself" instruction and its containment-hook caveat; **update `_cron-shared.ts`'s `injectRunDate` contract comment** to enumerate this exception (R13). Scoping the widening to growth-audit keeps `cron-content-generator`'s STEP 3 note (*"only the issue TITLE date is pre-filled"*) true.
3.5 Export the predicate consts the tests import.
3.6 *(deleted — was R9)*
3.7 **Dedup short-circuit hardening (V1, P0).** Port `digestCommittedOnDefaultBranch` +
`dedup-digest-committed-check` to all 7, mirroring `cron-community-monitor.ts`: the short-circuit
requires **both** the issue and the artifact committed on the default branch, and fails **closed
toward spawning**. Class B uses its allowlist-prefix predicate rather than an exact dated path.
3.8 **Liveness markers (R10).** Wire `emitCronDigestLiveness` (with the arm that decided the verdict)
and `emitCronPersistSkipped` into the 7, mirroring the reference's call sites.

**Phase 4 — Tests, in the existing suite (V4).**
4.1 Extend `Row` with `producerClass: "A" | "B"` and `artifact: {hit, nearMiss, unrelated}`; add the
missing `cron-architecture-diagram-sync` row; lift `makeStep(throwOn)` from the reference.
4.2 Reconcile the shared `safeCommitAndPrSpy` fixture per class (R2). **Do NOT touch the existing
`AC1b — the dedup-skip path posts a GREEN heartbeat` assertion for *liveness* reasons** — that path is
an early `return` ~50 lines before `safe-commit-pr` and never reaches the liveness table, so editing
it as a liveness fix would break a correct, passing test. It changes for a **different** reason:
Phase 3.7's hardening means the skip now also requires the committed artifact, so its fixture must
stage that artifact. The terminal assertion liveness actually moves is `return { ok: heartbeatOk };`.
4.3 One `describe.each(ROWS)` liveness block covering scenarios 1–14 for **all 7**.
4.4 Mutation-battery rules carried forward verbatim: **≥2-element `paths`** wherever production calls
`.includes`/`.some`; a **near-miss** fixture for every anchored property; **cardinality** assertions
on any table claiming exhaustiveness; every added field asserted on a **non-zero** value.
4.5 Assert R11: a liveness-RED run does not create a second issue for the same date.

**Phase 5 — C4.** Edit `model.c4`; `bash scripts/regenerate-c4-model.sh`; commit both together.

**Phase 6 — Operator comms + reconciliation (V14).**
6.1 Compute the **expected-RED roster** mechanically from `cron-artifact-age.sh`'s `name` +
`cron_expr` columns: which monitors may go RED and when each next fires.
6.2 Comment it on **#4375** with the defer-corrected diagnosis and a pointer to this PR. Do **not**
file a new `action-required` issue; do **not** close #4375 (ADR-138 owns that authority).
6.3 Ensure the first post-merge `soleur:operator-digest` carries the roster — the surface the
operator actually opens, versus a PR body read once.
6.4 File two **deferral** issues (`wg-when-deferring-a-capability-create-a`): the
`inngest -> github`/`inngest -> doppler` re-attribution, and the detector's missing self-check-in (V13).

**Phase 7 — Verification.** Launch `bash scripts/test-all.sh` with `run_in_background`; **wait via the
Monitor tool, never a hand-rolled rc-file poll** (`hr-monitor-not-run-in-background-for-polling`).
Redirect the **log** to `/var/tmp`; leave `TMPDIR`/`TC_TMPDIR` to the script, which pins them
deliberately. Then `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. Before treating a
failure as real, check for a sibling worktree's concurrent run (`ps -ef | grep test-all`, then
`/proc/<pid>/cwd`).

---

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| **Uniform rule, no classes** (DHH) | **Rejected, narrowly.** It would false-RED the five change-conditional producers, and the issue explicitly scopes Class A assertions to two named producers. Surfaced as DC-3. |
| **Two 509-line harness ports** | **Rejected** — the cohort suite already parameterises over the handlers; ports would ship a 3rd/4th copy of the substrate mocks and triplicate the mutation-vacuity risk. |
| **R9: bump `last_updated` so the assertion holds** | **Rejected** — production behaviour changed to satisfy a test, and the reasoning proved the file change-conditional. |
| **New ADR-150** | **Rejected** — the issue sanctions an amendment, which avoids the ordinal collision + renumber sweep. |
| **`inngest -> kb`** (issue wording) | **Rejected on evidence** (R7). Surfaced as DC-1. |
| **`webapp -> kb`** (plan v1) | **Rejected** — altitude mismatch; `webapp` is a system, every other `kb` edge is container-level. |
| **Handler-side `emitCronPersistResult`** | **Rejected** — double-emits; R5. |
| **Split the C4 edge into its own PR** | **Rejected** — V16. |
| **Fix `inngest -> github`/`-> doppler` inline** | **Deferred with a tracking issue** (Phase 6.4) + an inline annotation, so the inconsistency is annotated rather than silent. |

---

## User-Brand Impact

- **If this lands broken, the user experiences:** *"PR withheld: safe-commit failed at stage
  `workspace-lost`"* with a runbook pointer, on their own GitHub issue, for a fault that never
  occurred — the concrete artifact of an inverted Phase 2/3 ordering or of the V12 residual.
- **If this lands broken (2):** duplicate committed artifacts and **unbudgeted Anthropic API spend**
  from a re-spawned agent on a replay that was never capable of recovery.
- **If this lands broken (3):** a wave of false-RED Sentry monitors paging weekly for
  change-conditional producers — alert fatigue on the one channel that is supposed to mean something.
- **If this lands broken (4) — R11:** every liveness-RED run attempts a GitHub issue write via
  `onBeforeHeartbeat`. If title dedup ever drifts, the operator gets duplicate FAILED audit issues.
  **v1 wrongly claimed this change "carries only a colour".**
- **If this leaks, the user's workflow is exposed via:** no new exposure vector. The two new markers
  carry `cron`, `run_id`, `attempt`, `ok`, `reason` — no user id, email, or secret. That is
  load-bearing: the marker logger has **no ADR-029 `renameUserIdToHash` formatter and no redact
  paths**, so adding a regulated field would silently bypass ADR-029. Phase 4 asserts the emitted
  field set with `toEqual`, not `toMatchObject`.
- **Brand-survival threshold:** `single-user incident`

---

## Observability

```yaml
liveness_signal:
  what: "Sentry cron monitor check-in per cron (postSentryHeartbeat), now gated on livenessOk in addition to heartbeatOk, plus a hardened dedup short-circuit that no longer posts GREEN on issue-presence alone"
  cadence: "per-run — weekly (growth-audit, campaign-calendar, seo-aeo-audit, architecture-diagram-sync), 2x/week (content-generator), 2x/month (growth-execution), monthly (competitive-analysis)"
  alert_target: "Sentry issue alert -> operator email (failure_issue_threshold = 1); Better Stack pages independently as the second source"
  configured_in: "apps/web-platform/server/inngest/functions/_cron-shared.ts (postSentryHeartbeat + finalizeOutputAwareHeartbeat); apps/web-platform/infra/sentry/"

error_reporting:
  destination: "Sentry (SENTRY_DSN) via reportSilentFallback; SOLEUR_CRON_PERSIST_RESULT + the newly-wired SOLEUR_CRON_DIGEST_LIVENESS and SOLEUR_CRON_PERSIST_SKIPPED pino WARN markers to Better Stack Logs source 2457081"
  fail_loud: "a ?status=error check-in opens a Sentry issue on the first miss; safeCommitAndPr's failure path comments 'PR withheld: safe-commit failed at stage <stage>' onto the operator's scheduled issue"

failure_modes:
  - mode: "producer committed nothing but the issue landed (the #6714 defect, widened)"
    detection: "livenessOk false -> heartbeatOk lowered -> ?status=error within one cron period"
    alert_route: "Sentry cron monitor issue -> operator email"
  - mode: "committed something, but NOT the consumed artifact (the flagship new RED)"
    detection: "SOLEUR_CRON_DIGEST_LIVENESS with reason=digest-absent-from-commit — WITHOUT this marker the run is undiagnosable, because safeCommitAndPr succeeded and SOLEUR_CRON_PERSIST_RESULT reports status=committed (R10)"
    alert_route: "Sentry cron monitor issue + betterstack-query.sh --grep SOLEUR_CRON_DIGEST_LIVENESS"
  - mode: "run 1 filed the issue but lost its commit; run 2 dedups on that issue"
    detection: "dedup-digest-committed-check requires the artifact on the default branch and fails closed toward spawning; SOLEUR_CRON_DEDUP_SKIP records the decision"
    alert_route: "the run proceeds and reports honestly rather than short-circuiting GREEN"
  - mode: "persistence skipped (timeout or heartbeatOk false)"
    detection: "SOLEUR_CRON_PERSIST_SKIPPED with reason=red|timeout (newly wired for the 7)"
    alert_route: "Sentry cron monitor issue + Better Stack Logs"
  - mode: "Class B producer legitimately produces no diff"
    detection: "NOT an alert by design — no-changes stays GREEN for Class B; staleness is caught by the threshold detector at 22-75 days depending on cadence"
    alert_route: "scheduled-cron-artifact-age.yml -> ci/cron-artifact-stale issue"
  - mode: "producer commits under its allowlist with the right message but never writes the consumed artifact"
    detection: "Class A only. Class B is NOT covered — the detector matches the commit message with no pathspec, so the age clock resets (R12). Named residual."
    alert_route: "none for Class B — recorded in the ADR amendment"
  - mode: "the detector itself stops running"
    detection: "NOT DETECTED — the workflow posts no check-in of its own, so its silence reads as healthy (V13). Named residual + tracking issue."
    alert_route: "none — deferred to the Phase 6.4 issue"
  - mode: "regression: a cohort file renames heartbeatOk, or drops retryEligible"
    detection: "cron-safe-commit-parity.test.ts gate regex + A1's call-site-anchored pins"
    alert_route: "CI required check on the PR"

logs:
  where: "Better Stack Logs source 2457081 (Vector from the web hosts), read-only via scripts/betterstack-query.sh; Sentry issues for exceptions"
  retention: "Better Stack per-plan retention (hot window ~40min + S3 archive arm); Sentry issue history 90d"

discoverability_test:
  command: "git fetch --unshallow 2>/dev/null; bash scripts/cron-artifact-age.sh --all"
  expected_output: "one row per producer with CADENCE/CLASS/AGE/THRESHOLD/VERDICT; every row PASS once the cohort is healthy. No SSH, no credential, no dashboard. The unshallow is load-bearing — a shallow clone reports NEVER/STALE for 9 of 9 regardless of production state."
```

**Affected-surface note (2.9.2).** The cron worker is a blind execution surface, and v1's claim that
the existing three emitters "already discriminate every hypothesis" was **false** (R10). With Phase
3.8, the four competing root causes of a RED — *committed the wrong thing*, *committed nothing*,
*persistence skipped*, *deduped on a phantom* — are discriminated by one structured field
(`SOLEUR_CRON_DIGEST_LIVENESS.reason`) rather than inferred.

**Soak follow-through (2.9.1):** not applicable — no AC is time-gated.

---

## Encryption Posture

**Skipped — detection does not fire.** No `.tf`, no `supabase/migrations/*.sql`, no `cloud-init*.yaml`,
no `docker-compose*.yaml`. No persistent store and no new cross-component connection: the new flags
are function-local booleans and every transport touched is pre-existing and already declared.

---

## Acceptance Criteria

**AC preamble.** Directory-wide greps are the wrong scope here and were measured wrong three ways.
Every count AC is evaluated over `$MP`, derived from the parity roster:

```bash
D=apps/web-platform/server/inngest/functions
MP=$(sed -n '/^const MIGRATED_PROMPT = \[/,/^\];/p' \
       apps/web-platform/test/server/inngest/cron-safe-commit-parity.test.ts \
     | grep -oE '"cron-[a-z-]+\.ts"' | tr -d '"' | sed "s|^|$D/|")
[ "$(echo "$MP" | wc -l)" -eq 8 ] || { echo "roster drifted"; exit 1; }
```

> **The three measured traps.** (1) `git grep -c` prints **per-file** counts, and
> `cron-community-monitor.ts` contains `retryEligible` **twice** — once as the field, once in a
> comment — so occurrence counts are contaminated by prose; count **files**. (2)
> `let heartbeatOk = false;` matches **9** files directory-wide (the 8 plus `EXEMPT`
> `cron-roadmap-review.ts`). (3) `await step.run("safe-commit-pr", async () =>` matches **12**
> directory-wide (the 5 `MIGRATED_HANDLER` crons share the shape) **and matches the bound form**,
> because the bound line contains that substring. The unbound form must be line-anchored:
> `^\s+await step\.run\("safe-commit-pr"`. Verified: anchored + `$MP`-scoped returns exactly **7**.

### Pre-merge (PR) — there are no post-merge operator steps

- **AC1** — `echo "$MP" | xargs grep -l 'retryEligible: false' | wc -l` → **8**. Baseline **1**.
- **AC2** — `echo "$MP" | xargs grep -lE 'const commitResult = await step\.run\("safe-commit-pr"' | wc -l` → **8**, and `echo "$MP" | xargs grep -lE '^\s+await step\.run\("safe-commit-pr"' | wc -l` → **0**. Baselines 1 and 7.
- **AC3** — `echo "$MP" | xargs grep -l 'let livenessOk = false;' | wc -l` → **8**, and the same for `let heartbeatOk = false;` → **8** (addition, never rename).
- **AC4** — `echo "$MP" | xargs grep -l 'if (!livenessOk) heartbeatOk = false;' | wc -l` → **8**, and per file its line number exceeds that file's `safe-commit-pr` step.
- **AC5** — behavioural, in `cron-cohort-dedup.test.ts`: for **all 7** (including
  `cron-architecture-diagram-sync`, newly added), `no-changes` → RED for Class A and GREEN for Class
  B; `failed` → RED for both; artifact-absent → RED for A, GREEN-iff-non-empty-allowlisted for B.
- **AC6a (R8)** — inside `GROWTH_AUDIT_PROMPT` **only** (extract with
  `sed -n '/GROWTH_AUDIT_PROMPT/,/^`;/p'`), `<today>` occurs **0** times and `{{RUN_DATE}}-` occurs
  **4** times. Scoping is load-bearing: `<today>` also appears in a **code comment** outside the
  prompt (anchor `files a \`[Scheduled] Growth Audit - <today>\` summary`), so a file-wide grep
  returns non-zero on a correct implementation.
- **AC6 (V1, P0)** — `echo "$MP" | xargs grep -l 'dedup-digest-committed-check' | wc -l` → **8**, and
  a behavioural case per handler: an issue present **without** the committed artifact does **not**
  short-circuit (it spawns), and with the artifact it does.
- **AC7 (R10)** — `echo "$MP" | xargs grep -l 'emitCronDigestLiveness' | wc -l` → **8**; a
  `digest-absent-from-commit` run emits exactly one marker whose `reason` names the deciding arm; the
  emitted field set is asserted with `toEqual` (ADR-029 leak guard).
- **AC8 (R5)** — `git grep -n 'emitCronPersistResult' apps/web-platform/server/inngest/functions/`
  returns exactly the one import and three call sites, **all in `_cron-safe-commit.ts`** — zero
  handler sites. Retained deliberately: the audit records this correction as *"the kind that quietly
  reverts"*.
- **AC9 (R7)** — `grep -cE '^\s*api -> kb' model.c4` → **2**, and `grep -cE '^\s*inngest -> kb' model.c4` → **0**. Anchored, not bare-token (`cq-assert-anchor-not-bare-token`).
- **AC10** — `git diff --name-only origin/main -- .../diagrams/` lists **both** `model.c4` and `model.likec4.json`, and `bash plugins/soleur/test/c4-model-freshness.test.sh` exits 0.
- **AC11** — ADR-126 contains an `## Amendment 2026-07-28 (#6750)` section whose Consequences carry
  all three accepted negatives and all four named residuals **with their day numbers** (15/22/46/75).
- **AC12 (ordering — review discipline, not the mechanism)** — no commit introduces `livenessOk`
  into a handler that did not **already** carry `retryEligible: false` **before** that commit. Note
  `$sha^`, not `$sha`:

  ```bash
  check() {
    local fail=0 sha f
    for sha in $(git rev-list origin/main..HEAD); do
      git show "$sha" -- apps/web-platform/server/inngest/functions/ \
        | grep -q '^+.*let livenessOk = false;' || continue
      for f in $(git show --name-only --format= "$sha" -- apps/web-platform/server/inngest/functions/); do
        git show "$sha" -- "$f" | grep -q '^+.*let livenessOk = false;' || continue
        git show "$sha^:$f" 2>/dev/null | grep -q 'retryEligible: false' \
          || { echo "ORDER VIOLATION $sha $f"; fail=1; }
      done
    done
    return "$fail"
  }
  ```

  Sanity-test against **four** throwaway commits — retryEligible-only, livenessOk-only,
  both-in-one-commit, and correct-order — and confirm it rejects the middle two. The
  both-in-one-commit fixture is what catches the `$sha` vs `$sha^` bug.
- **AC12b (A1 pin 1)** — the cohort assertion derives its roster from
  `cronFiles.filter(src => /finalizeOutputAwareHeartbeat\(/)` (**not** the literal array) and matches
  `retryEligible: false` **at the call site** (inside the `finalizeOutputAwareHeartbeat({…})` argument
  object, or after stripping `//` lines). Falsify by deleting the **field** while leaving the comment
  — the suite must go RED.
- **AC12c (A1 pin 2)** — both arms of the identity test in `cron-shared.test.ts`, described
  behaviourally rather than as a literal call (the helper also requires `step`, `sentryMonitorSlug`,
  `cronName`, `logger`, so an abbreviated literal would not typecheck): with `threw: true`,
  `heartbeatOk: false`, `attempt: 0`, `maxAttempts: 2` — **`retryEligible: false`** → `{retry: false}`
  plus exactly one `?status=error` check-in; **`retryEligible` omitted** → `{retry: true}` with the
  heartbeat step never run.
- **AC12d (A1 pin 3)** — a test parses `scripts/cron-artifact-age.sh`'s `class` column and asserts
  set-equality with the handlers' class arms; `cron-content-generator` reads **B** (R3).
- **AC13** — #4375 carries a comment with the defer-corrected diagnosis, the expected-RED roster, and
  a pointer to this PR. No new `action-required` issue is filed by this PR.
- **AC14** — the two Phase 6.4 deferral issues exist and are linked from the ADR amendment.
- **AC15** — `bash scripts/test-all.sh` fully green (background launch, **Monitor-tool wait**, log under `/var/tmp`).
- **AC16** — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- **AC17** — `git diff --numstat origin/main -- .../cron-safe-commit-parity.test.ts` shows **0 deletions** (additions only).
- **AC18a** — citation sweep: `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.(md|c4|json|sh)' <this-plan> | sort -u`,
  minus the Files-to-Create list, resolves with no misses. Run with the real path substituted — `<…>`
  is shell redirection, not a placeholder — and from the repo root, since the `-e` test is CWD-relative.
- **AC18** — the runbook's stage table and dedup-contract sections name the new RED arms and the
  `SOLEUR_CRON_DIGEST_LIVENESS` reasons.

---

## Test Scenarios

One `describe.each(ROWS)` block in `cron-cohort-dedup.test.ts`, covering **all 7**:

1. happy path posts exactly one `ok` check-in (no double-signal)
2. `no-changes` → RED for Class A, **GREEN for Class B**
3. `failed` → RED for both classes
4. committed other allowlisted files but not the artifact → RED (A) / GREEN-iff-non-empty (B)
5. artifact among **several** committed files stays GREEN — membership, not position (**≥2-element `paths` fixture mandatory**)
6. stale-dated artifact → RED for `cron-growth-audit` (the near-miss; the date anchor is the point)
7. `paths: []` → treated as artifact-absent, not undetermined
8. undetermined `paths` + `resumed` → GREEN
9. undetermined `paths` without `resumed` → RED
10. throw before the persistence gate → RED, **no retry** (`retryEligible: false` makes it terminal)
11. `DeployInProgressError` rethrown bare with **no** heartbeat — asserted as the **named residual** it is (V12), not as a safety property
12. timed-out spawn whose issue landed → RED, and `SOLEUR_CRON_PERSIST_SKIPPED` reason `timeout`
13. **dedup: issue present, artifact NOT committed → does NOT short-circuit** (V1 — the dated incident shape)
14. dedup: issue present **and** artifact committed → short-circuits GREEN
15. a liveness-RED run does not create a **second** issue for the same date (R11)

**Regression:** `cron-community-monitor`'s 19-case harness passes **unchanged**;
`cron-safe-commit.test.ts`'s three persist-result marker sites still count 3; the parity gate regex
is byte-identical.

**Mutation battery + adversarial pass:** every added field mutated to a constant must fail a test;
every `.some`/`.includes` mutated to positional equality must fail a test. Then a reviewer whose
brief is explicitly *"find what my battery missed — do not re-run my mutations"* (this vacuity class
recurred three times in five days, and v1 reproduced it in AC12b).

---

## Open Code-Review Overlap

**None.** Queried 61 open `code-review` issues against every path in Files to Edit/Create. Zero matches.

---

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — by threshold, not by UI surface).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Confined to `apps/web-platform/server/inngest/functions/`, one shell table, the C4
model and a runbook. The three structural risks are (a) the two-half remedy — porting only the
return-value half leaves the dated incident live (V1, now Phase 3.7); (b) the `heartbeatOk`
literal-source-text cohort invariant, which a rename would break across 8 files (AC17); (c) roster
drift, now pinned three ways (A1). No new infrastructure, secret, vendor, or Terraform — the IaC
gate does not fire. Maintenance cost is materially lower than v1: no new test files, no new ADR
ordinal, and the class table single-sourced so a 9th cron cannot silently drift.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** cpo, cto (headless, structured advisory only)
**Skipped specialists:** none — no UI-surface file appears in Files to Edit/Create, so the mechanical
UI-surface override does not fire and `ux-design-lead` is not applicable.
**Pencil available:** N/A (no UI surface)

#### Findings

The product content of this change is *what the operator's monitor colour means*: it becomes noisier
before it becomes quieter, deliberately. A PR-body line is read once, at a moment the operator is not
in. Phase 6 therefore routes a **mechanically computed** expected-RED roster into the #4375 comment
and the next `soleur:operator-digest` — the surface the operator already opens.

---

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **Porting only half the remedy** (v1's actual defect) | was **certain** | **high** — the dated incident shape stays live ×7 while every AC is green | Phase 3.7 + AC6; the reference's "SURVIVES … unless closed here" quoted into the ADR so a future porter cannot miss it |
| The new RED is undiagnosable | was high | high | Phase 3.8 markers + AC7 (R10) |
| Phase 3 lands before Phase 2 in commit order | low | high | AC12 (`$sha^`, 4 fixtures); A1's pins are the mechanism that survives merge |
| Evidence gathered in a shallow clone | **was certain in this worktree** | high — two reviewers drew false conclusions from it | Phase 0.1 `--unshallow` is mandatory and the warning is at the top of the plan |
| Class A misassignment | low (structural rule, prompt-evidenced) | medium — now **cheap to reverse**: one line in `cron-artifact-age.sh` | Single-sourced table + AC12d parity pin |
| Roster drift (a 9th cron) | medium | medium | A1 derives the roster from `finalizeOutputAwareHeartbeat` presence, not a literal array (V10) |
| `DeployInProgressError` mid-spawn still buys a useless replay | medium | medium | **Named residual** in the ADR; not papered over |
| The detector can go dark silently | low | medium | **Named residual** + Phase 6.4 tracking issue |
| Operator alert fatigue in week 1 | high | medium | Expected-RED roster via #4375 + operator-digest (V14) |

---

## Dependencies & Prerequisites

- No blocking dependencies; #6737 is CLOSED and its artifacts are on `main`.
- **A non-shallow checkout** — Phase 0.1.
- `likec4@1.50.0` resolvable for `scripts/regenerate-c4-model.sh`.
- `gh` authenticated for Phase 6.

---

## References & Research

- `knowledge-base/engineering/architecture/decisions/ADR-126-cron-liveness-must-assert-the-consumed-artifact.md` — amended here
- `knowledge-base/engineering/audits/2026-07-20-cron-liveness-cohort-audit.md`
- `knowledge-base/project/learnings/2026-07-20-the-fix-for-a-green-with-no-artifact-bug-shipped-green-with-no-artifact.md` — the fail-closed correction and the mutation-vacuity class this plan's v1 reproduced
- `knowledge-base/project/learnings/2026-06-29-c4-source-edit-requires-regenerate-model-json-orphan-suite.md`
- `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` — the operator-facing target of the "PR withheld" comment
- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — anchor `const failed = threw && !heartbeatOk && retryEligible !== false;`
- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` — the reference; anchors `let livenessOk = false;`, `const commitResult = await step.run("safe-commit-pr"`, `retryEligible: false,`, `#6714 Phase 3.4 — the dedup early-return used to post GREEN`
- `apps/web-platform/test/server/inngest/cron-cohort-dedup.test.ts` — the `describe.each(ROWS)` harness this plan extends
- `scripts/cron-artifact-age.sh` — the canonical producer/class table (single source after R3)
- Related: #6750, #6737, #4375, #5026, #5728, #6714
