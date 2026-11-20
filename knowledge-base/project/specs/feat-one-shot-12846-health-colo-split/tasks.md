# Tasks: feat-one-shot-12846-health-colo-split

Plan: `knowledge-base/project/plans/2026-11-19-feat-analytics-health-colo-host-offset-plan.md` (issue #12846, `Ref` only; draft PR #12959). Rulings: `decision-challenges.md`; section 9 text: `clo-ruling-text.md` (apply verbatim, do not re-word).

Standing limits for every task: no production apply, no workflow dispatch (including `apply-web-platform-infra.yml`), no Doppler or credential change. Do not edit or comment on PR #12876.

## 1. Setup (baseline, no repository change)

- [x] 1.1 `git fetch origin main feat-one-shot-12742-public-sdk-url-poll feat-one-shot-12712`; record the merge base.
- [x] 1.2 Run `bash plugins/soleur/test/cloudflare-readonly.test.sh` and `bun test plugins/soleur/test/components.test.ts` on the untouched branch; record pass counts, the four floor values and wall time.
- [x] 1.3 `bash plugins/soleur/test/c4-count-parity.test.sh` green; read `model.c4`, `views.c4`, `spec.c4` in full for the C4 no-change check.

## 2. Tests first (RED)

- [x] 2.1 Suite: add `COLOSUBS=(analytics-health-colo)` inside `ALLSUBS` (`ANSUBS` unchanged); derive census counts and mutation labels from the arrays (CTO T4).
  - [x] 2.1.1 Helper `case` arms for the new read: `sargs`, `tok_of`, `tokvar_of`, `url_of`, `ok_body`, `check_wire` (POST vector), `status_cells`, `tpl_of`.
  - [x] 2.1.2 Census rows restated exactly (parity, dispatcher arms, `cf_graphql` callers, body assignments, TPL constants, "exactly two query template constants", one `cf_graphql` per analytics body, analytics-token arms `3/3`, `^GQL_(HEALTH|EDGE|COLO)_TPL=` template-content rows and ASC/DESC tally, suite `^TPL_` count).
  - [x] 2.1.3 Per-function QLIMIT tie (edge and colo arms).
  - [x] 2.1.4 `TPL_COLO`; `check_body` gains the offset (F/G pass `0`); fake-clock rows for (1,0), (24,0), (216,0), (1,527), (216,527), (100,250), (216,250).
  - [x] 2.1.5 Grammar rows (exact message, zero curl calls, with and without a token): missing offset, fourth argument, `-1`, `01`, `+5`, `1e3`, `""`, trailing space, `528`, `1000`, a 20-digit offset (regex message), non-ASCII digit, `H=0`, `H=217`, `217/526`, `1/528`; `216/527` accepted. Canary rows: environment `END_OFFSET='a[$(touch canary)]'` on F and H (no canary), the same string as `$3` (exit 64, no canary).
  - [x] 2.1.6 Projection rows: splice prefix `{"zone":...,"window_end":...,`, cleaned sort, non-matching colo -> `null` with the raw canary absent from stdout/stderr, numeric colo and off-the-hour stamp -> `bad-response (shape)`, `truncated` at 9999/10000, `no-zone-access`, `api-error`, leak/redaction rows; `window_end`/`window_hours` rows under `make_variant fakeclock` with O > 0; an hour holding `"AMS"` and `"lhr"`; a two-value `make_variant` row -> `bad-response (shape)`; the one-`project`-caller-with-a-prefix source row; the new PINNED lines (CTO D1).
  - [x] 2.1.7 Status cells for the new arm (floor derived from `${#ALLSUBS[@]}` x 15).
  - [x] 2.1.8 Mutation rows of Guards 1, 2 and 3 (incl. D1.M1-M4, D5.M1, the `{0,2}` widening); update labels quoted by G1.A8, G1.A9, G1.A9b, W6.9 and G1.Q1, add the G1.Q1c twin; keep W1.1, W1.6, W6.19, W6.21, G1.H4, G1.H4b literals unchanged; the jq/date census stays 9.
  - [x] 2.1.9 Insert new rows away from #12876's suite inserts (after the analytics projection block; end of the mutation list).
- [x] 2.2 `components.test.ts`: `CF_SIX` -> `CF_SUBCOMMANDS`; "its seven subcommands" slice; `arrNames.length` 7; "the three analytics subcommands each send one POST"; `VENDOR_SENTENCE`; pins for `from 0 to ${MAX_OFFSET}` and `at most ${MAX_HOURS + MAX_OFFSET}` (527, 743).
- [x] 2.2b `plugins/soleur/test/health-colo-falsification.test.sh` with `fixtures/health-colo-falsification/base.json`, about 20 cases (three T2 classes plus both sides of boundaries (i)-(ix)), the outputs-block row and seven recipe mutation rows; `scripts/lib/test-affected-paths.sh` entry (CTO D3).
- [x] 2.3 Run all three suites; confirm the new rows fail for the right reason.

## 3. Core implementation (GREEN)

- [x] 3.1 Wrapper `plugins/soleur/scripts/cloudflare-readonly.sh`, edits 1-15 of the plan (header, globals `MAX_OFFSET=527` and `END_OFFSET=0`, `GQL_COLO_TPL`, `def colo` after `def idv:`, additive `end=$((end - END_OFFSET * 3600))` line, `need_colo_args` reusing `need_hours "$1" "$2"`, `sub_analytics_health_colo` with the inline on-the-hour guard, `project` with the optional prefix argument and its shape check (CTO D1), argument alternation, dispatcher arm). `END_OFFSET=0` is unconditional; the offset bound is fail-closed (`-le`). `project()`'s `res=` line, `emit_ok` and the existing `end=` line stay byte-identical.
- [x] 3.2 Suite green; raise the four floors to the observed counts; record baseline, delta and new value per floor for the PR body.
- [x] 3.3 Section 9 (Boundary, item 2, Credentials) from `clo-ruling-text.md` A-C verbatim; `components.test.ts` green.
- [x] 3.4 ADR-289 `## Addendum 2026-11-19 (Ref #12846)` from section D; `related:` gains 12846.
- [x] 3.5 `plugins/soleur/agents/engineering/cto.md`: edit only if its wrapper sentence states a subcommand count.
- [x] 3.6 Runbook `origin-tls-strict-flip.md` additions-only addendum before `#### What was NOT run before the flip`: subcommand scope (no `requestSource`, on purpose), R1, T2 rule with its four terms, the T2 jq recipe inside the `health-colo-r2-recipe` marker pair with its closed `inconclusive:` reason set and the D2 null-colo rule, the `health-colo-r2-outputs` block matching the new suite, the other-event list by pointer, "supported is not reachable", the deadline (hard date 2026-11-24), the T3 handoff loop, and the Class R line for this session's read.
- [x] 3.7 `git mv` `knowledge-base/project/specs/feat-one-shot-12846-health-colo-split/2026-11-19-analytics-health-216h.json` to `knowledge-base/engineering/operations/runbooks/evidence/`.

## 4. Testing and verification

- [ ] 4.1 Full cloudflare suite, `health-colo-falsification.test.sh` (and `bash scripts/test-all.sh --print-selection` on a runbook-only change), `components.test.ts`, `c4-count-parity.test.sh`, markdown lint, `bash scripts/test-all.sh --affected`.
- [x] 4.2 AC10 hunk-distance check from `git diff -U0 origin/main...HEAD` against the merge-base anchors.
- [x] 4.3 Pre-push `git merge-tree --write-tree` against `origin/feat-one-shot-12742-public-sdk-url-poll` (conflicts allowed only on the four floor lines) and `origin/feat-one-shot-12712`.

## 5. PR and sequencing

- [ ] 5.1 Push; update draft PR #12959: `Ref #12846`, `Ref #12441`, `Ref #10479`, no `Closes`, `closingIssuesReferences` is `[]`; lead with the deadline; the six CLO owner-review items; the per-floor deltas and the rebase-and-re-pin note for whichever of this PR and #12876 lands second.
- [x] 5.2 One comment on #12931: run the #12846 read against the old zone before Doppler `CF_ZONE_ID` changes; old zone may be deleted from about 2026-11-25; new-zone token reach is unverified.

## 6. Post-landing (same session, Class R; then the PR that closes #12846)

- [ ] 6.0 Right after merge, file the follow-through tracker (CTO Q10): title "Capture the per-colo H read before the old zone is deleted (deadline 2026-11-24)", label `follow-through`, body with `Ref #12846` and, unfenced at column 0, `<!-- soleur:followthrough script=scripts/followthroughs/health-colo-capture-12846.sh earliest=<merge instant, YYYY-MM-DDTHH:MM:SSZ> secrets=GH_TOKEN -->`; then confirm the next sweeper run log shows the probe's `exit=` line.
- [ ] 6.1 From a fresh `origin/main` checkout with an empty wrapper diff, run the handoff loop (main capture, split fallback if truncated, archival capture); push the kept files alone on a branch at once. Hard date 2026-11-24. Then, with the owner's typed go (a record marker is not Class R, standing-delegation section 9 item 5), post on #12846 a comment with a line starting `S1-HEALTHCOLO-CAPTURED: <read instant>`, the kept file names, the branch and the archival result; post it only when the main read is kept for the whole R1 window.
- [ ] 6.2 Follow-up PR (`Closes #12846`): run the pre-registered T2 recipe on the main capture; record the one-line outcome as an `Unverified:` line in a dated runbook addendum.
