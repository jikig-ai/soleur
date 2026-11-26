---
title: "test(cf-token-scope): answer zone-rest grant probes with the live Cloudflare error codes"
type: fix
date: 2026-11-26
slug: test-cf-token-scope-mock-live-grant-codes
branch: feat-one-shot-cf-token-scope-mock-live-codes
issue: 12931
closes: none
lane: single-domain
brand_survival_threshold: none
---

# test(cf-token-scope): answer zone-rest grant probes with the live Cloudflare error codes

## Enhancement Summary

**Deepened on:** 2026-11-26. The fan-out was kept small for a one-file test change: two plan reviewers, one learnings researcher, two CTO ruling rounds, and the deepen halts at Phases 4.6, 4.7, 4.8, 4.11 and 4.12.
**Agents used:** soleur:engineering:review:code-simplicity-reviewer, soleur:engineering:review:test-design-reviewer, soleur:engineering:research:learnings-researcher, soleur:engineering:cto.

### Key Improvements

1. The committed `run_mut` mutation row was cut (CTO re-ruling R1). It reused the pin literals, so it could not catch a loosened M2. The floor is now 681, not 688.
2. The pins reuse the existing `count_f` helper instead of adding one.
3. H3 was replaced with a must-PASS check that can actually fail. M1 asserts no error code, so M1 staying green showed nothing.
4. The Observability section now carries the 5-field block. The test file is not Markdown, so deepen Phase 4.7 applies. Its probe passes `probe-verb-gate.sh` and stays clear of the suite-shape proxy.
5. The work-time matrix run was narrowed to rows 2-5 (CTO R3). Row 1 is the Phase 1 RED.

### New Considerations Discovered

- The suite's `MIN_ASSERTIONS` floor equals its assertion count (680), so every assertion delta must move it.
- `.errors[-1].code` is an equivalent mutant under the current single-error fixtures. It is recorded as a known survivor.

## Overview

The cf-token-scope test mock answers every authorized write-probe grant with one
error code, 10026. The live zone-rest probe run on 2026-11-26 returned a
different code for each zone-rest row. This plan makes the mock answer the two
zone-rest rows with the codes Cloudflare actually returned, and makes the
assertions pin those codes. It is a follow-up to epic #12931 and references it
without closing it. The PR body says `Ref #12931`, never `Closes` or `Fixes`.

Live evidence (epic #12931 comment 7201789881, main at `6baae09683`, staged keys,
exit 0):

```text
probe=zone-rest row control: zones/<zone>/settings -> authorized (200)
probe=zone-rest row zones/<zone>/settings -> authorized (PATCH 400, err 1006 after a 403 control)
probe=zone-rest row zones/<zone>/bot_management -> authorized (PUT 400, err 10400 after a 403 control)
probe=zone-rest verdict=pass
```

What changes, all in `plugins/soleur/test/cf-token-scope.test.sh`:

1. The mock's `granted == 1` branch picks the 400 code by URL: `/zones/<z>/settings`
   answers 1006, `/bot_management` answers 10400, and every other granted URL
   (the redirects-dns rows) keeps 10026. A comment marks 10026 as never measured live.
2. The mock's settings-branch comment drops "ASSUMED here" and cites the measurement.
3. M2 replaces its permissive settings regex with two whole-line exact counts, one per
   zone-rest row, each pinning its live code.
4. The suite's anti-vacuity floor `MIN_ASSERTIONS` moves from 680 to 681. That is the new
   assertion count: one permissive assertion is removed and two pins are added.

The probe script, SKILL.md and the M4 fixture do not change (see Research Insights).

## Research Insights

**Premise Validation.** Epic #12931 is OPEN. #12937 (zot bridge) is OPEN, and it
blocks web-platform release deploys only, not this plugin-only PR. Comment
7201789881 exists and shows the two lines quoted in the Overview. No live
measurement of any redirects-dns grant row exists in the epic's comments
(searched every comment for `probe=redirects-dns row` and `err 10026`), so
10026 stays unmeasured for those rows. Collision pre-check
(`collision-precheck.sh 12931`): one open draft PR, #12958 (zot bridge
re-home). It touches none of the cf-token-scope files, so there is no
overlap. Baseline: `bash plugins/soleur/test/cf-token-scope.test.sh` gives
`680 passed, 0 failed`, rc 0, about 90 s.

