# Tasks: feat-one-shot-12726-flip-silent-prd-diagnosis (PR-A)

Plan: `knowledge-base/project/plans/2026-11-17-fix-inngest-cutover-flip-silent-stuck-at-zero-plan.md`. Ref #12726 (never Closes/Fixes). Rulings: `decision-challenges.md` (R1-R7, split, F1-F6).

## 1. Setup

- 1.1 Re-run the read-only evidence queries (object rows by hour since 2026-11-12 17:00Z, largest gaps, the alert SQL replayed on four 900 s windows, the incident read) with `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh` and the read-only incident API; paste the numbers into the PR body (AC1).
- 1.2 Record the pre-change counts from each suite's printed output: comment-stripped `higher_than`/`lower_than` operators on `origin/main` (21/1), the flip guard's assertion floor (61), `PRESENCE_ROWS` (32), `MUT_ROWS_EXPECTED` (29), `CENSUS_FLOOR_ALERTS`/`CENSUS_FLOOR_EXPLORATIONS` (22/22), `EXPECT_BLOCKS` (22), the M17 vector-source count in `betterstack-send-failed-alert-mutation.test.sh` (22).

## 2. RED (flip guard first)

- 2.1 `apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh`: header text (new canon, pinned `higher_than`/0/`treat_as_zero`); new `EXPECT_SQL` (host-count canon, roster 1); block-anchored operator/value/`on_missing_data` rows on both alerts; no-`GROUP BY` row; the presence rows of the plan's "replace() is static text" list (whole-line `replace()` pin, exactly-once host on `LOCAL_SQL` matched to `BS_HOST`, consumer counts, canary-absent anti-collision, byte-0 CANARY warning, name literals twice each, one alert per exploration id, 4 headers across all infra `*.tf`); canary/production block-equality rows; canary `-target` rows; the instrument self-test.
- 2.2 Add Guard 1 mutation rows 1 to 18 with the lettered rows (plan Guard Contract), each block-anchored and each SQL row with its own expected `[FAIL]` text.
- 2.3 Run the guard on the unchanged tree; confirm it fails for the expected reasons.

## 3. GREEN (Terraform)

- 3.1 `apps/web-platform/infra/betterstack-logs-alerts.tf`: new SQL in `inngest_cutover_flip_silent_sql`; `operator = "higher_than"`, `value = 0`; `incident_cause` addition; a one-line comment that the greatest/toInt64 canon is kept on purpose.
- 3.2 Add `inngest_cutover_flip_silent_canary_sql = replace(local.inngest_cutover_flip_silent_sql, "'soleur-inngest-prd'", "'soleur-inngest-canary-absent'")`, the canary exploration and alert (identical apart from name, exploration and cause; the cause starts at byte 0 with the plain-ASCII CANARY warning, within 300 bytes after `sanitize`).
- 3.3 `.github/workflows/apply-web-platform-infra.yml`: two canary `-target=` lines in the MAIN plan beside the production pair.
- 3.4 Run the flip guard to green.

## 4. Census

- 4.1 Run every suite that reads the alerts file (plan, Relevant files and Files to Edit, including `betterstack-send-failed-alert-mutation.test.sh` M17 and `betterstack-alert-structure.test.sh`); re-derive each moved count from its printed output; list old and new values in the PR body (AC9). The structure suite's header contract is not edited (AC5).
- 4.2 Re-derive the flip guard's floor, `PRESENCE_ROWS` and `MUT_ROWS_EXPECTED` from its own run.
- 4.3 Update the flip guard's step comment in `.github/workflows/infra-validation.yml`: "both -target lines" becomes the four lines.

## 5. Records

- 5.1 Rewrite the tf comment paragraphs ("WAS PAUSED PENDING #11869", "WINDOW", "INCIDENT LIFECYCLE") into a record of what was done, plus the false-silence residual and its three arms.
- 5.2 ADR-218: one short amendment "2026-11-17 (#12726)" after the 2026-11-13 (#10538) amendment, no widening wording, naming the convention, residual, canary and its planned retirement; bracketed pointer on the 2026-11-05 "today only" status note (AC10).
- 5.3 Runbooks: the `betterstack-log-query.md` bullet in the egress form; the `inngest-server.md` "Silence alert (#11820)" bullet (poller, never a revert; resolve needs the owner's go). AC11's three greps print 0.
- 5.4 Run `plugins/soleur/test/c4-count-parity.test.sh` and `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.

## 6. Verification and ship prep

- 6.1 `terraform validate`; a read-only plan for the MAIN target list (or the CI plan): 2 to add, 2 to change, 0 to destroy (AC13).
- 6.2 File the tracker issue (Class R), `Ref #12726`: the two reads and their six values, the +4 h earliest time, the PR-C gate, the egress rule for an absent canary, the canary mirror issue as an accepted cost (AC14).
- 6.3 PR body: first line "merging changes production"; `Ref #12726`; measured-cause paragraph; AC2 keyword check prints `0`.
- 6.4 Prepush secret scan before every push. Push nothing while a merge is queued.
- 6.5 Hold the merge for the owner's typed go on `gh pr merge <N> --squash --auto`.

## 7. Post-merge (after the owner's go)

- 7.1 Monitor until-loop on the `apply-web-platform-infra.yml` push run to a conclusion; emit a resume prompt naming the run id, the tracker and both read times (AC16).
- 7.2 If the apply fails or is partial: read what applied, post it on the tracker, open the hotfix PR; its merge needs its own typed go (AC17a).
- 7.3 At apply +25 min: the six-value read (alerts API, incidents API, betterstack-query.sh; token on stdin), posted on the tracker with the canary mirror issue number (AC17). Arm the +4 h Monitor (AC17b).
- 7.4 If the alert is live, rows arrive and 1051496324 is still open (canary fired or not): put the self-contained AC18 prompt to the owner for the typed go on `POST https://uptime.betterstack.com/api/v2/incidents/1051496324/resolve`.
- 7.5 If the canary is absent: the egress rule (AC19) — keep production armed, raise #12190, name the LUKS deadman on the tracker.
- 7.6 If a production incident started after the apply floor while rows are present: record partial visibility as the INFERRED cause; poller, never a revert (AC17 value 3).
- 7.7 At apply +4 h: repeat the read on the tracker; open PR-C only if the AC20 gate holds.
