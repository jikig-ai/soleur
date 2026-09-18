---
title: "git-data boot-signal poll: make the read work, make its failure self-describing"
type: fix
date: 2026-09-17
slug: fix-git-data-boot-signal-poll
branch: feat-one-shot-8178-boot-signal-poll
issue: 8178
# NOT `closes:` — the close criterion is event-gated (QG11); the PR body carries `Ref #8178`
# and scripts/followthroughs/git-data-boot-poll-8178.sh closes it on real evidence.
ref: 8178
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# git-data boot-signal poll: make the read work, make its failure self-describing

## Enhancement Summary

**Deepened on:** 2026-09-17
**Review rounds folded in:** 4 (CTO domain review, SpecFlow audit, scoped advisor
consult, and a four-agent plan-review panel), plus this deepen pass.

### Key improvements

1. **A rival explanation was tested instead of assumed.** ADR-192 records that reads
   against this table answered HTTP 500 `CLUSTER_DOESNT_EXIST` because the source had
   never stored a row — dated before both cited runs, and indistinguishable from an
   auth failure through `--fail-with-body`. Measured and refuted: the table holds 31
   rows before 2026-09-15, oldest `dt 2026-09-04 15:15:56`.
2. **The plan was cut back twice.** A pre-apply probe, a typed-confirm-token override,
   a `mixed` outcome, an `ingest_dark` outcome with its control read, an early break,
   and a pre-merge diagnostic step were all removed — each because a reviewer showed it
   bought no property, or inverted on this source. `## What was cut` records them.
3. **The library moved to `scripts/lib/`** after `lint-diagnosis-claims.sh` (the
   blocking AP-021 hook) and `lint-workflow-errexit-capture.py` (AP-022) were found to
   be path-scoped in ways that would have moved this change's prose and rc capture out
   of their reach — in a plan about diagnostic honesty.
4. **The run anchor became load-bearing and correctly typed.** `dt` is `DateTime64(6)`,
   so a bare epoch integer would have matched every row while still passing a hermetic
   stub, and `dt` is emitter-assigned, so the anchor needs a clock-skew allowance.
5. **The follow-through predicate was rewritten** after it was found already satisfiable
   by a row that predates the fix — #8178 could have closed without the poll ever
   running.

### New considerations discovered in this pass

- `scripts/lib/betterstack-sources.sh` already owns `BS_GIT_DATA_TABLE` and
  `BS_GIT_DATA_TABLE_S3`. FR9 originally re-spelled both as literals; the library
  exists because #7855 found one source spelled three ways joined only by prose.
- The classifier's rc partition is eight classes, not five, and needs a
  `table-missing` token for the `CLUSTER_DOESNT_EXIST` shape this issue's own history
  produced.
- The cutover suite inlines `_bs_read_remedy`'s *text* into a generated driver rather
  than calling it, and the hermetic suite must stub `doppler` as well as the query
  script — otherwise every row grades rc=127.

## Overview

The git-data host's boot-signal poll is the only in-job evidence that a newly born or
replaced host actually came up. It has never returned a row. Both real dispatches
recorded twenty consecutive transport failures, and because the step pipes the query's
stderr to `/dev/null`, the run log cannot say why.

This plan routes the read through the credential path that is measured to work, makes
a failed read name its own cause in the run log, stops a window that was never read
from being reported as a statement about the host, and anchors the query to the
dispatch so a previous host generation's row can never be mistaken for this one's.

## Problem Statement

`.github/workflows/apply-web-platform-infra.yml`, job `git_data_host_create`, step
`Poll for the git-data boot-completion signal` (id `poll`) is ADR-149 checklist item
4's only in-job discharge. Measured, self-pulled 2026-09-17:

| Run | When | Apply | Poll result |
|---|---|---|---|
| 34822248580 | 2026-09-14 08:24 UTC | skipped by the birth gate | 20/20 `rc=22`; terminal `Could not read the boot signal at all` |
| 34836141887 | 2026-09-14 15:13 UTC | success, host born | 20/20 `rc=22`; same terminal branch, job RED, birth UNVERIFIED |

`gh run view <id> --log` on both runs returns twenty `poll N/20: rc=22, no
boot_complete row yet` lines and zero occurrences of `DB::Exception`, `Code: <n>`,
`ACCESS_DENIED` or `Authentication failed`. That negative is **vacuous, not
exculpatory**: the HTTP error body lands on stdout and was never echoed, and stderr
went to `/dev/null`, so no body text could have appeared whatever the cause. The cause
is not recoverable from the log — which is the defect, not a clue.

