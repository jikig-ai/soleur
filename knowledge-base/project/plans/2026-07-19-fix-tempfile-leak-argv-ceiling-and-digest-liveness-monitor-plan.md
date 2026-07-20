---
title: "fix: tempfile leak, jq argv ceiling, and a digest liveness monitor that watches the wrong artifact"
date: 2026-07-19
type: bug-fix
lane: cross-domain
issues: [6713, 6714, 6720]
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# fix: tempfile leak (#6713), jq argv ceiling (#6720), and digest liveness monitor (#6714)

## Enhancement Summary

**Deepened on:** 2026-07-19
**Review passes:** code-simplicity (plan-review), architecture-strategist (plan-review),
test-design (deepen), plus self-executed measurement on this host — every R-row claim and every
review finding was re-run locally, not taken on trust.

### What changed from plan v1

1. **#6713's prescribed fix was rejected as harmful** and proven so by execution (R1/R2): a new
   `trap … EXIT` would replace the harness's existing trap and leak more than the bug it fixes.
   Replaced with a two-line `-p "$RUN_SCRATCH"` change matching an in-repo sibling.
2. **#6720 moved from `--slurpfile` to `--rawfile`** (R8/R9) — removes the silent-undercount
   shape hazard entirely instead of warning about it; proven byte-identical at small scale and
   proven to survive past the ceiling where `--argjson` dies.
3. **#6714 re-framed from a scheduling bug to a persistence + liveness bug** (R13): telemetry
   showed the cron fired daily throughout. The primary defect is that the handler **discards**
   `safeCommitAndPr`'s return value (R16a).
4. **The `outputOk` rename was reverted** (R20): `cron-safe-commit-parity.test.ts:176` pins the
   gate as literal source text across 8 cohort files. Split by addition (`livenessOk`) instead.
5. **R17 was refuted and Phase 3.5 dropped**: the dedup exclusion the plan proposed to add
   already exists at `_cron-shared.ts:937`. The proposed test would have passed on unmodified
   code — a vacuous guard.
6. **Phase 2.2 was fixed after it reproduced the very bug the plan diagnoses**: `_TMPFILES+=`
   inside `emit_extract_json()` is lost to the `$( )` subshell in `drift` mode, and the parent
   EXIT trap does not fire there.
7. **Marker form corrected to the ADR-108 precedent** (Phase 3.3): markers must be pino **WARN**
   (level ≥ 40) structured fields, fail-open, on a dedicated non-Sentry-mirroring logger.
   An info-level marker never leaves the host — the plan's original stdout-string form would
   have shipped an invisible observability surface.
8. **`discoverability_test` command fixed**: `betterstack-query.sh` has no `--query` flag; the
   correct form is `--grep <token> --since <N>[hmd]`. Verified against the script's arg parser.
9. **The >131 KB fixture was vacuous as specified** (test-design, measured): the plan said
   "~1200 synthetic rows", but 1200 *minimal* rows measure only **75,782 B** — under the ceiling,
   exit 0, passing on unmodified code. **Bytes per fact is load-bearing, not row count.** The
   fixture now uses production-shaped rows and asserts its own adequacy *in-suite*.
10. **Behavioral ACs were routed to a suite that cannot execute behavior**: `cron-community-monitor.test.ts`
   has 23 `SUT_SOURCE` refs and **zero `vi.mock`**. Retargeted to `cron-community-monitor-heartbeat.test.ts`,
   the existing behavioral harness. Landing them in the grep suite would have reproduced the exact
   grep-as-proxy anti-pattern the plan warns about.
11. **The `SafeCommitResult` widening breaks three suites the plan said were unaffected**: all
   three mock `{ ok: true }`, which is outside the union — once `status` is read, they fall to the
   RED arm. Added to Files to Edit.
12. **AC numbering replaced with descriptive references.** Numeric `AC-N` cross-refs drifted
   twice during this session's edits; descriptive names ("the no-second-trap AC") do not.

### Cuts (accepted from code-simplicity review)

Phase 0 (duplicated ACs), Phase 1.4 fold-ins (→ tracked sweep issue), the standalone tmpfile
test file (would have been unreachable — a real defect it caught), `DM_MAX_FACTS` (invented a
failure mode the fix removes), and one duplicate marker.

### Recorded disagreement

DC-1 in `specs/…/decision-challenges.md` — marker 4 retained against recommendation.

---

## Overview

Three sibling defects surfaced by the community-monitor collector review that merged
2026-07-19 (`36fbb2905`, PR #6709). They share one theme — **a guard that reads as
protective but does not hold** — but they are otherwise independent and are fixed in
three self-contained phases.

- **#6713** — `apps/web-platform/infra/workspaces-luks-freeze.test.sh` allocates two
  tempfiles outside the harness's already-trapped scratch directory. Any early exit
  leaks them onto the 4 GB `/tmp` tmpfs.
- **#6720** — `scripts/domain-model-drift.sh:107` binds a ~73 KB unbounded accumulator
  as a single jq `--argjson` argv argument, at 55.6% of the 131,072 B per-argument
  kernel ceiling, on a monotonic growth curve.
- **#6714** — the community-monitor cron's liveness signal asserts that a *labelled
  GitHub issue* was updated, not that a *digest was committed*. Telemetry pulled during
  planning shows the cron **did** fire, the agent **did** keep filing digest issues, and
  `safeCommitAndPr` simply stopped landing the artifact — while the monitor reported GREEN
  for the last six days of the gap and went silent in Sentry after 07-13.

**Two findings re-scope this plan away from its issue bodies, both on measured evidence:**

1. **The fix prescribed in issue #6713 would make the leak strictly worse** (R1/R2, proven by
   execution). The named file has no trap; the harness it sources already has one, and adding a
   second would replace it.
2. **#6714 is not a scheduling bug.** The issue asks "did the cron fire?" — it did, on all but
   four Tier-2-deferred days (R13). The real defect is a persistence path with three distinct
   GREEN-with-no-artifact holes (R16) and a liveness signal watching the wrong artifact (R12).

#6720's prescription is also refined: `--rawfile` over the raw TSV beats the prescribed
`--slurpfile`, because it removes the silent-undercount shape hazard entirely rather than
warning about it (R8/R9).

---

## Research Reconciliation — Spec vs. Codebase

Every claim below was measured on this host during planning, not inferred.

