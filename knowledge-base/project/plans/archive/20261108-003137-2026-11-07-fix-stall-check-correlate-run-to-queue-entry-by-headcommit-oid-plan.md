---
title: "merge-queue-stall-check: correlate temp-ref runs to the queue entry by headCommit.oid"
date: 2026-11-07
slug: stall-check-correlate-run-to-queue-entry-by-headcommit-oid
branch: feat-one-shot-12320-stall-check-headcommit-oid
issue: 12320
closes: 12320
type: fix
lane: cross-domain
brand_survival_threshold: none
---

# merge-queue-stall-check: correlate temp-ref runs to the queue entry by headCommit.oid

Spec lacks valid lane: - defaulted to cross-domain (TR2 fail-closed). No brainstorm and no `spec.md` exist for this branch; the brief is the spec.

## Enhancement Summary

**Deepened on:** 2026-11-07
**Method:** the deepen-plan halt gates run mechanically against this file (4.6 user-brand impact, 4.7 observability fields, 4.8 PAT sweep, 4.11 guard-contract lint, 4.12 scope-check count and recommendation; 4.9, 4.10, 4.13 do not trigger: no UI file, no `.tf`/migration/compose file, no new autonomous task), the quality checks (every cited issue and PR number and the cited SHAs resolved live, every cited rule id found in `AGENTS.md`/`AGENTS.rules.md`, no filler tokens), and the review that already ran on this plan: three plan-review seats (DHH-lens, Kieran-lens, simplicity) plus two batched CTO rulings. The skill's open-ended fan-out of 20-40 agents was not run: the change is one bash+jq function and its mutation-scored suite, the design forks are already ruled, and every claim a fan-out would re-check was re-read against the real files by the correctness seat.
**Review agents used:** `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, `soleur:engineering:cto` (x2).

### Key Improvements
1. Plan-review cut the machinery to what the properties need: no `-` sentinel, no body clause, no stub-control row, 8 mutants instead of 12, one guard instead of two (CTO E1-E3).
2. The correctness seat verified, by running them, the bash/jq behaviours the plan relies on (trailing empty TSV field under tab-IFS, `[[ =~ {40} ]]` rejecting empty/uppercase/short, `${3-}` under `set -u`, prefix-assignment on a function call) and pinned the mutation anchors that would otherwise be ambiguous (full guard expression; notice tail plus `continue`; all three C11 occurrences).
3. The premise correction (a live failed-load push run does exist) is carried into the PR wording as observed / transitive / not observed.

### New Considerations Discovered
- The `discoverability_test` grep counts the literal `headCommit { oid }`; comments and notices must spell `headCommit.oid` so the count stays 1 (Phase 2 step 4, and an acceptance criterion below).
- A two-argument `queue_candidate_cause` caller reads as "cannot correlate" and could pass a row vacuously: Phase 1 greps every call site first, and the L24 driver passes the oid as the third argument (C20 must stay RED).
- Residual to watch after merge (CTO risk 1): if GitHub nulls `headCommit` for a built entry whose required check never reported, every named cause degrades to "suspected"; the null `::notice::` is the signal and the flip evidence is stated in Decision Record D8.

## Overview

`.github/workflows/merge-queue-stall-check.yml` (PR #12295) names the likely cause of a merge-queue stall by joining a stalled entry's latest temp ref (`gh-readonly-queue/main/pr-<N>-<40hex>`) to the Actions runs on that ref. It never checks that those runs belong to the entry's own commit. A stale run on a reused or superseded ref can therefore be attributed to a newer entry (the unrelated-broken-push caveat the brief calls the "wrong-workflow caveat").

This change adds the missing correlation: read `headCommit { oid }` for each queue entry, keep `head_sha` on the run records, and name a cause only when the failed push run's `head_sha` equals the entry's `headCommit.oid`. A QUEUED entry has `headCommit` null; that means "cannot correlate" and files the unchanged "suspected" form, and it is never reported as a mismatch. The arm is purely subtractive: it can turn a named cause into "suspected" and never the reverse. The wording "LIKELY CAUSE (inferred from the run signature)", the title form and the whole issue body do not change.

Operating constraints carried from the brief (binding): PR body says `Closes #12320` and `Ref #9927` (never closes the epic); nothing operator-held is touched; Operating constraints carried from the brief (binding): PR body says `Closes #12320` and `Ref #9927` (never closes the epic); nothing operator-held is touched; technical forks go to the CTO agent (done, see `## Decision Record`); no `sleep` or background polling in Bash (Monitor only); `gh pr merge` runs as a bare command; per-PR tally cited from `plugins/soleur/scripts/pipeline-tally.sh show`.

## Research Insights

### Premise Validation (Phase 0.6)

