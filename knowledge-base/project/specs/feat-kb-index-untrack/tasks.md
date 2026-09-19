# Tasks: feat-kb-index-untrack

Plan: `knowledge-base/project/plans/2026-09-19-feat-untrack-generated-kb-caches-regenerate-on-conflict-plan.md`
Spec: `knowledge-base/project/specs/feat-kb-index-untrack/spec.md`
Lane: `cross-domain` · Brand-survival threshold: `single-user incident` · Closes #8377, #8370

## Phase 1: Regenerate on demand (P2, P3, P7)

- [ ] 1.1 Write `scripts/ensure-kb-index.test.sh` FIRST (RED) — Guard 2 rows 1–8, H1, P1, P2: add/delete/rename an indexed `.md`; a timestamp-preserving edit (`touch -d '2 years ago'` after changing a title); `kb-tags.txt` removed with `INDEX.md` fresh; generator stubbed to exit non-zero (targets byte-identical, temp dir gone); script stubbed to a no-op; `INDEX.md` replaced by a symlink; the harness row (drop the fixture edit → the regenerated assertion must fail); fresh index with `archive/` touched (must PASS); `--soft` with a failing generator (must PASS, exit 0, `WARN:`).
- [ ] 1.2 Register the suite in `scripts/test-all.sh` with a `run_suite` line beside `:2325` (bare `scripts/*.test.sh` is not globbed by `SUITE_GLOBS` — an unregistered suite is an orphan).
- [ ] 1.3 Implement `scripts/ensure-kb-index.sh [--soft]` to the plan's §1 contract: `[ -d knowledge-base ] || exit 0`; per-target absence check; fingerprint vs `knowledge-base/.kb-index.stamp` (`git hash-object --stdin` over `git ls-files -s` + `git status --porcelain -uall`, both scoped to `knowledge-base`); regenerate via `generate-kb-index.sh --out "$tmp"` (`mktemp -d`, `EXIT` trap) then `mv -f` each file, stamp written last; symlink refusal; `SOLEUR_KB_INDEX_REGEN reason=<absent|stale> ms=<n>` on regeneration and silence when fresh; `--soft` downgrades every failure to `WARN:` + exit 0. No `sha1sum`/`date +%N`/`stat -c`/`readlink -f`/`timeout`.
- [ ] 1.4 GREEN 1.1; confirm the fresh path regenerates nothing (assert the three files' mtimes are unchanged).
- [ ] 1.5 `scripts/generate-kb-index.sh`: inline `kb_render_index` at `:230` without the header lines; delete the `--check` arm (`:59-116`, `:20-23`, `:47`); keep `--out`; then delete `scripts/lib/kb-index-render.sh`.
- [ ] 1.6 `plugins/soleur/test/generate-kb-index.test.sh`: drop `--check` cases, assert no `> Total files:` line, keep row/facet cases. Green.
- [ ] 1.7 Wire readers to call `ensure-kb-index.sh` **before** they read: `plugins/soleur/skills/kb-search/SKILL.md` Phase 1 (`:57-73`) and Tier 1 (`:146-151`); `plugins/soleur/agents/engineering/research/learnings-researcher.md:13-20`; `.openhands/skills/learnings-researcher/SKILL.md:13-20`; `scripts/learning-retrieval-bench.sh:36` (default `INDEX_PATH` only).
- [ ] 1.8 `kb-search` degraded path: with neither the facet files nor `scripts/generate-kb-index.sh` present (a customer repo), validate `--tag`/`--category` via `git grep -il '^tags:.*<tag>' -- 'knowledge-base/**/*.md'` and fall back to content grep for Tier 1 — never `exit 1` with a Soleur-only remediation.
- [ ] 1.9 Repoint `package.json:8` `prepare` → `bash scripts/ensure-kb-index.sh --soft`; `.claude/settings.json:48-50` and `.devin/config.json:22-25` → same, last in the SessionStart array; `.claude/hooks/devin-dispositions.tsv:111` → new row target. Run `devin-matcher-parity.test.sh`.
- [ ] 1.10 Verify `bash scripts/ensure-kb-index.sh` exits 0 in a directory with no `knowledge-base/`.

## Phase 2: Untrack the caches and retire the driver (P1, P5)

- [ ] 2.1 Write `plugins/soleur/test/kb-caches-untracked.test.sh` FIRST (RED) — Guard 3 rows 1–4 over the five paths (four caches + `.kb-index.stamp`): `.gitignore` entry removed; `git add -f` in the fixture; a sixth path added without a `.gitignore` line; the path list emptied (the suite asserts it holds 5 entries).
- [ ] 2.2 `.gitignore` "Local state" block (`:62-65`): add `knowledge-base/INDEX.md`, `knowledge-base/kb-tags.txt`, `knowledge-base/kb-categories.txt`, `knowledge-base/project/rule-metrics.json`, `knowledge-base/.kb-index.stamp`. GREEN 2.1.
- [ ] 2.3 `git rm --cached` the four tracked cache files (the stamp was never tracked).
- [ ] 2.4 Delete `scripts/merge-kb-index.sh`, `scripts/install-kb-merge-driver.sh`.
- [ ] 2.5 Delete `plugins/soleur/test/kb-index-merge-driver.test.sh`, `kb-index-merge-driver-registration.test.sh`, `merge-kb-index-driver-mutation.test.sh`, `kb-index-check-guard-mutation.test.sh`, `kb-index-freshness.test.sh`.
- [ ] 2.6 `.gitattributes`: remove the kb block (`:1-49` — the three path lines and their comment block); leave any non-kb attributes intact.
- [ ] 2.7 `lefthook.yml`: delete the `generate-kb-index` step (`:386-402`) and rewrite the `:404-424` comments that cite it as the precedent shape for `c4-model-regenerate`.
- [ ] 2.8 `.claude/hooks/guardrails.sh`: delete ONLY the three kb-index `awk` lines (`:431-433`) and the kb-index clause of the deny message (`:445`). **Leave `:383-429` and `:435-450` intact** — the generic two-marker check shares that `if` block and `awk` program. Update `.claude/hooks/guardrails.test.sh:491-547` accordingly and prove the generic guard still denies (a two-marker fixture) and still allows a clean commit.
- [ ] 2.9 `.github/CODEOWNERS`: delete rows `:204-206`; rewrite the `:196-203` rationale comment (it describes the retired driver) and keep the `.gitattributes` row.
- [ ] 2.10 Sweep, only if they pin deleted names: `plugins/soleur/test/fixture-relative-assert.baseline.txt`, `plugins/soleur/test/lint-shell-trace-credential-refusal.test.sh`, `.claude/hooks/skill-context-queries.sh`.
- [ ] 2.11 Prose: `merge-pr/SKILL.md:164-204` → replace the driver/diagnosis section with the transition one-liner + a resolver pointer; `ship/SKILL.md:2132,2410-2416,2470-2474` → drop the caches from the regenerable-index hatch trigger set, add the transition one-liner; `compound/SKILL.md:516` → drop the `generate-kb-index.sh` re-run from the recovery line.

## Phase 3: rule-metrics.json (P1)

- [ ] 3.1 Add the `rule-prune` suite cases FIRST (RED): file absent + `RULE_METRICS_ROOT` unset → the aggregator runs and the read succeeds; aggregator exits non-zero after a partial write → the file is removed and `rule-prune.sh` exits 2 with `aggregator failed (rc=<n>)`; `RULE_METRICS_ROOT` set → the aggregator is NOT run.
- [ ] 3.2 `scripts/rule-prune.sh`: insert between the `METRICS=` assignment (`:53`) and the `-f` check (`:55`). GREEN 3.1.
- [ ] 3.3 `plugins/soleur/skills/compound/SKILL.md:301-320`: keep the aggregator run + the unused-rules hint; remove the `git diff --quiet || git add` staging lines and the "committed" wording; change the failure branch from `git checkout -- "$OUT"` to `rm -f "$OUT"` (the file is no longer tracked, so `git checkout --` cannot restore it).
- [ ] 3.4 Delete `.github/workflows/rule-metrics-aggregate.yml`.
- [ ] 3.5 `.github/workflows/ci.yml`: remove the `rule-metrics-shape` step (`:269-290`) and fix the reasoning comment at `:387-393` that derives an empty intersection from a two-member `ALLOWED_PATHS`.
- [ ] 3.6 `.github/actions/bot-pr-with-synthetic-checks/action.yml`: remove `knowledge-base/project/rule-metrics.json` from `ALLOWED_PATHS` (`:163`), update the `:234` comment and the action's `CHANGELOG.md:45,99`.
- [ ] 3.7 Fix the comments that reason from the deleted workflow or the two-member set: `scripts/marketplace-manifest-validate.sh:32`, `scripts/required-checks.txt:80,135,167,227,252`, `.github/workflows/weakness-miner.yml:4`, `infra/github/README.md:188` (repoint the merge-queue canary at `weakness-miner.yml`), `tests/scripts/test-audit-bot-codeql-coverage.sh:110` ("Only rule-metrics-aggregate.yml remains" is already false — `weakness-miner.yml` is enumerated too).
- [ ] 3.8 Verify `AUDIT_ENUMERATE_ONLY=1 bash scripts/audit-bot-codeql-coverage.sh | wc -l` ≥ 1 post-delete (measured pre-change: 2) and `tests/scripts/test-audit-bot-codeql-coverage.sh` green.
- [ ] 3.9 Run `plugins/soleur/test/c4-count-parity.test.sh`; if a workflow count moved, update the `model.c4` edge prose in the same commit.

## Phase 4: Regenerate on conflict (P4)

- [ ] 4.1 Write `plugins/soleur/scripts/resolve-regenerable-conflicts.test.sh` FIRST (RED) — Guard 1 rows 1–8, H1, P1, with a stub regen command and a two-branch fixture repo; implement rows 1/3/4/6/7/8 as ONE table-driven loop asserting `rc != 0` AND a byte-identical tree; allow the resolvable set to be overridden (`RESOLVABLE_OVERRIDE`) for rows 3–4; row 5 asserts the committed artifact equals a regeneration of the MERGED tree, not of HEAD.
- [ ] 4.2 Implement `plugins/soleur/scripts/resolve-regenerable-conflicts.sh <base-ref>` to the plan's §6 contract: one hardcoded pair (`model.likec4.json` → `bash scripts/regenerate-c4-model.sh`); precondition clean tree + no `MERGE_HEAD`; read `merge-tree` rc 0/1/≥2; parse only `CONFLICT (content):`; `git merge --no-ff --no-commit`, regen, symlink refusal, `git add`, assert no `--diff-filter=U`, `git commit --no-edit`; `SOLEUR_REGEN_ON_CONFLICT paths=<csv> rc=0`; **exit 0 or non-zero only**, diagnosis in stderr; no lock; never pushes. GREEN 4.1.
- [ ] 4.3 Call site 1 — `plugins/soleur/scripts/sync-pr-behind.sh:63-68`: on `merge-tree` failure call the resolver; rc 0 → existing push path (keep its exit 7 on a rejected push); else existing exit 6.
- [ ] 4.4 Call site 2 — `.claude/hooks/pre-merge-rebase.sh:333-345`: after `git merge --abort`, call the resolver; rc 0 → continue as merged; else the existing deny JSON.
- [ ] 4.5 Call site 3 — `plugins/soleur/skills/ship/SKILL.md:2299-2309` DIRTY arm: on an unclean `merge-tree`, run the resolver; rc 0 → push and keep polling; else the existing poll exit.
- [ ] 4.6 Extend / create `plugins/soleur/scripts/sync-pr-behind.test.sh` with the rc-0 (resolved → pushed) and rc-non-zero (untouched → exit 6) paths.
- [ ] 4.7 Confirm `npx -y likec4@1.50.0` is reachable where the sync runs; if absent, the regen exits non-zero and the caller surfaces — never a silent commit.

## Phase 5: Decision record and sweeps (P6)

- [ ] 5.1 Create ADR-230 via `soleur:architecture` — cache-vs-product classification, `Supersedes: ADR-210`, alternatives table (regen-on-main, count-header-only, driver+resolver for INDEX.md, untracking `model.likec4.json`, web-platform render-at-sync, a manifest).
- [ ] 5.2 ADR-210 → `Status: Superseded by ADR-230` with a retained-parts note; ADR-091 → dated amendment retiring the "committed metric reflects the committing worktree" consequence and the deferred canary.
- [ ] 5.3 Re-derive the ADR ordinal across every pushed ref with a **per-ref loop** (`git ls-tree` takes one tree-ish); `check-adr-ordinals.sh` green. Re-run immediately before merge.
- [ ] 5.4 Sweep §Verification sections and ticked `- [x]` boxes that assert the deleted mechanism (ADR-210 §Verification gets the supersession note, not a rewrite).
- [ ] 5.5 Run the AC5 sweep; expect zero hits outside the six historical-record exclusions.
- [ ] 5.6 Run the plan-citation check (`grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md'` → `[[ -f ]]`) over the plan, the ADR and the spec.

## Phase 6: Verification

- [ ] 6.1 Walk every AC (AC1–AC14 incl. AC7b, AC9b, AC11b, AC11c) and record the command + output.
- [ ] 6.2 Full battery: `bash scripts/test-all.sh` (or the shards the diff touches at `/work` exit, full battery at `/ship` Phase 4). Confirm `--enumerate-commands all` lists no deleted suite and does list `ensure-kb-index`.
- [ ] 6.3 markdownlint every touched `.md`; `bun test` for the plugin.
- [ ] 6.4 Comment on #6109 that its §1 `merge=ours` sub-item is moot; the rest stands.
