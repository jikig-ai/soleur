# Tasks — feat-one-shot-6750-cron-handler-local-liveness

Derived from `knowledge-base/project/plans/2026-07-28-chore-cron-handler-local-liveness-cohort-plan.md` (v2).
Closes #6750. Lane: `cross-domain`. Brand-survival threshold: `single-user incident`.

> **Read the plan's shallow-clone warning before running ANY history command.** This worktree is a
> shallow clone; `scripts/cron-artifact-age.sh` reports NEVER/STALE for 9 of 9 here regardless of
> production state. Task 1.1 is a hard prerequisite for 1.3–1.5.

**The cohort (7 targets)** — re-derive in 1.2, do not trust this list:
`cron-growth-audit`, `cron-campaign-calendar`, `cron-content-generator`, `cron-seo-aeo-audit`,
`cron-growth-execution`, `cron-competitive-analysis`, `cron-architecture-diagram-sync`.
**Class A:** growth-audit, campaign-calendar. **Class B:** the other five.

---

## Phase 1 — Preconditions (no edits)

- [x] 1.1 `git fetch --unshallow || git fetch --depth=1000000`, then `git rebase origin/main`. **Blocks 1.3–1.5.**
- [x] 1.2 Re-derive the roster from `MIGRATED_PROMPT` in `cron-safe-commit-parity.test.ts` **and** from `scripts/cron-artifact-age.sh`'s producer table; confirm they agree modulo the `cron-content-generator` A→B correction.
- [x] 1.3 `bash scripts/cron-artifact-age.sh --all` — capture the baseline (valid only after 1.1).
- [x] 1.4 Re-run the plan's R1/R2/R5/V1 greps; paste output into the session log. Confirm 0/7 carry `dedup-digest-committed-check`.
- [x] 1.5 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-cohort-dedup.test.ts test/server/inngest/cron-safe-commit-parity.test.ts` — pre-change green (expect ~159 passing).
- [x] 1.6 Confirm the class assignment is settled structurally (plan R3): a producer is Class A iff its prompt mandates the consumed-artifact write with no conditional or early-stop. Already decided; re-read only if a prompt changed.

## Phase 2 — ADR-126 amendment (before any handler edit)

- [x] 2.1 Run `/soleur:architecture` and append `## Amendment 2026-07-28 (#6750) — the cohort widening` to `ADR-126-cron-liveness-must-assert-the-consumed-artifact.md`.
- [x] 2.2 Record: the decision; **the remedy's two halves** with the reference's *"SURVIVES … unless closed here"* quoted; the three accepted negatives (RED-where-GREEN ×7; terminal RED instead of retry; every liveness-RED run attempts a GitHub write via `onBeforeHeartbeat`).
- [x] 2.3 Record the class-assignment evidence, including the `cron-content-generator` A→B correction and why the audit's table was wrong.
- [x] 2.4 Record the four **named residuals with day numbers**: `DeployInProgressError` mid-spawn; a `sentry-heartbeat` step throw; the detector posts no check-in of its own; Class B silent windows **15d / 22d / 46d / 75d**.
- [x] 2.5 Record the C4 attribution decision (`api`, not `inngest`, not `webapp`), the second-visual-edge note, and that the cited note's headline reason is network topology.

## Phase 3 — `retryEligible: false` sweep (own commit)

- [x] 3.1 RED first: add A1 pin 2 to `cron-shared.test.ts` — both arms of the identity test (`retryEligible: false` → `{retry:false}` + one `?status=error`; omitted → `{retry:true}` + no heartbeat step). Describe behaviourally; the helper needs `step`/`sentryMonitorSlug`/`cronName`/`logger`.
- [x] 3.2 Add `retryEligible: false` + the scoped comment to all 7 `finalizeOutputAwareHeartbeat` call sites.
- [x] 3.3 **Commit here.** No return-value binding in this commit (plan AC12).

## Phase 4 — Handler changes (after Phase 3's commit)

