---
feature: feat-one-shot-6713-6714-6720-tempfile-argv-digest-monitor
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-19-fix-tempfile-leak-argv-ceiling-and-digest-liveness-monitor-plan.md
issues: [6713, 6714, 6720]
---

# Tasks — #6713 tempfile leak, #6720 jq argv ceiling, #6714 digest liveness monitor

Derived from the finalized (post-review) plan. **Read the plan's Research Reconciliation table
before starting** — it reverses the fix prescribed in issue #6713 and refines the ones in #6720
and #6714, all on measured evidence.

The three phases are independent and share no files. They may be implemented in any order.

---

## 1. #6713 — tempfile leak (smallest, do first)

- [ ] **1.1** Read `apps/web-platform/infra/workspaces-luks-freeze.test.sh` and
      `apps/web-platform/infra/workspaces-luks-harness.sh` in full before editing.
- [ ] **1.2** Change `:101` `BIGF="$(mktemp)"` → `BIGF="$(mktemp -p "$RUN_SCRATCH" bigf.XXXXXX)"`.
- [ ] **1.3** Change `:331` `mut="$(mktemp --suffix=.sh)"` →
      `mut="$(mktemp -p "$RUN_SCRATCH" mut.XXXXXX.sh)"`. Match the sibling form at
      `workspaces-luks-staging.test.sh:413, 802, 1004`.
- [ ] **1.4** Add a why-comment at both sites: a `trap … EXIT` here would REPLACE the harness
      trap at `workspaces-luks-harness.sh:42` and leak the whole `RUN_SCRATCH` tree. Do not add one.
- [ ] **1.5** Add residue self-check cases **inside the same suite** (it is already wired at
      `.github/workflows/infra-validation.yml:395`): re-invoke in a subshell under a private
      `TMPDIR`; assert 0 residue on a clean run, and 0 residue after a forced `SIGTERM` during
      the mutation block (a ≥2-tempfile window).
- [ ] **1.6** Verify: `grep -c 'mktemp' …` → 2; `grep -c 'mktemp -p "$RUN_SCRATCH"' …` → 2;
      `grep -c '^\s*trap ' …` → 0; harness trap grep → 1. *(AC-1, AC-2, AC-3)*
- [ ] **1.7** Run the suite: `0 failed`, pass count ≥ 58. *(AC-5)*
- [ ] **1.8** File the tracked tempfile sweep issue: the 2 confirmed class-c/class-d instances
      (`scripts/content-publisher.sh:69-77` + 6 `$(make_tmp)` sites;
      `scripts/skill-freshness-aggregate.sh:101` vs `:270`), the 121 class-(b) no-trap files, and
      the absence of any lint gate. Link from the PR body. *(AC-6)*

## 2. #6720 — jq argv ceiling

- [ ] **2.1** Read `scripts/domain-model-drift.sh` in full, especially `emit_extract_json()`
      (`:60-109`) and its `drift`-mode caller at `:127`.
- [ ] **2.2** Capture a pre-fix output baseline for the byte-identity check (AC-9).
- [ ] **2.3** Restructure `:96-108` to a single `jq -Sn … --rawfile facts_tsv --rawfile blind_tsv`,
      moving the existing jq programs into it. Preserve: the unsupported-stack early return
      (`:64-68`) and the secret-scan fail-close (`:91-94`) — **the spool write must come after
      the scan**.
- [ ] **2.4** Cleanup: allocate the two spool files in the **caller** (main-shell scope) and pass
      the paths in, OR `rm -f` on every return path including the `exit 3` at `:93`.
      **Do NOT append to a parent `_TMPFILES` from inside the function** — `drift` mode calls it
      via `$( )`, so the append is lost to the subshell and the parent EXIT trap does not fire.
      *(This is the class-d bug the plan diagnoses elsewhere; plan v1 walked into it.)*
- [ ] **2.5** If a top-level trap is introduced, migrate `write_row()` (`:235`) onto it — its
      `trap - EXIT` at `:246` would otherwise clear the new trap. Do not half-migrate.
- [ ] **2.6** Verify counts are exact: `extract | jq '{f:(.facts|length),b:(.blind_spots|length)}'`
      → `{"f":350,"b":54}`. A non-emptiness assertion is insufficient. *(AC-8)*
- [ ] **2.7** Verify byte-identity against the 2.2 baseline. *(AC-9)*
- [ ] **2.8** Add a >131,072 B fixture to `scripts/domain-model-drift.test.sh` (~1200 synthetic
      rows); assert exit 0 + correct count, **and** demonstrate the same fixture fails on pre-fix
      code with `Argument list too long`. The negative half is what makes it non-vacuous. *(AC-10)*
