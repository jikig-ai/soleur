---
title: "chore: tempfile-ownership sweep, argv-ceiling sweep, and the cron-liveness cohort audit"
date: 2026-07-20
type: chore
lane: cross-domain
issues: [6734, 6736, 6737]
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
plan_version: 2
---

# chore: tempfile ownership (#6734), jq argv ceiling (#6736), cron-liveness cohort audit (#6737)

Three sweep/audit follow-ups split out of PR #6726 (which closed #6713, #6714, #6720).

> **v2 after an 8-agent plan review.** v1 was over-built, and several of its findings were wrong —
> including its headline. v2 is roughly a third the size, retracts three claims, and cuts Phase 3
> back to the audit that ADR-126 explicitly scoped. The corrections are recorded as first-class
> rows, not quietly edited.

## Enhancement Summary

- **#6734** — the issue's framing ("a second EXIT trap replaces the first") is **right for one named
  file and wrong for the other**. `content-publisher.sh` has exactly **one** trap; its defect is
  *subshell-append*, and it leaks on **every run**, not only on abort.
- **#6736** — measured exposure **inverts the issue's ranking**. Only 2 of its 8 listed sites are
  genuinely unbounded; the sweep found **2 the issue missed**, in code that already caused a live
  HTTP 500 (#5523).
- **#6737** — **audit only.** v1 proposed cohort-wide handler edits on a premise the code
  contradicts, and its "cohort is dark" finding is confounded by an already-fixed Tier-2 defer.

### What changed from v1 — including three retractions

| # | Change | Source |
|---|---|---|
| **RETRACTION 1** | **v1's "the other 7 emit nothing at all" is falsified by code.** `emitCronPersistResult` is called from **inside `safeCommitAndPr`** on all three status paths, with **zero** handler-side call sites. v1's Phase 3.2 would have **double-emitted**, and its `discoverability_test` asserted something untrue. | architecture-strategist |
| **RETRACTION 2** | **R22 is confounded and underpowered.** Six of the eight sat in `TIER2_DEFERRED_CRONS` — which **skipped the spawn and posted `ok:true`** — until it was emptied on **2026-06-13**. Every date in R22(a) falls in or before that window. R22(b)'s window is **12 days**, during which `competitive-analysis` fires **zero** times. Not independent corroboration: one confounded measurement and one cadence-blind one. | architecture-strategist, CMO |
| **RETRACTION 3** | **Both Phase 1.3 sites were misdiagnosed, and "fixing" either would cause harm.** `session-state.sh`'s trap lives inside a function never run at source time, its caller never invokes it, and its `flock` locks are fd-held (kernel-released — not a leak). `workspaces-cutover.sh`'s `mktemp` calls are all inside functions invoked **after** the trap arms; adding a trap would **clobber `trap cleanup EXIT` and destroy the LUKS rollback path**. | architecture-strategist |
| 4 | **Phase 3 cut to audit + one independent-vantage detector.** ADR-126 says verbatim it "deliberately does not widen to the cohort; #6737 **audits**". v1 did the widening anyway, without an ADR. | architecture-strategist, simplicity, DHH |
| 5 | **Lint rule (b) cut.** Its discriminator is incoherent — it passes `provision-hetzner.sh` for the wrong reason and has no account of `( … )` or `trap - EXIT`. | DHH, simplicity, Kieran |
| 6 | **Rule (c) added** — `mktemp` + zero trap. v1's gate **did not gate the class it accepted**. | CTO |
| 7 | **R13 was inverted** — the argv site is `--argjson drift_entries`, one of the two lines the issue *did* list; there is nothing at `:275`. R14/R15 anchors also wrong (3 of 4 spot-checked). Whole table re-expressed with content anchors. | Kieran |
| 8 | **R25 corrected**: `B_ALWAYS` = **22,900** (100 B headroom) per the linter — not my `wc -c` of 22,973/27. Conclusion unchanged, but a wrong number was about to ship inside an ADR. | architecture-strategist |
| 9 | **`retryEligible: false` deferred** — not a no-op; it suppresses Inngest retry in 7 crons, and it is a **prerequisite** for (not a peer of) return-value consumption. | planning, Kieran, spec-flow, architecture |
| 10 | **Phase 2.3 assertions cut** to comments-only, except the one live landmine (`PR_JSON`). **18 ACs → 9.** | DHH, simplicity |
| 11 | **Two escalations raised out of scope**: a live published brand defect (E1) and the escalation channel's measured 0% success rate (E2). | CMO, CPO |

---

## Overview

> Spec lacks valid `lane:` (no `spec.md` for this branch) — defaulted to `cross-domain` (fail-closed).

The unifying thread is that **a claim about scope is a hypothesis until measured**. Each issue body
supplied a candidate list written during another PR; each is partly wrong. v1 re-derived those lists
and then committed the same error one level up — asserting "two independent measurements" for its own
headline when both measured the same thing, and neither controlled for a known defer window. R22b/R22c
are that correction. **The plan failed its own opening gate, and that is the most useful thing this
review produced.**

The second thread is **anti-vacuity**. These deliverables are tests and gates, and the repo has 7
mutation-vacuity learnings in the past week. v1 responded by applying the strongest available guard
uniformly, which review correctly called its own ceremony. v2 calibrates by stakes.

### Scope: Phases 1+2 belong together; Phase 3 is a separate concern

Correcting v1's false claim that the phases "share no code": they share **four** files
(`learning-retrieval-bench.sh`, `skill-freshness-aggregate.sh`, `test-all.sh`, `ci.yml`), one ADR and
one CI job. Splitting 1 from 2 would race two PRs on one file. **Phase 3 shares none of that.** Four
of five reviewers recommended splitting there — recorded as **UC-1** in `decision-challenges.md`, an
operator decision, not applied here.

---

## Research Reconciliation — Spec vs. Codebase

Citations are **content anchors**, not line numbers (`cq-cite-content-anchor-not-line-number`).

| # | Claim | Measured reality | Plan response |
|---|---|---|---|
| **R1** | #6734: `content-publisher.sh` has a dead trap from **trap replacement**. | **Half right, wrong mechanism.** Anchor `trap 'rm -f "${_TMPFILES[@]}"' EXIT` is the file's **only** trap. The defect is *subshell-append*: all 6 sites use `x=$(make_tmp)`, so `_TMPFILES+=("$f")` mutates the **subshell's** copy. **Reproduced**: parent array length 0, both files survive. | Trap fires as `rm -f ""` and removes **nothing, on every run**. Parent-scope append. Phase 1.1. |
| **R2** | #6734: "cron-critical publishing script". | **True and worse.** `scheduled-content-publisher.yml` deleted in `5b2c1922d` (#4483); now Inngest `cron-content-publisher` on a **long-lived host** — no runner teardown to mask the leak. | 6 files/run accumulate indefinitely (#6713: 9,470 files / 1.9 GB). |
| **R3** | #6734: `skill-freshness-aggregate.sh` trap replacement. | **CONFIRMED + a third window.** `trap 'rm -rf "$INVOCATIONS_TMPDIR"' EXIT` → `trap 'rm -f "$OUT.tmp"' EXIT` → `trap - EXIT`. The final clear means the **success path leaks the tmpdir every time it writes a report**. | Fix all three. Phase 1.2. |
| **R4** | #6734: canonical pattern is `github-community.sh` using `mktemp -p "$RUN_SCRATCH"`. | **Citation wrong.** `github-community.sh` uses one-trap-in-`main()` + parent-scope appends (anchor: *"Bash EXIT traps are global and singular"*). `-p "$RUN_SCRATCH"` is the `workspaces-luks-harness.sh` idiom. | Cite both halves. |
| **R5** | #6734: "~121 files with no trap at all." | **Verified 121.** 282 shell files contain `mktemp`; 16 have >1 trap. | Derive by committed command — my first glob returned 107. Phase 1.4. |
| **R6** | #6734: the 2 named files are the class-c/d population. | **3 more genuinely exist** (`learning-retrieval-bench.sh`, `weekly-analytics.sh`, `constraint-scaffold.sh`). **But two v1 flagged are NON-DEFECTS — see R6b.** | Tracking issue for the 3. |
| **R6b** | v1: `session-state.sh` is a lock leak; `workspaces-cutover.sh` has unprotected `mktemp`. | **BOTH FALSE, and both dangerous to "fix."** `session-state.sh`'s only trap is inside `_register_lease_release_trap()`, never run at source time; `pre-merge-rebase.sh` never calls it; `flock` locks are **fd-held and kernel-released**, and the `.lock` file is intentionally never unlinked. `workspaces-cutover.sh`'s 8 `mktemp` calls are all **inside functions invoked after `trap cleanup EXIT` arms**; the `trap - EXIT` is the standard self-disarm at the top of `cleanup()`. | **Dropped entirely.** `session-state.sh` is sourced by ~34 hooks and `pre-merge-rebase.sh` runs on **every Bash call**; `workspaces-cutover.sh` performs an irreversible LUKS cutover of sole-copy user data, where a stray trap would **destroy the rollback path** and a stray write would fail byte-identity verify. |
| **R7** | — | **A naive lint would be wrong — and so was v1's discriminator.** `provision-hetzner.sh` is **not** cumulative; it is safe only because its second trap sits inside `( … )`, which v1's rule passes by an empty-subset accident. `vendor-pin-integrity.test.sh` uses `trap - EXIT` **correctly** — the shape v1's own AC condemned. | **Cut rule (b).** One analyzer cannot hold two contradictory models of subshell scope. |
| **R8** | #6734: "no lint rule for any of this." | Confirmed and broader: **no `.shellcheckrc`, no shellcheck CI job**; shellcheck has no rule for either defect. | Custom rule required. Template: `lint-infra-no-human-steps.py`. |
| **R8b** | — | **v1's gate did not gate the class it accepted.** Class-b is *"`mktemp`, no trap"*; rules (a) and (b) both require traps to exist. Neither fires on a new no-trap file. | **Rule (c)**, `--changed`-scoped, + a high-water count asserting `≤ 121`. |
| **R8c** | v1: the lint gate is "stronger enforcement" than an AGENTS.md rule. | **`lint-bot-statuses` is NOT a required check** — absent from both `scripts/required-checks.txt` and `infra/github/ruleset-ci-required.tf`. A PR can merge with it red. | Either add the job to both, or record in the ADR that enforcement is **advisory**. Do not claim teeth it lacks. |
| **R9** | — | **3 orphans**: `skill-freshness-aggregate.test.sh`, `compound-promote.test.sh`, `lint-agents-enforcement-tags.test.sh`. `test-all.sh`'s glob covers `scripts/lib/*.test.sh` but **not** `scripts/*.test.sh`. | Load-bearing: the first is a target of *both* #6734 and #6736, so a test added there gates nothing. |
| **R9b** | — | **`lint-agents-enforcement-tags.test.sh` FAILS today** — exit 1, `Total: 9 Pass: 7 Fail: 2`. Pre-existing, unrelated. | v1's AC5 and AC10 were **mutually unsatisfiable**. Register the two passing orphans; carve an explicit documented exclusion + tracking issue for the third. |
| **R10** | #6736: `MAX_ARG_STRLEN` = 131,072 B per argument. | **Confirmed by bisect**: 131,071 PASS, 131,072 FAIL. `getconf ARG_MAX` = 2,097,152 — a payload at **6% of ARG_MAX** still dies. | Always write the constant **named**, never bare. |
| **R11** | #6736: `rule-metrics-aggregate.sh --argjson enriched` is largest. | **Confirmed**: 35,081 B at 101 rules (27%, 347 B/rule) → ceiling at **~378 rules**, and AGENTS.md grows every compound cycle. In-file `--rawfile` precedent exists. | **Convert.** Phase 2.1. |
| **R12** | #6736: `learning-retrieval-bench.sh` ×3. | **All bounded** — a hardcoded 7-element array (~1.1 KB) and an explicit `.[0:20]` (4,156 B, 3%). The 1,986-learning corpus never reaches argv. | **Do not convert — churn.** Comment only. |
| **R13** | #6736: `audit-bot-codeql-coverage.sh` `:249`, `:269`. | **v1 inverted this.** The real argv site **is** `--argjson drift_entries "$DRIFT_ENTRIES"` — one of the two the issue listed. Nothing exists at `:275`; v1 sent the implementer to a non-existent location. Bounded by `gh pr list --limit 100` → 19,186 B. | Comment at the **correct** anchor. |
| **R14** | #6736: `skill-freshness-aggregate.sh` ×2. | **Safe** — bounded by skill count (94) because `jq -s group_by(.skill)` collapses to one row per skill. **Anchor correction**: the `group_by` is at the *producer*, not the `--argjson` consumer v1 cited. | Comment at the producer. |
| **R15** | #6736: `triage-prs.sh` scales with PR count. | `--argjson prs "$CLASSIFIED"` is **safe** (3,738 B at 17 PRs). **The real finding is adjacent**: raw `PR_JSON` is **328,940 B at 17 open PRs — 2.5× the ceiling today** — surviving only via the `<<<"$PR_JSON"` herestring. | Not an eroding bound — a live landmine. **The one Phase-2.3 assertion.** |
| **R16** | #6736: `skill-security-scan` ×2. | **The only genuinely unbounded site in the issue's list** — snippets capped at 200 chars, **finding count is not** → ceiling ~425 findings. This repo holds `plan/SKILL.md` at 220,523 B. | **Convert.** Phase 2.2. |
| **R17** | — | **Two sites the issue missed**, both the #5523 shape re-introduced one line after the spool fix: `inngest-doublefire-probe.sh` and `inngest-inventory.sh`. The latter's **sibling already carries the #5523 comment**. | **Convert both.** Phase 2.2. |
| **R18** | #6737: the cohort is 8. | **Confirmed.** `cron-roadmap-review` shares the blind spot via a different mechanism and is **outside** every handler-local remedy. | The detector covers **9/9**. |
| **R19** | #6737: the parity test pins `heartbeatOk` as literal source text. | **Confirmed**, and caps the gate→call gap at 800 chars. **Measured headroom is 736** (gap = 64 in all 7). | v1's Risk 5 targeted a non-hazard. See R19b. |
| **R19b** | v1 AC12: "parity green proves the split was by addition." | **It proves almost nothing.** The regex matches only text *before* `safeCommitAndPr({`; liveness work sits *after*. Green today, green after a correct change, green after no change. | Exactly the vacuity class the plan claims to prevent. **Cut.** |
| **R20** | #6737: audit may conclude "N of 8 need no change". | **7 of 8 discard the return value.** All 8 use the identical issue-based predicate. | On that axis, **0 of 8**. Recorded in the audit. |
| **R20b** | v1: `{status:"failed"}` is "silently dropped" and the 7 "emit nothing at all". | **FALSIFIED.** `safeCommitAndPr`'s `failure()` already calls `reportSilentFallback`, comments *"PR withheld: safe-commit failed at stage …"* on the operator's issue, and calls `emitCronPersistResult` — and that emitter is invoked from **inside the shared helper** on all three status paths, with **zero** handler call sites. | The real delta is **the Sentry monitor colour**, not "silent". Much smaller than v1 claimed, and it dissolves v1's marker work (which would have double-emitted). |
| **R21** | — | **Two sub-classes.** Class A (deterministic): `growth-audit`, `campaign-calendar`. Class B (change-conditional, verified against the allowlists): `seo-aeo-audit`, `growth-execution`, `competitive-analysis`, `architecture-diagram-sync` — refresh-in-place targets where a run legitimately produces no diff. | Sound. A naive must-commit rule false-REDs Class B. |
| **R21b** | — | **Per-run reasoning cannot close the gap.** A cron emitting `no-changes` once and one emitting it for 110 consecutive days are **indistinguishable in every operator-reachable surface**. v1 had no streak detector while declaring `aggregate pattern` as its harm model. | This is what the detector fixes. |
| **R22** | — | **A real artifact gap exists**: last self-authored commits run 2026-04-01 → 2026-06-09, and `architecture-diagram-sync` has **never** produced one. | Real, but **heavily qualified by R22b/R22c**. |
| **R22b** | v1: "confirmed by two independent measurements." | **Not independent.** Both measure *cron self-authorship*. A genuinely independent producer — **artifact frontmatter freshness** — disagrees: `competitive-intelligence.md` reads `last_updated: 2026-07-04` (**16 days**) against a 90-day-old cron self-commit. The artifact was refreshed by another path. | The audit must carry **both** columns and name every disagreement. |
| **R22c** | — | **Confounded and underpowered.** `TIER2_DEFERRED_CRONS` held **six of the eight** until emptied `5ea440f4c` on **2026-06-13**; while deferred, `deferIfTier2Cron` **skipped the spawn and posted `ok:true`**. Every R22(a) date falls in or before that window. R22(b)'s window is **12 days** (2026-07-08→07-20) — `competitive-analysis` (`0 9 1 * *`) fires **zero** times in it. | **Diagnose before escalating.** Subtract the defer window; re-measure over ≥2 fire intervals per cron. |
| **R23** | — | A mode neither the issue nor ADR-126 enumerates: **seo-aeo PR #5026 opened, never merged**. GREEN under the old predicate *and* a naive `paths` check — the commit happened, on a branch that never landed. | Only a default-branch check catches it. The instance is **Class B**, where v1's detection was Class-A-only. |
| **R24** | — | **C4 gap confirmed** — the sole `inngest -> github` edge covers ADR-088 token minting. **But v1 proposed the wrong edge.** All nine inbound `kb` edges come from inside the plugin (`skills -> kb`, `agents -> kb`, `architecture -> kb`), all as local `File I/O`; **nothing in `infra` writes to `kb`**. The falsehood is that the KB appears only ever operator-written, when a scheduled server-side container authors committed KB content unattended. | The informative edge is **`inngest -> kb`**. Also: v1's AC17 was vacuous — `views.c4` enumerates elements and both endpoints are already included, so the edge renders automatically and **no `views.c4` edit is needed**. Ships with the Phase 3 follow-up. |
| **R25** | — | **`B_ALWAYS` = 22,900 against a 23,000 cap — 100 bytes**, per `lint-agents-rule-budget.py`. v1's `wc -c` said 22,973/27; the linter is authoritative. | A ~50-60 B pointer *could* land, barely. Still declined on margin — but v1 was about to ship a wrong number inside an ADR. |
| **R26** | — | Three suites mock `safeCommitAndPr` with `{ok: true}`, not a member of `SafeCommitResult`. | Any handler-local change REDs them for a **fixture** reason. Avoided entirely by the audit-only cut. |
| **R27** | — | **4 of 8 handlers have no behavioural harness**; `architecture-diagram-sync` has **no test file**. The community-monitor liveness harness is **509 lines**. | Porting ×2 ≈ 1,000 lines — v1's largest cost, deleted by the cut. |
| **R28** | ADR-126 follow-up: sweep `retryEligible`. | **Not a no-op.** Per `const failed = threw && !heartbeatOk && retryEligible !== false;`, *omitting* is inert but *passing `false`* **suppresses Inngest retry**. Worse, it is a **prerequisite** for return-value consumption, not a peer: lowering `heartbeatOk` on a run that also throws returns `{retry:true}` → Inngest **replays the function and re-spawns the Claude agent** (API cost + duplicate-artifact risk). | **Deferred**, with the ordering constraint recorded. |
| **R29** | — | PR #6348 (draft, HOLD) touches `cron-inngest-cron-watchdog.ts` — not a cohort member. | No collision. |

---

## User-Brand Impact

**If this lands broken:** a reprise of the #6713 disk-fill on a long-lived host if
`content-publisher.sh`'s fix is botched; and — had the retracted Phase 1.3 work been attempted — a
clobbered LUKS rollback path on prod host web-1 (R6b). The latter is the sharpest reminder that a
sweep's blast radius is set by its worst-diagnosed member.

**Harm already realized (partially).** v1 wrote this section conditionally; measurement shows real
accrual, though **less than v1 claimed** (R22c). Firm: `content-strategy.md` has missed 6 weekly
cycles; `campaign-calendar.md` is 56d stale; article output is **zero for 35 days** (~6 permanently
lost indexable assets — indexation age is monotonic). Not firm: the per-cron "dark" durations, which
are confounded by the Tier-2 defer.

**Escalation E1 — a live published accuracy defect.** Two published, indexed comparison pages assert
**Polsia at $1.5M ARR / 2,000+ managed companies**, while `competitive-intelligence.md`
(`last_updated: 2026-07-04`) carries **~$10M and 7,600** — a ~6.7× understatement of a competitor,
**inside JSON-LD** (a `FAQPage` `acceptedAnswer`), on pages whose whole purpose is that comparison.
It errs in the direction that flatters Soleur, and the correction has been available for 16 days.
**The stale figure appears in 8 files.** Copy work on published pages — its own PR, tracked here.

**Escalation E2 — the escalation channel itself.** #4375 (*"competitive-analysis … has not fired in
36 days"*) has been open with `action-required` since **2026-05-24 (57 days)**; the queue holds **28**
items, oldest from 2026-03-12. This finding was already escalated through this exact channel and
broadened while the issue sat. Filing a 29th is an append, not an escalation (**UC-3**).

**If this leaks:** no new exposure vector; no user data is touched.

**Brand-survival threshold:** `aggregate pattern`. Retained. CPO's challenge that Phase 3 warrants
more is recorded as **UC-2**.

---

## Implementation Phases

### Phase 1 — #6734 tempfile ownership

**1.1 `content-publisher.sh` — the subshell-append fix (highest severity).** Append to `_TMPFILES` in
the **parent scope** at each of the 6 sites, not inside `make_tmp`. Add the
`((${#_TMPFILES[@]} > 0))` guard the trap lacks — load-bearing: under `set -u`, empty-array expansion
errors on older bash. Why-comment citing #6734 and the subshell mechanism.

**1.2 `skill-freshness-aggregate.sh` — all three leak windows.** One owning trap; remove the
replacement and the `trap - EXIT`. **Register `skill-freshness-aggregate.test.sh` and
`compound-promote.test.sh` in `test-all.sh`**; for the third orphan, register with a documented
exclusion + tracking issue (R9b) — do not silently absorb a pre-existing failure.

**1.4 Class-b: accept + ratchet.** Commit the derivation command, not the number (1.1/1.2 change it).
Record a high-water count and assert **`≤ 121`** in CI so the accept monotonically improves. Put the
accept in the **ADR** with an explicit upgrade trigger — plans get archived — and in the debt ledger.

**1.5 The lint gate — rules (a) and (c) only.**
- **(a) subshell-append** — `ARR+=(…)` in a helper invoked as `$(helper)`. Syntactic, narrow, cannot
  false-positive on cumulative-restatement files. Catches R1.
- **(c) `mktemp` + zero `trap … EXIT`**, `--changed`-scoped — the actual new-entrant gate (R8b).
- **Rule (b) cut** (R7).
- **Mandatory reason-carrying escape hatch** (`# lint-trap-ownership: ok <reason>`), following the
  template's `lint-infra-ignore` precedent. A gate without one dies at its first false positive.
- **Full 282-file census before merge**, hit list in the PR body — an 8-file two-arm test overfits.
- **Synthesized, frozen, checked-in fixtures** (`cq-test-fixtures-synthesized-only`): Phase 1 fixes
  both real subjects, so a post-merge positive arm otherwise has no subject.
- **State the enforcement level honestly** (R8c): either add `lint-bot-statuses` to
  `required-checks.txt` + the Terraform ruleset, or record in the ADR that it is advisory.

**1.6 Residue harness** for `content-publisher.sh`, modelled on the R0/R1/R2 probe in
`workspaces-luks-freeze.test.sh`. **R0 positive control mandatory** — "0 residue" is evidence only if
the counter can count; un-run reports UN-RUN, never PASS. **Two state-based synchronizations:** poll
for the tempfile window, then **wait for the trap to have run before `SIGKILL`**. The second is not
optional — bash resumes after `TERM`, so a bare `SIGTERM` lets the tail `rm -f` scrub the evidence;
and because this port defines residue as "anything under the private `TMPDIR`" (no scratch tree to
subtract), a `SIGKILL` before the trap runs counts in-flight tempfiles and **fails correctly-fixed
code**.

**Dropped:** `session-state.sh` and `workspaces-cutover.sh` (R6b — non-defects, high blast radius).
**Tracking issue:** the 3 genuine remaining class-c/d sites.

### Phase 2 — #6736 argv ceiling

**2.1 Convert** `rule-metrics-aggregate.sh`'s `--argjson enriched` and in-file siblings to `--rawfile`.

**2.2 Convert** the unbounded and the missed: `skill-security-scan` `lib.sh` + `run-scan.sh` (R16);
`inngest-doublefire-probe.sh` and `inngest-inventory.sh` (R17).

**2.3 Comment, don't assert — one exception.** For the bounded sites (R12; R13 **at the corrected
anchor**; R14 **at the producer**; R15's `--argjson prs`), add a load-bearing comment naming *why* the
site is bounded. No regression harness: it would synthesize ~30× the real fixture to prove a bound
nobody proposed removing, and fires only for the mutation imagined. The comment is what a human reads
at the moment of editing. **The exception is `PR_JSON`** (R15) — 2.5× the ceiling today, safe only via
herestring. That gets the one assertion.

**2.4 Fixture adequacy** for the 2.1/2.2 conversions, replicating `domain-model-drift.test.sh` T20: a
generator-cardinality check plus an **in-suite byte assertion** against `MAX_ARG_STRLEN` (131,072).
Carry T20's insight — **row count is not the parameter, bytes per row is**.

### Phase 3 — #6737 audit (audit-only, as ADR-126 scoped it)

ADR-126 states verbatim that it "deliberately does not widen to the cohort; **#6737 audits** each
producer's asserted-vs-consumed artifact." v1 did the widening without an ADR. v2 does not.

**3.1 The audit — diagnose before escalating.** Per handler: what the operator consumes, what the
check-in asserts, the Class A/B determination, and **two genuinely independent freshness columns** —
cron self-authorship *and* artifact frontmatter (R22b) — with the **Tier-2 defer window
(pre-2026-06-13) subtracted** and per-cron cadence stated, so a 12-day window is never read as
evidence for a monthly cron (R22c). Plus the gaps the issue does not enumerate:
`cron-roadmap-review` as a 9th site (R18), opened-but-never-merged (R23), the propagation-vs-blindness
distinction (R22c), and the corrected marker reality (R20b — the real delta is monitor colour, not
silence).

**3.2 One artifact-age detector, measured from an independent vantage.** A cohort-generic script: for
each of the **9** producers, compute days-since-last-artifact **on the default branch** and report
against a per-cron threshold derived from its own schedule.

Why measure from outside the handler, and why this instead of handler edits:

- **Every handler-local remedy shares the bug's flaw — the reporter is the subject.** R22 was found by
  measuring from outside precisely because the handler-local monitors missed it. That is the durable
  lesson, and it is the ADR-126 follow-up worth writing down.
- **Covers 9/9**, including `cron-roadmap-review`, which no handler-local mechanism reaches.
- **Catches what return-value reads structurally cannot**: the *thrown* `safe-commit-pr` path (a throw
  produces no return value); `no-changes` **streaks** (R21b); and never-merged PRs (R23), because it
  asks about the **default branch**.
- **Dissolves the Class A/B problem** — the *threshold* differs per cron, the *mechanism* does not.
- Avoids the R26 fixture hazard, the R27 missing-harness cost, and the R20b double-emit entirely.

**3.2a Substrate — GitHub Actions `schedule:`, NOT an Inngest cron (deepen-pass finding).** This is
load-bearing and counter-default. ADR-033 makes Inngest canonical for scheduled work (51 Inngest crons
vs 9 remaining GHA `scheduled-*`), and `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` will
soft-warn at `/work` time. Take the exception deliberately:

- **Putting the cohort's watchdog on Inngest reintroduces "the reporter is the subject" at the
  substrate level.** If Inngest is down or wedged, the crons stop *and* the detector stops — the exact
  correlated-failure shape that let this go unnoticed for weeks.
- **There is an exact, self-documented precedent.** Of the 4 `schedule:`-fired GHA workflows,
  `scheduled-inngest-health.yml` states in its own header: *"This workflow is the EXTERNAL probe that
  runs independently of inngest"* — written after the #5542 ~3.5h silent crash-loop.
  `scheduled-zot-restart-loop.yml` is the same class.
- **It satisfies ADR-033's stated exception**: the work is purely git/repo-scoped (it reads commit
  history on the default branch — no app context, no app secrets) and gains nothing from `step.run`
  memoization or Inngest replay.

