---
title: "A guard keyed on a proxy for the hazard was wrong in both directions"
date: 2026-09-03
category: best-practices
module: apps/web-platform/infra
issue: 7640
pr: 7793
tags: [guards, mutation-testing, terraform, dns, verification, vacuity]
---

# Learning: my guard blocked the recovery and missed the hazard

## Problem

PR4b of the ADR-194 cutover flips the `soleur.ai` apex from a GitHub Pages `A`
record to a `CNAME`, at one Terraform address so core serialises Delete→Create.
Cloudflare rejects an `A` and a `CNAME` at one name (`81053`), so that ordering
is the whole safety case on a live, HSTS-preloaded apex.

The flip itself — a `moved` block and a new record, about fifteen lines — was
correct from the first RED/GREEN cycle and survived an eleven-agent panel
untouched.

**All 47 review findings were in the verification.** The guards, the runner, the
fixtures, the tests and the runbook I wrote to prove the flip was safe.

## The central defect

`[ack-destroy]` cannot discriminate a correct PR4b plan from a broken one —
`resource_deletes` is 1 in both — so I added a counter that HALTs the apply above
the ack gate. It counted a `pages_apex` create whose `previous_address` was
absent or wrong.

That is a **proxy** for the hazard, not the hazard, and a proxy is wrong in both
directions:

- It **missed** the real case its own error text named. A PR4a that merges
  without converging leaves four instances in state; the `moved` resolves the
  pinned key *correctly*, so `previous_address` reads clean while three orphan
  siblings plan as separate concurrent deletes. Four apex addresses in flight.
  Worse, `destroy_count` goes 1→4, and the merge commit already carries
  `[ack-destroy]` for the healthy 1 — so the ack authorising the intended
  replace authorises the orphans with it.
- It **fired on the safe recovery**. A replace that dies between Delete and
  Create leaves state holding neither address, so the re-run's `moved` no-ops for
  a legitimate reason and `pages_apex` plans as a bare create — with nothing left
  to collide with. The guard HALTed that, with no ack bypass, in the single worst
  state of the migration: apex recordless, NXDOMAIN negative-cached 1800 s. And
  its remediation text told the operator not to delete the `moved` block, which
  there is exactly the right action.

The property is **not two addresses**. Counting the co-occurrence of a
`pages_apex` create with any `github_pages` delete is strictly stronger, catches
the unconverged case, and admits the recovery.

## Key Insight

**Ask of every guard: is this the property, or a proxy for it?** A proxy fails in
both directions at once, and the two failures are asymmetric in how they present.
The missed hazard is silent. The false positive shows up only in the state the
system is already broken — which is the state nobody fixtures, because it is
uncomfortable to think about and the guard "obviously" is not for that case.

Concretely, for any guard that gates a destructive or recovery path, write down
the states the system can be in **including the ones after a partial failure**,
and ask what the guard reports in each. If it blocks a state you would need to
recover from, that is a P1 whether or not anyone has hit it.

## Supporting findings, same shape

- **A fixture set that moves one axis leaves every other conjunct vacuous.** Four
  fixtures varied only `previous_address`; deleting the `.type`, `.name` or
  create-scoping conjuncts each left the suite fully green. Eight fixtures now,
  each conjunct isolated, mutation-proven against a green control.
- **An anti-vacuity floor counting its own helper's counters backstops deletion
  and is blind to disarming.** Rewriting `_report` to route every verdict to the
  PASS arm reported `56 passed, 0 failed` with the floor satisfied. The fix is an
  instrument self-test driving both arms — the sibling suite already had one.
- **`cp A B` then `cmp B A` asserts that `cp` copies.** That tautological row
  certified a rollback generator which would have reverted the whole of `dns.tf`
  to a frozen snapshot, deleting `app.soleur.ai`, the Protonmail MX/DKIM set,
  `_dmarc` and DNSSEC — under a pre-baked `[ack-destroy]`. When a test's oracle is
  produced by the code under test, it cannot fail.
- **Two copies of one fact, and the weaker copy was on the dangerous path.** The
  GitHub-origin marker list existed twice; the probe — the rollback's branch
  selector, whose Cloudflare arm is *residual* — held three of six markers, so
  the three it did not know read as "already on Cloudflare" and route into
  reverting PR3, a second destroy.
