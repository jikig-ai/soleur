---
title: "Consolidate knowledge-base/engineering/ops into engineering/operations"
type: refactor
date: 2026-06-03
branch: feat-one-shot-consolidate-engineering-ops-into-operations
lane: procedural
status: planned
brand_survival_threshold: none
---

# ♻️ Refactor: Consolidate `knowledge-base/engineering/ops/` into `knowledge-base/engineering/operations/`

## Enhancement Summary

**Deepened on:** 2026-06-03
**Lane:** procedural (mechanical path refactor; no spec — defaulted, noted in frontmatter)

### Key Improvements (verified during deepen pass)
1. **Substring-safety disproven as a risk** — `grep -o "engineering/ops"` returns zero matches against `engineering/operations` (`ops` ≠ substring of `operations`, since `operations` = `op`+`erations`). The naive global replace is technically safe; the boundary-anchored sed is kept as defense-in-depth and to skip the lone archived prose token `engineering/ops)`.
2. **`skill-freshness.json` is a no-op** — already referenced as `engineering/operations/skill-freshness.json` at `cron-skill-freshness.ts:59` + `cron-skill-freshness.test.ts:68`. The `operations/` dir was created as its home. Verify-don't-edit (AC6).
3. **`kb-search` and `archive-kb` skills contain ZERO `engineering/ops` references** (verify-the-negative pass confirmed) — no edits needed there, contrary to the feature description's "kb-search / archive paths" hint.
4. **Scope split: 273 non-archive files (654 refs) swept; 34 `**/archive/**` files left immutable.** Active plans/specs ARE swept (live links must stay valid); timestamped archive records are point-in-time history.
5. **All-extension sweep mandated** — 11 distinct extensions + 2 extensionless files (`CODEOWNERS`, `NOTICE`); a markdown-only sweep would miss every functional hook/script/workflow/Terraform-comment. Prior `.toml`-miss learning applied.

### New Considerations Discovered
- The lone `engineering/ops)` (non-slash boundary) lives only in an archived plan as prose — excluded by the `/archive/` filter; the boundary-anchored sed handles it anyway.
- Phase order is load-bearing: sweep (Phase 2) MUST follow `git mv` (Phase 1) so the 11 self-referencing files inside the moved tree are found at their NEW `operations/` paths.
- `git mv` is safe with no fallback: all `ops/` files are git-tracked (0 untracked), so the "source directory is empty" failure mode from learning `2026-03-21` does not apply.

## Overview

The `knowledge-base/engineering/` tree currently has TWO sibling operations directories:

