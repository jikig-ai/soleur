---
feature: feat-one-shot-6178-soak-explained-pins
issue: 6178
pr: 8835
plan: knowledge-base/project/plans/2026-09-25-feat-inngest-soak-6178-explained-pins-plan.md
lane: cross-domain
---

# Tasks — pin three attributed soak groups (#6178)

`Ref #6178`, never `Closes`. This PR makes no production writes.

## 1. Setup

- 1.1 Re-read `scripts/followthroughs/inngest-soak-6178.sh` and `inngest-soak-6178.test.sh` on this branch. Confirm the `EXPLAINED_WHY=` and `SNAPSHOTS=` lines and the C2 loop match `origin/main`.
- 1.2 Run the suite once to confirm the baseline: `117 passed, 0 failed`.

## 2. RED (tests first)

- 2.1 Add the fixture constants beside `EXPLAINED_CREDIT`:
  - `PROMOTE`, `DRIFT` and `NOW_0925=1790337600`;
  - `PIN_PROMOTE`, `PIN_MINTER2` and `PIN_DRIFT`, holding the production ids with vendor-shaped startedAt values;
  - `add_new_pins()`.
- 2.2 Add the C26 block after C5 (C26, C26b, C26c, C26f, C26q), following the plan's §Test Scenarios. Include the AC5 assertions: a whole-line `grep -cxF` for the three new why lines and a prefix check for 1491374. Include the AC6 `tail -c 4000` first-line assertions, with the size reported by `LC_ALL=C wc -c`, never `${#OUT}`.
- 2.3 Change C3's assertion to `explained_why: bucket=1491374 2026-09-17T12:40–13:00Z catch-up`.
- 2.4 Extend the header's production-id carve-out to thirteen ids.
- 2.5 Run the suite. C26, C26b, C26q and the new C3 assertion must fail against the unmodified probe. Save the output for the PR body.

## 3. GREEN (probe)

- 3.1 Insert the three pins, each with a `why` (ASCII, at most 110 bytes, no `'` or `\`, using the plan's measured strings), directly after `EXPLAINED='[`, ordered by bucket.
- 3.2 Add one pin-comment line: only the 09-17 pins omit `why`, and they fall back to `EXPLAINED_WHY`.
- 3.3 `jqv split split`: select the matched pin using the same four inline conjuncts, then carry `why: ($pin.why // "")`.
- 3.4 Replace the single `explained_why:` print with the `why_rows` query and its loop. The query does the fallback in jq and uses `unique_by(.bucket)`. The loop starts with `[[ -n "$b" ]] || continue`, then an `INT_RE` check, then prints `explained_why: bucket=<b> <text>`.
- 3.5 Rewrite the header `WHAT IT MEASURES` sentence (five groups, four events) and the SCOPE manual-trigger residual sentence.
- 3.6 Run the suite to 0 failed. Set `FLOOR=` to the measured pass count and re-run.

## 4. Docs

- 4.1 Add the two in-place `[Updated 2026-09-25]` notes inside ADR-100's `## Addendum — 2026-09-19 (#6178)`: the flip-condition bracket, and a closing paragraph of about three sentences. Do not append at EOF.

## 5. Verification

- 5.1 AC3: `grep -c` each of the seven new ULIDs in the probe returns 1. The two 09-17 pin lines are unchanged.
- 5.2 AC7: `grep -nE '^\s*exit (0|1)\b'` on the probe returns nothing.
- 5.3 AC8: `git diff origin/main` leaves the `EXPLAINED_WHY=`/`SNAPSHOTS=`/verdict-printf lines and the C2 loop untouched.
- 5.4 AC9: the header phrase "Exactly two such groups" is gone, and ADR-100 has exactly two `Updated 2026-09-25` hits, both inside the 09-19 (#6178) addendum.
- 5.5 E1 (evidence): `git merge-file` of all three files against #8626's current head, then run the suite once on `git merge-tree --write-tree HEAD refs/remotes/pr8626` in a scratch worktree.
- 5.6 E2 (evidence, read-only): `gh workflow run scheduled-followthrough-sweeper.yml --ref feat-one-shot-6178-soak-explained-pins -f dry_run=true`, watched to completion. Record the #6178 `exit=` value and the output tail.
- 5.7 Run markdownlint on the plan and this file.

## 6. PR body

- 6.1 Use `Ref #6178`, with no close keyword.
- 6.2 Include the RED output, the byte counts from C26q and C26f, and the E1/E2 results.
- 6.3 Include the web-1 quiesced-shape evidence as prose: last `server_active=active` at 2026-09-15 08:29Z, before SOAK_FROM, then 242 later hourly rows all inactive, per #6178 comment 5829980093.
- 6.4 Fold in `decision-challenges.md` (DC-1 and DC-2).