Record this rationale **in the workflow file itself**, not only here — the hook fires on the file, and
the next reader needs the reason at the point of surprise.

**Deferred to a tracking issue, with reasons:** handler-local `livenessOk`; Class A ports; the
`retryEligible` sweep (R28 — and it must land **before** return-value consumption, not beside it); the
`inngest -> kb` C4 edge (R24). Any of these needs **its own ADR** (or an ADR-126 amendment), because
ADR-126 explicitly declined the cohort decision and recorded the RED-on-trailing-throw consequence as
an accepted negative.

**Escalation is deliberately NOT a phase deliverable.** Per UC-3, the right action is to reconcile with
#4375 after 3.1 has produced a defer-corrected diagnosis — not to file a 29th issue on a confounded
measurement.

---

## Files to Edit

**Phase 1:** `scripts/content-publisher.sh`, `scripts/skill-freshness-aggregate.sh`,
`scripts/test-all.sh`, `.github/workflows/ci.yml`.
**Phase 2:** `scripts/rule-metrics-aggregate.sh`,
`plugins/soleur/skills/skill-security-scan/scripts/{lib.sh,run-scan.sh}`,
`apps/web-platform/infra/{inngest-doublefire-probe.sh,inngest-inventory.sh}`,
`scripts/audit-bot-codeql-coverage.sh`, `scripts/learning-retrieval-bench.sh`,
`plugins/soleur/skills/drain-prs/scripts/triage-prs.sh`, plus the two `.test.sh` files.
**Phase 3:** audit doc + the detector. **No handler edits.**

