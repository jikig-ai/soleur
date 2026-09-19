---
title: "feat: untrack generated KB caches, regenerate product artifacts on conflict"
type: feat
date: 2026-09-19
slug: feat-untrack-generated-kb-caches-regenerate-on-conflict
branch: feat-kb-index-untrack
issue: 8377
closes: [8377, 8370]
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-09-19-kb-index-untrack-generated-artifacts-brainstorm.md
spec: knowledge-base/project/specs/feat-kb-index-untrack/spec.md
---

# feat: untrack generated KB caches, regenerate product artifacts on conflict

## Overview

Three machine-generated files make every open PR unmergeable on every advance of `main`,
because GitHub's server-side merge cannot run the local merge driver that resolves them
(ADR-210). Each is a different kind of artifact and gets a different fix:

| File | Kind | Fix |
|---|---|---|
| `knowledge-base/INDEX.md`, `kb-tags.txt`, `kb-categories.txt` | cache of the tree | untrack; regenerate on demand via `scripts/ensure-kb-index.sh` |
| `knowledge-base/project/rule-metrics.json` | cache of gitignored local data (ADR-091) | untrack; `rule-prune.sh` regenerates before reading |
| `knowledge-base/engineering/architecture/diagrams/model.likec4.json` | product artifact (the web-platform C4 viewer reads it from synced repos; its write path commits it via the Contents API — `apps/web-platform/server/c4-render.ts:22-29`) | stays committed; one resolver script regenerates it on conflict, called from the three sync sites |

The merge driver, its installer, its `.gitattributes` routing, the guardrails sentinel, AC17
and five test suites exist only to protect the committed caches and retire with them. A new
ADR records the classification so the next generated file lands in the right column.

