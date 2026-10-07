## Problem

Stage 4 of the #9721 hosted-runner demand plan (lever 3), parked: PR runs run the `--affected` suite set plus the always-on ratchets, while `merge_group` keeps the full battery. This is a merge-gate change that amends ADR-262 and ADR-183 and touches the required `test` aggregator's meaning. Measured 2026-10-07: affected selection picks 27% (docs diff), 29% (web UI file), 36% (skill plus script) and 51% (`ci.yml` plus `required-checks.txt`) of the 79.0 registered suite-minutes; about 23 suite-minutes off a PR `test-scripts` run, roughly 300 to 700 job-minutes per 6h window (about 300 once draft-light is in). The affected pre-pass costs 86 s wall, so it must run once per run, not per shard leg.

## Re-decide gate

Do not start before S2 (push-run dedupe, #9512) and S3 (draft-light) have post-merge censuses. Evidence is a replay, not a live shadow: `--print-selection` over the last 300 first-parent commits against suite failures, replay escape rate under 2%. Break-even escape rate is about 12 to 16 percent (a queue failure costs a ~148 job-minute candidate run plus a re-queue and ejects the entries behind it).

## Scope

Extend ADR-262's call-site opt-in (`_diff_touches --pr-gated`) from five batteries to the affected set on `pull_request` only; `merge_group`, `push`, `workflow_dispatch`, `schedule`, an undeterminable diff and a runner edit keep the full battery. Own Guard Contract in its plan.

User-Impact: PR required `test` context behaviour (`scripts/test-all.sh`, `scripts/lib/test-relevance-paths.sh`); merge_group stays the full battery
Fix-Size: 400 lines / 8 files

Re-evaluation: after S2 and S3 have post-merge censuses.

Refs #9721, #9307, #9323