- **A gate can be armed by accident.** `ssl-full-mitigation.test.sh` stays
  `pre-cutover` after this merge only because the `moved` block contains an IP
  literal — a one-shot artifact whose purpose ends at convergence. The disarming
  event is routine housekeeping, so the warning belongs at the deletion site.

## Instrument lessons

- **Deterministic lints and an agent panel have disjoint yields.** Two repo lints
  found three real defects in code written hours earlier that eleven agents did
  not surface. They fire only on *new* code, so running them at session start
  measures nothing — run them after each guard-shaped commit, before the panel.
- **A red control voids a mutation battery.** My first run's sandbox omitted
  `.github`; the control failed and I discarded the run rather than reading its
  rows.
- **A false fact in an incident runbook is worse than a bug**, because an agent
  executes it. Three shipped, including a hand-written rollback fallback that
  would have planned the apex for DESTROY by moving state into an address with
  no configuration.

## Session Errors

**Overwrote a tracked `session-state.md` without reading it** — clobbered PR4a's
session state, including an open AC52 thread recording that the deferred-cleanup
issue did not exist. Recovery: restored from HEAD, merged both sessions.
**Prevention:** the file showed as ` M` not `??` in `git status`; check the status
letter before a heredoc write to any path that may already be tracked.

**Blanket-ticked a phase's checkboxes** — marked task 0.5 (PF-DEFER) done when it
was not, and the evidence that it was not was in the file I had just overwritten.
Recovery: un-ticked with a rationale after restoring. **Prevention:** an
acceptance checkbox is a claim; tick each from its own evidence.

**Leaked two live bearer tokens** by running a token-carrying script under
`bash -x` while debugging it (#7797). **Prevention:** landed mechanically — the
script now refuses xtrace (`$-`, `SHELLOPTS`) and passes tokens via
`curl --config -` on stdin, closing the argv/`/proc` window too.

**Used a 403 as operator-only evidence**, violating
`hr-never-label-any-step-as-manual-without`. Recovery: ran the Playwright
attempt, which found BetterStack has a live session and is *not* operator-only.
**Prevention:** the rule already says this; the gap was mine.

**`grep -E '\t(healthy|unhealthy)$'`** — POSIX ERE has no `\t`, so a fail-closed
baseline guard never matched. **Prevention:** `printf '\t'` into the pattern.

**`tr -s '[:space:]'` collapsed newlines** in the CUT9 normaliser, joining every
record into one blob and defeating the set comparison it existed to enable.

**Fixed a record-labelling bug at one site and left it at the other** — the
capture path and the comparison path had the identical `printf` format-reuse
defect. **Prevention:** grep the construct, not the instance.

**Assumed identity mapping** for the legacy legal redirects; `terms-of-service`
consolidates into `terms-and-conditions`. Now derived from the config.

**Assumed `.status` on a Sentry monitor was health.** It is configuration state
and reads `active` during an outage, so CUT8 would have been vacuous.

**Truncated my own suite enumeration with `head -3`**, missing a mutation battery
that the registered runner then caught.

**Claimed in the PR body that the ssl-full guard flips to post-cutover.** It does
not — corrected, and the real mechanism is sharper.

**Attributed a marker to the probe that the probe did not carry**, in
`session-state.md`, as the positive control for its own verdict.

**Introduced a bug while fixing another** — the scoped-transform rewrite left
`www` pointing at the Pages project. Caught by my own suite, which is the system
working.

**Guessed an assertion-count floor** (26) instead of counting (24). The exact
cardinality floor caught it. **Prevention:** count the call sites.

**A guardrail hook blocked `gh issue comment` twice** because my issue PROSE
contained the literal `doppler secrets set`. The hook scans the command text and
cannot distinguish a command from a description of one — it blocked the sentence
documenting the block, which is the cleanest possible demonstration.
**Prevention:** when writing about a guarded command, describe it rather than
quoting it. Same collision class as a body-grep matching its own explanatory
comment (`cq-assert-anchor-not-bare-token`), pointed the other way: there the
prose satisfies the assertion, here it trips the guard.

**Ran `terraform init -backend=false` early for a syntax check**, which wrote a
local backend stub and made the later real `init` fail with "Backend
initialization required". Recovery: `-reconfigure`. **Prevention:** `validate`
needs no backend, but the stub it leaves is stateful — use a scratch dir, or
expect the reconfigure.

## Tags
category: best-practices
module: apps/web-platform/infra
