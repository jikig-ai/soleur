# Tasks: sign off the founder-acceptance-record text (plan 2026-11-07-feat-founder-acceptance-record-text-draft-signoff-plan.md)

Supersedes the draft-phase task list (all done). The CLO agent's ruling stands in for counsel on the operator's instruction of 2026-11-07; human-lawyer review stays owed.

## Phase 0: setup
- 0.1 Confirm cwd and branch; `git fetch`; text still absent from `origin/main`; PR #12342 still DRAFT; `ci.yml` has `workflow_dispatch`.

## Phase 1: RED first
- 1.1 Write `registry-pins.test.ts`, the always-on unfinished-marker check, the retention single-source test, the `legal_reauth_event` column pin, the kind-copy tests; run only the node-only files once (`--no-file-parallelism --maxWorkers=1`) and cite the RED output.

## Phase 2: text and notices
- 2.1 Apply edits A1 to A8 to `founder-acceptance-record.md` by exact OLD/NEW (each OLD once before, each NEW once after); version stays `2026-11-07`.
- 2.2 Edit `cardNotice` and `requestChangesNotice` in `legal-acceptance-copy.ts` and sections (c), (c-2) (and (b)) of the DSAR note in the same commit.
- 2.3 `sha256sum` the final bytes; check LF-only printable ASCII; markdownlint on the committed path.

## Phase 3: deck, consumers, label (#12344)
- 3.1 Add `LEGAL_TEXT_KINDS`, `LEGAL_KIND_COPY`, `LEGAL_TEXT_KIND`, `legalTextKind`, `legalKindCopy`, `legalIndexState`, `legalDisplayLabel` to the leaf; move the 16 members; `exactTextHeading` and `dialog.codeBody` new strings; `signOff.clo`; header comment.
- 3.2 Card: null render for an undeclared key, `label` prop, `answerDetail` to the dialog. Dialog: required `answerDetail` prop. `[key]` page: 404 plus Sentry mirror. Index: filter plus Sentry plus `legalIndexState`.

## Phase 4: tests
- 4.1 Delete the merge guard describe, its real-data control, the retention-clause test, the CI-visible test, the registry tripwire.
- 4.2 `legal-copy.test.ts`: both variants walked, ban regex, identity, null cases, signOff pins, notices byte for byte without placeholder.
- 4.3 `card.test.tsx`, `page.test.tsx`: `declared` mock for `customer-terms`/`other-terms`; new `card-ack.test.tsx` (the kind tests were folded into `card.test.tsx` and `card-ack.test.tsx`; there is no `card-kind.test.tsx`).
- 4.4 Run mutation rows (node-side once each; jsdom one file at a time, single worker) and cite.

## Phase 5: records
- 5.1 Persist the CLO ruling as `knowledge-base/legal/audits/2026-11-07-clo-ruling-founder-acceptance-record-12197.md`.
- 5.2 Addenda with superseded markers: attestation (block stays blank), counsel-review-12011 pointer, LIA, PA-40 and item 17, compliance-posture row, ADR-319 dated amendment. Read all three `.c4` files before concluding "no C4 impact".
- 5.3 `texts/README.md` (pin rule), `server/legal-acceptance/README.md`, `test/feature-map.md`.
- 5.4 File tracking issues: published trio as flag precondition (S5); terms "updated" wording and base-SHA pin guard (S6); restate #12080 trigger.

## Phase 6: holds and PR
- 6.1 Rewrite the old plan's `## Operator Holds` and `## HOLD procedure`; append rows to `decision-challenges.md`.
- 6.2 Rewrite PR #12342 title and body (stand-in statement, 8 residual risks, new sha256, conditional `Closes #12344`, pre-flag count check).

## Phase 7: CI then ready (no local full runs)
- 7.1 `git merge origin/main`; commit; push; head SHA fixed.
- 7.2 `gh workflow run ci.yml --ref <branch>`; arm a Monitor watch; confirm headSha; require success incl. `test-webplat` shards not skipped.
- 7.3 `gh pr ready 12342` per ready-run-wait; watch to `full-decided`.
- 7.4 Stop. Never merge, never enqueue, flag untouched.

## Deepen-plan additions (2026-11-07; see the plan's deepen-plan block)
- 5.0 Phase 5 starts by filing S5, S6, the base-SHA pin deferral issues and commenting on #12080 (CLO 4b, 4c); records cite real numbers.
- 3.3 Founder gate: `server/legal-acceptance/surface.ts`, wire into both pages and the decide/reauth routes; null-kind 404 in `guardLegalRequest`; `kindUndeclared` op, contract test, README line.
- 4.5 Tests per the deepen-plan block C7/C8 (neutral probes, `document.body` DOM ban without negation stripping, exact retention multiset, 30-day tie, dated 2030-11-07 test, wording pin of 16 fields x 2 kinds, hoisted `declared` mock).
- 6.3 Hold mechanism (commit group 4): `ship-operator-step-gate.sh` merge branch + tests, `triage-prs.sh` `parked` tier + test; old-plan superseded banners; verify `hold-gate-eval.sh` rc 0 on the old plan and rc 3 on the new plan.
- 6.5 `soleur:review` on the delta before the final push.
- 7.0 Add and verify the `parked` label BEFORE `gh pr ready`; pre-ready head and `origin/main` assertions.

## Review round 1 (2026-11-08)

- R1 Hook: `parked_barrier` hardened per CTO T2 (102 rows, 25 mutants killed); header states the real strength.
- R2 `hold-gate-eval.sh` refuses `WA_NON_TERMS_KEYS`; cross-check in `registry-pins.test.ts`; `operator-holds.md` line; ADR-319 reworded.
- R3 `surface.ts`: founder first, once-per-process config report; decide route pinned (T4).
- R4 Text: CLO L1, L2, L5; notice and DSAR (c): L4; records and markers: L6; no edit of the published trio (L7); residual risk 13 (L8).
- R5 Tests: T5 items (kind pin, every-text loops with scanned-count controls, one probe per alternative, shared TERMS_PRESUMING, dated rows, data-kind/data-key, ops-table row).
- R6 Phase 7 stays: merge origin/main, push, dispatch, `parked` label before any ready flip, end state DRAFT (CTO T1).