- `#12320` is OPEN, no closing PR. Epic context `#9927` is operator-held and is only ever referenced with `Ref`. The draft PR `#12350` that the collision pre-check reports as "naming #12320" is this branch's own auto-created draft (headRefName equals this branch), not a competing change. The seven foreign `test-all.sh` processes it lists belong to other worktrees (CPU contention only; run suites with an explicit generous timeout).
- The decision `D7` cited by the issue now lives at `knowledge-base/project/specs/archive/20261107-165123-feat-one-shot-ci-duplicate-yaml-key-guard-queue-stall/decision-challenges.md` (the issue text still names the pre-archive path).
- **Live re-verification, 2026-11-07 21:09Z, read-only `gh api graphql` + Actions API** (the brief required this before building):
  - The queue held 4 entries: position 1 PR 12326 and position 2 PR 12325, both `AWAITING_CHECKS` with `headCommit.oid` set; positions 3 and 4 (PR 12338, PR 12341) `QUEUED` with `headCommit: null`. This confirms the null-on-QUEUED claim.
  - PR 12326 (oid `c3210a2aef...`, ref `pr-12326-6529be1a57...`): 7 `merge_group` runs on the ref, 7 of 7 have `head_sha == headCommit.oid`. PR 12325 (oid `a2075a2e10...`, ref `pr-12325-c3210a2aef...`): 7 of 7. Run kind: `merge_group`. Chaining holds: the ref suffix of PR 12325 is PR 12326's oid, and the merged entries PR 12295, 12306 and 12334 show each ref's runs at the previous entry's tip.
  - **Correction to the brief** ("no live failed-load push run existed"): one does exist. Run `42336368201` (event `push`, name equal to its path `.github/workflows/ci.yml`, conclusion `failure`, ref `pr-12275-1d2efed77...`) has `head_sha` `6eafbf40f217`, and all 6 `merge_group` runs on that same ref have the same `head_sha`; that commit is the #12275 squash whose parent is the ref suffix. Run `42337331354` (ref `pr-12279-6eafbf40f2...`) has `head_sha` `a03d9b0ad807`, chained on the previous tip. What is genuinely NOT observed anywhere: the `headCommit.oid` of an entry while its own push run is failed (that entry has left the queue). So "failed push run head_sha equals headCommit.oid" is transitive: push equals its sibling merge_group runs on the ref, merge_group runs equal `headCommit.oid` on two live entries, and temp-ref suffix chaining. Per CTO D7 the PR and the fixture comment state exactly this split.
- Suite baseline measured in this worktree: `bash plugins/soleur/test/merge-queue-stall-check.test.sh` prints `=== 142 passed, 0 failed ===` and takes over two minutes (runs foreground with a 600000 ms timeout).
- ADR corpus check (Phase 0.6 item 4): `ADR-270` and `ADR-032` mention the stall check only as part of the merge-queue machinery; no ADR rejects an identity-correlation arm. No architectural decision is made here (see `## Architecture Decision (ADR/C4)`).
- Deepen-plan live checks (2026-11-07): cited issues and PRs resolved (`#12320` OPEN, `#9927` OPEN, `#12283` CLOSED, `#12295` MERGED, `#12275` MERGED, `#12279` MERGED, `#12350` OPEN draft of this branch); `6eafbf40f21701933a4b418b6dca0b7763fb310f` resolves via `gh api repos/jikig-ai/soleur/commits/...`; run `42337331354` has ref `pr-12279-6eafbf40f2...` and `head_sha` `a03d9b0ad807` (event `push`); `b2281fe9c6` is the #12295 squash on `origin/main`.

### Property List and Cut List (Phase 0.6b)

Properties the change must buy:

1. A cause is named only for a failed push run whose `head_sha` equals the entry's `headCommit.oid` (a stale ref on a newer entry never names a cause).
2. A null, absent or malformed `headCommit.oid` never names a cause, is reported with text distinct from a mismatch, and spends no Actions API call.
3. A mismatching candidate spends no history lookup, and one mismatching candidate never hides a matching one beside it.
4. The suite proves 1-3 by mutation (a deleted or inverted check turns a named row RED), not by the happy path alone.

Cut List (mechanism, property, what already covers it):

- Select the temp ref by `oid` instead of newest `created_at` (CTO D3 option B): rejected; it would resurrect a cause on an older ref that the existing latest-ref guard deliberately drops, and changes selection semantics for no gain. Keep select-then-verify.
- A new `headCommit` field in the GraphQL query for the triage step in the issue body (`Triage` step 1): cut; it buys no listed property.
- The jq-side `head_sha` validation and `-` sentinel (CTO D3 first ruling, revoked by E1): the function's first statement already requires a non-empty 40-hex oid, so no empty, short or textual `head_sha` can equal it; a trailing empty TSV field is safe under tab-IFS `read`.
- The observed `headCommit.oid (<oid>)` clause in the cause paragraph (CTO D5 first ruling, revoked by E2): it answered no ask, and the body stays true without it, so it stays byte-identical.
- Row L30 (stub projection control), the `mkrun_sha` wrapper, and mutants for log text and call ordering (see Phase 3): the assertions stay in rows L28/L29; C34 proves the stub projection end to end.
- A new workflow, cron or issue label: none needed; the existing step and function carry the arm.
- A separate issue for the wrong-workflow caveat: cut per the brief (it rides along).

### Repo and learning inputs