## Files to Create

- `scripts/lint-trap-tempfile-ownership.py` + synthesized-fixture `.test.sh`
- `scripts/lint-orphan-test-suites.sh` (~15 lines; **no companion `.test.sh`** — AC3 mutation-proves it
  inline; a 150-line suite testing a 15-line grep reproduces the orphan problem in miniature)
- `scripts/content-publisher.test.sh` (residue harness — the existing suite uses the legacy
  `test-content-publisher.sh` prefix; do not collide)
- `scripts/cron-artifact-age.sh` + `.test.sh`
- `knowledge-base/engineering/audits/2026-07-20-cron-liveness-cohort-audit.md`
- `knowledge-base/engineering/architecture/decisions/ADR-129-jq-argv-ceiling-and-shell-cleanup-ownership.md`
  (**128, not 127** — 127 is taken on `origin/main`; this worktree was a commit behind. Provisional;
  `/ship` re-verifies, and a renumber must sweep this plan and `tasks.md`.)

---

## Acceptance Criteria

### Pre-merge (PR)

1. `content-publisher.test.sh`: **R0** positive control fails loudly when the probe is blinded; **R1**
   clean run leaves 0 residue; **R2** forced mid-run abort in a **≥2-tempfile window**, with the
   trap-fired-before-`SIGKILL` wait, leaves 0 residue — and reports **UN-RUN** (counted as failure) if
   the window never opened.
