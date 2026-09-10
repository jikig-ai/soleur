---
title: "ADR-207 — the repo-write boundary partitions by ATTRIBUTION, not severity"
status: accepted
date: 2026-09-07
tags: [test-runner, repo-write-boundary, guard-design, attribution, worktrees, git-refs]
related_adrs: [ADR-166, ADR-181, ADR-183, ADR-193]
related_issues: [7553, 7652, 7702, 7795]
---

# ADR-207: the repo-write boundary partitions by ATTRIBUTION, not severity

- **Status:** Accepted
- **Date:** 2026-09-07
- **Issue:** [#7795](https://github.com/jikig-ai/soleur/issues/7795)
- **Ordinal note:** re-derived across every `origin/*` ref, not `origin/main` alone — the corpus
  topped out at ADR-206 (ADR-205 and ADR-206 exist only on sibling branches, so `origin/main`
  alone would have said 204 and collided twice). The population is
  `git for-each-ref refs/remotes/origin` (~75 at the time of writing, and moving); an earlier
  revision of this line said "76 refs" without naming the command, and no reading reproduces it
  — `refs/remotes/origin/*` is 42 and `git ls-remote --heads` is 73. Re-derive at ship, and cite
  the command rather than the number.

## Context

`scripts/test-all.sh` samples the repository's state twice — once at the first suite, once at
the end — and classifies the delta. It exists because of #7553/#7652: a suite whose fixture
`cd` fails, or whose `git -C` operand is empty, runs git in the caller's live repository.

The classifier's design record lived only in comment blocks inside
`scripts/lib/repo-write-boundary.sh`. No ADR described it: a grep of **this directory**
(`knowledge-base/engineering/architecture/decisions/`) for `repo-write-boundary`, `shared_store`
or `shared ref store` returned **zero** hits before this file. Scoped wider, the claim would be
false and is not made — the same grep over `knowledge-base/` returns 6, one of them the
non-archived, index-listed learning file this change also edits. What was missing was an
architecture record, not every mention. #7795 is the point at which the partition acquired a
second reviewer-visible exemption request, and a contract about to be widened for the n-th time
needs to say what n is.

## Decision

### 1. The three classes, and what each one MEANS

| Class | Meaning | Effect |
|---|---|---|
| `FATAL` | this run is the only candidate author of the change | increments `failed`, which alone drives `exit 1` |
| `REPORT` | the change is one that a sibling worktree routinely produces, and the run **cannot** attribute it | printed, named, and counted in the summary breakdown; **no** exit-code effect |
| `UNMEASURABLE` | the dimension was captured at one boundary and not the other | neither clean nor dirty; the run is simply not evidence about it |

**The partition keys on ATTRIBUTION, not on how bad the write would be.** This is the whole
design and it is counter-intuitive, which is why it is recorded here. Every ref except this
worktree's own lives in the SHARED bare repo that all linked worktrees write to. When sibling
worktrees exist, a non-own ref delta has no attributable author: a `git fetch` in any sibling
moves `refs/heads/main`, `worktree add -b` creates a head, and `cleanup_merged_worktrees()`
deletes one. All routine, none of it this run's doing.

The alternative — classify by harm — was rejected on measurement, not on taste. One 73-minute
`scripts` shard on 2026-09-02 observed **six** sibling ref moves and reddened the gate with all
342 suites passing, while the config dimension independently classified the *same* sibling
`git push -u` as `REPORT`: the two dimensions disagreed about one event. A gate that cannot
pass on the ordinary workflow gets ignored, and it is the operator's machine, not CI, that this
boundary exists to protect.

**`REPORT` is never silence.** It is printed with its ref name, and it is counted in the
summary's observation field. ADR-181's `skipped` is the precedent for a counted-but-not-failing
class.

### 2. The measurement invariant

**The `shared_store` predicate is read from the BEFORE snapshot and is never re-derived at
classify time.** `elsewhere` — the set of branches checked out in another worktree, whose
non-emptiness is the entire predicate — is read from the snapshot's `wt` family with `<none>`
filtered out. There is deliberately **no** re-derivation fallback.

**Stated exactly, because a stronger version of this sentence would be false.** An earlier
revision of this ADR said "every classification input" is snapshot-read. It is not, and asserting
a safety invariant the code does not hold is worse than not writing it down (review found this
before merge). Three inputs are live git reads at classify time:

| Input | Read | Direction it can be wrong |
|---|---|---|
| `elsewhere` / `shared_store` | BEFORE snapshot | — the anti-laundering guarantee, and it holds |
| `bsha` (create vs move) | BEFORE snapshot | — holds |
| `default_branch` | live (`refs/remotes/origin/HEAD`, else literal `main`) | can only be repointed to make the guard *stricter or laxer*; see below |
| `own_short` | live (`git symbolic-ref HEAD`) | empties on a detached HEAD, so the conjunct self-disables |
| `remote_names` | live (`git remote`) | can only ADD members to the FATAL set — strictly fail-closed |

The shadow test itself is derived from the **measured** `refs/heads/*` of both snapshots, so the
two live conjuncts above are now *fallbacks* for a ref absent from the measured set rather than
the primary test — which is what keeps a mid-run `checkout --detach` or `origin/HEAD` repoint
from opening the softened cell. That narrowing was made in response to review; before it, either
write silently disabled a conjunct. The residual is recorded rather than closed: `own_branch`'s
own FATAL arm (a different, pre-existing arm) still reads `git symbolic-ref` live, and predates
this change.

The reason is not tidiness. A suite that runs `git -C "" worktree add -b probe` mid-window
would, under a re-deriving classifier, register its own branch as a sibling and thereby
manufacture the softening that launders its own write. Three reviewers found that hole
independently in the original design; `wt` was promoted from a bare body family to a **manifest
dimension** precisely because a classification input outside the manifest is what this design
exists to prevent.

Two consequences follow, and both are load-bearing:

- **The `<none>` sentinel.** Without it, "measured, and there are no siblings" is byte-identical
  to "not carried in this snapshot" — and on any single-worktree checkout (i.e. every CI runner)
  that made the re-derivation the DEFAULT path.
- **A missing measurement withholds the softening.** `wt: not-measured` yields `FATAL`, never
  `REPORT`. A softening keyed on a measurement must fail closed when that measurement is absent,
  and — added by #7795 — it must not be MANUFACTURED by that measurement failing either:
  `_repo_boundary_branches_elsewhere` now returns non-zero on an unreadable toplevel instead of
  degrading to an empty `here`, which made *every* branch read as `elsewhere`.

This is also why issue #7795's Option 2 (`git ls-remote --tags origin <name>` to discriminate a
fetched tag from an authored one) was rejected: independently of discriminating the wrong
property, it re-derives a classification input *after* the measurement window closes.

