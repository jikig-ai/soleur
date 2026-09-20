# ADR-235 — Generated artifacts: caches are untracked and regenerated on demand; products are committed and regenerated on conflict

- **Status:** Accepted
- **Date:** 2026-09-20
- **PR:** #8384
- **Issue:** #8377 (also closes #8370)
- **Supersedes:** [ADR-210](./ADR-210-regenerating-merge-driver-for-committed-generated-artifacts.md)
- **Amends:** [ADR-091](./ADR-091-rule-metrics-local-producer.md)
- **Related:** [ADR-174](./ADR-174-kb-index-exclusion-supersedes-per-feature-archival.md) (the
  row-eligibility predicate the generator still owns and this ADR does not touch),
  [ADR-032](./ADR-032-github-branch-protection-as-iac.md) (the ruleset that sets
  `strict_required_status_checks_policy`, which is what makes every `main` advance expensive)

## Context

ADR-210 made a committed generated artifact merge correctly by re-deriving it from git's three
merge inputs, via a `merge.kb-index.driver` registered in local `git config`. The driver worked.
It was also **structurally unable to run where the cost actually landed**, and that is the fact
this ADR turns on.

A merge driver lives in local `git config`, never in the tree. GitHub's server-side merge
therefore cannot run one. So every `gh pr update-branch`, every "Update branch" click, and every
strict-up-to-date auto-merge resolved `knowledge-base/INDEX.md` with the default text merge —
the exact path ADR-210 existed to prevent, on the surface that produces most merges.

Measured on 2026-09-19: **71 of 102 first-parent `main` commits in 7 days touched `INDEX.md`.**
Under `strict_required_status_checks_policy = true` (ADR-032) every one of those re-`BEHIND`s
every open PR, and a PR that is `DIRTY` is the one state the `--admin` hatch cannot cross. PRs
#8319 / #8321 / #8347 paid 7 / 11 / 3 forced resyncs; the first two cost roughly six hours of
wall-clock each. #8151 shortened each resync without removing the class. A second symptom,
#8370, is the same cause on the CI surface: AC17 reddened on `refs/pull/N/merge` — a tree that
exists only on GitHub, where the driver cannot run — while the branch head was self-consistent.

