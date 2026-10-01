# Decision record — shell git-fixture containment sweep (PR 2)

Headless run (`/soleur:one-shot` plan phase, plan-file-path argument). Per ADR-084 the operator is
not paused; decisions that diverge from the brief's stated direction are recorded here for `ship` to
render into the PR body and file as an `action-required` issue.

## 1. The sweep set is FOUR, not five — technical fork, not an operator question

**Brief said:** five suites, re-derived by the operator 2026-09-08 and unchanged from planning.

**Measured 2026-09-09:** the pinned predicate returns **four**. `proc.test.sh` carries
`env -u PROC_SH_WORKTREE -u GIT_DIR -u GIT_WORK_TREE` at its T9 case (blame `6ad705063f`,
2026-08-13 — it **predates** planning), so the predicate's scrub arm excludes it.

**Decision:** treat as a predicate-**application** error in the inherited list, not corpus drift.
`proc.test.sh` stays in scope for **A1** on its own merits (its T9 `NOGIT` case is the vacuity
class), which is what the source plan actually assigned it. Per `hr-technical-fork-is-not-an-operator-question`
this is settled by measurement, not escalated. The brief explicitly instructed re-derivation and
drift reporting; this is that report.

## 2. Corpus is 88, not 82; repo-wide count is regex-bound, not 30

**Measured:** `git ls-files 'plugins/soleur/test/*.test.sh'` = 88. Repo-wide, the narrow anchor
`measurements.md` used returns **17 / 6 under `.claude/hooks/`**; a `git -C`-aware anchor returns
**41 / 13**. Neither reproduces the recorded 30 / 7.

**Decision:** ship **one** executable predicate and report the number **it** yields. A count whose
regex is unstated is not falsifiable, and AC13 requires falsifiability. Recorded rather than
silently reconciled, because the recorded 30/7 appears in `measurements.md` on `main` and a future
reader will hit the discrepancy.

## 3. #7822 does NOT say exposure is "highest" under `.claude/hooks/`

**Brief said:** "7 of the repo-wide 27 remainder sit under `.claude/hooks/`, which is where #7822
says exposure is highest."

**#7822 actually says:** *"**These are candidates, not confirmed defects** — I have not driven each
one under `GIT_DIR`. Several are `.claude/hooks/*` suites, i.e. the ones most likely to be executed
*from* a hook. That list is the work, not the finding."* Its list is headed by
`apps/web-platform/infra/workspaces-luks-loopback.test.sh`, a **do-not-touch path**.

**Decision:** the PR body names the residue as #7822 names it — most likely to be executed *from* a
hook, **candidates** rather than confirmed defects, none driven under `GIT_DIR`. The brief's
requirement to name the residue is honoured; its characterisation is corrected.

## 4. A recurrence ratchet over the test-file corpus was reached for, then CUT

**Considered:** promoting the sweep predicate to a shrink-only CI ratchet, to discharge #7822's ask
2 (*"a lint is the only thing that stops it recurring — care demonstrably does not"*).

**Cut, because the sibling already buys it in a better shape.**
`plugins/soleur/test/hook-git-env-coverage.test.sh` (Guard 2) ratchets **hook entry points**, and
its header carries the measurement: all four recurrences of this defect entered through an entry
point that lacked the scrub, **never** through a test file that lacked a helper — and *"that corpus
is not enumerable anyway"*. This plan independently re-proved the non-enumerability by getting
17/30/41 from three readings of one predicate. A ratchet whose baseline is a regex artifact can be
silently narrowed, which is the defect it would claim to prevent.

**Consequence:** #7822's asks 1 and 2 are **already shipped**; ask 3 and the "quieter second harm"
are this PR's A3 and A1. Closing #7822 is therefore honest and is recorded as such in the plan.

## 5. The Incident-PIR precedent-citation gate — the brief required a decision this run

**Decision: the fixture discharges the remaining criterion. The issue can be closed on that basis;
closing it is NOT this PR's work, and the code fix is not reopened.**

The remaining criterion was a behavioural observation at the next `/ship`. PR 1's ship did not
provide one, and structurally could not: the **pre-fix** gate was measured against that same PR and
was **also** silent, so the PR never exercised the path — an observation both the fixed and unfixed
gate produce identically carries zero information.
`plugins/soleur/test/fixtures/ship-incident-pir-gate/precedent-citation-inside-hypothetical-paragraph.md`
pins the same property deterministically (pre-fix FIRES, post-fix silent, both already measured),
is consumed by `scripts/ship-incident-pir-gate-mutation.test.sh` and
`plugins/soleur/test/ship-incident-pir-gate.test.ts`, and re-runs every CI cycle. It is **strictly
stronger** evidence: it has the positive control a chance observation structurally cannot have, and
it repeats. Waiting would trade better evidence for worse on a timeline nobody controls.

## 6. An institutional learning was consulted and OVERRULED by measurement