Measured baseline (2026-09-19): 42 of 71 first-parent `main` commits in 7 days touched
`INDEX.md`; regeneration takes 3.0 s on the operator host (7–11 s on slower hosts);
the fingerprint probe (`git ls-files -s` + `git status --porcelain -uall`, both scoped to
`knowledge-base`, hashed with `git hash-object`) takes ~60 ms.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| FR4: prose edits needed in `archive-kb`, `spec-templates`, `work`, `brainstorm` SKILL.md | Those four only *mention* the files as examples (`archive-kb/SKILL.md:12`, `spec-templates/SKILL.md:79-84`, `work/SKILL.md:76`, `brainstorm/SKILL.md:235,252`); staging/merge *instructions* live in `merge-pr/SKILL.md:164-204`, `ship/SKILL.md:2132,2300,2410-2416,2470-2474`, `compound/SKILL.md:301-320,516` | Sweep only the instruction sites |
| FR5: `rule-prune.sh` "runs the aggregator before reading" | It reads the committed file cold: `rule-prune.sh:55` `[[ -f "$METRICS" ]] \|\| { …; exit 2; }` (`:53` is the `METRICS=` assignment — insert the aggregator call between them) | Add an aggregator call ahead of the read, skipped when `RULE_METRICS_ROOT` is set; discard a partial write on non-zero exit |
| FR5: CI `rule-metrics-shape` keeps its skip path | Once untracked the file is never present in CI; the step (`ci.yml:269-290`) is dead machinery (ADR-151 class) | Delete the step |
| FR6: resolver lives in `sync-pr-behind.sh` + `pre-merge-rebase.sh` | ship Phase 7's DIRTY arm (`ship/SKILL.md:2299-2309`) inlines its own `git merge-tree` and never calls `sync-pr-behind.sh` | ONE script (`plugins/soleur/scripts/resolve-regenerable-conflicts.sh`), three call sites |
| FR6: a manifest of regenerable artifacts | One product artifact exists; a manifest is speculative generality (advisor consult) | Hardcode the single path→command pair in the resolver; ADR-230 says how a second one is added |
| FR3: "the SessionStart entry" | Two registries: `.claude/settings.json:48-50` and `.devin/config.json:22-25`, plus the audited row `.claude/hooks/devin-dispositions.tsv:111` (ADR-223) | Edit all three; `devin-matcher-parity.test.sh` stays green |
| FR4: delete `scripts/lib/kb-index-render.sh` | `kb_render_index()` (`:35-57`) is the whole row/domain renderer; `generate-kb-index.sh:41` sources it | Inline the header-less renderer, then delete the lib |
| FR7: transition is a documented `git rm` | An open PR's sync runs the **branch's** copy of `sync-pr-behind.sh` / `pre-merge-rebase.sh`, which predates this change, so no resolver rule can automate the first sync from the branch side | Keep the one-liner; no sweep script (both simplification reviewers cut it) |
| Brainstorm: regen needs `bunx likec4` | `regenerate-c4-model.sh:75` uses `npx -y likec4@1.50.0`, renders off-tree, validates on diagnostics + element count (`:81-105`), exits 1 on fault | Resolver relies on that exit code |
| FR1: `--out` kept, `--check` removed | `--check` (`generate-kb-index.sh:59-116`) self-recurses via `--out`; no production caller of `--out` | Remove `--check`, keep `--out` (the ensure script's atomic write uses it) |

## Research Insights

**Premise validation (Phase 0.6).** #8377 OPEN; #8370 OPEN; PR #8384 OPEN draft. ADR-210
§Alternatives rejected lists "Stop committing the generated artifacts entirely" as deferred on
scope, not merits. ADR-091 rejected committing raw incidents (privacy) and CI-zero; untracking
the *aggregate* contradicts neither. No cited symbol was missing on `origin/main`. Next free ADR
ordinal on `origin/main`: **ADR-230** (provisional — re-verify at ship). `git merge-tree
--write-tree` (git ≥ 2.38) is already what `sync-pr-behind.sh:63` and ship Phase 7 use, so the
resolver adds no new git-version precondition.

**Property List (Phase 0.6b).**

- P1 No feature branch carries a diff on a regenerable cache (`INDEX.md`, `kb-tags.txt`, `kb-categories.txt`, `rule-metrics.json`).
- P2 Every reader of the KB index reads a fresh, branch-local index (fixes the #8177 class).
- P3 A new checkout or session has an index without operator action, and never fails `bun install` to get one.
- P4 A `model.likec4.json` content conflict is resolved without a human, and a stale or empty model is never committed.
- P5 No machinery remains whose only referent is a committed cache.
- P6 The classification is recorded (ADR) so the next generated file is placed correctly.
- P7 `kb-search --tag` never dead-ends in a repo without the generator.

**Cut List (Phase 0.6b).**

- "Guard that blocks staging the caches off `main`" → P1 → `.gitignore` refuses `git add` without `-f`; a 10-line CI assertion (Guard 3) covers `-f`.
- "Keep `--check` as a main-only freshness gate" → no property (no committed copy) → removed.
- "Keep the `> Total files:` header" → no reader → removed with the render lib.
- "`merge=ours` on `rule-metrics.json`" (#6109 §1) → P1 → moot once untracked.
- "Regenerate `INDEX.md` on `main` post-merge" (issue's option 1) → P1/P2 → dominated (adds `main` advances under strict up-to-date, needs a bypass actor, leaves the branch index stale).
- "`scripts/regenerable-artifacts.tsv` manifest" → P4 → one member; hardcoded pair in the resolver (advisor consult).
- "Resolver auto-`git rm`s the caches on modify/delete" → transition → cannot run from the branch side on the first sync (see reconciliation row FR7); the documented one-liner covers it.
- "`--dry-run` on `ensure-kb-index.sh`" → no Property; only a test convenience, and the suite asserts freshness from the filesystem instead (both simplification reviewers).
- "A `find -newer` mtime probe beside the fingerprint" → P2 → the fingerprint already catches every tracked-content change including timestamp-preserving edits; two mechanisms for one property.
- "`regen-resolve` lock on the resolver" → P4 → the clean-tree/no-merge precondition plus git's `index.lock` already serialize it, fail-closed; no reviewer could name two call sites racing on one tree.
- "Distinct resolver exit 1 vs exit 2" → P4 → no call site branches on the difference; collapsed to 0 / non-zero with the diagnosis in stderr.
- "`scripts/transition-untrack-caches.sh`" → no Property (P1 is forward-looking) → one documented `git rm --cached` per affected branch.
- "Web-platform renders the C4 model at sync time instead of committing it" → P4 → a product-architecture change to the customer read path (`c4-render.ts` commits rendered bytes by design, #4976); out of scope, recorded in ADR-230 alternatives.

**Relevant files.**

- Generator: `scripts/generate-kb-index.sh` (`:40-41` sources lib; `:59-116` `--check`; `:158` `find` enumeration; `:230` render call), `scripts/lib/kb-index-render.sh:35-57`.
- Driver surface: `scripts/merge-kb-index.sh`, `scripts/install-kb-merge-driver.sh`, `.gitattributes:1-49`, `lefthook.yml:386-402` (+ comments `:404-424`), `.claude/hooks/guardrails.sh:431-433` (the kb-index `awk` clause) + the kb-index phrase in the deny message at `:445` — **NOT** the `:344-433` range an earlier draft named: the sentinel lives inside a SHARED `awk` program whose generic two-marker logic continues at `:435-439`, all within one `if` block opening at `:383`, so deleting that range orphans the generic guard, `.claude/settings.json:48-50`, `.devin/config.json:22-25`, `.claude/hooks/devin-dispositions.tsv:111`, `package.json:8`, `.github/CODEOWNERS:196-210`.
- Tests to delete: `plugins/soleur/test/{kb-index-merge-driver,kb-index-merge-driver-registration,merge-kb-index-driver-mutation,kb-index-check-guard-mutation,kb-index-freshness}.test.sh`. To edit: `plugins/soleur/test/generate-kb-index.test.sh`, `.claude/hooks/guardrails.test.sh:491-547`; only if they pin deleted names: `plugins/soleur/test/fixture-relative-assert.baseline.txt`, `plugins/soleur/test/lint-shell-trace-credential-refusal.test.sh`, `.claude/hooks/skill-context-queries.sh`.
- Readers: `plugins/soleur/skills/kb-search/SKILL.md:57-73,146-151,165`, `plugins/soleur/agents/engineering/research/learnings-researcher.md:13-20`, `.openhands/skills/learnings-researcher/SKILL.md:13-20`, `scripts/learning-retrieval-bench.sh:36,449,467`.
- rule-metrics: `scripts/rule-prune.sh:20-60` (`:53` assignment, `:55` the `-f` check), `:263`, `scripts/rule-metrics-aggregate.sh:39`, `.github/workflows/ci.yml:269-290,387-393`, `.github/workflows/rule-metrics-aggregate.yml`, `.github/actions/bot-pr-with-synthetic-checks/action.yml:161-164,234` (+ CHANGELOG/tests), `scripts/marketplace-manifest-validate.sh:32`, `scripts/required-checks.txt:80,135,167,227,252`, `plugins/soleur/skills/compound/SKILL.md:301-320`.
- Sync sites: `plugins/soleur/scripts/sync-pr-behind.sh:59-75`, `.claude/hooks/pre-merge-rebase.sh:327-345` (holds `rebase-main` via `acquire_lock`), `plugins/soleur/skills/ship/SKILL.md:2299-2309`.
- Test registration: `scripts/test-all.sh:77-89` `SUITE_GLOBS` (auto-globs `plugins/soleur/test/*.test.sh`, `plugins/soleur/scripts/*.test.sh`, `scripts/lib/*.test.sh`); bare `scripts/*.test.sh` needs an explicit `run_suite` line (`:1684`; e.g. `:1823`, `:2325`).
- `.gitignore:62-65` "Local state" block receives the new entries; `kb-domain-allowlist-guard.sh:51` and `.markdownlintignore:2` need no change.

**Institutional learnings applied.**

- `2026-09-19-a-generated-artifact-in-my-diff-made-every-landing-on-main-a-conflict.md` — names INDEX.md and rule-metrics.json as the DIRTY mechanism; cite in ADR-230.
- `2026-07-06-aggregator-must-run-where-its-gitignored-input-lives.md`, `2026-07-05-adr-renumber-must-sweep-planning-docs-and-scripts-glob-orphan.md`, `2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber.md` — a new `scripts/*.test.sh` is an orphan until `test-all.sh` registers it.
- `2026-06-11-posttooluse-hooks-that-write-files-need-atomic-restore-symlink-refusal-and-orphan-gate-exemption.md` — `mktemp` + `mv -f`, symlink refusal, re-run the source command for the write.
- `2026-06-18-likec4-exits-0-on-syntax-error-gate-on-diagnostic-not-just-element-count.md` — the regen script already gates on diagnostics + element count; the resolver trusts its exit code.
- ADR-027 / ADR-068 — supersession mechanics: retired ADR gets `Status: Superseded by ADR-NNN` plus a retained-parts note; superseding ADR carries `**Supersedes:**`.
- `2026-06-15-sessionstart-snapshot-ordering-and-committed-config-sanitization.md` — keep the ensure step last in the SessionStart array; it writes ignored paths only.
- `2026-06-06-lefthook-pre-push-push-files-and-dual-glob-depth1.md` — no new lefthook step; the deleted step's comments must be rewritten.
- `2026-09-18-every-defect-was-in-my-verification-not-the-feature.md` — deletion rounds sweep §Verification sections and ticked checkboxes that assert the deleted mechanism.
- ADR-178 — `pre-merge-rebase.sh` sources `acquire_lock`/`release_lock` from the shipped plugin; the resolver uses the same primitives.

**Conventions.** Bash suites use `test-helpers.sh`, `set -euo pipefail`, fixture repos under `mktemp -d`; markdownlint on every `.md`; `bun test` for TS; test files in `test/` siblings or `*.test.sh` beside the script for `plugins/soleur/scripts/`.

**Related issues.** #8116 (closed by #8151), #8370 (closes here), #8177, #7935, #6109 (its `merge=ours` item becomes moot), #2231 (see overlap section).

**External research:** skipped — strong local context; every mechanism is repo-internal bash/git.

**Advisor consult (Phase 4.5).** Accepted: drop the manifest; move the transition out of prose. Rejected with reason: "regenerate `model.likec4.json` on `main` only" and "web-platform renders at sync" — the first re-creates the `main`-advance cost for a ~1.2/day file with a bypass-actor dependency; the second changes the customer read path (out of scope, recorded as an ADR-230 alternative). The transition cannot be automated from the branch side (reconciliation row FR7), so it stayed a documented one-liner rather than becoming a resolver rule — and the sweep script the advisor's point implied was then cut by both simplification reviewers.

**SpecFlow (Phase 3).** 11 findings folded: per-file absence check before staleness (§1), symlink refusal (§1), temp cleanup (§1), set-atomicity accepted explicitly (Technical Considerations), timestamp-preserving edits caught by the content fingerprint (§1), resolver concurrency (§6 — answered by the precondition rather than a lock), push ownership (§6), modify/delete transition (§8), partial aggregate discard (Phase 3), `prepare` blast radius via `--soft` (§1, §3).

**Plan review (3-agent eng panel + standing checks).** `soleur:engineering:review:kieran-rails-reviewer` returned 5 findings, all re-derived and confirmed: a **P0** — the guardrails deletion range `:344-433` would have orphaned the generic conflict-marker guard, since the kb-index sentinel is 3 `awk` lines inside a shared program whose generic logic continues at `:435-439` in the same `if` block; `rule-prune.sh`'s `-f` check is `:55` not `:53`; AC5's original form returns 127 lines (reframed above); AC11's single multi-ref `git ls-tree` silently checks one ref (per-ref loop now); `git grep -c` on a no-match single file prints nothing rather than `0`. `soleur:engineering:review:dhh-rails-reviewer` + `soleur:engineering:review:code-simplicity-reviewer` converged independently on four cuts (`--dry-run`, the sweep script, the resolver lock, the exit 1/2 split) — all applied, all recorded in the Cut List. Both flagged the fingerprint; it survives because Guard 2 row 4 (a timestamp-preserving edit) is a correctness row mtime cannot cover, but its mtime half was cut so one mechanism serves the property, and AC2's wall-clock bar became an assertion that nothing was regenerated. One finding of the orchestrator's own, from re-deriving AC5: three live references to the deleted workflow (`weakness-miner.yml:4`, `infra/github/README.md:188`, `tests/scripts/test-audit-bot-codeql-coverage.sh:110`) were absent from Files to Edit, and the bot-workflow enumeration drops 2→1, which holds T6's `>= 1` floor with no slack (AC11c).

## Problem Statement / Motivation

PRs #8319 / #8321 / #8347 paid 7 / 11 / 3 forced resyncs (~6 h wall-clock each for the first
two) because every `main` advance made their `INDEX.md` conflict server-side. #8151 shortened
each resync; it did not remove the class, and the settle-then-admin-merge hatch cannot reach a
`DIRTY` PR. AC17 additionally reds on `refs/pull/N/merge` (#8370). `rule-metrics.json` is the same
class with counters (#8321 neutralised it by resetting to `main`'s blob); `model.likec4.json` is
a single-line JSON that conflicts whenever two PRs edit `.c4` sources.

## Proposed Solution

1. **`scripts/ensure-kb-index.sh [--soft]`** — regen-if-stale.
   - `[ -d knowledge-base ] || exit 0`.
   - Targets: `INDEX.md`, `kb-tags.txt`, `kb-categories.txt` under `knowledge-base/`, plus the
     gitignored stamp `knowledge-base/.kb-index.stamp`.
   - **Absent** when any target or the stamp is missing. **Stale** when the fingerprint differs
     from the stamp. Fingerprint = `git hash-object --stdin` over the concatenation of
     `git ls-files -s -- knowledge-base` and `git status --porcelain --untracked-files=all --
     knowledge-base` (blob ids for tracked content, paths for modified/untracked; ~60 ms;
     `git hash-object` rather than `sha1sum` so the script is portable to macOS hosts — no
     `sha1sum`, `date +%N`, `stat -c`, `readlink -f` or `timeout` anywhere in it). **One mechanism,
     not two:** an earlier draft paired this with a `find -newer` mtime probe; the fingerprint
     already catches every content change the index depends on, including a timestamp-preserving
     edit (`cp -p`, `rsync -a`, a `git checkout` of an older blob) that an mtime probe misses, so
     the mtime half was cut. The residue is an edit to a *gitignored* file under `knowledge-base/`
     (a local `private/` note): the fingerprint does not see it, no Property requires it, and the
     next tracked change picks it up. Outside a git checkout the fingerprint is empty, so the
     script regenerates on first call and then no-ops.
   - Regenerates via `generate-kb-index.sh --out "$tmp"` (`tmp` from `mktemp -d`, removed by an
     `EXIT` trap on every path), then `mv -f` each file into place and writes the stamp last.
     Per-file atomic; the three files are not swapped as a set (accepted — see Technical
     Considerations).
   - Refuses if any target is a symlink: `ERROR: refusing to write through symlink <path>`, exit 3.
   - Generator failure: `ERROR: generate-kb-index.sh failed (rc=<n>)`, exit 1, targets untouched.
   - `--soft`: always exit 0; failures become `WARN:` lines (for `prepare` and SessionStart).
   - On regeneration print `SOLEUR_KB_INDEX_REGEN reason=<absent|stale> ms=<n>`; when fresh print
     nothing (default) — silence is the fresh signal for callers.
2. **Untrack** the caches: `.gitignore` entries in the "Local state" block (the four paths plus
   `knowledge-base/.kb-index.stamp`); `git rm --cached`; lefthook `generate-kb-index` step deleted;
   generator loses `--check` and the count header (render lib inlined header-less, then deleted).
3. **Wire regeneration**: readers call `ensure-kb-index.sh` before reading (kb-search Phase 1 and
   Tier 1, learnings-researcher Step 0 + `.openhands` copy, bench when `INDEX_PATH` is default);
   `package.json` `prepare` → `bash scripts/ensure-kb-index.sh --soft` (Soleur's own root
   `package.json` only — customers never run it; covers `worktree-manager.sh feature` via
   `bun install`); `.claude/settings.json` + `.devin/config.json` SessionStart run it with
   `--soft` in the slot the driver installer vacates, last in the array; `devin-dispositions.tsv:111`
   re-pointed. `kb-search --tag/--category` with neither file nor generator present falls back to
   `git grep -il '^tags:.*<tag>' -- 'knowledge-base/**/*.md'` instead of `exit 1`.
4. **Retire** the driver surface and rewrite the prose that instructed merging/staging the caches.
5. **rule-metrics.json**: untrack; `rule-prune.sh` runs the aggregator first when
   `RULE_METRICS_ROOT` is unset, and on non-zero exit removes the (possibly partial) file and
   exits 2 with `aggregator failed (rc=<n>)`; compound stops staging it and its failure branch
   becomes `rm -f "$OUT"` instead of `git checkout -- "$OUT"`; delete `rule-metrics-aggregate.yml`,
   the CI shape step, the `ALLOWED_PATHS` entry and the comments that reason from it.
6. **`plugins/soleur/scripts/resolve-regenerable-conflicts.sh <base-ref>`** — one hardcoded
   pair: `knowledge-base/engineering/architecture/diagrams/model.likec4.json` →
   `bash scripts/regenerate-c4-model.sh` (a second pair is added by editing the array and the
   ADR, never by a manifest). Contract:
   - Precondition: clean tree, no merge in progress; otherwise non-zero, nothing touched.
   - **No dedicated lock.** A second concurrent run in the same worktree fails that precondition
     (or git's own `index.lock`) and exits non-zero without touching anything — that is the
     serialization, and it is fail-closed. An earlier draft added a `regen-resolve` lock; neither
     simplification reviewer could name two of the three call sites running concurrently on one
     tree, and a second lock beside the caller's `rebase-main` buys nothing the precondition does
     not already give.
   - `git merge-tree --write-tree <base> HEAD`: rc 0 = clean (nothing to do); rc 1 = conflicts
     (parse them); rc ≥ 2 = git error (print stderr). The script reads the value here because git
     gives three meanings, but it reports only two to its callers (below). Parse
     `CONFLICT (content): Merge conflict in <path>` (substring after the `Merge conflict in`
     prefix; paths with spaces preserved). Any other `CONFLICT (` kind (modify/delete, rename,
     add/add) or any non-resolvable path → non-zero, nothing touched.
   - Otherwise `git merge --no-ff --no-commit <base>`; for each resolvable path run its command
     (the regen script writes the tracked path itself, validates, exits non-zero on fault);
     refuse a symlink at the path; `git add <path>`; assert `git diff --name-only --diff-filter=U`
     is empty; `git commit --no-edit`; print `SOLEUR_REGEN_ON_CONFLICT paths=<csv> rc=0`; exit 0.
   - **Two outcomes only: `exit 0` = merge completed and committed; any non-zero = the caller falls
     back to its existing behaviour and the tree is byte-identical to entry.** On a regen failure
     or residual conflict the script `git merge --abort`s first and prints a distinct stderr line
     (`regen failed` vs `not applicable: <reason>`) — the *diagnosis* lives in that text, not in
     the exit code, because none of the three call sites branches differently on the two failure
     classes. An earlier draft split them into exit 1 / exit 2.
   - **Never pushes.** Callers own the push and its existing non-fast-forward handling
     (`sync-pr-behind.sh` exit 7; ship Phase 7 re-polls and re-syncs on the next iteration).
   - Call sites: `sync-pr-behind.sh` (on `merge-tree` failure, before its own `git merge`; rc 0 →
     push path), `pre-merge-rebase.sh` (after its failed merge is aborted and before the deny;
     rc 0 → continue as merged), ship Phase 7 DIRTY arm (before the poll exit; rc 0 → push, keep
     polling). No manifest → not applicable here (customer repos have no `regenerate-c4-model.sh`;
     the resolver exits non-zero when the command is absent).
7. **ADR-230** — "Generated artifacts: caches are untracked and regenerated on demand; products
   are committed and regenerated on conflict" — supersedes ADR-210, amends ADR-091.
8. **Transition**: one line in `merge-pr` and `ship` — an open branch that still tracks the caches
   hits a one-time modify/delete conflict on its next sync, resolved with
   `git rm --cached knowledge-base/INDEX.md knowledge-base/kb-tags.txt knowledge-base/kb-categories.txt knowledge-base/project/rule-metrics.json`.
   No sweep script: both simplification reviewers cut it, no Property requires it (P1 is about
   branches going forward), and a bespoke multi-branch mutation tool is a worse answer than one
   `git rm --cached` per branch on a conflict its owner is already resolving.

## Technical Considerations

- **Why a fingerprint and not only mtimes.** A `cp -p`/`rsync -a`/`git checkout` of an older
  blob can leave an eligible file older than the stamp; the blob-id fingerprint catches content
  changes to tracked files and path changes for untracked files; the mtime probe catches edits to
  ignored files (e.g. a local `knowledge-base/private/`). A change under `archive/` triggers a
  redundant 3 s regen — accepted.
- **Enumeration stays `find`.** The generator indexes a local `knowledge-base/private/`
  (gitignored, `.gitignore:6,65`). That was a latent leak into the committed public file;
  untracked, it becomes a feature. No enumeration change.
- **Set-atomicity accepted.** Two sessions regenerating in one worktree race on `mv -f`; a
  reader may see `INDEX.md` from generation A beside `kb-tags.txt` from generation B. Both derive
  from near-identical trees and are consumed independently (rows vs. facet validation); the next
  read regenerates. Not worth a lock.
- **Resolver on customer repos.** `sync-pr-behind.sh` ships in the plugin; `regenerate-c4-model.sh`
  is Soleur-only. Absent command → non-zero → callers keep today's abort-and-surface behaviour.
- **`prepare` blast radius.** `--soft` guarantees `bun install` never fails on the index; a
  foreign or malformed `knowledge-base/` yields `WARN:` lines only.
- **CI**: no workflow reads the four files; `c4-count-parity.test.sh` may move if
  `model.c4` embeds a workflow count that deleting `rule-metrics-aggregate.yml` changes — run it
  and update the edge prose in the same commit if so.
- **Rollback.** `git revert` the PR, then `bash scripts/generate-kb-index.sh && git add
  knowledge-base/INDEX.md knowledge-base/kb-*.txt`; the generator is untouched.

## User-Brand Impact

- **If this lands broken, the user experiences:** an agent (`kb-search`, `learnings-researcher`) that reads an absent or stale local index and reports "no prior art", or a PR sync that regenerates `model.likec4.json` from broken `.c4` sources and commits an empty model that the web-platform C4 viewer then renders.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing new — the files are derived from content already in the same repository; untracking removes a latent path by which a gitignored `knowledge-base/private/` title would have reached the committed public index.
- **Brand-survival threshold:** `single-user incident` (inherited from brainstorm Phase 0.1; CPO reviewed the brainstorm — carry-forward sign-off; `soleur:engineering:review:user-impact-reviewer` runs at review).

## Observability

```yaml
liveness_signal:
  what:            per-run stdout markers SOLEUR_KB_INDEX_REGEN / SOLEUR_REGEN_ON_CONFLICT (layer 7, cli-stdout-artifact, ADR-171); on main, c4-model-freshness.test.sh + main-health-monitor.yml assert the committed model matches its sources
  cadence:         per invocation (every reader, every sync); main-health-monitor on its existing schedule
  alert_target:    the invoking agent/operator terminal; pre-merge-rebase.sh emits a hook incident (emit_incident) on deny; main-health-monitor's existing alert route for a red c4 freshness
  configured_in:   scripts/ensure-kb-index.sh, plugins/soleur/scripts/resolve-regenerable-conflicts.sh, .github/workflows/main-health-monitor.yml

error_reporting:
  destination:     stderr + non-zero exit surfaced by the caller (sync-pr-behind exit 6/7, pre-merge-rebase deny JSON, ship Phase 7 poll exit); no Soleur-side sink for self-hosted CLI runs (ADR-171)
  fail_loud:       "SOLEUR_REGEN_ON_CONFLICT paths=... rc=1" followed by the caller's existing "merge conflict — manual resolution required"; ensure-kb-index prints "ERROR: generate-kb-index.sh failed (rc=N)" and exits 1 (or "WARN:" under --soft)

failure_modes:
  - mode:          generator fails so no index is produced
    detection:     ensure-kb-index.sh exit 1 + ERROR line (WARN under --soft); readers continue with content grep and say the index was unavailable
    alert_route:   invoking session terminal
  - mode:          staleness probe misses a change (index silently stale)
    detection:     scripts/ensure-kb-index.test.sh rows (add/delete/rename/timestamp-preserving edit → regen); kb-search Tier 2 content grep still covers new files
    alert_route:   CI test-scripts shard
  - mode:          resolver regenerates from broken .c4 sources
    detection:     regenerate-c4-model.sh exit 1 (diagnostic grep + element count) → resolver non-zero, merge aborted, nothing committed; c4-model-freshness on main as backstop
    alert_route:   caller surfaces; main-health-monitor alert on main
  - mode:          a cache path gets force-added and tracked again
    detection:     plugins/soleur/test/kb-caches-untracked.test.sh (Guard 3) reds on `git ls-files` listing any of the four paths
    alert_route:   CI test-scripts shard
  - mode:          partial rule-metrics.json left by a failed aggregator
    detection:     rule-prune.sh removes it and exits 2 "aggregator failed"; compound's failure branch rm -f's it
    alert_route:   invoking session terminal

logs:
  where:           session stdout (markers); hook incidents in .claude/.rule-incidents.jsonl (gitignored, rotated)
  retention:       session transcript lifetime; incidents log rotation per lib/log-rotation.sh

discoverability_test:
  command:         git check-ignore knowledge-base/INDEX.md knowledge-base/kb-tags.txt knowledge-base/kb-categories.txt knowledge-base/project/rule-metrics.json knowledge-base/.kb-index.stamp
  expected_output: the five paths, one per line (each is ignored); exit 0
```

## Guard Contract

### Guard 1 — resolve-regenerable-conflicts fail-closed

**Property.** The resolver commits a merge only when every conflicted path is a content conflict on a resolvable path and every regen command exited 0 and left no conflict; on any other input the tree is byte-identical to entry and nothing is committed.

**Assembly.** One script, `plugins/soleur/scripts/resolve-regenerable-conflicts.sh`, is the chokepoint; its inputs are `git merge-tree --write-tree <base> HEAD` and the in-script resolvable array; rows 1/3/4/6/7/8 are one property (*fail closed on anything that is not the exact happy path*) and the suite implements them as one table-driven loop asserting `rc != 0` AND a byte-identical tree, not six hand-written cases; its three call sites are `plugins/soleur/scripts/sync-pr-behind.sh` (before `git merge`), `.claude/hooks/pre-merge-rebase.sh` (after the failed merge is aborted, before the deny), and the ship Phase 7 DIRTY arm in `plugins/soleur/skills/ship/SKILL.md`. Any DIRTY-handling path that merges `origin/main` without going through this script is a fourth injection site and a defect.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture conflicts on the resolvable path AND `README.md` | RED — non-zero, `git status --porcelain` empty, no new commit |
| 2 | Stub regen command exits non-zero | RED — non-zero, merge aborted, no new commit, `regen failed` on stderr |
| 3 | Two resolvable paths both conflicting (array extended in the fixture); stub regenerates only the first | RED — non-zero (second path still conflicted), no commit |
| 4 | Resolvable array emptied (resolver's own dispatch) | RED — non-zero; a run that resolved 0 paths never returns 0 |
| 5 | Regen command invoked BEFORE `git merge` instead of after (order) | RED — the stub writes the merged inputs it saw; test asserts the committed artifact equals a regen of the merged tree, not of HEAD |
| 6 | Conflict kind is modify/delete on the resolvable path | RED — non-zero (non-content conflict is fail-closed) |
| 7 | Resolvable path is a symlink | RED — non-zero, nothing written through the link |
| 8 | Merge already in progress at entry (`MERGE_HEAD` exists) | RED — non-zero, untouched |
| H1 | Suite harness: remove the resolver invocation from the fixture driver | RED — the "commit exists" assertion fails |
| P1 | Must-PASS non-canonical: base ref given as a SHA rather than `origin/main` | PASS — exit 0, artifact regenerated |

### Guard 2 — ensure-kb-index freshness

**Property.** After `ensure-kb-index.sh` returns 0, `INDEX.md` lists exactly the eligible KB files present on disk (ADR-174 predicate) — it regenerated if anything eligible changed since the last generation and did nothing otherwise.

**Assembly.** The script is the chokepoint; its callers are `kb-search` (Phase 1 and Tier 1), `learnings-researcher` (+ `.openhands` copy), `learning-retrieval-bench.sh`, `package.json` `prepare`, `.claude/settings.json` SessionStart, `.devin/config.json` SessionStart. A reader that greps `INDEX.md` without calling the script first is a defect.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a `.md` under `knowledge-base/` after the last generation | RED if the row is absent after the call |
| 2 | Delete an indexed `.md` (only the directory mtime moves) | RED if the row survives |
| 3 | Rename an indexed `.md` | RED if the old row survives or the new one is absent |
| 4 | Change a tracked file's title with `touch -d '2 years ago'` after the edit (timestamp-preserving) | RED if the old title survives — this row is why the fingerprint exists and an mtime probe does not suffice |
| 5 | Remove `kb-tags.txt` only, leave `INDEX.md` fresh | RED if the file is not recreated with `reason=absent` |
| 6 | Generator stubbed to exit 1 (own dispatch) | RED — exit 1, previous three files byte-identical, temp dir removed |
| 7 | Script stubbed to a no-op `exit 0` | RED — row-present assertion fails |
| 8 | `INDEX.md` replaced by a symlink | RED — exit 3, link target untouched |
| H1 | Suite harness: drop the fixture edit that makes the index stale | RED — the "regenerated" assertion cannot pass on a fresh fixture |
| P1 | Must-PASS non-canonical: index fresh, `knowledge-base/archive/` touched | PASS — exit 0 (a redundant regen is allowed, not required) |
| P2 | Must-PASS: `--soft` with the generator stubbed to fail | PASS — exit 0, `WARN:` line, targets untouched |

### Guard 3 — caches stay untracked

**Property.** None of the five cache paths is tracked on the branch, and each is matched by `.gitignore`.

**Assembly.** `plugins/soleur/test/kb-caches-untracked.test.sh` asserts over the fixed list; `.gitignore` is the mechanism; `git ls-files` + `git check-ignore` are the oracle.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove one `.gitignore` entry | RED |
| 2 | `git add -f knowledge-base/INDEX.md` in the fixture | RED |
| 3 | Add a sixth path to the list without a `.gitignore` line (second member) | RED |
| 4 | Empty the path list (own dispatch) | RED — the suite asserts the list has 5 entries |

## Architecture Decision (ADR/C4)

### ADR

Create **ADR-230 — Generated artifacts: caches are untracked and regenerated on demand; products are committed and regenerated on conflict** via `soleur:architecture` (ordinal provisional; ship's ADR-Ordinal Collision Gate re-verifies). Decision: classify every generated file as a *cache* (derivable from the tree or from gitignored local data → untracked, regenerated by a staleness-checked script at read/start time) or a *product* (read by a consumer that cannot regenerate it → committed, regenerated on conflict by `resolve-regenerable-conflicts.sh`, whose resolvable set is edited with the ADR, not a manifest); no generated artifact is resolved by a merge driver, because the server-side merge cannot run one. **Supersedes ADR-210** (status → `Superseded by ADR-230`; note that its regeneration-diff reasoning and the ADR-174 predicate remain valid history). **Amends ADR-091**: the aggregate is no longer committed; the "committed metric reflects the committing worktree" consequence and the deferred "read-only scheduled canary on the committed file" are retired; the local producer model is unchanged. Alternatives table: option 1 (regen on `main`), count-header-only removal, driver + resolver for INDEX.md, untracking `model.likec4.json`, web-platform rendering at sync time, a regenerable-artifacts manifest.

### C4 views

No C4 impact. Checked all three model files (`model.c4`, `views.c4`, `spec.c4`): (a) external human actors — none change; (b) external systems — none added or removed (GitHub, the likec4 CLI are unchanged edges); (c) containers/data stores — the KB index was never a modelled store; `model.likec4.json` remains the modelled C4 artifact; (d) access relationships — none change. The `hooks` container description (`model.c4:108`) enumerates hook registries and `pre-merge-rebase.sh`'s primitive sourcing, not the SessionStart driver installer, so it stays true. Deleting `rule-metrics-aggregate.yml` may move a workflow count embedded in edge prose — AC12 requires `plugins/soleur/test/c4-count-parity.test.sh` green, with the edge prose updated in the same commit if it moves.

### Sequencing

The ADR describes the target state and ships in this PR (no soak).

## Implementation Phases

### Phase 1 — Regenerate on demand (P2, P3, P7)

- Create `scripts/ensure-kb-index.sh` (contract in Proposed Solution §1) and `scripts/ensure-kb-index.test.sh` implementing Guard 2; register the suite with a `run_suite` line in `scripts/test-all.sh` beside `:2325`.
- `scripts/generate-kb-index.sh`: inline `kb_render_index` without the header lines at `:230`; delete the `--check` arm (`:59-116`, `:20-23`, `:47`); keep `--out`; delete `scripts/lib/kb-index-render.sh`.
- `plugins/soleur/test/generate-kb-index.test.sh`: drop `--check` cases; assert no `> Total files:` line; keep row/facet cases.
- Readers: `kb-search/SKILL.md` Phase 1 (`:57-73`) and Tier 1 (`:146-151`); `learnings-researcher.md:13-20`; `.openhands/skills/learnings-researcher/SKILL.md:13-20`; `learning-retrieval-bench.sh:36`.
- `package.json:8` `prepare` → `bash scripts/ensure-kb-index.sh --soft`; `.claude/settings.json:48-50` and `.devin/config.json:22-25` → same, last in the array; `.claude/hooks/devin-dispositions.tsv:111` → re-point; run `devin-matcher-parity.test.sh`.
- No extra `worktree-manager.sh` call is needed: `bun install --frozen-lockfile` and `--frozen-lockfile --cwd <dir>` (the form `worktree-manager.sh:1626` runs) both execute the root `prepare` script — measured 2026-09-19 on bun 1.4.2 in a `mktemp -d` fixture whose `prepare` touched a marker file (`fired=yes`, rc 0 for both forms). Re-derive if bun's major version moves.

### Phase 2 — Untrack the caches and retire the driver (P1, P5)

- `.gitignore:62-65` block: add the four cache paths and `knowledge-base/.kb-index.stamp`; `git rm --cached` the four tracked files.
- Delete: `scripts/merge-kb-index.sh`, `scripts/install-kb-merge-driver.sh`, the five suites, `.gitattributes:1-49` kb block, `lefthook.yml:386-402` step (rewrite `:404-424` comments), `guardrails.sh:431-433` (the three kb-index `awk` lines) + the kb-index clause of the deny message at `:445` — leave `:383-429` and `:435-450` intact (the generic multi-marker check shares that `if` block and `awk` program), `guardrails.test.sh:491-547`, CODEOWNERS `:204-209`.
- Edit if they pin deleted names: `fixture-relative-assert.baseline.txt`, `lint-shell-trace-credential-refusal.test.sh`, `skill-context-queries.sh`.
- Add `plugins/soleur/test/kb-caches-untracked.test.sh` (Guard 3; auto-globbed).
- Prose: `merge-pr/SKILL.md:164-204` → transition note + resolver pointer; `ship/SKILL.md:2132,2410-2416,2470-2474` → drop the caches from the "regenerable index" hatch trigger set, add the transition note; `compound/SKILL.md:516` → drop the regen step.

### Phase 3 — rule-metrics.json (P1)

- `scripts/rule-prune.sh` — insert between the `METRICS=` assignment (`:53`) and the `-f` check (`:55`): when `RULE_METRICS_ROOT` is unset and `scripts/rule-metrics-aggregate.sh` is executable, run it (output to a temp log); non-zero → `rm -f "$METRICS"`, print `aggregator failed (rc=<n>)`, exit 2; then the existing `-f` check. Add a suite case (existing `rule-prune` test or new) for both branches.
- `plugins/soleur/skills/compound/SKILL.md:301-320` → keep the run + hint; remove the `git add`/staged lines and the "committed" wording; failure branch `rm -f "$OUT"`.
- Delete `.github/workflows/rule-metrics-aggregate.yml`; remove `ci.yml:269-290`; remove `action.yml:163` from `ALLOWED_PATHS`, update `:234` and the action's CHANGELOG; fix the reasoning comments at `ci.yml:387-393`, `scripts/marketplace-manifest-validate.sh:32`, `scripts/required-checks.txt:80,135,167,227,252`.
- Run `plugins/soleur/test/c4-count-parity.test.sh`; update the `model.c4` edge prose in the same commit if a count moved.

### Phase 4 — Regenerate on conflict (P4)

- Create `plugins/soleur/scripts/resolve-regenerable-conflicts.sh` (contract in Proposed Solution §6) and `plugins/soleur/scripts/resolve-regenerable-conflicts.test.sh` (auto-globbed) implementing Guard 1 with a stub regen command, a two-branch fixture repo, and the array overridable via `RESOLVABLE_OVERRIDE` for rows 3–4.
- Call sites: `sync-pr-behind.sh:63-68` → on `merge-tree` failure call the resolver; rc 0 → `git push` path; else existing exit 6. `pre-merge-rebase.sh:333-345` → after `merge --abort`, call the resolver; rc 0 → continue as merged; else existing deny. `ship/SKILL.md:2299-2309` → on unclean `merge-tree`, run the resolver; rc 0 → push and keep polling; else existing exit. Extend `sync-pr-behind`'s suite (create `plugins/soleur/scripts/sync-pr-behind.test.sh` if absent) with the rc-0 and rc-2 paths.

### Phase 5 — Decision record and sweeps (P6)

- ADR-230 via `soleur:architecture`; ADR-210 → superseded; ADR-091 amended (§Consequences + §Deferred).
- Sweep §Verification sections and ticked checkboxes that assert the deleted mechanism (ADR-210 §Verification gets the supersession note rather than a rewrite).
- Zero-hit sweeps (AC5).
- Comment on #6109 at ship: §1's `merge=ours` item is moot; the rest unchanged.

## Files to Create

- `scripts/ensure-kb-index.sh`, `scripts/ensure-kb-index.test.sh`
- `plugins/soleur/scripts/resolve-regenerable-conflicts.sh`, `plugins/soleur/scripts/resolve-regenerable-conflicts.test.sh`
- `plugins/soleur/scripts/sync-pr-behind.test.sh` (if no suite exists)
- `plugins/soleur/test/kb-caches-untracked.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-230-generated-artifacts-caches-untracked-products-regenerated-on-conflict.md`

## Files to Edit

- `.gitignore`, `.gitattributes`, `lefthook.yml`, `package.json`, `.claude/settings.json`, `.devin/config.json`, `.claude/hooks/devin-dispositions.tsv`, `.github/CODEOWNERS`
- `scripts/generate-kb-index.sh`, `scripts/rule-prune.sh` (+ its suite), `scripts/learning-retrieval-bench.sh`, `scripts/test-all.sh`, `scripts/marketplace-manifest-validate.sh`, `scripts/required-checks.txt`
- `.claude/hooks/guardrails.sh`, `.claude/hooks/guardrails.test.sh`, `.claude/hooks/pre-merge-rebase.sh`, `.claude/hooks/skill-context-queries.sh` (only if it names the driver)
- `plugins/soleur/scripts/sync-pr-behind.sh`
- `plugins/soleur/skills/kb-search/SKILL.md`, `plugins/soleur/skills/merge-pr/SKILL.md`, `plugins/soleur/skills/ship/SKILL.md`, `plugins/soleur/skills/compound/SKILL.md`
- `plugins/soleur/agents/engineering/research/learnings-researcher.md`, `.openhands/skills/learnings-researcher/SKILL.md`
- `plugins/soleur/test/generate-kb-index.test.sh`; `plugins/soleur/test/fixture-relative-assert.baseline.txt` and `plugins/soleur/test/lint-shell-trace-credential-refusal.test.sh` (only if they pin deleted names)
- `.github/workflows/ci.yml`, `.github/actions/bot-pr-with-synthetic-checks/action.yml` (+ its `CHANGELOG.md:45,99`)
- Live references to the deleted workflow found by the AC5 sweep, all comment/prose: `.github/workflows/weakness-miner.yml:4` (cites it as the precedent path), `infra/github/README.md:188` (merge-queue canary step: "confirm a `rule-metrics-aggregate.yml` bot PR flows through" — repoint at `weakness-miner.yml`), `tests/scripts/test-audit-bot-codeql-coverage.sh:110` (T6's comment "Only rule-metrics-aggregate.yml remains" — already false, `weakness-miner.yml` is also enumerated; correct it in the same edit)
- `knowledge-base/engineering/architecture/decisions/ADR-210-*.md`, `ADR-091-*.md`; `knowledge-base/engineering/architecture/diagrams/model.c4` only if a count moves

## Files to Delete

- `scripts/merge-kb-index.sh`, `scripts/install-kb-merge-driver.sh`, `scripts/lib/kb-index-render.sh`
- `plugins/soleur/test/kb-index-merge-driver.test.sh`, `kb-index-merge-driver-registration.test.sh`, `merge-kb-index-driver-mutation.test.sh`, `kb-index-check-guard-mutation.test.sh`, `kb-index-freshness.test.sh`
- `.github/workflows/rule-metrics-aggregate.yml`
- Tracked copies of `knowledge-base/INDEX.md`, `knowledge-base/kb-tags.txt`, `knowledge-base/kb-categories.txt`, `knowledge-base/project/rule-metrics.json` (`git rm --cached`)

## Open Code-Review Overlap

- #2231 `perf(kb-search): skip past frontmatter with nextfile in facet extraction` touches `scripts/generate-kb-index.sh` — **Acknowledge.** The generator persists and is now called more often, so the finding stays relevant and independent; not folded, to keep this PR a retirement rather than an optimisation. Left open.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Issue's option 1: keep committed, regenerate on `main` post-merge | Every regen commit is a `main` advance that re-`BEHIND`s every open PR under `strict_required_status_checks_policy = true` (~6/day), needs a GitHub-App `bypass_mode = always` actor or per-merge bot PRs, spends CI runs, and leaves the branch-local index stale (#8177 shape). |
| Drop only the `> Total files:` header | Adjacent same-day row inserts still conflict; the driver and AC17 remain. |
| Keep the driver and add the resolver for `INDEX.md` too | Every branch conflicts with every other on `main`; automating resolution keeps the DIRTY state and the check restarts. |
| Untrack `model.likec4.json` as well | The web-platform C4 viewer reads it from synced repos without the compiler; its write path commits rendered bytes by design (#4976). |
| Web-platform renders the C4 model at sync time | Changes the customer read path in `apps/web-platform/server/` — a product-architecture decision outside this PR; recorded in ADR-230. |
| Regenerate `model.likec4.json` on `main` only | Same `main`-advance and bypass-actor cost as option 1, for a file whose conflicts are rare (concurrent `.c4` edits only). |
| A `regenerable-artifacts.tsv` manifest | One member; a manifest invites re-tracking regenerable files and adds a parse surface. |
| Resolver auto-`git rm`s the caches on modify/delete | The first sync of an open PR runs the branch's pre-change scripts; the rule would never execute where it is needed. |
| Regenerate caches in a lefthook step without staging | Readers would still see a pre-commit snapshot; the on-read probe is cheaper and covers cloud harnesses without hooks. |

## Acceptance Criteria

- [ ] AC1 `git ls-files` on the branch lists none of the four cache paths; `git check-ignore` matches all five paths (Guard 3 suite green).
- [ ] AC2 `bash scripts/ensure-kb-index.sh` on a checkout with no index produces the three files plus the stamp and prints `SOLEUR_KB_INDEX_REGEN reason=absent`; a second call prints nothing and **regenerates nothing** (the suite asserts the three files' mtimes are unchanged — the property, not a wall-clock number); `--soft` with a failing generator exits 0 with a `WARN:` line; a symlinked target exits non-zero with nothing written through the link.
- [ ] AC3 `scripts/ensure-kb-index.test.sh` is registered in `scripts/test-all.sh` (`run_suite` line) and green; it implements Guard 2 rows 1–8, H1, P1, P2.
- [ ] AC4 `generate-kb-index.sh --check` is gone (`exit 2 unknown argument`); output has no `> Total files:` line; `scripts/lib/kb-index-render.sh` does not exist; `generate-kb-index.test.sh` green.
- [ ] AC5 The retirement sweep is complete over **live** surfaces. Run:

  ```bash
  git grep -n -e 'merge=kb-index' -e install-kb-merge-driver -e merge-kb-index.sh \
    -e kb-index-render -e 'Total files:' -e rule-metrics-aggregate.yml \
    -- ':!**/archive/**' ':!knowledge-base/project/learnings/**' \
       ':!knowledge-base/engineering/architecture/decisions/**' \
       ':!knowledge-base/project/plans/**' ':!knowledge-base/project/specs/**' \
       ':!knowledge-base/project/brainstorms/**'
  ```

  Expected: **zero hits.** The six exclusions are the historical record (archive, learnings, ADRs,
  plans, specs, brainstorms) which must keep citing the retired mechanism. Measured on the
  pre-change tree this command returns 127 lines across 30 files, and every one of those 30 is in
  this plan's Files-to-Edit/Delete set — that equivalence is the AC. An earlier draft excluded only
  `specs/feat-kb-index-untrack/**` and asserted zero; that form returns unrelated sibling-spec prose
  and could never be green.
- [ ] AC6 `package.json` `prepare`, `.claude/settings.json` SessionStart and `.devin/config.json` SessionStart run `scripts/ensure-kb-index.sh --soft`; `devin-matcher-parity.test.sh` green; `bash scripts/ensure-kb-index.sh` exits 0 in a directory without `knowledge-base/`.
- [ ] AC7 `kb-search/SKILL.md`, `learnings-researcher.md` and its `.openhands` copy instruct running `ensure-kb-index.sh` before reading; `kb-search --tag` with neither file nor generator present documents the frontmatter-grep fallback and no `exit 1`.
- [ ] AC7b Reader census (not a name list): every file under `plugins/soleur/skills`, `plugins/soleur/agents`, `.openhands`, `scripts` that matches `git grep -l 'knowledge-base/INDEX.md\|kb-tags.txt'` and instructs *reading* it also matches `ensure-kb-index` — enumerate the census in the PR body with each file's disposition (reader-wired / example-mention-only).
- [ ] AC9b Call-site census: `git grep -ln 'merge-tree --write-tree\|git merge origin/main' -- plugins/soleur/scripts .claude/hooks plugins/soleur/skills/ship` returns exactly the three resolver call sites (plus the resolver itself); any other hit is a fourth DIRTY-handling path and must either call the resolver or be justified in the PR body.
- [ ] AC8 `scripts/rule-prune.sh` runs the aggregator before its `-f` check when `RULE_METRICS_ROOT` is unset, and removes the file + exits 2 on aggregator failure (both suite cases green); `compound/SKILL.md` no longer stages `rule-metrics.json`; `rule-metrics-aggregate.yml` deleted; `ci.yml` has no `rule-metrics-shape` step; `action.yml` `ALLOWED_PATHS` has one entry and the comments that reasoned from two are updated.
- [ ] AC9 `plugins/soleur/scripts/resolve-regenerable-conflicts.test.sh` green, implementing Guard 1 rows 1–8, H1, P1; `sync-pr-behind.sh`, `pre-merge-rebase.sh` and ship Phase 7's DIRTY arm each call the resolver (three `git grep -n resolve-regenerable-conflicts` hits in those files); the resolver never pushes (`git grep -c 'git push' plugins/soleur/scripts/resolve-regenerable-conflicts.sh` prints nothing and exits 1 — `grep -c` on a no-match single file emits no `0`).
- [ ] AC10 In a fixture where only `model.likec4.json` conflicts, `bash plugins/soleur/scripts/sync-pr-behind.sh` completes the merge with a regenerated model and pushes; with a non-resolvable conflict it exits 6 with a clean tree; with a rejected push after a resolved merge it exits 7 and the merge commit remains local.
- [ ] AC11 `ADR-230-*.md` exists with `Supersedes: ADR-210`; ADR-210 status reads `Superseded by ADR-230`; ADR-091 carries a dated amendment; `check-adr-ordinals.sh` green; the ordinal was probed across every pushed ref at work time and again immediately before merge, with a **per-ref loop** — `git ls-tree` takes exactly ONE tree-ish and silently treats extra refs as (non-matching) pathspecs, so a single multi-ref invocation checks one arbitrary ref and reports clean:

  ```bash
  git fetch --all --prune
  for r in $(git for-each-ref --format='%(refname)' refs/remotes/origin); do
    git ls-tree -r --name-only "$r" -- knowledge-base/engineering/architecture/decisions/
  done | grep 'ADR-230-' | sort -u
  ```

  Expected: only this PR's own filename (or nothing, before it is committed).
- [ ] AC11b Every `knowledge-base/…​.md` path cited in this plan, the ADR and the learning exists: `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | sort -u | xargs -I{} bash -c '[[ -f "{}" ]] || echo "BROKEN: {}"'` prints nothing.
- [ ] AC11c Deleting `rule-metrics-aggregate.yml` leaves the bot-workflow enumeration non-empty: `AUDIT_ENUMERATE_ONLY=1 bash scripts/audit-bot-codeql-coverage.sh | wc -l` ≥ 1 (measured pre-change: 2 — `rule-metrics-aggregate.yml` + `weakness-miner.yml`, so the post-change count is 1 and `tests/scripts/test-audit-bot-codeql-coverage.sh` T6's `>= 1` floor holds with no slack); that suite is green.
- [ ] AC12 `guardrails.test.sh`, `c4-count-parity.test.sh`, `c4-model-freshness.test.sh`, `devin-matcher-parity.test.sh`, `rule-metrics-aggregate.test.sh` green; `bash scripts/test-all.sh --enumerate-commands all` lists no deleted suite and does list `ensure-kb-index`.
- [ ] AC13 `merge-pr/SKILL.md` and `ship/SKILL.md` carry the one-line transition note (naming the exact `git rm --cached` command); ship's hatch trigger prose no longer lists the caches.
- [ ] AC14 Every `.md` touched passes markdownlint; `bun test` (plugin) green.

## Test Scenarios

- Given a fresh clone with no `INDEX.md`, when `kb-search` runs, then `ensure-kb-index.sh` regenerates first and Tier 1 finds rows (AC2, AC7).
- Given a branch that adds a new learning file under `knowledge-base/project/learnings/` after the last generation, when `ensure-kb-index.sh` runs, then the new row is present (Guard 2 row 1).
- Given a tracked file's title edited and its mtime reset to the past, when `ensure-kb-index.sh` runs, then the new title is present (Guard 2 row 4).
- Given `INDEX.md` fresh, when `ensure-kb-index.sh` runs, then no file is rewritten and no marker is printed (AC2).
- Given the generator stubbed to fail, when `ensure-kb-index.sh` runs, then exit 1, the previous files are byte-identical, and the temp dir is gone (Guard 2 row 6).
- Given a fixture where `main` and the branch both edited `model.c4` so `model.likec4.json` conflicts, when `sync-pr-behind.sh` runs with a stub regen, then the merge commit exists, the artifact equals the stub's post-merge output, and the marker prints `rc=0` (Guard 1 rows 5, P1; AC10).
- Given the same fixture plus a conflicting `README.md`, when the resolver runs, then non-zero, no commit, `git status --porcelain` empty (Guard 1 row 1).
- Given the stub regen exits non-zero, when the resolver runs, then non-zero, merge aborted, tree identical (Guard 1 row 2).
- Given a merge already in progress, when the resolver runs, then non-zero and `MERGE_HEAD` still exists (Guard 1 row 8).
- Given a customer repo with no `regenerate-c4-model.sh`, when `sync-pr-behind.sh` hits a conflict, then behaviour is unchanged (exit 6, surfaced paths).
- Given `rule-metrics.json` absent and `RULE_METRICS_ROOT` unset, when `rule-prune.sh` runs, then the aggregator runs first and the read succeeds; given the aggregator exits 1 after a partial write, then the file is removed and `rule-prune.sh` exits 2 (AC8).
- Given `.gitignore` missing one cache entry, when `kb-caches-untracked.test.sh` runs, then RED (Guard 3 row 1).
- Regression: a branch that still carries `INDEX.md` merges `origin/main` → modify/delete conflict → the documented `git rm --cached` resolves it (AC13).

## Success Metrics

- Zero `INDEX.md` / `rule-metrics.json` conflicts on any PR sync in the 7 days after merge (`git log --first-parent main -- knowledge-base/INDEX.md` shows no commits after the merge; ship Phase 7 logs show no DIRTY exits naming the caches).
- `kb-search --tag` on a branch finds a learning written on that branch (the #8177 probe) in the first session after merge.
- No `test-scripts` shard failure on `refs/pull/N/merge` attributable to index freshness (#8370 class).

## Dependencies & Risks

- ~20 open PRs carry the caches; each hits a one-time modify/delete conflict on its next sync, resolved by the documented `git rm --cached`. Documented, low risk.
- `c4-count-parity` may move when a workflow is deleted — handled in Phase 3.
- Resolver depends on `npx -y likec4@1.50.0` being reachable where the sync runs (operator host: yes; hosted ship clone: verify at work time — if absent the regen exits 1 and the caller surfaces, never a silent commit).
- ADR-230 ordinal may collide with a sibling PR — ship's collision gate renumbers; sweep the plan and tasks for the old ordinal.
- Push-after-resolve can be rejected when `main` moves again — pre-existing strict-up-to-date behaviour, handled by the callers' existing paths; out of scope.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from brainstorm `## Domain Assessments`)

### Engineering

**Status:** reviewed
**Assessment:** CTO sized the KB-index half at ~one day; retirement inventory adopted; the staleness probe was upgraded from mtimes to a content fingerprint after SpecFlow; `prepare` wiring covers new worktrees; latent `private/` leak closes. Learnings research: regen 7–11 s on slow hosts (probe-gated regen is load-bearing); lazy regen must precede the read. Sibling artifacts folded in at operator direction; the advisor consult cut the manifest and reframed the transition.

### Legal

**Status:** reviewed
**Assessment:** No legal gate — no new collection, transmission or processing; gdpr-gate at Phase 2.7: 0 regulated paths, no findings.

### Product/UX Gate

**Tier:** none — no UI-surface file in Files to Create/Edit; CPO confirmed no customer consumer of the caches and no roadmap conflict; #8177 evidence supports on-demand regeneration.

**Brainstorm-recommended specialists:** none.

## References & Research

- Brainstorm: `knowledge-base/project/brainstorms/2026-09-19-kb-index-untrack-generated-artifacts-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-kb-index-untrack/spec.md`
- Learning: `knowledge-base/project/learnings/workflow-patterns/2026-09-19-enumerate-the-readers-before-proposing-a-writer-for-a-generated-artifact.md`
- ADR-210, ADR-091, ADR-174, ADR-032 (strict policy / merge queue), ADR-178 (lock primitives), ADR-223 (hook registries)
- `apps/web-platform/server/c4-render.ts:1-41` (why the C4 model is committed)
- Prior #7935 challenge record: `knowledge-base/project/specs/archive/20260908-175747-feat-one-shot-7935-kb-index-merge-driver/decision-challenges.md`
- Related PRs/issues: #8151, #8116, #8370, #8177, #6109, #2231
