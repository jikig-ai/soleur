# Tasks: feat-one-shot-12846-health-colo-split

Plan: `knowledge-base/project/plans/2026-11-19-feat-analytics-health-colo-host-offset-plan.md` (issue #12846, `Ref` only; draft PR #12959). Rulings: `decision-challenges.md`; section 9 text: `clo-ruling-text.md` (apply verbatim, do not re-word).

Standing limits for every task: no production apply, no workflow dispatch (including `apply-web-platform-infra.yml`), no Doppler or credential change. Do not edit or comment on PR #12876.

## 1. Setup (baseline, no repository change)

- [ ] 1.1 `git fetch origin main feat-one-shot-12742-public-sdk-url-poll feat-one-shot-12712`; record the merge base.
- [ ] 1.2 Run `bash plugins/soleur/test/cloudflare-readonly.test.sh` and `bun test plugins/soleur/test/components.test.ts` on the untouched branch; record pass counts, the four floor values and wall time.
- [ ] 1.3 `bash plugins/soleur/test/c4-count-parity.test.sh` green; read `model.c4`, `views.c4`, `spec.c4` in full for the C4 no-change check.

## 2. Tests first (RED)

- [ ] 2.1 Suite: add `COLOSUBS=(analytics-health-colo)` inside `ALLSUBS` (`ANSUBS` unchanged); derive census counts and mutation labels from the arrays (CTO T4).
  - [ ] 2.1.1 Helper `case` arms for the new read: `sargs`, `tok_of`, `tokvar_of`, `url_of`, `ok_body`, `check_wire` (POST vector), `status_cells`, `tpl_of`.
  - [ ] 2.1.2 Census rows restated exactly (parity, dispatcher arms, `cf_graphql` callers, body assignments, TPL constants, "exactly two query template constants", one `cf_graphql` per analytics body, analytics-token arms `3/3`, `^GQL_(HEALTH|EDGE|COLO)_TPL=` template-content rows and ASC/DESC tally, suite `^TPL_` count).
  - [ ] 2.1.3 Per-function QLIMIT tie (edge and colo arms).
  - [ ] 2.1.4 `TPL_COLO`; `check_body` gains the offset (F/G pass `0`); fake-clock rows for (1,0), (24,0), (216,0), (1,527), (216,527), (100,250).
  - [ ] 2.1.5 Grammar rows (exact message, zero curl calls, with and without a token): missing offset, fourth argument, `-1`, `01`, `+5`, `1e3`, trailing space, `528`, non-ASCII digit, `H=0`, `H=217`, `217/526`, `1/528`; `216/527` accepted.
  - [ ] 2.1.6 Projection rows: splice prefix `{"zone":...,"window_end":...,`, cleaned sort, non-matching colo -> `null` with the raw canary absent from stdout/stderr, numeric colo and off-the-hour stamp -> `bad-response (shape)`, `truncated` at 9999/10000, `no-zone-access`, `api-error`, leak/redaction rows.
  - [ ] 2.1.7 Status cells for the new arm (floor derived from `${#ALLSUBS[@]}` x 15).
  - [ ] 2.1.8 Mutation rows of Guards 1 and 2; update labels quoted by G1.A8, G1.A9, G1.A9b, W6.9; keep W1.6, W6.19, W6.21, G1.H4, G1.H4b literals unchanged.
  - [ ] 2.1.9 Insert new rows away from #12876's suite inserts (after the analytics projection block; end of the mutation list).
- [ ] 2.2 `components.test.ts`: `CF_SIX` -> `CF_SUBCOMMANDS`; "its seven subcommands" slice; `arrNames.length` 7; "the three analytics subcommands each send one POST"; `VENDOR_SENTENCE`; pins for `from 0 to ${MAX_OFFSET}` and `at most ${MAX_HOURS + MAX_OFFSET}` (527, 743).
- [ ] 2.3 Run both suites; confirm the new rows fail for the right reason.

## 3. Core implementation (GREEN)

- [ ] 3.1 Wrapper `plugins/soleur/scripts/cloudflare-readonly.sh`, edits 1-15 of the plan (header, globals `MAX_OFFSET=527` and `END_OFFSET=0`, `GQL_COLO_TPL`, `def colo` after `def idv:`, additive `end=$((end - END_OFFSET * 3600))` line, `need_colo_args` reusing `need_hours "$1" "$2"`, `sub_analytics_health_colo` with the inline on-the-hour guard and the pinned splice statement, argument alternation, dispatcher arm). `project()` and the existing `end=` line stay byte-identical.
- [ ] 3.2 Suite green; raise the four floors to the observed counts; record baseline, delta and new value per floor for the PR body.
- [ ] 3.3 Section 9 (Boundary, item 2, Credentials) from `clo-ruling-text.md` A-C verbatim; `components.test.ts` green.
- [ ] 3.4 ADR-289 `## Addendum 2026-11-19 (Ref #12846)` from section D; `related:` gains 12846.
- [ ] 3.5 `plugins/soleur/agents/engineering/cto.md`: edit only if its wrapper sentence states a subcommand count.
- [ ] 3.6 Runbook `origin-tls-strict-flip.md` additions-only addendum before `#### What was NOT run before the flip`: subcommand scope (no `requestSource`, on purpose), R1, T2 rule with its four terms, the T2 jq recipe and its outputs on three synthetic fixtures, the other-event list by pointer, "supported is not reachable", the deadline (hard date 2026-11-24), the T3 handoff loop, and the Class R line for this session's read.
- [ ] 3.7 `git mv` `knowledge-base/project/specs/feat-one-shot-12846-health-colo-split/2026-11-19-analytics-health-216h.json` to `knowledge-base/engineering/operations/runbooks/evidence/`.

## 4. Testing and verification

- [ ] 4.1 Full cloudflare suite, `components.test.ts`, `c4-count-parity.test.sh`, markdown lint, `bash scripts/test-all.sh --affected`.
- [ ] 4.2 AC10 hunk-distance check from `git diff -U0 origin/main...HEAD` against the merge-base anchors.
- [ ] 4.3 Pre-push `git merge-tree --write-tree` against `origin/feat-one-shot-12742-public-sdk-url-poll` (conflicts allowed only on the four floor lines) and `origin/feat-one-shot-12712`.

## 5. PR and sequencing

- [ ] 5.1 Push; update draft PR #12959: `Ref #12846`, `Ref #12441`, `Ref #10479`, no `Closes`, `closingIssuesReferences` is `[]`; lead with the deadline; the six CLO owner-review items; the per-floor deltas and the rebase-and-re-pin note for whichever of this PR and #12876 lands second.
- [ ] 5.2 One comment on #12931: run the #12846 read against the old zone before Doppler `CF_ZONE_ID` changes; old zone may be deleted from about 2026-11-25; new-zone token reach is unverified.

## 6. Post-landing (same session, Class R; then the PR that closes #12846)

- [ ] 6.1 From a fresh `origin/main` checkout with an empty wrapper diff, run the handoff loop (main capture, split fallback if truncated, archival capture); push the kept files alone on a branch at once. Hard date 2026-11-24.
- [ ] 6.2 Follow-up PR (`Closes #12846`): run the pre-registered T2 recipe on the main capture; record the one-line outcome as an `Unverified:` line in a dated runbook addendum.
