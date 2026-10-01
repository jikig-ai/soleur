# Decision Challenges — feat-one-shot-7909-7910-ccla-instrument-file-icla-watch

Persisted at plan time (headless pipeline). `ship` Phase 6 renders these into the PR body and
files the `action-required` issue.

---

## DC-1 — CLO finding P4: call the TypeScript authority, or re-derive the notice epoch in bash?

**Class:** user-challenge (a binding domain-leader instruction the plan does not follow literally)
**Raised by:** `soleur:legal:clo`, plan Phase 2.5 domain review, 2026-09-07
**Surface:** `scripts/followthroughs/ccla-representative-icla-7922.sh`

**The instruction.** CLO P4 directs that the probe call the exported
`resolveCoverageMapNoticeEpoch()` in `apps/web-platform/scripts/cla-evidence/roster-entry-gate.ts`
through `tsx`, rather than re-deriving the epoch in shell — on the B2-b ground that *"a second
copy is the drift the shared implementation exists to prevent"*, which is one of the two findings
the CLO blocked PR #7828 on twice. It adds that an unavailable `tsx` is a TRANSIENT, not a licence
to reimplement.

**Why the plan does not follow it literally.** Measured:
`.github/workflows/scheduled-followthrough-sweeper.yml` runs no `npm ci` and no `setup-node`, so
`apps/web-platform/node_modules/.bin/tsx` is absent on the only runner that ever executes the
probe. Applied literally the probe exits 3 on every sweep forever, which leaves #7910 unsolved and
returns the operator to checking by hand — a worse compliance outcome than the drift risk P4
guards against. Provisioning Node in the sweeper was weighed and rejected: a daily dependency
install into a job that holds many repository secrets, for one probe among roughly seventy.

**What the plan does instead, and how it changed under review.** The first draft offered a
merge-blocking byte-equality arm comparing the probe's `--print-epoch` to the TS authority
**against the live repository**. Plan review measured that offer and falsified it twice:

1. The live repo returns **exactly one** anchor match, so `--first-parent` is a no-op and
   `head -1 == tail -1`. The arm would have passed with `--first-parent` dropped, with
   oldest-vs-newest inverted, with `-S`→`-G`, and with the `--` pathspec separator dropped — four
   of the six drift vectors it was introduced to catch, and every one of them lowers the epoch,
   which is the direction that admits pre-notice signers.
2. `.github/workflows/ci.yml:743-749` checks out the `test-webplat` shard **shallow**, so on the
   very shard the arm was assigned to, `--print-epoch` would refuse and the TS authority would
   return the graft commit's date. The arm could never be green there, and the only ways to make
   it green would have both implementations agreeing on a wrong value.

The repo's own suite had already stated the first problem in prose and solved it:
`apps/web-platform/test/cla-evidence/roster-entry-gate.test.ts:288-295` names it *"a 1-of-1
quantification"* and builds a throwaway two-touch repository, and every other epoch assertion in
that file passes a synthetic `repoRoot` (`:336`, `:407`, `:440`, `:456`).

**The discharge now offered** is a differential over a **family of synthetic fixtures** —
one-touch, two-touch, merge-commit, rebase-replay, squash, grafted — asserting byte-equality
between the probe and `resolveCoverageMapNoticeEpoch(<fixture>)` **per fixture**. It is hermetic,
shard-independent, and non-vacuous by construction. Two corrections deepen-plan then made to that
claim: the `--` pathspec vector was covered by **no** fixture (measured — without `--`, git resolves
the argument as a path unless a ref shares the name, so one `git branch docs/legal/individual-cla.md`
in one fixture is required), and `-S`→`-G` is **uncoverable in principle** and has been struck from
the vector list. Each fixture asserts the property that makes it a *discriminator* — not merely that
it was built — because "match count, merge presence" passes on a fixture that no longer separates
the two implementations, which is the silent degradation this replacement exists to avoid. The
grafted fixture is **not** in the parity subset: the TS authority has no control B and returns a
value where the probe refuses, so byte-equality against a refusal is undefined.

