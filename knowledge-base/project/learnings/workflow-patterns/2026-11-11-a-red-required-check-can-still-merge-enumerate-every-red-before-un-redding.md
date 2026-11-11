# Learning: a red *required* check can still merge — and un-redding main means enumerating every red, not just the one you found

## Problem

Main was red twice over on 2026-11-11 and neither red behaved the way "required check" implies:

1. PR #12565 merged (auto-merge armed, `mergedBy: deruelle`, no `merge_group` run) while its **required** `test`
   aggregate — and `test-scripts (3/8)` beneath it — were FAILURE for ~21h. Ruleset `14145388` ("CI Required") does
   list `test` in `required_status_checks`; the merge was only possible via its bypass actors
   (`OrganizationAdmin`/`RepositoryRole`, `bypass_mode: pull_request`). Detection worked; enforcement didn't. Filed
   as #12666.
2. Eleven minutes later PR #12649 added agent #68 without running `sync-readme-counts.sh`, so `lint-bot-statuses`
   went red on a *different* invariant. Diagnosing only the weight-row failure would have shipped a PR whose `test`
   aggregate stayed red on the README drift.

## Solution

The un-red PR (#12665) carried both fixes, each via its canonical regenerator — never a hand-edit:

- `python3 scripts/regenerate-shard-manifest.py --incremental --write` → `0 moved, 1 new, 0 no longer registered`
  (weight row `1272\tfloor`, leg `2`).
- `bash scripts/sync-readme-counts.sh` → 8 lines across the two READMEs.

Before scoping an un-red PR, run `gh pr checks <your-PR>` / the check-runs API on main's merge SHA and enumerate
*every* failing required check — each red on main is a separate defect with a separate provenance (`git log` the
responsible file, `gh api .../check-runs` the merge SHA). Fold mechanical regenerator fixes into the same vehicle;
file systemic gaps (ruleset bypass) as their own audit issue.

## Key Insight

`required_status_checks` is a *default*, not a wall — a bypass actor (`pull_request` mode) can land over a red
required check silently, so "the gate will catch it" is only true if nobody merges past the gate. When a required
check is red on a merged PR, the audit question is not "why did the gate miss it" but "who merged over it, and was
that acknowledged". When main is red, always ask "red how many times": each independent red is a separate regression
window, and fixing one while another still stands still leaves every PR's `test` aggregate red.

## Session Errors

1. **Reported "CI in progress, no failures" from a bounded watcher before the run finished.** The watcher's
   deadline snapshot (36/38 green) missed `test-scripts (3/8)` failing *while* the watch was still armed — the
   failure was only found by direct check-runs inspection afterward. A partial green is not a verdict; always state
   which checks are still open when reporting "no failures so far".