**Which 10026 fixtures model a zone-rest grant.** Grep of the test file for
`10026` finds two sites:

- Mock write branch (the `if [[ "$granted" == 1 ]]` line, about line 163): the shared
  granted default for every migration profile. It does model the zone-rest grants
  (`tok-zonesettings-mock` on `/settings`, `tok-botmgmt-mock` on `/bot_management`)
  and the redirects-dns grants. **Changed for the zone-rest URLs only.**
- M4 fixture (`'/http_config_settings/entrypoint$|tok-pages-mock|400:...10026...'`,
  about line 1255): the redirects-dns profile's rulesets entrypoint, with the
  DENY-control token (`tok-pages-mock`) answering 400 to prove a deny-control 400
  reads inconclusive. It is not a zone-rest grant, and M4 asserts exit code, verdict
  text and "grant never probed", not the code. **Unchanged.**

**Probe logic classifies 1006 and 10400 correctly; no script change.** In
`plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh`, step 3's grant
`case "$CODE" in 400)` arm reads `authorized` unless the row is `settings-json` and
`mig_grant_unparsed` holds (not one JSON document, or any listed code is 6007).
`{"errors":[{"code":1006,...}]}` is one JSON document without 6007, so the
settings row reads authorized. The bot_management row is `invalid`, so it reads
authorized on any 400. `mig_errcode` prints `.errors[0].code` when it is digits
only. The live run read both rows as authorized through this same code.

**Docs.** No file under `plugins/soleur/skills/cf-token-scope/` names 10026
(`grep -rn 10026 plugins/soleur/skills/cf-token-scope/` is empty), so the brief's
"plus the skill's documented codes if they name 10026" changes nothing. SKILL.md
(the `settings-json` bullet) still says the grant's 400 is "expected but not yet
measured", and the 2026-11-26 run makes that sentence out of date. It does not
name 10026, so editing it would go beyond the brief. Recorded as an operator
scope row in `decision-challenges.md`, defaulting to no edit.

**Relevant files.**

- `plugins/soleur/test/cf-token-scope.test.sh`: the mock heredoc's write branch (comment
  `# PATCH /zones/<z>/settings parses JSON BEFORE it checks authorization`, the
  `granted` case table), M2 (`# --- M2: zone-rest happy path ---`), the mutation
  block (`run_mut "M2w ...` rows, `run_mut()` definition).
- `plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh`: `mig_report()`
  (prints the `probe=<profile> row <label> -> <verdict>` line), `mig_errcode()`,
  `mig_grant_unparsed()`, the step-3 write loop. The one authorized-line source line,
  `mig_report "$w_label" "authorized ($w_method 400$(mig_errcode) after a 403 control)"`
  (indented eight spaces), appears exactly once (`grep -cxF` = 1), so it is a valid whole-line anchor for the work-time
  matrix row 3 mutant.

**Institutional learnings.**

- `2026-07-24-stubbed-uniform-fixture-hides-per-endpoint-response-shape.md`: a uniform stub
  hid a per-endpoint divergence. Here the mock answers per URL, from live measurement.
- `2026-10-15-i-wrote-the-fixtures-from-my-model-of-the-tool-and-the-tests-agreed-with-me.md`:
  fixtures come from captured provider output. 1006 and 10400 are captured, while the
  message strings are not, so they stay neutral synthetic text (`cq-test-fixtures-synthesized-only`).
- `2026-11-07-a-pin-whose-harness-runs-only-arg-two-passes-vacuously.md`: confirm the pin
  can fail. The Phase 1 RED (AC2) shows it, and the Phase 3 work-time matrix run covers the rest (CTO R1/R3).
- `best-practices/2026-06-03-grep-over-markdown-marker-tests-line-wrap-and-vacuous-alternation.md`:
  no alternation in the new pins. They are fixed-string whole-line matches.

