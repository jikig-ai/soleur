---
date: 2026-09-07
category: best-practices
tags: [guards, mutation-testing, terraform, uptime-monitoring, observability, assertions, vendor-contracts]
component: apps/web-platform/infra/www-apex-canonicalizer.test.sh
related_issues: [7798, 7883, 7884, 7895]
related_adrs: [ADR-204]
---

# My guard pinned the three attributes the vendor already refuses

## Problem

Issue #7798: `sentry_uptime_monitor.soleur_www` asserted `equals 301` on
`https://www.soleur.ai/`. Sentry's uptime checker always follows 3xx and grades the
assertion against the **final** response, so it compared `equals 301` to the apex's
200 — an assertion it cannot satisfy. The www redirect had no working alarm.

The fix moved redirect-health to Better Stack (`follow_redirects = false`), retargeted
the Sentry monitor to 2xx, and added seven guard cases so the new alarm could not
silently go vacuous.

Ten review agents then found that the guard pinned **the three attributes Better Stack
already refuses at create time (HTTP 422)** — `follow_redirects`,
`expected_status_codes`, `remember_cookies` — and left every attribute with no vendor
backstop unasserted. Ten one-line edits were measured to leave the suite at `OK: 31/31`
while killing the alarm:

```
A1 url repointed to apex   rc=0 :: OK: 31/31    <- #7798 verbatim
A2 monitor_type=status     rc=0 :: OK: 31/31    <- FAILS OPEN
A3 paused=true             rc=0 :: OK: 31/31    <- the #7798 STATE
A4 email=false             rc=0 :: OK: 31/31
A5 for_each={}             rc=0 :: OK: 31/31
A6 lifecycle ignore_changes rc=0 :: OK: 31/31
A8 confirmation_period=86400 rc=0 :: OK: 31/31
A9 policy_id removed       rc=0 :: OK: 31/31
```

`A2` is the worst: under `monitor_type = "status"` the status-code list goes inert and
the monitor reports **green precisely when www serves the site instead of redirecting**
— the exact state it exists to catch.

## Key Insight

**Before writing an assertion, determine what ALREADY enforces the property. An
assertion that duplicates an existing enforcement point pins nothing, and the
un-enforced sibling is the one that needed pinning.**

The three attributes I pinned were the three I had just been thinking about, because
the Phase 0 falsification probe had returned a 422 on each. That 422 is exactly the
evidence they did **not** need a guard. The attributes with no vendor opinion —
`url`, `monitor_type`, `paused` — never entered my attention, and they are the whole
property.

This is why "derive the assertion set from *what can make this ineffective*" is a
different instruction from "assert the things you verified". The first is an
enumeration over the failure space; the second is an enumeration over your own recent
working memory, and it reliably produces a guard shaped like the last thing you
debugged.

**The same error, one level up, produced the merge-blocker.** The plan reasoned that
`name` is an in-place attribute (only `organization`/`project` carry `RequiresReplace`)
and concluded the change was update-only and needed no `[ack-destroy]`. True about the
ATTRIBUTE, irrelevant to the change: the plan also renamed the resource's **address**,
which Terraform plans as delete + create regardless of provider schema. Measured through
the repo's own filter:

```
$ terraform show -json … | jq -f tests/scripts/lib/destroy-guard-filter-sentry.jq
{ "resource_deletes": 1, "resource_creates": 1, ... }     # no moved{} block
{ "resource_deletes": 0, "resource_creates": 0, ... }     # with moved{}
```

Both defects are the same shape: an assertion (a guard case; an "update-only" claim)
written against the enforcement mechanism that happened to be in view, rather than
against the one that actually governs the change.

## Solution

- **`moved {}` block** for the Sentry rename. Precedent already in-repo (`dns.tf`,
  `placement-group.tf`). Without it the `sentry-destroy-required` gate blocks the PR,
  and acked it destroys the live detector's check history mid-fix.