2. `lint-trap-tempfile-ownership.py` flags **synthesized frozen fixtures** for rules (a) and (c), and
   does **not** flag synthesized fixtures for the correct shapes — including a `( … )`-scoped second
   trap and a `trap - EXIT` handoff (R7). Both arms, against fixtures that survive the fix.
3. `lint-orphan-test-suites.sh` exits 0, and exits non-zero when a `run_suite` line is deleted
   (mutation-proven inline). The `lint-agents-enforcement-tags.test.sh` exclusion is explicit and
   carries a tracking-issue reference (R9b).
4. The 282-file census hit list is in the PR body; the class-b high-water assertion (`≤ 121`) is wired
   into CI; and the ADR states the gate's true enforcement level (R8c).
5. Phase-2.1/2.2 fixtures each assert their own adequacy in-suite: bytes > `MAX_ARG_STRLEN` (131,072),
   with the constant **named** at every use.
6. A test fails when `PR_JSON`'s herestring is replaced by `--argjson` (R15).
7. `bash scripts/test-all.sh` green; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
8. `scripts/cron-artifact-age.sh` reports a per-cron age for **all 9** producers, and its test proves
   it flags a synthesized stale cron **and** passes a synthesized fresh one — both arms.
9. The audit carries a per-handler row for all 8 with a **content anchor** each, **two independent
   freshness columns**, the **Tier-2 defer window subtracted**, and each cron's **cadence** stated —
   naming every row where the two producers disagree (R22b/R22c).

