---
title: "Reconcile lib/types vs runner WorkflowEndStatus enum drift (9→7)"
issue: 3827
parent_issue: 3243
adr_amendment: ADR-031
type: code-review-fix
classification: code-only
lane: single-domain
created: 2026-05-15
---

# Reconcile `lib/types` vs runner `WorkflowEndStatus` enum drift (9 → 7)

Closes `code-review` finding from PR #3823 / ADR-031. Ref #3243.

## Overview

`apps/web-platform/lib/types.ts:16-26` advertises a **9-status**
wire-protocol enum (`WORKFLOW_END_STATUSES`). The runner at
`apps/web-platform/server/soleur-go-runner.ts:631-652`
(`WorkflowEnd["status"]`) actually emits only **7** terminal states —
`sandbox_denial` and `runner_crash` are never produced.

ADR-031 documents this drift as pre-existing and explicitly chose the
runner's narrower union as the type source for
`cc-workflow-end-messages.ts` so its exhaustiveness rail aligns with the
actually-emitted set. This plan closes the drift by **narrowing the wire
enum to match the runner** (option (b) from the issue body).

### Decision: narrow the wire enum (option b), not extend the runner (option a)

The issue body offered two valid resolutions. The chosen path is
**option (b)** because:

1. **Both speculative statuses have lived ~2 months with zero emit
   sites.** `sandbox_denial` and `runner_crash` were added in PR #2902
   (Stage 3 protocol extension) but no `emitWorkflowEnded` call in
   `soleur-go-runner.ts` produces either status. The runner's
   sandbox-failure path (cc-dispatcher.ts:1077, agent-runner.ts:2138)
   mirrors to Sentry under `feature: agent-sandbox` then *re-throws* —
   the error surfaces to the client as a generic `error` WS event, not
   as `workflow_ended`. Adding `sandbox_denial` as a `workflow_ended`
   variant would require reclassifying that path (a behavior change),
   not just adding an emit site. **Sandbox-denial observability is
   preserved via the existing `feature: agent-sandbox` Sentry channel**;
   option (a) would duplicate the signal, not add one.
2. **`runner_crash` has no failure-mode semantic distinct from
   `internal_error`.** The runner already routes uncaught failures
   through `internal_error` (catch-all) and `runner_runaway` (idle-window
   / max-turn-duration). Inventing a third bucket without an operator
   benefit is dead surface area.
3. **YAGNI**: ADR-031's Negative section calls option (b) "the cheaper
   fix if they are vestigial" — the codebase audit above confirms they
   are vestigial.
4. **Cardinality alignment is the actual AC goal.** The
   `cc-workflow-end-messages.ts` exhaustiveness rail already covers all
   7 emitted statuses. Narrowing the wire enum makes
   `WORKFLOW_END_STATUSES.length === |WorkflowEnd["status"]|` and removes
   the `cc-dispatcher.ts:213` local re-derive's *raison d'être* (though
   the re-derive itself stays — ADR-031 #3827.3 documents that removing
   it is a separate concern).

Brand-survival threshold: `none` — dead-code cleanup with no
user-visible surface impact.

## Research Reconciliation — Issue Body Claims vs. Codebase Reality

| Issue body claim | Codebase reality | Plan response |
|---|---|---|
| Wire enum `WORKFLOW_END_STATUSES` has 9 entries | Confirmed: `lib/types.ts:16-26` literally contains 9 string literals | Use as authoritative |
| Runner union `WorkflowEnd` has 7 variants | Confirmed: `soleur-go-runner.ts:631-652` is a 7-arm discriminated union | Use as authoritative |
| Missing: `sandbox_denial`, `runner_crash` | Confirmed by set difference | Use as authoritative |
| "The runner never produces the two missing terminal states" | Confirmed: `rg "runner_crash\|sandbox_denial" apps/web-platform/` returns hits only in `lib/types.ts:22-23` (declaration) and `test/ws-protocol.test.ts:540-541` (round-trip test fixture). Zero `emitWorkflowEnded({ status: "sandbox_denial"\|"runner_crash" })` call sites. | Use as authoritative |
| PR #3823 / ADR-031 chose runner's narrower union as type source | Confirmed: `cc-workflow-end-messages.ts:5-7` imports `WorkflowEnd` from `./soleur-go-runner` and locally re-derives | Plan inherits this pattern; narrowing the wire enum aligns ws-zod-schemas + chat-state-machine + types.ts:300 with the runner without re-pivoting type sources |
| "Audit every consumer (clients reading WS payloads, log filters, dashboards) for breakage before merging" | Two in-repo consumers parse `workflow_ended.status`: `lib/ws-zod-schemas.ts:381` (`z.enum(WORKFLOW_END_STATUSES)`) and `lib/chat-state-machine.ts:128, 183` (reducer + lifecycle bar state). Both derive from the tuple-as-source, so narrowing is automatic. **External consumers** (Sentry dashboards keyed on the status string, log filters): no evidence of dashboards keyed on the two removed values — they were never emitted, so any dashboard filter on them was matching zero events. | Verify via grep at /work Phase 0; document in PR body |