- Workflow anchors read: the `stalled` jq (TSV one line per entry), `fetch_runs` (projection lacks `head_sha`), `has_mg_history`, `queue_candidate_cause`, the per-entry loop, `cause_tmpl`. Suite anchors read: the `gh` stub (strips unselected GraphQL fields), `node()`, `mkrun()` (constant `head_sha`), `one_entry()`, rows L1-L26, mutation rows C1-C26 / Q1-Q14, `control_fails`, exact floor `EXPECTED_PASSES=142`.
- Learning `knowledge-base/project/learnings/2026-11-07-a-guard-must-equal-the-platforms-own-reader-not-yaml-semantics.md`: lesson 6 "grep the suite for the literal before editing a workflow line it mutates" (applies: the C11 mutant embeds the literal call `queue_candidate_cause "$pr" "$enq"`); lesson 5 "run suites foreground with a timeout and set the floor yourself".
- Learning `2026-10-06-a-non-completed-verdict-on-one-clock-false-pages-two-ways.md`: stub the thing, then mutate it; fixtures synthesized, never copied (`cq-test-fixtures-synthesized-only`).
- `scripts/ci-pr-affected-audit.accept.tsv` carries per-line accept rows keyed by suite, workflow file and a 12-hex line hash for this suite (rows 1350-1371). New fixture lines that spell a workflow path need a row or must reuse the `$WF_PATH_CI` variable; run the ratchet to find out (`python3 -I scripts/ci-pr-affected-replay.py ratchet`).

## Research Reconciliation - Spec vs. Codebase

| Brief / issue claim | Reality | Plan response |
|---|---|---|
| "keep `head_sha` in `fetch_runs`" | The `fetch_runs` jq projection is `{id, name, path, workflow_id, event, head_branch, conclusion, created_at, html_url}`; `head_sha` is dropped there. | ADD `head_sha` to the projection; the naming jq emits `(.head_sha // "")` as the LAST tab field; the byte-equality against the validated oid is the whole check. |
| "no live failed-load push run existed" | Run 42336368201 exists and is a failed-load push run; its `head_sha` equals its 6 sibling merge_group runs. | Keep the brief's required plain statement, made accurate: directly observed vs transitive vs not observed (CTO D7). |
| "the merge queue had 3 entries" | 4 entries at 21:09Z (2 built, 2 QUEUED). | Cite the counts as read at the time of re-verification. |
| "~40 lines, 2 files" (issue Fix-Size) | The suite is a mutation-scored harness with an exact pass floor; the stub strips unselected GraphQL fields, `node()` has no `headCommit`, `mkrun()` has a constant `head_sha`. | Honest sizing: about 40 workflow lines and about 150 suite lines (3 rows, 8 mutation rows, helpers); two files plus the audit ledger if the ratchet asks. |
| Issue cites `specs/feat-one-shot-ci-duplicate-yaml-key-guard-queue-stall/decision-challenges.md` | The directory was archived with a timestamp prefix. | Cite the archived path. |

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO consulted twice, batched (D3-D7, then E1-E3 for plan-review seat dissents), for the design forks; the rulings are recorded in `## Decision Record` and in `knowledge-base/project/specs/feat-one-shot-12320-stall-check-headcommit-oid/decision-challenges.md`. No product, legal, finance, marketing, sales, support or operations implication: a CI diagnostic workflow and its test suite, no user-facing surface, no data store, no vendor.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly. The stall check files an operator issue; a broken arm degrades a named cause to the existing "suspected" wording (the safe direction), or in the worst case a crash of the detection step leaves a stalled queue unreported, which the next 10-minute tick retries.
**If this leaks, the user's data is exposed via:** no data path. Strings from run records are untrusted and already validated before reaching an issue; the new field is a 40-hex string validated before the compare and never interpolated unvalidated.
**Brand-survival threshold:** none

threshold: none, reason: a read-only diagnostic workflow edit (no secrets, no user data, no new permission scope); the arm only ever removes a claim from an operator-facing issue.

## Hypotheses

The brief names no network or connectivity symptom (the Phase 1.4 trigger terms are absent); skipped.

## Architecture Decision (ADR/C4)

No ADR and no C4 change. Test from `plan` Phase 2.10: would an engineer reading only the ADRs and C4 be misled after this ships? No. Checked against `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` for this feature: external human actors (the operator reading a filed issue; unchanged), external systems (GitHub merge queue GraphQL and Actions REST API; both already modeled as the `github` system with the existing stall-check edge), data stores (none touched), actor-to-surface access relationships (unchanged). Derived cardinalities in edge prose (workflow and monitor counts): no workflow added or removed, so `plugins/soleur/test/c4-count-parity.test.sh` is expected to stay green; the work phase runs it to confirm.

## Observability