- [x] 4.1 Bind `const commitResult = await step.run("safe-commit-pr", …)` in all 7.
- [x] 4.2 Declare `let livenessOk = false;` beside `let heartbeatOk = false;` — **addition, never rename** (the parity gate pins `heartbeatOk` as literal source text; measured budget leaves 715 of 800 chars).
- [x] 4.3 Apply the class table; place `if (!livenessOk) heartbeatOk = false;` **after** the persistence block.
- [x] 4.4 Class B committed arm uses the **non-vacuous** predicate `paths.length > 0 && paths.some(p => <ALLOWED_PATHS> prefix)` (plan R12).
- [x] 4.5 (`cron-growth-audit` only) Pin the four report paths to `{{RUN_DATE}}`; delete the "compute today's date yourself" instruction and its containment-hook caveat.
- [x] 4.6 Update `_cron-shared.ts`'s `injectRunDate` contract comment to enumerate the growth-audit report paths as a deliberate exception to "issue-TITLE date ONLY" (plan R13). **Comment only — no behaviour change.**
- [x] 4.7 Export the predicate consts the tests import (the `COMMUNITY_DIGEST_DIR` pattern).
- [x] 4.8 **P0 — dedup short-circuit hardening (does NOT port uniformly, plan R14).** The short-circuit must require **both** the issue and the artifact, failing **closed toward spawning**. Two arms:
  - [x] 4.8a `cron-growth-audit` **only** — port `digestCommittedOnDefaultBranch` verbatim against the exact `<RUN_DATE>-content-audit.md` path. Sound because a date-named file cannot exist unless this run wrote it.
  - [x] 4.8b The other 6 — an existence probe is **VACUOUS** (their artifacts are permanent files/directories, so the contents API returns 200 forever). Add `artifactCommittedSince({ anchorRegex, sinceIso })` to `_cron-shared.ts` and use it: a **freshness** probe on the cron's own `commitMessage:` anchor, reusing the mechanism `scripts/cron-artifact-age.sh` already trusts.
  - [x] 4.8c Never pass a directory or a permanent file path to `digestCommittedOnDefaultBranch` — that is a guard that can never fail (plan AC6b).
  - [x] 4.8d Preserve `emitCronDedupSkip`'s placement: **outside** `step.run`, **before** the `digestAlreadyExists && digestCommitted` gate, so it fires on both the healthy-dedup and the recovery arm.
  - [x] 4.8e Export each target's `*_ALLOWED_PATHS` const (only `COMPETITIVE_ANALYSIS_ALLOWED_PATHS` is exported today) so the probe and the tests share one source.
  - [x] 4.8f Leave `cron-roadmap-review` untouched — it is the 8th `digestIssueExistsForDate` caller but calls `safeCommitAndPr` zero times (EXEMPT). Note it in the PR body so its identical dedup block does not read as an oversight.
- [x] 4.9 Wire `emitCronDigestLiveness` (carrying the arm that decided the verdict) and `emitCronPersistSkipped` into all 7. **Do NOT add `emitCronPersistResult`** — it already fires from inside `_cron-safe-commit.ts` on all three status paths.
- [x] 4.10 Correct `cron-content-generator`'s class `A` → `B` in `scripts/cron-artifact-age.sh`.

## Phase 5 — Tests (in the existing suite; no new test files)

- [x] 5.1 Extend `Row` in `cron-cohort-dedup.test.ts` with `producerClass: "A" | "B"` and `artifact: { hit, nearMiss, unrelated }`.
- [x] 5.2 Add the missing `cron-architecture-diagram-sync` row — its first behavioural test.
- [x] 5.3 Lift `makeStep(throwOn)` from `cron-community-monitor-heartbeat.test.ts`.
- [x] 5.4 Reconcile the shared `safeCommitAndPrSpy` fixture per class. **Do not edit the `AC1b — dedup-skip` assertion as a liveness fix** — that path returns early and never reaches the liveness table; it changes only because 4.8 now also requires the committed artifact.
- [x] 5.5 Add one `describe.each(ROWS)` liveness block covering plan scenarios 1–15 for all 7.
- [x] 5.5a Mirror the two `#6714` dedup tests from `cron-community-monitor-dedup.test.ts`: *"a digest ISSUE without the committed artifact does NOT dedup; the run spawns"* and *"WITH the committed artifact still dedups (healthy path preserved)"*. Copy two harness details or the tests are vacuous: `committedPaths` must be populated **by the `safeCommitAndPr` mock** (never seeded directly — seeding lets a test dedup on an artifact nothing committed), and `fakeRequest` must throw an `Error` carrying `status = 404` for an absent path (a bare `Error` exercises the wrong arm and fires a spurious `reportSilentFallback`).
- [x] 5.6 Mutation-battery rules: **≥2-element `paths`** wherever production calls `.includes`/`.some`; a **near-miss** fixture for every anchored property; **cardinality** assertion on any table claiming exhaustiveness; every added field asserted on a **non-zero** value; marker field sets asserted with `toEqual` (leak guard). The residual risk on this dedicated logger is the **`redact` key set** — a top-level `token`/`secret`/`password`/`authorization` ships verbatim — NOT user ids, which Vector's `pii_scrub_structured` still pseudonymizes downstream.
- [x] 5.7 A1 pin 1 in `cron-safe-commit-parity.test.ts` (**ADD-ONLY**): roster derived from `cronFiles.filter(src => /finalizeOutputAwareHeartbeat\(/)`, matching `retryEligible: false` **at the call site** (not the mirrored comment).
- [x] 5.8 A1 pin 3: parse `scripts/cron-artifact-age.sh`'s `class` column and assert set-equality with the handlers' class arms.
- [x] 5.9 Assert plan R11: a liveness-RED run does not create a **second** issue for the same date.
- [x] 5.10 Adversarial pass — a reviewer briefed to *"find what my battery missed; do not re-run my mutations"*. `test-design-reviewer` surfaced **6** surviving mutations the battery did not imagine; all closed in `072b033f`/`1b3785de`. Highest-value finding: the `PRODUCER_CLASS` assertion was **dead** — it pinned a constant rather than a behaviour, so it could never have gone RED. Now pins the class **arm**.