- **Guard 1 re-derived** from "what can make this alarm ineffective": `url`,
  `monitor_type`, `paused`, an armed notification channel, `confirmation_period`,
  `count` OR `for_each`, and no `lifecycle ignore_changes`. Cases renumbered `W1..Wn`
  because the sibling battery already owns `M1..M10` for unrelated rows.
- **Committed the mutation evidence.** The battery had **zero** rows touching
  `uptime-alerts.tf` — it copied the file into its sandbox only so the baseline would
  stay green. Replacing the whole Guard 1 section with tautologies reported `18/18`.
  Now 28 rows: nine kills plus a far-side green.
- **A far-side fixture, which did not exist at all.** Every Guard 1 fixture was
  must-trip, so nothing could catch the guard becoming *too aggressive* — and it was:
  `attr` reads the first physical line, so a `terraform fmt`-legal
  `expected_status_codes = [\n  301,\n]` FAILED on a semantically identical file.

## Prevention

- For any guard: **list what the vendor / compiler / platform already refuses, and do
  not spend assertions there.** A create-time 422 is a stronger guarantee than a
  grep-based test; assertions belong where nothing else is looking.
- For any Terraform rename: `moved {}`, and reason about the ADDRESS separately from
  the ATTRIBUTES. `RequiresReplace` says nothing about an address leaving the config.
- For any guard-shaped PR: **run the cheap deterministic lints and the mutation battery
  before the agent panel.** In this session `shellcheck`, `actionlint` and nine repo
  lints were all clean and found nothing; the battery found one real gap (`W11`, my
  `ignore_changes` anchor was line-anchored and a one-line `lifecycle { … }` evaded it);
  the panel found the rest. The yields are disjoint.
- **A harness that ABORTS instead of scoring is worth its cost.** The mutation harness
  refused three times — twice on a stale sandbox `NEEDED` list after I gave the guard
  new path operands, once on a non-unique anchor — rather than emitting confident-wrong
  verdicts. Every one was a real omission.

## Session Errors

1. **Read a commit's verdict from a pipeline.** `git commit … | tail -5; rc=$?`
   reported `tail`'s status as 0 while the commit had failed on markdownlint.
   **Prevention:** capture `rc` on its own line; never read a verdict through a pipe.
   Already documented in `work/SKILL.md`; it recurred anyway.
2. **markdownlint blocked three commits** (session-state MD022/MD032; ADR-194 + the gsc
   learning MD012/MD018/MD022, both pre-existing; the runbook MD031 from my own edit).
   **Prevention:** run `markdownlint-cli` on touched `.md` before staging.
3. **`git stash list` inside a probe** denied the entire Bash call.
   **Prevention:** `hr-never-git-stash-in-worktrees` covers the read-only subcommands too.
4. **`npx bun test` failed** (bun postinstall not run), and its background wrapper
   reported "exit code 0" while the run failed.
   **Prevention:** use the project's pinned binary; read the rc file, not the notification.
5. **`terraform validate` false FAIL** — my sandbox copied `*.tf` and missed the local
   module `./modules/git-data-userdata`. **Prevention:** for a root with local modules,
   `cp -a` the tree; verify the instrument before believing a failure.
6. **Mutation `W11` survived** — my `ignore_changes` absence anchor required line-start,
   so a one-line `lifecycle { ignore_changes = [...] }` evaded it. Caught by my own
   battery. **Prevention:** inside an already comment-stripped block, do not line-anchor
   an absence assertion.
7. **Mutation anchor not unique** — `verify_ssl / paused / }` terminates all three
   monitor blocks. **Prevention:** anchor on block-terminal context, and keep the
   `count == 1` assert that caught it.
8. **Harness ABORT ×2 on a stale `NEEDED` list.** **Prevention:** re-derive `NEEDED`
   from `grep -nE 'REPO_ROOT|SCRIPT_DIR' <guard>` whenever the guard gains a path operand
   (now written into the harness).