### Post-merge (operator)

None.

---

## Observability

```yaml
liveness_signal:
  what: "scripts/cron-artifact-age.sh — computes days-since-last-artifact on the default branch for
         all 9 committed-file cron producers, from git history rather than from the handlers
         themselves. The independent vantage is the point: every handler-local signal shares the
         defect's own flaw, that the reporter is the subject."
  cadence: "daily; per-cron threshold derived from each cron's own schedule"
  alert_target: "Sentry issue-owners -> operator"
  configured_in: "scripts/cron-artifact-age.sh + its CI schedule"

error_reporting:
  destination: "Sentry (exceptions) + Better Stack (SOLEUR_* markers, ADR-108)"
  fail_loud: true

failure_modes:
  - mode: "cron fires but persists nothing (safeCommitAndPr returns failed/no-changes)"
    detection: "artifact age exceeds the per-cron threshold"
    alert_route: "Sentry -> operator"
  - mode: "cron THROWS out of safe-commit-pr — a throw produces no return value, so return-value
           reads inside the handler structurally cannot see it"
    detection: "artifact age exceeds threshold; the git-history check is indifferent to mechanism"
    alert_route: "Sentry -> operator"
  - mode: "Class B cron emits no-changes for a long STREAK (indistinguishable from healthy per-run)"
    detection: "artifact age exceeds a deliberately looser Class-B threshold"
    alert_route: "Sentry -> operator  # closes R21b"
  - mode: "PR opened but auto-merge never completed (R23, observed on seo-aeo #5026)"
    detection: "age measured on the DEFAULT BRANCH, so an unmerged branch never counts"
    alert_route: "Sentry -> operator"
  - mode: "cron-roadmap-review (9th site, outside MIGRATED_PROMPT and every handler-local mechanism)"
    detection: "same detector — it enumerates producers, not handler shapes"
    alert_route: "Sentry -> operator"
  - mode: "content-publisher.sh leaks 6 tempfiles per run on a long-lived host"
    detection: "content-publisher.test.sh R1/R2 residue cases, registered in test-all.sh"
    alert_route: "CI red on the PR"
  - mode: "a new script introduces subshell-append, or mktemp with no trap"
    detection: "lint-trap-tempfile-ownership.py rules (a) and (c)"
    alert_route: "CI red on the PR (advisory unless lint-bot-statuses is made required — R8c)"
  - mode: "a new scripts/*.test.sh is never registered (the orphan class)"
    detection: "lint-orphan-test-suites.sh"
    alert_route: "CI red on the PR"
  - mode: "a jq accumulator crosses MAX_ARG_STRLEN as its corpus grows"
    detection: "per-site fixtures asserting bytes > 131072 pre-fix"
    alert_route: "CI red on the PR"

logs:
  where: "Better Stack (SOLEUR_* markers from the app container, Vector Source 3
          app_container_journald); Sentry for exceptions"
  retention: "per existing Better Stack plan retention"

discoverability_test:
  command: "bash scripts/cron-artifact-age.sh --all"
  expected_output: "9 rows, one per committed-file cron producer, each with days-since-last-artifact
                    on the default branch, its cadence, and a PASS/STALE verdict. Readable with no
                    credential and no dashboard. NOTE: v1 asserted here that 7 crons 'emit nothing at
                    all' to Better Stack — that was FALSE (R20b): emitCronPersistResult fires from
                    inside safeCommitAndPr for every caller. This command deliberately depends on git
                    history rather than on markers, so it cannot inherit that error."
```