```yaml
liveness_signal:
  what: the stall-check run itself (dispatched by the Inngest cron every 10 minutes, schedule as fallback) plus a ::notice:: line in the run log when an entry cannot be correlated
  cadence: every 10 minutes (requested; delivery is degraded, see the workflow TIMING header)
  alert_target: the existing executor-visibility check-in in cron-merge-queue-stall-dispatch.ts (red or stuck previous run)
  configured_in: .github/workflows/merge-queue-stall-check.yml, apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts
error_reporting:
  destination: GitHub Actions run log (::warning:: for a failed read, ::notice:: for a null or mismatching oid) and the filed merge-queue-stall issue
  fail_loud: a GraphQL error fails the step (unchanged); a failed Actions read is fail-soft by design and files the suspected form
failure_modes:
  - mode: headCommit is null for a built entry whose required check never reported, so every named cause silently degrades to suspected
    detection: the ::notice:: "no usable headCommit.oid" in the run log of a stalled AWAITING_CHECKS entry; a stall issue with the suspected title and a load-failed ref
    alert_route: the filed merge-queue-stall issue (action-required label); flip evidence for CTO risk 1 is exactly this combination
  - mode: head_sha missing from the Actions reply, so every candidate mismatches
    detection: the ::notice:: "does not match the queue entry's headCommit.oid" on a stalled entry whose temp ref was just built
    alert_route: same issue; the suite mutant C32 pins the projection
  - mode: GraphQL schema rejects headCommit { oid }
    detection: the detect step fails (set -e) and the run goes red; the dispatcher reports the previous red run as an error check-in
    alert_route: Sentry check-in from cron-merge-queue-stall-dispatch.ts
logs:
  where: GitHub Actions run logs of the merge-queue-stall-check workflow
  retention: GitHub default (90 days)
discoverability_test:
  command: grep -c 'headCommit { oid }' .github/workflows/merge-queue-stall-check.yml
  expected_output: 1
```

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add headCommit{oid} to the GraphQL queue read" [brief] | Phase 2 step 1 | mapped |
| 2 | "keep head_sha in fetch_runs" [brief] | Phase 2 step 3 (add it; the projection lacks it, see Reconciliation) | mapped |
| 3 | "require headCommit.oid == run head_sha before naming a cause" [brief] | Phase 2 steps 4-6 | mapped |
| 4 | "A QUEUED entry has headCommit null: treat null as \"cannot correlate\" and fall back to the existing \"suspected\" wording, never as a mismatch" [brief] | Phase 2 step 4, rows L29, C29-C30 | mapped |
| 5 | "add fixtures with synthesized shas: stale-ref-on-new-entry (mismatch), null-oid, matching-oid" [brief] | Phase 1 rows L28, L29, L27 | mapped |
| 6 | "State plainly in the fixture/PR that push-run head_sha == headCommit.oid is shown only by temp-ref chaining" [brief] | Phase 1 fixture comment, Phase 5 PR body (made accurate per D7) | mapped |
| 7 | "The stall-cause wrong-workflow caveat ... rides along; no separate issue" [brief] | Phase 2 step 8 (header text), no new issue | mapped |
| 8 | "Keep the wording \"LIKELY CAUSE (inferred)\"" [brief] | title, lead paragraph and body unchanged (E2) | mapped |
| 9 | "Re-verify this live yourself against a real queue entry before building, and cite it in the PR" [brief] | Research Insights (done at plan time), Phase 0 re-run at build time, Phase 5 PR body | mapped |
| 10 | "Not in scope (ruled): non-ASCII key fold ... pr-quality-guards.yml ... F21 flake" [brief] | untouched | mapped |
| 11 | "Closes #12320 ... Ref #9927 never Closes" and "post a classification comment on #9927 (Ref only)" [brief] | Phase 5 / Phase 6 | mapped |
| 12 | "before pushing any PR that adds or changes a test suite run locally: ratchet, fixture-env-adoption, grep-q-pipe-guard, run-all registration" [brief] | Phase 4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| headCommit in query, equality check, null fallback | "require headCommit.oid == run head_sha before naming a cause" | asked |
| Short-circuit on a null oid before any Actions read, distinct ::notice:: texts | "treat null as \"cannot correlate\"" | asked (placement and notice text ruled by CTO D4) |
| Stub learns to keep `headCommit` only when the query selects `oid`; `node()` and `mkrun()` carry the field | "add fixtures with synthesized shas" | inferred - justification: without it the fixtures cannot express the case (the stub strips unselected fields, so an old query would not fail the new rows) |
| Eight mutation rows C27-C34 | "stale-ref-on-new-entry (mismatch), null-oid, matching-oid" | inferred - justification: the suite scores every load-bearing literal by mutation and ends on an exact floor; a row without a mutant is not scored |
| Raise `EXPECTED_PASSES` | - | inferred - justification: the floor is exact by design |

### Split Assessment

- Subsystems touched: 1 - `.github/workflows` + `plugins/soleur/test` (one feature, two files, plus possibly one ledger row file)
- Planned files: 2 to 4 | Estimated changed lines: about 200
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Decision Record

All forks went to the CTO agent (no operator question). Full table: `knowledge-base/project/specs/feat-one-shot-12320-stall-check-headcommit-oid/decision-challenges.md`. Plan review (DHH-lens, Kieran-lens, simplicity) dissented from two first rulings; the dissents were batched into one CTO call (E1-E3) and the plan below reflects the final rulings.

- D1 (brief-carried) build now, blocker lifted.
- D3 select-then-verify (not select-by-oid); `head_sha` is the LAST tab field. The first ruling's `-` sentinel is revoked (E1): emit `(.head_sha // "")`, no `tostring`.
- D4 null or malformed oid short-circuits before the enqueuedAt guard and before any Actions read with its own `::notice::`; a mismatch skips before `has_mg_history` with a different `::notice::`; both pinned as row assertions (`hist_calls == 0`, notice present / absent).
- D5 revoked (E2): the cause paragraph and title are unchanged; the correlation is documented in the workflow header only.
- D6 grouped-merge non-deepest members: accepted stated residual (fail-safe).
- D7 PR wording splits observed / transitive / not observed.
- E3 suite trimmed to 8 mutants (C27-C34), no L30, no `mkrun_sha`, Guard 2 merged into Guard 1; EXPECTED_PASSES expected 153.

## Implementation Phases

### Phase 0 - re-verify live and prove the query is schema-valid (before any edit)

