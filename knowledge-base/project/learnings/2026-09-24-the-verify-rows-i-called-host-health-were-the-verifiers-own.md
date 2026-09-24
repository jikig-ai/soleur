---
title: The rows I called host health were the verifier's own, and the job I added to the verifier would have parked its cron
date: 2026-09-24
category: workflow-patterns
module: workspaces-luks
tags: [observability, github-actions, concurrency, terraform-data, token-rotation, test-harness, bash]
pr: 8703
---

# Learning: a telemetry row is evidence about the component whose emitter produced it

## Problem

#8632 asked for the prd_workspaces_luks Doppler token to be rotated, because retained web-1 snapshot
411798619 very likely holds it, and for the new token to be delivered to web-1's
`/etc/default/luks-monitor`. The approved runbook said to add a dispatch-only `refresh_host_token`
job to `workspaces-luks-verify.yml`, gated by the `workspaces-luks-cutover` environment.

I built that, and I told the operator the host's daily probe was green, citing `luks-monitor` rows
in Better Stack. A 10-seat review then found two problems.

1. **The rows were the verifier's own.** `SOLEUR_WORKSPACES_READYZ` lines are emitted only when
   `LUKS_MONITOR_ASSERT_READYZ=1`, which only the GitHub verify job sets. The host's
   `luks-monitor.timer` had emitted nothing, and no Sentry event, in 7-30 days (#8706). The same tag
   and the same script produce rows from two different callers.
2. **The job I added coupled to the cron through a key I never read.** `concurrency:` was set at
   workflow level. A refresh run waiting for approval would hold the group, park the daily 04:41
   scheduled verify, and page a missed Sentry check-in. The workflow's runs are also cited as legal
   evidence, and the ADR-119 §(e) channel I cited grants only the cutover job's SSH path. Four seats
   converged on the concurrency coupling.

## Solution

The CTO ruling replaced the dispatch job with `terraform_data.luks_monitor_token_install` in
`workspaces-luks.tf`. The pattern is `server.tf`'s `private_nic_guard_install`:

- the only trigger is `nonsensitive(sha256(token.key))`;
- the connection pins `host_key`;
- the per-merge SSH `-target` fires it;
- the token has `create_before_destroy`.

The helper proves the new token reads `WORKSPACES_LUKS_KEY` before it rewrites the line, and never
starts the unit. The rotation now happens in one merge, and every future rotation re-delivers by
itself. ADR-119 has a 2026-09-24 addendum recording who owns each line of the file.

The review also found that the CTO's question "what else was on web-1 before the snapshot?" pointed
at a second live full-`prd` token, `web-probes-read`, which #8632's premise had called dead (#8705).

## Key Insight

- **Name the emitter before citing a row.** Before telling anyone a component is healthy from a
  telemetry row, read the row's emitter fields (`_SYSTEMD_UNIT`, `_COMM`, the flag that gates the
  line). A shared tag and a shared script are not a shared caller.
- **A job's scope keys can be set outside the job.** A job added to an existing workflow inherits
  that workflow's `concurrency:`, `permissions:` and triggers. Adding an environment-gated
  (human-wait) job to a scheduled workflow is a change to the schedule.
- **Find the owning resource type before building a delivery path.** When a credential Terraform
  mints must reach a host, look for an existing `terraform_data` delivery before building a
  workflow. The repo already had one, and it removes the manual step for every future rotation.

## Session Errors

1. **Told the operator "the host's daily probe is green" from verify-job rows.** Recovery: the
   observability seat pulled `_SYSTEMD_UNIT`/flag evidence; I corrected it and filed #8706.
   **Prevention:** before citing a row as a component's health, confirm its emitter
   (`_SYSTEMD_UNIT`, `_COMM`, gating flag). Routed to review/SKILL.md.
2. **Added an environment-gated job to a scheduled workflow without reading its workflow-level
   `concurrency:`.** Recovery: CTO redesign to `terraform_data`. **Prevention:** before adding a job
   to a workflow, read the workflow-level `concurrency:`, `permissions:` and `on:`, and ask what a
   pending approval does to the other jobs' runs. Routed to review/SKILL.md.
3. **Cited ADR-119 §(e) as a standing write channel; it grants only the cutover job's SSH path.**
   Recovery: ADR-119 addendum. **Prevention:** quote the ADR clause verbatim before citing it as
   authority for a new mechanism.
4. **`betterstack-query.sh --since 2026-09-24T00:00:00Z` returned HTTP 400.** ClickHouse would not
   convert the ISO `T…Z` string to `DateTime64`. The script's header says "ISO", but line 408
   documents the literal `'YYYY-MM-DD HH:MM:SS'` form. **Prevention:** use relative windows (`12h`)
   or the space-separated literal form.