## User-Brand Impact

- **If this lands broken, the user experiences:** no user-facing
  artifact. The two removed enum values have never been emitted by the
  runner, so the chat surface, lifecycle bar, and Sentry dashboards have
  never carried them. The only way to break this PR is a TypeScript
  error at compile time (caught by `tsc --noEmit`) or a vitest
  regression (caught by the full `apps/web-platform` suite).
- **If this leaks, the user's data is exposed via:** N/A. This is a
  type-narrowing of an internal status enum. No data-handling change, no
  new API surface, no exfiltration vector.
- **Brand-survival threshold:** `none` — dead-code cleanup. The
  `wg-after-merging-a-pr-that-adds-or-modifies` post-merge log scan is
  the only check needed.

## Open Code-Review Overlap

None — verified via:

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
jq -r --arg path "apps/web-platform/lib/types.ts" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
jq -r --arg path "apps/web-platform/server/soleur-go-runner.ts" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
jq -r --arg path "apps/web-platform/lib/ws-zod-schemas.ts" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
```

Plan to re-run at /work Phase 0 to confirm no new overlapping issue
landed between plan and work.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)

**Status:** reviewed (inline by planner — single-domain dead-code
cleanup with no architectural blast radius)

**Assessment:** This is a 2-line tuple edit plus test-fixture
narrowing. The narrowing direction is type-safe by construction:
removing union members can only *narrow* downstream consumers'
allowable inputs, never widen them. The Zod schema (`z.enum(...)`) is
derived from the same tuple-as-source, so it auto-narrows. The
`cc-dispatcher.ts:213` local re-derive (`WorkflowEndStatus =
WorkflowEnd["status"]`) is unaffected — it was already runner-bound.

No Product, Legal, Compliance, Brand, Growth, or UX implications: this
plan touches no user-facing string, no privacy surface, no marketing
asset, no UX flow.

## Files to Edit

1. **`apps/web-platform/lib/types.ts`** — remove `"sandbox_denial",`
   and `"runner_crash",` from `WORKFLOW_END_STATUSES` (lines 22-23).
   Update the JSDoc comment at lines 11-15. Post-edit wording (exact):

   ```ts
   /**
    * Terminal states a `/soleur:go` workflow run can end in. The
    * runner's `WorkflowEnd["status"]` union in
    * `server/soleur-go-runner.ts` is the canonical source; this tuple
    * mirrors it (enforced by `_AssertWorkflowEndStatusMatches` in
    * `soleur-go-runner.ts` — adding to either side without the other
    * is a TS error there). Both the Zod schema in
    * `lib/ws-zod-schemas.ts` and the TS union below derive from this
    * tuple. #3827 + ADR-031 amendment 2026-05-15.
    */
   ```

   The pre-edit comment claims "The tuple is the single source of
   truth"; that becomes misleading post-narrow because the runner
   union becomes the de-facto SoT and the tuple mirrors it. The exact
   wording above captures the new contract.
2. **`apps/web-platform/test/ws-protocol.test.ts`** — narrow the
   `workflow_ended round-trip with all 9 statuses` test (lines 532-551)
   to the 7 runner-emitted statuses. Rename test description to
   `workflow_ended round-trip with all 7 statuses`. Remove
   `"sandbox_denial"` and `"runner_crash"` from the `statuses` array
   (lines 540-541). Add a negative-case assertion: parsing
   `{ type: "workflow_ended", workflow: "plan", status: "sandbox_denial" }`
   MUST fail Zod validation (`r.ok === false`) — this pins the new wire
   contract.
3. **`apps/web-platform/server/soleur-go-runner.ts`** — add a
   **bidirectional cardinality assert** near the `WorkflowEnd` union
   (after line 652). Load-bearing rationale: the existing
   `_workflowEndExhaustive` (`cc-workflow-end-messages.ts:42`) and
   `_abortFlushExhaustive` (`cc-dispatcher.ts:247`) both derive from
   `WorkflowEnd["status"]` locally — they catch only
   *runner-widening-without-consumer-update*. They have **zero coupling**
   to `WORKFLOW_END_STATUSES`. The opposite direction — adding to the
   wire tuple without widening the runner — has no compile-time gate
   today (Zod would parse-fail at runtime on actually-emitted statuses
   if the runner widened without the tuple, but the wire-widens-runner-
   narrows direction is silent — the exact bug we are fixing).

   Adopt the **codebase-conventional `_AssertKindsMatch` nested-ternary
   form** at `lib/types.ts:94-110` (precedent: `InteractivePromptKind`
   vs `InteractivePromptPayload["kind"]` bidirectional rail). Do NOT
   use a novel `&`-intersection variant — keep style parity:

   ```ts
   // (extend the existing `@/lib/branded-ids` import block at line 47
   // with a sibling import — currently the runner does NOT import from
   // `@/lib/types`; this PR introduces the first such import in this
   // file. Pattern is consistent with `agent-runner.ts:11,27`,
   // `cc-dispatcher.ts:24-25`, `ws-handler.ts:7-8`.)
   import type { WorkflowEndStatus } from "@/lib/types";

   // Cardinality assert (#3827 + ADR-031 amendment): the runner's
   // `WorkflowEnd["status"]` union MUST equal the wire-protocol
   // `WorkflowEndStatus` source-of-truth in `lib/types.ts`. Adding to
   // either side without the other fails compilation here. Mirrors the
   // `_AssertKindsMatch` pattern at `lib/types.ts:94-110` for style
   // parity (nested ternary, NOT &-intersection).
   type _AssertWorkflowEndStatusMatches =
     WorkflowEndStatus extends WorkflowEnd["status"]
       ? WorkflowEnd["status"] extends WorkflowEndStatus
         ? true
         : never
       : never;
   const _exhaustiveWorkflowEndStatusCheck: _AssertWorkflowEndStatusMatches =
     true;
   void _exhaustiveWorkflowEndStatusCheck;
   ```

   The `void _exhaustive*Check` line is the codebase convention (matches
   `lib/types.ts:101, 110`) — do NOT drop it.

4. **`knowledge-base/engineering/architecture/decisions/ADR-031-cc-dispatcher-extraction-cc-workflow-end-messages.md`** —
   add a `## Amendment — 2026-05-15` section at the bottom recording
   the decision: option (b) chosen, drift reconciled, table at line 25
   updated (the cardinality column now shows 7/7/7 across all three
   rows), AND a note that the new bidirectional cardinality assert in
   `soleur-go-runner.ts` is the rail that prevents silent re-drift
   (the existing rails only cover the runner→consumer direction). Do
   NOT rewrite the original Decision section — preserve the historical
   record per ADR convention.