### 3. The exemption ledger

Every softened cell, with the evidence that bought it. **This ledger is the point of the ADR:**
each request looks locally reasonable, and only the list makes the cumulative position visible.

| # | Softened cell | Landed | Evidence that a sibling routinely produces it |
|---|---|---|---|
| 1 | `config`: `branch.<n>.remote`/`.merge` ADDED | #7702 | the shape `git push -u` / `checkout -b --track` leaves |
| 2 | `config`: `branch.<n>.remote`/`.merge` DELETED | #7702 | the shape `git branch -d` / `cleanup-merged` leaves |
| 3 | `refs`: a non-own, non-tag ref DELETED | #7702 | `cleanup_merged_worktrees()` deletes merged branches |
| 4 | `refs`: `refs/heads/<default>` MOVED | #7702 | the sibling `git pull` shape |
| 5 | `refs`: a non-own, non-default, non-tag ref CREATED or MOVED | #7702 | `worktree add -b`; sibling branch work |
| 6 | `refs`: a collision-free `refs/tags/*` **CREATED** | #7795 | measured live at #7795: a `git fetch` auto-follows tags, and any sibling worktree or operator shell sharing the ref store can create one with no attributable author. The witness cited when this row was written — `worktree-manager.sh`'s fetch inside `cleanup_merged_worktrees()`, which `/work` Phase 0 runs at session start — was CLOSED by #7917: every fetch and pull in that file now carries `--no-tags`, so a reader who greps the old witness finds the opposite of what it claimed. The cell rests on the general shape, never on that one caller. **Bounded by `scripts/battery-tag-authorship.test.sh`** (#7917) — see §5 |

