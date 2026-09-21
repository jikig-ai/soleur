---
title: "chore(inngest): close #6617 against the recorded pre-cutover verdict and drop the 14 dark-Inngest tables on soleur-dev with atomic retirement of 0002/apply-inngest-rls-dev.yml"
type: chore
date: 2026-09-19
slug: chore-retire-doublefire-probe-drop-dark-inngest-tables
branch: feat-one-shot-6617-6488-retire-doublefire-drop-dark-tables
issue: 6488
closes: [6617, 6488]
priority: p1-high
lane: cross-domain
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

# chore(inngest): close #6617 against the recorded pre-cutover verdict and drop the 14 dark-Inngest tables on soleur-dev with atomic retirement of 0002/apply-inngest-rls-dev.yml

## Enhancement Summary

**Deepened on:** 2026-09-19 · **Lenses:** CTO (structural), ADR-083 advisor, DHH, code-simplicity, CTO (devex), Kieran (correctness) · **Halt gates resolved:** 4.6, 4.7, 4.8, 4.9, 4.10, 4.11

### Key improvements

1. **Roughly 40% of the machinery was cut** — a capability probe, a commit split, a typed confirmation literal, a write-counter handshake, two deliberate red dispatches, a 10-row shape-guard block, four blocking preconditions and six acceptance criteria. Dispatch runs went 5 → 3, commits 4 → 2, acceptance criteria 15 → 9. No risk coverage was lost: what replaced them is an identity assertion, no-`CASCADE`, and reading the dry-run's 14 rows before authorising anything.
2. **A dishonest principle was fixed rather than defended.** P6 claimed the PAT never leaves repo secrets while the plan itself put it in the terminal three times. It now claims only what the workflow buys — preflight and DROP in one process, an immutable run log — and says reads are terminal.
3. **Five P0s were caught in the verification instruments**, two by execution rather than argument: deleting the dev workflow would have reddened 13 of 15 surviving prd probes (`probe()` opens `argv[2]` at module top level), and the "no live references" gate was blind because `[^\n]` in POSIX ERE is a negated set of the literals `n` and `\`.
4. **Three CI-red-only failure modes were added to scope** that a local check could not see: the Supabase census ratchet (CI runs `--check-highwater`), a row-equality baseline for a deleted test, and an unregistered harness in a directory no glob covers.
5. **One shared premise was reversed by measurement.** Two reviewers argued the lib would have a single consumer; `cpx22-invoice-reconcile-7431.sh` is live on open #7437 and is named by `ship/SKILL.md` as the reference implementation — which also put three authoring surfaces in scope, without which this PR would ship a convention contradicting the skill that teaches it.

### New considerations discovered

- The sweeper's dry-run emits a different log line than its live path, so the draft's assertion could never have passed.
- The `ALLOW_14` cardinality guard lives inside the profile the cleanup deletes — removing it silently opens a new vacuity hole in the guard that survives.
- The sweeper may close #6488 on its own between the drop and the merge; that is correct behaviour, recorded rather than fought.
- No app code or migration references any of the 14 table names (deepen-pass sweep), which is the static half of the identity argument.

## Overview

Two follow-through trackers turn the nightly sweeper red and neither red is telling the operator anything new.

The first, #6617, asks whether the dedicated Inngest host was dark and a second scheduler was double-firing. The operator answered it on 2026-07-20 with a recorded `RESULT: PASS` (zero runs on the dedicated host, pre-cutover). The sweeper cannot see that answer: the probe filters comments by `authorAssociation`, the operator's org membership is private, and the sweeper's `GITHUB_TOKEN` therefore renders the verdict as `CONTRIBUTOR`. The probe's own remediation text ("re-dispatch `op=doublefire-probe`") is also inverted post-cutover, because the dedicated host is now the only scheduler and the exactly-once reading is owned by `op=verify` and the ADR-100 soak. The right move is to close the tracker against the recorded verdict, retire its probe, and fix the cause where it is still live.

The second, #6488, tracks the physical drop of the 14 orphaned Inngest tables that the pre-cutover rehearsal left on soleur-dev, together with the retirement of the transient lockdown (`0002_dev_inngest_tables_lockdown.sql` + `apply-inngest-rls-dev.yml`) that defended them. Every precondition the tracker and the ADR-030/ADR-100 addenda name now holds and was read from live data on 2026-09-19: the cutover flag is `done`, the prod DSN targets the dedicated project, the soak window has elapsed, nothing is connected to the dev tables, and the dedicated project shows ~970 runs a day. No drop mechanism exists in the repo, so this plan builds one in the shape the repo already uses for SQL against these projects: the existing dev workflow file is rewritten in place into a fail-closed, dispatch-only drop, dispatched pre-merge from the branch, and then deleted in the same PR so the drop, the retirement and the closure land atomically.

## Research Insights

### Premise Validation (Phase 0.6)

- **#6617** is OPEN (`priority/p1-high`, `follow-through`, directive `script=scripts/followthroughs/inngest-doublefire-reading-6617.sh earliest=2026-07-21T12:00:00Z secrets=GH_TOKEN`). No PR closes it. The probe exits 0 (PASS) locally and exit 1 (FAIL, "no verdict recorded") under the sweeper (run 35465233346, 2026-09-19T19:44Z). **Root cause established in this session:** `gh api orgs/jikig-ai/public_members/deruelle` returns HTTP 404 (membership private); `GITHUB_TOKEN` cannot see private org membership, so the API reports the operator's comments as `authorAssociation: CONTRIBUTOR`, and the probe's `OWNER|MEMBER|COLLABORATOR` filter (added for #7448) drops the 2026-07-20 `RESULT: PASS`. This resolves item 19 ("UNRESOLVED") of `knowledge-base/project/learnings/2026-09-18-every-instrument-i-built-to-check-the-guards-needed-checking.md`. The identical filter lives in `scripts/followthroughs/concierge-strand-754ee124-5733.sh` (open #5733, fails nightly for the honest reason "no verdict yet" — but the day the operator posts one, the same cause will hide it), `betterstack-quota-verdict-5105.sh` and `cpx22-invoice-reconcile-7431.sh` (both trackers closed; dead code).
- The verdict #6617 asked for **is already on the tracker**: 2026-07-20T14:02Z, `RESULT: PASS`, `op=doublefire-probe` run 29748606817, "ZERO runs on the dedicated host". H4 was answered pre-cutover. Post-cutover the criterion "zero runs on the dedicated host" is inverted (the dedicated host is now the only scheduler: `op=registry-probe` run 34948634783 read 70 registered functions from `10.0.1.40:8288`, ADR-100 addendum 2026-09-15), and exactly-once is owned by `op=verify` 2.6 + the ADR-100 Phase-4 soak (#6178). Re-dispatching `op=doublefire-probe`, as the probe's FAIL text instructs, would be the wrong reading.
- **#6488** is OPEN (labels `priority/p0-critical`, `priority/p1-high`, `priority/p3-low`, `action-required`, `follow-through`; directive `script=scripts/followthroughs/inngest-rls-drop-6488.sh earliest=2026-09-13T00:00:00Z secrets=SUPABASE_ACCESS_TOKEN`, so the soak window has elapsed). Probe run locally 2026-09-19: `FAIL: 14/14 dark-Inngest tables still present`, `rls_disabled 0/14`, cumulative writes 81 (baseline 15 on 2026-07-15).
- **Live readiness reads (2026-09-19, pulled, not asked):** Doppler `soleur-inngest/prd` `INNGEST_CUTOVER_FLIP=done`; `INNGEST_POSTGRES_URI` username `postgres.pigsfuxruiopinouvjwy` (the dedicated prd project, not dev). soleur-dev (`mlwiodleouzwniehynfz`) `pg_stat_activity` client backends: `supabase_admin` (loopback), `postgrest`, `postgres_exporter`, and this session's `mgmt-api` — no Inngest session. `function_runs` = 0 rows ever; `events` = 0 live rows (the 25 counted inserts are dead tuples); `apps` = 1 row whose `url` is `http://10.0.1.10:3000/api/inngest` (the pre-cutover co-located host, created 2026-07-10); `goose_db_version` 6 rows, last 2026-07-10T09:38Z; `pg_depend` shows **zero** views/matviews depending on the 14; the only dependent objects are their own PK/unique indexes and `goose_db_version_id_seq`. The 49 `apps` updates + 25 dead `events` inserts explain 81 − 15 = 66 of the counter delta: pre-cutover dark-host heartbeats and the lockdown's own anon-probe round-trips, not a live consumer. The dedicated prd project (`pigsfuxruiopinouvjwy`) shows 970 `function_runs` in the last 24 h (last 2026-09-19T20:09Z). All three drop preconditions hold.
- **No drop mechanism exists on `origin/main`.** `git grep -n 'DROP TABLE' -- .github apps/web-platform/infra scripts` returns only comments (`apply-inngest-rls-dev.yml:16`, `check-tom4-rls-posture.sh`). The brief's "if the drop is a gated workflow_dispatch" hypothesis is false — the mechanism must be built.
- `apply-inngest-rls-dev.yml` is registered on `main` (workflow id 313996104, `state: active`; last runs 2026-09-18/10/09, all `push`, all success).
- The `inngest-cutover` GitHub environment requires **1 reviewer** (an approval click), so the drop must not ride `cutover-inngest.yml`'s environment-gated jobs. `SUPABASE_ACCESS_TOKEN` is a plain repo secret already consumed unenvironmented by `apply-inngest-rls-dev.yml`.
- **ADR corpus check:** ADR-030 I8 (amendment log, 2026-08-20 correction) and ADR-100 (addendum 2026-08-20 #7462) both state that `0002` + `apply-inngest-rls-dev.yml` must NOT retire until the 14 tables are physically gone, and that the governing trigger is exactly the one `inngest-rls-drop-6488.sh` encodes. This plan is the sanctioned execution of that trigger, not a divergence. ADR-100 is `status: adopting`; the `adopting → accepted` flip is #7230 (operator queue, out of scope).
- **Sweeper closed-set behaviour** (`scripts/sweep-followthroughs.sh` ~`:497-503`): a directive whose script is missing from the checkout logs `fail "... missing in repo HEAD — leaving issue open"` and `return 0` — no reopen, no comment; and the run-level verdict only reddens on truncation / missing-secret / fenced-directive. So `Closes #N` in the PR body plus deleting the probe is safe against the 14-day reopen window. Removing the `follow-through` label additionally takes the tracker out of both query sets.

### Property List (Phase 0.6b)

- **P1** The nightly sweeper stops emitting a red for #6617, and #6617 stays closed (no closed-set reopen).
- **P2** The H4 double-scheduler answer survives on the tracker with the pre/post-cutover distinction stated (2026-07-20 PASS = pre-cutover zero runs; `op=verify` 2.6 / ADR-100 soak = post-cutover exactly-once authority).
- **P3** The 14 dark-Inngest tables are absent from soleur-dev (`tables_remaining=0` by the #6488 probe's own query).
- **P4** `0002` + `apply-inngest-rls-dev.yml` + every registration, test, allowlist and comment that references them retire in the SAME PR as the drop (no sentinel RAISE, no green cruft, no dangling suite registration, no stale "the tables still exist" prose).
- **P5** The drop is fail-closed on the two things that can actually be wrong: the project is `soleur-dev` (identity record, not a ref literal alone) and the 14 named relations carry the lockdown posture no app table has. `DROP TABLE` without `CASCADE` supplies the dependent check; four further counters are reported for the operator's information and gate nothing.
- **P6** The destructive statement executes in CI, so the identity preflight and the `DROP` run in one process with no step between them, and the run log is a third-party record. **Reads are not covered by this property** — the plan performs several from the terminal with the same credential, and an earlier draft that claimed otherwise was self-contradictory.
- **P7** An operator-verdict probe works under the token the sweeper actually runs it with. The filter lives in one place, both live consumers use it, a lint blocks the alternative, and the surfaces that teach probe authors point at it.

### Cut List (Phase 0.6b, extended after review)

Mechanisms cut **before** research, for buying no property or a property something already bought:

- "Rewrite #6617's probe to read the exactly-once verdict" → P2 → `op=verify` 2.6 and the ADR-100 soak (#6178) already own that reading.
- "Inline the DROP from the pipeline shell" → P3 → violates P6 and the repo's only precedent for SQL against these projects.
- "A new `drop-*.yml` workflow file" → P3/P6 → cannot be dispatched pre-merge; two PRs; the #4707 rot class.
- "A generic run-dev-SQL workflow" → P6 → YAGNI: a new arbitrary-DDL surface for a one-time drop.
- "Cross-check the prd project's run count inside the dev workflow" → P5 → would name the prd ref inside a file forbidden to contain it.

Mechanisms cut **after** the review panel, from this plan's own scope — recorded here because a cut list that only names roads never taken is a tour, not a cut list:

- Phase 0.5 capability probe → no property; its expected answer is documented and its one open question is unanswerable on that branch.
- A1/A2 commit split → no property; both commits are unmerged branch state and squash merge erases the boundary.
- Typed `confirm` literal + its negative dispatch → P5 → `mode` (choice, default `dry-run`) already separates the arms.
- `expect_writes` freshness handshake + its negative dispatch → P5 → the write delta is already fully accounted for; it needed a second input and a third failure mode.
- Post-drop negative dispatch → P5 → proves an arm of a workflow deleted in the next commit.
- Transient `drop_*` shape-guard block, `EXPECTED_DROP_CHECKS`, and the `infra-validation.yml` paths add-then-remove → P5 → a static guard buys regression value over time, and the file has one commit of time; the dry-run's 14 rows are the stronger evidence.
- Blocking on `dependents_outside` / `foreign_sessions` / `runs` / `events` → P5 → demoted to reported; the plan's own analysis says the safety case does not rest on them, and one of them may sample the workflow's own connection.
- `anon_grants` as a separate counter → folded into `posture_ok` (same query, same meaning); secret-present → folded into the identity arm.
- AC-4's post-merge re-check as a standalone criterion → folded into AC-2, with its executor named because the same PR deletes the probe.
- Six acceptance criteria that asserted the procedure had been followed rather than a property of the result.

### Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (verified) | Plan response |
|---|---|---|
| "if the drop is a gated workflow_dispatch, verify readiness and dispatch it" | No drop mechanism exists anywhere on `origin/main` (`git grep 'DROP TABLE'` → comments only) | Build the dispatch-only drop by rewriting the registered dev workflow in place; dispatch it from the branch; delete it in the same PR |
| "#6617 … either close against the cutover addendum, or rewrite its probe" | The verdict was recorded 2026-07-20; the probe cannot see it because of `authorAssociation` under `GITHUB_TOKEN` (cause established here, previously "UNRESOLVED") | Close via the PR; retire the probe; fix the cause in the live sibling (#5733) and the convention; use #6617 as the pre-deletion fixture that proves the fix |
| "#6488 … the cutover is done, so the post-cutover precondition holds" | Confirmed from Doppler (`done`, prd DSN) and both catalogs (dev idle, prd ~970 runs/day) | Phase 0 re-reads the same signals at work time and records them in the PR body |
| "Probe FAILs nightly: 14/14 still present" | Confirmed (local run 2026-09-19); writes 15 → 81 explained by pre-cutover heartbeats + the lockdown's own anon-probe traffic | The drop workflow's dry-run prints per-table `n_live_tup` so the "nothing real lives here" claim is in the run log, not just in this plan |

### Files and anchors

- `.github/workflows/apply-inngest-rls-dev.yml` — identity preflight `:126-145` (`identity_unreachable` / `identity_mismatch`), Management-API POST `:157`, `record_failure` pattern `:112-113`, `sanitize`/`scrub_pat` helpers `:98-104`, `gate_coverage` (`seen_n` vs 14) `:223`, job-level pinned `PROJECT_REF` `:85`.
- `apps/web-platform/infra/inngest-rls/apply-inngest-rls-dev-workflow.test.sh` — python/pyyaml probe with `env_values`/`env_all_eq`/`all_run_text`/`uses_list`/`step_if`/`routes`; prd assertions `prd_routes_0001`, `prd_ignores_*`, `prd_no_wildcard_glob`, `prd_ref_pinned`, `prd_identity_name`, `prd_identity_call`, `prd_gate_*` (5), `prd_uses_sha_pinned` must survive the dev arm's removal.
- `apps/web-platform/infra/inngest-rls/inngest-rls.test.sh` — `SQL_0002` (`:39`), `check_workflow_allowlist_matches` (`:158-171`, reads the dev workflow's `ALLOW` literal), `check_sequence_ddl_is_allowlist_bound` (`:175-206`, "0002 ONLY"), `profile_0002` (`:337+`); `profile_0001` (`:207+`) stays.
- `apps/web-platform/infra/inngest-rls/inngest-rls-mutation.test.sh` — mutates 0002 only; `anon-probe.sh` — invoked only by the dev workflow (`:302`).
- Registrations: `.github/workflows/infra-validation.yml` `paths:` (`:66-67`) and steps (`:1495-1499`, `:1522-1523`); `.github/scripts/test/test-infra-suite-registration.sh:113-115`; `apps/web-platform/infra/run-registered-suites.test.sh:114-116`.
- Comment/allowlist references: `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh:1351`; `scripts/lib/scrub-supabase-pat.sh:6-10` ("FOUR places"); `scripts/lint-supabase-deprecated-endpoints.sh:147-148` (dated non-caller allowlist entries for `0002` and the dev shape test); `scripts/lint-shell-trace-credential-refusal.baseline.txt:58` and `-d.baseline.txt:37` (file-membership suppression; a stale entry is inert but must not be left); `scripts/followthroughs/cpx22-invoice-reconcile-7431.sh:65` (comment naming the 6617 probe); `knowledge-base/operations/expenses.md:27` (row note asserting the 14 still exist).
- Sweeper: `scripts/sweep-followthroughs.sh` directive anchor `:120,152-166`, missing-script arm `:497-503`, closed-set precheck `:227-310`, run-level verdicts (tail). Sweeper workflow: `.github/workflows/scheduled-followthrough-sweeper.yml` (`workflow_dispatch` input `dry_run: boolean`, `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` `:101`, cron `0 18 * * *`).
- ADRs: `ADR-030-inngest-as-durable-trigger-layer.md` I8 (`:125`) + amendment log (`:160-181`); `ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` addendum pattern `## Addendum — YYYY-MM-DD (#N) — <title>` (`:1353`, `:1400`), cross-references at `:655`, `:741`.
- C4 count parity baseline (this session): `bash plugins/soleur/test/c4-count-parity.test.sh` → 10/10 PASS (C1 = 13 heartbeat workflows; the dev workflow carries no `sentry-heartbeat` step, so its deletion moves no count).

### Institutional learnings applied

- `2026-04-21-workflow-dispatch-requires-default-branch.md` — a new workflow 404s on `--ref <branch>`; this is why the drop reuses the registered filename.
- `2026-08-09-the-monitor-reported-success-and-i-read-the-field-that-cannot-say-otherwise.md` — an existing workflow dispatched with `--ref` runs the modified file; read `conclusion`, not `status`, and confirm the run's `head_sha` is the pushed commit.
- `2026-09-18-every-instrument-i-built-to-check-the-guards-needed-checking.md` item 19 — the local-vs-sweeper disagreement on #6617; this plan supplies the cause and edits the item to point at it.
- `2026-08-11-my-fixture-shared-the-bug-so-the-test-could-not-see-it.md` (#7448) — the author filter is load-bearing on a public repo; the replacement must still reject a non-collaborator's `RESULT: PASS`, and its fixture must carry an author field.
- `2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md` — a shape test must pin the DROP's name-set and its guards, not a helper that re-implements them.
- `2026-09-08-the-guard-was-deleted-the-plan-still-cited-it-and-the-linter-validated-the-citation.md` — after deleting suites, re-run every registration guard and every sibling suite whose population changed.
- `2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker.md` — here the `Closes #6617` / `Closes #6488` adjacencies are **intentional**; no other `closes|fixes|resolves #N` adjacency may appear in the PR body.
- `2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md` — Monitor on `gh run watch <id> --exit-status`, never `pgrep -f` on the wrapper.
- `2026-05-11-manual-dispatch-substitutes-for-scheduled-tick-when-external-dependency-resolves.md` — a `gh workflow run` of the sweeper is equivalent to its scheduled tick; used here in `dry_run=true` as the P7 fixture.
- `2026-09-17-followthrough-directive-on-existing-issue-three-silent-traps.md` — silence is not success: read the sweeper log line for #6617, not the absence of a comment.
- `best-practices/2026-04-15-plan-skill-reconcile-spec-vs-codebase.md` — the reconciliation table above.

### Community discovery

Functional-overlap scan (3/3 registries): no overlap for the core deliverables; the closest match (`jawwadfirdousi/supabase`, Management-API query helper) covers only the `POST /database/query` call shape the repo already has. Nothing installed. No uncovered stack (bash / GitHub Actions / Supabase).

## Deepen Pass (2026-09-19)

Run after the review panel, so it verifies the *revised* plan rather than the draft. No new mechanisms were added; three claims were upgraded from argued to measured and all six halt gates were resolved mechanically.

**Verify-the-negative sweep (Phase 4.45).** The plan's load-bearing negative claim is "the 14 tables were never read by the application" — load-bearing because soleur-dev is co-tenanted and a name collision would make the DROP destructive. Two sweeps, both empty:

- `git grep -cE '\.from\("<t>"\)|FROM <t>\b|INTO <t>\b' -- apps/web-platform` over all 14 names → **0 references**.
- `git grep -lE 'CREATE TABLE …(the 14)…' -- apps/web-platform/supabase/migrations` → **no file**.

This is the catalog-independent half of the identity argument, and it is stronger than the migration grep the Technical Considerations section cites: no app code queries any of the names, and no app migration creates one. `posture_ok` remains the runtime discriminator; this is the static one.

**Rule-ID citations (Quality Check).** Three cited: `cq-cite-content-anchor-not-line-number` and `wg-when-tests-fail-and-are-confirmed-pre` are ACTIVE in `AGENTS.rules.md`; `cq-ac-must-not-depend-on-concurrent-sessions` is MIGRATED-but-active (its canonical home is now `plan-review/SKILL.md`, per PR #8034). None fabricated, none retired.

**Precedent-diff gate (Phase 4.4).** Both pattern-bound deliverables have a sibling precedent in-repo and adopt it rather than inventing a form: the drop workflow's identity preflight, anti-exfil helpers and Management-API POST are copied verbatim from the file it replaces (the same shape `apply-inngest-rls.yml` uses for prd); `scripts/lib/trusted-verdict.sh` follows `scripts/lib/scrub-supabase-pat.sh` — with one deliberate divergence recorded, that the precedent lib exists as a landing zone for future callers and explicitly declines to migrate its pre-existing copies, whereas this lib migrates both of its live consumers in the same PR because a lint makes the alternative red.

**Halt gates.** 4.6 User-Brand Impact — present, threshold `none`, and the diff touches 8 sensitive paths so the required `threshold: none, reason:` scope-out is present. 4.7 Observability — all five fields non-placeholder, no `ssh`, probe verb `git` is on the Check-10 allowlist. 4.8 PAT-shaped variables — none. 4.9 UI wireframe — no UI-surface path in the Files sections (the glob strings elsewhere in the plan are self-references to the detection regex, not matches). 4.10 Encryption posture — no path matches the detection set, no new store or cross-component connection. 4.11 Guard Contract — `lint-guard-contract.py` green over both entries, and both Assemblies name a structural chokepoint (a counter pair; a lib plus the lint that forbids bypassing it) rather than a member list.

## Problem Statement / Motivation

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed); this branch has no `spec.md`.

- Two of the nightly sweeper's FAIL comments are permanent by construction: #6617's verdict is invisible to the sweeper's token, and #6488's completion signal (table absence) has no executor. Both read as "someone must act" and both will read that way forever without this change.
- `0002` + `apply-inngest-rls-dev.yml` are a transient lockdown whose `LIFETIME: TRANSIENT` header binds them to the Phase-5 drop. Left in place after the drop, `0002`'s positive sentinel RAISEs on its next trigger; left in place without the drop, the workflow stays green defending a co-tenancy the cutover ended (ADR-030 amendment 2026-08-20; ADR-100 addendum #7462).
- The `authorAssociation` verdict filter is the sanctioned pattern in four probes and the convention's "operator-confirmed" arm, and it cannot pass under `GITHUB_TOKEN` for an operator whose org membership is private. #5733 will hit it the day its verdict is posted.

## Proposed Solution

**Revised after a five-lens review panel cut roughly 40% of the original machinery** (see Review and Consult Provenance below). What survives: rewrite the registered dev workflow in place into a dispatch-only DROP, dispatch it twice from the branch, then delete it along with the lockdown it retires — two commits, not four.

1. **Commit A — the transient drop workflow + the verdict-filter fix.** Rewrite `.github/workflows/apply-inngest-rls-dev.yml` in place into `Drop: soleur-dev dark-Inngest tables (#6488, transient)`: `workflow_dispatch` only, one `mode` input (choice `dry-run` | `drop`, default `dry-run`), the pre-existing `reason` kept. The job keeps the pinned `PROJECT_REF`/`PROJECT_NAME`, the identity preflight and the anti-exfil helpers **verbatim** from the file it replaces. Alongside it, extract `scripts/lib/trusted-verdict.sh` and repoint the two live `authorAssociation` probes plus the three authoring surfaces that would otherwise contradict it.
2. **Dispatch (three runs, each watched by a Monitor in the same turn).** Sweeper `dry_run=true` → proves the verdict filter under `GITHUB_TOKEN` and prints the observed `authorAssociation`. Concurrency quiesce check. Drop `mode=dry-run` → the 14-row report. Drop `mode=drop` → echoes the exact statement, POSTs it, re-reads and requires 0.
3. **Commit B — retire everything transient and record.** Delete the drop workflow, `0002`, `anon-probe.sh`, the mutation battery, both follow-through probes and every registration/ratchet/allowlist/comment that names them; write the ADR-100 addendum (the one record carrying the run URLs) with one-line pointers from ADR-030 and `expenses.md`; de-enrol both trackers. PR body carries `Closes #6617` and `Closes #6488`.

## Technical Considerations

- **Why the destructive statement runs in CI and the reads do not — the honest form of P6.** An earlier draft stated P6 as "the PAT never leaves repo secrets", and the panel correctly observed that the plan violates that three times over: Phase 0 and Phase 2 both run the `#6488` probe from the terminal with the Doppler-held PAT against the same `/database/query` endpoint. Credential hygiene is therefore **not** what the workflow buys, and claiming it was the defect. What it does buy, and what P6 now says: the identity preflight and the `DROP` execute **in one process**, so no human- or agent-typed step can sit between "this project is `soleur-dev`" and "drop these tables"; and the run log is an immutable third-party record tied to a commit, which a pasted terminal transcript is not. Reads are non-destructive and stay in the terminal. This also matches the repo's only precedent for applying SQL to these projects (`0001`/`0002` via the two `apply-inngest-rls*` workflows, each with the same preflight).
- **Why the workflow keeps the old filename.** `workflow_dispatch` resolves a workflow by name against the default branch and then runs the file at `--ref`; the repo measured a 404 for a branch-only file on 2026-04-21 (#2717) and `plan-sharp-edges.md` carries it as a standing edge. `apply-inngest-rls-dev.yml` is registered (id 313996104) and already declares `workflow_dispatch` on `main`, so the in-place arm is **measured, not assumed** — which is why this plan carries no capability probe and no two-armed decision rule.
- **Concurrency.** `concurrency.group: apply-inngest-rls-dev` is shared with main's `push` runs of the same workflow — a hazard inherited from reusing the file. A merge to main touching `cloud-init-inngest.yml`, `0002`, `anon-probe.sh` or the workflow during the dispatch window would interleave main's old lockdown code with this drop, and after the drop `0002`'s positive sentinel RAISEs. Two shell lines (Phase 2 step 2) assert zero in-flight runs before the drop and re-assert after; cheaper than the separate-file arm it would otherwise justify.
- **Input-schema risk.** If GitHub validates the new `mode` input against the default branch's copy and rejects it (`Unexpected inputs provided`), carry the mode in the pre-existing `reason` input (`reason` matching `^drop$` ⇒ drop; anything else ⇒ dry-run). One input, one fallback, no third mechanism. Record which arm ran.
- **The DROP statement.** One statement, all 14 names, schema-qualified, no `IF EXISTS` (exactly-14 is asserted first, so a partial state must fail rather than be papered over), no `CASCADE` — **`DROP TABLE` without `CASCADE` is itself the exhaustive dependent check, enforced by Postgres**, and that is the dependent-safety property. Preceded by `SET lock_timeout TO '10s'`. The step **echoes the exact statement immediately before the POST**, so the run log binds run → SQL without depending on a commit that a squash merge will not preserve. Sequences owned by the 14 (`goose_db_version_id_seq`), their indexes, and `0002`'s policies/grants go with the tables.
- **Identity, not count — the one precondition that distinguishes an Inngest table from an app table.** `tables_present == 14` is a count, and soleur-dev is co-tenanted with ~52 app tables. The discriminator is the posture `0002` established and the app tables deliberately lack: for each of the 14, `relrowsecurity = true`, zero policies, and no `anon` SELECT privilege. The drop requires `posture_ok == 14`. Its stated limit, so it is not over-read: `posture_ok` is evaluated over the 14 selected **by name**, so a hypothetical app table renamed onto one of those names *and* carrying the lockdown posture would satisfy it — the report therefore also prints `relnamespace` and `reltuples` per row. (A migration grep finds no app table sharing any of the 14 names today; that is a grep, not a catalog read, which is why the posture assertion carries the weight.)
- **Four counters are reported, not blocking — deliberately, because the earlier draft blocked on them while arguing they were not load-bearing.** `dependents_outside` (`pg_depend` does not record view dependencies — they go through `pg_rewrite` — nor function bodies, dynamic SQL or policy expressions), `foreign_sessions` (a point-in-time sample whose `usename = 'postgres'` predicate structurally excludes PostgREST's `authenticator`, the very consumer class `anon-probe.sh` tested, and which may sample the workflow's own `mgmt-api` backend), and `runs`/`events` (weak against an insert-then-delete consumer). All four are printed; none gates the POST, because a gate that cannot be trusted to be right is a flake, not a safety property.
- **No typed confirmation literal and no freshness handshake.** `mode` is a `choice` input defaulting to `dry-run`; selecting `drop` is already the deliberate act. A 52-character literal typed by the agent out of this plan adds a typo surface to guard an enum that cannot be typo'd, and its only other deliverable was a PR-body sentence disclaiming that it was not an approval gate. A write-counter handshake between two dispatches was likewise cut: the plan already accounts for the entire 15 → 81 delta as pre-cutover heartbeats and the lockdown's own probe traffic, and it would have required a second input, a third failure mode and an extra negative dispatch.
- **The verdict filter, and why it is in this PR.** Under `GITHUB_TOKEN`, `authorAssociation` is not trustworthy for a private-membership org, but `GET /repos/{owner}/{repo}/collaborators/{login}/permission` resolves *effective* permission (measured: `admin` for the operator, `none` for `github-actions[bot]`). `scripts/lib/trusted-verdict.sh` collects distinct `author.login` values, resolves each once, and honours a `RESULT:` line only from `admin`/`maintain`/`write`; an HTTP error is TRANSIENT (exit 2), never PASS. **Measured, and it reverses a premise two reviewers shared:** the filter has **two live consumers** — `concierge-strand-754ee124-5733.sh` (open #5733) and `cpx22-invoice-reconcile-7431.sh`, enrolled on **open** issue #7437 and named by `ship/SKILL.md` Step 3.5.B as *"the reference implementation"*. Whether the endpoint returns 200 under an installation token scoped `contents: read, issues: write` is **unmeasured** (no prior art here; the fine-grained mapping is Metadata:read, which every `GITHUB_TOKEN` carries, so 200 is likely) — Phase 2 step 1 measures it, using the 6617 probe as the only available fixture, because it is the one probe carrying a real verdict comment from a private-membership author. **Fallback if it 403s:** derive the trusted set from the committed `.github/CODEOWNERS` `*` owner line, readable with `contents: read` and changeable only through a CODEOWNERS-protected review.
- **The three authoring surfaces are in scope because otherwise this PR ships a contradiction.** `ship/SKILL.md` Step 3.5.B currently says the `authorAssociation` filter is *"mandatory, not stylistic"* and names a probe to copy; `followthrough-stub-template.sh` shows an **unfiltered** `.comments[].body` example. A convention bullet saying the opposite would be born contradicted, and the next probe author is routed past the lib by name. `scripts/lint-followthrough-varq-ban.sh` — already registered, already the executable form of this convention's census — gains one rule so the alternative is blocked mechanically rather than by prose.

## Files to Edit

**Citations name content anchors (function, key, heading) rather than line numbers** — a review pass found several of the draft's line numbers had drifted, and `cq-cite-content-anchor-not-line-number` is the durable fix rather than correcting each one.

**The drop workflow and the lockdown**

- `.github/workflows/apply-inngest-rls-dev.yml` — commit A: rewrite into the dispatch-only drop, reusing its own `record_failure`, `scrub_pat`/`sanitize`, identity-preflight and `database/query` POST blocks verbatim; commit B: delete.
- `apps/web-platform/infra/inngest-rls/apply-inngest-rls-dev-workflow.test.sh` → `git mv` to `apply-inngest-rls-workflow.test.sh`. **The `dev_*` block cannot simply be dropped — `probe()` is hard-coupled to the dev file.** It passes both paths as argv and runs `dev = yaml.safe_load(open(sys.argv[2]))` at module top level, *before* any key is selected, so every call opens the dev workflow. Measured by the panel with `DEV_WF` pointed at a nonexistent path: `passed=2 failed=46` — **13 of the 15 `prd_*` probes go red**, not just the dev ones. Commit B must therefore also remove `argv[2]`, the `dev =` load, the `DEV_WF=` assignment and the two bash asserts for dev existence/parse. Add the `EXPECTED_TOTAL` floor (Guard 1).
- `apps/web-platform/infra/inngest-rls/inngest-rls.test.sh` — delete `SQL_0002`, `profile_0002`, `check_workflow_allowlist_matches`, `check_sequence_ddl_is_allowlist_bound` and their call sites. **Hoist `ALLOW_14`'s cardinality guard out of `profile_0002` first:** `profile_0001` consumes `ALLOW_14` in its negative-noun loop, but the `[[ ${#ALLOW_14[@]} -eq 14 ]]` guard lives inside `profile_0002`, so deleting that profile lets the array silently shrink while the surviving guard still reports `ok` — a new vacuity hole created by the cleanup itself. Also remove the helpers that go dead with it (`check_no_schemawide_ddl_loop`, `check_raw_has`, `has_raw`, `RAW`) and refresh the comment stating the 14 names live in three places; two of the three disappear.
- `.github/workflows/infra-validation.yml` — `paths:` keeps the dev-workflow entry through commit A and loses it in B; rename the shape-guard step to the new filename; delete the mutation-attestation step and its comment.

**Registrations, ratchets and baselines — every one of these reds CI if missed**

- `.github/scripts/test/test-infra-suite-registration.sh` (`KNOWN_UNDERIVABLE`) and `apps/web-platform/infra/run-registered-suites.test.sh` (`KNOWN_UNDERIVED`) — replace the three entries with the one renamed suite. Both are strict: the first reds on a *stale* entry and keys on the exact path, the second is a hard set equality, so the rename forces both edits.
- `scripts/test-all.sh` — register the new probe harness and `scripts/lib/trusted-verdict.test.sh`. Measured: all 21 follow-through suites are registered by individual `run_suite` lines, and the file states verbatim that `scripts/followthroughs/` *"is covered by no glob here"*. An unregistered harness is the orphan-suite class this repo has already paid for, and it would defeat Guard 2 exactly as the guard says it must not be.
- `scripts/lint-supabase-deprecated-endpoints.highwater` — **the census ratchet, and a CI-only failure mode.** Measured 2026-09-19: the file reads `28` and `--census` returns `28`. Deleting the dev workflow removes its three counted call sites and `anon-probe.sh` two more; the drop workflow adds its own in commit A and loses them in B. The header is explicit that a *drop* is the failure and must be lowered in the same commit with the sites named. Measure at commit B and write the provenance line.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` — carries a row-equality entry for `inngest-rls-mutation.test.sh`, enforced by `diff` in `fixture-relative-assert.test.sh`, where "a fall reddens exactly like a rise". Regenerate in the same commit as the deletion.
- `scripts/lint-shell-trace-credential-refusal.baseline.txt` and `-d.baseline.txt` — remove the `inngest-rls-drop-6488.sh` entries. Measured: a stale entry is **inert** (the loader does no existence check and non-existent paths are filtered before the membership test), so this is hygiene, not a red. **But `scripts/lib/trusted-verdict.sh` is in Rule D's scan scope** — that rule deliberately drops the `^scripts/lib/` exclusion — so its credentialed `gh api` call must carry `--disable` as its first argument and `--noproxy '*'`, or the lint reds. The new `.test.sh` is excluded and needs no entry.
- `scripts/lint-supabase-deprecated-endpoints.sh` (`ALLOWLIST`) — **the draft's rationale was inverted.** There is no stale-entry arm (the scan loop skips missing files; the only staleness finding is the opposite case, an allowlisted file that starts calling), so removing the `0002` entry is hygiene. The **rename entry is mandatory** for a different reason: the renamed shape guard still matches the host-pin assembly and, with no allowlist entry under its new name, emits `UNPINNED-HOST` and exit 1.

**The verdict filter and the surfaces that would contradict it**

- `scripts/followthroughs/concierge-strand-754ee124-5733.sh` and `scripts/followthroughs/cpx22-invoice-reconcile-7431.sh` — source `scripts/lib/trusted-verdict.sh`; drop the `authorAssociation` select. Both are **live** (open #5733 and open #7437).
- `scripts/followthroughs/inngest-doublefire-reading-6617.sh` — commit A: same lib, plus the `observed authorAssociation=` last-stderr line; commit B: delete.
- `plugins/soleur/skills/ship/SKILL.md` Step 3.5.B — **the highest-leverage edit.** It currently states the `authorAssociation` filter is *"mandatory, not stylistic"* and names `cpx22-invoice-reconcile-7431.sh` as *"the reference implementation"* to copy. Keep its threat model (the repo is public; a forged `RESULT: PASS` still closes a tracker) and replace the mechanism with "source `scripts/lib/trusted-verdict.sh`". Without this the convention is born contradicted and the next author is routed past the lib by name.
- `plugins/soleur/skills/ship/references/followthrough-stub-template.sh` — its example pipes an **unfiltered** `.comments[].body` into the verdict grep.
- `scripts/lint-followthrough-varq-ban.sh` — add a rule forbidding `authorAssociation` under `scripts/followthroughs/`, with its own floor mirroring the existing per-rule floors. Already registered; already the executable form of this convention's census.
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` — the rule, citing the value measured in Phase 2 step 1 rather than an inference.
- `knowledge-base/project/learnings/2026-09-18-every-instrument-i-built-to-check-the-guards-needed-checking.md` item 19 — replace "UNRESOLVED … cause is unestablished" with the measured cause, marked `[Updated 2026-09-19]`.

**Dangling prose references in surviving files** (none match an executable-shape grep, so AC-4 cannot find them — swept by hand)

- `.github/workflows/apply-inngest-rls.yml` — header comments naming `anon-probe.sh` and *"the dev counterpart"*.
- `apps/web-platform/infra/inngest-rls/0001_enable_rls_lockdown.sql` — a `RAISE EXCEPTION` message telling the operator to use `0002` instead.
- `scripts/supabase-advisor-scan.sh`, `apps/web-platform/infra/supabase-advisor/scan-workflow-mutation.test.sh`, the `lint-supabase-deprecated-endpoints.highwater` provenance header, `.github/CODEOWNERS`, `scripts/lib/scrub-supabase-pat.sh` ("FOUR places" → "THREE"), `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` (comment citing the old suite's `routes()`), `scripts/followthroughs/cpx22-invoice-reconcile-7431.sh` (comment naming the 6617 probe).
- `scripts/followthrough-exec-bit.test.sh` and `scripts/followthrough-predicate-parity.test.sh` — no edit expected, but both are constraints: the first asserts every `scripts/followthroughs/*.sh` is committed `100755` (the new harness matches that glob; the lib does not), and the second is a differential oracle over the directive-enrolment readers, which this plan does not change. Confirm both stay green after the deletions.

**Records**

- `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` — the addendum, the one record carrying the run URLs.
- `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md` amendment log and `knowledge-base/operations/expenses.md` — one line each, pointing at the addendum rather than restating it.
- GitHub issues #6617 and #6488 — de-enrol (label plus directive block).

## Files to Delete

- `apps/web-platform/infra/inngest-rls/0002_dev_inngest_tables_lockdown.sql`, `anon-probe.sh`, `inngest-rls-mutation.test.sh` (commit B)
- `.github/workflows/apply-inngest-rls-dev.yml` (commit B)
- `scripts/followthroughs/inngest-rls-drop-6488.sh` and `inngest-doublefire-reading-6617.sh` (commit B)
- `scripts/followthroughs/betterstack-quota-verdict-5105.sh` — tracker #5110 is closed, it has no harness, and it is a forgeable-looking `authorAssociation` template sitting in the directory new probe authors browse.

## Files to Create

- `scripts/lib/trusted-verdict.sh` — the verdict filter, with two live consumers from day one.
- `scripts/lib/trusted-verdict.test.sh` — the lib's own matrix. It lives beside the lib, not inside a consumer, because ten sibling libs follow that convention and because a consumer-housed test dies when its tracker closes.
- `scripts/followthroughs/concierge-strand-754ee124-5733.test.sh` — the per-probe assembly rows, modelled on the existing `cpx22-invoice-reconcile-7431.test.sh`. Committed `100755`.
- Planning artifacts under `knowledge-base/project/specs/feat-one-shot-6617-6488-retire-doublefire-drop-dark-tables/`.

## Implementation Phases

### Phase 0 — Readiness re-read (work time, read-only, recorded in the PR body)

1. `doppler secrets get INNGEST_CUTOVER_FLIP -p soleur-inngest -c prd --plain` → `done`; the `INNGEST_POSTGRES_URI` **username only** → `postgres.pigsfuxruiopinouvjwy` (the URI itself is never printed).
2. `SUPABASE_ACCESS_TOKEN="$(doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd --plain)" bash scripts/followthroughs/inngest-rls-drop-6488.sh` → exit 1 with `14/14` (the pre-state). A terminal **read**, per the P6 restatement.
3. `bash scripts/followthroughs/inngest-doublefire-reading-6617.sh` → exit 0 locally, contrasting with the sweeper's exit 1 in run 35465233346.
4. `gh api repos/jikig-ai/soleur/collaborators/deruelle/permission --jq .permission` → `admin` under the operator token. The `GITHUB_TOKEN` reading — the one that matters — comes from Phase 2 step 1.

### Phase 1 — Commit A: the transient drop workflow + the verdict-filter fix

1. Rewrite `.github/workflows/apply-inngest-rls-dev.yml`:
   - `on: workflow_dispatch` only; inputs `mode` (choice `dry-run` | `drop`, default `dry-run`) and the pre-existing `reason`.
   - `permissions: contents: read`; `concurrency: group: apply-inngest-rls-dev`; `timeout-minutes: 10`; job env `PROJECT_REF: mlwiodleouzwniehynfz` and `PROJECT_NAME: soleur-dev`; step env `SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}` (a repository secret — measured: no environment gate, readable from any branch); `actions/checkout` at the existing SHA pin.
   - One `run:` step, `set -uo pipefail`, helpers copied verbatim (`strip_log_injection`, `scrub_pat`, `sanitize`, `record_failure`), `API="https://api.supabase.com"` pinned, every curl keeping `--max-time 30`, and `NAMES=( apps event_batches events function_finishes function_runs functions goose_db_version history migrations queue_snapshot_chunks spans trace_runs traces worker_connections )` as the single source for both the catalog predicate and the DROP list.
   - **Blocking chain** (each arm `record_failure`s and exits 1 before any write): identity `/v1/projects/${PROJECT_REF}` HTTP 200 **and** `.name == soleur-dev` — an absent secret surfaces here as `identity_unreachable`, so there is no separate secret-present arm; then one catalog query returning `tables_present`, `posture_ok`, and the four **reported** counters `dependents_outside`, `foreign_sessions`, `runs`, `events`, plus a per-table `relname, relnamespace, reltuples, n_live_tup` listing to the log and `$GITHUB_STEP_SUMMARY`.
   - `mode=dry-run` ⇒ print the report, exit 0, write nothing. `mode=drop` ⇒ require `tables_present == 14` **and** `posture_ok == 14`; **echo the exact statement**; POST `SET lock_timeout TO '10s'; DROP TABLE public.apps, …, public.worker_connections;`; re-read and require `tables_present == 0`; write `tables_remaining=0` to the summary.
   - Header: `LIFETIME: TRANSIENT — deleted in commit B of this same PR. RETIREMENT: this file and its infra-validation paths: entry.`
2. `scripts/lib/trusted-verdict.sh` and `scripts/lib/trusted-verdict.test.sh`, the lib's `gh api` call carrying `--disable` first and `--noproxy '*'` (Rule D reaches `scripts/lib/`).
3. Source the lib from **both** live consumers — `concierge-strand-754ee124-5733.sh` and `cpx22-invoice-reconcile-7431.sh` — and transiently from `inngest-doublefire-reading-6617.sh`, which additionally prints `observed authorAssociation=<value> for verdict author <login> (token=GITHUB_TOKEN)` as its **last stderr line**; the sweeper's dry-run tail is capped at 600 bytes, so last is the only surviving position.
4. The three authoring surfaces (`ship/SKILL.md` Step 3.5.B, the stub template, the new `lint-followthrough-varq-ban.sh` rule) and the deletion of `betterstack-quota-verdict-5105.sh`.
5. `EXPECTED_TOTAL` floor in the shape guard, carrying an inline comment naming the measurement date and the counts it was derived from, so the next editor investigates a mismatch instead of bumping the number.
6. Register both new test files in `scripts/test-all.sh`.
7. Local green: the shape guard; `bash scripts/lib/trusted-verdict.test.sh`; both probe harnesses; `bash scripts/lint-followthrough-varq-ban.sh`; `python3 scripts/lint-shell-trace-credential-refusal.py`; `bash scripts/followthrough-exec-bit.test.sh`; `actionlint .github/workflows/apply-inngest-rls-dev.yml`; the Guard 1 and Guard 2 matrices, each row applied, expectation observed, reverted.
8. Commit, push, record `SHA_A`. **Under squash merge** (enabled here) `SHA_A` is not an ancestor of `main` — it survives as `refs/pull/N/head`, which is why the echoed DROP in the run log, not the SHA, is the durable binding.

### Phase 2 — Dispatch (three runs; each dispatch arms a Monitor on `gh run watch <id> --exit-status` in the same turn)

1. `gh workflow run scheduled-followthrough-sweeper.yml --ref "$BR" -f dry_run=true` → the log must **contain** `issue #6617: DRY_RUN — would close with verdict=PASS`. **Measured, load-bearing:** under `DRY_RUN=1` the sweeper returns early and emits the `DRY_RUN — would <action> with verdict=<v>` spelling; the bare `verdict=<v> action=<a>` line is on the **live** path only, so asserting it here would fail every time. Read the `observed authorAssociation=` line from the same 600-byte tail; if the permission endpoint 403s, take the CODEOWNERS fallback, push, and re-run this step.
2. Quiesce: `gh run list --workflow=apply-inngest-rls-dev.yml --json status --jq '[.[]|select(.status!="completed")]|length'` → `0`. Re-assert after step 4.
3. `gh workflow run apply-inngest-rls-dev.yml --ref "$BR" -f mode=dry-run -f reason="#6488 rehearsal"` → `conclusion=success`, `head_sha == SHA_A`, report shows `tables_present=14 posture_ok=14` plus the four reported counters and the 14 per-table rows. **Read the 14 rows before authorising the drop** — that reading, not a static guard, is what confirms the name set. On `Unexpected inputs`, take the `reason`-carried fallback and re-dispatch.
4. `gh workflow run apply-inngest-rls-dev.yml --ref "$BR" -f mode=drop -f reason="#6488 drop"` → `conclusion=success`; the log echoes the exact `DROP TABLE` statement immediately before its POST; the summary reports `tables_remaining=0`.
5. From the terminal: the `#6488` probe → exit 0, `PASS: all 14 dark-Inngest tables are gone`.
6. Capture the three run URLs and the echoed statement for the PR body and the ADR-100 addendum.

### Phase 3 — Commit B: retire the transient pieces, record, close

**Load-bearing:** once the drop has run, this commit reaches `main` even if the rest of the PR is abandoned (see Risks).

1. Delete `.github/workflows/apply-inngest-rls-dev.yml`, `0002_dev_inngest_tables_lockdown.sql`, `anon-probe.sh`, `inngest-rls-mutation.test.sh`, and both follow-through probes with their lint-baseline entries.
2. `git mv` the shape guard to `apply-inngest-rls-workflow.test.sh`, strip the `dev_*` block **together with `argv[2]`, the `dev =` load, `DEV_WF=` and the two dev asserts**, and update `inngest-rls.test.sh` per Files to Edit (hoisting the `ALLOW_14` cardinality guard first).
3. Registration sites, comment references, lint allowlists, the `fixture-relative-assert` baseline, and `scripts/lint-supabase-deprecated-endpoints.highwater` — **measure the new census at this commit and record which call sites left**, per that file's own provenance requirement.
4. ADR-100 addendum (the record carrying the three run URLs, the readiness readings and the echoed statement); ADR-030 amendment-log one-liner pointing at it; `expenses.md` corrected with a one-line pointer.
5. `gh issue edit --remove-label follow-through` on both trackers and replace each directive block with a retirement note, so no `<!-- soleur:followthrough` sits at column 0 in either body.
6. Re-run the Phase 1 step-7 suites plus the full registration set — the suite population changed again.
7. PR body: `## Changelog`; `Closes #6617`; `Closes #6488`; which dispatch arm ran; the three run URLs; the echoed DROP in a `<details>` block.

### Phase 4 — Post-merge verification (pipeline)

1. Merge-commit workflows green; `infra-validation` green with the renamed suite present in its log.
2. `git ls-files` of the retired paths on `main` → empty (the Observability discoverability command).
3. `gh workflow run scheduled-followthrough-sweeper.yml --ref main -f dry_run=true` → its log names neither tracker. Scoped to the two trackers, not to the run's overall colour: the sweeper reddens on truncation, a missing secret or a fenced directive anywhere on the 56-tracker page, so "the run is green" could be flipped by an unrelated tracker (`cq-ac-must-not-depend-on-concurrent-sessions`).
4. An ad-hoc Management-API read counting the 14 names in `pg_class` → 0 (the `#6488` probe no longer exists to do it).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing on the product surface — the 14 tables were never read by the application, soleur-dev is the development project, and the dedicated prd Inngest project is untouched (the workflow cannot name it: its `PROJECT_REF` is a pinned literal and the shape guard forbids the prd ref appearing in the file). The worst internal outcome is a red dispatch run on a dev-only workflow, watched synchronously, with the PR blocked until it is green.
- **If this leaks, the user's data is exposed via:** no vector — the change deletes tables that contained no user records (0 runs, 0 live events) and removes a lockdown that defended those empty tables; `SUPABASE_ACCESS_TOKEN` stays a repository secret consumed inside the runner, with the same `scrub_pat` redaction as today.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the only touched SQL file is a deleted dev-project lockdown whose 14 tables hold no user data, and the only workflow touched is dev-only and deleted in the same PR.`

## Observability

```yaml
liveness_signal:
  what: "the three pre-merge dispatch runs, each watched by a Monitor on `gh run watch <id> --exit-status` in the turn that dispatched it; after merge, the nightly follow-through sweeper is the standing signal that neither tracker is red"
  cadence: "per-dispatch (three runs, pre-merge); daily (sweeper) after merge"
  alert_target: "the pipeline session via Monitor for the dispatches; the sweeper's ::error annotations and issue comments for the standing signal"
  configured_in: ".github/workflows/apply-inngest-rls-dev.yml (transient, commit A); .github/workflows/scheduled-followthrough-sweeper.yml"

error_reporting:
  destination: "GitHub Actions run log and $GITHUB_STEP_SUMMARY for the drop workflow (no Sentry: a dev-only, one-time, synchronously-watched dispatch); the sweeper's existing issue-comment channel for the trackers"
  fail_loud: "the drop step exits 1 with `failure_mode=<identity_unreachable|identity_mismatch|catalog_precondition|drop_error|post_verify>` on the summary; the PR cannot advance to commit B while any dispatch is not `conclusion=success`"

failure_modes:
  - mode: "identity preflight rejects the pinned ref (wrong project name, unreachable API, or an absent secret surfacing as a non-200)"
    detection: "run red before any write; `failure_mode=identity_*` in the summary; Monitor reports the non-success conclusion"
    alert_route: "pipeline session; nothing was written, so no human paging is needed"
  - mode: "catalog precondition false (tables_present != 14 or posture_ok != 14)"
    detection: "the dry-run report in the run log plus `failure_mode=catalog_precondition`; the drop arm refuses"
    alert_route: "pipeline session; the report names the offending counter so the next action is data-driven"
  - mode: "DROP succeeds but the post-verify read returns non-zero"
    detection: "`failure_mode=post_verify`, run red; the #6488 probe re-read from the terminal"
    alert_route: "pipeline session; the PR stops before commit B — a partial drop cannot happen inside one statement, so this arm means the API is lying, not Postgres"
  - mode: "the verdict filter does not work under GITHUB_TOKEN (permission endpoint 403)"
    detection: "the sweeper dry-run log shows TRANSIENT or FAIL for #6617 instead of `would close with verdict=PASS`, and the probe's `observed authorAssociation=` line names what it actually saw"
    alert_route: "pipeline session; take the CODEOWNERS fallback and re-run"
  - mode: "after merge a tracker reappears as red (label left on, or directive left in a body)"
    detection: "the post-merge sweeper dispatch names #6617 or #6488; AC-1's `gh issue view --json labels,body` check"
    alert_route: "sweeper comment on the tracker (existing channel)"

logs:
  where: "GitHub Actions run logs for the three dispatches (URLs recorded in the PR body and the ADR-100 addendum); sweeper run logs"
  retention: "90 days (GitHub default); the ADR-100 addendum and the PR body carry the durable record"

discoverability_test:
  # Asserts the SURVIVING set, not the absent one, and that inversion is forced
  # rather than stylistic. preflight Check 10 matches by substring: it tokenises
  # `expected_output` and passes when any token appears in the probe's stdout, so
  # an expectation of "no output" can never match and an absence probe FAILs the
  # gate however correct it is. Measured at ship time on this very plan: the
  # earlier form ran `git ls-files` over the seven retired paths and printed
  # nothing — the right answer — and scored row 11 (expectation drift).
  # The absence half is asserted by AC-3 and AC-4, which are greps, not probes.
  command: "git ls-files apps/web-platform/infra/inngest-rls/"
  expected_output: "0001_enable_rls_lockdown.sql, apply-inngest-rls-workflow.test.sh, inngest-rls.test.sh"
```

## Gate dispositions (Phases 2.7–2.11)

- **2.7 GDPR** — fired (`.*\.sql$`: the deleted `0002`). One `Suggestion` (`GDPR-Art-17`): the change is a structure-only deletion, and the reported `runs`/`events` counters plus the dry-run's per-table row listing are the evidence that no records were erased without a record of their count. No `Critical`, no Art. 9 column-name match, no new column, FK or vendor. Corpus 5 days stale (fresh).
- **2.8 IaC routing** — skipped. No server, secret, vendor account, DNS record, cert, firewall rule or persistent runtime process is introduced; the one new surface is a CI workflow deleted in the same PR, and every step runs in GitHub Actions (no `ssh`, no vendor dashboard, no secret write).
- **2.11 Encryption posture** — skipped. No path matches the detection set (`\.tf$`, `supabase/migrations/.*\.sql$`, `cloud-init.*\.ya?ml$`, `docker-compose.*\.ya?ml$`); no persistent store and no new cross-component connection — the drop workflow makes the same TLS call to `api.supabase.com` that the file it replaces makes today, and then ceases to exist.
- **2.9.1 Soak enrollment** — not triggered: no acceptance criterion is time-gated (the post-merge sweeper check is a same-session manual dispatch), and nothing defers an issue's or an ADR's status change to a soak. Deliberate: no new follow-through is enrolled by a PR whose purpose is to retire two of them.

## Guard Contract

Two guards ship. The panel cut a third — a 10-row static shape block pinning the transient drop workflow — because a static guard buys *regression* value over time and that file has no time: it exists for one commit, never runs from `main`, is dispatched twice under synchronous observation, and echoes its exact SQL into the run log before the POST. The dry-run's 14 per-table rows, read before the drop is authorised, are stronger evidence of the name set than any static probe, and reading them is already a required step.

### Guard 1 — anti-vacuity floor on the RLS workflow shape guard

**Property.** The shape guard cannot report success while checking fewer things than it declares: its executed assertion count must equal a declared total.

**Assembly.** `apps/web-platform/infra/inngest-rls/apply-inngest-rls-workflow.test.sh` — the bash `assert` lines (the sole drivers of the `PASS`/`FAIL` counters) and the `checks` dict in the embedded python probe that each one reads. The chokepoint is the counter pair, asserted against `EXPECTED_TOTAL` at the file's last line.

**Correction, because the draft asserted a measurement that is false.** The draft claimed an emptied `checks` dict "would exit 0 with `passed=0 failed=0`". The panel ran it: **exit 1, `passed=0 failed=48`** — a missing key raises `KeyError`, the probe prints nothing, and each `assert` therefore FAILs. Today's suite is *not* vacuous in the way the draft described, and the #7493 framing was wrong. The floor is still worth adding, for the failure the draft did not name: deleting `assert` **lines** (rather than dict keys) silently lowers the count with everything still green — and this PR removes 25 of the suite's 40 keys, which is exactly the edit under which a hand-miscounted deletion hides. The matrix is written against that real property.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete an `assert` line and its `checks` key together (the shape a hand-edited cleanup produces) | RED — `PASS + FAIL` falls below `EXPECTED_TOTAL`; nothing else in the suite notices |
| 2 | Delete every key from the `checks` dict | RED — measured today as `passed=0 failed=48` via KeyError, and RED on the floor as well; both arms must hold |
| 3 | Make `assert()` never increment `FAIL` | RED — the floor still holds, but a known-bad inline fixture must register a FAIL; if it does not, the harness is lying |
| 4 | Point `PRD_WF` at a nonexistent path | RED — `prd workflow exists` / `prd YAML parses` |
| 5 | Must-PASS non-canonical: reflow the prd workflow's YAML, reorder step `name:` strings, add comments | PASS |

### Guard 2 — trusted-verdict filter (`scripts/lib/trusted-verdict.sh`)

**Property.** A `RESULT: PASS|FAIL` line changes a probe's exit code only when its author's repository permission, read with the token the probe runs under, is `admin`, `maintain` or `write`; a permission read that fails yields TRANSIENT, never PASS.

**Assembly.** The single comment-selection function in `scripts/lib/trusted-verdict.sh`, and every probe that sources it — **two live consumers**, `concierge-strand-754ee124-5733.sh` (open #5733) and `cpx22-invoice-reconcile-7431.sh` (open #7437), plus the transient 6617 copy. The lib is the chokepoint because the new `scripts/lint-followthrough-varq-ban.sh` rule forbids `authorAssociation` anywhere under `scripts/followthroughs/`, so a probe cannot re-inline its own filter and stay green — the mechanical rule is what makes "the lib is the chokepoint" a fact rather than an assertion. Exercised by `scripts/lib/trusted-verdict.test.sh` (the lib's own matrix, outliving any one consumer) plus a per-probe harness.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture: `RESULT: PASS` from a login whose permission stub returns `read`/`none` | probe exit ≠ 0 |
| 2 | Fixture: operator comment with `authorAssociation: CONTRIBUTOR` and permission stub `admin` (the measured #6617 shape) | probe exit 0 |
| 3 | Fixture: two trusted comments, PASS then FAIL | exit 1 — last verdict wins |
| 4 | Permission stub returns HTTP 403 | exit 2 TRANSIENT, never 0 |
| 5 | Delete the permission lookup and pipe `.comments[].body` straight to the grep | RED — row 1 would then pass |
| 6 | Add `authorAssociation` to any file under `scripts/followthroughs/` | RED — the new lint rule |
| 7 | Must-PASS non-canonical: a trusted verdict whose body has a leading blank line before `RESULT: PASS` | exit 0 |

**Harness integrity:** a fixture with the `author` field removed must make the test FAIL loudly rather than pass — a fixture without an author cannot exercise the filter, which is the exact defect #7448's learning file records. The live confirmation under `GITHUB_TOKEN` is **not** a matrix row; it is AC-5.

## Architecture Decision (ADR/C4)

### ADR

No new ADR. Two **amendments as dated addenda**, in scope for commit B: an ADR-030 amendment-log entry (I8's co-tenanted arm closes — the 2026-08-20 correction's "must not be retired" condition is now met, by date) and an ADR-100 addendum (`## Addendum — 2026-09-19 (#6488, #6617)`) carrying the three run URLs, the readiness readings, the echoed statement, and the `authorAssociation` cause that let #6617 outlive its own verdict. Neither ADR's `## Decision` changes; ADR-100 stays `adopting` (the flip is #7230). The addendum also records that no committed probe survives to re-answer "are the 14 still gone", so the next reader does not go looking for one.

### C4 views

**No C4 impact**, checked against all three model files. (a) External human actors — none new; the operator is already modelled. (b) External systems/vendors — Supabase is already modelled and carries an `inngest -> supabase` edge; the co-tenanted dev project and its dark tables were never modelled as elements (a grep for `soleur-dev`, the dev project ref, `inngest-rls` and `0002` over `{model,views,spec}.c4` returns zero), so removing them removes nothing from the model. (c) Containers/data stores touched — the dev Supabase project only, not a modelled element. (d) Actor↔surface access relationships — unchanged. Derived cardinalities: `plugins/soleur/test/c4-count-parity.test.sh` ran green (10/10) this session, and the deleted workflow carries no `sentry-heartbeat` step or `monitor-slug`, so none of its counted edges move. Re-run at commit B.

### Sequencing

The ADR-100 addendum is written in commit B, after the drop run exists, because it cites the run URLs. The retirement is complete at merge; nothing is soak-gated.

## Domain Review

**Domains relevant:** engineering

Assessed against all eight domain questions: Product, Marketing, Sales, Finance, Legal, Operations and Support are not relevant — no user-facing surface, no pricing or positioning, no revenue or expense change (the `expenses.md` edit corrects a note, not an amount), no new processing activity (the GDPR gate ran separately and returned one Suggestion), no vendor or account change, no support surface. The mechanical UI-surface override does not fire: no path in the Files sections matches `components/**/*.tsx`, `app/**/page.tsx` or `app/**/layout.tsx`. **Product/UX Gate tier: NONE.**

### Engineering

**Status:** reviewed
**Assessment:** The in-place rewrite, pre-merge dispatch and same-PR retirement are the right shape, and the dispatch precondition is measured rather than assumed. Five structural findings changed the plan (log spelling, count-vs-identity, two concurrency/abandonment windows, guard rows that tested bookkeeping, the filter change shipping without a harness); the simplification panel then removed a capability probe, a commit split, a confirmation literal, a freshness handshake, two negative dispatches and a transient shape-guard block; the devex pass caught two CI-red gates and the authoring-surface contradiction; and the correctness pass caught five P0s, four of them in the verification instruments — two proven by execution. Complexity: medium, dominated by the retirement sweep rather than the drop. Risk: low on the drop (identity + posture + no-`CASCADE`), low on sequencing, low on the filter change now that it has a committed harness and a mechanical rule. Dispositions: Review and Consult Provenance.

## Open Code-Review Overlap

- #7942 ("Two mutation batteries in plugins/soleur/test/ are named *.mutation.sh and run in no gate") touches `.github/workflows/infra-validation.yml`. **Acknowledge:** different files (`plugins/soleur/test/*.mutation.sh`); this plan only removes the `inngest-rls-mutation.test.sh` step, which is registered and named per the convention #7942 wants. No fold-in, no conflict.

## Review and Consult Provenance

Six independent lenses ran against this plan. All findings below classify **Mechanical** under ADR-084 (technical, one right answer) and were auto-applied; the two that challenge the operator's stated scope are in `decision-challenges.md` instead.

- **CTO, structural (Phase 2.5)** — 5 applied: the sweeper's dry-run log spelling; the count-vs-identity gap (→ the `posture_ok` assertion); the shared-`concurrency` and post-drop-`main` windows; guard rows that tested bookkeeping; the P7 change shipping without a harness. 2 recorded: the four weak counters demoted to reported, and the confirmation literal disclosed rather than trusted.
- **Advisor consult (ADR-083, curated payload)** — proposed a capability probe and an A1/A2 commit split; **both were subsequently cut** by the simplification panel (below) and its third unknown — whether the Supabase secret is readable from a non-default ref — was **measured instead of deferred**: a repository secret, no environment gate, readable from any branch.
- **DHH (overengineering)** — the sharpest finding, and it landed: P6 as drafted ("the PAT never leaves repo secrets") was **violated three times by the plan's own terminal reads**, so the workflow could not be justified on credential hygiene. Resolution was to fix the dishonest principle rather than the mechanism — P6 now claims only what the workflow actually buys (identity preflight and DROP in one process; an immutable run log). Also applied: cut the capability probe, the A1/A2 split, the confirmation literal, the freshness handshake, the negative dispatches, and the transient shape-guard block. **Not applied:** running the DROP from the terminal, and cutting the verdict-filter work entirely — see Alternatives.
- **code-simplicity (per-mechanism)** — concurred with DHH on every cut above and was more surgical where they diverged: it kept the in-place rewrite (P3+P6, nothing on `origin/main` buys it) and kept the transient 6617 filter fix, on the ground that it is the **only** probe carrying a real verdict comment from a private-membership author and therefore the only vehicle that can answer the permission-endpoint question. Its `anon_grants`-into-`posture_ok` fold and secret-present-into-identity fold were applied.
- **CTO, devex** — two CI-red findings that would have shipped: the Supabase census ratchet (CI runs `--check-highwater`; a plain-mode check is green locally) and the unregistered harness. Plus the highest-leverage edit in the change: `ship/SKILL.md` Step 3.5.B currently calls the `authorAssociation` filter *"mandatory"* and names a probe to copy, so the convention bullet would have been born contradicted.
- **Kieran (correctness)** — 5 P0s, four of them in the verification instruments. Two were proven by execution rather than argued: `probe()` opens `argv[2]` at module top level, so deleting the dev workflow reds **13 of 15** surviving `prd_*` probes (`passed=2 failed=46`); and AC-4's draft regex `[^\n]` is a negated set of the literals `n` and `\`, so the "no live references" gate returned clean while `run: bash …` references remained (re-verified here: the `xnx` spelling scores 0, `xqx` scores 1). Also applied: the census ratchet, the `fixture-relative-assert` row-equality baseline, the `ALLOW_14` cardinality guard stranded inside `profile_0002`, the inverted lint-allowlist rationale (the *rename* is what is mandatory, via `UNPINNED-HOST`), Rule D's scan scope reaching `scripts/lib/`, and a correction to this plan's own claimed measurement about the suite's vacuity (see Guard 1).

**One premise the panel shared and a measurement reversed.** Two reviewers argued `cpx22-invoice-reconcile-7431.sh` is dead code and that `trusted-verdict.sh` would therefore ship with a single consumer. It is enrolled on **open** issue #7437 and is named by `ship/SKILL.md` as the reference implementation — so the lib has two live consumers and a live authoring pointer, which is what settled the extract-vs-inline question.

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| **Run the DROP from the terminal instead of CI** (DHH, twice) | **Rejected, after fixing the principle it attacked.** The objection was sound — P6 as drafted claimed credential hygiene the plan violates on its own read steps. What survives the correction is narrower and real: the identity preflight and the DROP execute in one process, and the run log is a third-party record a pasted transcript is not. With every other cut applied the workflow is ~80 lines of YAML and two dispatches. |
| **Cut the verdict-filter work to a separate PR** (DHH; advisor DC-1) | **Rejected on a measurement.** Both argued it serves a different tracker and could wait. But #6617's probe is the only one carrying a real verdict comment from a private-membership author, so it is the only fixture that can answer the permission-endpoint question — and it is deleted by this PR. Doing it later means doing it blind. Recorded as DC-1 in `decision-challenges.md`. |
| **Inline the filter fix rather than extract a lib** (code-simplicity) | **Rejected on a measurement.** The premise was one live consumer; `cpx22-invoice-reconcile-7431.sh` is enrolled on **open** #7437 and is named by `ship/SKILL.md` as the reference implementation, so there are two live consumers and a live authoring pointer. |
| A capability probe on a scratch branch before choosing the workflow arm (advisor) | Rejected: its expected result is the documented 404, its one open question is unanswerable on that expected branch, and it makes the whole plan two-armed. The arm actually taken is already measured on `main`. |
| An A1/A2 commit split to bound unwind cost (advisor) | Rejected: both commits live on an unmerged branch, abandonment deletes the branch, and squash merge erases the boundary. The hazard it gestured at is handled by commit B being separate. |
| A new `drop-dark-inngest-tables-dev.yml` + post-merge dispatch + follow-up retirement PR | Rejected: cannot be dispatched pre-merge (404 on a branch-only file); two PRs; the leftover-workflow rot class (#4707). |
| Merge-apply the drop on `push: main` with a `0003_*.sql` | Rejected: fires the DROP on merge with no rehearsal on the same file, and still leaves the workflow to retire. |
| Rewrite #6617's probe to read `op=verify`'s exactly-once verdict | Rejected: duplicates the ADR-100 soak's authority (#6178) and keeps a nightly probe alive for a question answered on 2026-07-20. |
| Drop with `CASCADE`, or with `IF EXISTS` | Rejected: no-`CASCADE` *is* the dependent check, and `IF EXISTS` would paper over a partial state that `tables_present == 14` exists to catch. |
| A typed confirmation literal, and a write-counter freshness handshake | Rejected: `mode` already separates the arms; the literal adds a typo surface to guard an enum that cannot be typo'd, and the handshake guards a delta the plan has already fully accounted for. |
| Publish the operator's org membership (one API call, fixes all four filters) | Not chosen: profile visibility is a personal choice, not an engineering lever, and a code fix is more robust. Surfaced as DC-2. |

## Non-Goals

- The ADR-100 `adopting → accepted` flip (#7230), the Doppler secret-name hardening probe (#7761) and the Redis-AOF LUKS chain (#6894) — the operator's queue after this PR.
- Any change to the exactly-once soak (#6178) or to `op=verify`, which remain the post-cutover authority this plan defers to.
- Moving the Inngest schema out of `public` on the dedicated project (ADR-030's deferred spike).
- Restoring anything from the 14 tables.
- **Not a non-goal any more:** an earlier draft listed "retiring the dead `authorAssociation` filters" here on the premise that both remaining copies were inert. That premise was wrong — `cpx22-invoice-reconcile-7431.sh` is live on open #7437 — so it is migrated in scope, and `betterstack-quota-verdict-5105.sh` (genuinely closed, no harness) is deleted rather than left as a forgeable template.

## Acceptance Criteria

Nine, down from fifteen. The review panel cut six as phase-instruction paraphrases or attestations ("the runs exist", "the matrix was pasted", "CI passes"), and rewrote two whose verification commands could not answer the question they claimed to.

- [ ] AC-1 **Both trackers are retired.** `gh issue view 6617 --json state,labels,body` and the same for 6488 show `CLOSED`, no `follow-through` label, and no match for `^<!-- *soleur:followthrough` in either body (the anchor allows zero-or-more spaces, so a fixed-string grep for the single-space spelling would miss it).
- [ ] AC-2 **The 14 tables are gone.** The drop run reports `tables_remaining=0`, and the `#6488` probe exits 0 at `SHA_A` before it is deleted. At Phase 4 the probe no longer exists, so the re-check is an explicit ad-hoc Management-API read from the terminal counting the 14 names in `pg_class` — named here because an acceptance criterion whose executor the same PR deletes cannot otherwise be performed.
- [ ] AC-3 **The retired artifacts are absent from `main`**: `git ls-files` of the seven deleted paths prints nothing, and `apps/web-platform/infra/inngest-rls/` contains exactly `0001_enable_rls_lockdown.sql`, `apply-inngest-rls-workflow.test.sh` and `inngest-rls.test.sh`.
- [ ] AC-4 **No live reference survives.** `git grep -nE '(bash|source|run:|script=)[^[:space:]]*.*(apply-inngest-rls-dev|0002_dev_inngest|inngest-rls-drop-6488|inngest-doublefire-reading-6617|anon-probe\.sh|betterstack-quota-verdict-5105)' -- . ':!knowledge-base'` returns nothing. **The `.*` is load-bearing:** the draft used `[^\n]*`, which in POSIX ERE is a negated set of the literal characters `n` and `\` — not "any character but newline". Verified: `printf 'run: xnx apply-inngest-rls-dev' | grep -cE 'run:[^\n]*apply-inngest-rls-dev'` returns **0** while the `xqx` spelling returns 1, so the draft's gate would have reported clean while live `run: bash …` references remained. Prose references in surviving files are swept by hand (`## Files to Edit`) because no executable-shape grep can see them.
- [ ] AC-5 **The verdict filter works under the sweeper's token.** The sweeper dry-run log *contains* `issue #6617: DRY_RUN — would close with verdict=PASS` (a `contains` assertion, not `equals` — the line is prefixed with a `[HH:MM:SS]` stamp, and the dash is U+2014), and the 600-byte output tail carries the probe's `observed authorAssociation=` line. If the permission endpoint 403s instead, the CODEOWNERS fallback shipped and this AC asserts the same line after that arm.
- [ ] AC-6 **Every gate this diff moves is green in the mode CI runs it in**, including `bash scripts/lint-supabase-deprecated-endpoints.sh --check-highwater` (CI runs `--check-highwater`; the plain invocation computes the ratchet but only *returns* it under that flag, so a plain-mode check is green locally and red in CI), the renamed shape guard, `inngest-rls.test.sh`, both registration guards, `fixture-relative-assert.test.sh`, `lint-followthrough-varq-ban.sh`, `lint-shell-trace-credential-refusal.py`, `c4-count-parity.test.sh`, `lint-guard-contract.py`, and both new test files via `scripts/test-all.sh`. A failure reproducible on `origin/main` at the merge base is pre-existing and is recorded and filed per `wg-when-tests-fail-and-are-confirmed-pre`, not fixed here.
- [ ] AC-7 **The census ratchet moved with a reason.** `scripts/lint-supabase-deprecated-endpoints.highwater` carries the value measured at commit B and a provenance line naming which call sites left, per that file's own requirement that a number moved without a reason "stops being evidence of anything".
- [ ] AC-8 **Guard 1 and Guard 2 mutation rows were applied and the expectation observed**, with the observations in the PR body. Guard 2's rows run against committed fixtures in `scripts/lib/trusted-verdict.test.sh`, so they are re-runnable by anyone rather than attested once.
- [ ] AC-9 **The record exists and is singular.** The ADR-100 addendum carries the three run URLs, the readiness readings and the echoed `DROP` statement; ADR-030's amendment log and `expenses.md` each carry a one-line pointer to it; `followthrough-convention.md` carries the `authorAssociation` rule; and `ship/SKILL.md` Step 3.5.B no longer instructs the opposite.

## Test Scenarios

- Given `SHA_A` is pushed, when the drop workflow is dispatched with `mode=dry-run`, then it succeeds, writes nothing (a second dry-run reports identical counters) and prints the 14 per-table rows.
- Given the dry-run reported `tables_present=14 posture_ok=14`, when `mode=drop` is dispatched, then the run log echoes the exact statement immediately before its POST and a catalog re-read returns 0 of the 14.
- Given a hypothetical app table renamed onto one of the 14 names but carrying anon grants, when the dry-run runs, then `posture_ok < 14` and the drop arm refuses — exercised against a synthesized row in the query, not against the live catalog.
- Given the operator's org membership is private, when the sweeper runs the fixed 6617 probe under `GITHUB_TOKEN` with `dry_run=true`, then the log contains `would close with verdict=PASS` and the tail carries the `observed authorAssociation=` line.
- Given a fixture comment `RESULT: PASS` from a login whose permission is `read`, when either live probe runs, then it does not exit 0.
- Given the permission endpoint returns 403, when a probe runs, then it exits 2 (TRANSIENT) and never 0.
- Given commit B, when `test-infra-suite-registration.sh` and `run-registered-suites.test.sh` run, then both report the renamed suite registered with no stale entries and no missing suites.
- Given commit B, when `apply-inngest-rls-workflow.test.sh` runs with the dev workflow deleted, then all surviving `prd_*` probes pass — the regression Kieran measured (`passed=2 failed=46`) must not reproduce.
- Given commit B, when `scripts/lint-supabase-deprecated-endpoints.sh --check-highwater` runs, then it exits 0 against the re-measured census.
- Regression: given `apply-inngest-rls.yml` is edited to a `**` path glob on a scratch branch, then the renamed shape guard goes red.

## Success Metrics

- Nightly sweeper FAIL comments on #6617 and #6488 drop from 2/day to 0/day from the first tick after merge.
- `apps/web-platform/infra/inngest-rls/` shrinks from 6 files to 3; `.github/workflows/` loses one workflow; `scripts/followthroughs/` loses three probes and gains one harness.
- The `authorAssociation` filter goes from four hand-copied instances with no test to one tested lib with two live consumers, a mechanical rule blocking the alternative, and an authoring surface that names it.
- Learning item 19 moves from UNRESOLVED to a measured cause with a rule in the convention.

## Dependencies & Risks

- **Input-schema validation against `--ref`**: fallback documented (carry the mode in `reason`); decided at the first dispatch and recorded.
- **Permission endpoint under `GITHUB_TOKEN`**: unmeasured until Phase 2 step 1; CODEOWNERS fallback documented, and the probe prints what it actually observed either way.
- **Actions queueing**: dispatch runs can sit queued behind a repo-wide backlog; a silent Monitor expiry is a re-arm signal, not a verdict.
- **The post-drop / pre-merge window is a live `main` hazard, not an accounting one.** Once the drop has run, `main` still carries `0002` and the apply workflow, whose positive sentinel now aborts against absent tables. If the PR stalls, `main` holds a latent red that fires on the next push touching any of the four trigger paths. **Recovery rule: once the drop has run, commit B reaches `main` regardless of what happens to the rest of the PR** — if the PR must be abandoned, extract commit B as a minimal deletion PR. The reverse window (the branch having no lockdown while the tables exist) is safe: the RLS/grant posture lives in the catalog and is not re-asserted at read time.
- **The sweeper may close #6488 before the merge.** Between the drop and the merge, the nightly tick runs the probe from `main` (still present there), gets exit 0, comments and closes #6488 on its own. Correct and harmless, but it makes `Closes #6488` a no-op and AC-1's body edit run against an already-closed issue. Either land the PR the same day or record the auto-close in the PR body as the expected path.
- **Irreversible on dev.** Accepted: the 14 hold no data worth keeping and there is no restore path. The dry-run's per-table listing in the run log is the record of what was there.
- **PR body keyword hygiene**: only the two intended `Closes` adjacencies; prose about other trackers (#5733, #6178, #7230, #7437, #7942) uses `Ref`. **`Closes` is correct here, and that is the inverse of the usual ops-remediation rule** — a fix executed *post-merge* must use `Ref` because `Closes` auto-closes before the remediation runs. This drop executes **pre-merge**, so both trackers are genuinely satisfied at merge time.
- **Network calls in CI stay bounded and sanitized**: the drop step keeps `--max-time 30` on every curl and routes every API body through the copied `sanitize` (`strip_log_injection` + `scrub_pat`) before it reaches a log line, a `$GITHUB_OUTPUT` value or an issue body.

## References & Research

- `knowledge-base/project/plans/2026-07-15-security-soleur-dev-inngest-rls-lockdown-plan.md` Phase 5 (the original drop prescription and its corrected rationale).
- ADR-030 I8 and its amendment log; ADR-100 addenda 2026-08-20 (#7462), 2026-09-15 (cutover completed), 2026-09-19 (#6178 soak reading).
- Learnings listed under Research Insights.
- Runs: sweeper 35465233346 (2026-09-19, the FAIL this plan removes); doublefire-probe 29748606817 (2026-07-20, the recorded reading); registry-probe 34948634783 (2026-09-15).
- PRs: #6485 (source of #6488), #6748 (source of #6617's enrolment); #7451 and #6748 are the collision-gate citations that close other issues.