No files to create. No migration. No schema change.

## Files to Verify (no edits expected; assert post-narrow correctness)

1. **`apps/web-platform/lib/ws-zod-schemas.ts:381`** — derives
   `z.enum(WORKFLOW_END_STATUSES)`. Post-edit MUST type-check and reject
   `"sandbox_denial"` / `"runner_crash"` at runtime. The
   `test/ws-protocol.test.ts` negative assertion (AC2) covers this. This
   is the only load-bearing verify entry — the other 5 entries from
   plan v1 were tautological (any TypeScript narrow auto-propagates).

The remaining consumers (`lib/chat-state-machine.ts:9,128,183`,
`lib/types.ts:300`, `server/cc-dispatcher.ts:213-255`,
`server/cc-workflow-end-messages.ts`, `e2e/cc-soleur-go-routing.e2e.ts`)
are covered by `tsc --noEmit` (AC3) — no targeted manual verification
needed.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — cardinality alignment AND bidirectional rail.** After
  the edit, `WORKFLOW_END_STATUSES.length === 7` and the new
  `_AssertWorkflowEndStatusMatches` rail in `soleur-go-runner.ts`
  (Files to Edit #3) type-checks. Verification is by inspection of
  the 5-line nested-ternary rail (matches the proven `_AssertKindsMatch`
  precedent at `lib/types.ts:94-110`) — both arms can be hand-traced:
  the inner `? true : never` collapses to `never` whenever either
  `extends` arm fails, which propagates to a TS2322 on
  `const _exhaustiveWorkflowEndStatusCheck: never = true`. No
  "exercise then revert" choreography (multi-agent panel flagged that
  pattern as fragile and operator-discipline-dependent; correctness is
  type-rail by-construction, not procedural).

  If a future operator wants to empirically validate the rail, do it
  in a throwaway scratch branch — NEVER in the work branch. To make
  this hard to violate, the commit message MUST cite this AC; an
  audit invariant is that `git diff main..HEAD -- apps/web-platform/`
  shows ONLY the planned narrowing + assert + test changes, no
  drift-test residue.
- [ ] **AC2 — Zod schema accepts the 7 surviving statuses and rejects
  the 2 removed.** Verified by the updated
  `test/ws-protocol.test.ts` round-trip test:
  - All 7 surviving statuses produce `r.ok === true`.
  - `"sandbox_denial"` and `"runner_crash"` produce `r.ok === false`.
- [ ] **AC3 — Exhaustiveness rails stay green.** Verify via `cd
  apps/web-platform && bunx tsc --noEmit`:
  - `cc-workflow-end-messages.ts:42` `_workflowEndExhaustive` —
    already runner-bound, no change expected.
  - `cc-dispatcher.ts:247` `_abortFlushExhaustive` — already
    runner-bound, no change expected.
- [ ] **AC4 — Full `apps/web-platform` vitest suite green.** Run via
  `cd apps/web-platform && bun run test` (resolves to vitest per
  `package.json`). Issue body AC pinned this; mirroring here.
- [ ] **AC5 — Consumer audit grep at /work Phase 0.** Confirm zero
  in-repo *production code* emit sites of the two removed statuses
  via a `--type ts`-scoped grep:
  `rg '"sandbox_denial"|"runner_crash"' apps/web-platform/ --type ts`
  MUST return only `lib/types.ts:22-23` (pre-edit) → zero (post-edit)
  AND `test/ws-protocol.test.ts:540-541` (pre-edit) → zero (post-edit).
  No other TS hits ever existed.

  **AC5.1 — Acknowledged non-TS hit (historical migration comment).**
  `apps/web-platform/supabase/migrations/032_conversation_workflow_state.sql:48`
  contains a `COMMENT ON COLUMN` enumerating all 9 statuses
  (including `sandbox_denial` / `runner_crash`). Historical migrations
  are append-only per convention — do NOT edit migration 032. PR body
  MUST acknowledge: "migration 032:48 comment is historical and
  preserved; out-of-scope cleanup tracked separately." If/when
  operator UX requires the comment to reflect current truth, a forward
  migration (e.g., 0XX_workflow_end_comment_refresh.sql) can issue
  `COMMENT ON COLUMN ... IS '<updated>'` — but that is a separate PR.
  Verification: `rg "sandbox_denial|runner_crash" apps/web-platform/`
  (no `--type` scope) returns exactly the migration 032 comment hit
  (plus the plan + ADR documents themselves).
- [ ] **AC6 — ADR-031 amendment recorded.** New
  `## Amendment — 2026-05-15` section at the bottom of the ADR
  documents: (a) which option was chosen, (b) the audit evidence (zero
  emit sites), (c) the post-narrow cardinality table (7/7/7).
- [ ] **AC7 — `Ref #3243`, not `Closes`.** PR body uses `Closes #3827`
  for the code-review finding AND `Ref #3243` for the parent
  decomposition issue (keeps #3243 open as the roadmap pointer per
  ADR-031 §4).
- [ ] **AC8 — External-consumer sweep documented in PR body.** Run
  the three checks below at /work Phase 5 and paste each result into
  the PR body. If any external hit appears, fold the remediation
  inline OR open a follow-up `code-review` issue before marking the
  PR ready.

  1. **In-org code search**:
     `gh search code "sandbox_denial OR runner_crash" --owner jikig-ai`
     — expected hits: this plan + the ADR-031 amendment + migration
     032:48 (all knowledge-base/code-history paths, not consumers).
     Document the expected hit list inline so deviation is obvious.
  2. **Sentry alert-rule scan**: use `mcp__plugin_supabase_supabase__*`
     OR `gh api /repos/jikig-ai/soleur/contents/apps/web-platform/scripts/sentry-config-export.json`
     (whichever path the codebase uses to source-control Sentry config),
     grep for `sandbox_denial|runner_crash` in alert conditions and
     dashboard queries. Expected: 0 hits. If non-zero, fold a Sentry
     config update into this PR via the IaC Sentry surface (ADR-031
     `Sentry as IaC` sibling).
  3. **Doppler config grep**:
     `doppler secrets --project soleur --config prd --json 2>/dev/null | jq -r 'to_entries | .[] | "\(.key)=\(.value.computed // .value.raw)"' | grep -iE "sandbox_denial|runner_crash"`
     — expected: 0 hits (the two literals are runner-internal status
     strings, never plumbed through env vars). If non-zero, surface
     the value to the operator for triage before merge.

  Remediation rule: if any of the three checks returns an unexpected
  hit, either (a) fold the remediation into this PR, or (b) open a
  follow-up `code-review` issue and acknowledge in the PR body. Do
  NOT merge silently over a non-zero hit.

### Post-merge (automated)

- [ ] **AC9 — Sentry sweep (automated, ship Phase 6).** Confirm the
  release sweep shows no new error class introduced. Routed through
  `/soleur:ship` Phase 6 standard log-scan; no manual operator action.

## Test Strategy

**Framework:** existing `vitest` (per `apps/web-platform/package.json`).
Verified via `grep -E '"test":' apps/web-platform/package.json` (no new
dependency).

**RED → GREEN:**

1. **RED (failing test first).** In `test/ws-protocol.test.ts`, change
   the `workflow_ended round-trip with all 9 statuses` test to
   `with all 7 statuses` and remove the two entries from the
   `statuses` array. Add the negative-case assertion that
   `sandbox_denial` and `runner_crash` are rejected. The negative
   assertion fails BEFORE the `lib/types.ts` narrow (Zod still accepts
   the 9 statuses).
2. **GREEN.** Apply the `lib/types.ts` narrow. The negative assertion
   now passes (Zod auto-narrows because the tuple is its source).
3. **EXHAUSTIVENESS RAILS.** Run `bunx tsc --noEmit`. Both
   `_workflowEndExhaustive` (cc-workflow-end-messages.ts:42) and
   `_abortFlushExhaustive` (cc-dispatcher.ts:247) stay green — both were
   already runner-bound; the narrow brings the wire enum INTO their
   contract, not out.

**No new test framework. No new dependency.**

## Risks

1. **External-consumer drift.** If a downstream consumer (Sentry filter,
   data-warehouse query, dashboard) parses `status:
   "sandbox_denial"` / `"runner_crash"` as a string, the narrow doesn't
   *break* them — those values were never emitted, so the consumer was
   matching zero events. The risk is purely cosmetic: the consumer's
   filter clause becomes dead text. **Mitigation:** AC8 grep-sweeps the
   org for in-code references; Sentry dashboards keyed on these strings
   would surface in the post-merge ship log scan.
2. **Future runner widening reintroduces drift.** If a future PR adds
   `sandbox_denial` back to the runner's `WorkflowEnd` union (e.g.,
   PR-A2-style sandbox-error-as-terminal-state refactor), the wire enum
   would have to widen in lockstep. **Mitigation:** the
   `cc-workflow-end-messages.ts` exhaustiveness rail already enforces
   this for the user-copy map; the same widening would force a Zod
   schema update because `WORKFLOW_END_STATUSES` is the Zod source. The
   structural enforcement remains — drift can't compound silently.