| # | Issue-body claim | Measured reality | Plan response |
|---|---|---|---|
| **R1** | #6713: root cause is one-`trap`-per-tempfile replacement + a `_mktemp()` helper losing array appends to a `$( )` subshell. Fix: `_TMPFILES=()` + a single `trap … EXIT` registered once. | **The named file registers ZERO `trap` statements** (`grep -c 'trap ' workspaces-luks-freeze.test.sh` → 0). The sourced harness `workspaces-luks-harness.sh:39-42` ALREADY registers exactly one `trap cleanup_scratch EXIT INT TERM HUP` over `RUN_SCRATCH`. The real defect is narrower: two `mktemp` calls (`:101`, `:331`) omit `-p "$RUN_SCRATCH"` and land in `$TMPDIR`. | **Reject the prescribed fix — it is actively harmful.** Adding `trap … EXIT` in the test file (sourced AFTER the harness at `:28`) REPLACES the harness trap, leaking the whole 31-case `RUN_SCRATCH` tree on *every* run. Proven empirically (R2). Adopt the two-line `-p "$RUN_SCRATCH"` fix instead. |
| **R2** | — | **Proof executed.** A minimal reproduction sourcing a harness-with-trap then registering `_TMPFILES=()` + a new `trap … EXIT` printed `NEW-TRAP-FIRED` and **leaked 1 scratch dir**; the `mktemp -p "$SCRATCH"` variant printed `HARNESS-TRAP-FIRED` and leaked **0**. | The plan's fix direction is empirically grounded, not stylistic. |
| **R3** | #6713: the trap-replacement and subshell-append classes are the root cause here. | Those classes are **real but live in two OTHER files**: `scripts/content-publisher.sh:69-77` (class d — `_TMPFILES=()` + trap, but `make_tmp()` appends inside `$( )` at 6 call sites, so the array is always empty and the trap is dead) and `scripts/skill-freshness-aggregate.sh:101` vs `:270` (class c — a second top-level `trap … EXIT` replaces the tmpdir trap, then `:274` clears it). | **Do NOT fold in** (re-scoped at plan-review): different files, different class, and no AC here would cover them behaviorally. `content-publisher.sh` is the higher-severity of the two because it *reads as fixed* while its trap is dead. Tracked sweep issue instead — see Phase 1.4. |
| **R4** | #6713: a `TEST_GROUP=scripts bash scripts/test-all.sh` run aborted because this file filled `/tmp`. | The file is **not invoked from `scripts/test-all.sh` at all** (`grep -c 'luks-freeze' scripts/test-all.sh` → 0; the `want_scripts` glob at `:294` does not cover `apps/web-platform/infra/`). It runs only from `.github/workflows/infra-validation.yml:395`. | The misattribution is real but indirect: this file pre-fills `/tmp`, and a *later, unrelated* `test-all.sh` run fails. Correct the causal chain in the PR body; do not add it to `test-all.sh`. |
| **R5** | #6713: 9,470 files / 1.9 GB observed. | A **clean run leaks 0 files** (measured, private TMPDIR, exit 0, 58 passed). A forced `SIGTERM` mid-suite leaked **2 files / 1,620,177 B**. The leak requires an early exit; the observed total is accumulation across many aborted runs. | Verification must FORCE a mid-suite failure and must exercise a ≥2-tempfile window (a single-tempfile probe cannot distinguish the classes). Do not assert a specific historical file count. |
| **R6** | #6720: `facts_json` ~72 KB, ~350 facts, ~55% of ceiling. | **Confirmed exactly**: `facts_json` = 72,878 B; `.facts \| length` = 350; `.blind_spots \| length` = 54; 72,878 / 131,072 = **55.6%**. | Claim holds verbatim. |
| **R7** | #6720: MAX_ARG_STRLEN = 131,072 B; 131,071 passes, 131,072 fails. | **Confirmed by bisect on this host**: `jq -n --arg x <131071 B>` → PASS; `<131072 B>` → FAIL (`Argument list too long`). | Claim holds verbatim. Use this bisect as a regression fixture. |
| **R8** | #6720: fix via `jq -Sn --slurpfile facts "$FACTS_NDJSON"`, watching the NDJSON-vs-array shape trap (`add // []`). | `--slurpfile` works but **carries an avoidable silent-undercount hazard**: the payload here is a single top-level array, so `$facts` becomes `[[…350…]]` and binding it directly yields `.facts \| length == 1`. The source data is **TSV, not JSON** — so `--rawfile` over the raw TSV eliminates the shape question entirely and matches an exact in-repo precedent at `scripts/rule-metrics-aggregate.sh:70-74, 203-210`. | **Adopt `--rawfile` (Option R), not `--slurpfile`.** Proven output-identical (R9). It also deletes the intermediate `facts_json`/`blind_json` variables rather than making them file-borne. |
| **R9** | — | **Proof executed.** Same TSV through both paths: at 410 B the `--argjson` and `--rawfile` outputs are **byte-identical** (`diff -q` clean), including quote/apostrophe/Unicode rows. At 175,472 B the `--argjson` path dies `jq: Argument list too long` with **no output**, while `--rawfile` returns **1200 facts** correctly. | Option R is a safe drop-in that also removes the ceiling. |
| **R10** | #6720: "there is NO existing tempfile to slurp." | **Confirmed.** The only `mktemp` in the file is at `:235` inside `write_row()`, a mutually-exclusive mode never reached from `extract`/`drift`. | Claim holds. A new spool file is required. |
| **R11** | #6714: newest committed digest is 2026-06-08; 41-day gap. | **Confirmed.** `knowledge-base/support/community/2026-06-08-digest.md`, committed 2026-06-08 (`4e5d713d1`, PR #5001). 80 digests total. **Zero `docs: daily community digest` PRs after #5001** and zero `ci/community-digest-*` remote branches after 2026-06-03. Note a **prior undiagnosed 8-day gap** (2026-05-26 → 2026-06-02) the issue does not mention. | Claim holds. The artifact truly stopped landing — this is not a naming/location drift. |
| **R12** | #6714 item 3: the monitor verifies a labelled ISSUE was updated, not that a digest was COMMITTED — so issue-filed-but-digest-not-committed is GREEN today. | **CONFIRMED twice over.** The code's own comment at `cron-community-monitor.ts:257-260` states it; and the call chain proves it: `heartbeatOk` ← `resolveOutputAwareOk` (`:562-572`) ← `verifyScheduledIssueCreated({label, sinceIso})` (`_cron-shared.ts:1041-1045`) — a GitHub issue search by label + update time. **There is no assertion anywhere that a digest file was committed, that a PR was opened, or that `safeCommitAndPr` returned `"committed"`.** | The substantive fix. Scoped in Phase 3. |
| **R13** | #6714 item 1: did the cron fire between 2026-06-08 and 2026-07-19? | **It fired — the issue's framing is wrong.** A `[Scheduled] Community Monitor - <date>` issue was filed at ~08:0x UTC on essentially every day 06-13 → 07-19 (#5253 … #6695). The four days 06-09 → 06-12 are explained: `cron-community-monitor` sat in `TIER2_DEFERRED_CRONS` from `a48c57e8d` (06-08) to `ff42a3ef6` (06-12), which **posts a GREEN check-in and skips the spawn** (`_cron-shared.ts:745-750`). | Re-scope: this is not a "cron stopped firing" bug. It is a persistence + liveness-signal bug. The Tier-2 defer explains 4 of 41 days and is itself a GREEN-with-no-artifact path worth instrumenting. |
| **R14** | #6714 item 2: did `safeCommitAndPr` run? | **Partially resolved.** Some runs were genuinely RED and correctly committed nothing: Sentry shows `Cron failure: scheduled-community-monitor` ×48 (05-19 → 07-13) and `scheduled-output-missing` ×17 (06-22 → 07-13); issue bodies #5626/#5666 are FAILED self-reports citing *"Credit balance is too low"*, exitCode 1. **But 07-14 → 07-19 is the damning window**: real digest issues (#6399, #6519, #6581, #6662, #6695) link to digest files that never landed, with **no Sentry cron failure after 07-13**. Persistence did not fail loudly — only one `safeCommitAndPr` Sentry event in 90 days (2026-06-11, `pr-create: Connect Timeout`), outside that window. | The GREEN-with-no-artifact state is not theoretical — it ran for six consecutive days. |
| **R15** | — | **The community-monitor path emits ZERO `SOLEUR_*` stdout markers.** The only `SOLEUR_*` token in the path is `SOLEUR_COLLECTOR_STATUS_DIR` (`:527`) — an *env var name*, not a monitored marker. Proven not to be a pipeline fault: `safe-commit-no-changes` shows 3 hits in 3 days, **all `cron-content-publisher`**, none for community-monitor — the log path ships, this cron just never emitted. | Phase 3.3's markers are the load-bearing deliverable, not decoration. Without them the next occurrence is equally undiagnosable. |
| **R16** | — | **Four distinct GREEN-with-no-artifact paths exist**, ranked by likelihood after architecture review: **(a) the handler DISCARDS `safeCommitAndPr`'s return value** — `cron-community-monitor.ts:652-663` is `await step.run("safe-commit-pr", async () => safeCommitAndPr({…}))` with **no assignment**, so a `{status:"failed"}` or `{status:"no-changes"}` result is silently dropped and `heartbeatOk` stays true; **(b)** dedup early-return (`:437-447`) posts `ok:true` and returns before minting a token or spawning; **(c)** Tier-2 defer (R13); **(d)** trailing-step throw caught at `:665-689`, left GREEN by design at `:669-671`. Additionally the gate at `:651` has **no `else`** — a RED/timeout run skips silently. | **(a) is the primary mechanism for 07-14 → 07-19 and is closed by 3.1/3.2 alone.** (d) is near-unreachable: `safeCommitAndPr` almost never throws — every failure stage `return`s `failure(...)` and the outer catch at `:808-811` converts residual throws to `return failure(…, "unexpected")`. Plan v1 mis-ranked (d) first; corrected. |
| **R17** | Plan v1 asserted: the FAILED audit issue shares the dedup check's label + title prefix, so a failed run's audit issue can satisfy a later run's dedup → a self-perpetuating loop. | **REFUTED — the exclusion already exists.** `isRealScheduledDigest` (`_cron-shared.ts:924-939`) has two rejection arms: `:935` requires the **exact** canonical title (so `- FAILED` never matches), and `:937` rejects any body starting with `AUDIT_SELF_REPORT_BODY_PREFIX` — which is exactly how `ensureScheduledAuditIssue` mints its body (`:1389-1390`). The intent is documented at `:868-870`: *"this read EXCLUDES them so a same-day recovery still files the real digest (zero-digest guard, P1)."* | **Phase 3.5 dropped.** The claim was plan-author paraphrase that I did not verify against source before writing it — the exact defect class this plan's own Sharp Edges warn about. A test asserting "run 2 still spawns" would have **passed on unmodified code**: a vacuous guard. Replaced with a *characterization* test pinning the `:937` arm, which is currently a load-bearing invariant with a single guard. |
| **R20** | — | **`cron-safe-commit-parity.test.ts:176` asserts the gate as literal source text** — `/if \(heartbeatOk && !spawnResult\.abortedByTimeout\) \{[\s\S]{0,800}?safeCommitAndPr\(\{/` — across all 8 files in `MIGRATED_PROMPT`, including `cron-community-monitor.ts` (`:43`). `cron-community-monitor.ts:507` explicitly cites preserving this shape as a design constraint the #6695 change worked around. | **Do NOT rename the gate variable.** Plan v1's `outputOk` rename would have turned this cohort test red and broken an invariant a prior PR deliberately preserved. Phase 3.1 restructured: `heartbeatOk` **keeps its name and its role as the persistence gate**; a new, separately-named `livenessOk` feeds the Sentry check-in. The split is achieved by *addition*, not renaming. |
| **R21** | — | **Replay-resume skips the file scan entirely.** When `resuming` is true (`_cron-safe-commit.ts:444-455`), the scan at `:457-549` never runs, so `matched` is never computed and `fileCount` is documented as `0` (`:121-122`). | A naive digest-path assertion would **false-RED a legitimate replay-resume** where the artifact did land. Phase 3.2 needs an explicit `resumed` carve-out. |
| **R18** | #6714: `days=1` is not the answer. | Not challenged. `days=1` is correct for a daily cadence. | Explicitly out of scope; do not propose it. |
| **R19** | — | **Stale comment**: `cron-community-monitor.ts:393-397` says the cron is "still Tier-2-deferred", contradicting `:151` and `_cron-shared.ts:736` (the set is empty at HEAD). Actively misleading during triage — it cost time in this very investigation. | Correct it in Phase 3. |

---

## Hypotheses (#6714)

Per the hypothesis-discipline sharp edge, a verdict is recorded **only** where the deciding
datum is in hand. "It is registered" is not evidence "it fired."

