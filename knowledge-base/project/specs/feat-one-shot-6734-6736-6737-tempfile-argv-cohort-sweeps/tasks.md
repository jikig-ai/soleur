# Tasks — feat-one-shot-6734-6736-6737-tempfile-argv-cohort-sweeps

Derived from
[`2026-07-20-chore-tempfile-ownership-argv-ceiling-and-cron-liveness-cohort-sweeps-plan.md`](../../plans/2026-07-20-chore-tempfile-ownership-argv-ceiling-and-cron-liveness-cohort-sweeps-plan.md)
**v2** (post 8-agent plan review). Issues: #6734, #6736, #6737.

> **Read the plan's `### What changed from v1` table before starting.** v2 **retracts three v1
> claims**. Two files v1 named as defects are non-defects that are *dangerous to touch*
> (`session-state.sh`, `workspaces-cutover.sh` — R6b), and v1's marker work would have
> **double-emitted** (R20b). Do not reintroduce them from the issue bodies.

---

## Phase 0 — Preconditions

- [ ] 0.1 Re-verify the next free ADR ordinal against `origin/main` (**128 at plan time; 127 is
      taken**). If it moves, sweep the plan, this file, and every AC naming it.
- [ ] 0.2 Confirm `lint-agents-enforcement-tags.test.sh` still fails on `main`
      (`Total: 9 Pass: 7 Fail: 2`). It is pre-existing and unrelated; task 1.2.3 depends on the
      disposition, not on fixing it.
- [ ] 0.3 Re-run the argv bisect on the build host to confirm `MAX_ARG_STRLEN` = 131,072
      (131,071 passes, 131,072 fails). Do not inherit the number.

## Phase 1 — #6734 tempfile ownership

### 1.1 `scripts/content-publisher.sh` — subshell-append (highest severity)
- [ ] 1.1.1 Write the failing residue case first (`cq-write-failing-tests-before`).
- [ ] 1.1.2 Move the `_TMPFILES+=("$f")` append out of `make_tmp` to the **parent scope** at all
      6 call sites.
- [ ] 1.1.3 Add the `((${#_TMPFILES[@]} > 0))` guard — load-bearing under `set -u` on older bash,
      with the reason stated inline.
- [ ] 1.1.4 Why-comment citing #6734 and the command-substitution mechanism.

### 1.2 `scripts/skill-freshness-aggregate.sh` — all three leak windows
- [ ] 1.2.1 Single owning trap covering `INVOCATIONS_TMPDIR` **and** `$OUT.tmp`.
- [ ] 1.2.2 Remove the second `trap … EXIT` and the `trap - EXIT`.
- [ ] 1.2.3 Register `skill-freshness-aggregate.test.sh` **and** `compound-promote.test.sh` in
      `scripts/test-all.sh`. For `lint-agents-enforcement-tags.test.sh`, add an **explicit
      documented exclusion + tracking issue** — do not absorb a pre-existing failure silently.

### 1.4 Class-b: accept + ratchet
- [ ] 1.4.1 Commit the derivation command (not the number — 1.1/1.2 change it).
- [ ] 1.4.2 Write the high-water count file and assert `≤ 121` in CI.
- [ ] 1.4.3 Record the accept in the **ADR** with an explicit upgrade trigger, and in the debt ledger.

### 1.5 The lint gate — rules (a) and (c) only
- [ ] 1.5.1 Author **synthesized, frozen** fixtures first (`cq-test-fixtures-synthesized-only`) —
      positive for (a) and (c), negative for a `( … )`-scoped second trap and a `trap - EXIT`
      handoff. The real subjects are fixed in Phase 1, so they cannot serve as fixtures.
- [ ] 1.5.2 Implement rule **(a)** subshell-append.
- [ ] 1.5.3 Implement rule **(c)** `mktemp` + zero trap, `--changed`-scoped. **This is the rule that
      actually gates the accepted class** — without it, 1.4 accepts a pile it does not fence.
- [ ] 1.5.4 Implement the **mandatory reason-carrying escape hatch**
      (`# lint-trap-ownership: ok <reason>`), per the `lint-infra-ignore` precedent.
- [ ] 1.5.5 Run the **full 282-file census**; paste the hit list into the PR body.
- [ ] 1.5.6 Wire into `ci.yml`'s `lint-bot-statuses`; register the `.test.sh` in `test-all.sh`.
- [ ] 1.5.7 Decide and **state** enforcement level: add the job to `required-checks.txt` + the
      Terraform ruleset, or record in the ADR that it is advisory. Do not claim teeth it lacks.
- [ ] 1.5.8 `scripts/lint-orphan-test-suites.sh` (~15 lines, **no companion `.test.sh`**).

### 1.6 Residue harness — `scripts/content-publisher.test.sh`
- [ ] 1.6.1 **R0 positive control** — must fail loudly when the probe is blinded.
- [ ] 1.6.2 R1 clean run → 0 residue.
- [ ] 1.6.3 R2 forced mid-run abort in a **≥2-tempfile window**. **Two state-based waits**: poll for
      the window, then **wait for the trap to have run before `SIGKILL`**. Omitting the second makes
      R2 fail on *correctly fixed* code, because residue here is "anything under the private
      `TMPDIR`" with no scratch tree to subtract.