- [ ] **2.9** Run `bash scripts/domain-model-drift.test.sh`. *(AC-11)*
- [ ] **2.10** File the argv sibling-sweep issue (ranked list is in plan Phase 2.5). Measure each
      candidate against 131,072 B — item count is not a proxy for argv bytes. *(AC-27)*

## 3. #6714 — digest liveness monitor

- [ ] **3.1** Read `cron-community-monitor.ts`, `_cron-safe-commit.ts`, and `_cron-shared.ts`
      around every line the plan cites. The evidence pull is already done — see the plan's
      H1–H12 table. **H9 stays UNKNOWN; do not manufacture a verdict.**
- [ ] **3.2** Widen `SafeCommitResult`'s `"committed"` arm with **optional** `paths?: string[]`
      (from `matched` at `_cron-safe-commit.ts:495`) and `resumed?: true` on the replay-resume
      branch (`:444-455`). Optional, not required — ~38 consumers.
- [ ] **3.3** Run the `hr-type-widening-cross-consumer-grep` three-pattern sweep, then
      `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. *(AC-13)*
- [ ] **3.4** **Assign** the `safe-commit-pr` step's return value at `cron-community-monitor.ts:652`
      — it is discarded today. This is the primary defect. *(AC-14)*
- [ ] **3.5** Add `livenessOk`, derived per the plan's four-arm table (committed+path → GREEN;
      committed+resumed → GREEN; no-changes/failed → RED; committed without the path → RED).
      Feed it to the Sentry check-in at `:708-741`.
- [ ] **3.6** **Do NOT rename `heartbeatOk`.** Verify
      `grep -c 'if (heartbeatOk && !spawnResult.abortedByTimeout)' …` → 1 and that
      `cron-safe-commit-parity.test.ts` passes unmodified. *(AC-15, R20)*
- [ ] **3.7** Close the dedup early-return GREEN path (`:437-447`): before returning GREEN,
      verify the dated digest is committed on the default branch; if not, spawn instead. *(AC-18)*
- [ ] **3.8** Add the five markers at their named sites (plan 3.3 table). Marker 1 has **three**
      sites in `_cron-safe-commit.ts` (`:395`, `:547`, `:805`) — assert per-site, and assert the
      emitted field set, not string presence. *(AC-20)*
- [ ] **3.9** Do **not** invert `:669-671`. Emit marker 1 with `status=failed` from the catch and
      leave retry semantics untouched — inverting causes a replay onto a deleted `spawnCwd` and a
      false `workspace-lost` Sentry event. *(plan 3.5b)*
- [ ] **3.10** Read the four suites that already exercise `isRealScheduledDigest`; confirm the
      `_cron-shared.ts:937` body-exclusion arm is genuinely unpinned before adding the
      characterization test. *(AC-19)*
- [ ] **3.11** Correct the stale Tier-2 comment at `:393-397`. *(AC-22)*
- [ ] **3.12** Tests: the four `livenessOk` arms, the resumed carve-out, the dedup GREEN-path
      close, and each marker. *(AC-16, AC-17, AC-18, AC-20)*
- [ ] **3.13** `terraform plan` on `apps/web-platform/infra/sentry/` → no diff for
      `sentry_cron_monitor.scheduled_community_monitor`. *(AC-21)*
- [ ] **3.14** File the cohort-audit follow-up issue (plan 3.8). *(AC-27)*

## 4. ADR + C4

- [ ] **4.1** Write `ADR-126-cron-liveness-must-assert-the-consumed-artifact.md`. Record: the
      persistence/liveness split; the four GREEN-with-no-artifact paths and **which two remain
      marker-only**; and the cohort-parity decision (why renaming was rejected). Re-verify the
      ordinal against `origin/main` — it is provisional.
- [ ] **4.2** Read all three of `model.c4`, `views.c4`, `spec.c4` in full. Enumerate external
      actors, external systems, data stores, and changed access relationships. Expected outcome
      is "no C4 impact" — but the conclusion must cite the enumeration. Edit + run
      `c4-code-syntax.test.ts` / `c4-render.test.ts` if a gap is found. *(AC-24)*

## 5. Exit

- [ ] **5.1** `bash scripts/test-all.sh` green. *(AC-25)*
- [ ] **5.2** PR body: `Closes #6713`, `Closes #6714`, `Closes #6720`; the H1–H12 evidence table
      with raw excerpts and H9 as UNKNOWN; the corrected #6713 causal chain (R4) and #6714 framing
      (R13). *(AC-12, AC-26)*
- [ ] **5.3** Confirm all three follow-up issues are filed and linked. *(AC-27)*
- [ ] **5.4** Surface `decision-challenges.md` (DC-1, marker 4 retained against review
      recommendation) for the operator.