**What is asked of the CLO at review.** Confirm that a merge-blocking per-fixture byte-equality
assertion against the authority is an acceptable discharge of B2-b, or name the alternative. Until
confirmed, the probe's epoch derivation is provisional.

**If the answer is no,** the fallback is a pinned `setup-node` + `npm exec tsx` step in the
sweeper, calling the exported function directly and accepting the supply-chain cost. The probe's
control, its exit contract and its output shape are unaffected either way.

---

## DC-2 — the login-free redesign of the watch

**Class:** user-challenge (it changes a property the CLO authored, and it trades away precision)
**Raised by:** convergent findings from `dhh-rails-reviewer` and `code-simplicity-reviewer`,
implied by `soleur:legal:clo` finding P1

**What changed.** The first draft watched a **named GitHub login**, held in a
`CCLA_WATCH_LOGIN` Actions secret, and reported on it. The plan now watches a **count**: *is there
any ICLA signature dated at or after the notice epoch that no live roster row covers?* Measured
against live data today it returns 0, and becomes ≥ 1 the moment the designated representative
signs.

**Why.** CLO P1 blocks publishing the employer↔account association before the account has signed
and before it has been told anything — the Art. 14-with-no-address interval. The login-keyed
design satisfied that only by *holding the login carefully*; the count form satisfies it **by
construction**, because the probe reads no name and resolves no account. It also removed a leak
path nobody had enumerated: `gh api /users/<login>` prints the request URL — containing the login
— to stderr on failure, which `sweep-followthroughs.sh:378` captures and `:505` publishes verbatim
into a public, permanent comment. And it deleted the secret, the workflow `env:` line, the
operator's `gh secret set` step, login-grammar validation, the never-print control,
`secrets=GH_TOKEN`, the `gh` stub, two verdict states and two mutation rows.

**The honest cost, and how deepen-plan repriced it.** An unrelated contributor who signs the ICLA
post-epoch also satisfies the predicate. This challenge originally priced that as "the operator
reads one comment and reopens". Measurement showed the price is far higher — the condition never
clears, so the reopened tracker is re-closed on every sweep — and **DC-4 supersedes this paragraph**:
the probe no longer takes exit 0 at all. No roster row is written by the probe either way; that
remains a separate command gated by `ccla-add.sh` Guard 3 and by the CI half, and the report text
states that the executed instrument's §4(c) designation list, not the probe, is the authority for
which account to record.

A second exposure deepen-plan surfaced and closed: the count form removed *direct* naming but left
naming **derivable** — a dated public transition next to an organisation's name joins against the
public, git-versioned ledger to recover the account that flipped it, and a PASS fired by an
unrelated signer would have publicly and permanently correlated an arbitrary contributor with a
counterparty. The tracker therefore names no counterparty, no person, and does not reference #7846.

**What is asked of the CLO at review.** P9 (*no surface publishes an association between a named
account and a corporate designation*) is the CLO's own property. Confirm that the count form,
which satisfies it by construction at the cost of the auto-close imprecision above, is preferred
to a login held carefully.

---

## DC-3 — one pull request, or two