9. **Two Python `replace` assertion failures** — em-dash vs `--`, and an anchor that did
   not exist as written. **Prevention:** grep the anchor before scripting a replace.
10. **`lint-infra-no-human-steps` blocked the commit** — my runbook fix added a human-run
    `terraform plan`. **Prevention:** runbooks route infra reads through CI; the fix was
    to point at the scheduled drift run, which is strictly better anyway.
11. **Duplicated `SINGLE-PUBLISH` comment** — off-by-one in a line-slice replacement.
    **Prevention:** diff the hunk after a slice-based edit.
12. **Wrote `credentials_required: none`.** Per #7393/ADR-175 any non-empty value means
    SKIP-DECLARED, so it would have suppressed the very probe it described. Caught by the
    corpus baseline test. **Prevention:** the field's absence is the assertion.
13. **Propagated a 10-sample measurement as a 101-day universal** into ~11 files.
    **Prevention:** state the structural claim and the measured claim separately.
14. **Corrected `seo-aeo/SKILL.md` the wrong way** — repointed a claim at the new monitor
    when neither monitor covers a uniform `site.url` flip. **Prevention:** when sweeping a
    false claim, ask whether the REPLACEMENT is true, not just whether the old name is gone.
15. **Dropped the cadence term from the MTTD arithmetic** across 6+ sites (~20 vs ~23 min),
    while two of the repo's own artifacts already had it right.
    **Prevention:** when a number appears in >1 file, derive it once and check a sibling.
16. **Phase 1.6 self-skip** — compound's token-efficiency report measures `HEAD~1`, which in
    the pipeline is always review's `--allow-empty` trailer commit, so it reports
    `0 lines changed` on a 3241-line branch. Filed as #7895 (different subsystem).
    **Prevention:** a gate that measures a diff must name WHICH diff — branch vs
    last-commit is not a detail, and the pipeline's own commit ordering decided it.

17. **The guard's asserted set came from working memory, not an enumeration** — the
    session's headline finding, recorded here as a session error too because that is
    what it was. Pinned three vendor-refused attributes; left `url`, `monitor_type`,
    `paused`, `email`, `for_each`, `ignore_changes` and `confirmation_period` open.
    **Prevention:** derive the set from "what can make this ineffective", then
    subtract whatever the vendor/compiler already refuses.
18. **Implemented the plan's `moved{}` category error faithfully.** The plan asserted
    "update-only, no ack needed" from `RequiresReplace`; I did not re-derive it before
    building on it. **Prevention:** a plan's SAFETY claim is a precondition to verify,
    not a fact — the same rule already applied to plan-quoted numbers, extended to
    plan-quoted guarantees.
19. **Wrote prose in `cutover-verify.sh` asserting a PR-time guard that did not exist**
    ("www-apex-canonicalizer.test.sh catches the divergence at PR time first").
    **Prevention:** `hr-verify-repo-capability-claim-before-assert` — grep for the
    mechanism before crediting it. Fixed by building the cross-read rather than
    deleting the sentence.
20. **The AC14 sweep anchored on one phrasing of the claim**, so it walked past two
    live-guidance files asserting a DIFFERENT false thing about the same monitor.
    **Prevention:** index a correction sweep by the CLAIM's subject, not by the
    wording; a residual-zero count is evidence about a string, never about a claim.

**Forwarded from `session-state.md`** (plan phase, context compacted): an IaC write-guard
denial on the word "out-of-band"; markdownlint blocking the first plan commit; and four
research errors caught by plan-review — a truncated read of a 250 KB test file, a
stale-claim sweep run with `':!knowledge-base'` (which is what hid ADR-194), Better Stack
quota counted from `.tf` declarations rather than live state, and a paid-tier-gated block
cited as an established pattern. **Prevention** for the sweep case is now encoded in this
PR's own AC14 amendment: index a correction sweep by the CLAIM, not by one phrasing of it.

## Tags

category: best-practices
module: apps/web-platform/infra
