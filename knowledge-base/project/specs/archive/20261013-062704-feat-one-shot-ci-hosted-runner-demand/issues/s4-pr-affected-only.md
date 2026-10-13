## Problem

Stage 4 of the #9721 hosted-runner demand plan (lever 3), parked: PR runs run the `--affected` suite set plus the always-on ratchets, while `merge_group` keeps the full battery. This is a merge-gate change that amends ADR-262 and ADR-183 and touches the required `test` aggregator's meaning. Measured 2026-10-07: affected selection picks 27% (docs diff), 29% (web UI file), 36% (skill plus script) and 51% (`ci.yml` plus `required-checks.txt`) of the 79.0 registered suite-minutes; about 23 suite-minutes off a PR `test-scripts` run, roughly 300 to 700 job-minutes per 6h window (about 300 once draft-light is in). The affected pre-pass costs 86 s wall, so it must run once per run, not per shard leg.

## Re-decide gate

Do not start before S2 (push-run dedupe, #9512) and S3 (draft-light) each have a post-merge census or are closed by their entry gate or stop rule, and ADR-270 is `accepted` (ADR-276 Decision 3(h)). Evidence is a replay, not a live shadow: `--print-selection` over the last 300 first-parent commits against suite failures, replay escape rate under 2%. Break-even escape rate is about 12 to 16 percent (a queue failure costs a ~148 job-minute candidate run plus a re-queue and ejects the entries behind it).

## Scope

Extend ADR-262's call-site opt-in (`_diff_touches --pr-gated`) from five batteries to the affected set on `pull_request` only; `merge_group`, `push`, `workflow_dispatch`, `schedule`, an undeterminable diff and a runner edit keep the full battery. Minutes target: PR `CI` job-minutes per run down at least 20% (about 20 of 99.8). Entry gates: (1) `admin-merge-ready.sh` demands the full-battery marker before treating an affected-set `test` success as green, because agent `--admin` merges skip the queue and "merge_group red with a green PR run" never sees them. The marker is a completed full-battery `CI` run on the head SHA that concluded `success`. A full-mode and an affected-mode PR run share head SHA, event and conclusion, so this stage adds a `[full]` `run-name` suffix to `ci.yml` that only full-battery runs carry (readable as `display_title`; affected-mode PR runs never do). The producer exists (a `workflow_dispatch` of `ci.yml`, ADR-262's force-full lever, and any full-mode PR run); this stage teaches `admin-merge-ready.sh` to read it through the runs API on head SHA, event, display_title and run conclusion (a completed run with conclusion `success` whose display_title ends in `[full]`, or event `workflow_dispatch` with the full input), not by check name (a `checks: write` token can post any check name, KNOWN LIMIT (b) in the script). It stops agent accidents, not non-agent admin tokens or a bypass actor editing the ruleset; (2) an admin-side control is decided with the repository admins before the stage starts (narrow the CI Required bypass actors, or a detective post-merge probe that flags any bypass merge whose head lacks the marker), and the residual is counted in the escape metric; (3) the "runner changed means full battery" detector and the affected-selection index are evaluated from a trusted base-ref copy, not the PR's own tree, and the registration-only carve-out stays out of PR mode. This stage's PR appends its ADR-276 amendment, pointer amendments to ADR-262 (recording that its stale "No merge queue is enforced" premise and its admission rule are reversed for the PR arm) and ADR-183, and `amends:` frontmatter. Own Guard Contract in its plan.

User-Impact: PR required `test` context behaviour (`scripts/test-all.sh`, `scripts/lib/test-relevance-paths.sh`); merge_group stays the full battery
Fix-Size: 520 lines / 12 files

Rollback: the repository variable unset restores the full battery on PRs; the `admin-merge-ready.sh` marker requirement stays, and full-mode PR runs also emit the marker, so the admin route does not stall.

Re-evaluation: after S2 and S3 each have a post-merge census, or are closed by their entry gate or stop rule.

Refs #9721, #9307, #9323