The `learnings-researcher` pass recommended *"upgrade all three suites to `set -euo pipefail`"*.
That is precisely the change **measured** to break `gitleaks-merge-commit.test.sh` (27/27 → rc=1).
The suites are deliberately `-e`-less because they are mutation-proof suites whose cases expect
non-zero returns inline. The plan takes the measured remedy (`set +e -uo pipefail`) and records the
contradiction, because the recommendation is plausible and would be reached again by anyone
reasoning from convention rather than running the suite.

The same pass recommended sizing the A3 fixture for concurrency ("13,815 files"). **Rejected:** the
`GIT_DIR` inheritance vector is environmental, not size- or concurrency-dependent; a one-commit
victim reproduces it deterministically, as measured.

---

# USER-CHALLENGE — raised by plan review, requires operator decision

## 7. Both `Closes` downgraded to `Ref`. This reverses the brief's stated direction.

**The brief said:** *"Work targets to close: #7822 and #7835."*

**The plan ships `Ref #7822` / `Ref #7835` instead.** Per ADR-084 the operator's stated direction is
the default, so this is surfaced rather than silently applied. Headless run — recorded here for
`ship` to render into the PR body and file as an `action-required` issue. **The operator can
overrule; the plan is written so that flipping `Ref` back to `Closes` requires no other change.**

### The evidence that forced it

**#7822 — 0 of the 10 files it enumerates are touched.** Its `## Measured population` lists ten shell
suites and calls that list *"the work, not the finding."* Measured against this plan's own
`_guarded()` clause: **10 of 10 still unguarded, 0 of 10 in the sweep set** — the sets are disjoint
(the sweep is entirely `plugins/soleur/test/*`; the population is `.claude/hooks/*` plus two
`apps/web-platform` files). One of the ten,
`apps/web-platform/infra/workspaces-luks-loopback.test.sh`, is a declared **do-not-touch path**, so
this PR is structurally barred from fixing it.

**#7835 — the TypeScript half did not ship, contrary to the brief.** The brief stated it "shipped
earlier". Measured: `cc-reprovision-git-discriminator.test.ts`, `helpers/context-queries-fixture.ts`,
`worktree-config-seed.test.ts` and `git-config-atomic.test.ts` carry **no** scrub idiom. #7849's body
independently corroborates, listing two of them as *"neither converted nor waived."*

### What the PR does contribute

#7822's ask 3 (a regression test that sets `GIT_DIR` and asserts the caller's branch tip does not
move) is this PR's **A3** — genuinely new, and not covered by `git-tripwire.test.sh`, which proves
*refusal* and never reads a victim's state. #7822's "quieter second harm" (vacuity) is **A1**. Ask 1
shipped; ask 2 is served at the entry-point layer by `hook-git-env-coverage.test.sh`. That is a real
contribution — it is not closure of either issue.

### The cheapest route to earning closure, if the operator wants it in this PR

Give the predicate a `--gate` mode that exits non-zero on any member outside a committed
acknowledgment file, register it as a ratchet, and seed the file with today's members — roughly 20
lines. **The plan deliberately does not do this**, because the Cut List's reasoning still holds: the
gate for this class lives at the **entry-point** layer (`hook-git-env-coverage.test.sh`, where all
four recurrences actually entered), and the test-file corpus is measurably not enumerable — three
readings of one predicate gave 17, 30 and 41. A ratchet whose baseline is a regex artifact can be
silently narrowed, which is the defect it would claim to prevent. Offered as an option, not a
recommendation.

**Mitigation shipped instead:** the residue is filed as a durable `type/bug` / `priority/p2-medium`
issue enumerating all fourteen files, per `wg-when-an-audit-identifies-pre-existing` (a PR body is
not a durable artifact) and `wg-defer-only-after-inline-triage` (the residue passes all three tests:
not a sub-30-minute one-file fix, concrete trigger, and it has already fired twice).

## 8. Plan review found the containment arm was unfalsifiable as first drafted

Recorded because it is the single most valuable finding of this planning run and the implementer must
not re-introduce it.

`SOLEUR_GIT_TRIPWIRE_ALLOW=1` **announces and falls through — it does not scrub.** Verified: the `if`
branch of the `test-helpers.sh` prelude holds one `printf` and no `unset`; the nine-variable loop
lives only in the `else`. The helper's own comment says *"This ABORTS rather than unsetting."*

Consequences, both now written into the plan:

1. **A2 buys refusal, never containment.** The containment arm tests a *different layer* —
   `scripts/test-all.sh`'s `unset GIT_DIR … GIT_EXEC_PATH` — and A3 must invoke its child through a
   **sandbox copy** of that line, because the real runner has no single-suite mode and refuses under
   fan-out. Without it the arm is red from birth. Measured as **M-10**: with no scrub in the path all
   three swept suites write into the victim, `gitleaks-merge-commit` landing 4 commits on the
   victim's live branch — a byte-for-byte reproduction of #7835, and the containment arm's positive
   control now measured rather than promised.
2. **The hostile environment must BE the victim** (`GIT_DIR="$VICTIM/.git"`). Aimed at scratch, the
   victim's triple cannot move whether containment holds or not, so mutation M1 silently stops being
   driveable. Guard 1 **M7** now pins this.
