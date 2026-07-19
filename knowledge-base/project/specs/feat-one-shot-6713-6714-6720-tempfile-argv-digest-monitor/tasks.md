---
feature: feat-one-shot-6713-6714-6720-tempfile-argv-digest-monitor
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-19-fix-tempfile-leak-argv-ceiling-and-digest-liveness-monitor-plan.md
issues: [6713, 6714, 6720]
---

# Tasks — #6713 tempfile leak, #6720 jq argv ceiling, #6714 digest liveness monitor

Derived from the finalized (post-review, post-deepen) plan. Tasks intentionally carry NO
numeric `AC-N` back-references — the plan's AC numbering shifted twice during review and the
refs silently drifted. Each task states its own acceptance condition; cross-check against the
plan's Acceptance Criteria section by description. **Read the plan's Research Reconciliation table
before starting** — it reverses the fix prescribed in issue #6713 and refines the ones in #6720
and #6714, all on measured evidence.

The three phases are independent and share no files. They may be implemented in any order.

---

## 1. #6713 — tempfile leak (smallest, do first)

- [x] **1.1** Read `apps/web-platform/infra/workspaces-luks-freeze.test.sh` and
      `apps/web-platform/infra/workspaces-luks-harness.sh` in full before editing.
- [x] **1.2** Change `:101` `BIGF="$(mktemp)"` → `BIGF="$(mktemp -p "$RUN_SCRATCH" bigf.XXXXXX)"`.
- [x] **1.3** Change `:331` `mut="$(mktemp --suffix=.sh)"` →
      `mut="$(mktemp -p "$RUN_SCRATCH" mut.XXXXXX.sh)"`. Match the sibling form at
      `workspaces-luks-staging.test.sh:413, 802, 1004`.
- [x] **1.4** Add a why-comment at both sites: a `trap … EXIT` here would REPLACE the harness
      trap at `workspaces-luks-harness.sh:42` and leak the whole `RUN_SCRATCH` tree. Do not add one.
- [x] **1.5** Add residue self-check cases **inside the same suite** (already wired at
      `.github/workflows/infra-validation.yml:395`): re-invoke in a subshell under a private
      `TMPDIR`; assert 0 residue on a clean run, and 0 residue after a forced `SIGTERM` during
      the mutation block (a ≥2-tempfile window).
- [x] **1.5a** Add a **recursion guard** (env sentinel) — the suite has none, and a self-check
      that re-invokes the suite recurses forever without one. Make sure the outer summary parse
      is not confused by the inner run's own `N passed, N failed` line.
- [x] **1.5b** Synchronize the SIGTERM on **file existence, not elapsed time**. Poll for the MUT
      file; a fixed `sleep` lands outside the window on a loaded runner and the test then passes
      for the wrong reason (nothing was live, so nothing leaked).
- [x] **1.6** Verify: `grep -c 'mktemp' …` → 2; `grep -c 'mktemp -p "$RUN_SCRATCH"' …` → 2;
      `grep -c '^\s*trap ' …` → 0; harness trap grep → 1.