No `ssh` appears in any verification path.

---

## Architecture Decision (ADR/C4)

### ADR

**ADR-129 — the jq argv ceiling, plus shell cleanup ownership.** Scoped down from v1's four
invariants after review showed v1's stated rationale ("they share one enforcement mechanism") was
**factually false** — the argv rule is enforced by per-site tests, not by any lint.

Core decision: **a jq binding whose payload grows with a corpus must use `--rawfile`/`--slurpfile`,
never `--argjson`.** `MAX_ARG_STRLEN` is 131,072 B *per argument*, independent of `ARG_MAX`
(2,097,152). Measured constant, rejected alternative (`--slurpfile`'s silent undercount), a live HTTP
500 (#5523), and a re-introduction one line after the fix (R17).

Secondary, lint-enforced: **cleanup arrays are appended in the parent scope, never inside `$( )`**;
**`mktemp` without an owning trap is gated for new files**. Carries the class-b accept with an upgrade
trigger, and **states the gate's true enforcement level** (advisory unless `lint-bot-statuses` is made
a required check — R8c).

`## Alternatives Considered`: an AGENTS.md rule (**declined — 100 bytes of headroom, R25 corrected**);
repo-wide shellcheck (no rule for either defect); converting bounded argv sites (churn, R12); and
**rule (b), trap-replacement-by-superset (rejected — incoherent about subshell scope and
`trap - EXIT`, R7)**.

**No ADR for cohort widening, because there is no cohort widening.** ADR-126 explicitly declined that
decision and scoped #6737 as an audit. If the deferred handler-local work is ever taken up, it needs
its own ADR or an ADR-126 amendment — it carries an accepted negative (a trailing persistence throw
posts RED where it was GREEN, #5728) that must be recorded before being applied to 7 more handlers.

### C4 views

**No C4 edit in this PR.** Enumeration against all three files (`model.c4` 539 lines, `views.c4` 62,
`spec.c4` 54): external human actors — `founder` already modeled; vendors — GitHub, Sentry, Better
Stack already modeled; containers/data stores — `inngest`, `kb` already modeled; access relationships
— **one genuinely missing** (R24).

The correct missing edge is **`inngest -> kb`**, not v1's `inngest -> github`: all nine inbound `kb`
edges come from inside the plugin as local `File I/O`, so the model asserts the KB is only ever
operator-written, when in fact a scheduled server-side container authors committed KB content
unattended. Note **no `views.c4` edit is required** — it enumerates elements, both endpoints are
already included, and LikeC4 renders the relationship automatically (which is why v1's "the view
renders" AC was vacuous). The edge ships with the Phase 3 follow-up that implements what it documents.

---

## Infrastructure (IaC)

**None.** No server, service, cron host, secret, DNS record, cert, firewall rule or vendor account is
introduced or reconfigured. Phases 1-2 edit shell scripts; Phase 3 adds a read-only git-history script
and a markdown audit. The Sentry cron monitors in `infra/sentry/cron-monitors.tf` are untouched. Phase
2.8's routing gate was reviewed and does not apply.

---

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` (61 open) against every path in
`## Files to Edit`. Two matches, both **Acknowledge**:

- **#3595** — YAML-aware parser for `audit-bot-codeql-coverage.sh`. Different concern (parser
  correctness vs. an argv bounding comment).
- **#3593** — post-synthetic-checks composite extraction, matching `skill-security-scan`. Concerns
  composite extraction, not the argv bindings 2.2 converts. Already ADR-deferred.

---

## Domain Review

**Domains relevant:** Engineering, Operations, Marketing, Product

### Engineering
**Status:** reviewed. Principal risks were a lint rule that false-fires (rule (b) cut, escape hatch
mandatory, full census pre-merge), a gate that does not gate its accepted class (rule (c)), and a
sweep whose blast radius is set by its worst-diagnosed member (R6b — two sites dropped).

### Operations
**Status:** reviewed. The decisive finding is E2/UC-3: the escalation channel this plan would have
used has a **measured 0% success rate on this exact finding** (#4375, 57 days; 28-deep queue).

### Marketing
**Status:** reviewed. Correcting v1's "substantially inert", which was both overstated and
understated. **Measured:** competitive intel is **fresh (16d)**; brand guide and marketing-strategy are
within cadence; social distribution never stopped (`content-publisher` is not in the cohort). But
`content-strategy.md` has breached its **weekly** SLA 6×, `campaign-calendar.md` is 56d stale and wrong
in both directions, and article output is **zero for 35 days**.

**The failure is propagation, not blindness** — the intel landed; the crons that walk it are dark. The
healthy distribution arm **masks** the dark generation arm, which is more dangerous than uniform
silence. GTM recovery order is not the engineering order: `campaign-calendar` first, then
**`content-generator`** (the only cron whose deferral cost accrues *irreversibly*), then the SEO pair.

**Do not backfill the ~6 missing articles** — retroactively-dated catch-up content signals the outage
publicly, dilutes quality, and search rewards sustained cadence over spikes. Take the loss.

**E1 (escalated, out of scope):** the live Polsia figure defect in published JSON-LD — 8 files, its own
PR, does not wait on cron restoration.

### Product
**Status:** reviewed (CPO). Two challenges recorded rather than applied: Phase 3 is not a P2 chore
(**UC-2**) and escalation must reconcile with #4375 (**UC-3**). CPO also measured the roadmap itself as
2 review cycles dark with count drift — the artifact used to *notice* problems is one of the dark
artifacts. Product/UX Gate: no UI-surface file in either Files list; mechanical override did not fire.

**GDPR gate:** not invoked — no schema, migration, auth flow, API route or `.sql`; markers carry no
personal data; none of triggers (a)-(d) fire.

---

## Research Insights (deepen pass, 2026-07-20)

The plan had already been through an 8-agent review, so this pass focused on the **verification
classes that produced v1's errors** rather than on more opinion.

### Citation verification — all clean

Every cited PR, issue and commit was resolved live (`gh pr/issue view`, `git rev-parse`,
`git merge-base --is-ancestor origin/main`) rather than trusted from context:

- **15 PR/issue citations** all resolve and match their claimed role. Two worth calling out because
  the plan's argument depends on their *state*, not just their existence: **#5026 is `CLOSED`, not
  `MERGED`** — which is exactly what R23 ("opened but never merged") asserts; and **#4375 is `OPEN`**
  at 57 days, which is what makes UC-3's "0% success rate" claim measurable rather than rhetorical.
- **2 commit attributions verified by diff, not by message.** `5ea440f4c` genuinely contains
  `-export const TIER2_DEFERRED_CRONS ... = new Set([` → `+ ... = new Set([])` dated **2026-06-13**,
  confirming R22c's defer-window boundary. `5b2c1922d` genuinely touches
  `scheduled-content-publisher.yml`, confirming R2. Both are ancestors of `origin/main`.

This matters because v1's failure mode was precisely an attribution that *read* plausible. The
`git show <sha> | grep` form is what separates "the commit exists" from "the commit did the thing".

### Precedent-diff gate (Phase 4.4)

Every pattern-bound behaviour in this plan has an in-repo precedent, and each is cited at its
anchor rather than described: the lint analyzer follows `lint-infra-no-human-steps.py` (analyzer +
`--changed --base` + `.test.sh` + `test-all.sh` registration + `ci.yml` step); the residue harness
follows `workspaces-luks-freeze.test.sh`'s R0/R1/R2; the argv conversion follows
`rule-metrics-aggregate.sh`'s own in-file `--rawfile` site and `domain-model-drift.sh`'s comment
block; the fixture-adequacy self-check follows `domain-model-drift.test.sh` T20. **No pattern here
is novel** — which is the point, and is why the plan's residual risk is concentrated in the two
places it deviates (the detector's substrate, below, and the residue harness's missing scratch tree).

### Scheduled-work substrate — the one counter-default choice

The scheduled-work precedent check (Phase 4.4) surfaced the plan's only genuine architectural
decision, and it points *away* from the canonical answer. See **3.2a**: the detector belongs on GitHub
Actions precisely because Inngest is the substrate under observation. Measured: 51 Inngest crons vs 9
GHA `scheduled-*` (4 `schedule:`-fired), of which `scheduled-inngest-health.yml` and
`scheduled-zot-restart-loop.yml` are self-documented external probes. This is a real exception with a
real precedent — not an escape from ADR-033.

### Gates run

Phase 4.6 (User-Brand Impact) **pass** — section present, 23 non-blank lines, valid threshold.
Phase 4.7 (Observability) **pass** — all 5 fields present, no placeholder values, no `ssh` in
`discoverability_test.command`. Phase 4.8 (PAT-shaped variables) **pass** — no matches.
Phase 4.9 (UI wireframe) **skipped** — no UI-surface file in either Files list.
Phase 4.5 (network-outage) and 4.55 (downtime/cutover) **not triggered** — no SSH/connectivity
symptom, and no host-replace, lock-taking DDL, or router change.

---

## Risks & Sharp Edges

1. **A sweep's blast radius is set by its worst-diagnosed member.** v1 would have touched a
   session-start hooks library and a prod LUKS cutover script on two **false** diagnoses (R6b). Verify
   each site's runtime behaviour, not its textual shape, before adding it to a sweep.
2. **A lint rule that fires on correct code is disabled within a week.** Hence rule (b) cut, a mandatory
   reason-carrying escape hatch, and a 282-file census rather than an 8-file test tuned to the corpus.
3. **A gate with no required-check registration has no teeth** (R8c). State the enforcement level
   honestly rather than claiming it beats an AGENTS.md rule.
4. **Pre-fix ACs go vacuous the moment the fix lands.** Fixtures must be **synthesized and frozen**
   (`cq-test-fixtures-synthesized-only`), never copies of the real subjects.
5. **A bare `SIGTERM` masks the leak**, and — with no scratch tree to subtract — a `SIGKILL` issued
   *before* the trap runs fails **correctly fixed** code. Both waits are state-based.
6. **Row count is not the argv parameter — bytes per row is.** 1,200 minimal rows = 75,782 B, under the
   ceiling, passing on unmodified code.
7. **`retryEligible: false` is not a no-op**, and it is a **prerequisite** for return-value consumption,
   not a peer — lowering `heartbeatOk` on a run that also throws triggers an Inngest replay that
   **re-spawns the Claude agent**.
8. **The parity regex cannot see post-call additions** (measured headroom 736/800), so "parity stayed
   green" proves only that `heartbeatOk` was not renamed.
9. **Cron self-authorship ≠ artifact currency, and a 12-day window cannot measure a monthly cron**
   (R22b/R22c). Any staleness claim must carry two genuinely independent producers and state cadence.
10. **ADR-129, not 127** — 127 is taken on `origin/main`. Re-verify at ship; a renumber must sweep this
    plan and `tasks.md`.
11. **`emitCronPersistResult` already fires for every caller** (R20b). Do not add handler-side emission
    — it double-emits and makes any emitter-count guard vacuous.

---

## Non-Goals

- **Fixing all 121 class-b files** — documented accept + ratchet.
- **`session-state.sh` and `workspaces-cutover.sh`** — non-defects (R6b); actively harmful to "fix".
- **Handler-local liveness, Class A ports, the `retryEligible` sweep, the `inngest -> kb` C4 edge** —
  tracking issue; each needs its own ADR per ADR-126's explicit scoping.
- **Filing a new escalation issue** — reconcile with #4375 after a defer-corrected diagnosis (UC-3).
- **The Polsia figure correction (E1)** — its own PR.
- **The raw claude-eval stderr / Better Stack `redactToken` issue** — out of scope by instruction; a
  pre-existing P1-HIGH in a different subsystem. Its issue stays open and untouched.
- **The community-monitor liveness-vs-dedup predicate asymmetry** — out of scope by instruction;
  contested design. Its issue stays open and untouched.
- **Repo-wide shellcheck**, and **converting bounded argv sites** — rejected in ADR-129.
- **Backfilling the ~6 missing articles** — resume forward cadence only.