`rc=22` is `curl`'s exit on `--fail-with-body` against HTTP >= 400 — the request was
sent and the endpoint refused it. `--fail-with-body` does not distinguish 400 from
401, 403, 404 or 500, and this repo has a documented 500 on this exact table
(ADR-192's `CLUSTER_DOESNT_EXIST`), so the class was not assumed: it was tested and
refuted (see `## Premise Validation`). What survives is a difference of credential —
the step binds `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` from GitHub repository
secrets, while the apply step directly above it, and every other operative Better
Stack read in this repo, resolves them through
`doppler run -p soleur -c prd_terraform`. The plan does not claim that is the *only*
possible difference; it claims every rival it could name has been tested, and that
change 2 is what makes the next one name itself.

Three consequences compound:

1. **The instrument has never run.** A poll that has never succeeded is
   observationally identical to a poll that correctly found nothing. Run
   34836141887 proves the cost: the host was genuinely dark (`gitdata_doppler_dl`
   FATAL) and produced exactly the output a healthy host would have produced.
2. **The failure is mute.** `2>/dev/null` is why characterising this took two
   dispatches and a manual investigation.
3. **Readability and silence are conflated at the per-poll line.**
   `echo "poll ${i}/20: rc=${rc}, no boot_complete row yet"` runs on every
   iteration, including the ones where nothing was asked, so forty transport
   failures read in the log as forty quiet polls.

## Premise Validation (plan Phase 0.6)

Every claim asserted by reference was probed before research was dispatched. All
measurements are from 2026-09-17 on this branch.

| Premise | Verdict | Evidence |
|---|---|---|
| #8178 is open and unresolved | HOLDS | `gh issue view 8178 --json state,closedByPullRequestsReferences` → `OPEN`, empty |
| The poll step is live on main with `2>/dev/null` | HOLDS | `git show origin/main:…apply-web-platform-infra.yml`, step `Poll for the git-data boot-completion signal`, query terminated `FORMAT JSONEachRow" 2>/dev/null)` |
| 20/20 `rc=22` on both cited runs | HOLDS | `gh run view 34822248580 --log`, `gh run view 34836141887 --log` |
| The terminal message prints `last rc=${rc}` unexpanded | REFUTED | the literal appears only in the echoed script source; the `##[error]` output reads `last rc=22`. Not a defect. |
| The identical query succeeds from Doppler `prd_terraform` | HOLDS | run by this session: the poll's exact `remote() UNION ALL s3Cluster(primary, …)` shape, `rc=0`, 2 rows, newest `boot_complete` `dt 2026-09-16 15:39:36` |
| The `s3Cluster` archive arm is the 4xx (the #7855 shape) | REFUTED | arm-isolated probes under the same credential: `remote()` alone `rc=0`/0 rows (hot window ~40 min; the row is two days old); `s3Cluster` alone `rc=0`/3 rows. Both arms answer. |
| A mis-pinned table could be the 4xx | REFUTED | the pinned identifier `t520508_soleur_git_data_prd_logs` is the one measured to answer |
| The git-data ClickHouse table did not yet exist during the cited runs, so the 4xx was ADR-192's `CLUSTER_DOESNT_EXIST` rather than a credential fault | **TESTED, REFUTED** | ADR-192 records (2026-09-06) that Better Stack creates the table lazily on the first *stored* row, that the git-data source had stored none, and that reads therefore answered HTTP 500 `CLUSTER_DOESNT_EXIST` — and `curl --fail-with-body` exits 22 on 500 exactly as on 401/403, so this was a live rival explanation dated before both runs. Measured by this session: the table holds **31 rows dated before 2026-09-15**, oldest `dt 2026-09-04 15:15:56`, so it existed and held rows on 2026-09-14. Residual caveat, named rather than hidden: `dt` is emitter-assigned and bounds emit time, not storage time; #7855 ("202 but stores nothing") closing 2026-09-07 is the corroborating date. |
| Prior art dde55bcf2 changed WHEN the poll runs, not whether it reads | HOLDS | committed 2026-09-14 22:03, after both cited runs; `2>/dev/null` and the GitHub-secret binding are both still on main |
| PR #8252 touches the same two files in disjoint regions | HOLDS | merge-conflict risk only |
| The `BETTERSTACK_QUERY_*` GitHub secrets are IaC-managed | REFUTED | no `github_actions_secret` resource exists; `gh secret list` shows all three last written **2026-07-03**, while git-data's own Logs source was created by #7772 (closed 2026-09-04) |

**A premise the brief asserts that measurement moved.** The brief says "could not
query at all" and "queried fine, no row yet" are "collapsed today". They are not:
main already carries two distinct terminal branches. The real collapse is one layer
down, in the predicate and the per-poll line — see `## The terminal-branch decision`.
The brief's conclusion survives; its stated mechanism does not.

**A premise nobody asserted, and it reshapes the scope.** `git_data_host_replace` has
no boot poll at all, and it is the job that actually runs: runs 34861860722
(2026-09-14 15:23) and 35116580943 (2026-09-16 15:37) were both
`git_data_host_replace :: success`, and the live host's newest `boot_complete` carries
`dt 2026-09-16 15:39:36`. A host therefore exists, and the birth gate refuses any
zero-create plan, so every future `git_data_host_create` dispatch is refused until the
host is destroyed. A fix confined to the birth job would ship a guard that cannot fire
on the route that is used. See `## Scope: both jobs, and why`.

**Stated precisely, because the short form of this argument is false.** `git_data_host_create`
is not a job that never runs — it RAN, and FAILED, in both of #8178's cited runs
(`34822248580` and `34836141887`: `git_data_host_create = failure`, `git_data_host_replace =
skipped`, measured). That is the entire evidence base for this issue, and a claim that the
birth job "cannot fire" would make #8178's own measurements inexplicable. The accurate claim
is narrower and is about the FUTURE: birth is a once-ever event, so with a live host now
present the birth job is dormant and every subsequent boot goes through `replace` — which has
no poll at all, and completed green on 2026-09-16 with zero in-job boot verification. Fixing
only the birth job would therefore be correct and never exercised again; fixing only `replace`
would leave #8178's measured defect in place. Both, for those two distinct reasons.

**A SECOND defect this plan did not carry, measured at implementation: the credential fix
alone would NOT have verified the one birth we have data for.** The 20 x 30 s bound is too
short for the boot it watches. Measured on run `34836141887` (the birth that succeeded):

| Event | Time (UTC) | Source |
|---|---|---|
| `Poll for the git-data boot-completion signal` starts | `15:14:37` | `gh run view 34836141887 --json jobs` |
| Poll gives up (20 x 30 s) | `15:24:47` | same, step `conclusion: failure` |
| The host's actual `boot_complete` row | **`15:27:24.816663`** | the pre-fix control, arm A |

The host reported **2 m 37 s after the poll stopped looking**. So with `BETTERSTACK_QUERY_*`
working perfectly, that run still reports `silent` — "the host never reported" — about a host
that reported shortly afterwards. That is the SAME defect class #8178 names (a guard asserting
a cause that did not occur), reached by a different route, and a fix that only repairs the read
would have shipped it intact while looking complete.

Both halves are therefore in scope, and they are independent: the read fix converts
`unreadable` into a real answer, and the bound fix is what makes that answer `received`
rather than a false `silent`. The bound is raised to cover the measured envelope with margin
(observed boot latency ~14 m 30 s from job start; the previous bound expired at ~10 m), and
the measurement above is the justification — not a round number chosen for comfort. The
suite's `max_polls` / `interval_s` parameters already exist for the hermetic run, so this
changes a call-site argument, not a mechanism.

**Residual, named rather than hidden:** one observation is not a distribution. `14 m 30 s` is
a single measured boot on one host class; the raise buys margin over that one point, and a
genuinely slow boot can still exhaust any finite bound. That is acceptable precisely because
the verdict vocabulary now distinguishes `silent` from `unreadable` — an exhausted bound is
reported as what it is, not as a read failure.

## Proposed Solution

Five changes. Each buys one named property; nothing here is optional.

1. **One credential source.** The poll resolves `BETTERSTACK_QUERY_*` through
   `doppler run -p soleur -c prd_terraform`, exactly as the apply step directly
   above it already does, and the three `secrets.BETTERSTACK_QUERY_*` bindings
   leave the step. The job already installs the Doppler CLI and already holds
   `secrets.DOPPLER_TOKEN`, so this adds no bootstrap and no new secret. The
   credentials-absent guard is retargeted at `DOPPLER_TOKEN`.
2. **A read that reports.** stderr goes to a **file**, never into the match
   buffer; on a failed read the step prints rc, a classification token, the
   response body's byte length and a first stderr line scrubbed of quoted values
   and of `*.betterstackdata.com` hostnames — never the body itself.
3. **A verdict anchored on the final read.** `received` / `silent` / `unreadable`,
   decided by a pure function a suite can drive into every arm.
4. **A query anchored on the dispatch.** `BOOT_TRAIL_SINCE` is stamped before
   apply and the predicate becomes `dt > <anchor>` instead of
   `now() - INTERVAL 2 HOUR`, so a previous host generation's row can never read
   as this dispatch's boot.
5. **A pinned table that cannot be overridden.** `BS_TABLE` and `BS_TABLE_S3` are
   pinned unconditionally rather than defaulted.

### Why one credential source rather than reconciling two

The failing step and the working path run the same script over the same SQL against
the same table; the only difference is where the credential comes from. Two supporting
facts make a single source the honest minimum rather than a shortcut:

- The step's own error text already names the wrong store. Both `::error::` strings
  tell the reader to check `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} in
  prd_terraform`, and the comment above the guard says "The credentials live in
  prd_terraform already". The step then reads GitHub secrets. The remediation and
  the binding have disagreed since #6982; this change makes the binding match the
  remediation rather than the reverse.
- The GitHub secret values were last written 2026-07-03. git-data's own Logs source
  (2734275) was created by #7772, closed 2026-09-04. Whatever those values are, they
  were minted before the source they are now asked to read existed.

**On diagnosis versus workaround.** The clean discriminator would be to run the failing
read with the GitHub-secret values and read the status; GitHub repository secrets are
write-only through the API, so their values are not in hand, and `rc=22` spans 400,
401, 403 and 404. That gap is named rather than papered over — but it does not change
the remedy. The one hypothesis a status code would have excluded that the swap could
otherwise mask is a mis-pinned table, and that is refuted directly: the pinned
identifier is the one measured to answer. Every surviving hypothesis is credential-side
and every one has the same fix. A temporary pre-merge probe printing the status from a
`pull_request` job was considered and cut: it adds and then deletes a step in a public
workflow to learn which of several equivalent causes applies, and change 2 makes the
next divergence on any path self-naming on its first occurrence, which is the better
trade.

### Why the failure surfaces a classification and not the response body

The brief asks the step to "surface the response body/status on failure". The repo has
a measured egress rule that forbids the body half, and it is load-bearing: this
repository is **PUBLIC** (`gh repo view --json visibility` → `PUBLIC`), its Actions
logs are world-readable, and a ClickHouse auth failure body reads
`Code: 516. DB::Exception: <BETTERSTACK_QUERY_USERNAME>: Authentication failed…` —
half of a Basic-auth pair. `scripts/cutover-inngest.sh`'s `_bs_read_remedy` records
this as a rule measured at review on 2026-09-11: never the body; only its length, a
classification, and a scrubbed stderr line.

The plan therefore delivers the property the brief asks for — the next occurrence
names its own cause from `gh run view` alone — through rc, classification, length and
scrubbed stderr, and declines the one channel that would put a credential fragment in
a public log. No silent-failure channel is left: every arm prints.

### Why only the classifier's partition is shared

`_bs_read_remedy()` already partitions the reader's rc space (3 = credentials absent;
1 = the wrapper or reader exited 1; 22 = an HTTP error under `--fail-with-body`;
6/7/28/35 = DNS / connect / timeout / TLS; 2/64/78 = the reader's own refusals) and
carries the two body greps that separate `credentials-rejected` from
`source-under-maintenance`. It cannot be reused whole: it only *prints*, its
`body_class` is function-local, its arms hard-prefix the inngest cutover's `2.0` label,
and every rc=22 arm ends "Re-dispatch later." — which on the birth path is an
**impossible** remedy, because the birth gate refuses a zero-create plan for as long as
a host exists.

So only the partition is shared, and by the smallest move that shares it:

- New file `scripts/lib/betterstack-read-classify.sh` containing one pure function,
  `bs_read_classify <rc> <rowsfile>`, emitting exactly one token on stdout and
  returning 0 unconditionally (a trailing `grep -q … && printf` would return non-zero
  on the common path and abort a `set -e` caller). The token set covers the full rc
  partition `_bs_read_remedy` already makes, which is **eight classes, not five**:
  `credentials-absent` (rc=3 — the three query variables not injected),
  `reader-exit-1` (rc=1 — `doppler run` or the reader itself exited 1, which names
  `DOPPLER_TOKEN`, not the Better Stack credentials), `credentials-rejected`,
  `source-under-maintenance`, `table-missing`, `reader-refusal` (rc 2/64/78),
  `transport` (rc 6/7/28/35) and `other`. Omitting `credentials-absent` and
  `reader-exit-1` would fold the two faults **most likely to arise from this change's
  own edits** into `other`.

  `table-missing` is new rather than inherited, and this issue's own history demands
  it: ADR-192 records that a read against a source that has never stored a row answers
  HTTP 500 `CLUSTER_DOESNT_EXIST`, which `--fail-with-body` reports as the same
  `rc=22` as an auth failure while meaning the opposite — the producer, not the
  reader, is at fault. It is matched on the vendor code, and it is the reason the run
  log could not have told the two apart.

  **Precedence is preserved exactly.** Today the two body greps are sequential
  assignments, so `maintenance` *overwrites* `credentials-rejected` when a body
  carries both markers. A natural `if`/`elif` rewrite inverts that silently and no
  existing fixture discriminates, so the extraction keeps the assignment order and the
  suite pins it with a body containing both.
- `scripts/cutover-inngest.sh` sources it, and `_bs_read_remedy` **stays where it
  is, at its current name and arity**, calling `bs_read_classify` in place of its
  inline partition. Its output and its callers are untouched.

An earlier revision of this plan proposed moving `_bs_read_remedy` out of that script
and parameterising its label and forward action. That was rejected here: it changes a
safety-critical operator script four ways (move, arity, two compatibility defaults,
and a repoint of the suite that extracts the function by name) to buy a property that
a twelve-line pure function buys outright. The printers legitimately diverge — they
want different forward actions — and only the partition needs to be single.

## The terminal-branch decision

**The question.** Should "could not query at all" and "queried fine, no row yet"
remain one terminal branch?

**They are already two, and that is correct** — different facts, different
remediations, and the repo has litigated this class. `flush_latch_decide()` in
`scripts/cutover-inngest.sh` records the ruling at #7674: `silent` is distinct from
`unreadable` "because the forward actions differ: `unreadable` points at
`BETTERSTACK_QUERY_*` credentials in prd_terraform; `silent` points at the dedicated
host having gone dark. Collapsing them prints the wrong remediation at the worst
possible moment."

**What is actually collapsed.** Three defects sit below the branch, and together they
are why 40/40 transport failures read as quiet polls:

1. **The per-poll line asserts a host fact from a read that did not happen.**
   `poll ${i}/20: rc=${rc}, no boot_complete row yet` prints on every iteration.
   On a failed read nothing was asked, so "no row yet" is not a fact in evidence.
   The line branches on the read's outcome: an answered empty read says no row
   yet; a failed read says the read failed and names its class.
2. **The unreadable branch is all-or-nothing.** It requires `query_fails -ge 20`,
   and `query_fails` resets to `0` on any `rc=0`. Nineteen failures followed by one
   clean empty read therefore routes to the *host* verdict, whose text asserts
   "the query path answered, so this IS a statement about the host" — over a window
   that was 95% unobserved.
3. **`rc=0` is a transport verdict, not a query verdict.** ClickHouse can return
   200 and append an exception to a streaming `FORMAT JSONEachRow` body; curl exits
   0. A `silent` declared over such a read routes the operator to the dark-host
   tree on a read that failed mid-stream.

**The vocabulary is not this plan's to invent.** `scripts/lib/betterstack-absence.sh`
(ADR-192, "an empty warehouse read is three states, not one") is the repo's single
implementation, and this plan consumes it rather than re-deriving beside it:

- `bs_absence_response_is_answer()` is the existing discriminator for defect 3. Its
  test is the line's **SHAPE** — every legitimate row begins `{"dt":` — never a
  content grep for `DB::Exception` / `Code: <n>`, which the library records as
  measured *wrong* for a query selecting `raw`, since `raw` is arbitrary
  application log text.
- `bs_absence_control_satisfied()` answers "is this source receiving anything at
  all", which is what separates a dark host from the #7855 warehouse shape
  ("Better Stack returns 202 but stores nothing for git-data source 2734275").

**The predicate is the final read, not a count.** Each poll queries the anchored
window, so one answered read at the *end* of the window is complete evidence about the
window; demanding twenty clean reads would let a single transient 5xx abort a birth.

| Outcome | Condition | Step exit | Remediation the log prints |
|---|---|---|---|
| `received` | a row parsed with `"stage":"boot_complete"`, dated after the run anchor | 0 (1 if a named assertion is `no`) | none — assertions are then checked per named field, as today |
| `silent` | the FINAL read ANSWERED (rc=0 **and** `bs_absence_response_is_answer`) and matched nothing | 1 | the host verdict: no signal **within the 10-minute budget** against a ~6-minute observed envelope, so re-read the source before acting; then Sentry's git-data fatal stages and the partial-birth decision tree |
| `unreadable` | the final read did not answer | 1 | the read-path verdict: this says NOTHING about the host; the classification names which fault, and the ok/total read counts print here |

**`mixed` was considered and cut.** An earlier revision carried a fourth arm for a
partially-read window. It had the same exit code and the same remediation as
`unreadable` and differed only by printing the ok/total counts — which is a log field,
not an outcome. Printing those counts unconditionally in the `unreadable` arm loses
the operator nothing and removes a parameter from the decision function.

**`ingest_dark` was considered and cut, and so was the control read behind it.**
ADR-192's third state is real and #7855 is a real precedent for this source, so an
earlier revision added a control read (`bs_absence_control_satisfied`) to separate a
dark host from a dark warehouse. Review established that this inverts here. That
function asks "is the warehouse receiving **anything at all**", and both ADR-192 and
the library's own comment scope it to an **account-wide** refusal on a **shared,
multi-producer** source. `t520508_soleur_git_data_prd_logs` is a *dedicated
single-producer* source since #7772 — so on a host that boots so dark it emits nothing
at all, the control is unsatisfied and the arm would have announced "the evidence
store is not accepting writes" about a host that never came up. That is this issue's
own conflation with the arms swapped, on the worst case in the partition.

Running the control against a shared source instead would restore the account-wide
question, at the cost of a second credentialed read, a fourth verdict, a parameter, a
mutation row and a scenario — to change prose on a verdict that already exits 1 and
already routes to Sentry, which `## Observability` names as the independent channel
that distinguishes the two. The control is therefore out of scope, and the `silent`
arm's existing Sentry route carries the disambiguation.

## Scope: both jobs, and why

`git_data_host_create` is the route the issue names. `git_data_host_replace` is the
route that runs, twice in the measured window, and it carries no boot poll. Because a
live host exists, the birth gate refuses every zero-create plan, so a fix wired only
into `git_data_host_create` cannot execute until the host is destroyed.

What the replace job carries instead is `Post-replace readiness note (authoritative
liveness is web-host-driven, non-SSH)`, whose summary says the authoritative liveness
gate is out of job. Its stated reasons are sound and are not contradicted here: the
runner cannot SSH a deny-all host, cannot reach it over the private net, and Better
Stack cannot *pull* it because `git_data_prd` is a paused PUSH monitor. None of those
reach the channel #6982 actually built — the host's own PUSH of `stage:boot_complete`
into Logs source 2734275, which is a read, not a pull. That channel demonstrably works
across a replace: the live host's newest `boot_complete` is dated roughly two minutes
after run 35116580943 dispatched one.

**Three things must land before the poll can fire there**, and none is optional:

- `Terraform apply (git-data-host -replace) — both-volumes-preserved assert`
  **carries no `id:`**. The poll's gate is
  `steps.apply.outcome == 'success' || == 'failure'`, and the enumerated form fails
  closed on the empty string, so a verbatim copy ships a poll that is permanently
  SKIPPED on the only route that fires. Add `id: apply`.
- That job's `Dispatch summary` carries neither the empty-outcome backstop nor the
  outcome-pair `case` the birth job's summary has (verified: the birth summary binds
  `APPLY_OUTCOME`/`POLL_OUTCOME`, fails closed when either is empty with "a step id
  was renamed or mis-keyed; this birth is UNVERIFIED", and branches on
  `${APPLY_OUTCOME}/${POLL_OUTCOME}` with a catch-all `success/*`). Port both.