- [x] **1.7** Run the suite: `0 failed`, pass count ≥ 58.
- [x] **1.8** (filed: #6734) File the tracked tempfile sweep issue: the 2 confirmed class-c/class-d instances
      (`scripts/content-publisher.sh:69-77` + 6 `$(make_tmp)` sites;
      `scripts/skill-freshness-aggregate.sh:101` vs `:270`), the 121 class-(b) no-trap files, and
      the absence of any lint gate. Link from the PR body.

## 2. #6720 — jq argv ceiling

- [x] **2.1** Read `scripts/domain-model-drift.sh` in full, especially `emit_extract_json()`
      (`:60-109`) and its `drift`-mode caller at `:127`.
- [x] **2.2** Capture a pre-fix output baseline for the byte-identity check.
- [x] **2.3** Restructure `:96-108` to a single `jq -Sn … --rawfile facts_tsv --rawfile blind_tsv`,
      moving the existing jq programs into it. Preserve: the unsupported-stack early return
      (`:64-68`) and the secret-scan fail-close (`:91-94`) — **the spool write must come after
      the scan**.
- [x] **2.4** Cleanup: allocate the two spool files in the **caller** (main-shell scope) and pass
      the paths in, OR `rm -f` on every return path including the `exit 3` at `:93`.
      **Do NOT append to a parent `_TMPFILES` from inside the function** — `drift` mode calls it
      via `$( )`, so the append is lost to the subshell and the parent EXIT trap does not fire.
      *(This is the class-d bug the plan diagnoses elsewhere; plan v1 walked into it.)*
- [x] **2.5** If a top-level trap is introduced, migrate `write_row()` (`:235`) onto it — its
      `trap - EXIT` at `:246` would otherwise clear the new trap. Do not half-migrate.
- [x] **2.6** Verify counts are exact: `extract | jq '{f:(.facts|length),b:(.blind_spots|length)}'`
      → `{"f":350,"b":54}`. A non-emptiness assertion is insufficient.
- [x] **2.7** Verify byte-identity against the 2.2 baseline.
- [x] **2.8** Add a >131,072 B fixture to `scripts/domain-model-drift.test.sh` using
      **production-shaped rows** (full migration anchor + a real `USING (...)` predicate).
      **Row count is NOT the load-bearing parameter — bytes per fact is.** Measured: 1200
      *minimal* rows = 75,782 B (under the ceiling → vacuous test); 1200 *realistic* rows =
      286,982 B. Crossover with realistic rows is between 500 and 600.
- [x] **2.8a** Assert **fixture adequacy in-suite**: `jq -c '.facts' | wc -c` must exceed
      131,072, else fail loudly as vacuous. A PR-body demonstration is not runnable post-merge.
- [x] **2.8b** Assert **zero spool residue** on every return path incl. `exit 3`, separately for
      `drift` (subshell) and `extract` (main shell) — the discriminating pair for Phase 2.2.
- [x] **2.9** Run `bash scripts/domain-model-drift.test.sh`.
- [x] **2.10** (filed: #6736) File the argv sibling-sweep issue (ranked list is in plan Phase 2.5). Measure each
      candidate against 131,072 B — item count is not a proxy for argv bytes.

## 3. #6714 — digest liveness monitor

- [x] **3.1** Read `cron-community-monitor.ts`, `_cron-safe-commit.ts`, and `_cron-shared.ts`
      around every line the plan cites. The evidence pull is already done — see the plan's
      H1–H12 table. **H9 stays UNKNOWN; do not manufacture a verdict.**
- [x] **3.2** Widen `SafeCommitResult`'s `"committed"` arm with **optional** `paths?: string[]`
      (from `matched` at `_cron-safe-commit.ts:495`) and `resumed?: true` on the replay-resume
      branch (`:444-455`). Optional, not required — ~38 consumers.
- [x] **3.3** Run the `hr-type-widening-cross-consumer-grep` three-pattern sweep, then
      `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [x] **3.4** **Assign** the `safe-commit-pr` step's return value at `cron-community-monitor.ts:652`
      — it is discarded today. This is the primary defect.
- [x] **3.5** Add `livenessOk`, derived per the plan's four-arm table (committed+path → GREEN;
      committed+resumed → GREEN; no-changes/failed → RED; committed without the path → RED).
      Feed it to the Sentry check-in at `:708-741`.
- [x] **3.6** **Do NOT rename `heartbeatOk`.** Verify
      `grep -c 'if (heartbeatOk && !spawnResult.abortedByTimeout)' …` → 1 and that
      `cron-safe-commit-parity.test.ts` passes unmodified (plan R20).
- [x] **3.7** Close the dedup early-return GREEN path (`:437-447`): before returning GREEN,
      verify the dated digest is committed on the default branch; if not, spawn instead.
- [x] **3.8** Add the five markers at their named sites (plan 3.3 table). Marker 1 has **three**
      sites in `_cron-safe-commit.ts` (`:395`, `:547`, `:805`) — assert per-site, and assert the
      emitted field set, not string presence.
- [x] **3.9** Do **not** invert `:669-671`. Emit marker 1 with `status=failed` from the catch and
      leave retry semantics untouched — inverting causes a replay onto a deleted `spawnCwd` and a
      false `workspace-lost` Sentry event. *(plan 3.5b)*
- [x] **3.10** Read the four suites that already exercise `isRealScheduledDigest`; confirm the
      `_cron-shared.ts:937` body-exclusion arm is genuinely unpinned before adding the
      characterization test.
- [x] **3.11** Correct the stale Tier-2 comment at `:393-397`.
- [x] **3.12** Land behavioral tests in **`cron-community-monitor-heartbeat.test.ts`** (5
      `vi.mock`s, real `postSentryHeartbeat`, asserts check-in colour end-to-end) — NOT in
      `cron-community-monitor.test.ts`, which is pure source-grep (23 `SUT_SOURCE`, 0 `vi.mock`)
      and would degrade the ACs into the grep-proxy the plan forbids. Cover: the four
      `livenessOk` arms (split `no-changes` / `failed` / `committed`-without-the-path), the
      resumed carve-out, the dedup GREEN-path close, and each marker.
- [x] **3.12a** Fix the three `{ ok: true }` mocks — `cron-community-monitor-heartbeat.test.ts:122`,
      `cron-cohort-dedup.test.ts:250`, `cron-community-monitor-dedup.test.ts:160`. They are
      outside the `SafeCommitResult` union; once the return is assigned, `status` is `undefined`
      → RED arm → three suites break for reasons unrelated to the defect.
- [x] **3.12b** Add behavioral assertions in `cron-safe-commit.test.ts` that `paths` is populated
      from `matched` and `resumed: true` is set on the replay branch. `tsc --noEmit` is a
      compile-time proxy and asserts neither.
      **Scoping gotcha:** `const matched` is block-scoped inside `if (!resuming)` (`:495`) while
      `fileCount` is hoisted (`:454`) — `paths` must be hoisted the same way.
- [x] **3.13** `terraform plan` on `apps/web-platform/infra/sentry/` → no diff for
      `sentry_cron_monitor.scheduled_community_monitor`.
- [x] **3.14** (filed: #6737) File the cohort-audit follow-up issue (plan 3.8).

## 4. ADR + C4

- [x] **4.1** Write `ADR-126-cron-liveness-must-assert-the-consumed-artifact.md`. Record: the
      persistence/liveness split; the four GREEN-with-no-artifact paths and **which two remain
      marker-only**; and the cohort-parity decision (why renaming was rejected). Re-verify the
      ordinal against `origin/main` — it is provisional.
- [x] **4.2** Read all three of `model.c4`, `views.c4`, `spec.c4` in full. Enumerate external
      actors, external systems, data stores, and changed access relationships. Expected outcome
      is "no C4 impact" — but the conclusion must cite the enumeration. Edit + run
      `c4-code-syntax.test.ts` / `c4-render.test.ts` if a gap is found.

## 5. Exit

- [x] **5.1** (193/193 suites, rc=0) `bash scripts/test-all.sh` green.
      **Runner note:** `apps/web-platform` is **vitest** (`package.json:15-16`), not `bun test`.
      Single-file form: `cd apps/web-platform && npx vitest run test/server/inngest/<file>`.
- [x] **5.2** PR body: `Closes #6713`, `Closes #6714`, `Closes #6720`; the H1–H12 evidence table
      with raw excerpts and H9 as UNKNOWN; the corrected #6713 causal chain (R4) and #6714 framing
      (R13).
- [x] **5.3** (#6734 tempfile sweep, #6736 argv sweep, #6737 cohort audit) Confirm all three follow-up issues are filed and linked.
- [x] **5.4** (DC-1 surfaced in the PR body) Surface `decision-challenges.md` (DC-1, marker 4 retained against review
      recommendation) for the operator.

## Findings (work phase)

**3.10 — the characterization test was NOT added; it would have been redundant.** The plan
instructed reading the four suites first and skipping if the arm was already pinned. It is:
`cron-shared.test.ts` asserts `isRealScheduledDigest(...) === false` directly on an
`AUDIT_SELF_REPORT_BODY_PREFIX` body ("EXCLUDES the audit FAILED self-report"), plus an
integration-level assertion in the same file and cohort-level ones in `cron-cohort-dedup` and
`cron-community-monitor-dedup`. Verified by mutation rather than by reading: deleting the
`_cron-shared.ts` body-exclusion arm reddens **9 tests across 3 suites**. A new test would be a
10th assertion of the same property.

**3.13 — no `terraform plan` diff, by construction.** `apps/web-platform/infra/sentry/cron-monitors.tf`
is absent from `git diff --name-only origin/main...HEAD`, so `scheduled_community_monitor` cannot
show a diff. The check-in *semantics* changed handler-side only; nothing leaked into IaC. Its
existing `failure_issue_threshold = 1` is what makes a RED check-in auto-page, so the liveness fix
is actionable with no Terraform change.

**4.2 — C4: no impact, enumeration cited.** (a) human actors: `founder = actor "Founder / Operator"`
(`model.c4:8`) — the digest consumer, modeled. (b) external systems: `sentry` (`:290`),
`betterstack` (`:283`), `github`, `discord` (`:244`) — modeled; the social collectors are not
modeled as distinct systems, which is pre-existing and untouched here. (c) data store:
`kb = database "Knowledge Base"` (`:85`), written via `agents -> kb "Reads/writes"` (`:388`) — the
path the digest lands through. (d) changed edges: `webapp -> sentry` (`:491`) already states it
carries "the Inngest-fired crons' end-of-run check-ins (`postSentryHeartbeat` …)". This PR changes
how the colour is COMPUTED inside `webapp`, not the edge, its technology, or its endpoints. No new
element or edge required, so no `views.c4` include change and no C4 test run needed.

**5.1 note — the first full-suite run was a FALSE RED.** It reported 4 `skill-security-scan`
failures. Root cause was a *concurrent* `test-all.sh` from a sibling session in a different
worktree (`feat-one-shot-6721-...`): that suite writes `.scan-meta.json` and runs the scanner
through shared paths, so two simultaneous runs collide. Not pre-existing, and not this diff —
`skill-security-scan.test.ts` is untouched here (`git diff --name-only origin/main...HEAD` → 0
hits). Confirmed three ways: isolated re-run 22 pass / 0 fail; the `skill-security-scan PR gate`
CI check SUCCESS; and a clean full re-run once the sibling finished, 193/193 rc=0. Recorded rather
than waved off as flake — the collision is reproducible and worth a learning.
