# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-9401-premerge-sync-stale-sha/knowledge-base/project/plans/2026-10-01-chore-premerge-sync-stale-sha-plan.md
- Status: complete

### Errors
- No blocking errors. Subagent had no Task/Skill/AskUserQuestion tools, so agent fan-outs (research, domain leaders, plan-review panel, deepen-plan research/review agents) ran as inline sequential passes — disclosed in the plan as `Reviewed-Coverage: sequential-fallback`; no independent reviewer agents ran. `markdownlint` CLI arg-shape note; canonical `scripts/markdown-lint.sh` reported new files out of scope.

### Decisions
- Merge-queue arm cut at premise validation: already adopted-and-reverted (PR #5800, ADR-032 amendment 2026-06-30); upstream codeql-action#1537 verified still OPEN. Plan ships the disjoint-delta arm only; queue adoption stays with #4856/#5840.
- Three-part mechanism: (1) `pre-merge-rebase.sh` skips the origin/main merge+push when `files(merge-base..origin/main) ∩ files(merge-base..HEAD) = ∅`, emitting a `delta disjoint` marker; (2) `MERGE_TARGET_WHY` resolver normalizes `-R`/`--repo`/`GH_REPO`/`GH_HOST` so same-repo invocations resolve the PR head (foreign repos keep state-L); (3) `admin-merge-ready.sh` gains an opt-in `--allow-local-merge` carryover arm requiring clean-merge proof via per-file `patch` equality in compare API responses, docs-only classifier, and PR-file disjointness.
- Bounds preserved: computation failures fall toward the existing sync (status quo), never toward skipping; `UNTRUSTED-CI`/`DIRTY`/verified-merge precedence unchanged; `sync-pr-behind.sh` untouched (#8683 scope-out).
- New provisional ADR-264 declared as in-plan deliverable (ordinal re-probed across `origin/*` before merge); C4 assessed no-impact.
- `ship/SKILL.md` edit budgeted to net ≤ ~300 bytes (byte ceiling 274000, current 273665).

### Components Invoked
- Skills (read-and-run inline): soleur:plan, soleur:deepen-plan
- Scripts: scripts/cloud-detect.sh (local), scripts/lint-guard-contract.py (PASS), scripts/markdown-lint.sh (out-of-scope)
- Artifacts: plan file, tasks.md, decision-challenges.md — committed fca439066f + 7ce1c641b8, pushed to origin/feat-one-shot-9401-premerge-sync-stale-sha

## Work Phase (2026-10-02)
- Status: implementation complete; review/qa/compound/ship pending.

### Implemented
- `.claude/hooks/pre-merge-rebase.sh`: disjoint-delta skip between the up-to-date check and `acquire_lock rebase-main` — `files(mb..HEAD)` ∩ `files(mb..origin/main)` via `comm -12` over `git diff --name-only`; empty intersection → `additionalContext` "delta disjoint" + counts, `exit 0`; any diff failure falls through to the sync. Header comment documents the policy + failure direction.
- `.claude/hooks/pre-merge-rebase.sh`: repo-pointer normalization (`_repo_url_parts`, `_repo_flag_operands`, `_repo_env_operands`, `_repo_pointers_same_repo`, `_strip_repo_flags`) — `-R`/`--repo`/`--repo=`/attached/`GH_REPO`/`GH_HOST` operands compared against the RAW `remote.origin.url` config (NOT `remote get-url`, which resolves `url.insteadOf`); all-pointers-same-repo → strip + resolve PR head; foreign/malformed → legacy denial arms unchanged. Known residual: `GH_REPO=x gh pr merge` (env-prefix, no separator) never matches the top-level detector — documented in ADR-265.
- `plugins/soleur/scripts/admin-merge-ready.sh`: `--allow-local-merge` (requires `--green-sha`). On `carryover-unverified` + flag: p1 read from `head.json`, `compare(p1...base)` must be ahead|identical, then `compare(G...SHA)` ⊆ `compare(G...p1)` on filename+status+byte-identical non-null patch, docs-only (`^(knowledge-base/|docs/|plugins/soleur/skills/)` or `*.md`), disjoint from the PR file list — all in ONE jq for a single error path. Ready: `reason=carryover-local-docs`; refusals: `carryover-local-{not-clean,nondocs,overlap}`; truncated/unparseable compare → `incomplete-files` error. `all-green` assignment now guards on `REASON == "none"`.

### Tests
- `.claude/hooks/pre-merge-rebase.test.sh`: +T-DJ1/2/3 (skip/overlap/failopen), +T-R1/2/3 (same-repo resolution incl. env forms, foreign still legacy, no cross-PR evidence lending); fixture `file.txt` is now multi-line so sync-path tests overlap; `EXPECTED_CASES=50`; suite green 126/126.
- `test/pre-merge-rebase.test.ts`: overlapping fixtures for the 3 sync-path tests + new `disjoint incoming delta skips the sync` case; green 22/22.
- `plugins/soleur/scripts/admin-merge-ready.test.sh`: +L1–L12 rows + 5 mutation rows (LM-clean/-nondocs/-overlap/-flag/-reason); stub gains `compare/$GREEN...$SHA` and `compare/$GREEN...$P1` arms + `STUB_P1`; `_min_cases=70`; green 71/71.
- Wiring 39/39, parity 12/12, headless 1/1, ship-unpushed-gate 16/16, adr-ordinals pass.

### Decisions / findings during work
- `git remote get-url` resolves `url.insteadOf` — the prover reads `git config --get remote.origin.url` instead (commented in source).
- Env-pointer extraction stops at `;&|` — an unquoted separator is shell syntax, not value (the `export GH_REPO=x;` form).
- jq predicate needs `-n` (all data via --slurpfile; otherwise jq reads stdin as input → EOF → empty output).
- ADR ordinal taken: **265** (264 claimed by in-flight `feat-one-shot-agent-runnable-operator-bootstrap`).

### Docs
- `settle-then-admin-merge.md` (carryover paragraph + detached-worktree bullet rescoped to overlapping deltas; fence count still 3), `ship/SKILL.md` + `merge-pr/SKILL.md` carryover sentences, `constitution.md` hook-enforced line annotated, ADR-265 authored.

### Remaining
- `soleur:review` → findings → `soleur:qa` → `soleur:compound` → `soleur:ship` (PR #9406 is draft).