- Its remediation text must be **distinct from the birth job's**. The birth path can
  safely say "do NOT re-dispatch (the gate refuses a zero-create plan)" because the
  birth gate is a mechanical backstop against a panic re-dispatch. The replace path
  has no such backstop: a re-dispatch there destroys and recreates the host. Its
  arms route to the out-of-job `git ls-remote` liveness check instead.

**The birth job is wired first.** Replace is the route that fires, but it is also the
destructive one, and making it the first consumer of a never-executed poll is the wrong
order for review. Birth is the safe job to land the call site in; the replace wiring is
a `source` line and a call once the library exists, and gets its own commit.

## What was cut, and why it was cut

Two independent reviews converged on the same over-growth, and the mechanisms below
were removed rather than defended. They are recorded here because a cut list that only
names rejected *alternatives* cannot catch a plan over-growing its own design.

| Mechanism | Why it was cut |
|---|---|
| A pre-apply read-path probe refusing a dispatch when the source cannot be read | It refuses only on `credentials-rejected` and reader refusals. Both cited runs grade `other` — their logs contain zero matches for `Authentication failed` / `Code: 516` / `maintenance` — which is transient, on which the probe would warn and proceed. On the exact 40/40 failure this plan exists to fix, it does nothing, while adding a vendor read dependency to the recovery path for the fleet's most irreplaceable data store. |
| A typed-confirm-token override for that probe | Its admissible set was empty: the probe's only refusals were the two classes the override itself refused. Dead branch with an input, a summary write and four mutation rows. |
| A requirement carrying the probe's verdict into the poll's arms | It existed only to repair a contradiction the probe introduced (a post-apply `unreadable` pointing at a store the same run had just validated). |
| A new readiness step in `git_data_host_replace` to host the probe | New surface on the destructive route, for the probe above. |
| A `mixed` fourth outcome | Identical exit and remediation to `unreadable`; differed only by a printed counter. |
| `ingest_dark` as a fifth outcome | Downgraded to a `::warning::` on the `silent` arm; see above. |
| An early break on a non-retryable classification | Its own measurement showed it would not have fired on either cited run, and it forced a fifth parameter into the decision function to resolve a contradiction only it created. |
| Moving `_bs_read_remedy` and parameterising its label and forward action | Replaced by a classify-only extraction; see above. |
| A temporary pre-merge probe step printing the GitHub-secret status | See `## Why one credential source`. |

## Research Insights

### Measured evidence pulled by this session (2026-09-17)

- The poll's exact query shape under `doppler run -p soleur -c prd_terraform`,
  `BS_TABLE=t520508_soleur_git_data_prd_logs`: `rc=0`, 2 rows, newest
  `{"dt":"2026-09-16 15:39:36.988877","stage":"boot_complete","host":"soleur-git-data"}`.
- Arm isolation under the same credential: `remote($BS_TABLE)` alone `rc=0` / 0 rows;
  `s3Cluster(primary, $BS_TABLE_S3)` alone `rc=0` / 3 rows.
- `gh run view` on both cited runs: 20 `rc=22` poll lines each; zero
  `DB::Exception` / `Code:` / `ACCESS_DENIED` / `Authentication failed` matches.
- `gh secret list`: all three `BETTERSTACK_QUERY_*` repository secrets last written
  2026-07-03; no `github_actions_secret` Terraform resource exists.
- `gh repo view --json visibility` → `PUBLIC`.
- `.github/workflows/scheduled-followthrough-sweeper.yml` header: it "comments FAIL
  on exit 1, comments TRANSIENT on any other exit".

### Relevant files (anchored on content, not line numbers)

- `.github/workflows/apply-web-platform-infra.yml` — jobs `git_data_host_create` and
  `git_data_host_replace`; steps `Poll for the git-data boot-completion signal`,
  `Terraform apply (git-data birth)`, `Terraform apply (git-data-host -replace) —
  both-volumes-preserved assert`, `Post-replace readiness note (authoritative
  liveness is web-host-driven, non-SSH)`, `Install Doppler CLI`, `Dispatch summary`,
  and `Stamp boot-trail run anchor (create)` / `(replace)` in the web-host jobs.
- `scripts/betterstack-query.sh` — Mode 1 raw SQL (`$1` matched against
  `^(SELECT|WITH|SHOW)`); `BS_TABLE` / `BS_TABLE_S3` substitution, longer token
  first; one `curl --disable --noproxy '*' -sS --fail-with-body --max-time 60`, so an
  HTTP error's body lands on **stdout** and the script's diagnostics on stderr.
- `scripts/lib/betterstack-absence.sh` — ADR-192's implementation:
  `bs_absence_response_is_answer`, `bs_absence_control_satisfied`,
  `bs_absence_classify`, and the `BETTERSTACK_QUERY_SCRIPT` override seam.
- `scripts/cutover-inngest.sh` — `_bs_read_remedy()` (the rc partition, the body
  greps and the egress rules), `_bs_query_rows()` (the Mode 2 `doppler run` reader),
  `flush_latch_decide()` (the #7674 `unreadable`-vs-`silent` ruling, and the
  extraction contract: signature and closing brace at column 0).
- `tests/scripts/lib/` — the sourced-gate convention this plan follows
  (`git-data-host-birth-gate.sh`, `git-data-host-replace-gate.sh`,
  `git-data-birth-readiness-gate.sh`, `stock-preflight-gate.sh`), sourced from the
  workflow under a `# shellcheck source=` directive and pinned by a paired
  `tests/scripts/test-<name>.sh` registered in `scripts/test-all.sh`.
- `tests/scripts/test-git-data-rung2-evidence-capture.sh` — the stub contract to
  follow: the `betterstack-query.sh` stub answers by **matching the SQL it is
  handed**, not by call ordinal.
- `knowledge-base/engineering/operations/runbooks/git-data-birth.md` — the readiness
  table row about the query credentials, and `## After the birth — verify the host
  actually booted (#6982)`, whose prescribed query is the Doppler-sourced form this
  plan moves the poll to.
- `knowledge-base/engineering/architecture/decisions/ADR-149-…` (item 4),
  `…/ADR-192-an-empty-warehouse-read-is-three-states-not-one.md`,
  `knowledge-base/engineering/architecture/diagrams/model.c4` (edges
  `gitDataStore -> betterstack` and `github -> betterstack`).

### Institutional learnings that constrain this plan

- `knowledge-base/project/learnings/2026-09-14-the-sweep-that-retired-false-sentences-wrote-new-ones-from-my-own-issue-comment.md`
  — the session that filed #8178. Its prevention line is requirement 2 verbatim: "a
  verification step must print the first stderr line of a failed probe; `2>/dev/null`
  on the only verifier hides the cause."
- `knowledge-base/project/learnings/2026-07-20-the-fix-for-an-evidence-discarding-gate-discarded-its-evidence.md`
  — the litmus: grep whether any caller wraps the probe in `$(...)`; if one does, the
  telemetry is already gone. The poll does, which is why stderr goes to a file rather
  than being re-plumbed into the substitution.
- `knowledge-base/project/learnings/2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`
  — "first prove the check *can* fail; then care that it didn't." This is why the
  mutation battery and the non-canonical must-PASS rows are acceptance criteria.
- `knowledge-base/project/learnings/2026-09-17-scoping-a-verdict-on-an-unanchored-query-is-a-false-close-primitive.md`
  — the run anchor (FR8) and the follow-through's run-anchored predicate both exist
  because of this class; the first revision of the follow-through *was* an instance
  of it.

### Property List (plan Phase 0.6b)

| # | Property | Observable outcome |
|---|---|---|
| P1 | The poll can read the git-data boot signal from CI | a dispatch's poll step reaches an answered read against `t520508_soleur_git_data_prd_logs` |
| P2 | A failed read names its own cause in the run log | `gh run view <id>` alone yields rc, classification, body length and a scrubbed stderr line |
| P3 | A window that was not read is never reported as a host verdict | the `unreadable` arm prints the read-path remediation and the ok/total counts, never the host one |
| P4 | Every arm of the decision can be driven RED by a suite | a mutation battery reddens each arm, including the guard's own dispatch |
| P5 | A `boot_complete` from a previous host generation never yields `received` | a row dated before the run anchor is not a match |

### Cut List (plan Phase 0.6b)

| Mechanism proposed | Property it would buy | Why it is cut |
|---|---|---|
| A new failure classifier written for the poll | P2 | `_bs_read_remedy()`'s partition already buys it, with measured egress rules. Extracted as `bs_read_classify` and shared. |
| Printing the HTTP response body on failure | P2 | Repo is PUBLIC and a ClickHouse 403 body names the username. Replaced by status + classification + byte length + scrubbed stderr. |
| Dropping the `s3Cluster` arm from the poll's UNION | P1 | Measured: both arms answer under the working credential, so the arm is not the 4xx. |
| Aligning the GitHub `BETTERSTACK_QUERY_*` secrets with Doppler | P1 | After this change no code on this path reads them. Deferred with a tracking issue. |
| A bespoke library convention for the poll | P4 | `tests/scripts/lib/*-gate.sh` + paired suite + `test-all.sh` registration is what this workflow already uses for four gates. |
| Re-deriving "did the read answer" | P3 | `bs_absence_response_is_answer()` (ADR-192) already buys it, and records why a content grep is the wrong implementation. |
| A standalone CI positive-control workflow | P1, P4 | The follow-through probe covers the between-dispatch window; a third surface buys nothing new. |