**Counting note, stated because a wrong count here is worse than none.** Cells 1-5 all landed in
a single commit with the `REPORT` class itself (`git log -S'shared_store' -- scripts/lib/repo-write-boundary.sh`
returns exactly two commits: the lib's introduction, and #7795). So #7795 is the **second
decision event** and the **sixth softened cell**. The plan for #7795 described it as "the third
softening"; that framing is not reproducible from the history and is corrected here rather than
propagated.

**What was NOT softened, and stays FATAL in every regime:** `HEAD`; the working tree; this
worktree's own branch; any tag **move**; any tag **deletion**; any tag creation on a checkout
with no sibling (every CI runner, i.e. the path that gates merges); and any tag creation whose
short name could shadow a ref git resolves ahead of it.

### 4. The collision guard, and why a CREATION can reach move-grade harm

`refs/tags/<n>` resolves **ahead of** `refs/heads/<n>` and `refs/remotes/<n>` in gitrevisions.
Verified live: with a tag literally named `origin/main` planted and the real remote-tracking ref
untouched, `git rev-parse origin/main` returns the **tag**, exit 0, warning only.

`scripts/test-all.sh` and the `/work`, `/qa` and `/ship` gates all scope against the bare name
`origin/main...HEAD`. So softening a tag *creation* whose name shadows a branch would silently
rescope every subsequent gate to attacker-chosen content with the exit code unchanged — harm a
tag *move* could not exceed. Cell 6 therefore carries four conjuncts: the short name must not
contain `/`, must not equal the default branch, must not equal our own branch, and must not
name a branch in `elsewhere`.

The guard therefore tests **six** shadow classes, not the four an earlier revision carried: a
name containing `/`; a bare hex string (which shadows an abbreviated object name); a name equal to
**any local branch in the measured `refs/heads/*` set**; a name equal to a **remote** (shadowing
`refs/remotes/<name>/HEAD`); and — as fallbacks for a ref absent from the measured set — the
default branch and our own branch. The third and fourth were added at review: the first
implementation tested only branches a *sibling worktree had checked out*, which on this repo left
18 local branches (the operator's own `backup-pre-*` recovery branches among them) softenable
while a same-named tag captured every later `git log/diff/merge/push`.

Measured cost of the guard on this repo: of **~3.05k tags**, **zero contain a `/`** and none is
named `main`, `master`, `HEAD` or `origin` (`git tag | grep -c '/'`, `git tag | grep -cxE
'main|master|HEAD|origin'` — both 0). The absolute count is deliberately imprecise: it was 3054
when this was drafted and 3056 at review, two days apart. Real release tags are `v3.262.3` /
`web-v0.261.4` shaped.

### 5. What bounds cell 6, and the shape of the thing that bounds it

Cell 6 is the only softened cell whose safety rests on a set the classifier cannot inspect. Cells
1-5 name shapes a sibling produces and the operator's own tree does not; cell 6 names a shape
**anything** can produce, and under `shared_store` §2's measurement invariant forbids re-deriving
who produced it. So the cell is safe exactly while the battery is not itself a tag author, and
nothing in the classifier can check that.

`scripts/battery-tag-authorship.test.sh` (#7917) is what checks it, and the shape of that guard is
itself a decision worth recording.

**It does not assert the property the cell needs.** The property the cell needs — *no battery
command writes a tag into the LIVE repository* — is not statically decidable. The working directory
is set by callers frames away, and `git -C "$x"` with `$x` empty is a documented no-op that runs in
the caller's cwd. The evidence that this is not a solvable parsing problem is historical: two
independent static adjudications of this exact question reached OPPOSITE answers, one naming
`worktree-manager.sh` as a live author and one concluding the set was already empty. A third
adjudication would have been a third opinion.

**It asserts a decidable property instead.** Every tag-authoring command the guard SEES in the
closure of executables reachable from `scripts/test-all.sh` either suppresses tag creation ON ITS
OWN COMMAND, or carries a `repo-boundary-tag-exempt:` marker within the two lines preceding it or
on the command's own line, AND a matching entry in the guard's ledger. That is checkable.

Note the two hedges, because an earlier revision of this paragraph omitted both and was wrong as a
result. "SEES" is doing real work — the guard's reach is bounded, and the bound is enumerated below
rather than implied. And the grading unit is the COMMAND, not the line: an earlier cut evaluated
every predicate against the whole line, so `git fetch --no-tags origin && git tag evil` graded
SUPPRESSED and `git push origin main && git tag evil` was dismissed as out-of-class. Both were
measured false GREENs, both are now closed, and both are the reason this ADR no longer claims the
guard "degrades toward a false OFFENDER … rather than toward a false green". It does BOTH, in
enumerable places.

**Its verb set is the cell's verb set, not `git fetch`.** This row says a tag CREATED, by anything.
A fetch-scoped guard would be literally true about fetches while green over `git pull`, over a
suite's own `git tag -a`, and over `git update-ref refs/tags/…`. Widening the verbs widens the
ledger, and that is the intended trade: the suite that TESTS this boundary is the one place a
deliberate tag author belongs, and declaring it is strictly better than a classifier that cannot
see it.

**`EXEMPT` is accepted risk, not a fix.** An exempted site still authors a tag into whatever
repository it is standing in. What the exemption buys is that it is *declared*: a reader at the
call site learns why, and this ledger shows the cumulative position — the same two-place argument
§3 makes for itself. An exemption whose site is later fixed, deleted, or has its marker removed is
an ORPHAN and reddens; the check is a bijection in both directions, because a one-directional check
is where offenders go to be forgotten.

**Ceiling governance, and its single home.** The exemption ledger's ceiling is **12**. That number
is the one AUTHORITY; the guard asserts its own constant equals this line, so the two cannot drift.
Raising it is an edit to this ADR AND to the two `LEDGER_CEILING=12` sed patterns in
`scripts/battery-tag-authorship-mutations.test.sh` (rows R7/R8), which would otherwise stop
matching. That second half is fail-CLOSED — a mutation that does not land is scored as a failed
row, never as a pass — but it is a four-place edit and calling it a one-place edit understates it.
The point stands: a ceiling raised locally to make a run green is not a ceiling. A ceiling paired with the bijection can be loose; without the bijection
it is satisfied equally by an empty ledger and by a ledger full of ghosts.

**What this does NOT establish.** The guard's closure is a FILESYSTEM walk, not a tracked-file walk:
membership is an `-f` test, so an untracked file named by a closure member joins it while a tracked
file absent from the working tree does not. (An earlier revision of this line said "the guard reads
tracked source"; that was false, and the guard's own header said the opposite two screens away.)

Within that closure, these are the places it can go green while seeing less. They are
UNDER-approximations — they fail toward a false GREEN — and they are what bounds this guard:

- **Reach.** A suite executed through a runtime glob rather than a path literal never enters the
  root set; `.github/scripts/test/run-all.sh` collects its 11 siblings that way, and 9 of them are
  outside the closure today. The `npm run test:ci` out-of-class entry waves through the vitest
  suites under `apps/web-platform`, of which only a handful are closure members.
- **Spelling of the callee.** The closure regex recognises four variable prefixes and five
  extensions; `"$ROOT/x.sh"`, `node scripts/x.js`, and `find … -exec bash {} \;` are invisible.
- **Spelling of the command.** `VERB_RE` requires a literal lowercase `git` followed by one of three
  enumerated global-option shapes. `$GIT tag`, a wrapper function or alias, `git --no-pager tag`,
  `git-tag`, and a verb held in a variable are all missed — as are `git fast-import`,
  `git symbolic-ref refs/tags/…`, `git filter-branch --tag-name-filter`, a `git push` to a LOCAL
  path (which writes a sibling's ref store, not a remote), and a direct write to `.git/refs/tags/`
  or `packed-refs`, which authors a tag with no `git` token at all.
- **Construction.** A command assembled at runtime from a variable, and a heredoc body — the guard
  applies NO heredoc exclusion, so those lines are counted, which is the safe direction.

The guard's header carries this same list under the name it deserves. Cell 6 is bounded, not
closed, and the bound is one-sided: the reach and spelling gaps above are the ones that stay quiet.

**Why the bound is acceptable anyway, and what would close it.** AP-025 says a hazard that is a
property of runtime STATE should be enforced by a self-refusal the artifact CARRIES, not by a
boundary check that must enumerate the ways to REACH that state — and a verb set plus a closure
plus a grep is exactly such an enumeration. The register-aligned instrument exists: git's
`reference-transaction` hook fires on EVERY ref write, including a tag a fetch auto-follows, and
can refuse `refs/tags/*` creation for the duration of a battery run. It is complete by
construction and needs no verb set, no closure, and no ledger. It is also blind to WHERE the
offending command lives, which is what a reviewer needs at review time; the two are complements.
The static census ships here because it names the site; the state predicate is tracked separately
as the thing that would actually close the cell.

## Consequences

- **The soft class is now the majority of the refs partition.** Counting the `refs` dimension's
  emission sites reachable under `shared_store`: **five REPORT and four FATAL** (the FATALs being
  a deleted tag or own branch, a moved tag, a shadowing tag creation, and a moved own branch).
  An earlier revision of this line said "five of six reachable outcomes", which reads as one
  surviving FATAL; there are four. Understating the strict half of your own partition is the
  error this section exists to avoid.
- **The safety case rests on an author set that is NOT closed.** Under `shared_store` the
  classifier cannot distinguish a suite-authored tag from a fetched one — by construction, since
  it refuses to re-derive attribution after the window. #7795 removes two known battery-reachable
  authors (`plugin-delivery-canary.sh`, `run-migrations.sh`) and does not close the class:
  `worktree-manager.sh` and the rest of the `plugins/` and `.claude/hooks/` fetch population
  remain. This is the single largest accepted risk and must not be described as closed.
- **The ceiling is CI.** `elsewhere` is empty on every single-worktree runner, so every ref event
  in CI remains `FATAL`. The relaxation exists only where attribution is genuinely impossible.

## The next request is the seventh cell, and it should be refused

A **seventh** softened cell — or a **third** decision event — should not be granted. (An earlier
revision headed this section "the fourth", carrying forward the plan's ordinal that the ledger
two sections above corrects. The heading is the enforcement sentence, so it has to agree with the
count.) When the
next dimension needs an exemption from `FATAL`, implement real per-suite attribution instead
(sample the boundary per suite rather than twice per run), which makes the exemptions
unnecessary rather than cheaper to grant. That work is tracked with an explicit trigger in the
Non-Goals of #7795; its known blocker is `repo_boundary_render_not_inspected`'s hardcoded
heredoc, which renders the not-inspected half of the operator claim from a literal list rather
than from the manifest — the file's own claim-cannot-outrun-the-check invariant, violated in its
own renderer.

## Alternatives considered

| Alternative | Why not |
|---|---|
| Classify by **harm** rather than attribution | Measured: reddens on the ordinary six-sibling workflow with every suite passing, and contradicts the config dimension about the same event. A gate that cannot pass gets ignored. |
| Drop `refs/tags/**` from the measured set, mirroring the `refs/remotes/**` exclusion | Gives up tag moves and deletions entirely — a suite deleting a release tag would become invisible. |
| Re-derive `elsewhere` at classify time when the snapshot lacks it | The laundering hole three reviewers found independently. A mid-run `worktree add -b` manufactures its own softener. |
| `git ls-remote --tags origin <name>` to discriminate fetched from authored | Discriminates the wrong property (a tag this run authored via an auto-following fetch is also "on origin"), re-derives an input after the window closes, and adds a network dependency with no offline disposition. |
| Widen the measured set with a fifth `refs/remotes/**` dimension as a sharper discriminator | Genuinely sharper and still pure BEFORE/AFTER measurement. Deferred: remotes deltas would flow into a refs partition with no arm for them, and the `render_not_inspected` heredoc blocks the manifest change. |
