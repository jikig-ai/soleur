# Decision Challenges — feat-one-shot-7695-inngest-image-pin-probe-schema

Persisted headless per ADR-084. `ship` Phase 6 renders these into the PR body and files an
`action-required` issue. Each is a challenge to the operator's stated direction, surfaced rather
than silently applied.

**Both challenges were NARROWED by the 2026-09-07 plan revision.** The reasoning for each narrowing
lives in the plan's `## Plan Revisions` section (content anchors: R9 for UC-1, R6/R7 for UC-2) and
is referenced rather than restated here.

## UC-1 — One PR with an in-PR red interval, or two PRs with the tag on a merge commit?

**Class:** User-Challenge (argues the operator's stated scope should change)
**Operator's stated direction, which remains the default:** "this is a PR only."
**Status after the revision:** materially weakened, but not dead.

### The 5-line frame

1. **What you asked for.** One PR that ships the enabling fix — re-pin, guards, heredoc repair — with
   no dispatch of any kind.
2. **What the plan found.** The image is a content carrier: its bytes must contain this PR's own
   edits, so the tag has to be pushed from the branch *after* the edits and *before* the pin bump.
   A squash-merge never places that branch commit in `main`'s history, which breaks the
   `git show <tag>:<carrier-file>` provenance the plan's Guard A and AC1 both depend on.
3. **The alternative.** PR1 ships the carrier edits and the guards and merges green. The tag is
   pushed at PR1's **merge commit on `main`**. PR2 ships the pin bump, and Guard A is green the
   moment it exists because the pin it lands with is the one it validates. The tag is permanently
   reachable from `main`.
4. **What it costs.** Two pipeline runs instead of one, and a merge between them — which is real
   delay on a PR whose whole point is delivering a merged P1 root-execution fix to a live host that
   is running the pre-fix script every thirty seconds.
5. **The honest narrowing.** The revision **reverses** the earlier claim that a one-PR shape leaves
   `main` permanently red. It does not: after merge the pin reads v1.1.26 and the newest tag is
   `vinngest-v1.1.26`, so the semver-max check is green and is therefore kept. The only red interval
   is inside the PR, between two of its own commits. **So the redness argument for splitting is
   gone.** What survives is narrower and sharper than the original framing: tag reachability and
   provenance under squash-merge.

**Recommendation:** surfaced, not applied. The provenance argument is real and Guard A's git-based
design makes it *more* load-bearing than before, since `git show <tag>:<path>` is now the guard's
entire mechanism rather than a one-off check. Weigh it against the delivery delay in §4, which the
revision established is measured in undelivered-root-execution-fix days, not in inconvenience.

## UC-2 — Should never-executed on-host code ride this tag?

**Class:** User-Challenge (argued for dropping operator-requested scope)
**Status after the revision:** substantially RESOLVED. Recorded for the record, not for a decision.

The original challenge was that the lifecycle self-report and the post-`daemon-reload` render
self-verification were brand-new on-host code that **nothing in a code-only PR exercises** — if
either misbehaved, the next recut attempt would fail for a new reason and cost another tag cycle.

The revision cut both, on independent grounds (they duplicate two live signals the host already
emits — see the plan's *Correction 3*). The challenge's remedy was adopted; only its framing differs.

**What still rides the tag that the original challenge would have questioned:** the heartbeat heredoc
repair. It is deliberately kept, and the reasoning is *not* "it is safe" but "the artifact it renders
is **already** broken on the host — it currently receives `doppler secrets` stdout into a file
written with no `umask`". Fixing it is strictly better than shipping a new tag that carries the
defect forward, and it costs two lines in a file already being re-tagged. If the tag must shrink
further, this is the last thing to cut, not the first.