**Conventions.** `cq-write-failing-tests-before` (tighten the assertion first and watch it
red against the 10026 mock), `cq-cite-content-anchor-not-line-number` (the line numbers above
are approximate; edits key on content anchors), `cq-assert-anchor-not-bare-token`
(pin the whole row line, not a bare `1006`), `hr-never-run-commands-with-unbounded-output`
(the suite's output goes to a file and only its tail is read).

**Property List (Phase 0.6b).**

- P1. The mock's grant answer for each zone-rest row has the error code live Cloudflare returned.
- P2. The suite fails when a zone-rest row's authorized line carries a code other than its live code, or no code.
- P3. The 403 deny control still runs before each grant probe, and the suite still checks that.
- P4. No probe behaviour changes, and no test makes a live call or prints a token.

**Cut List.** None. The brief proposes one mechanism, the per-row mock answer (P1), and
nothing already in the repo provides it. A per-URL code table was considered and cut
(CTO Q1): only two codes are measured, so a table adds structure and no evidence.
A negative "no row carries err 10026" check was cut (CTO Q3): once the exact line
appears exactly once, the negative check adds nothing.

## Implementation Phases

### Phase 1: RED (tighten the assertions against the current mock)

In M2, replace

```bash
has_re 'zones/<zone>/settings +authorized \(PATCH 400(, err [0-9]+)? after a 403 control\)' "M2 the settings row reads authorized, with the grant's error code"
```

with two exact pins. They use the suite's existing `count_f` helper (`grep -cF -- "$1" "$OUTFILE" || true`).
No new helper is added. The full `probe=zone-rest row ...` string appears only on the `mig_report` probe line,
never in the indented ledger copy of the row, so a fixed-string count of 1 is exact:

```bash
M2_SET_LINE='probe=zone-rest row zones/<zone>/settings -> authorized (PATCH 400, err 1006 after a 403 control)'
M2_BOT_LINE='probe=zone-rest row zones/<zone>/bot_management -> authorized (PUT 400, err 10400 after a 403 control)'
assert_eq "M2 the settings row reads authorized with its live code (1006, measured 2026-11-26)" 1 "$(count_f "$M2_SET_LINE")"
assert_eq "M2 the bot_management row reads authorized with its live code (10400, measured 2026-11-26)" 1 "$(count_f "$M2_BOT_LINE")"
```

Run the suite. Exactly these two assertions must fail (mock still answers 10026) and
the count reads `679 passed, 2 failed` (680, minus the removed `has_re`, plus the two pins).
Any other failure means the edit broke something else.

### Phase 2: GREEN (per-row mock answer)

In the mock heredoc's write branch, replace the single granted line

```bash
    if [[ "$granted" == 1 ]]; then spec='400:{"success":false,"errors":[{"code":10026,"message":"invalid json"}]}'
```

with a URL-keyed choice inside the same branch (the `elif`/`else` 403 arms stay as they are):

```bash
    # A granted token's 400, by URL. 1006 (zone settings PATCH) and 10400 (bot
    # management PUT) were measured live on 2026-11-26 (#12931 comment 7201789881).
    # 10026 for the redirects-dns rows was never measured live. The script reads
    # only .errors[0].code, so the message strings are synthetic.
    if [[ "$granted" == 1 ]]; then
      if [[ "$url" =~ /zones/[^/]+/settings$ ]]; then spec='400:{"success":false,"errors":[{"code":1006,"message":"mock: settings grant rejected the probe body"}]}'
      elif [[ "$url" =~ /bot_management$ ]]; then spec='400:{"success":false,"errors":[{"code":10400,"message":"mock: bot management grant rejected the probe body"}]}'
      else spec='400:{"success":false,"errors":[{"code":10026,"message":"invalid json"}]}'; fi
```

Then rewrite the settings-branch comment's last sentence ("The grant token's 400 on the
JSON probe body is ASSUMED here: it is not measured until the post-merge staged run
records it.") to cite the measurement: the grant token's answer to the JSON probe
body, 400 code 1006, was measured on 2026-11-26 (#12931 comment 7201789881).

Leave the write-branch header comment ("a token that holds the URL's scope gets 400 for the
invalid body") unchanged. It is still true, and the new comment above the per-URL arms already
says the code depends on the URL (CTO R2).

Raise the anti-vacuity floor from `MIN_ASSERTIONS=680` to `MIN_ASSERTIONS=681`, so it still equals the
assertion count. Run the suite: `681 passed, 0 failed`.

### Phase 3: Work-time mutation checks (not committed)

Matrix row 1 (a uniform 10026) is the Phase 1 RED state, so AC2 already proves it. On a scratch
copy of the test file and of the script, never the tree, apply matrix rows 2-5 one at a time.
Each must red as stated, giving four suite runs of about 90 s each. Also run harness rows H1-H3.
Then delete the copies. Nothing from this phase is committed (CTO R1 cut the committed mutation
row; R3 keeps this run because it is the only proof of rows 2-5).

## Files to Edit

- `plugins/soleur/test/cf-token-scope.test.sh`: the mock write branch (granted answer + two comments), M2 (two exact pins on the existing `count_f` helper), and `MIN_ASSERTIONS` 680 → 681.

## Files to Create

None.

## Open Code-Review Overlap

None. No open `code-review` issue body names `cf-token-scope` (checked with
`gh issue list --label code-review --state open --json number,title,body --limit 200`
and a `jq` `contains("cf-token-scope")` filter).

## Guard Contract

### Guard 1 — M2 per-row live-code pins

**Property.** Each zone-rest write row's authorized line carries the error code live
Cloudflare returned for it (settings 1006, bot_management 10400), after a 403 deny control.

**Assembly.** The one chokepoint is `mig_report` in the script's step-3 write loop.
It is the only producer of `probe=zone-rest row <label> -> authorized (...)` lines,
and the authorized arm is one source line. The mock's `granted` branch is the only
default source of the code. M2 reads the output of one `mrun --profile zone-rest`.
Rows are `MIG_WRITE_ZONE_REST` (2 rows, `MW_ZR_N`). A third zone-rest row would have
no pin, and the existing `M2 two write probes per zone-rest row` count would still
pass. That is out of scope because no such row exists, and adding a row means editing
this table.

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Mock reverts to one uniform 10026 for every granted URL | RED: both M2 pins count 0 |
| 2 | Mock swaps the codes (settings 10400, bot_management 1006) | RED: both pins count 0 (the answer is keyed per URL) |
| 3 | Script authorized line drops `$(mig_errcode)` (work-time) | RED: both pins count 0 |
| 4 | Script reads `.errors[1].code` instead of `.errors[0].code` in `mig_errcode` | RED: both pins count 0 (no code printed) |
| 5 | Only the bot_management mock answer reverts to 10026, after a compliant settings row | RED: the bot_management pin counts 0, the settings pin stays 1 |
| 6 | Reorder: the grant is probed before the deny control | RED: existing `M2 both rows probe the known-denied token first` |

Rows 1, 2 and 5 all change the mock's answer. Rows 3 and 4 both remove the printed code.
Known survivor: a `mig_errcode` that reads `.errors[-1].code` (the last error) instead of `.errors[0].code`.
It is equivalent under this fixture, because every mock body lists exactly one error.

**Harness rows.**

| # | Edit to the suite | Expected |
|---|-------------------|----------|
| H1 | The two M2 pins are moved above `mrun --profile zone-rest`, so they read the previous run's `$OUTFILE` (M1, redirects-dns) | RED: both pins count 0 |
| H2 | `M2_SET_LINE` edited to `err 10026` | RED: settings pin counts 0 on the GREEN mock |
| H3 | Must-PASS, work-time only: on M1's output (redirects-dns, GREEN mock), `grep -cE '^probe=redirects-dns row .* -> authorized \\([A-Z]+ 400, err 10026 after a 403 control\\)$'` equals `MW_RD_N` | PASS. This shows the per-URL branch did not leak 1006 or 10400 to other URLs. It is not committed because 10026 is not a measured code, and M1 itself asserts no code, so M1 staying green proves nothing here |

**Anchor.** The expected codes are literals in the test, and one diff could change
both the mock and the pins. What is outside the commit is the live measurement in
#12931 comment 7201789881, which the test comment cites. A reviewer checks the two
literals against that comment.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Make the mock answer per row with the live codes (1006 for settings, 10400 for bot_management)" [brief] | Phase 2 | mapped |
| 2 | "tighten the assertions so each row pins its live code rather than accepting any code" [brief] | Phase 1 | mapped |
| 3 | "keeping the 403-deny-control ordering" [brief] | Existing M2 deny-first assertion unchanged; pins include `after a 403 control` | mapped |
| 4 | "plus the skill's documented codes if they name 10026" [brief] | None: no skill doc names 10026 (Research Insights, Docs) | descoped — justification: the condition is false, so there is nothing to change |
| 5 | "change probe logic only if a test shows it mis-classifies 1006 or 10400" [brief] | None: the analysis shows both are classified authorized, and the M2 pins confirm it at GREEN | descoped — justification: the condition is false |
| 6 | "verify which probe each 10026 fixture feeds before changing it, and only change those that model a live zone-rest grant" [brief context] | Research Insights (two sites); M4 unchanged | mapped |
| 7 | "Ref #12931 only, never Closes/Fixes it" [brief] | Overview; `closes: none` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Mock granted branch per URL | asks 1 | asked |
| Settings-branch comment cites the measurement | — | inferred — justification: the comment says the code is ASSUMED, and this PR's own fixture contradicts it. Leaving it would mislead the next reader of the mock (CTO Q5) |
| M2 exact pins (on `count_f`) | asks 2–3 | asked |
| `MIN_ASSERTIONS` 680 → 681 | — | inferred — justification: the suite's anti-vacuity floor equals its assertion count. Without the bump, the floor would no longer catch one silently skipped assertion |
| Phase 3 work-time mutation run (rows 2-5, H1-H3) | — | inferred — justification: it is the only run that proves the matrix's RED claims for rows 2-5 (CTO R3). It is not committed |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur/test/`
- Planned files: 1 | Estimated changed lines: about 15
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing at runtime. The probe script is unchanged. A broken test only produces a red `cf-token-scope.test.sh` in CI, or a mock that disagrees with live Cloudflare and so hides a future probe regression from the operator running the zone-rest migration.
- **If this leaks, the user's data is exposed via:** no new vector. The suite uses synthetic tokens and ids, makes no live calls, and keeps its existing "output never carries token" assertions.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** test-only diff in `plugins/soleur/test/`, with no runtime, data or credential surface. `aggregate pattern` would require a shipped behaviour change.

## Observability

The diff is a test file only, so no runtime surface gains or loses a signal. The block
below names the suite's own CI signal (deepen-plan Phase 4.7 applies because the file
is not Markdown).

```yaml
liveness_signal:
  what: "the cf-token-scope.test.sh ledger line '<N> passed, <M> failed' in the plugin test shard"
  cadence: "per push and per PR, through the shard registered in scripts/suite-shard-legs.tsv"
  alert_target: "the red required test check on the PR"
  configured_in: "scripts/suite-shard-legs.tsv (row plugins/soleur/test/cf-token-scope.test.sh)"

error_reporting:
  destination: "CI job log for the test shard (no Sentry: a test file emits nothing at runtime)"
  fail_loud: "a non-zero exit and a 'not ok' line naming the failed M2 pin, or 'ANTI-VACUITY FLOOR' when fewer than MIN_ASSERTIONS ran"

failure_modes:
  - mode: "the mock answers a zone-rest grant with a code other than its live code"
    detection: "the M2 live-code pins count 0, and the suite exits non-zero in CI"
    alert_route: "red PR check"
  - mode: "assertions silently skipped (the suite stops early)"
    detection: "MIN_ASSERTIONS floor prints ANTI-VACUITY FLOOR and exits 1"
    alert_route: "red PR check"

logs:
  where: "GitHub Actions job log for the test shard"
  retention: "GitHub Actions default log retention for the repository"

discoverability_test:
  command: "git grep -c '\"code\":1006,' -- 'plugins/soleur/*/cf-token-scope.*'"
  expected_output: "cf-token-scope.test.sh:1"
```

At baseline the command prints nothing and exits 1, because no `"code":1006,` exists yet.
After Phase 2 it prints `plugins/soleur/test/cf-token-scope.test.sh:1`. The pathspec keeps
the command free of the literal `test/` path segment, which deepen-plan's suite-shape
proxy would otherwise flag.

## Acceptance Criteria

- [ ] AC1. `bash plugins/soleur/test/cf-token-scope.test.sh > "$LOG" 2>&1; echo rc=$?; tail -1 "$LOG"` prints `rc=0` and `681 passed, 0 failed`, and `grep -c '^MIN_ASSERTIONS=681$' plugins/soleur/test/cf-token-scope.test.sh` = 1.
- [ ] AC2. At Phase 1 (pins in, mock unchanged) the same command prints a non-zero rc and `679 passed, 2 failed`, and the two failures are the two `M2 ... live code` assertions.
- [ ] AC3. In `plugins/soleur/test/cf-token-scope.test.sh`: `grep -c '"code":10026'` = 2 (the redirects-dns granted fallback and the M4 fixture, as at baseline), `grep -c '"code":1006,'` = 1 and `grep -c '"code":10400,'` = 1 (baseline: 2, 0, 0).
- [ ] AC4. `grep -c "ASSUMED here" plugins/soleur/test/cf-token-scope.test.sh` = 0 (baseline 1), and `grep -c 7201789881 plugins/soleur/test/cf-token-scope.test.sh` >= 1.
- [ ] AC5. `grep -cF 'PATCH 400(, err [0-9]+)?' plugins/soleur/test/cf-token-scope.test.sh` = 0 (baseline 1: the permissive regex is gone).
- [ ] AC6. `git diff --name-only origin/main...HEAD` lists only `plugins/soleur/test/cf-token-scope.test.sh` and files under `knowledge-base/project/{plans,specs}/`. `plugins/soleur/skills/cf-token-scope/` is unchanged.
- [ ] AC7. Guard Contract mutation-matrix rows 2-5 were each confirmed RED on a scratch copy during work (Phase 3), and harness rows H1-H3 behaved as stated. The scratch copies were then removed. Row 1 is covered by AC2.
- [ ] AC8. The PR body says `Ref #12931` and contains no `Closes #12931` or `Fixes #12931`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is a test-only change to a plugin test suite.

## Test Scenarios

All at the `unit` layer: `plugins/soleur/test/cf-token-scope.test.sh`, with curl and doppler mocked.

- M2 (changed): zone-rest happy path. Settings row line exactly `... authorized (PATCH 400, err 1006 after a 403 control)`, bot_management row line exactly `... authorized (PUT 400, err 10400 after a 403 control)`, each counted once.
- Unchanged and still green: M1 (redirects-dns grants answer 10026), M4 (deny-control 400 with 10026 → inconclusive), M5e (bot_management grant 6007 override → authorized, settings grant now 1006 by default), M5h (row lines survive the wrapper filter).

## Constraints (carried from the brief)

- No live Cloudflare calls from tests, no SSH, and no token value printed in output or logs.
- Do not run any operator-authorized act on epic #12931: prev-0b, swap-0b,
  branch-copies-tokens, revoking `CF_API_TOKEN_DNS_EDIT_PREV`, the zone-rest
  rehearsal and apply, deploy-docs, or revoking the old `ZONE_SETTINGS`/`BOT_MANAGEMENT`
  tokens. Each one waits on a typed go from the owner that names its exact command.
- Leave the old zone read-only, and never fire the gh-pages cert reissue with `probeOnly:false`.
- #12937 blocks web-platform release deploys, not this plugin-only PR.

## Sharp Edges

- The line numbers in this plan are approximate. Edit by the content anchors quoted
  (`cq-cite-content-anchor-not-line-number`).
- `count_f` reads `$OUTFILE`, which every `run`/`mrun`/`run_script` overwrites. Keep the two pins directly
  after `mrun --profile zone-rest` in M2. Harness row H1 is the mutation that moves them and reds.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.

## Addendum — 2026-11-26 (review of PR #13080)

This addendum supersedes the scope lines above. The sections above are left as written.

- **The pins are whole-line.** `count_f` is `grep -cF`, a substring count. Three review seats showed it passes a row with text appended after `control)`. The two M2 pins now use `grep -cxF -- "$M2_SET_LINE" "$OUTFILE" || true` inline, matching the decision-challenges ruling (`grep -cxF` equal to 1). "Use the existing `count_f`" in Phase 1, the Files list and tasks 2.1 is superseded.
- **Pin placement.** The pins sit after M2's other assertions, not directly after `mrun`. None of those assertions overwrites `$OUTFILE`.
- **M5e pins the displayed code.** For the two-error body, the row shows `, err 1000`, the first error's code. A reader of `.errors[-1]` showed 6007 and left the suite green before this pin. The two-document body shows no code. `MIN_ASSERTIONS` stays 681, because the M5e `has_re` was tightened, not added.
- **Scope grew. AC6 is superseded.**
  - The diff also changes `plugins/soleur/skills/cf-token-scope/SKILL.md` and the `cf-token-scope.sh` header comment (decision-challenges, scope row).
  - It also changes `knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md`: the revoke-recipe DELETE form, the remaining-token list in Phase 5, and the expected `authorized` line (decision-challenges, runbook row).
  - Line 63's "The probe script, SKILL.md and the M4 fixture do not change" now holds only for the probe logic and the M4 fixture.