`knowledge-base/project/rule-metrics.json` is the same shape with counters, and it is worse in
one respect: per ADR-091 its inputs are gitignored local incident data, so the committed
aggregate was never more than a snapshot of whichever worktree last ran the aggregator and
committed it. 20 of 20 recent merges touched it (#8301).

The question ADR-210 did not ask is whether these files should be committed at all. Its
Alternatives section lists "stop committing the generated artifacts entirely" and defers it on
scope, not on merits.

## Decision

**Classify every generated artifact as a CACHE or a PRODUCT, and treat the two differently.**

A **cache** is derivable from the repository tree, or from gitignored local data. It is
**gitignored and never committed**, and a staleness-checked script regenerates it at read time.
A file that is never committed cannot conflict — the defect class is removed rather than
automated.

- Members: `knowledge-base/INDEX.md`, `kb-tags.txt`, `kb-categories.txt`,
  `knowledge-base/project/rule-metrics.json`, and the `knowledge-base/.kb-index.stamp` that
  records the first three's freshness.
- `scripts/ensure-kb-index.sh [--soft]` regenerates the index trio. Every reader calls it
  first: `kb-search`, `learnings-researcher` (and its `.openhands` copy),
  `learning-retrieval-bench.sh`, the `prepare` lifecycle script, and both SessionStart
  registries.
- `scripts/rule-prune.sh` runs `rule-metrics-aggregate.sh` ahead of its own read.
- `plugins/soleur/test/kb-caches-untracked.test.sh` asserts the set stays untracked AND
  gitignored. Those two can disagree in the direction that hurts: ignore rules are silently
  inert for an already-tracked path, so a re-added cache reads as protected while not being.

A **product** is read by a consumer that cannot regenerate it. It **stays committed**, and its
conflicts are resolved by regenerating from the MERGED sources.

- The only member is
  `knowledge-base/engineering/architecture/diagrams/model.likec4.json`. The web-platform C4
  viewer (`apps/web-platform/app/api/kb/c4/project/route.ts`) fetches the committed blob from
  the GitHub source of truth on the request path, with no build step, so the bytes have to
  exist as a committed blob. (Corrected at review: an earlier draft cited
  `server/c4-render.ts` and "no likec4 compiler". That file is the *writer*, and it proves a
  compiler exists in the runner image (`npm install -g likec4@1.50.0`). The classification
  held; the cited reason did not.)
- `plugins/soleur/scripts/resolve-regenerable-conflicts.sh <base-ref>` does the resolution, and
  is called from all three DIRTY-handling paths: `sync-pr-behind.sh`, `pre-merge-rebase.sh`, and
  ship Phase 7. Any fourth path that merges `origin/main` without it is a defect.

**No generated artifact is resolved by a merge driver**, because the server-side merge cannot
run one. That is the sentence that supersedes ADR-210.

### Why the resolvable set is a hardcoded array and not a manifest

It has one member. A manifest is a parse surface, and — more importantly — it makes the list
feel cheap to extend, which is precisely the pressure that put these files in the tree in the
first place. Adding a second product means editing the array AND amending this ADR, so the
cache-vs-product question is asked every time.

### Why the staleness probe is a content fingerprint

`ensure-kb-index.sh` hashes `git ls-files -s` plus `git status --porcelain -uall`, both scoped
to `knowledge-base/`. An mtime comparison cannot see a timestamp-preserving edit — a `cp -p`, an
`rsync -a`, or a `git checkout` of an older blob leaves content changed and the file OLDER than
the stamp. The failure is silent and lands on the reader: it greps an index that does not list
what is on disk and reports "no prior art". That is the #8177 shape.

The generated paths are excluded from the fingerprint explicitly. They live inside
`knowledge-base/`, so without that exclusion every regeneration moves the value the next run
compares against and the script regenerates forever. `.gitignore` happens to mask this in THIS
repo, which is what would have made it correct here and wrong in any checkout with different
ignore rules.

**Known residue, accepted:** an edit to a gitignored file under `knowledge-base/` (a local
`private/` note) is invisible to both halves of the fingerprint. No property requires it and
the next tracked change picks it up.

## Consequences

- Open PRs stop conflicting on the caches. The measured 71-of-102 `main`-advance cost goes to
  zero for those paths.
- **One-time transition cost.** A branch opened before this landed still tracks the four files
  while `main` has deleted them, so its next sync is a modify/delete conflict. It is resolved
  by one `git rm --cached` of the four paths, documented in `merge-pr/SKILL.md`. This is
  deliberately not a sweep script: it runs once per affected branch, on a conflict its owner is
  already resolving, and a tool that force-pushes ~20 branches is a worse failure mode than ~20
  blocking conflicts. (This PR's own merge of `origin/main` hit exactly this and the one-liner
  resolved it.)
- A fresh clone has no index until something calls `ensure-kb-index.sh`. `prepare` and
  SessionStart cover the normal paths; readers call it themselves regardless, so an uncovered
  path degrades to a regeneration rather than a wrong answer.
- `kb-search --tag` in a repo with neither the facet files nor the generator (every self-hosted
  install) now validates against the corpus frontmatter instead of exiting 1 with a Soleur-only
  remediation the user cannot run.
- Retired with the driver: `scripts/merge-kb-index.sh`, `scripts/install-kb-merge-driver.sh`,
  `scripts/lib/kb-index-render.sh`, the root `.gitattributes` (which held nothing else), four
  test suites, the lefthook `generate-kb-index` step, the guardrails path-conditional sentinel
  arm, `generate-kb-index.sh --check`, the derived `> Total files:` header, AC17,
  `.github/workflows/rule-metrics-aggregate.yml`, and `ci.yml`'s `rule-metrics-shape` step.
- The guardrails deletion is pinned as ABSENCE rather than behaviour: re-adding any
  path-conditional arm reds a passing assertion in `guardrails.test.sh`.
- `compound` no longer stages `rule-metrics.json`, and its failure branch is `rm -f` rather
  than `git checkout --` — the latter cannot restore an untracked file, so the old recovery
  would have left exactly the partial it was written to clean up.

## Alternatives rejected

| Alternative | Why not |
|---|---|
| Keep the driver (ADR-210 status quo) | It cannot run server-side, which is where most merges happen. Local correctness does not reach `refs/pull/N/merge` or the Update-branch button. |
| Regenerate `INDEX.md` on `main` post-merge | Every regeneration commit is a `main` advance that re-`BEHIND`s every open PR under ADR-032 (~14/day, measured 2026-09-13..19), needs a GitHub-App `bypass_mode = always` actor or a bot PR per merge, spends CI runs, and still leaves the branch-local index stale — the #8177 shape it was meant to fix. |
| Drop only the `> Total files:` header | Adjacent same-day row inserts still conflict; the driver and AC17 remain. |
| Keep the driver and add the resolver for `INDEX.md` too | Automating the resolution keeps the DIRTY state and the CI restarts. The cost is the merge, not the resolution. |
| Untrack `model.likec4.json` as well | The web-platform C4 viewer reads it from synced repos with no compiler; its write path commits rendered bytes by design (#4976). |
| Web-platform renders the C4 model at sync time | Changes the customer read path in `apps/web-platform/server/` — a product-architecture decision outside this change's scope. Recorded here so the option is not re-litigated by accident. |
| Regenerate `model.likec4.json` on `main` only | Same `main`-advance and bypass-actor cost as option 1, for a file whose conflicts are rare (concurrent `.c4` edits only). |
| A `regenerable-artifacts.tsv` manifest | One member; adds a parse surface and invites re-tracking regenerable files. |
| Resolver auto-`git rm`s the caches on modify/delete | The first sync of an open PR runs that branch's pre-change scripts, so the rule would never execute where it is needed. |
| Regenerate the caches in a lefthook step without staging | Readers would still see a pre-commit snapshot, and cloud harnesses run no git hooks. The on-read probe is cheaper and covers both. |

## Verification

- `plugins/soleur/test/kb-caches-untracked.test.sh` — the set is untracked and ignored (4/4
  mutations RED).
- `scripts/ensure-kb-index.test.sh` — freshness, including the timestamp-preserving edit that
  is the whole reason the probe is a fingerprint (8 mutation axes, all RED).
- `plugins/soleur/scripts/resolve-regenerable-conflicts.test.sh` — fail-closed on every input
  that is not the exact happy path (12 mutations, 10 RED; the 2 survivors are labelled in the
  source as unreachable by any fixture and kept deliberately).
- `plugins/soleur/scripts/sync-pr-behind.test.sh` — the caller's two outcomes.
- `git check-ignore` over the five cache paths exits 0 and prints all five.