3. **`code-review` label inflation if the narrow surfaces a stale
   reference.** If AC5/AC8 surface an unexpected hit (e.g., a comment
   block citing the removed statuses), fold inline rather than filing a
   follow-up `code-review` issue. Per
   `rf-review-finding-default-fix-inline` — single-class cleanups
   should converge to zero in one PR.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. Filled above with `threshold: none`.
- `Closes #3827` uses `Closes` (the code-review finding genuinely
  resolves at merge). `Ref #3243` uses `Ref` (the parent decomposition
  issue stays open as roadmap pointer per ADR-031 §4). Two different
  keyword choices, intentional.
- `tsc --noEmit` is the canonical exhaustiveness gate (per
  `2026-05-07-tsc-not-source-grep-enumerates-exhaustiveness-rails.md`).
  Do NOT add source-grep-based exhaustiveness rails to this PR — the
  existing `_workflowEndExhaustive` + `_abortFlushExhaustive`
  type-rails + the new bidirectional cardinality assert are the
  canonical enumerators.
- AC1 verification is by-inspection (5-line nested-ternary rail
  matching the proven `_AssertKindsMatch` pattern at
  `lib/types.ts:94-110`). Do NOT use "exercise then revert"
  choreography in the work branch — the multi-agent panel flagged
  that pattern as fragile and operator-discipline-dependent. If
  empirical validation is needed for confidence, do it in a throwaway
  scratch branch and never in `feat-one-shot-3827`.