**Class:** user-challenge (the operator's stated direction)
**Raised by:** `soleur:engineering:cto`, restated by `dhh-rails-reviewer` and
`code-simplicity-reviewer`

Three reviewers recommend splitting: `--instrument-file` (#7909) is settled, small, and could
merge immediately, while the watch (#7910) carries an open legal question (DC-1) and the larger
share of the review findings. The two halves share no file — `apps/cla-evidence/**` and its suite
on one side, `scripts/followthroughs/**` plus the sweeper workflow on the other.

The operator asked for both together, with both issues closed in the PR body. Operator direction
is the default and has not been overridden. The branch is deliberately structured so the split
remains available without rework if the watch stalls at review.

---

## DC-4 — the probe reports and never closes

**Class:** user-challenge (it departs from the exit-code contract #7910 specifies)
**Raised by:** `soleur:engineering:review:data-integrity-guardian`, deepen-plan, 2026-09-07

Issue #7910 specifies `0 PASS (ready to record) / 1 unused / 2 TRANSIENT`. The plan now refuses exit 0
entirely: the probe reports a count on exit 2 and never takes the sweeper's close verb.

**Why.** The notice epoch is today, and this repository requires contributors to sign the ICLA, so
every future signature by anyone is post-epoch by construction. Under the count form the first
unrelated contributor to sign satisfies "a post-epoch signature no roster row covers" — and the
condition never clears, because that person is not a corporate representative and never will be.
Exit 0 would post PASS and close; `closed_precheck` then refuses to re-litigate an issue carrying
the sweeper's own PASS block; a reopened tracker is re-closed on the next sweep. The cost priced in
DC-2 as "the operator reads one comment and reopens" is therefore a daily manual loop for the whole
remaining wait, and it reaches the same terminal outcome the plan's User-Brand Impact section names
— the Corporate CLA is never recorded — by the opposite route from the one that section enumerates.
A second latch exists independently: a representative withdrawn under `remove` and never re-added
is post-epoch and permanently not-live. That one is removed by narrowing "covered" to
live-or-withdrawn; the unrelated-signer latch is removed only by refusing the close verb.

**What is preserved.** #7910's actual ask is that the operator is told without having to look. A
daily comment delivers that. Auto-closing is a bonus the probe has not earned — its own PASS text
already says it is not authority to record, and closing is the irreversible verb on a legal
tracker. The operator closes it when they record the row, which is the human decision point the
design already insists on.

**What is asked at review.** Confirm that report-only is preferred to an auto-close that measurement
shows will latch on the first unrelated signature. The alternative — reintroducing account precision
so the close is trustworthy — is foreclosed by P9 and the CLO's finding P1.

---

## DC-5 — a THIRD exit code (5 = ACTION), added at /work

**Class:** taste (user-legible) — it changes what the operator sees daily
**Raised by:** implementation, 2026-09-07
**Surface:** `scripts/followthroughs/ccla-representative-icla-7922.sh`

The plan's exit table and its own exit-contract block CONTRADICTED each other: the
block refused exit 0 as the sweeper's close verb, and the table three paragraphs
later still mapped `count >= 1` to `0`. Resolving it in favour of the block left
NOT YET and ACTION sharing exit 2.

That is not survivable. `sweep-followthroughs.sh` renders `TRANSIENT (exit $rc, …)`
in the comment HEADING and folds the body behind a `<details>`. With one code the
tracker would carry a byte-identical heading every day for months — including on
the day the count moved — and the operator would have to expand a fold they had
already learned to ignore. That is the same silent-never-notice the whole issue
exists to remove, reached by a different route.

**Decision:** 2 = NOT YET, 5 = ACTION, 3 = CANNOT ESTABLISH. The sweeper treats
every code other than 0 and 1 as TRANSIENT, so 5 is inert to the substrate and
legible to the operator. The plan's table has been corrected rather than quietly
followed.

**If the operator disagrees:** collapsing 5 into 2 is a one-line change in the
probe and two arms in its suite. The cost is that the daily comment stops
distinguishing "still waiting" from "go and look".

---

## DC-6 — three deferrals, and one that was NOT deferred

**Class:** mechanical (scope), recorded because the boundary is arguable
**Raised by:** implementation, 2026-09-07

Filed rather than fixed here:

- **#7923** — sweeper comment de-duplication, a per-probe timeout, and the
  ungated `gh issue edit --add-label` enrolment path. Substrate shared by all 80
  probes; the timeout in particular changes execution semantics for every one of
  them and needs its own runtime measurement first.
- **#7924** — `repo-write-boundary` does not sample `.git/shallow`. Changing what
  a guard used by every suite samples needs a sweep of current offenders first
  (`ccla-add.sh` is one, and its `--depth=1` is load-bearing there).
- **#7925** — the roster has no correction affordance for a wrong landed value.
  **CLO decision, and the trigger is the first roster row, not a date**: the
  schema is `.strict()` and `organizations` is `[]` today, so it is free now and
  a migration over published rows afterwards.

NOT deferred, because this PR made it worse: the sweeper listed open trackers
with `--limit 50` against 51 live ones, newest-first, so the oldest was silently
never swept. Enrolling #7922 would have made it two. Fixed inline, with a
truncation detector — raising the number alone would only move the silent
failure.