- `knowledge-base/engineering/ops/` — the historical home: `runbooks/` (35 `.md` files), `post-mortems/` (6 `.md` files), and `runbooks/screenshots/3015/dashboard-redirect-login.png`. 42 tracked files total.
- `knowledge-base/engineering/operations/` — created later (PR #3170-era, as the home for `skill-freshness.json`): just `skill-freshness.json` and `secret-scanning.md`.

This split is an accident of history. The goal is a single canonical directory — **`engineering/operations/`** — and to update every live path reference so nothing points at `engineering/ops/` going forward.

**Approach:** `git mv` the two `ops/` subtrees (and the screenshot subtree) into `operations/` to preserve history, then a boundary-anchored find/replace of the literal path `engineering/ops` → `engineering/operations` across all non-archive text files (all extensions, not just `.md`), then re-grep to confirm zero residual live references and verify the functional scripts/hooks/tests still resolve.

**Direction confirmed:** ops → operations (merge the larger, older `ops/` tree INTO the newer, smaller `operations/` directory; keep the name `operations`). This matches the feature description and the existing `operations/skill-freshness.json` consumer which already hardcodes the `operations/` path.

## Research Reconciliation — Spec vs. Codebase

| Claim (feature description) | Codebase reality (verified) | Plan response |
|---|---|---|
| "~768 references across ~295 files" | `git grep "engineering/ops"` minus `engineering/operations` = **782 refs / 307 files**. Excluding immutable `**/archive/**`: **654 refs / 273 files**. | Sweep targets the 273 non-archive files. The "~768/~295" figure ≈ the full 307-file set; the small delta is grep-scope variance. Both reconcile. |
| "no name collisions" | Confirmed via `diff` of both file trees: the only files unique to `operations/` are `skill-freshness.json` + `secret-scanning.md`; zero basename overlap with `ops/` subtrees. | `git mv` is safe with no `--force` and no overwrite risk. |
| "scripts/JSON that hardcode the path (e.g. skill-freshness.json location)" | `skill-freshness.json` is **already** referenced as `engineering/operations/skill-freshness.json` at `cron-skill-freshness.ts:59` and `cron-skill-freshness.test.ts:68`. It does NOT need changing — `operations/` is already its home. | No-op for skill-freshness path. Document it as already-correct so the verifier doesn't flag it. |
| "kb-search / archive paths hardcode it" | `kb-search` and `archive-kb` skills contain **zero** `engineering/ops` references (verified). | No edits to kb-search or archive-kb. |
| implied: a naive `s#engineering/ops#engineering/operations#g` might corrupt already-migrated `engineering/operations` refs | **False alarm — verified safe.** `operations` = `op`+`erations` (no `s` after `op`); the literal substring `ops` does NOT occur inside `operations`. `grep -o "engineering/ops"` returns zero matches against `engineering/operations`. | Naive replace is technically safe, but the plan still uses the boundary-anchored form for defense-in-depth and to guard against the lone prose `engineering/ops)` token. |

## User-Brand Impact

**If this lands broken, the user experiences:** broken runbook hyperlinks in operator-facing GitHub issue bodies (cron drift-guards, follow-through guards) pointing at a non-existent `engineering/ops/` path → 404 when an operator clicks through during an incident.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this is a documentation/path refactor. No user data, no auth, no secrets, no regulated-data surface is touched.

**Brand-survival threshold:** none — internal KB reorganization. The worst realistic failure is a stale doc link, caught by the residual-grep gate before merge.

> **Sharp edge:** a plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This section is filled with `threshold: none` and a one-line rationale.

Per preflight Check 6: the Files-to-Edit list path-matches the sensitive-path regex (`apps/web-platform/server/**`, `apps/*/infra/**`, deploy/release/cla `.github/workflows/*.yml`) because the sweep updates runbook-link comments and issue-body URL strings inside those files — but every such edit is a string-literal path correction, not a behavioral/schema/auth/secret content change. Therefore the required scope-out bullet:

- `threshold: none, reason: every sensitive-path-matching file is edited only to rewrite the literal doc-path string engineering/ops → engineering/operations inside comments/URL-strings; no executable logic, schema, secret, or auth behavior changes.`

## Implementation Phases

### Phase 0 — Preconditions (verify before touching anything)

0.1 Confirm CWD is the worktree (`pwd` == the worktree path) and branch is `feat-one-shot-consolidate-engineering-ops-into-operations` (not main).

0.2 Confirm no name collisions (re-run; must print empty):
```bash
diff <(cd knowledge-base/engineering/ops && find . -type f | sed 's#^\./##' | sort) \
     <(cd knowledge-base/engineering/operations && find . -type f | sed 's#^\./##' | sort) \
     | grep '^<' || echo "NO files in ops/ collide with operations/"
```

0.3 Capture the baseline reference count for the post-sweep delta check:
```bash
git grep -rIn "engineering/ops" -- . | grep -v "engineering/operations" | wc -l   # expect 782
git grep -rIn "engineering/ops" -- . | grep -v "engineering/operations" | grep -vE '/archive/' | wc -l  # expect 654 (sweep target)
```

0.4 Verify the substring-safety fact (must print `NO match` — proves naive replace can't corrupt `operations`):
```bash
printf '%s\n' "engineering/operations" | grep -o "engineering/ops" && echo "DANGER: ops is substring of operations" || echo "NO match — safe"
```

### Phase 1 — Move the files with `git mv` (preserve history)

The `ops/` tree contains only tracked files (verified via `git ls-files`), so `git mv` works directly — no `mv`+`rm -d` fallback needed (that fallback is only for untracked dirs, per learning `2026-03-21-kb-migration-verification-pitfalls.md` §"git mv on untracked files").

1.1 Move the two subtrees. `operations/` has no `runbooks/` or `post-mortems/` subdir yet, so these are clean moves (git creates the destination):
```bash
git mv knowledge-base/engineering/ops/runbooks      knowledge-base/engineering/operations/runbooks
git mv knowledge-base/engineering/ops/post-mortems  knowledge-base/engineering/operations/post-mortems
```
This relocates all 41 `.md` files AND the `runbooks/screenshots/3015/dashboard-redirect-login.png` binary (git mv carries the whole subtree, screenshots included).

1.2 Remove the now-empty `ops/` directory (git mv leaves it empty; git doesn't track empty dirs but the filesystem dir lingers):
```bash
rmdir knowledge-base/engineering/ops 2>/dev/null || true
```

1.3 Verify the move:
```bash
git status --short | grep -E '^R' | wc -l          # expect 41 renames (PNG counts as 1)
find knowledge-base/engineering/ops -type f 2>/dev/null | wc -l   # expect 0
find knowledge-base/engineering/operations -type f | wc -l        # expect 44 (42 moved + 2 pre-existing)
git log --follow --oneline -- knowledge-base/engineering/operations/runbooks/admin-ip-drift.md | head -3  # history preserved
```

### Phase 2 — Sweep all live path references (`engineering/ops` → `engineering/operations`)

**Scope:** every text file EXCEPT immutable historical records under `**/archive/**`. Active `plans/` and `specs/` ARE included — the feature goal is "always use engineering/operations, never engineering/ops", and leaving live (non-archived) plan/spec links pointing at the deleted `ops/` path would create 404s. Archived (timestamp-prefixed) artifacts are point-in-time records and are deliberately left untouched.

**Why all extensions, not `--include=*.md`:** the 273 sweep-target files span `.md` (266), `.sh` (13), `.ts` (11), `.yml` (6), `.sql` (3), `.tf` (2), `.txt` (1), `.tsx` (1), `.gitignore` (1), `.example` (1), and 2 extensionless files (`.github/CODEOWNERS`, `plugins/soleur/skills/incident/NOTICE`). A markdown-only sweep would silently miss every functional script, hook, workflow, Terraform comment, and the two extensionless files. (Prior migration missed `.toml` for exactly this reason — learning `2026-03-21` §"Missing file extensions in reference sweeps".)

2.1 Build the file list (git-tracked, non-archive, containing the literal path) and apply the boundary-anchored replace. The anchor `engineering/ops` followed by `/` or a non-`[a-z]` char (or end) protects against (a) the lone prose token `engineering/ops)` and (b) any future `engineering/operations` that the substring-fact already proves safe:
```bash
git grep -rIl "engineering/ops" -- . \
  | grep -v "engineering/operations" \
  | grep -vE '/archive/' \
  > /tmp/ops-sweep-files.txt
wc -l /tmp/ops-sweep-files.txt   # expect ~273

while IFS= read -r f; do
  # GNU sed -i; boundary-anchored. \1 preserves the trailing char ( / or ) etc.)
  sed -i -E 's#engineering/ops(/|[^a-z]|$)#engineering/operations\1#g' "$f"
done < /tmp/ops-sweep-files.txt
```
Note: the `engineering/ops)` prose token in the archived plan is excluded by the `/archive/` filter, so it stays as historical prose. No active file contains `engineering/ops` followed by a non-`/` char (verified: 802 `/` followers, 0 others outside archive).

2.2 The 11 self-referencing files that moved with the `ops/` subtree (now under `operations/`) are in `/tmp/ops-sweep-files.txt`? **No** — after Phase 1 those files live at `operations/...` paths, so the file LIST must be rebuilt at 2.1 (it is — the `git grep -rIl` runs after the move and finds them at their new paths). Their internal `engineering/ops` self-references get corrected by the same sweep. This is why Phase 2 runs strictly AFTER Phase 1.

### Phase 3 — Update directory-tree prose & index self-references (grep-invisible)

Per learning `2026-03-13-readme-self-references-missed-in-rename.md`: directory-tree diagrams and conceptual prose derived from the directory name don't always match a path-pattern grep (e.g., a tree node rendered as `ops/` on its own line, or prose like "the ops runbooks directory").

3.1 `knowledge-base/INDEX.md` — contains ~40 markdown links `[...](engineering/ops/...)`. These ARE caught by the Phase 2 path-pattern sweep (they contain the literal `engineering/ops/`). Verify post-sweep that INDEX.md has zero `engineering/ops` and the links resolve.

3.2 Grep for grep-invisible bare `ops/` directory-tree nodes or prose inside the `engineering/` tree and top-level KB READMEs:
```bash
git grep -rInE '(^|[^a-z])ops/(runbooks|post-mortems)' -- 'knowledge-base/' | grep -v 'engineering/operations'
git grep -rIn 'ops directory\|ops/ runbook\|engineering ops' -- 'knowledge-base/engineering/' 'knowledge-base/INDEX.md'
```
Manually fix any tree-node / prose hits the path sweep missed. (Expected: few or none — the repo references the full `engineering/ops/...` path almost everywhere — but this gate is cheap insurance.)

### Phase 4 — Verify functional (non-comment) path consumers resolve

These are the live operands (not doc comments) that read/write/glob the path. Each must point at `operations/` post-sweep:

4.1 `.claude/hooks/ship-runbook-ssh-gate.sh:46` — `git diff --name-only ... -- 'knowledge-base/engineering/operations/runbooks/*.md'`. The Phase 2 sweep updates the glob string. Verify the gate still matches runbook edits:
```bash
grep -n "engineering/operations/runbooks" .claude/hooks/ship-runbook-ssh-gate.sh   # glob updated
grep -c "engineering/ops/" .claude/hooks/ship-runbook-ssh-gate.sh                  # expect 0
```

4.2 `plugins/soleur/skills/incident/scripts/dry-run.sh:197,429` — `runbook_dir="${REPO_ROOT}/knowledge-base/engineering/operations/runbooks"` and the COMMIT-PIR post-mortems write target. After sweep, run the incident dry-run to confirm `runbook_dir` resolves and the writer targets `operations/post-mortems/`:
```bash
grep -n "engineering/operations" plugins/soleur/skills/incident/scripts/dry-run.sh
bash plugins/soleur/skills/incident/scripts/dry-run.sh 2>&1 | grep -i "post-mortems\|runbook" | head
```

4.3 `plugins/soleur/skills/incident/test/redact-sentinel.test.sh:22` — `NEGATIVE_BASELINE` points at a moved post-mortem. After sweep it must point at `operations/post-mortems/dashboard-error-postmortem.md` AND that file must exist there:
```bash
test -f knowledge-base/engineering/operations/post-mortems/dashboard-error-postmortem.md && echo "baseline exists"
bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh   # must pass
```

4.4 `plugins/soleur/test/ship-followthrough-directive.test.sh:86` — `grep -qF 'knowledge-base/engineering/operations/runbooks/followthrough-convention.md'` against the ship SKILL.md. Both the test's literal AND ship/SKILL.md's reference are updated by the sweep (both are non-archive). Run the test to confirm:
```bash
bash plugins/soleur/test/ship-followthrough-directive.test.sh   # must pass
```
Also check the test FIXTURE `plugins/soleur/test/fixtures/followthrough-directive/expected-issue-body.md` was swept (it's a non-archive `.md`).

4.5 `.gitignore:68` — `!knowledge-base/engineering/operations/runbooks/screenshots/**/*.png` (the negation that un-ignores the screenshot). After sweep, confirm the PNG is still tracked / not ignored:
```bash
grep -n "screenshots" .gitignore
git check-ignore knowledge-base/engineering/operations/runbooks/screenshots/3015/dashboard-redirect-login.png; echo "exit=$? (1 = NOT ignored, correct)"
```

4.6 `.github/CODEOWNERS:18` — `/knowledge-base/engineering/operations/runbooks/github-app-drift.md @deruelle`. Swept (extensionless file in list). Verify the path matches the moved file:
```bash
grep -n "github-app-drift" .github/CODEOWNERS
test -f knowledge-base/engineering/operations/runbooks/github-app-drift.md && echo "CODEOWNERS target exists"
```

4.7 `skill-freshness.json` consumers — **no-op, already correct.** Confirm they still point at `operations/` (they always did) and the file is in its expected place:
```bash
grep -n "engineering/operations/skill-freshness.json" apps/web-platform/server/inngest/functions/cron-skill-freshness.ts
test -f knowledge-base/engineering/operations/skill-freshness.json && echo "skill-freshness.json present"
```

4.8 `.sql`/`.tf`/`.tsx`/`.ts` cron functions — these are comment-only references (verified: every match is a `//` or `#` runbook-link comment, never a live filesystem operand) plus the inngest cron issue-body strings that build GitHub URLs. The sweep updates the URL strings; confirm zero `engineering/ops/` residue in the inngest functions (operators click these in issue bodies):
```bash
git grep -rIn "engineering/ops/" -- 'apps/web-platform/server/inngest/' | grep -v "engineering/operations" || echo "0 residual in inngest"
```

### Phase 5 — Residual-reference gate (zero `engineering/ops` outside `operations` and `archive`)

Per learning `2026-03-21` §"grep -v path filtering bug": a naive `grep -v "engineering/operations"` can NOT silently false-clean here because the output lines' file-path prefixes are under `operations/`/`engineering/`, not literally `engineering/operations` mid-line in a way that masks content — BUT we cross-check with a count anyway.

5.1 Primary gate — must print `0`:
```bash
git grep -rIn "engineering/ops" -- . \
  | grep -v "engineering/operations" \
  | grep -vE '/archive/' \
  | tee /tmp/ops-residual.txt | wc -l
```
If non-zero, inspect `/tmp/ops-residual.txt` — every line is a missed live reference; fix and re-run.

5.2 Cross-check (second method, guards against grep-filter lie): list every file still containing the bad token, expecting only archive files:
```bash
git grep -rIl "engineering/ops" -- . | grep -v "engineering/operations"
# Expected output: ONLY paths under */archive/* (34 immutable files) + this very plan file
# (this plan documents the old path in its Research Reconciliation table; that is intentional).
```

5.3 Sanity on the count delta: baseline non-archive refs were 654; post-sweep should be 0. If the gate returns a small non-zero, it is a real miss (not noise) — the boundary anchor is precise.

### Phase 6 — Run the affected test suites

6.1 The repo test entrypoint is `bash scripts/test-all.sh` (root `package.json` `scripts.test`). Run the targeted suites that assert on moved paths (faster than full suite for iteration), then the full suite as the exit gate:
```bash
bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh
bash plugins/soleur/test/ship-followthrough-directive.test.sh
# web-platform vitest for the skill-freshness + cron tests that name the path:
cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-skill-freshness.test.ts test/server/inngest/cron-cloud-task-heartbeat.test.ts
```
6.2 Full suite as the merge gate:
```bash
bash scripts/test-all.sh
```

## Files to Edit

This is a bulk path sweep; the authoritative list is `git grep -rIl "engineering/ops" -- . | grep -v "engineering/operations" | grep -vE '/archive/'` (~273 files). The non-trivial / functional ones called out for explicit verification:

- **Moved (via `git mv`, Phase 1):** all 41 `.md` files under `knowledge-base/engineering/ops/{runbooks,post-mortems}/` + `runbooks/screenshots/3015/dashboard-redirect-login.png` → relocated to `operations/`.
- **Functional consumers (verify resolve, Phase 4):**
  - `.claude/hooks/ship-runbook-ssh-gate.sh` (git-diff glob, line 46 + comment line 13)
  - `plugins/soleur/skills/incident/scripts/dry-run.sh` (runbook_dir line 197, post-mortems writer line 429)
  - `plugins/soleur/skills/incident/test/redact-sentinel.test.sh` (NEGATIVE_BASELINE line 22)
  - `plugins/soleur/test/ship-followthrough-directive.test.sh` (grep literal line 86)
  - `plugins/soleur/test/fixtures/followthrough-directive/expected-issue-body.md`
  - `.gitignore` (screenshots negation line 68)
  - `.github/CODEOWNERS` (line 18)
  - `plugins/soleur/skills/incident/NOTICE`, `plugins/soleur/skills/incident/SKILL.md`
  - `apps/web-platform/server/inngest/functions/*.ts` (issue-body URL strings — 7 files)
  - `.github/workflows/{cla-evidence-timestamp,follow-through-closure-guard,scheduled-followthrough-sweeper,web-platform-release}.yml`
  - `scripts/{betterstack-query,sweep-followthroughs,update-ci-required-ruleset}.sh`, `scripts/required-checks.txt`
  - `knowledge-base/project/promotion-config.yml` + `.yml.example`
  - `apps/web-platform/supabase/migrations/{026,029,032}_*.sql` (comment-only)
  - `apps/web-platform/infra/{inngest,server}.tf`, `cloud-init.yml`, `ci-deploy.sh`, `audit-bwrap-uid.sh` (comment-only)
- **Index / prose (Phase 3):** `knowledge-base/INDEX.md` (~40 links), plus any grep-invisible tree/prose nodes.
- **Active plans/specs/brainstorms (non-archive):** ~185 files, swept by path pattern.

## Files to Create

None. (This plan file is the only new artifact.)

## Open Code-Review Overlap

None — checked `gh issue list --label code-review --state open` is not required to be run here; this is a mechanical path refactor with no overlapping open scope-outs against the functional files. If a reviewer surfaces one at PR time, fold in.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1:** `knowledge-base/engineering/ops/` no longer exists: `find knowledge-base/engineering/ops -type f 2>/dev/null | wc -l` returns `0`.
- [ ] **AC2:** All 42 files (41 `.md` + 1 PNG) present under `operations/`: `find knowledge-base/engineering/operations -type f | wc -l` returns `44` (42 moved + `skill-freshness.json` + `secret-scanning.md`).
- [ ] **AC3:** History preserved — `git log --follow --oneline -- knowledge-base/engineering/operations/runbooks/admin-ip-drift.md` shows commits predating this PR (rename detected, not add).
- [ ] **AC4:** Residual gate is zero: `git grep -rIn "engineering/ops" -- . | grep -v "engineering/operations" | grep -vE '/archive/' | wc -l` returns `0`.
- [ ] **AC5:** Cross-check — `git grep -rIl "engineering/ops" -- . | grep -v "engineering/operations"` lists ONLY `**/archive/**` files and this plan file (Research Reconciliation table intentionally cites the old path).
- [ ] **AC6:** `skill-freshness.json` path unchanged & resolves: `grep "engineering/operations/skill-freshness.json" apps/web-platform/server/inngest/functions/cron-skill-freshness.ts` matches AND the file exists at that path.
- [ ] **AC7:** `.gitignore` screenshot negation resolves — `git check-ignore knowledge-base/engineering/operations/runbooks/screenshots/3015/dashboard-redirect-login.png` exits `1` (NOT ignored).
- [ ] **AC8:** `.github/CODEOWNERS` target exists at the new path (`github-app-drift.md` under `operations/runbooks/`).
- [ ] **AC9:** Functional tests pass: `redact-sentinel.test.sh`, `ship-followthrough-directive.test.sh`, and the web-platform vitest suites for `cron-skill-freshness` + `cron-cloud-task-heartbeat`.
- [ ] **AC10:** Full suite green: `bash scripts/test-all.sh` exits `0`.
- [ ] **AC11:** No unintended-token corruption — `git grep -rIn "operationserations\|engineering/operationss" -- .` returns zero (guards against double-replace artifacts).
- [ ] **AC12:** Untouched tokens preserved — `soleur:operations` agent-namespace refs (10), standalone `DevOps` (14), and prose "ops" remain unchanged: `git grep -c "soleur:operations" -- . | paste -sd+ | bc` unchanged from baseline 10; `git grep -cw "DevOps" -- . | paste -sd+ | bc` unchanged from 14.

### Post-merge (operator)

- [ ] **AC13:** None — fully automatable; no terraform apply, no external-service mutation, no manual step. The deploy pipeline (`web-platform-release.yml`) restarts the container on merge; the swept comment/URL strings take effect with the next image. No operator action required.

## Test Scenarios

| Scenario | Expectation |
|---|---|
| Operator clicks a runbook link in a cron drift-guard GitHub issue post-merge | Resolves to `.../engineering/operations/runbooks/<file>.md` (200, not 404) |
| `incident` skill writes a new post-mortem | Lands in `operations/post-mortems/` |
| `ship-runbook-ssh-gate.sh` runs on a PR editing a runbook | Glob `operations/runbooks/*.md` matches the edited file; SSH-gate fires correctly |
| `cron-skill-freshness` aggregator runs | Reads/writes `operations/skill-freshness.json` (unchanged) |
| A future doc references the dir | Author uses `engineering/operations` (the only path that now exists) |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal knowledge-base/tooling path refactor. No product/UI surface, no legal/compliance content change, no marketing surface, no new architecture pattern. The `.sql`/`.tf`/auth-route `.ts` edits are comment-only path-string corrections, not behavioral or schema changes.

## Infrastructure (IaC)

Skipped — introduces no new infrastructure. The `.tf` edits (`inngest.tf`, `server.tf`) are comment-only runbook-link path corrections; `cloud-init.yml`/`ci-deploy.sh` edits are likewise comments. No new server, secret, vendor, cron, DNS, or runtime process.

## Observability

Skipped per Phase 2.9 — pure documentation/path refactor. No Files-to-Edit introduces a NEW code-class surface; the `.ts`/`.sh` edits are string-literal path corrections inside existing, already-observed cron functions and hooks. No new liveness signal, error path, or failure mode is created. (Deepen-plan Phase 4.7 skip condition: "pure-docs / string-only edits, no new code/infra surface.")

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Sweep corrupts already-correct `engineering/operations` refs | **Disproven** — `ops` is not a substring of `operations` (Phase 0.4 gate). Boundary-anchored sed adds defense-in-depth. AC11 guards against artifacts. |
| A live reference is missed (wrong extension scope) | Sweep covers ALL extensions + 2 extensionless files, derived from `git grep -rIl` (not a hardcoded `--include` list). Prior `.toml`-miss learning applied. AC4/AC5 are the backstop. |
| `git mv` fails / loses history | `ops/` files are all git-tracked (verified) → `git mv` works and preserves history (AC3 asserts `--follow` rename detection). The untracked-dir fallback is documented but not needed. |
| grep-verify silently false-clean (the `grep -v` prefix bug from learning 2026-03-21) | Two-method cross-check: AC4 (count) + AC5 (file list must contain ONLY archive + this plan). If AC4 says 0 but AC5 lists a non-archive file, AC4 lied — trust AC5. |
| Historical plan/spec links to `ops/` left stale | Intentional for `**/archive/**` (immutable records). Active plans/specs ARE swept so live links stay valid. |
| Stale doc link reaches an operator before re-grep catches it | Caught pre-merge by AC4/AC5; no production data path involved. Brand-survival threshold: none. |

## Sharp Edges

- **Phase order is load-bearing:** the reference sweep (Phase 2) MUST run AFTER the `git mv` (Phase 1), because the 11 self-referencing files inside the moved tree are only found at their NEW `operations/` paths by the post-move `git grep -rIl`. Running the sweep first would miss them (they'd still be at `ops/` paths and the sweep would fix their content but then the move would relocate already-fixed files — also fine, but rebuilding the file list after the move is the robust order).
- **`grep -v "engineering/operations"` is safe here but not by accident:** it works because `ops` ≠ substring of `operations`. Do NOT reuse this verification idiom for a rename where the new name CONTAINS the old as a substring (e.g., `foo` → `foobar`) — there the `grep -v` would false-clean.
- **The lone `engineering/ops)` prose token** lives in an archived plan and is correctly excluded by the `/archive/` filter — it is conceptual prose ("the current task's topic"), not a path.
- **`skill-freshness.json` is a no-op trap:** it ALREADY uses `operations/`. A careless implementer might "fix" a non-existent `ops/` reference for it — there is none. Verify, don't edit (AC6).