1. Re-run the live read (`gh api graphql` for `mergeQueue(branch:"main") { entries(first:50) { nodes { position state enqueuedAt headCommit { oid } pullRequest { number url } } } }`) and the per-ref Actions read; record queue size, states, and `head_sha == oid` counts per built entry with the run kind (`merge_group`) for the PR body. If the queue is empty at build time, cite the 2026-11-07 21:09Z reading above and say so.
2. After Phase 2, extract the exact query text from the edited workflow and run it live once (read-only). A stub cannot prove GitHub accepts the selection; this can.

### Phase 1 - failing rows first (`cq-write-failing-tests-before`)

Edit `plugins/soleur/test/merge-queue-stall-check.test.sh` only (the workflow is untouched); run it and confirm the new rows fail for the right reason before Phase 2. Before editing, `grep -n 'queue_candidate_cause' plugins/soleur/test/merge-queue-stall-check.test.sh` and list EVERY call site and anchor (the L24 driver and the three C11 occurrences at least); a two-argument caller silently reads as "cannot correlate" and could pass vacuously.

1. Constants: `TIP_SHA` (the existing literal `2222222222222222222222222222222222222c22`, 40 lowercase hex, now named), plus synthesized `SHA_A` and `SHA_B` (invented 40-hex values, never copied from a real run). A fatal `exit 2` self-check (not a `pass`, so the count is unaffected) asserts each is 40 lowercase hex so a typo cannot turn a negative row vacuous.
2. Stub (the `gh` heredoc): in the `api graphql` branch add `--argjson oid "$(has oid)"` and `| (if $oid then . else del(.headCommit) end)`; list `headCommit.oid` among the selectable fields in the stub header comment.
3. Helpers: `node <pos> <min-ago> <pr> [state] [oid|null]` adds `headCommit` (`null` token gives JSON null, default `TIP_SHA`); `mkrun` takes `head_sha` from `${MKSHA:-$TIP_SHA}` instead of the constant (callers use the inline `MKSHA=<sha> mkrun ...` / `MKSHA=<sha> mg_noise ...` prefix, which is visible in nested calls and restored afterwards; no wrapper function); `one_entry <wf> <pr> <runs-file> [oid [state]]`. Defaults keep every legacy row byte-equivalent: entry oid equals run head_sha, so L1-L26 stay green on the new workflow (monotonicity check).
4. L24 driver: the printf template gains a second `%q`; the call becomes `queue_candidate_cause 101 <enq> <tip>` with a valid 40-hex oid as the THIRD positional argument, so the `empty`/`garbage` kinds still reach the enqueuedAt guard and C20 stays RED once the driver is edited (verify C20 explicitly after the edit).
5. New cause rows, added to `CAUSE_ROWS`, `ldesc`, and the rows loop. Every assertion message carries its row label (`want` is matched against it); `check_named`/`check_suspected` keep their signatures (the body is unchanged, so no oid parameter):
   - **L27 matching-oid (non-canonical shas)**: entry oid `SHA_A`; the failed push run and the six merge_group noise runs all carry `SHA_A`; expects the named form (`check_named`) and `hist_calls 111 == 1`. The fixture comment states plainly: push-run `head_sha == headCommit.oid` is shown only through temp-ref chaining and sibling merge_group runs; no entry's `headCommit` was ever read while its push run was failed (D7).
   - **L28 stale-ref-on-new-entry (mismatch)**: (a) control - the same runs with oid `SHA_A` name the cause; (b) entry re-enqueued with new oid `SHA_B`, the failed push run (created inside the 5-minute slack, on the old ref) and its noise carry `SHA_A`: `check_suspected` with the lookup-ran assertion, `hist_calls 111 == 0`, the mismatch `::notice::` present and the null `::notice::` absent; (c) two candidates on one ref where the mismatching one sorts FIRST (`aa-stale.yml`, workflow 113, `SHA_B`; `set_ever 111 113`) and `ci.yml` matches: only `ci.yml` is named and `aa-stale.yml` appears nowhere (per-candidate skip, not an abort; unreachable in production because one ref's runs share a `head_sha`, kept as the stops-at-first-member row of the guard contract); (d) a candidate run with no `head_sha` and a valid oid: suspected.
   - **L29 null-oid (cannot correlate)**: (a) control - same runs, valid oid, named; (d) FIRST after the control, null oid and runs that carry no `head_sha` at all: suspected (empty must never equal empty); (b) `headCommit: null` on a `QUEUED` entry: `check_suspected ... none`, unchanged title and body, ZERO `actions/` calls in the gh log, the null `::notice::` present, the mismatch `::notice::` absent; (c) malformed oids (uppercase 40-hex, 39 chars, `not-a-sha`): same as (b). Ordering matters: each sub-case message names itself so the mutant rows below match `L29 \(d\)` or `L29 \(b\)` distinctly.
6. Run the suite foreground (timeout 600000): the new rows fail for the right reason, the legacy rows pass.

### Phase 2 - the workflow edit (`.github/workflows/merge-queue-stall-check.yml`)

1. GraphQL selection: add `headCommit { oid }` after `state` in the `entries(first:50)` node block (same 24-space indent; keep `Q3`'s anchor `state\n` intact).
2. `stalled` jq: append a sixth TSV field `\(.headCommit.oid // "")` LAST; the loop becomes `read -r pr age url state enq oid` (a trailing empty field is safe under tab-IFS; an empty middle field would not be). Update the comment above it.
3. `fetch_runs` projection: add `head_sha`.
4. `queue_candidate_cause <pr> <enqueuedAt> [<oid>]`: `local pr="$1" enq="$2" oid="${3-}"` (an unset third argument defaults to empty, so `set -u` cannot abort). FIRST statement, one contiguous unique line `if ! [[ "$oid" =~ ^[0-9a-f]{40}$ ]]; then`: print `::notice::merge-queue-stall: PR #<pr>: the queue entry has no usable headCommit.oid (a QUEUED entry has none); cannot correlate a run to it, so no cause is named.` and `return 0` - before the enqueuedAt guard and before any Actions read. Write `headCommit.oid` (never `headCommit { oid }`) in comments and notices so the Observability discoverability grep counts exactly one query occurrence.
5. Naming jq: emit a fifth tab field after the workflow id, `(.head_sha // "")`, still `@tsv`, still last. Selection logic (latest ref, name equals path, no merge_group run of that workflow on that ref) is unchanged (CTO D3 option A).
6. Candidate loop: `while IFS=$'\t' read -r ref p u w hs; do`; first, on ONE contiguous line `if [[ "$hs" != "$oid" ]]; then`, then a notice line ending `(stale or foreign ref); not attributing the stall to it."; continue; fi` (the notice and `continue` on one line so the C31 anchor is unique), THEN `if has_mg_history "$w"; then` (unchanged). Both notices avoid the phrase `could not read`. `ref` and `p` are already validated by the jq regexes; no unvalidated text is printed. Add `hs` to the function's `local` list.
7. Call site: `queue_candidate_cause "$pr" "$enq" "$oid"`. The cause paragraph template and the title are NOT changed (CTO E2).
8. Header comment (CAUSE NAMING paragraph), about 6 lines: what is compared; the null rule; the narrowed caveat and what remains; the two stated residuals (grouped-merge non-deepest member never gains a cause, fail-safe; a null `headCommit` on a built, never-reporting entry would silently degrade every cause to suspected, flip evidence per CTO risk 1). The observed / transitive / not-observed split goes in the PR body and the fixture comment. Keep the S11 and S12 text-arm phrases intact.
9. `python3 -I .github/scripts/check-workflow-duplicate-keys.py` and `actionlint` if present; the structural rows S4-S9 stay green (no new `${{ }}`, no new permission).

### Phase 3 - mutation rows (C27-C34) and the floor

Add after C26, using `mutate_lit` (each anchor must exist and be unique in the pristine workflow; the engine fails loudly otherwise). First update C11: ALL THREE occurrences of the literal `queue_candidate_cause "$pr" "$enq"` (the old anchor, the new insertion, and the copy inside the second replacement) become `queue_candidate_cause "$pr" "$enq" "$oid"`; leave the suite's other anchors alone (grep first).

| Row | Edit to the workflow (anchor) | Named row that must go RED |
|---|---|---|
| C27 | equality check removed (the contiguous `if [[ "$hs" != "$oid" ]]; then` line becomes `if false; then`) | L28 |
| C28 | equality inverted (`!=` becomes `==` on that line) | L27 |
| C29 | null short-circuit removed (the full `if ! [[ "$oid" =~ ^[0-9a-f]{40}$ ]]; then` line becomes `if false; then`) | L29 (b) (fetch calls made, null notice absent) |
| C30 | oid validation loosened (the full guard expression's `{40}` becomes `{0,40}`) | L29 (d) and (b) (an empty oid reaches the compare; empty equals empty names a cause) |
| C31 | mismatch branch aborts the loop (the notice tail plus `continue` becomes `return 0`) | L28 (c) (a first mismatching candidate hides the matching one) |
| C32 | `head_sha` removed from the `fetch_runs` projection | L27 |
| C33 | call site drops the third argument | L27 |
| C34 | `headCommit { oid }` removed from the query | L27 |

Cut by CTO E3 (do not re-add): log-text mutants, the history-call ordering mutant (the `hist_calls == 0` assertion stays in L28 (b)), the sentinel and the oid-clause mutants, row L30, the `mkrun_sha` wrapper.

`EXPECTED_PASSES` is set from the count the suite actually prints (expected 153 = 142 + 3 cause rows + 8 mutants); run the suite and write the observed number in the same edit.

### Phase 4 - local gates before the single push (batch every fix; a push restarts the ~40 minute shard run)

Run each, foreground, with explicit timeouts, and record rc:

1. `bash plugins/soleur/test/merge-queue-stall-check.test.sh` (expects the observed count, 153 expected, equal to `EXPECTED_PASSES`).
2. `python3 -I scripts/ci-pr-affected-replay.py ratchet`; if it asks for accept rows for new workflow-path-naming lines in the suite, add them to `scripts/ci-pr-affected-audit.accept.tsv` with the existing false-positive reason, or reuse `$WF_PATH_CI` so no new line spells a path.
3. `bash plugins/soleur/test/fixture-env-adoption.test.sh`.
4. `bash .claude/hooks/grep-q-pipe-guard.test.sh` (its `PJ_TRIPLES` pass-through row for this suite names the wrapper jq; adjust only if it fires).
5. `bash plugins/soleur/test/c4-count-parity.test.sh` (confirms "no C4 impact").
6. `python3 -I scripts/lint-guard-contract.py knowledge-base/project/plans/2026-11-07-fix-stall-check-correlate-run-to-queue-entry-by-headcommit-oid-plan.md`.
7. The suite's own registration: it is already glob-registered (`scripts/suite-shard-legs.tsv` leg 5, `scripts/lib/test-affected-paths.sh`); the `.github/scripts/test/run-all.sh` registration is checked, not assumed (state the result).
8. Phase 0 step 2: the live schema-validity probe of the exact query text.

### Phase 5 - ship (handled by `soleur:ship`; constraints for it)

- PR body: `Closes #12320`, `Ref #9927`, the live re-verification block (queue size and states, `head_sha == oid` counts, run kind `merge_group`, and the failed-load run 42336368201 with run kind `push`), the D7 observed / transitive / not-observed split, residuals, and the `pipeline-tally.sh show` output for THIS PR. Re-read the body after every edit (a stale unfilled tally token fails the gates).
- CI claims: every claim states run kind and leg. A green `push` run of `ci.yml` is not Guard 1 evidence; only `merge_group` or `workflow_dispatch` runs on the SHA are.
- Queue: `gh pr merge` as a bare command; if the entry conflicts after a queue-mate lands, merge `origin/main`, resolve, push, re-arm; do not hand-sync while merely BEHIND and armed. After any merge from main run `python3 -I .github/scripts/check-workflow-duplicate-keys.py`.
- Review panels that simulate an inherited `GIT_DIR` use a throwaway repo; afterward check `git log main -1`, `HEAD`, and `git config --local --list` for leaked `user.*` or `commit.gpgsign`.
- Net-issue-flow counts bot-filed issues (stall issues 12347 and 12351 are filed today by this very probe); use the override marker only if the count is wrong.

### Phase 6 - postmerge and the #9927 comment

- Postmerge: merge_group evidence for this PR's queue entry with run kind and leg; deploy arm exact+success; KB archival read-back clean; the first post-merge `workflow_dispatch` or schedule run of `merge-queue-stall-check.yml` on the merged SHA is green (job `stall-check`) with the headCommit query accepted live; read its log for the `::notice::` lines against the live queue. Watch item (CTO risk 1): the next real stall issue should name a cause when its ref has a load-failed push run; if a built entry shows "no usable headCommit.oid", that is the flip evidence (drop to the old join).
- Post a classification comment on `#9927` that uses `Ref` only and does not close, edit or relabel it.

## Guard Contract

### Guard 1 - head-commit correlation gate

**Property.** A cause is named only when the entry's `headCommit.oid` is a valid 40-hex string and is byte-equal to the failed push run's `head_sha`; a null, absent or malformed oid is "cannot correlate" (its own notice, no Actions read, the unchanged suspected issue), so a run on a stale or foreign ref is never attributed to a newer entry and an empty value can never match.

**Assembly.** Every path by which a candidate can reach `CAUSE_PATHS`: the single candidate loop in `queue_candidate_cause` (the only writer of `CAUSE_PATHS`, `CAUSE_LINES`, `CAUSE_REF`, `CAUSE_N`), fed by exactly three producers - the `stalled` jq (`// ""` for the oid), the function's first statement (validation of the oid), and the naming jq (the one place that builds candidate rows from `fetch_runs` output, `head_sha` last) - and the one call site that passes `$oid`. The loop reads each candidate's own `head_sha`, not a per-ref summary, so a second candidate on the same ref is checked separately. The validated oid is the single defence against empty equalling empty (no second sentinel).

**Mutation matrix.**

| # | Edit (must drive the guard RED) | Why it matters |
|---|---|---|
| 1 | Remove the equality check (C27) | a stale ref names a cause again |
| 2 | Invert it (C28) | a matching candidate is dropped |
| 3 | Remove the null short-circuit (C29) | a null spends fetches and reports the wrong notice (null conflated with mismatch) |
| 4 | Loosen validation to accept empty (C30) | the one row where the precondition holds (a run with no head_sha) and the property still fails: empty equals empty names a cause |
| 5 | `continue` becomes `return 0` in the mismatch branch (C31) | a second member added after a mismatching first is never checked (stops-at-first-member) |
| 6 | Drop `head_sha` from the `fetch_runs` projection (C32) | every candidate mismatches, the arm silently kills all naming |
| 7 | Call site drops the third argument (C33) | the oid never reaches the function, every entry reads as null |
| 8 | Drop `headCommit { oid }` from the query (C34) | the guard's own input is gone; also proves the stub projection end to end |

**Harness rows.** Suite edit that must go RED: the legacy named rows depend on the `node()` default carrying `headCommit` equal to `TIP_SHA`; during Phase 1 step 3 run the pristine suite once with that default removed and record that the legacy named rows fail (proves the monotonic default is load-bearing). Must-PASS non-canonical inputs: L27 uses invented `SHA_A` (not the default `TIP_SHA`); L28 (a) and L29 (a) are same-fixture controls that must name the cause, so a guard that rejects everything cannot pass.

**Anchor.** The compared value is not a stored hash: both sides are read live in the same run (GraphQL and Actions REST). The independent anchor for the premise is the 2026-11-07 live reading in Research Insights (7 of 7 per built entry, run 42336368201 against its siblings); a weakening of the check changes only the workflow, and the suite (not the workflow) is the other half, which is why C27-C34 live in the suite and the pass floor is exact.

## Files to Edit

- `.github/workflows/merge-queue-stall-check.yml`
- `plugins/soleur/test/merge-queue-stall-check.test.sh`
- `scripts/ci-pr-affected-audit.accept.tsv` (only if the ratchet reports new spell-a-workflow-path lines)
- `.claude/hooks/grep-q-pipe-guard.test.sh` (only if its pass-through row for this suite fires)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-12320-stall-check-headcommit-oid/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-12320-stall-check-headcommit-oid/decision-challenges.md`

(The plan file itself is `knowledge-base/project/plans/2026-11-07-fix-stall-check-correlate-run-to-queue-entry-by-headcommit-oid-plan.md`.)

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200 rows) was searched with a standalone `jq --arg` for `.github/workflows/merge-queue-stall-check.yml` and `plugins/soleur/test/merge-queue-stall-check.test.sh`; zero bodies name either path.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] The detection step selects `headCommit { oid }`; the exact query text, extracted from the edited workflow, is accepted by a live read-only `gh api graphql` call (Phase 0 step 2).
- [ ] `fetch_runs` keeps `head_sha`; the naming jq emits it as the last tab field with `-` for a missing or malformed value.
- [ ] A cause is named only when the candidate `head_sha` equals the entry `headCommit.oid`; verified by rows L27 (named, distinct invented shas), L28 (stale ref on a new entry: suspected, `hist_calls 111 == 0`, mismatch notice), and mutants C27, C28, C31, C32.
- [ ] A null, absent or malformed oid files the unchanged suspected title and body, makes zero `actions/` calls, and prints the null notice and not the mismatch notice; verified by row L29 and mutants C29, C30, C33.
- [ ] The title form and the lead sentence "LIKELY CAUSE (inferred from the run signature)" and the whole issue body are unchanged (existing `check_named`/`check_suspected` assertions stay green).
- [ ] Every legacy cause row (L1-L26 minus the stub controls) stays green unmodified apart from the helper defaults - the arm is subtractive.
- [ ] The suite prints `=== <n> passed, 0 failed ===` with `EXPECTED_PASSES` set to that observed `<n>` (153 expected), the run output cited.
- [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet`, `fixture-env-adoption.test.sh`, `grep-q-pipe-guard.test.sh`, `c4-count-parity.test.sh`, and `python3 -I .github/scripts/check-workflow-duplicate-keys.py` all exit 0 (rc recorded for each).
- [ ] `python3 -I scripts/lint-guard-contract.py <this plan>` exits 0.
- [ ] The `discoverability_test` command in `## Observability` prints exactly `1` against the edited workflow.
- [ ] The fixture comment and the PR body state the observed / transitive / not-observed split (D7) and the Guard 1 rule (a push-run `ci.yml` result is not Guard 1 evidence; run kind and leg stated per CI claim).
- [ ] PR body contains `Closes #12320`, `Ref #9927`, the live re-verification block, and the `pipeline-tally.sh show` output for this PR; no operator-held item is touched (A6 record, host-replace, G2e pin, PR #12275, `CI_ORACLE_LANE`, the `SOLEUR-DEBT` marker in `ci.yml`, doppler `inngest_arm_write`).

### Post-merge (operator-free, agent-run)

- [ ] `merge_group` evidence for the PR's queue entry cited with run kind and leg; the `ci.yml` required `test` shards are `merge_group` runs on the SHA.
- [ ] Deploy arm exact+success; KB archival read-back clean.
- [ ] First post-merge `merge-queue-stall-check.yml` run on the merged SHA (event `workflow_dispatch` or `schedule`, job `stall-check`) is green.
- [ ] Classification comment posted on `#9927` using `Ref` only.

## Test Scenarios

1. Matching oid with distinct invented shas names the cause and prints the correlated oid (L27).
2. Re-enqueued PR whose stale ref carries the old tip: suspected, no history call, mismatch notice (L28).
3. `QUEUED` entry with `headCommit: null`: suspected, zero Actions calls, null notice only (L29).
4. Uppercase / short / textual oid: behaves as null (L29 c).
5. Null oid with runs that carry no `head_sha`: suspected, never empty-equals-empty (L29 d).
6. Mismatching candidate sorting before a matching one: the matching one is still named (L28 c).
7. Each of C27-C34 turns exactly its named row RED with that row's own message and no crash signature.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only filler text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's threshold is `none` with a one-sentence reason because the diff touches a workflow path.
- `read` with `IFS=$'\t'` collapses adjacent tabs: any new TSV field must be LAST (the empty-last case is safe).
- The suite's mutation anchors are literal text. Before editing any workflow line, `grep` the suite for that literal (C11 embeds the `queue_candidate_cause` call).
- Both new notices must not contain the phrase `could not read`; `lookup_ran` treats it as a failed lookup.
- The suite's pass floor is exact and a full run exceeds two minutes: run it foreground with `timeout` 600000, never in the background, and set the literal from the observed count.
- Do not select the ref by oid; the arm is deliberately subtractive (CTO D3). A future change that makes it additive reopens the stale-ref hole.
- The live queue changes minute to minute: cite the reading with its timestamp and counts, not "the queue".
