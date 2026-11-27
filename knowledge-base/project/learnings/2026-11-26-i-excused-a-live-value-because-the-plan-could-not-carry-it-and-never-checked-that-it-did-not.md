---
title: I excused a live value because the plan could not carry it, and never checked that it did not
date: 2026-11-26
category: logic-errors
module: cf-account-migrate gate (tests/scripts/lib/cf-account-migrate-gate.sh)
tags: [cloudflare, dns, gate, comparator, fail-closed, review]
issues: [13056, 13057, 13070, 12931]
---

# Learning: an exception justified by "the other side can't carry X" must assert the other side carries no X

## Problem

The redirects-dns rehearsal (#12931) was refused because the six CNAMEs read live `settings`
`{"flatten_cname":false}`. That value is Cloudflare's API default. Provider 4.52.7 has no `settings`
attribute, and cloudflare-go v0.116.0 sends `"settings":{}`. The fix (#13056, PR #13057) made
`cfam_live_diff` treat that live value as equal on a CNAME.

The first version justified the carve-out entirely by the planned side ("4.52.7 has no `settings`").
It never read `$after.settings`. A later provider that does send `settings` would have let a planned
`{flatten_cname:true}` compare equal to a live `false`, both before apply on no-op records and in the
post-apply re-read. Two review seats (security, structural enumeration) found it independently.

## Solution

- The carve-out now also requires `$after.settings == null`. A plan that carries `settings` is
  refused, not assumed equal. L11b and D6 passing show that no planned CNAME carries `settings` today, so the
  extra condition changes nothing now and fails closed later.
- D7 and M-flatten-plan pin the new condition.
- L11d runs once per settings key. A `del(.ipv6_only)` mutant survived the single-key row.
- Job-level rows N-cn1 and N-cn2 drive the post-apply re-read, which the PR relies on as its
  detection, through the real job script.
- The docs say the PATCH outcome is inferred from source, not observed.

## Key Insight

When a comparator excuses a difference because "the other side cannot hold this attribute", the
excuse is a premise about a dependency version. Encode the premise as a condition (`other side holds
no such attribute`), so a dependency bump fails closed instead of inheriting the excuse silently.
The same goes for a doc that tells the operator to record evidence: check that the producer emits
it. Here the job prints only `reread=ok records=26` and deletes its work dir.

## Session Errors

1. **A scratchpad `rm` was blocked by the protected-path hook** (forwarded). Recovery: recreated the directory. **Prevention:** none needed; the hook did its job.
2. **`gh pr diff 12958` exceeded the 20000-line limit** (forwarded). Recovery: `git diff` between refs. **Prevention:** compare overlap with `git diff --stat` between fetched refs from the start.
3. **The first Scope Check draft failed the deepen schema** (forwarded). Recovery: rewritten. **Prevention:** read the schema before drafting.
4. **`review-scan-gate.sh --help` read as empty input (`skip`)**. Recovery: re-ran with the changed paths. **Prevention:** the script takes paths only; pass the classified path list.
5. **A stray `sed -i … /dev/null` failed.** Recovery: none needed. **Prevention:** one edit per command.
6. **The carve-out never read the planned `settings`.** Recovery: added `$after.settings == null`, D7 and M-flatten-plan. **Prevention:** plan sharp-edges bullet (routed in this PR).
7. **The runbook asked for per-record re-read values the job never keeps.** Recovery: reworded to cite the `reread=ok` line. **Prevention:** `hr-verify-repo-capability-claim-before-assert`: grep the producer for the output before a doc asks for it.
8. **N-cn1 failed twice: the synthetic job plan types every record TXT, then only `after.type` was changed (shape refusal).** Recovery: plan the record as CNAME on both `before` and `after`. **Prevention:** read the fixture builder (`build_plan`, `norm_case`) before writing a row that relies on a field's value.
9. **The new job rows reused labels N9 to N12.** Recovery: renamed them N-cn1 and N-cn2. **Prevention:** grep existing labels before numbering.
10. **`gh issue create` was blocked twice by the filing hook (milestone, then the filing exit).** Recovery: `--milestone "Post-MVP / Later"` and `--label meta/machinery`. **Prevention:** a gate or verification finding is `meta/machinery`.

## Tags

category: logic-errors
module: cf-account-migrate gate