## Phase 6 — C4

- [x] 6.1 Add the second `api -> kb` relationship to `model.c4` with the attribution comment.
- [x] 6.2 Add the 2-line annotation above `inngest -> github` marking it and `inngest -> doppler` as the same mis-attribution.
- [x] 6.3 `bash scripts/regenerate-c4-model.sh`; commit `model.c4` + `model.likec4.json` **together** (the freshness gate is an orphan suite).

## Phase 7 — Docs, operator comms, deferrals  *(= plan Phase 6; tasks numbering is offset +1 throughout)*

- [x] 7.1 Update `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md`: the new RED arms and the `SOLEUR_CRON_DIGEST_LIVENESS` reasons in the stage table + dedup contract.
- [x] 7.2 Compute the **expected-RED roster** mechanically from `cron-artifact-age.sh`'s `name` + `cron_expr` columns.
- [x] 7.3 Comment it on **#4375** with the defer-corrected diagnosis and a pointer to this PR. **Do not** file a new `action-required` issue; **do not** close #4375 (ADR-138 owns that authority).
- [~] 7.4 **Not achievable as written — recorded, not silently dropped.** `operator-digest`
  reads `gh issue list --json number,title,url,createdAt,labels`; it does NOT read comments, so
  the roster (which lives in a #4375 comment) cannot render inline. The two ways to force it are
  both closed: retitling #4375 is forbidden by the runbook's watchdog Dedup Contract (it breaks
  `find_silence_issue()` and causes duplicate issues), and 7.3 forbids filing a new
  `action-required` issue. **Achieved instead:** the digest surfaces #4375 in §4 with its age and
  URL, one click from the roster. Flagged in the PR body.
- [x] 7.5 File two deferral issues: the `inngest -> github`/`-> doppler` re-attribution, and the detector's missing self-check-in. Link both from the ADR amendment.

## Phase 8 — Verification

- [x] 8.1 Launch `bash scripts/test-all.sh` with `run_in_background`; **wait via the Monitor tool**, never a hand-rolled rc-file poll. Redirect the log to `/var/tmp`; leave `TMPDIR`/`TC_TMPDIR` to the script. **Final run: `=== 233/233 suites passed ===`, exit 0**, on a clean tree with zero edits made while the gate was live.
- [x] 8.2 If it fails, check for a sibling worktree's concurrent run (`ps -ef | grep test-all`, then `/proc/<pid>/cwd`) before treating it as real. Exercised twice: runs 1–2 hit 232/233 with a **different** suite each time (`apps/web-platform`, then `test/content-publisher`), both green in isolation, `SIBLING_RUN_DETECTED` throughout. Neither suite is reachable from this diff — `test/content-publisher` imports only `bun:test` and `path`. Contention, not regression; the clean run confirms it.
- [x] 8.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [x] 8.4 Walk plan ACs 1–18 in order. Note the `$MP` roster-scoping preamble — directory-wide greps are wrong three separate ways. **All pass.** Two apparent misses were both scoping errors in the *walk*, not the implementation, and are recorded because they are the preamble's own trap re-sprung: (a) AC6a's `sed` range for `GROWTH_AUDIT_PROMPT` needs the closing backtick **escaped** inside a double-quoted shell string, or the range runs past line 123 and swallows the `<today>` **code comment** at line 368 — correctly scoped the prompt body has 0; (b) AC6b is scoped to the **cohort of 7**, not `$MP`'s 8 — the 8th caller of `digestCommittedOnDefaultBranch` is `cron-community-monitor`, the pre-existing #6714 reference implementation.
- [x] 8.5 Sanity-test AC12's ordering script against **four** throwaway commits (retryEligible-only, livenessOk-only, both-in-one-commit, correct-order); it must reject the middle two.
- [x] 8.6 Confirm AC17: `git diff --numstat origin/main -- .../cron-safe-commit-parity.test.ts` shows **0 deletions**.
- [ ] 8.7 PR body carries `Closes #6750`.
