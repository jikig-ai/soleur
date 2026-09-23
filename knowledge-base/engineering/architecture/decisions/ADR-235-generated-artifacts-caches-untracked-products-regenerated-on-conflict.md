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

**Classify the knowledge-base generated artifacts as CACHE or PRODUCT, and treat the two
differently.** The scope is the six artifacts this decision enumerates below. It is NOT a
classification of every generated file in the repository, and an earlier draft claimed it was:
at review (#8384) at least eight further generated artifacts were found that the two-cell table
either classifies differently from how they are handled or cannot classify at all —
`plugins/soleur/skills/eval-harness/models.generated.json` (tree-derived yet committed and
parity-guarded as such), `knowledge-base/project/weakness-digest.md` (tree-derived, committed
back by a bot PR), `apps/web-platform/infra/cron-egress-allowlist-cidr.txt` (sourced from a live
external API — a third class), `apps/web-platform/infra/cutover-monitor-baseline.txt` (a frozen
snapshot whose value is that it is *never* regenerated), and
`knowledge-base/engineering/architecture/diagrams/generated-components.c4` plus
`knowledge-base/project/kb-coverage.md` (both untracked AND unignored today). Extending this
decision to them needs at least a third term — PIN: committed because regeneration is not
idempotent, or the source is outside the tree — and an admission gate derived by shape rather
than a hand-maintained list. That is a separate decision; this one is honest about its edge.

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

## Amendment — 2026-09-22 (#8542): the product is committed in a mergeable format

The classification above stands: `model.likec4.json` is a product and stays committed. What
changes is its **on-disk format**, and with it how often regenerate-on-conflict is needed at all.

**The "conflicts are rare" rationale in *Alternatives rejected* is superseded by measurement.**
In the 7 days before 2026-09-22, 27 of 121 commits on `main` changed the artifact, all alongside a
`.c4` source. Because likec4 exports one ~1.1 MB line, any two such PRs conflict on GitHub, whose
server-side merge cannot run the resolver. That is a second, separate sample: of 152 pairs of
real `.c4` commits replayed from `main` (the last 30 such commits, paired at gaps 1-10), 0 merged
cleanly in the old format.

**Decision.** Every writer publishes one canonical format, produced by
`plugins/soleur/lib/c4-canonical.mjs`:

- one JSON value per line, no indentation (`JSON.stringify(model, null, 1)` with leading spaces
  stripped), and a trailing newline;
- every `views[*].hash` set to `""`.

Blanking the hash is what makes the format mergeable. That hash is an `objectHash` of the
pre-layout view. It changes on almost every model edit, and it was the only JSON value both sides
of most pairs changed. Nothing reads it:

- not `@likec4/diagram`;
- not `LikeC4Model.create` (pinned by `apps/web-platform/test/c4-canonical-mirror.test.ts`);
- not this repo;
- not the likec4 CLI, whose export is byte-identical with a blank-hash artifact in its workspace.

The key is kept because the `ViewWithHash` type declares it.

**Measured** (replay harness and results: `knowledge-base/project/specs/archive/20260922-133038-feat-c4-model-mergeable/replay/`):

- Real concurrent pairs whose `.c4` sources merge cleanly: 0/152 merge today, 107/152 in the
  canonical format.
- No merge in the replay was clean but wrong: each of the 107 clean merges equals a fresh render
  of the merged sources. This is a measurement, not a guarantee. In this repo, `ci.yml` runs on
  `merge_group`, so `c4-model-freshness.test.sh` re-renders the merged tree before it lands, and
  `main-health-monitor.yml` re-checks `main`. Customer repos have neither, so a clean merge there
  that is not a faithful render stays until the next writer runs.
- Pretty-printing alone, without blanking the hash, fixes only 7/152.
- The 45 remaining conflicts still route through `resolve-regenerable-conflicts.sh`, and
  `RESOLVABLE_PATHS` is unchanged:
  - 43 are true overlaps. Both sides moved the same Graphviz coordinates in a shared view
    (`containers`, `index`), or set the same relation's title differently. No text format can
    merge those correctly.
  - 2 are adjacency conflicts: no value differs on both sides, but the edits sit on neighbouring
    lines.

**Three writers, one module.** Each canonicalizes only after its own validation gates, and each
maps a canonicalize failure to its existing failure contract without publishing: the script exits
1, `renderC4Model` returns `io_error`, and the `soleur:sync` producer reports `failed`.

| Writer | Where it runs | Reaches the module via |
|---|---|---|
| `scripts/regenerate-c4-model.sh` (lefthook, resolver) | this repo | `node plugins/soleur/lib/c4-canonical-cli.mjs` |
| `apps/web-platform/server/c4-render.ts` (diagram editor) | the app; commits to customer repos | `apps/web-platform/lib/c4-canonical.mjs`, a byte-identical mirror |
| `plugins/soleur/scripts/generate-c4-from-components.ts` (`soleur:sync`) | customer repos, from the installed plugin | direct import |

- **Why a mirror.** No single path is reachable by all three writers. The app's Docker build
  context is `apps/web-platform` only, and a plugin install has no `apps/`. Byte identity is
  asserted by both the bun and the vitest suite, so a PR touching either copy runs the check.
- **Where canonicalization runs.** Each writer canonicalizes only after its existing validation
  gates, and a canonicalize failure never publishes.
- **What guards the committed format.** `c4-model-freshness.test.sh` also asserts it with
  `--check`. The byte comparison alone cannot see a PR that drops the step and regenerates raw in
  the same diff.

**Scope limits, accepted:**

- **Customer repos have no resolver.** `resolve-regenerable-conflicts.sh` calls
  `scripts/regenerate-c4-model.sh`, which exists only in this repo. A customer's residual true
  overlaps stay conflicted until one of their writers re-renders.
  > **Superseded 2026-09-23 (#8542 follow-up):** the renderer moved into the plugin and the
  > resolver runs it from there; see *Amendment — 2026-09-23* below.
- **Rollout.** The app and the regenerated artifact ship from one merge. The plugin reaches
  self-hosted customers on their next plugin update; until then an older plugin still writes the
  raw one-line format, and each switch between writers rewrites the whole file. Upgrading is the remedy. No migration
  runs, because every writer already rewrites the whole file, so old files convert on their next
  write.
- **Size headroom.** The canonical artifact is 1,210,508 B, 28.9% of `MAX_C4_BYTES`, against
  1,133,281 B raw. Room to grow drops from 3.70x to 3.46x. The caps are unchanged and apply to the
  canonical bytes, so a customer model whose raw export was roughly 3.75-4.0 MB (growth depends
  on the model's shape) now crosses the 4 MiB cap: the editor's re-render is skipped with a Sentry
  event (`feature: c4-rerender`, `op: commit-json`, "regenerated model too large to commit") and
  the diagram stays on the last committed version, and the viewers return 413 for a file written
  over the cap by another writer. Raising the served cap is a product decision this change does
  not make.
- **`.gitattributes`.** The root `.gitattributes` returns with a single line,
  `linguist-generated=true` for the artifact, so GitHub collapses it in PR diffs.
  `plugins/soleur/test/c4-canonical.test.ts` fails if a `binary`, `-diff`, `-merge` or `merge=`
  attribute joins it. The resolver's comment explains why a `binary` attribute would turn
  regeneration into keeping one side.

**Alternatives rejected here:**

| Alternative | Why |
|---|---|
| Untrack the artifact and generate it at build/deploy | The viewer fetches the committed blob from GitHub per request, and the app commits it into customer repos. A render-on-read path is a product change of its own. |
| Split per view or per section | Measured no gain over one file once the hash is blanked. The same shared views overlap either way. |
| A bot that resyncs PRs that go DIRTY | Treats the symptom. The resolver already covers the residual. |
| Indent 2 or sorted keys | Identical merge outcomes (measured), at +59% bytes for indent 2. |
| A layout-free artifact, with the browser laying out views | Would remove the residual too, but it changes rendering. Deferred as #8541. |

## Amendment — 2026-09-23 (#8542 follow-up): the regeneration command is plugin-owned

Supersedes the 2026-09-22 scope limit *"Customer repos have no resolver."* The gap was not that
the resolvable set is too small; it was that the set's one command lived in the wrong repository.
So the fix moves the command and leaves the set alone.

**What moved.** The renderer is `plugins/soleur/scripts/render-c4-model.sh` (history kept from
`scripts/regenerate-c4-model.sh`). It takes `--root <repo>`, runs the canonicalizer beside itself,
passes `--ignore-scripts` to `npx` as the TS producer does, and needs only one `.c4` source: a
`soleur:sync` repo carries `spec.c4`, `views.c4` and `generated-components.c4` but never
`model.c4`, so the old all-three guard refused every synced repo. The old path is a wrapper kept
for lefthook and the docs. It is **not** an arm of the resolver.

**The one arm.** `bash <plugin-root>/scripts/render-c4-model.sh --root <repo>`. The plugin root is
the resolver's own directory, made absolute before the script `cd`s into the repo. A bare
`${CLAUDE_PLUGIN_ROOT}` is used only when no renderer sits beside the resolver. That order is the
control. The `plugin.json` name check runs on whichever root is used, and it is defence-in-depth,
not a boundary: this repo's own tracked `plugin.json` names `soleur`, so a shadowing copy inside a
merged tree passes it (ADR-179 A11, A17). No part of the argv comes from the repo being merged.
Each argv-producing line carries an `ARGV-SOURCE` marker, and the suite pins the set of markers.

**Still one member; the manifest stays rejected.** `model.likec4.json` is the only generated file
Soleur commits into a customer repo, and the plugin now owns its renderer. A manifest would bring
back a command supplied by the repo, which is the thing this amendment removes.

**New refusals.** Each one leaves the tree byte-identical:

- **An untracked or ignored `.c4` in the artifact's directory.** likec4 compiles every `.c4` it
  finds, so a local `generated-components.c4` would end up in a committed model that the merge
  never saw. Untracked files that are not ignored already fail the clean-tree check.
- **A regen that writes any path besides the conflicted one.** `git merge --abort` keeps unstaged
  changes and untracked files. So the unwind restores and removes those paths itself. The tree was
  clean at entry, so every such path was written during the run.
- **An interrupt.** The `INT`/`TERM`/`HUP` trap now exits after aborting. A trap that returned
  resumed the loop. With two members, the loop then deleted the second path, and nothing restored
  it (measured through the test seam).

The arm's output is captured and its tail goes into the `bail` message. The arm runs under
`timeout` (600 s, matching the TS producer) where `timeout` exists. A progress line comes first.
The success marker names `arm=` and `root=`.

**Call sites.** Both `pre-merge-rebase.sh` hooks now share a byte-identical lookup. They prefer an
identity-checked `${CLAUDE_PLUGIN_ROOT}` and fall back to the in-repo copy. `sync-pr-behind.sh`
falls back to `${CLAUDE_PLUGIN_ROOT}` when it runs from ship's mktemp snapshot, which has no
siblings. The skills (`merge-pr`, `drain-prs`, `ship`, `architecture`) and the settle reference
invoke the resolver and the renderer through `${CLAUDE_PLUGIN_ROOT}`. The resolver suite fails on
any repo-relative invocation left in skills, commands, agents or hooks.

**Unchanged coverage bound.** This only helps merges run locally through a Soleur skill or hook.
GitHub's *Update branch* button and server-side auto-merge still resolve nothing.

**Residuals, recorded:**

- A resolver loaded from the merged tree runs that tree's renderer. This depends on the call
  site. The script cannot defend against it, which is why the hooks now look in the plugin first.
- A regen that writes an **ignored** stray file is not detected. The P3 check sees unstaged
  changes and untracked files that are not ignored.
- Stock macOS has no `timeout`, so the arm runs without a bound there.
- `resolve-regenerable-conflicts.test.sh` row 3 failed 4 times in about 150 full-suite runs, all
  under heavy parallel load. Each time the SUT exited 1 with nothing printed after its first progress
  line, and left `MERGE_HEAD` behind. Not reproduced in isolation (0/40), and the cause is not
  established.

**Verification.** `resolve-regenerable-conflicts.test.sh` (73 cases, including the Guard Contract
rows), `render-c4-model.test.sh` (a real likec4 render of the `soleur:sync` shape),
`pre-merge-rebase-regen-lookup.test.sh`, `sync-pr-behind.test.sh`, `c4-model-freshness.test.sh`.