Mechanisms this plan *kept* and then cut on review are in `## What was cut, and why`.

### Value-Proposition Measurement (plan Phase 0.6c)

The justification is correctness, not cost, so Phase 0.6c does not gate this plan. One
candidate saving was measured and the mechanism behind it was then cut: breaking the
loop early on a non-retryable classification would return up to ten minutes per failed
dispatch, but it would not have fired on either cited run — both logs contain zero
matches for the classifier's non-retryable markers, so both grade `other`, which is
transient, which polls the full budget. A saving bounded to a class the observed
failures do not belong to is not a justification, and the mechanism was removed.

## Research Reconciliation — Spec vs. Codebase

| Claim as received | Reality on `origin/main` (2026-09-17) | Plan response |
|---|---|---|
| The two terminal branches are "collapsed today" | Two distinct branches already exist | Keep them separate; fix the predicate and the per-poll line |
| The `s3Cluster` arm may be 4xx-ing (the #7855 shape) | Both arms answer `rc=0` under the working credential | Refuted by measurement; the arm stays |
| "the birth route's ONLY in-job verification" | True — and the *replace* route has none, and it is the route that runs | Scope widened to both jobs |
| Fix step 1 is "capture stderr and print its first line" | `--fail-with-body` puts the HTTP error body on **stdout**, already captured into `$out` and silently discarded on the failure path | Both channels handled: stdout by length + classification (never echoed), stderr by a scrubbed first line |
| The GitHub secrets are the likely cause | Consistent with every measurement, not directly measurable without a dispatch | The plan does not assert it; it removes the path and makes the next divergence self-naming |

## Open Code-Review Overlap

`gh issue list --label code-review --state open --limit 200` returned 65 issues; one
body names a path this plan edits.

- **#7942** — "Two mutation batteries in `plugins/soleur/test/` are named
  `*.mutation.sh` and run in no gate" — names `scripts/test-all.sh`.
  **Disposition: acknowledge.** Different files and a different concern, but it
  constrains this plan in one direction, encoded as QG4: the new suite and the
  follow-through's test must both be registered in `scripts/test-all.sh`, so neither
  becomes the third orphan #7942 is about. The scope-out stays open.

### GDPR / compliance disposition (plan Phase 2.7)

`plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` over this plan reports `path
scan complete — 1 examined, 0 matched`: no schema, migration, auth flow, API route or
`.sql` surface is touched. The gate was run because the `single-user incident`
threshold is one of its widened triggers. It also emitted a **pre-existing**
`POSTURE_FAIL` — its detection rules were last verified 2026-05-10 and are 130 days
stale — which predates this plan, affects every plan run through the gate, and is
recorded in `## Deferred Items` rather than absorbed silently.

## Technical Approach

### Architecture

Two files carry the change; the workflow becomes a caller rather than an
implementation.

```
scripts/lib/betterstack-read-classify.sh      (new, ~12 lines)
  bs_read_classify <rc> <rowsfile>
    -> credentials-rejected | source-under-maintenance | reader-refusal | transport | other
  sourced by scripts/cutover-inngest.sh, whose _bs_read_remedy() stays put and calls it

scripts/lib/git-data-boot-signal-poll.sh         (new; the sourced read-path library)
  sources scripts/lib/betterstack-absence.sh       (ADR-192: answer shape, source control)
  sources scripts/lib/betterstack-read-classify.sh (the rc partition)

  git_data_boot_read       <outfile> <errfile> <anchor>  -> rc; stdout and stderr to separate files
  git_data_boot_answered   <rowsfile> <rc>               -> 0 iff rc=0 AND bs_absence_response_is_answer
  git_data_boot_poll       <max_polls> <interval_s> <anchor>
                                                         -> the loop: per-poll line, accounting
  git_data_boot_poll_decide <found> <final_answered>      -> received | silent | unreadable

.github/workflows/apply-web-platform-infra.yml
  git_data_host_create  : anchor stamp + poll
  git_data_host_replace : id: apply + anchor stamp + poll + Dispatch summary backstop
```

**The library lives in `scripts/lib/`, not `tests/scripts/lib/`, and that placement is
load-bearing rather than aesthetic.** The workflow sources fourteen
`tests/scripts/lib/*-gate.sh` files at dispatch time, so that directory *is* a
production location and the convention would have fit. But two blocking CI hooks are
scoped by path:
`scripts/lint-diagnosis-claims.sh` — the AP-021 diagnostic-honesty gate, which is the
principle this whole plan exists to satisfy — walks
`[".github/workflows", ".github/actions", "scripts", "apps/web-platform/infra"]` and
additionally skips any path matching `/tests?/`; and
`scripts/lint-workflow-errexit-capture.py` (AP-022) scans only `.github/workflows`.
Putting the `::error::` arms and the `rc=$?` capture under `tests/` would move them out
of both detectors' reach — and ADR-149 records that this very poll has already shipped
the errexit-capture defect once. `scripts/lib/` keeps the arms inside AP-021's scope
and sits beside its siblings `betterstack-absence.sh` and `betterstack-sources.sh`;
the file has no `tfplan.json` dependency, which is what the `*-gate.sh` convention is
actually organised around. For AP-022, the `rc=$?` capture stays in the workflow's
`run:` block so the hook still sees it, and the library takes rc as a parameter.

**The loop lives in the library.** If it stays in the `run:` block, the per-poll line
and the whole `found` / answered accounting sit outside the assembly, and the
highest-value mutation rows — feeding the match buffer from stderr, suppressing
stderr, unconditionalising the per-poll line — have no detector at all, which is the
"check that cannot fail" class this plan exists to end. `max_polls` and `interval_s`
are parameters so the hermetic suite runs in seconds rather than the ten minutes
twenty real sleeps would cost.

**The stdout/stderr split is structural, not conventional.** `git_data_boot_read`
writes stdout to `$outfile` and stderr to `$errfile`, and the match runs on `$outfile`
only when the read answered. The match buffer therefore cannot receive the script's
own error echo — the failure the existing in-file comment warns about, where
`betterstack-query.sh` echoes the failing query back, that query contains the literal
`boot_complete`, and a `2>&1` capture reports the boot signal as received on poll 1/20.
Because `--fail-with-body` puts an HTTP error's body on **stdout**, that buffer is also
never echoed on a failed read: it is read only by `wc -c` and by `bs_read_classify`'s
two fixed greps, then dropped.

**The test seam is the repo's existing one**: `BETTERSTACK_QUERY_SCRIPT`, which
`scripts/lib/betterstack-absence.sh` documents and `scripts/zot-restart-loop-alarm.sh`
already exports. The suite shims that, not `PATH`.

Two readers against `betterstack-query.sh` now exist — `_bs_query_rows()` (Mode 2:
`--since/--grep/--limit`) and `git_data_boot_read` (Mode 1: raw SQL). The split is
deliberate: the modes take disjoint argument shapes and the poll's field-isolated SQL
cannot be expressed as a `--grep`. FR7 pins single-implementation for the partition; it
does not, and should not, pin it for the reader.

### Implementation Phases

**Phase 0 — Preconditions (no code).**

- Re-run the three arm probes under `doppler run -p soleur -c prd_terraform` and
  record rc + row counts in the PR body. This is the **pre-fix control**: it
  establishes that the query shape and both arms are sound before any edit.
- Confirm `secrets.DOPPLER_TOKEN` is in scope for both poll steps and that the step
  `Install Doppler CLI` precedes both. The apply step proves it for the birth job
  only; the replace job's binding is read, not assumed.
- Confirm `scripts/lint-guard-contract.py` and
  `scripts/lint-infra-no-human-steps.py` pass on this plan file, and add
  `scripts/lint-diagnosis-claims.sh` (AP-021) and
  `scripts/lint-workflow-errexit-capture.py` (AP-022) to the battery — both are
  path-scoped, and this change moves prose and an rc capture across their boundaries.
- Read ADR-149 item 4 to confirm it is the amendment target, and ADR-192 to confirm
  the verdict vocabulary this plan composes with.
- Note PR #8252 as a rebase-order interaction on the same two files.

**Phase 1 — `bs_read_classify` (RED first).** Write the failing assertions, add
`scripts/lib/betterstack-read-classify.sh`, and have `_bs_read_remedy` call it. The
`source` line goes **after** `set -euo pipefail` in `scripts/cutover-inngest.sh`,
because `apps/web-platform/infra/cutover-inngest-workflow.test.sh` reconstructs a
single-file view from that marker onward and would otherwise drop it. The existing cutover suites are the regression gate and the function's output must
not change — but "the suites pass" is **not** a sufficient gate here, for two measured
reasons. First, `apps/web-platform/infra/cutover-inngest-workflow.test.sh` does not
call `_bs_read_remedy`; it extracts the function's **text** with
`awk '/^_bs_read_remedy\(\) \{$/,/^\}$/'` and `printf`s it into a generated
`driver.sh` that runs in a fresh `bash` with a stubbed `doppler`. After the split that
driver must inline `bs_read_classify` too, or the arm dies under `set -euo pipefail`
and the render assertion goes RED. Second, that file reconstructs a single-file view
of the script with `sed -n '/^set -euo pipefail$/,$p'`, so the `source` line must sit
**after** that first column-0 `set -euo pipefail` or roughly 120 assertions never see
it — and it must not introduce a second column-0 `set -euo pipefail`, which the
script's own header forbids.

**Phase 2 — The sourced poll library (RED first).** Write
`tests/scripts/test-git-data-boot-signal-poll.sh` first, carrying the full mutation
matrix below, driving a `betterstack-query.sh` shim resolved through
`BETTERSTACK_QUERY_SCRIPT` that answers by matching the SQL it is handed **and by
reading `BS_TABLE` / `BS_TABLE_S3` from the environment** — the env read is
load-bearing, because `betterstack-query.sh` substitutes those tokens internally, so
the SQL a shim receives is byte-identical for the pinned and the default table and a
SQL-matching stub could not otherwise see which source was selected. The suite must stub **`doppler` as well**, as a shell function in the harness, exactly
as the cutover driver does: `doppler` is not installed on a workstation or in the
hermetic environment, so shimming only `BETTERSTACK_QUERY_SCRIPT` would change the
argument of a command that never runs and every row would grade rc=127 -> `other`.
Then implement `scripts/lib/git-data-boot-signal-poll.sh` to green it, with every
function signature and closing brace at column 0. Register the suite in `scripts/test-all.sh`.

**Phase 3 — Wire the birth job.** Replace the poll step's inline body with `source` +
calls; drop the three `secrets.BETTERSTACK_QUERY_*` bindings and add
`DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}`; retarget the credentials-absent guard at
`DOPPLER_TOKEN`; delete `2>/dev/null` and route stderr to `${RUNNER_TEMP}`; branch the
per-poll line; pin `BS_TABLE` and `BS_TABLE_S3` unconditionally; add the
`Stamp boot-trail run anchor (git-data create)` step immediately before apply.

**Phase 4 — Wire the replace job (its own commit).** `id: apply`, the anchor stamp,
the `source` + call with replace-specific remediation text, the `Dispatch summary`
backstop port, and the amendment to `Post-replace readiness note`'s summary naming the
in-job boot signal as a second gate.

**Phase 5 — Follow-through enrolment.** See `## Observability` §soak.

**Phase 6 — Records.** ADR-149 amendment, the two `model.c4` edges, the runbook.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Keep GitHub secrets; sync their values from Doppler | Leaves two credential stores for one read and requires a write to repo secrets that is neither IaC-managed nor verifiable in-band. Filed as a follow-up. |
| Diagnose the 4xx status first, fix second | The status would not change the remedy; the one hypothesis it would have excluded (a mis-pinned table) is refuted directly. See `## Why one credential source`. |
| Print the raw error body | Public repo; the body names the username. |
| Drop the archive arm and poll `remote()` only | Measurement shows the arm is not the fault, so this would be a behaviour change with no property behind it, and it would break parity with the runbook's query. |
| A pre-apply read-path probe | See `## What was cut, and why it was cut`. |
| Fix the birth job only | It cannot currently fire; see `## Scope: both jobs, and why`. |
| Fail the poll open (warn, exit 0) | Explicitly rejected by the step's own comment and by ADR-149 item 4; reproduces the green-birth-over-a-dark-host state. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a git-data host adopted as verified
  while it is dark — every connected user's `git push`, `git clone` and workspace
  history operation against `soleur-git-data` fails, and the step that exists to catch
  exactly that reported green.
- **If this lands broken, the user experiences (second artifact):** the inverse — a
  healthy host reported unverified, which points a dispatch at a *replace* of the
  fleet's most irreplaceable data store on false evidence.
- **If this leaks, the user's data is exposed via:** the public Actions run log. The
  failure path prints diagnostics from a credentialed ClickHouse query whose error
  body can carry the query username. The classification/length/scrubbed-stderr design
  is the mitigation and the raw body is never printed.
- **Brand-survival threshold:** `single-user incident`

This diverges deliberately from the issue body's "no direct end-user surface;
operator-facing" line. That line is right about the change's *surface* and wrong about
its *blast radius*: the asset behind this interlock is, in the workflow's own words,
"the fleet's most irreplaceable data store — every connected user's source code and
workspace history". CPO sign-off is required at plan time; `user-impact-reviewer` runs
at review time.

## Observability

```yaml
liveness_signal:
  what:            "stage:boot_complete row from host_name=soleur-git-data in Better Stack Logs source 2734275 (table t520508_soleur_git_data_prd_logs), read by the git-data create/replace job's poll step"
  cadence:         "per git-data create or replace dispatch; 20 reads at 30 s over a 10-minute budget"
  alert_target:    "the dispatching run itself — the job exits non-zero and the ::error:: names the outcome arm; Sentry's git-data fatal-stage rule is the independent second channel"
  configured_in:   ".github/workflows/apply-web-platform-infra.yml, steps 'Poll for the git-data boot-completion signal' in jobs git_data_host_create and git_data_host_replace, sourcing scripts/lib/git-data-boot-signal-poll.sh"

error_reporting:
  destination:     "GitHub Actions run log (public) for the read path; Sentry project web-platform for the host's own boot fatals via the git-data emitter's dual-ship"
  fail_loud:       "a non-zero step exit plus one of three named ::error:: arms — received / silent / unreadable — each carrying rc, the read classification, the response body's byte length, the ok/total read counts and a scrubbed first stderr line"

failure_modes:
  - mode:          "the read path rejects the credential (ClickHouse Code: 516 / Authentication failed)"
    detection:     "bs_read_classify returns credentials-rejected on a failed read; the arm names it"
    alert_route:   "::error:: on the dispatching run naming prd_terraform as the store to verify"
  - mode:          "the source is under maintenance, or a transport fault (DNS/connect/timeout/TLS)"
    detection:     "bs_read_classify returns source-under-maintenance or transport; the verdict is unreadable if the final read is affected"
    alert_route:   "::error:: on the dispatching run, read-path remediation, explicitly NOT a host verdict"
  - mode:          "HTTP 200 carrying a mid-stream ClickHouse exception"
    detection:     "bs_absence_response_is_answer fails on the line's shape; the read does not count as answered"
    alert_route:   "::error:: on the unreadable arm, never the host one"
  - mode:          "the host booted dark (no boot_complete emitted)"
    detection:     "the final read answers and matches nothing after the run anchor -> silent"
    alert_route:   "::error:: routing to Sentry's git-data fatal stages and the partial-birth decision tree"
  - mode:          "the source's ClickHouse table does not exist (no row ever stored — ADR-192's CLUSTER_DOESNT_EXIST)"
    detection:     "bs_read_classify returns table-missing on the vendor code; rc=22 alone cannot distinguish it from an auth failure"
    alert_route:   "::error:: naming the producer rather than the reader, so the operator is not sent to rotate a working credential"
  - mode:          "the poll silently stops being exercised (the guard goes vacuous again)"
    detection:     "scripts/followthroughs/git-data-boot-poll-8178.sh asserts a post-merge dispatch's poll answered"
    alert_route:   "the follow-through sweeper's comment on #8178"

logs:
  where:           "GitHub Actions run log for the step; Better Stack Logs source 2734275 for the host's own emits; Sentry for the boot fatal stages"
  retention:       "Better Stack remote() hot window measured at ~40 minutes with the s3 archive behind it; GitHub Actions logs 90 days"

discoverability_test:
  command:         "bash tests/scripts/test-git-data-boot-signal-poll.sh"
  expected_output: "a green summary whose assertion count is at or above the suite's declared floor"
```

### Soak / follow-through enrolment (plan Phase 2.9.1)

#8178's honest close criterion is not a green suite — it is a real dispatch whose poll
answers. Dispatches are rare and operator-initiated, so the criterion is event-gated
and must not be left to memory.

**The predicate must be a RUN, not a row.** An earlier revision proposed "exits 0 when
the read path answers and a `boot_complete` row for `soleur-git-data` is present". That
is already true today: the row at `dt 2026-09-16 15:39:36` is in the source right now,
readable from the sweeper's own credentials, with no dispatch and no poll step
involved. `earliest=<merge+1d>` is a time delay, not an event gate, so #8178 would have
closed on evidence predating the fix — the false-close primitive this plan's own cited
learning names.

- Script: `scripts/followthroughs/git-data-boot-poll-8178.sh` — locates a
  `git_data_host_create` or `git_data_host_replace` job in an
  `apply-web-platform-infra.yml` run **newer than the merge commit** and asserts that
  run's poll step answered. Exit contract: **2** while no such dispatch exists or the
  run log cannot be read; **1** when such a dispatch exists and its poll did not
  answer; **0** only on a post-merge dispatch whose poll answered. Verified against
  the sweeper's own header — it "comments FAIL on exit 1, comments TRANSIENT on any
  other exit" — so exit 2 neither discharges the tracker nor reddens the sweep while
  it waits for a dispatch that may be weeks away.
- Because the predicate reads a run log rather than the warehouse, its only credential
  is the workflow token. Tracker directive on #8178:
  `<!-- soleur:followthrough script=scripts/followthroughs/git-data-boot-poll-8178.sh earliest=<merge+1d> -->`
  plus the `follow-through` label.
- **No `secrets=` wiring is required, and that is deliberate.**
  `.github/workflows/scheduled-followthrough-sweeper.yml` carries
  `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` but not `DOPPLER_TOKEN`. Adding
  `DOPPLER_TOKEN` would hand every follow-through script in that sweeper a
  `prd_terraform` read token, against that file's own argument that withholding a
  credential is what makes a rule hold by capability rather than by string comparison;
  reusing its Better Stack secrets would bind the close criterion to the credential
  store this change is moving off. The run-anchored predicate dissolves the fork.

> **Corrected at /work (2026-09-18).** Two statements above did not survive implementation.
> (1) "No `secrets=` wiring is required" is wrong as written: the sweeper runs every probe
> under `env -i` and forwards only the names its directive declares, so the workflow token
> reaches the probe only as `secrets=GH_TOKEN`. The credential is still the workflow token
> alone, and the DOPPLER_TOKEN / BETTERSTACK_QUERY_* fork stays dissolved. Precedent: the
> #7574 probe declared `secrets=GH_TOKEN` and reached its PASS by reading run logs.
> (2) "Exit 2 while … the run log cannot be read" became **exit 3**: the sweeper prints
> exit 2 as `NOT YET` for every probe, and "could not look" reported as "nothing yet" is
> exactly #8178's own defect. Both codes are TRANSIENT (neither closes nor FAILs).
> Also measured: `gh api …/jobs/<id>/logs` refuses this log (terminal escape sequences, gh
> 2.101.0), so the probe reads via `gh run view --job <id> --log`.

### Observability layer citation

Layer 7 (the CI execution surface) for the poll's own diagnostics — the step runs on a
GitHub-hosted runner and the run log is the only surface, which is precisely why
`2>/dev/null` was fatal. Layer 3 (host telemetry, Better Stack Logs source 2734275)
for the signal being read. Layer 2 (Sentry, project web-platform) for the host's boot
fatal stages, which is the independent channel the `silent` arm routes to. No arm is
reachable only by SSH (`hr-no-ssh-fallback-in-runbooks`).

## Encryption Posture

Not applicable: the plan introduces no persistent data store and no new
cross-component connection, and touches no `.tf`, migration, cloud-init or compose
file. The Better Stack ClickHouse read already exists on the `github -> betterstack`
edge and already runs over TLS through `scripts/betterstack-query.sh`'s single `curl`,
whose destination is pinned to `*.betterstackdata.com` (#7898) and which uses
`--disable --noproxy '*'` so neither a proxy nor `~/.curlrc` can re-point it. This
change moves where the credential is read from, not what is stored or how it travels.

## Guard Contract

### Guard 1 — boot-signal read and verdict

**Property.** No arm of the boot poll may report a fact about the host that was not
read: `received` comes only from a row parsed after this dispatch's run anchor, and
`silent` only from a window whose final read answered.

**Assembly.** The chokepoint is `scripts/lib/git-data-boot-signal-poll.sh` — the
read, the loop, the per-poll line and `git_data_boot_poll_decide` all live there, so
every verdict the workflow prints flows through it. There is more than one call site:
the poll step in `git_data_host_create` and the poll step in `git_data_host_replace`,
and the property quantifies over both. The suite asserts the call-site set by grepping
the workflow rather than by listing the two steps, so a third job added later is
covered by the same census, and it asserts on the workflow's own bytes:

1. each poll step contains the `source` directive for the library, and the library
   path is under `scripts/lib/` so its `::error::` arms remain inside
   `scripts/lint-diagnosis-claims.sh`'s `DIRS` and outside its `/tests?/` skip;
2. each poll step calls `git_data_boot_poll` and neither re-implements the loop nor
   invokes `betterstack-query.sh` directly;
3. neither poll step binds `secrets.BETTERSTACK_QUERY_*`;
4. inside `git_data_boot_read`, the `betterstack-query.sh` invocation's stderr goes to
   a file path — not `/dev/null`, not `&1`;
5. both jobs stamp `BOOT_TRAIL_SINCE` before their apply, both apply steps carry
   `id: apply` and both poll steps carry `id: poll`;
6. the replace job's arms do not contain a re-dispatch instruction, and do contain the
   out-of-job liveness route.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change the `silent` condition from "the final read answered" to "any read answered" | RED |
| 2 | Make `git_data_boot_poll_decide` return `received` unconditionally — neuter its own dispatch so the battery checks nothing | RED |
| 3 | Add a SECOND call site whose poll step prints a verdict without calling `git_data_boot_poll` | RED |
| 4 | Redirect the `betterstack-query.sh` invocation's stderr to `/dev/null` | RED |
| 5 | Feed the match buffer from stderr (`2>&1`) with a stub that echoes the failing query — the historical `boot_complete`-on-poll-1 failure | RED |
| 6 | Make the per-poll line print `no boot_complete row yet` unconditionally | RED |
| 7 | Return a `boot_complete` row dated BEFORE `BOOT_TRAIL_SINCE` | RED (must not be `received`) |
| 8 | Leave `BOOT_TRAIL_SINCE` empty at read time | RED (must fail closed, not fall back to an unbounded window) |
| 9 | Return HTTP 200 whose body appends a bare `Code: 241. DB::Exception:` line after the rows | RED (must be `unreadable`, never `received` or `silent`) |
| 10 | Restore `export BS_TABLE="${BS_TABLE:-…}"` so an inherited value wins | RED |
| 12 | Write the anchor predicate as a bare integer (`dt > 1758…`) instead of `fromUnixTimestamp(…)` | RED — driven against a ClickHouse-shaped comparison, not a stub that pre-filters by date |
| 13 | Return a genuine `boot_complete` whose `dt` is 60 s BEHIND the anchor | RED unless it is still `received` — the reciprocal of row 7, and the only detector the skew allowance has |
| 14 | Reorder the poll's SELECT so `dt` is not the first column | RED — `bs_absence_response_is_answer` tests the prefix `{"dt":`, so every row would grade unreadable |
| 11 | Put a re-dispatch instruction in the replace job's `unreadable` arm | RED |

**Harness rows:**

| # | Mutation to the SUITE (not the guard) | Expected |
|---|---|---|
| H1 | Replace the shimmed `betterstack-query.sh` with one that always exits 0 | RED — the suite must detect that every RED row would now pass |
| H2 | Make the suite's pass predicate `failures == 0` with no floor on assertions run | RED — a zero-assertion run must not exit 0 |
| M1 | must-PASS, non-canonical: 19 failed reads followed by an answered final read returning a row after the anchor | PASS as `received` |
| M2 | must-PASS, non-canonical: a `boot_complete` carrying `nft_metadata_drop":"no"` with all four required assertions `yes` | PASS with a `::warning::`, never a failed birth — the #7772 report-not-enforce split |

**Anchor.** This guard compares no stored value to the thing it protects, so the
merge-base/registry anchor requirement does not apply. What prevents a silent weakening
is that the workflow *sources* the library rather than inlining it, and the suite
asserts the six workflow-byte properties enumerated above; weakening the guard requires
editing a file the suite reads.

## Acceptance Criteria

### Functional Requirements

- **FR1** — The poll step in each git-data job resolves `BETTERSTACK_QUERY_*` through
  `doppler run -p soleur -c prd_terraform` and binds no `secrets.BETTERSTACK_QUERY_*`;
  its credentials-absent guard names `DOPPLER_TOKEN`. The no-binding check extracts the
  step's block by an explicit `awk` range and asserts the extraction is non-vacuous
  before counting (the idiom `apps/web-platform/infra/cutover-inngest-workflow.test.sh`
  uses: "arm extraction is non-vacuous"), because an empty range satisfies "count is
  zero" trivially. It uses `grep -c … || true`, since `grep -c` exits 1 on a zero count
  and would abort the suite on the passing case.
- **FR2** — The read writes stdout and stderr to separate files; the match runs on the
  stdout file only when the read answered. Verified by ANCHOR, not bare token
  (`cq-assert-anchor-not-bare-token`): the `betterstack-query.sh` invocation inside
  `git_data_boot_read` redirects stderr to a file path and to neither `/dev/null` nor
  `&1`. A bare "no `2>/dev/null` in the block" check would false-RED against the
  sourced classifier's own `2>/dev/null` on `head` / `grep` / `wc`.
- **FR3** — On a failed read the step prints rc, the classification token, the response
  body's byte length and a first stderr line scrubbed of quoted values and of
  `*.betterstackdata.com` hostnames. The raw body is never printed and never matched;
  it is read only by `wc -c` and by `bs_read_classify`'s two greps, then dropped.
  (The never-matched half is a regression pin: main already guards the match with an
  rc check, and this keeps that property while the code moves.)
- **FR4** — The per-poll line branches: an answered empty read reports no row yet; a
  failed read reports that the read failed and names its classification.
- **FR5** — `git_data_boot_poll_decide` returns exactly one of `received`, `silent`,
  `unreadable`, per the table in `## The terminal-branch decision`, and each arm prints
  its own remediation. The `unreadable` arm prints the ok/total read counts.
- **FR6** — A read counts as ANSWERED only when rc=0 **and**
  `bs_absence_response_is_answer()` passes; a 200 carrying a mid-stream exception is
  `unreadable`, never `silent`. The discriminator is the line's SHAPE, never a content
  grep for `DB::Exception` / `Code: <n>`.
- **FR7** — `bs_read_classify` is defined in exactly one file. Verify over the whole
  repo, not a three-directory sample, and tolerate the spacing variant:
  `git grep -lE '^bs_read_classify ?\(\) \{' -- . ':!knowledge-base'` returns exactly
  `scripts/lib/betterstack-read-classify.sh`. `scripts/cutover-inngest.sh` sources it
  after its first column-0 `set -euo pipefail` and adds no second one.
- **FR8** — Both git-data jobs stamp `BOOT_TRAIL_SINCE` immediately before their apply,
  in the idiom `web_host_create` / `web_host_replace` already use. The predicate is
  `dt > fromUnixTimestamp(<anchor - skew>)` — an explicit conversion, never a bare
  integer and never a quoted string literal. Both wrong forms fail differently and
  neither is cosmetic: `dt` is `DateTime64(6)`, so a bare epoch integer compares a
  microsecond tick count against a second count and matches every row — an inert
  anchor that a hermetic stub doing its own date filtering would still show green,
  i.e. a detector that works only where the bug cannot occur; and a quoted literal is
  parsed in the session timezone, which the epoch value is not. A row older than the
  anchor never yields `received`, and an empty anchor fails closed rather than
  widening the window.
- **FR8b** — The anchor carries an explicit clock-skew allowance (120 s) with the
  reason recorded beside it. The existing `BOOT_TRAIL_SINCE` consumer compares against
  Sentry's **server-assigned** `.dateCreated`; `dt` is the **emitter's** timestamp,
  written by a Hetzner host in the first minutes of its first boot, before chrony has
  necessarily stepped the clock. Without the allowance this trades a false-`received`
  risk for a false-`silent` risk — and `silent` routes a dispatch toward replacing the
  fleet's most irreplaceable data store. 120 s is far below the two-hour predecessor
  window the anchor exists to exclude, so the #6969 property is preserved.
- **FR9** — `BS_TABLE` and `BS_TABLE_S3` are pinned unconditionally, not defaulted, so
  an inherited value cannot re-point either arm — and the pin is **assigned from
  `scripts/lib/betterstack-sources.sh`'s `BS_GIT_DATA_TABLE` / `BS_GIT_DATA_TABLE_S3`,
  not re-spelled as literals**. That library already owns both identifiers, and it
  exists because #7855 found the same source spelled three independent ways joined
  only by prose. The poll spells them inline on main today; this change must not add a
  fourth spelling, and the follow-through script sources the same declaration.
- **FR10** — `git_data_host_replace` carries `id: apply` on its apply step, `id: poll`
  on the new poll step, the anchor stamp, and the `Dispatch summary` empty-outcome
  backstop and outcome-pair case with their `APPLY_OUTCOME` / `POLL_OUTCOME` `env:`
  bindings. Porting the backstop without `id: poll` would produce exactly the empty
  outcome the backstop exists to catch.
- **FR11** — The replace job's `silent` and `unreadable` arms contain no re-dispatch
  instruction and route to the out-of-job `git ls-remote` liveness check that
  `Post-replace readiness note` already names. Asserted on that content, not on the two
  jobs' texts merely differing.
- **FR13** — `scripts/followthroughs/git-data-boot-poll-8178.sh` asserts a post-merge
  dispatch's poll answered, exits 2 while none exists, and is registered with its test
  in `scripts/test-all.sh`.

### Non-Functional Requirements

- **NFR1** — `_bs_read_remedy`'s output and call signature are unchanged; the existing
  cutover suites pass without modification.
- **NFR2** — No credential, and no fragment of one, reaches a public run log.
- **NFR3** — The hermetic suite runs in seconds: `max_polls` and `interval_s` are
  parameters, and the workflow passes `20 30`.

### Quality Gates

- **QG1 — Pre-fix control (before any edit).** The three arm probes under
  `doppler run -p soleur -c prd_terraform` are re-run and their rc + row counts
  recorded in the PR body: UNION `rc=0` with >= 1 row, `remote()` alone `rc=0`,
  `s3Cluster` alone `rc=0`.
- **QG2 — Mutation battery, both directions.** Every row of the mutation and harness
  matrices produces its expected verdict. A row that cannot be driven RED is a finding,
  not a pass.
- **QG3 — Anti-vacuity floor.** The suite exits non-zero when it runs fewer than its
  declared minimum number of assertions, and prints the count.
- **QG4 — Registration.** `tests/scripts/test-git-data-boot-signal-poll.sh` and
  `scripts/followthroughs/git-data-boot-poll-8178.test.sh` are both registered in
  `scripts/test-all.sh` and appear in its output; a committed test nothing dispatches
  is the #7942 shape.
- **QG5 — FR coverage.** FR1's no-binding grep, FR6's rc=2 and rc=78 arms, FR7's
  single-implementation grep and FR8's anchor assertion each have a named assertion in
  the suite.
- **QG6 — NFR2 has a gate.** A fixture whose HTTP error body carries a synthetic
  username token and whose stderr carries a quoted value and a
  `*.betterstackdata.com` hostname is driven through the failure path, and the suite
  asserts none of the three appears in the step's output.
- **QG7** — `actionlint .github/workflows/apply-web-platform-infra.yml` clean, and
  every extracted `run:` snippet parses under `bash -c`. Never `bash -n` on the
  workflow file.
- **QG8** — `python3 scripts/lint-guard-contract.py` and
  `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` both
  pass, the second run with the gate's OWN invocation over the changed set.
- **QG9** — `bash plugins/soleur/test/c4-count-parity.test.sh` green after the
  `model.c4` edits, and the C4 render/syntax suites pass.
- **QG10** — Every `knowledge-base/` path cited in this plan resolves:
  `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | grep -v '^knowledge-base/project/specs/feat-one-shot-8178-boot-signal-poll/' | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN: {}'`
  **and the gate exits non-zero when it does not** — the bare pipeline always exits 0,
  so as written it would be an eyeball check rather than a gate. The carve-out is this
  feature's own pipeline-written artifacts (`tasks.md`, `session-state.md`), which do
  not exist when the plan is written.
- **QG11 — Post-merge, event-gated.** The next `git_data_host_create` or
  `git_data_host_replace` dispatch shows a poll step reaching an answered read.
  Tracked by the follow-through directive; #8178 closes on that evidence, not on the
  suite.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given a shimmed reader returning rc=22 with a body matching none of the classifier's
  markers — the MEASURED shape of runs 34822248580 and 34836141887 — when the poll
  runs, then it polls the full budget, the outcome is `unreadable`, the log names the
  `other` classification and prints the ok/total counts. This is the arm #8178 is
  about and it is asserted directly.
- Given a shimmed reader returning rc=22 with a `Code: 516 … Authentication failed`
  body, when the poll runs, then the outcome is `unreadable`, the log names
  `credentials-rejected` and the body's byte length, and contains no substring of the
  body.
- Given a shimmed reader returning an answered empty read for all 20 reads, when the
  poll runs, then the outcome is `silent` and the log routes to Sentry's fatal stages,
  never to the credential remediation.
- Given 19 failed reads followed by an answered final read returning a row after the
  anchor, when the poll runs, then the outcome is `received`.
- Given 19 answered empty reads followed by a failed final read, when the poll runs,
  then the outcome is `unreadable` and the log prints `19/20` answered.
- Given a shimmed reader whose stderr echoes the failing query (containing the literal
  `boot_complete`) with empty stdout and rc=22, when the poll runs, then the outcome is
  NOT `received`.
- Given an HTTP 200 whose body appends a bare `Code: 241. DB::Exception:` line, when
  the poll runs, then the read does not count as answered.
- Given a `boot_complete` row dated before `BOOT_TRAIL_SINCE`, when the poll runs, then
  the outcome is not `received`.
- Given an empty `BOOT_TRAIL_SINCE`, when the poll runs, then it fails closed.
- Given a shimmed reader returning rc=22 with a `CLUSTER_DOESNT_EXIST` body, when the
  poll runs, then the classification is `table-missing` and the arm names the producer,
  not the credential.
- Given a shimmed reader returning rc=3, then the classification is
  `credentials-absent`; given rc=1, `reader-exit-1`, naming `DOPPLER_TOKEN`.
- Given a body carrying BOTH an auth marker and `maintenance`, the classification is
  `source-under-maintenance` — the precedence `_bs_read_remedy` has today.

### Regression Tests

- Given a `boot_complete` row with `luks_mounted":"no"`, the step fails with the
  invariant-unmet error, exactly as today.
- Given a `boot_complete` row lacking `nft_metadata_drop`, a `::warning::` is printed
  and the birth stands — the #7772 report-not-enforce split is preserved.
- Given the existing cutover suites, after `_bs_read_remedy` calls `bs_read_classify`,
  they pass unchanged.

### Edge Cases

- `BS_TABLE` or `BS_TABLE_S3` set to another value in the environment: the pin wins.
  An explicit `BS_TABLE_S3` otherwise always wins inside `betterstack-query.sh`, which
  would re-point the `s3Cluster` arm while `remote()` stayed correct — a half-correct
  UNION.
- A reader usage error (rc=64) or destination refusal (rc=2): classified as
  `reader-refusal`; the verdict is `unreadable`.
- `doppler run` itself failing (rc=1): classified by the rc=1 arm, which names
  `DOPPLER_TOKEN`, not the Better Stack credentials.

### Integration Verification

- **Live read (credentialed, read-only):**
  `BS_TABLE=t520508_soleur_git_data_prd_logs doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh "<the poll's SQL>"`
  expects rc 0 and at least one `"stage":"boot_complete"` row.
- **Hermetic:** `bash tests/scripts/test-git-data-boot-signal-poll.sh`.
- **Cleanup:** none — every probe is read-only.

## Files to Create

- `scripts/lib/betterstack-read-classify.sh`
- `scripts/lib/git-data-boot-signal-poll.sh`
- `tests/scripts/test-git-data-boot-signal-poll.sh`
- `scripts/followthroughs/git-data-boot-poll-8178.sh`
- `scripts/followthroughs/git-data-boot-poll-8178.test.sh`

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml`
- `scripts/cutover-inngest.sh`
- `scripts/test-all.sh`
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh` (only if its single-file
  reconstruction needs an assertion for the new `source` line)
- `knowledge-base/engineering/architecture/decisions/ADR-149-git-data-host-birth-route-and-readiness-interlock.md`
- `knowledge-base/engineering/architecture/decisions/ADR-192-an-empty-warehouse-read-is-three-states-not-one.md`
- `knowledge-base/engineering/architecture/principles-register.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/operations/runbooks/git-data-birth.md`
- `knowledge-base/project/plans/2026-09-17-fix-git-data-boot-signal-poll-plan.md`
- `knowledge-base/project/specs/feat-one-shot-8178-boot-signal-poll/tasks.md`

Pipeline-written files that will also appear in the diff and must be named by any
diff-scope acceptance criterion: `knowledge-base/INDEX.md`,
`knowledge-base/kb-tags.txt`,
`knowledge-base/project/specs/feat-one-shot-8178-boot-signal-poll/session-state.md`.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO verdict **PROCEED with four blocking amendments**, all folded in:

1. *The scope widening is correct but is two changes, not one.* In the birth job the
   poll is a repair; in the replace job it is a new gate on a destructive path, and the
   replace path lacks the birth gate's mechanical backstop against a panic re-dispatch.
   Folded as FR11 and a dedicated commit.
2. *A pre-apply probe is right for create and an availability inversion for replace.*
   Subsequent review showed the probe refuses only on classes that have never been
   observed, and warns-and-proceeds on the class that has — so it was cut entirely
   rather than split. See `## What was cut, and why it was cut`.
3. *"Verbatim extraction" was the wrong framing.* `_bs_read_remedy` only prints, its
   `body_class` is function-local, and its arms hard-prefix the cutover's `2.0` label.
   Folded as the classify-only extraction, with the printer left in place.
4. *The query window is not anchored to the dispatch.* `host_name` pins the host, not
   the host generation, so a replace re-dispatched within two hours of a prior boot
   would match the destroyed host's row. Folded as FR8.

CTO confirmed no capability gaps and no new ADR ordinal, and recommended the
anchored-window rule join the ADR-149 amendment because it generalizes past git-data.

**Agents invoked:** `soleur:engineering:cto`, `spec-flow-analyzer`, a scoped
strong-model advisor consult, and the `plan-review` engineering panel
(`code-simplicity-reviewer`, `architecture-strategist`, `dhh-rails-reviewer`,
`kieran-rails-reviewer`).
**Skipped specialists:** none.

### SpecFlow audit (plan Phase 3 — run inline)

`spec-flow-analyzer` walked the operator/CI journey and returned six P0s. The ones that
changed the design:

- The replace job's apply step carries **no `id:`**, so a copied poll gate resolves to
  the empty string and the poll would be permanently skipped on the only route that
  fires; its `Dispatch summary` also lacks the birth job's backstop. (FR10.)
- The follow-through's proposed predicate was **already satisfiable today** by the
  `dt 2026-09-16 15:39:36` row, so #8178 could have closed on evidence predating the
  fix. Rewritten to be run-anchored. (FR13.)
- The 20-iteration loop sat outside the library, leaving three mutation rows with no
  detector and making the hermetic suite 40+ minutes. Moved in, with injectable bounds.
- **The measured production failure classifies as `other`**, i.e. transient — an arm
  that had no Test Scenario, in a plan about that exact failure. Scenario added, and
  the mechanism whose saving depended on the other class was cut.

### Plan-review panel (engineering, escalated for the `single-user incident` threshold)

Four reviewers ran against the plan; every finding below was applied, not deferred.
`spec-flow-analyzer` had already run inline at Phase 3 with a targeted prompt, so it
was not re-spawned as part of the panel.

- **`code-simplicity-reviewer` and `dhh-rails-reviewer` converged independently on
  over-growth**, and one finding was decisive: the pre-apply probe refused only on
  `credentials-rejected` and reader refusals, while both cited runs grade `other` —
  i.e. on the exact 40/40 failure the plan exists to fix, the probe would have warned
  and proceeded, after adding a vendor read dependency to the recovery path for the
  fleet's most irreplaceable data store. DHH additionally showed the escape hatch's
  admissible set was **empty**: the probe's only refusals were the two classes the
  override itself refused. Both were cut, with `mixed`, the early break, the
  `_bs_read_remedy` move, and a pre-merge diagnostic step. See `## What was cut`.
- **`architecture-strategist`** found two blocking layering defects: the poll library
  under `tests/` would have escaped `scripts/lint-diagnosis-claims.sh` (the blocking
  AP-021 hook, whose `DIRS` excludes it twice over) and `lint-workflow-errexit-capture.py`
  (AP-022, workflows-only) — moving the very prose and rc-capture those hooks exist to
  police out of their reach, in a plan about diagnostic honesty. It also showed the
  control read inverts on a dedicated single-producer source, and supplied the
  `CLUSTER_DOESNT_EXIST` rival hypothesis that this session then tested and refuted.
- **`kieran-rails-reviewer`** found the run anchor was a type mismatch (`dt` is
  `DateTime64(6)`; a bare epoch integer matches every row and would still pass a
  hermetic stub), that the classifier's token set omitted rc=3 and rc=1, that the
  cutover suite inlines the function's *text* into a fresh shell rather than calling
  it, that the hermetic suite must stub `doppler` and not only the query script, and
  that the replace job needs `id: poll` as well as `id: apply`. It also verified a long
  list of the plan's factual claims as true.

### Product/UX Gate

Not applicable. The mechanical UI-surface scan over `## Files to Create` and
`## Files to Edit` matches no UI-surface path. Tier: NONE.

## Architecture Decision (ADR/C4)

This plan extends an existing decision rather than making a new one, so it amends
ADR-149 and claims no new ordinal.

### ADR

Amend `ADR-149-git-data-host-birth-route-and-readiness-interlock.md`:

Land it as a dated **`### Addendum — #8178 (2026-09-17)`**, not an in-place rewrite of
item 4. That is ADR-149's own convention — it already carries `### Addendum — #8189
(2026-09-15)`, `### Disposition — #6982 (2026-07-27)` and a clarification of item 4 —
and ADR-192 states the reason directly: editing a dated record to match a later
understanding destroys the evidence. The addendum records the credential source
(Doppler `prd_terraform`, not repository secrets), the three-way outcome partition
composed with ADR-192's states, the rival `CLUSTER_DOESNT_EXIST` hypothesis and the
measurement that refuted it, and — explicitly — that the GitHub-secret path was never
measured, so the record does not imply a cause the change did not establish.

The **anchored-window rule** does not belong here. The CTO's own reason for adding it
(it generalizes to every `boot_complete`-style poll) is the argument against putting it
in an ADR whose title scopes it to the git-data birth route. Its home is the principles
register (`knowledge-base/engineering/architecture/principles-register.md`), where
AP-021/AP-022/AP-023 already hold exactly this class of cross-cutting, repeatedly
relearned invariant: *a verdict scoped by `host_name` is scoped to the host, not the
host generation; a read that may see a same-named predecessor requires a run anchor.*
The pattern's existing implementation is `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`
(#6969). ADR-149's addendum cites the register row rather than restating it.

`## Alternatives Considered` in the addendum: "keep the GitHub repository secrets and
reconcile their values", "drop the archive arm from the poll's UNION", "refuse a
dispatch pre-apply when the read path cannot answer", and "add a control read to
separate a dark host from a dark warehouse" — each with the measurement that rejected
it.

**ADR-192 needs an addendum of its own, and this change is what falsifies it.** Its
`### Consequence: the round trip creates a permanent table` says the git-data source
"has never stored one" and that the first round trip "has not yet occurred". The table
now holds 31 rows dated before 2026-09-15, oldest `dt 2026-09-04 15:15:56`. Two
consumers depend on that text — `scripts/followthroughs/git-data-rung2-evidence-capture.sh`'s
documented observable states, and the capture's `CLUSTER_DOESNT_EXIST` -> zero-rows
transition — so the clause is retired by addendum rather than left to mislead.

### C4 views

All three of `model.c4`, `views.c4` and `spec.c4` were read. Two edge descriptions are
falsified by this change and are corrected in the same PR; no element is missing and no
new `view … include` line is required.

- `gitDataStore -> betterstack` closes with "TARGET state — wired at merge, unobserved
  until the birth dispatch". Measurement has overtaken it: the dispatch happened twice
  and the poll never read a row. Replaced with the measured state and the credential
  source.
- `github -> betterstack` enumerates the Logs sources CI polls and does not name
  git-data's source 2734275, which the birth poll has read since #6982. A clause is
  added.

External actors, external systems, containers and access relationships enumerated and
found already modelled: the `betterstack` system, the `github` actor, the
`gitDataStore` container, the Hetzner host system, and both relationships above. No
human actor changes. Because `model.c4` embeds derived cardinalities that
`plugins/soleur/test/c4-count-parity.test.sh` gates as required context, that suite is
QG9 — the edits add prose only and must not move a count.

### Sequencing

The ADR amendment and the C4 edits land in this PR. The event-gated proof (QG11) is
carried by the follow-through directive, not by a status flip.

## Success Metrics

- The next git-data dispatch's poll step reaches an answered read (the close
  criterion).
- Time from a failed read to a named cause: one `gh run view`, down from two dispatches
  and a manual investigation.

## Dependencies & Prerequisites

- Doppler `soleur/prd_terraform` holds `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}`
  (verified by name, value-silent, 2026-09-17).
- `Install Doppler CLI` precedes both poll steps, and `secrets.DOPPLER_TOKEN` must be
  bound on each — the apply step proves it for the birth job only.
- PR #8252 is open against the same two files in disjoint regions. Rebase order is the
  only interaction.

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| The replace job's new poll turns a job that has gone green twice into one that can go RED | That is the point, and the cited learning about arming a silently-gating check is the warning. Mitigated by FR11's replace-specific remediation, which never points at re-dispatch, and by giving the replace wiring its own commit. |
| The poll matches a previous host generation's `boot_complete` | FR8's run anchor, with mutation rows 7 and 8 as its battery. |
| The GitHub-secret 4xx status is never measured, so the swap could mask a different cause | The one hypothesis a status would exclude — a mis-pinned table — is refuted by measurement; every surviving hypothesis is credential-side with the same fix, and FR3 makes the next divergence self-naming. |
| Production read-path code lives under `tests/scripts/lib/` | Consistent with four existing sourced gates in this workflow, so this plan follows the convention rather than forking it — but the convention means a dispatch-time dependency sits under `tests/`. Noted, not solved here. |
| Touching `scripts/cutover-inngest.sh`, a safety-critical operator script | The change is one `source` line and one substituted partition; its output, name and arity are unchanged and NFR1 pins the existing suites as the regression gate. |
| Merge conflict with PR #8252 | Disjoint regions; rebase and re-run the full battery. |

## Deferred Items (tracking issues to file)

1. `gdpr-gate`'s detection rules are 130 days stale (last verified 2026-05-10), so its
   `POSTURE_FAIL` fires on every plan that invokes it. Pre-existing and repo-wide,
   surfaced by this plan's Phase 2.7 run rather than caused by it. Filing: refresh the
   corpus per that skill's "Corpus freshness" section.
2. The **seven** remaining `secrets.BETTERSTACK_QUERY_*` binders —
   `registry-host-replace-dispatch.yml`, `registry-zot-inventory.yml`,
   `reusable-release.yml`, `scheduled-followthrough-sweeper.yml`,
   `scheduled-inngest-health.yml`, `scheduled-zot-restart-loop.yml`, and the inngest
   dark-host read inside `apply-web-platform-infra.yml` itself — read only the shared
   source and are green today. Note the consequence for the file this plan edits:
   after this lands, `apply-web-platform-infra.yml` holds **both** credential paths,
   so the controlled comparison this plan relied on no longer exists in-repo for the
   next reader. The tracking issue is scoped accordingly — a divergence between the
   two stores is a live class across seven workflows, not a tidy-up.
   Filing: migrate them to the single Doppler source, or place the three repository
   secrets under Terraform. Re-evaluation trigger: the next time a read against a
   non-default Better Stack source is added to CI.

**Noted at /work, not filed (2026-09-18).** `actionlint` (docker `rhysd/actionlint:latest`,
bundled shellcheck) reports four `SC1083` warnings in `apply-web-platform-infra.yml`, all in
one `run:` body of the `inngest_volume_recut` job: literal `{`/`}` inside the escaped operator
recipe in its Guard-2 `::error::` string. The findings are byte-identical on `origin/main`, so
this branch adds none. Not filed: they are warnings inside a deliberately literal message, with
no user-visible consequence, so the `wg-defer-only-after-inline-triage` test fails. This line is
the durable record.

## Documentation Plan

- ADR-149 amendment and the two `model.c4` edge corrections (above).
- `knowledge-base/engineering/operations/runbooks/git-data-birth.md`: the readiness
  table row asserting "The Better Stack query credentials are present" becomes a
  statement about the Doppler-sourced read; the `## After the birth` section notes that
  the in-job poll now uses the same query it prescribes, so the two can no longer
  disagree; the partial-birth decision tree gains the replace arm.
- `git_data_host_replace`'s `Post-replace readiness note` asserts "the AUTHORITATIVE
  post-replace liveness gate is NOT in this job". Phase 4 makes that false, so its
  summary text is amended in the same commit. Its other claim — that Better Stack
  cannot *pull* this host — stays true and is left alone.
- A learning file capturing the class: an instrument whose only failure channel was
  `2>/dev/null`, a verdict predicate that reset on success, and a plan that had to be
  cut back twice before it was the size of its defect.

## Deepen-Plan Pass (2026-09-17)

### Precedent diff (gate 4.4)

The plan prescribes a pattern-bound behaviour — a sourced shell library under
`scripts/lib/` consumed by a workflow — so the precedent was grepped rather than
assumed.

| Prescribed shape | Precedent on `main` | Plan response |
|---|---|---|
| A library computing its own directory | `scripts/lib/betterstack-absence.sh` uses `_bs_absence_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` | Adopt verbatim rather than resolving by CWD — `cutover-inngest.sh` runs under `set -euo pipefail` from the repo root and a CWD-relative resolve is the fragile form |
| How a consumer sources it | `# shellcheck source=scripts/lib/<name>.sh` directive plus an absolute base (`"${REPO_ROOT}/scripts/lib/…"` in followthroughs, `"${GITHUB_WORKSPACE}/…"` in the workflow) | Adopt both; the shellcheck directive is what keeps the sourced symbols analysable |
| A source identity (table / source id / ingest URL) | **`scripts/lib/betterstack-sources.sh` already declares `BS_GIT_DATA_SOURCE_ID="2734275"`, `BS_GIT_DATA_TABLE`, `BS_GIT_DATA_TABLE_S3`** | **Finding — folded into FR9.** The plan's original FR9 would have re-spelled both identifiers as literals. That library exists precisely because #7855 found one source spelled three independent ways joined only by prose; this change would have made it four. FR9 now assigns from the declaration. |
| The three-state read verdict | `scripts/lib/betterstack-absence.sh` (ADR-192) | Consumed, not re-derived; see `## The terminal-branch decision` |
| A classifier for a failed read | `_bs_read_remedy()` in `scripts/cutover-inngest.sh` | Partition extracted as `bs_read_classify`; the printer stays put |

The plan prescribes no SQL `SECURITY DEFINER`/`INVOKER`, no atomic-write sequence, no
lock or circuit-breaker shape, and no new scheduled job, so the remaining precedent
classes in gate 4.4 do not apply.

### Gate dispositions

| Gate | Result |
|---|---|
| 4.5 Network-outage deep-dive | **Skip.** No trigger pattern in `## Overview` or `## Problem Statement` (measured: 0 matches). The transport faults this plan classifies (DNS/connect/timeout/TLS at rc 6/7/28/35) are named in the classifier, not diagnosed as the defect, and the change drives no `terraform apply` against a resource carrying a `connection`/`provisioner` block. |
| 4.55 Downtime & cutover | **Skip, evaluated not assumed.** The change adds a read and a stamp to two dispatch jobs; it introduces no reboot/replace class, no lock-taking DDL and no router change. It does make `git_data_host_replace` able to go RED, which is a *verification* change rather than an availability one, and `## Risk Analysis` prices it. |
| 4.6 User-Brand Impact | **Pass.** Section present, 18 non-empty lines, threshold `single-user incident`, both artifacts and the exposure vector named concretely. |
| 4.7 Observability | **Pass.** All five fields present with non-placeholder values; `discoverability_test.command` starts with `bash` (allowlisted) and carries no `ssh`. |
| 4.8 PAT-shaped variable | **Pass.** Zero matches for any PAT-shaped variable, `TF_VAR_*` form or literal token shape. |
| 4.9 UI wireframe | **Skip.** No UI-surface path in `## Files to Create` / `## Files to Edit` (measured: 0 matches). |
| 4.10 Encryption posture | **Skip, trigger evaluated.** No `.tf`, `supabase/migrations/*.sql`, `cloud-init*.yml` or `docker-compose*.yml` in either Files list, and the change introduces no persistent store and no new cross-component connection — it changes which credential store feeds an existing TLS-pinned read. The section records that evaluation rather than asserting a posture it does not have. |
| 4.11 Guard Contract | **Pass.** `scripts/lint-guard-contract.py` green (1 guard entry). Adequacy read: the Assembly names the chokepoint (the library) and specifies that the suite derives the call-site set *by grepping the workflow* rather than by listing the two steps, so a third job added later is covered by the same census — structural, not a member snapshot. |

### Citation sweep

Every citation was resolved live in this pass rather than carried from memory.

- **Rule IDs** — `cq-assert-anchor-not-bare-token` and `hr-no-ssh-fallback-in-runbooks`
  both resolve to active `[id: …]` entries in `AGENTS.md`. No retired or fabricated ID.
- **ADRs** — ADR-149, ADR-192 and ADR-128 all exist under
  `knowledge-base/engineering/architecture/decisions/`.
- **Issues and PRs** — #8178, #8010, #6982, #7772, #7855, #7674, #7942, #8252, #6969
  and #7898 all resolve, and each title matches the role the plan gives it. #7674 is
  cited for the `unreadable`-vs-`silent` split, which `flush_latch_decide()`'s own
  comment attributes to that number.
- **Grep-shaped acceptance criteria** — FR7 scopes with `':!knowledge-base'`, FR1
  extracts the step block by an explicit `awk` range with a non-vacuity assertion, and
  QG10 carves out this feature's own pipeline-written spec artifacts. No AC greps a
  scope that would match the plan's own prose.
- **Every `knowledge-base/` path cited in this plan resolves on disk** (checked; only
  this feature's not-yet-written `tasks.md` / `session-state.md` are excluded, and
  `tasks.md` now exists).

## References & Research

- Issue #8178; Ref #8010, #6982 (the poll's origin), #7772 (git-data's own Logs
  source), #7855 (the 202-but-stores-nothing precedent), #7674 (the
  `unreadable`-vs-`silent` ruling), #7942 (the orphan-suite scope-out), PR #8252
  (open, disjoint regions).
- ADR-149 (the birth route and readiness interlock), ADR-192 (an empty warehouse read
  is three states, not one).
- Commit dde55bcf2 — the post-birth sweep that gated the poll on the apply outcome.
- Runs 34822248580, 34836141887 (the two RED dispatches); 34861860722, 35116580943
  (the two green `git_data_host_replace` dispatches).