- **Rolling-deploy Zod-parse-failure fall-through.** During a rolling
  deploy, in principle an old server pod could send a `workflow_ended`
  frame with `status: "sandbox_denial"` to a browser running the new
  narrower Zod schema. In practice this is unreachable (the old
  server never emits those statuses today), but the fall-through
  matters: `lib/ws-zod-schemas.ts:381` `z.enum(WORKFLOW_END_STATUSES)`
  will fail-closed; the existing WS-parse-failure handler routes the
  failure to Sentry per `cq-silent-fallback-must-mirror-to-sentry`.
  No new fallback code needed. Document at /work Phase 0: confirm the
  parse-failure handler is wired to Sentry; if not, file a `code-review`
  follow-up issue (do NOT block this PR).
- ADR amendment must NOT rewrite the original Decision section —
  preserve historical record per ADR convention. The amendment is an
  append at the bottom. Precedent: ADR-026 uses the same in-place
  `## Amendments` block pattern with `status: active` preserved.

## Out of Scope (deferred)

- **`cc-dispatcher.ts:213` local re-derive removal.** ADR-031 §
  Negative explicitly defers this: removing `export type
  WorkflowEndStatus = WorkflowEnd["status"]` from cc-dispatcher.ts
  would touch `TERMINAL_WORKFLOW_END_STATUSES`, `ABORT_FLUSH_STATUSES`,
  and `AbortFlushStatus` (which carry behavior at lines 1569-1613).
  That's a separate ADR.
- **Next `cc-dispatcher.ts` extraction (`cc-singletons.ts`).** The
  PR #3823 status comment names this as the next-next extraction;
  tracked via #3243 roadmap.
- **Duplicate ADR-031 filename.** Two files in
  `knowledge-base/engineering/architecture/decisions/` claim ADR
  number 031:
  `ADR-031-cc-dispatcher-extraction-cc-workflow-end-messages.md` (the
  one this PR amends) and `ADR-031-sentry-as-iac.md`. Pre-existing
  filing collision; out of scope for #3827. Tracked as a separate
  cleanup — rename one to ADR-032 in a docs-only PR. This plan
  amends only the cc-dispatcher-extraction ADR; do not touch the
  Sentry ADR.
- **Forward migration to refresh `migrations/032_conversation_workflow_state.sql:48`
  column comment.** Historical migration is preserved (append-only
  convention). If/when operator UX requires the comment to reflect
  the narrowed 7-status set, file a separate forward migration. Not
  required by #3827's acceptance criteria.