| ID | Hypothesis | Verdict | Deciding datum |
|----|-----------|---------|----------------|
| H1 | Newest committed digest is 2026-06-08; the artifact genuinely stopped landing. | **CONFIRMED** | `ls` + `git log`: last file `2026-06-08-digest.md`, last commit `4e5d713d1` (PR #5001). Zero `docs: daily community digest` PRs and zero `ci/community-digest-*` branches thereafter. |
| H2 | The cron did not fire during the gap. | **REFUTED for 06-13 → 07-19** | A `[Scheduled] Community Monitor - <date>` issue was filed at ~08:0x UTC on essentially every day (#5253 … #6695). |
| H3 | The cron fired but was short-circuited before the spawn, 06-09 → 06-12. | **CONFIRMED** | `cron-community-monitor` was in `TIER2_DEFERRED_CRONS` from `a48c57e8d` (06-08) to `ff42a3ef6` (06-12); zero labelled issues exist between #5002 (06-08) and #5253 (06-13). |
| H4 | The Tier-2 defer explains the full 41 days. | **REFUTED** | The defer window is 4 days; the set is empty at HEAD (`_cron-shared.ts:736`) and issues resumed 06-13. |
| H5 | Persistence is gated on `heartbeatOk && !spawnResult.abortedByTimeout`. | **CONFIRMED** | `cron-community-monitor.ts:651`. |
| H6 | The monitor asserts a labelled **issue**, not a committed **digest**. | **CONFIRMED** | `resolveOutputAwareOk` → `verifyScheduledIssueCreated({label, sinceIso})`, `_cron-shared.ts:1041-1045`. No digest-commit assertion exists anywhere. |
| H7 | Some runs were genuinely RED and committed nothing by design. | **CONFIRMED** | Sentry: `scheduled-output-missing` ×17 (06-22 → 07-13); `Cron failure: scheduled-community-monitor` ×48 (05-19 → 07-13). Issue bodies #5626/#5666 are FAILED self-reports citing "Credit balance is too low", exitCode 1. |
| H8 | On the GREEN days the agent produced a digest issue but nothing was committed. | **CONFIRMED at artifact level** | 07-14 → 07-19: real digest issues (#6399, #6519, #6581, #6662, #6695) reference digest files that never landed, with **no Sentry cron failure after 07-13**. |
| H9 | Which internal branch swallowed persistence on those GREEN days (trailing-step throw vs. dedup early-return vs. `no-changes`). | **UNKNOWN** | Would be decided by Inngest **step-level** run history. `INNGEST_BASE_URL=http://host.docker.internal:8288` is container-internal and unreachable (`curl` → `000`); no run-history API route exists. **Phase 3.3 marker #3 is what would decide it.** |
| H10 | Persistence failed loudly during the window. | **REFUTED** | Exactly one `safeCommitAndPr` Sentry event in 90 days — 2026-06-11, `pr-create: Connect Timeout` — outside the GREEN window. |
| H11 | The merged collector fix (#6709) explains the missing artifact. | **REFUTED** | #6709 addressed number *fabrication*. The artifact-absence path is untouched by it — a correct-numbers run with no committed digest is still GREEN. |
| H12 | `days=1` caused the gap. | **REFUTED** | `days=1` is the correct daily-cadence parameter and was always passed. |

**Summary of the measured cause.** The cron fired on all but the four Tier-2-deferred days.
The agent kept producing digest issues. `safeCommitAndPr` stopped landing the artifact — and
the monitor, which asserts only that a labelled issue was updated, reported **GREEN for the
last six days of the gap** and stopped reporting anything to Sentry after 07-13.

**H9 stays UNKNOWN and the plan does not pretend otherwise.** Per the hypothesis-discipline
sharp edge, the deciding datum (Inngest step history) is unreachable from this environment, so
no verdict is recorded. Critically, **the fix does not depend on H9**: H6 alone establishes
that the liveness signal tracks the wrong artifact, and R16 enumerates all three GREEN-with-no-
artifact paths from source. Phase 3.3's `SOLEUR_COMMUNITY_DIGEST_FILE` marker is specifically
designed to convert H9 into a measured datum on the next fire.

---

## User-Brand Impact

**If this lands broken, the user experiences:** a community digest that silently stops
appearing under `knowledge-base/support/community/` while the operator's monitoring says
everything is green — plus CI failures attributed to the wrong test suite, costing debugging
time on a defect that lives elsewhere.

**If this leaks, the user's data/workflow is exposed via:** no new exposure vector. All three
fixes are internal tooling, CI, and observability. No user data, credentials, or
customer-facing surface is touched. The tempfile fix strictly *reduces* residue left on disk.

- **Brand-survival threshold:** `aggregate pattern` — the harm is cumulative operator blindness
  and misattributed engineering time, not a single-user incident.

---

## Implementation Phases

### Phase 0 — (removed)

*Cut at plan-review (code-simplicity, accepted).* The three proposed preconditions were
verbatim duplicates of the "harness trap intact", "fact count relational", and ">131 KB fixture" ACs respectively. Baselines measured at plan time and
recorded in Research Reconciliation: harness trap present (R1), extract = `{"f":350,"b":54}`
(R6), argv bisect 131,071 PASS / 131,072 FAIL (R7). The ACs are the checkable post-conditions;
a "blocking" phase that verifies nothing the ACs don't is ceremony.

---

### Phase 1 — #6713 tempfile leak

**1.1 Fix the two deviant allocations.** Match the sibling's exact form
(`workspaces-luks-staging.test.sh:413, 802, 1004`), which already uses this pattern at all
7 of its sites and registers no second trap:

- `apps/web-platform/infra/workspaces-luks-freeze.test.sh:101`
  `BIGF="$(mktemp)"` → `BIGF="$(mktemp -p "$RUN_SCRATCH" bigf.XXXXXX)"`
- `apps/web-platform/infra/workspaces-luks-freeze.test.sh:331`
  `mut="$(mktemp --suffix=.sh)"` → `mut="$(mktemp -p "$RUN_SCRATCH" mut.XXXXXX.sh)"`

`RUN_SCRATCH` is already in scope in this file (used at `:260`, `:276`, `:307`), so no new
variable, no array, and no trap is introduced. `mutate()`'s `$( )` return stays as-is — the
subshell-append hazard evaporates because there is nothing to append.

**1.2 Do NOT register a `trap … EXIT` in this file.** Add a one-line comment at the
allocation sites recording why (it would replace the harness trap). This is the load-bearing
constraint; a future "cleanup" PR will otherwise re-introduce the worse bug.

**1.3 Retain or drop the tail `rm -f` lines** (`:346, 357, 368, 379, 390, 402, 414, 415`).
Prefer **retain** — they bound peak scratch usage during a long run, and are now redundant
rather than load-bearing. State the choice in the PR body.

**1.4 Do NOT fold in the sibling class instances — file a tracked sweep issue instead.**
*Re-scoped at plan-review (code-simplicity, accepted).* R3's two files (`scripts/content-publisher.sh`
class-d dead trap at `:69-77` + 6 `$(make_tmp)` sites; `scripts/skill-freshness-aggregate.sh`
class-c trap replacement at `:101` vs `:270`) are **different files with a different defect
class** from #6713. `content-publisher.sh` in particular is a 6-call-site refactor of a
cron-critical publishing script, and no AC here would cover it behaviorally. Research also found
**121 class-(b) no-trap files** repo-wide — far past what this PR should absorb.

File one tracked issue covering: the 2 confirmed class-c/class-d instances (highest severity —
`content-publisher.sh` *reads as fixed* while its trap is dead), the 121 class-(b) files, and
the absence of any lint gate for the class. Reuse the Phase 2.5 precedent. Reference the
canonical safe pattern at `plugins/soleur/skills/community/scripts/github-community.sh:92-127, 529`.

**1.5 Verification — add cases to the EXISTING freeze suite, do not create a new file.**
*Re-scoped at plan-review (code-simplicity, accepted — it found a real defect).* A new
`workspaces-luks-tmpfile.test.sh` would be **unreachable**: infra tests are enumerated by hand in
`.github/workflows/infra-validation.yml` and `test-all.sh`'s `want_scripts` glob does not cover
`apps/web-platform/infra/` (R4). As originally specified it was a file nothing would ever run.

Add instead, inside `apps/web-platform/infra/workspaces-luks-freeze.test.sh` (already wired at
`infra-validation.yml:395`), a self-check that re-invokes the suite in a subshell under a
**private `TMPDIR`**:
- clean run → **zero residue**;
- **FORCED mid-suite failure** (`SIGTERM` during the mutation block, where BIGF and a MUT file
  are simultaneously live — a **≥2-tempfile window**, since a single-tempfile probe cannot
  detect the trap-replacement class) → **zero residue**.

**Two mechanics that must be specified or the check is unreliable:**

1. **Synchronize on state, never on elapsed time.** `mutate()` returns immediately and each
   `MUT` file lives only until its `rm -f` a few lines later. A fixed `sleep N; kill` will miss
   that window on a loaded CI runner and the test then **passes for the wrong reason** (nothing
   was live, so nothing leaked). Poll for the MUT file's existence and signal on that.
2. **Add a recursion guard.** The suite carries only `set -uo pipefail` — no sentinel. A
   self-check that re-invokes the suite from inside the suite recurses forever without one.
   Gate the self-check on an env sentinel (e.g. skip when `WL_SELF_CHECK=1`, and set it for the
   inner run), and make sure the outer summary parse is not confused by the inner run's own
   `N passed, N failed` line.

The separate negative-control fixture is dropped: the **"no second trap"** AC (`trap` count must be 0) already
guards the trap-replacement regression deterministically and for free, so the fixture would be
redundant rather than falsifiability-preserving.

---

### Phase 2 — #6720 jq argv ceiling

**2.1 Restructure `emit_extract_json()` (`scripts/domain-model-drift.sh:60-109`) to Option R.**
Spool the two TSVs to files and bind with `--rawfile`, moving the existing jq programs from
`:97-104` into the final `jq -Sn` at `:106-108`:

The spool write MUST come **after** the secret-scan fail-close at `:91-94` (the scan operates on
the `$facts_tsv$blind_tsv` shell variables and must stay upstream of any file materialization).

```bash
# NOTE: cleanup is caller-owned — see 2.2. Do NOT append to a parent _TMPFILES here.
local facts_f blind_f
facts_f="$(mktemp)"; blind_f="$(mktemp)"
printf '%s' "$facts_tsv" > "$facts_f"
printf '%s' "$blind_tsv" > "$blind_f"

jq -Sn --argjson v "$SCHEMA_VERSION" --arg d "$DISCLAIMER" \
  --rawfile facts_tsv "$facts_f" --rawfile blind_tsv "$blind_f" \
  '{schema_version:$v, stack:"supabase-ts", disclaimer:$d,
    facts: ($facts_tsv | split("\n") | map(select(length>0)) | map(split("\t")) |
            map({kind:.[0], anchor:.[1], object:.[2], detail:.[3]}
                + (if .[0]=="policy" then {predicate:.[3]} else {} end))
            | sort_by(.anchor)),
    blind_spots: ($blind_tsv | split("\n") | map(select(length>0)) | map(split("\t")) |
                  map({file:.[0], detail:.[1]}) | sort_by([.file,.detail]))}'
```

**No `add // []`, no `$facts[0]`, no array-of-arrays.** `--rawfile` binds the file's raw text
to a string variable; the existing program already parses TSV from a string, so the transform
is a move, not a rewrite. Verified output-identical (R9).

**2.2 Cleanup — and the trap that would NOT have fired.**

**Plan v1 got this wrong and architecture review caught it.** v1 put
`_TMPFILES+=("$facts_f" "$blind_f")` inside `emit_extract_json()`. But in `drift` mode that
function runs in a command substitution — `scripts/domain-model-drift.sh:127`,
`extract_json="$(emit_extract_json)"` — so the append lands in a **subshell** and never reaches
the parent array, **and bash does not run the parent's EXIT trap when the subshell exits.** The
spool files would leak on every `drift` invocation and the newly-added trap would be dead. That
is R3's class-d defect, reproduced verbatim inside the fix for a different bug. Verified
empirically by review (`TRAP-FIRED pid=… n=0`, parent array empty).

`extract` mode would have been fine (`:250 extract) emit_extract_json ;;` runs in the main
shell) — which is exactly why a single-mode test would not have caught it.

**Correct approach — pick one, and state which in the PR body:**
- **(preferred)** Allocate the two spool files in the **caller** (main-shell scope), pass their
  paths into `emit_extract_json()`, and register one `trap` over them at top level. The function
  stays substitution-safe.
- Or: keep allocation inside the function and `rm -f` on **every** return path, including the
  `exit 3` secret-refuse at `:93`. No trap, no array — explicit and subshell-proof.

Do **not** introduce a function-local `trap … EXIT` expecting it to fire from a subshell.

**Also:** `write_row()` at `:235` registers `trap 'rm -f "$tmp"' EXIT` and clears it with
`trap - EXIT` at `:246`. Modes are genuinely mutually exclusive (`case "$MODE"` at `:249-254`),
so there is no live collision today — but if a top-level trap is introduced, that
`trap - EXIT` at `:246` **would clear it**. Either migrate `write_row()` onto the shared trap or
leave both untouched; do not half-migrate.

**2.3 Decide the "genuinely exceeds a sane bound" behavior — the answer is: no bound is needed.**
The issue asks the plan to "decide and implement what happens when the fact set genuinely
exceeds a sane bound." **Decision: implement nothing.** With Option R the argv ceiling no longer
applies — file I/O has no per-argument limit, so there is no size at which the fix breaks. This
is a deliberate, recorded decision, not an omission.

*A `DM_MAX_FACTS` soft bound was drafted and cut at plan-review (code-simplicity, accepted).*
The argument against it is decisive: it invents a failure mode the fix just removed. It would
add an env var, a marker, an exit code, an AC, and a test scenario — and because the plan itself
characterises fact growth as monotonic, the cap **would eventually fire on a corpus that is
fine**, converting a working pipeline into a red one. If an oversized drift report ever becomes
a real complaint, that is a legible trigger to file an issue then, against evidence.

**2.4 Regression test** — extend `scripts/domain-model-drift.test.sh`:
- A fixture whose `facts_json` **exceeds 131,072 B** (the existing 1–3-migration fixtures can
  never reach it — the blind spot the 2026-06-18 learning names explicitly).

  **Row COUNT is not the load-bearing parameter — BYTES PER FACT is.** Measured during
  deepen-plan: 1200 *minimal* rows (`policy\tm1\tt1\tp`) produce only **75,782 B** — under the
  ceiling, exit 0, and the test would **pass on unmodified code**: vacuous, the R17 class again.
  1200 *production-shaped* rows (full migration anchor + a real `USING (...)` predicate,
  ~229 B/fact) produce **286,982 B**. The crossover with realistic rows sits between **500**
  (119,282 B) and **600** (143,182 B).

  So the fixture MUST assert its own adequacy **inside the suite**, as a precondition — not as a
  one-time PR-body demonstration (which is unrunnable post-merge, since there is no pre-fix code
  left to run against):

  ```bash
  fj_bytes=$(printf '%s' "$out" | jq -c '.facts' | wc -c)
  [[ "$fj_bytes" -gt 131072 ]] || fail "fixture is only ${fj_bytes} B — below MAX_ARG_STRLEN, this test proves nothing"
  ```

  Use production-shaped rows and assert exit 0 + the exact fact count.
- Assert `.facts | length` equals the TSV line count — **not** merely "output is non-empty."
  `add // []` and `$facts[0]` are indistinguishable on a single-array body, so a
  non-emptiness assertion cannot catch the undercount.
- **Spool-file residue (Phase 2.2's correctness, currently untested).** Phase 2.2 is the most
  defect-prone step in this plan — v1 got it wrong — yet nothing asserted its outcome. Wrap the
  existing `exit 3` secret-refuse cases (`scripts/domain-model-drift.test.sh:82` T5 and `:234`
  T16b) with a private `TMPDIR` and assert **zero residue**, covering BOTH modes separately:
  `drift` (runs `emit_extract_json` under `$( )` — the subshell case) and `extract` (main
  shell). That mode pair is exactly the discriminating axis Phase 2.2 describes, and a
  single-mode test cannot detect the subshell defect.

**2.5 Sibling sweep (do not skip — per the 2026-06-18 learning, "X is unaffected" is a
hypothesis).** File a tracked follow-up issue enumerating the unbounded `--argjson` bindings
found during research, ranked: `scripts/rule-metrics-aggregate.sh:241` (largest; the file
already knows the `--rawfile` pattern one screen earlier at `:204`), `:214`, `:215`, `:242`;
`scripts/audit-bot-codeql-coverage.sh:249/269`; `scripts/learning-retrieval-bench.sh:1495/1530/1531`;
`scripts/skill-freshness-aggregate.sh:177/178`; `plugins/soleur/skills/drain-prs/scripts/triage-prs.sh:94`;
`plugins/soleur/skills/skill-security-scan/scripts/lib.sh:48`, `run-scan.sh:165`. Measure each
against 131,072 B before fixing — item count is not a proxy for argv bytes.

---

### Phase 3 — #6714 digest liveness monitor

**3.0 Evidence pull — DONE at plan time** (self-served, `hr-no-dashboard-eyeball-pull-data-yourself`;
the operator was not asked for anything). Results are the H1–H12 table above and R11–R19. Carry
the raw excerpts into the PR body. Two residual items for /work:
- **H9 remains UNKNOWN** — Inngest step-level run history is unreachable. Per ADR-030 the
  server is bound to `127.0.0.1:8288` (events) / `:8289` (admin) on the Hetzner host, so it is
  host-local by design.

  **Deepen-plan checked whether any non-SSH path exists, and there is none for run history.**
  A CF-Access-fronted `/hooks/inngest-liveness` endpoint does exist (consumed by
  `.github/workflows/scheduled-inngest-health.yml` via `scripts/inngest-liveness-classify.sh`),
  but it returns an **inventory** verdict — `.functions` registration state — not per-run step
  history. So it can answer "is the scheduler alive and are functions registered" and cannot
  answer "which branch did run N take."

  That absence is itself a telemetry gap and is precisely why Phase 3.3 marker #3 is the
  remedy: the markers move the deciding datum out of Inngest's local SQLite and into Better
  Stack, where it is queryable without SSH. Do **not** manufacture a verdict for H9.
- Probe the **earlier 2026-05-26 → 2026-06-02 gap** (R11) opportunistically; if the datum is
  unavailable, record UNKNOWN and move on. It does not gate the fix.

**3.1 Split the signal by ADDITION, not by renaming.** Today one flag serves two jobs. Split
them — this is the architectural change:

- **`heartbeatOk`** — **keeps its name and its current role**: a labelled
  `scheduled-community-monitor` issue exists in the run window; gates **persistence** at `:651`,
  so a RED run still commits nothing.
- **`livenessOk`** (new) — the dated digest `knowledge-base/support/community/<YYYY-MM-DD>-digest.md`
  was **actually committed**. This is what the Sentry check-in asserts at `:708-741`.

**The no-rename constraint is load-bearing (R20).** `cron-safe-commit-parity.test.ts:176`
asserts the gate as **literal source text** across all 8 `MIGRATED_PROMPT` cohort files:

```js
/if \(heartbeatOk && !spawnResult\.abortedByTimeout\) \{[\s\S]{0,800}?safeCommitAndPr\(\{/
```

Plan v1 renamed the gate to `outputOk` and would have turned this cohort test red — breaking an
invariant `cron-community-monitor.ts:507` records a *prior* PR (#6695) as having deliberately
worked around. Adding `livenessOk` downstream leaves the regex matching and the cohort invariant
intact, so **`cron-safe-commit-parity.test.ts` needs no edit and the cohort question genuinely
defers to 3.8** — the outcome plan v1 claimed but did not achieve.

This also breaks the apparent circularity: persistence stays gated on issue-presence; only the
*liveness* signal moves to digest-commit. It follows the file's existing structure — `:502-506`
already documents a flag applied to the heartbeat AFTER the persistence step.

**3.1b Capture the return value — this is the primary defect (R16a).** `:652-663` currently reads
`await step.run("safe-commit-pr", async () => safeCommitAndPr({…}))` with **no assignment**, so a
`{status:"failed"}` or `{status:"no-changes"}` result is silently discarded and the monitor stays
GREEN. Assign it, and derive `livenessOk` from it. **This single change closes the most probable
07-14 → 07-19 mechanism** and is independent of everything else in Phase 3.

**3.2 Assert the commit, not the intent — and widen the result type to make that possible.**

**Blocker found at plan time:** `SafeCommitResult` (`_cron-safe-commit.ts:116-124`) carries
`status: "committed"` with `prNumber`, `branch`, `fileCount`, `deletionCount` — but **no
committed path set**. And `fileCount` is documented as **`0` on a replay-resume** (`:121-122`),
so even a count-based assertion is unreliable. The naive "read the committed paths from the
result" is **not implementable against the current type.**

Required change, in this order:

1. **Widen `SafeCommitResult`** with an **optional** `paths?: string[]` on the `"committed"` arm,
   populated from the already-computed `matched` array at `_cron-safe-commit.ts:495` (each entry
   carries `.path`; it is currently collapsed to `fileCount = matched.length` at `:549`).
   **Scoping gotcha:** `const matched` is block-scoped *inside* the `if (!resuming)` block, while
   `fileCount` is hoisted at `:454`. `paths` must be hoisted the same way — it is **not** in
   scope at the return statement.
   Optional — not required — because the type is consumed across **~20 handler files and ~18
   test files**; a required field is a breaking change to all of them.
2. **Handle replay-resume explicitly (R21).** When `resuming` is true (`:444-455`) the scan at
   `:457-549` never runs, so `matched` does not exist and `paths` will be `undefined`. Add
   `resumed: true` to the committed arm on that branch. **`paths === undefined` means "not
   determined", never "nothing committed"** — conflating them would false-RED a legitimate
   replay-resume where the artifact did land.
3. **Cross-consumer sweep (`hr-type-widening-cross-consumer-grep`).** Run the three-pattern
   sweep, then `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — the compiler is the
   canonical enumerator of exhaustiveness rails, not a source grep.
4. **Then** derive `livenessOk`:
   - `status === "committed"` and `paths` includes the dated digest → **GREEN**
   - `status === "committed"` and `resumed === true` (paths undetermined) → **GREEN** (R21 carve-out)
   - `status === "no-changes"` or `"failed"` → **RED**
   - `status === "committed"` but `paths` present and lacking the digest → **RED**

Do **not** substitute either weaker proxy: "the agent said it wrote the file" is the fabrication
class #6709 already addressed, and workspace file-existence alone does not prove the file
entered the commit (though it is still worth emitting as marker #3, which discriminates
*written-but-not-committed* from *never-written* — the exact split H9 could not resolve).

**3.3 Emit the missing self-reporting markers — following the ADR-108 precedent exactly.**

The path emits **zero** `SOLEUR_*` markers today (R15: exactly one `SOLEUR_` token exists in
`cron-community-monitor.ts`, and it is the env-var *name* `SOLEUR_COLLECTOR_STATUS_DIR` at
`:527`; `_cron-safe-commit.ts` has none). That is why H9 is unresolvable.

**Precedent (deepen-plan Phase 4.4 gate).** `apps/web-platform/server/claude-cost-marker.ts` is
the canonical in-repo form, and four of its properties are load-bearing — a naive
`console.log("SOLEUR_X foo=bar")` would be **silently invisible**:

1. **pino WARN level (40+), never info.** The Vector `app_container_warn_filter` ships only
   pino level ≥ 40 to Better Stack. *An info-level marker never leaves the host.* (See
   `claude-cost-marker.ts:5-8` and runbook `betterstack-log-query.md`.)
2. **Top-level boolean discriminator + spread fields**, so
   `betterstack-query.sh --grep SOLEUR_X` matches via its `raw LIKE '%…%'` filter with no
   script change:
   ```ts
   log.warn({ SOLEUR_CRON_PERSIST_RESULT: true, cron, status, files, pr }, "cron persist result");
   ```
3. **Fail-open** — wrap every emit in `try { … } catch { /* never propagate */ }`. Observability
   must never break the run it observes.
4. **A dedicated pino instance that does NOT install the `mirrorToSentry` logMethod hook**
   (`logger.ts:123-125` auto-mirrors every WARN+ line to a Sentry breadcrumb; a steady marker
   stream would evict genuine breadcrumbs).

**Prescription:** add `apps/web-platform/server/cron-liveness-marker.ts` mirroring
`claude-cost-marker.ts`'s structure (dedicated logger + typed payloads + fail-open wrappers),
and call its exported emitters from the sites below. Do not hand-roll the emit at each site.

Structured fields must **discriminate all competing hypotheses in one event** — a single boolean
that fires on only one failure shape is insufficient.

| # | Marker | Site | Resolves |
|---|---|---|---|
| 1 | `SOLEUR_CRON_PERSIST_RESULT cron=<n> status=<committed\|no-changes\|failed> files=<n> pr=<n\|->` | `_cron-safe-commit.ts:547`, `:805`, and inside `failure()` at `:395` | Persistence outcome is currently `logger.info`-only and unmonitored |
| 2 | `SOLEUR_CRON_PERSIST_SKIPPED cron=<n> reason=<red\|timeout>` | new `else` at `cron-community-monitor.ts:664` | The gate at `:651` has **no `else`** — RED/timeout skips silently |
| 3 | `SOLEUR_COMMUNITY_DIGEST_FILE digest_path=<p> present=<0\|1>` | immediately before the gate at `cron-community-monitor.ts:651`, stat'ing `<spawnCwd>/knowledge-base/support/community/<date>-digest.md` | **This is the single signal that would have decided H9 on day one.** |
| 4 | `SOLEUR_CRON_TIER2_DEFERRED cron=<n>` | `_cron-shared.ts:750` | Tier-2 defer is indistinguishable from a healthy run (the 06-09 → 06-12 blind spot) |
| 5 | `SOLEUR_CRON_DEDUP_SKIP cron=<n> date=<d> digest_committed=<0|1>` | `cron-community-monitor.ts:438` | Dedup early-return is GREEN by construction with no spawn and no commit |

*Marker 6 (`SOLEUR_CRON_SPAWN_TIMEOUT`) was cut at plan-review (code-simplicity, accepted):
marker 2's `reason=timeout` already discriminates it, so it was a duplicate signal at a
different destination.*

*Marker 4 was recommended for cutting (the `TIER2_DEFERRED_CRONS` set is empty at HEAD, so it
instruments a condition not currently occurring) — **retained, disagreement recorded.** The
defer path posts a GREEN check-in while committing nothing, which is precisely the class ADR-126
generalizes ("every GREEN check-in path must be enumerated"). Cutting it would contradict the
ADR this same plan writes, and it accounted for 4 of the 41 gap days. The emit is one line at a
single site; the insurance is worth more than the line.*

**3.4 Close the dedup early-return GREEN path (R16b) — this one survives 3.1/3.2 unless closed.**
`cron-community-monitor.ts:437-447` posts `ok: true` and returns before minting a token or
spawning, whenever a digest issue already exists for the date. Consider the actual observed
state: run 1 files a genuine digest issue but fails to commit; run 2 dedups on that issue and
posts **GREEN with no artifact** — the exact 07-14 → 07-19 shape, surviving the rest of Phase 3.

Fix: before the GREEN early-return, verify the digest for that date is **committed on the default
branch** (a cheap contents API read). If the issue exists but the digest does not, do **not**
dedup — proceed to spawn. Emit marker #5 with the outcome either way.

**3.5 — REMOVED.** *Plan v1 proposed narrowing the dedup predicate to exclude FAILED audit
issues, on the claim that they could satisfy a later run's dedup. Architecture review REFUTED it
(R17): `isRealScheduledDigest` (`_cron-shared.ts:924-939`) already excludes them twice over —
`:935` requires the exact canonical title, `:937` rejects bodies starting with
`AUDIT_SELF_REPORT_BODY_PREFIX`, which is precisely how the audit issue's body is minted
(`:1389-1390`). The intent is documented at `:868-870` as a P1 zero-digest guard. The proposed
"regression test" would have passed on unmodified code — a vacuous guard — and rewriting the
predicate could only regress a correct P1 invariant.*

Replace with a **characterization test** pinning the `:937` body-exclusion arm: it is currently a
load-bearing invariant protected by a single guard, and nothing tests it directly.

**3.5b Trailing-step throw (R16d) — de-scoped to marker-only, deliberately.**
*Plan v1 proposed inverting `:669-671` so a trailing-step throw sets the flag false. Architecture
review found two problems.* (i) **The premise is mostly wrong**: `safeCommitAndPr` almost never
throws — every failure stage `return`s `failure(...)` and the outer catch at `:808-811` converts
residual throws to `return failure(…, "unexpected")`, so the `:665-689` catch is near-unreachable
for persistence failures. 3.1b's captured return value is what actually closes this class.
(ii) **Inverting it is actively harmful**: with `retries: 1` (`:777`), `finalizeOutputAwareHeartbeat`
(`_cron-shared.ts:463-471`) would compute `failed = threw && !heartbeatOk` → true on a non-final
attempt → `retry: true`. Inngest replays memoized steps including `setup-workspace`, whose
`spawnCwd` the `finally` at `:750` already deleted — so `safeCommitAndPr` hits the
`workspace-lost` guard (`_cron-safe-commit.ts:433-436`) and fires a **false `workspace-lost`
Sentry event blaming the wrong cause**, plus a wasted attempt and a delayed RED.

**Decision: do not invert the flag.** Emit marker #1 with `status=failed` from the catch so the
path is observable, and leave the retry semantics untouched. If a real trailing-throw failure
mode ever shows up in the marker data, revisit with evidence.

**3.6 Correct the stale comment (R19).** `cron-community-monitor.ts:393-397` claims the cron is
"still Tier-2-deferred"; `:151` and `_cron-shared.ts:736` say the set is empty. It misled this
investigation. One-line fix, but do not skip it.

**3.7 Sentry monitor.** `apps/web-platform/infra/sentry/cron-monitors.tf:326`
(`scheduled_community_monitor`) needs **no schedule/margin change** — the check-in semantics
change handler-side, not in Terraform. Confirm with `terraform plan` that the resource shows
**no diff**; if it does, the change leaked into IaC and must be re-scoped.

**3.8 Cohort question (scope-out, tracked).** `resolveOutputAwareOk` is shared across the cron
cohort, so every producer whose real deliverable is a committed file — not an issue — has the
same blind spot. **Do not** widen this PR to the cohort. File a tracked follow-up to audit each
producer's asserted-vs-consumed artifact, referencing the ADR from Phase 4.

---

### Phase 4 — ADR + C4

**4.1 ADR.** Write **ADR-126** (next free ordinal — highest existing is ADR-125; treat as
**provisional**, `/ship` re-verifies against `origin/main` and a sibling PR may claim it):
*"A cron's liveness signal must assert the artifact operators consume."* Record the
persistence-gate / liveness-gate split, why issue-presence remains correct for persistence,
and the cohort implication from 3.5. Supersedes nothing; extends the output-aware heartbeat
decision.

If the ordinal is renumbered, **sweep the whole feature artifact set in the same edit** —
`grep -rn 'ADR-126' knowledge-base/project/{plans,specs}/` — so no AC is left asserting a
nonexistent file.

**4.2 C4.** Read **all three** of `model.c4`, `views.c4`, `spec.c4` in full — a keyword grep for
the feature's own noun is not evidence of no impact. Enumerate and confirm each is modeled:
(a) external human actors (the operator consuming the digest); (b) external systems (GitHub,
Discord, X/Bluesky/LinkedIn collectors, Sentry, Better Stack); (c) containers/data stores (the
knowledge-base digest directory); (d) actor↔surface access relationships that change. If the
digest artifact or the Sentry liveness edge is unmodeled, adding it (element + `#external` tag
where outside the boundary + relationship edges + the `view … include` line in `views.c4` so it
renders) is an in-scope task. Then run `apps/web-platform/test/c4-code-syntax.test.ts` and
`c4-render.test.ts` — a `view include` on an undefined element fails there, not at `tsc`.

A "no C4 impact" conclusion must cite the enumeration it checked. An unsupported "None" is a
reject condition.

---

## Files to Edit

| File | Phase | Change |
|---|---|---|
| `apps/web-platform/infra/workspaces-luks-freeze.test.sh` | 1.1, 1.5 | 2 lines: `-p "$RUN_SCRATCH"` at `:101`, `:331` + why-comment; plus the residue self-check cases |
| `scripts/domain-model-drift.sh` | 2.1–2.2 | `--rawfile` restructure; `_TMPFILES` + one trap |
| `scripts/domain-model-drift.test.sh` | 2.4 | >131,072 B fixture; exact-count assertions |
| `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` | 3.1–3.6 | Capture the `safe-commit-pr` return (3.1b); add `livenessOk` (no rename); dedup GREEN-path close; markers 2/3/5; stale comment |
| `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts` | 3.2, 3.3 | Optional `paths?: string[]` + `resumed?: true` on the committed arm; marker 1 at `:395`, `:547`, `:805` |
| `apps/web-platform/server/inngest/functions/_cron-shared.ts` | 3.3 | Marker 4 at `:750` |
| `apps/web-platform/test/server/inngest/cron-community-monitor-heartbeat.test.ts` | 3.1–3.5 | **The behavioral harness** (5 `vi.mock`s, real `postSentryHeartbeat`, stubbed `fetch`, asserts check-in colour end-to-end). Home for the `livenessOk` arms + dedup close. Also: fix its `{ ok: true }` mock (F3) |
| `apps/web-platform/test/server/inngest/cron-community-monitor.test.ts` | 3.6 | Source-grep suite (23 `SUT_SOURCE`, **0 `vi.mock`**) — comment/shape assertions ONLY. Do **not** land behavioral ACs here |
| `apps/web-platform/test/server/inngest/cron-cohort-dedup.test.ts` | 3.2 | `{ ok: true }` mock at `:250` → union-valid value (F3) |
| `apps/web-platform/test/server/inngest/cron-community-monitor-dedup.test.ts` | 3.2 | `{ ok: true }` mock at `:160` → union-valid value (F3) |
| `apps/web-platform/test/server/inngest/cron-safe-commit.test.ts` | 3.2 | Behavioral assertions for `paths` / `resumed` on the committed arm (F4) |
| `apps/web-platform/test/server/inngest/cron-shared.test.ts` | 3.5 | Characterization test pinning `isRealScheduledDigest`'s `:937` body-exclusion arm. *(Four suites already exercise `isRealScheduledDigest` — `cron-shared`, `cron-cohort-dedup`, `cron-community-monitor-dedup`, `cron-cohort-title-date-pin`. Read them first: confirm the `:937` arm is genuinely unpinned before adding, or the new test is redundant.)* |
| *(consumers of `SafeCommitResult`)* | 3.2 | ~20 handlers + ~18 tests; the field is **optional** so the widening is additive. Enumerated by `tsc --noEmit`, not by grep |

**`cron-safe-commit-parity.test.ts` needs NO edit** — the no-rename constraint (R20) preserves its
literal source-text regex. That is the point of splitting by addition.

**But three OTHER suites do need edits (F3, found at deepen-plan).** Every existing mock returns
a value *outside* the `SafeCommitResult` union:

```
cron-community-monitor-heartbeat.test.ts:122   safeCommitAndPrSpy.mockResolvedValue({ ok: true });
cron-cohort-dedup.test.ts:250                  safeCommitAndPrSpy.mockResolvedValue({ ok: true });
cron-community-monitor-dedup.test.ts:160       safeCommitAndPrSpy.mockResolvedValue({ ok: true });
```

`{ ok: true }` has no `status`. Once 3.1b assigns the return and 3.2 derives `livenessOk` from
`status`, `result.status` is `undefined` on all three → falls through to the RED arm → those
suites go red **for a reason unrelated to the defect**. Update each mock to a union-valid value
(`{ status: "committed", prNumber: 1, branch: "x", fileCount: 1, deletionCount: 0, paths: [...] }`).
Plan v1 claimed only the parity suite was spared; that understated the blast radius by three files.
| `knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4` | 4.2 | Only if enumeration finds a gap |

**No new test file is created** — the residue check lands in the already-wired freeze suite
(Phase 1.5). `.github/workflows/infra-validation.yml` therefore needs **no edit**.

## Files to Create

| File | Phase | Purpose |
|---|---|---|
| `apps/web-platform/server/cron-liveness-marker.ts` | 3.3 | Dedicated WARN-level fail-open marker emitters, mirroring `claude-cost-marker.ts` (ADR-108) |
| `knowledge-base/engineering/architecture/decisions/ADR-126-cron-liveness-must-assert-the-consumed-artifact.md` | 4.1 | The gate-split decision |

---

## Acceptance Criteria

### Pre-merge (PR)

**#6713**
1. `grep -c "mktemp" apps/web-platform/infra/workspaces-luks-freeze.test.sh` → `2`, and
   `grep -c 'mktemp -p "\$RUN_SCRATCH"' …` → `2` (both allocations relocated).
2. *(invariant guard — passes today; guards this PR's own diff, does not verify the fix)*
   `grep -c '^[[:space:]]*trap ' apps/web-platform/infra/workspaces-luks-freeze.test.sh` → `0`
   (no second trap introduced — the R1/R2 invariant).
3. *(invariant guard — passes today)*
   `grep -c 'trap cleanup_scratch EXIT INT TERM HUP' apps/web-platform/infra/workspaces-luks-harness.sh` → `1`.
4. The residue self-check lives **inside** `apps/web-platform/infra/workspaces-luks-freeze.test.sh`
   (already wired at `infra-validation.yml:395` — no new file, no workflow edit) and covers:
   clean run → 0 residue; forced mid-suite `SIGTERM` in a ≥2-tempfile window → 0 residue.
5. `bash apps/web-platform/infra/workspaces-luks-freeze.test.sh` reports `0 failed` and a pass
   count of **at least 58** (58 today + the new residue cases).
6. A tracked sweep issue exists for the R3 class-c/class-d instances and the 121 class-(b)
   files, and is linked from the PR body. *(Fold-in cut at plan-review — see Phase 1.4.)*

**#6720**
7. `grep -c -- '--argjson facts' scripts/domain-model-drift.sh` → `0`;
   `grep -c -- '--rawfile facts_tsv' scripts/domain-model-drift.sh` → `1`.
   *(Baseline measured at plan time: `1` and `0` respectively.)*
8. `.facts | length` equals the **TSV line count**, and `.blind_spots | length` equals its own —
   a *relational* assertion, not a literal pin. This is fully discriminating against the
   array-of-arrays undercount (`1 ≠ N`) **and** stable as the corpus grows. Do **not** pin the
   literal `350`/`54`: the plan characterises fact growth as monotonic, so any migration merged
   between plan time and merge would turn a literal AC red on a correct pipeline. (Measured at
   plan time for reference only: 350 facts / 54 blind spots / 72,878 B.)
9. Post-fix output is **byte-identical** to a captured pre-fix baseline on the current corpus.
10. A >131,072 B synthetic fixture passes at exit 0 with the correct fact count, **and the same
    fixture is demonstrated to FAIL on the pre-fix code** (`Argument list too long`) — the
    negative half is what proves the test is not vacuous.
11. **Fixture adequacy is asserted inside the suite** (`facts_json` byte count > 131,072), so the
    >ceiling test cannot silently degrade to vacuous as the fixture or jq encoding changes.
12. **Spool-file residue is zero on every return path**, including the `exit 3` secret-refuse,
    asserted for BOTH `drift` (subshell) and `extract` (main shell) — the discriminating pair for
    Phase 2.2's defect.
13. `bash scripts/domain-model-drift.test.sh` passes.

**#6714**
14. The H1–H12 evidence table is reproduced in the PR body with raw excerpts. **H9 is recorded
    as UNKNOWN** with its missing datum named (Inngest step history unreachable). A verdict
    without a datum is a reject condition; an honest UNKNOWN is not.
15. **Behavioral** (not compile-time) assertions in `cron-safe-commit.test.ts` that `paths` is
    populated from `matched` on a real committed run and `resumed: true` is set on the replay
    branch. `tsc --noEmit` alone is a compile-time proxy and asserts neither.
16. The three `{ ok: true }` mocks (`cron-community-monitor-heartbeat.test.ts:122`,
    `cron-cohort-dedup.test.ts:250`, `cron-community-monitor-dedup.test.ts:160`) are updated to
    union-valid values, and all three suites pass.
17. `SafeCommitResult`'s `"committed"` arm carries **optional** `paths?: string[]` (from `matched`
    at `_cron-safe-commit.ts:495`) and `resumed?: true` on the replay-resume branch;
    `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean across all ~38 consumers.
18. The `safe-commit-pr` step's return value is **assigned** at `cron-community-monitor.ts:652`
    (it is discarded today — R16a, the primary defect), and `livenessOk` is derived from it per
    the 3.2 four-arm table.
19. **`heartbeatOk` is NOT renamed.** `grep -c 'if (heartbeatOk && !spawnResult.abortedByTimeout)'
    apps/web-platform/server/inngest/functions/cron-community-monitor.ts` → `1`, and
    `cd apps/web-platform && npx vitest run test/server/inngest/cron-safe-commit-parity.test.ts`
    passes unmodified (R20 — the cohort invariant survives). **Runner note:** `apps/web-platform`
    uses **vitest** (`package.json:15-16`, `"test": "vitest"` / `"test:ci": "vitest run"`);
    `bun test` is used in this repo only for `plugins/soleur/` and three named non-web-platform
    files. Do not prescribe `bun test` for this package.
20. *(invariant guard — passes today, and is additionally covered by
    `cron-safe-commit-parity.test.ts:176` and `cron-community-monitor.test.ts:352`, both of
    which already fail on a rename.)*
21. A simulated **issue-filed-but-digest-not-committed** run turns the monitor **RED**. This is
    the exact state that ran GREEN for six days (07-14 → 07-19); without this the fix is
    unverified.
22. **Replay-resume stays GREEN** (R21): `status === "committed" && resumed === true` with
    `paths === undefined` → GREEN, not RED. `undefined` must never be read as "nothing committed".
23. **The dedup early-return no longer posts GREEN without an artifact** (3.4): a test where a
    digest issue exists for the date but the digest is not committed asserts the run **spawns**
    rather than dedup-returning GREEN.
24. **Characterization test** pins `isRealScheduledDigest`'s body-exclusion arm
    (`_cron-shared.ts:937`): an issue with the exact canonical title but an
    `AUDIT_SELF_REPORT_BODY_PREFIX` body is **not** treated as a real digest. *(Replaces plan v1's
    vacuous dedup test — see R17.)*
25. Each of the five markers in the 3.3 table is asserted **per emission site**, not by a
    repo-wide `grep -c` (marker 1 alone has three sites: `_cron-safe-commit.ts:395`, `:547`,
    `:805`). Each assertion checks the **emitted field set**, not string presence — a comment
    would satisfy a bare grep.
26. Every marker is emitted at **pino WARN (level ≥ 40)** and is **fail-open** (wrapped so an
    emit failure cannot propagate), per the ADR-108 precedent. An info-level marker never
    reaches Better Stack — a test asserting the level is the only thing that catches this,
    because the code would look correct and simply be invisible in production.
27. `terraform plan` on `apps/web-platform/infra/sentry/` shows **no diff** for
    `sentry_cron_monitor.scheduled_community_monitor` (the change is handler-side).
28. The stale Tier-2 comment at `:393-397` is corrected (R19).

**Cross-cutting**
29. `ADR-126-*.md` exists. If the ordinal is renumbered, `grep -rn 'ADR-1[0-9][0-9]'` across
    `knowledge-base/project/{plans,specs}/` shows no stale reference.
30. The `### C4 views` task either lands `.c4` edits + passing `c4-code-syntax.test.ts` /
    `c4-render.test.ts`, or states "no C4 impact" citing the actors/systems/relationships it
    checked. *(Expected outcome: no impact — this is an observability change adding no container
    or actor. The citation requirement is the plan-skill Phase 2.10 reject condition, kept
    lightweight.)*
31. Full suite green: `bash scripts/test-all.sh`.
32. PR body uses `Closes #6713`, `Closes #6714`, `Closes #6720`; corrects the #6713 causal
    chain per R4 (the file is not invoked from `test-all.sh`); and corrects the #6714 framing
    per R13 (the cron fired — this is a persistence + liveness-signal bug, not a scheduling one).
33. Follow-up issues filed and linked for: the Phase 1.4 tempfile sweep, the Phase 2.5 argv
    sibling sweep, and the Phase 3.8 cohort audit.

### Post-merge (operator)

None. All verification is automatable in-session or in CI.
*Automation note:* the telemetry pull (done at plan time), the `terraform plan` no-diff check,
and every AC above run via CLI/API — no dashboard eyeballing, no SSH.

---

## Observability

```yaml
liveness_signal:
  what: "sentry_cron_monitor.scheduled_community_monitor check-in, newly gated on the
         COMMITTED digest artifact (knowledge-base/support/community/<date>-digest.md)
         rather than labelled-issue presence"
  cadence: "daily 0 8 * * * UTC; checkin_margin 60 min; max_runtime 55 min"
  alert_target: "Sentry issue-owners → operator; failure_issue_threshold 1"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf:326 (unchanged);
                  gate logic in cron-community-monitor.ts"

error_reporting:
  destination: "Sentry (handler exceptions) + Better Stack (SOLEUR_* stdout markers)"
  fail_loud: true   # digest-not-committed now turns the monitor RED instead of GREEN

failure_modes:
  - mode: "agent ran, filed the issue, but no digest was committed (the 07-14→07-19 state)"
    detection: "SOLEUR_COMMUNITY_DIGEST_FILE present=0 + SOLEUR_CRON_PERSIST_RESULT status!=committed"
    alert_route: "Sentry cron monitor RED → operator page"
  - mode: "safeCommitAndPr returned failed/no-changes and the result was discarded"
    detection: "SOLEUR_CRON_PERSIST_RESULT status=failed|no-changes; livenessOk false"
    alert_route: "Sentry cron monitor RED  # the primary 07-14 to 07-19 mechanism"
  - mode: "throw in the trailing safe-commit-pr step (near-unreachable; marker-only by design)"
    detection: "SOLEUR_CRON_PERSIST_RESULT status=failed from the catch"
    alert_route: "marker only — retry semantics deliberately untouched, see 3.5b"
  - mode: "agent produced no labelled issue (spawn RED)"
    detection: "SOLEUR_CRON_PERSIST_SKIPPED reason=red"
    alert_route: "Sentry cron monitor RED"
  - mode: "run aborted by timeout"
    detection: "SOLEUR_CRON_PERSIST_SKIPPED reason=timeout"
    alert_route: "Sentry cron monitor RED"
  - mode: "Tier-2 defer short-circuits the spawn (the 06-09→06-12 blind spot)"
    detection: "SOLEUR_CRON_TIER2_DEFERRED"
    alert_route: "informational marker; distinguishes a deferred run from a healthy one"
  - mode: "dedup early-return skips the spawn while no digest is committed for the date"
    detection: "SOLEUR_CRON_DEDUP_SKIP digest_committed=0"
    alert_route: "Sentry cron monitor RED when the issue exists but the digest is not committed (3.4)"
  - mode: "cron never fired"
    detection: "absent check-in past checkin_margin_minutes=60"
    alert_route: "Sentry missed-checkin → operator page"
  - mode: "tempfile residue reappears in the freeze suite"
    detection: "the residue cases in workspaces-luks-freeze.test.sh fail in infra-validation.yml"
    alert_route: "CI red on the PR"

logs:
  where: "Better Stack (SOLEUR_* markers from the soleur-web-platform app container on the web host -- Vector Source 3 app_container_journald -> app_container_warn_filter, NOT the dedicated Inngest host, whose Source 1 filters PRIORITY 0-4 and would drop every pino line); Sentry for exceptions"
  retention: "per existing Better Stack plan retention"

discoverability_test:
  command: "doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --grep SOLEUR_COMMUNITY_DIGEST_FILE --since 48h"
  expected_output: "one SOLEUR_COMMUNITY_DIGEST_FILE record per daily fire with present=0|1 set,
                    paired with a SOLEUR_CRON_PERSIST_RESULT or SOLEUR_CRON_PERSIST_SKIPPED
                    record naming the outcome. Today this query returns ZERO rows for this cron
                    (measured) — that is the gap being closed."
```

No `ssh` appears in any verification path.

---

## Architecture Decision (ADR/C4)

### ADR
**ADR-126 — a cron's liveness signal must assert the artifact operators consume** (provisional
ordinal). Records the persistence-gate / liveness-gate split: issue-presence remains the
correct gate for *persistence* (it prevents committing garbage from a RED run), but is the
wrong gate for *liveness* (it goes green on a run that produced nothing operators read).

The ADR must also record two things architecture review surfaced as load-bearing:

1. **The corollary that every GREEN check-in path must be enumerated**, with the **four** found
   here as the worked example (discarded return value, dedup early-return, Tier-2 defer,
   trailing-step throw). A correct gate expression is insufficient if sibling paths post GREEN
   and return early. The ADR must state plainly which two this PR closes and which two remain
   marker-only, so a later reader does not assume the class is fully handled.
2. **The cohort-parity decision (R20).** `cron-safe-commit-parity.test.ts:176` pins the
   persistence gate as literal source text across 8 cohort files. This PR keeps that shape
   intact and splits by *addition* (`livenessOk`), so the cohort invariant survives and the
   cohort-wide question genuinely defers to 3.8. Record why renaming was rejected — it is the
   more consequential architectural choice than the split itself, and the next person to
   "clean up" the two flags needs to find this reasoning.

Created in this PR, not deferred. Extends the
output-aware heartbeat decision; supersedes nothing.

### C4 views
Per 4.2 — read all three `.c4` files in full and enumerate external actors (operator as digest
consumer), external systems (GitHub / Discord / X / Bluesky / LinkedIn collectors, Sentry,
Better Stack), the digest data store, and any changed access relationship. Edit `.c4` directly
in this feature's lifecycle if a gap is found; validate with the C4 test suite.

### Sequencing
The ADR describes the target state and ships with the change — no soak gating.

---

## Infrastructure (IaC)

No new infrastructure. The Sentry monitor already exists as Terraform
(`apps/web-platform/infra/sentry/cron-monitors.tf:326`, per ADR-031 Sentry-as-IaC) and its
resource attributes are **unchanged** — the semantics change handler-side. The **"terraform plan shows no diff"** AC asserts
`terraform plan` shows no diff for that resource, which is the guard that the change did not
silently leak into IaC. No servers, secrets, DNS, vendor accounts, or systemd units are
introduced; no operator SSH or dashboard step appears anywhere in the plan.

---

## Open Code-Review Overlap

**None.** Queried 61 open `code-review` issues; none reference
`workspaces-luks-freeze.test.sh`, `workspaces-luks-harness.sh`, `domain-model-drift.sh`,
`cron-community-monitor.ts`, `content-publisher.sh`, or `skill-freshness-aggregate.sh`.

---

## GDPR / Compliance Gate

**Skipped — no regulated-data surface.** No schema, migration, auth flow, API route, or `.sql`
file is touched. No new processing activity, no new LLM-bound personal data (the community
monitor's existing collection is unchanged in scope), no new artifact distribution surface.
The expanded triggers (a)–(d) do not fire: the marker additions are operational telemetry
about commit success, containing a file path and a date, with no personal data.

---

## Domain Review

**Domains relevant:** Engineering only.

Infrastructure/tooling/observability change. No product, marketing, sales, finance, legal, or
support implications. No user-facing surface — the mechanical UI-surface override does not fire
(no path in Files to Edit/Create matches any UI glob), so the Product/UX Gate is correctly
skipped at NONE.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| A future "cleanup" PR adds a `trap … EXIT` to the freeze suite, silently re-introducing a worse leak. | The **"no second trap"** AC pins `trap` count at 0 deterministically; the why-comment at the allocation sites (1.2) states the reason; R2's executed proof is quoted in the ADR. |
| Option R changes output shape and silently undercounts. | The **relational count** AC asserts `.facts \| length` == TSV line count (discriminating against the `1 ≠ N` array-of-arrays undercount, and corpus-stable); the **byte-identity** AC compares against a captured pre-fix baseline. Proven identical at plan time on small + Unicode fixtures (R9). |
| The >131 KB regression fixture is slow or brittle. | Generate synthetically in the test (~1200 rows), not from a real corpus; assert count, not content. |
| Splitting the gate accidentally lets a RED run commit. | The **persistence-gate regression guard** AC pins the existing `heartbeatOk && !spawnResult.abortedByTimeout` behavior at `:651`, and the **no-rename** AC keeps the cohort parity regex matching. |
| H9 stays UNKNOWN, so the exact branch that swallowed persistence is never identified. | The fix does not depend on H9 — H6 and R16 establish the defect from source. Marker #3 (`SOLEUR_COMMUNITY_DIGEST_FILE`) is designed to convert H9 into a measured datum on the next fire. Accepting an honest UNKNOWN beats manufacturing a verdict. |
| Inverting the `:669-671` design decision (3.4) makes the monitor noisier — a transient GitHub timeout now pages. | That is the intended trade: a trailing-step failure now *is* an artifact failure under the new semantics. The one observed instance in 90 days (2026-06-11 `pr-create: Connect Timeout`) suggests the noise floor is ~1 page/quarter. If it proves noisy, add a bounded retry before flipping the flag — do not restore the silent-GREEN behavior. |
| Closing the dedup GREEN path (3.4) causes duplicate digests if the new contents check is wrong. | The **dedup GREEN-path** AC covers the false-negative direction (issue exists, digest absent → must spawn); the existing `isRealScheduledDigest` exact-title match still covers the true-duplicate direction, and the **characterization** AC pins its body-exclusion arm. |
| Three issues in one PR obscures review. | Phases are independent with no shared files; each has its own ACs. Reviewers can assess each phase standalone. |
| ADR-126 collides with a sibling PR. | Ordinal is provisional; `/ship` re-verifies against `origin/main` and the renumber sweep (4.1) covers plan/spec/tasks/ACs. |

---

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.** Filled above.
- **The issue body's prescribed fix for #6713 is wrong and harmful.** Anyone re-reading the
  issue without this plan's R1/R2 will "correct" the implementation back into the worse bug.
  The why-comment and the **"no second trap"** AC exist specifically to stop that.
- **`--slurpfile` on a single top-level array yields `[[…]]`.** If a future edit switches from
  `--rawfile` to `--slurpfile`, `.facts | length` silently becomes `1` and the drift report
  reads as fully-documented at exit 0 — a fail-open undercount. The **relational count** AC
  (`.facts | length` == TSV line count) is the guard; do not weaken it to a non-emptiness check.
- **Test fixtures of 1–3 migrations can never reach the argv ceiling.** This is precisely why
  the defect survived the existing suite. The >131 KB fixture is not optional.
- **A verification that exercises only one tempfile cannot distinguish the leak classes.** The
  forced-failure window must have ≥2 tempfiles live simultaneously.
- **`resolveOutputAwareOk` is shared across the cron cohort.** Changing its *callers'* gating
  here does not fix siblings; resist widening scope, and file the tracked audit (3.8) instead.
- **A GREEN check-in is emitted on FOUR paths that commit nothing** (R16): a discarded
  `safeCommitAndPr` return, the dedup early-return, the Tier-2 defer, and a trailing-step throw.
  This plan closes the first two (3.1b, 3.4). **The Tier-2 defer remains GREEN-with-no-artifact
  and is marker-only** — it is not closed, by decision, because the deferred set is empty at HEAD.
  The trailing-step throw is marker-only for the reasons in 3.5b. Do not read "Phase 3 shipped"
  as "all GREEN-with-no-artifact paths are closed."
- **Do NOT rename `heartbeatOk`.** `cron-safe-commit-parity.test.ts:176` matches it as literal
  source text across the 8-file cohort, and `cron-community-monitor.ts:507` records a prior PR
  deliberately preserving that shape. Split by adding `livenessOk`, never by renaming.
- **`isRealScheduledDigest` already excludes audit issues** (`_cron-shared.ts:935`, `:937`).
  Plan v1 asserted otherwise and would have shipped a vacuous test plus a rewrite of a correct
  P1 zero-digest guard. Verify against source before "fixing" a dedup predicate.
- **"The cron didn't fire" is the intuitive hypothesis and it is wrong here.** It fired daily and
  filed issues throughout. Anyone re-reading issue #6714's framing without R13 will look for a
  scheduling bug that does not exist.
- **Sentry going quiet is not evidence of health.** `Cron failure` events stop after 07-13 while
  digests still were not landing — the silence *is* the symptom, because the monitor's assertion
  had drifted off the artifact. Treat "no alerts" as unverified, not as GREEN.
- **A `SOLEUR_*` string in the source does not prove a marker is emitted.** `SOLEUR_COLLECTOR_STATUS_DIR`
  is an env var *name*, and the path has zero real markers today. The **per-emission-site** AC
  asserts the emitted field set per marker, not string presence — a comment would satisfy a bare
  grep. The **WARN-level** AC is equally load-bearing: an info-level marker is correct-looking
  code that is simply invisible in production.

---

## Test Scenarios

1. Freeze suite, clean run, private `TMPDIR` → exit 0, 58 passed, **0 residue**.
2. Freeze suite, `SIGTERM` during the mutation block (BIGF + MUT live) → **0 residue**.
3. `domain-model-drift extract` on the live repo → `.facts | length` equals the TSV line count
   (relational, not a literal pin) and output is byte-identical to the captured pre-fix baseline.
4. `domain-model-drift extract` on a **production-shaped** synthetic corpus whose `facts_json`
   is asserted in-suite to exceed 131,072 B → exit 0, exact fact count. *(Minimal-shape rows do
   NOT reach the ceiling — 1200 of them measure 75,782 B and the test would be vacuous.)*
5. Spool-file residue: `exit 3` secret-refuse under a private `TMPDIR` leaves **zero residue**,
   asserted separately for `drift` (command-substitution) and `extract` (main shell).
6. Community monitor: issue filed **and** digest committed → monitor GREEN,
   `SOLEUR_COMMUNITY_DIGEST_FILE present=1` + `SOLEUR_CRON_PERSIST_RESULT status=committed`.
7. Community monitor: `safeCommitAndPr` returns `{status:"no-changes"}` → `livenessOk === false`,
   monitor **RED**. *(A digest never written IS `no-changes` — this is the six-day state.)*
8. Community monitor: `safeCommitAndPr` returns `{status:"failed"}` → `livenessOk === false`,
   monitor **RED**, `SOLEUR_CRON_PERSIST_RESULT status=failed`. *(Today the return value is
   discarded and the monitor stays GREEN — the primary regression.)*
9. Community monitor: `{status:"committed"}` with `paths` present but **lacking** the dated
   digest → monitor **RED**. *(The only scenario exercising the path-membership check; nothing
   covers this today.)*
10. Community monitor: spawn RED → nothing committed (persistence gate intact), monitor RED,
    `SOLEUR_CRON_PERSIST_SKIPPED reason=red`.
11. Community monitor: aborted by timeout → nothing committed, monitor RED,
    `SOLEUR_CRON_PERSIST_SKIPPED reason=timeout`.
12. Community monitor: a digest issue exists for the date but the digest is **not committed** →
    the dedup early-return does **not** post GREEN; the run spawns (3.4).
13. `isRealScheduledDigest` characterization: exact canonical title + an
    `AUDIT_SELF_REPORT_BODY_PREFIX` body → **not** a real digest (pins `_cron-shared.ts:937`).
14. Community monitor: replay-resume (`status:"committed"`, `resumed:true`, `paths:undefined`)
    → monitor **GREEN**, not RED (R21 carve-out).
15. Community monitor: Tier-2 defer active → `SOLEUR_CRON_TIER2_DEFERRED` emitted, distinguishing
    the deferred run from a healthy one. *(Still GREEN-with-no-artifact by decision — marker-only.)*
16. `terraform plan` on `apps/web-platform/infra/sentry/` → no diff for the monitor resource.