- [ ] 1.6.4 Un-opened window reports **UN-RUN** (counted as failure), never PASS.
- [ ] 1.6.5 Register in `test-all.sh` (do not collide with legacy `test-content-publisher.sh`).

### 1.x Deferred
- [ ] 1.x.1 Tracking issue for the 3 genuine remaining class-c/d sites
      (`learning-retrieval-bench.sh`, `weekly-analytics.sh`, `constraint-scaffold.sh`).
- [ ] 1.x.2 **Do NOT touch** `session-state.sh` or `workspaces-cutover.sh` (R6b).

## Phase 2 — #6736 argv ceiling

### 2.1–2.2 Convert (4 sites)
- [ ] 2.1.1 `rule-metrics-aggregate.sh` `--argjson enriched` → `--rawfile`, lifting the in-file
      precedent; plus in-file siblings.
- [ ] 2.2.1 `skill-security-scan/scripts/lib.sh` + `run-scan.sh` (the only genuinely unbounded site
      in the issue's list).
- [ ] 2.2.2 `apps/web-platform/infra/inngest-doublefire-probe.sh` (issue missed it).
- [ ] 2.2.3 `apps/web-platform/infra/inngest-inventory.sh` (issue missed it; its sibling already
      carries the #5523 comment).

### 2.3 Comment, don't assert — one exception
- [ ] 2.3.1 `learning-retrieval-bench.sh` — comment the `.[0:20]` cap and the 7-seed array as
      load-bearing. **No conversion, no harness.**
- [ ] 2.3.2 `audit-bot-codeql-coverage.sh` — comment at the **corrected anchor**
      (`--argjson drift_entries`, one of the two lines the issue listed). **v1 pointed at `:275`,
      which does not exist.** Name `--limit 100` as the bound.
- [ ] 2.3.3 `skill-freshness-aggregate.sh` — comment at the **producer** (`jq -s group_by(.skill)`),
      not the `--argjson` consumer, explaining the collapse-to-94-skills bound.
- [ ] 2.3.4 `triage-prs.sh` — comment `--limit 200`, **and** the `PR_JSON` herestring invariant.
- [ ] 2.3.5 **The one assertion**: a test that fails when `PR_JSON`'s herestring is replaced by
      `--argjson` (328,940 B at 17 PRs — 2.5× the ceiling today).

### 2.4 Fixture adequacy
- [ ] 2.4.1 For each 2.1/2.2 conversion: generator-cardinality check **plus** an in-suite byte
      assertion `> MAX_ARG_STRLEN`. Write the constant **named** at every use.
- [ ] 2.4.2 Verify each fixture is **production-shaped**, not minimal — 1,200 minimal rows measure
      75,782 B, under the ceiling, and pass on unmodified code.

## Phase 3 — #6737 audit only

- [ ] 3.1.1 Write `knowledge-base/engineering/audits/2026-07-20-cron-liveness-cohort-audit.md`:
      per-handler asserted-vs-consumed rows for all 8, each with a **content anchor**.
- [ ] 3.1.2 Add **two genuinely independent freshness columns** — cron self-authorship *and*
      artifact frontmatter — and name every row where they disagree.
- [ ] 3.1.3 **Subtract the Tier-2 defer window** (pre-2026-06-13, when 6 of 8 skipped the spawn and
      posted `ok:true`) and state each cron's **cadence**, so a 12-day window is never read as
      evidence about a monthly cron.
- [ ] 3.1.4 Record the four gaps the issue does not enumerate: `cron-roadmap-review` (9th site),
      opened-but-never-merged (#5026), propagation-vs-blindness, and the corrected marker reality
      (the real delta is monitor **colour**, not silence).
- [ ] 3.2.1 `scripts/cron-artifact-age.sh` — days-since-last-artifact **on the default branch** for
      all **9** producers, from git history, with a per-cron threshold from its own schedule.
- [ ] 3.2.2 `.test.sh` proving **both arms**: flags a synthesized stale cron, passes a synthesized
      fresh one. Register in `test-all.sh`.
- [ ] 3.3.1 Tracking issue for the deferred handler-local work (`livenessOk`, Class A ports,
      `retryEligible`, the `inngest -> kb` C4 edge) — noting each needs **its own ADR**, and that
      `retryEligible: false` must land **before** return-value consumption, never beside it.
- [ ] 3.x **Do NOT** file a new `action-required` issue (UC-3) and **do NOT** add handler-side
      `emitCronPersistResult` (R20b — it already fires from inside the helper).

## Phase 4 — ADR + close-out

- [ ] 4.1 Write `ADR-128-jq-argv-ceiling-and-shell-cleanup-ownership.md` — core argv decision,
      secondary lint-enforced cleanup-ownership rules, the class-b accept + upgrade trigger, the
      honest enforcement level, and `## Alternatives Considered` (AGENTS.md rule declined at 100 B
      headroom; shellcheck; converting bounded sites; rule (b)).
- [ ] 4.2 Full suite: `bash scripts/test-all.sh`; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 4.3 Verify every `knowledge-base/` path cited in the plan resolves (run from repo root).
- [ ] 4.4 Confirm `decision-challenges.md` (UC-1/2/3, E1, E2) is carried into the PR body by `/ship`.
- [ ] 4.5 PR body uses `Closes #6734`, `Closes #6736`, `Closes #6737`.