5. **The first merge commit of #8626 was rejected by two hooks.** Main had claimed ADR-242/245 in
   the meantime, and main's growth pushed `work/SKILL.md` 204 bytes over its ceiling. Recovery:
   renumbered ours to 246/247, and moved the learning pointer to review/SKILL.md with a dated
   addendum. **Prevention:** already documented (treat branch ADR ordinals as provisional; re-check
   against a fresh `origin/main` before any merge).
6. **GitHub push protection rejected the synthetic `dp.st.` test fixtures.** Recovery: built them by
   concatenation and squashed the branch. **Prevention:** already documented in work/SKILL.md (split
   secret-shaped fixtures from the first write).
7. **H6 passed vacuously.** `${DOUT+FIXTURE_DOPPLER_OUT="$DOUT"}` in an env-assignment prefix is an
   expanded WORD, not an assignment, so bash ran it as a command (rc 127), and "a non-zero rc" read
   as "the helper refused". Recovery: always assign
   (`FIXTURE_DOPPLER_OUT="${DOUT-default}"`), and require H6 to find the helper's own logged reason.
   **Prevention:** never build an assignment prefix from a conditional expansion, and assert the
   refusal's REASON, never only a non-zero rc.
8. **A Python verdict emitter wrote a multi-line `detail` into a TSV row.** It split one verdict into
   several empty `FAIL` rows. Recovery: collapse whitespace in the detail. **Prevention:** normalize
   every free-text TSV field (`" ".join(s.split())`).
9. **Fixture ratchets tripped twice**: an env-directed `ENVF` default, then a `mktemp`-derived backup
   path. Recovery: made `ENVF` a literal (the test rewrites it in a scratch copy), and kept the
   original in memory instead of in a backup file. **Prevention:** already documented (work 6.6).
10. **guard-vacuity-floor's deferral ledger grew by the new suite.** Recovery: promoted the file.
    **Prevention:** already documented in guard-vacuity-floor.test.sh.
11. **lint-shell-trace-credential-refusal flagged `luks-monitor.sh` after a comment-only edit.**
    Recovery: added the xtrace refusal. **Prevention:** already documented (work 6.5: touching a
    file owes its whole debt).
12. **The mutation battery's M-tf-argv survived the first round.** The check was a substring
    containment where the property is exact-line equality. Recovery: exact-line assertion.
    **Prevention:** already documented (review: a prefix/containment pin is not the property).
13. **One Bash call combining `git worktree remove` with `rm -rf /var/tmp/...bak` was blocked.** The
    guard resolved it onto the worktree root. Recovery: split the calls. One-off.
14. **The git-history seat mislabeled verified facts as "P1".** One-off; its content was right, and
    the cutover-refusal claim it doubted was confirmed at `workspaces-cutover.sh`'s `already_cutover`
    guard.
15. **`vector-pii-scrub.test.sh` cannot run locally without a Vector 0.43.1 binary.** CI covers it.
    One-off environment limit.
16. **CI reddened `web-host-provisioner-parity-mutation.test.sh` G2-3 after I reported G2 green.**
    Adding a pinned-`host_key` `connection` block in `workspaces-luks.tf` moved the non-`server.tf`
    block count from 1 to 2, and the mutant's expected message encodes that number. I ran the guard
    (6/6) but not its mutation battery. Recovery: expected text updated to `swept only 2`, and
    `FLOOR_BLOCKS` raised 19 → 20 in the same edit. **Prevention:** already documented (work: a
    file-selected suite set cannot see a battery that encodes a baseline-derived count). When a
    guard has a `*-mutation.test.sh` sibling, run the sibling too.
17. **The first rotation apply failed on web-1 with `envfile_absent`, after the old token was
    already revoked.** The helper refused an absent `/etc/default/luks-monitor` by design ("refuse to
    invent it"). I never measured that precondition on the live host, and #8706 had already found
    the host timer dark with "the unit fails before emitting" as a candidate cause. Because the
    refusal came after the revocation, it left the host with no working token, not with the old one.
    The failure also tainted the installer, so every later infra apply would have reddened until a
    fix landed. Recovery: #8632 follow-up PR, the helper creates the file (after the proof, 0600,
    rollback to absent), and the tainted resource re-fires on that merge. **Prevention:** a refusal
    on a production host path is a claim about the live host's state. Before shipping one, find
    read-only evidence of that state, such as an existing emitter row or a prior apply's output. And
    order it against what the same apply has already done: a refusal that runs after an
    irreversible step no longer protects the old state.

## Tags
category: workflow-patterns
module: workspaces-luks
