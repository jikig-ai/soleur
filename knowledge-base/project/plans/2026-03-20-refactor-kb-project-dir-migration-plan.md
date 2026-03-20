---
title: "refactor: complete knowledge-base project directory migration"
type: refactor
date: 2026-03-20
---

# Complete Knowledge-Base Project Directory Migration

Merge 4 top-level workflow directories (`brainstorms/`, `specs/`, `learnings/`, `plans/`) into their existing counterparts under `knowledge-base/project/`. Update the handful of remaining source references.

## Context

The migration to `knowledge-base/project/` was mostly completed — most skills and scripts already reference `project/` paths. However, 291 files remain in top-level dirs (newer content created after the migration stalled), and a few source files still reference old paths.

**Brainstorm:** `knowledge-base/project/brainstorms/2026-03-20-kb-project-dir-migration-brainstorm.md`

### Corrections from SpecFlow Analysis

The brainstorm overestimated the blast radius. Key corrections:

1. **AGENTS.md reference is CORRECT** — `knowledge-base/project/constitution.md` exists. Decision #4 ("fix broken reference") was wrong and must NOT be implemented.
2. **Most plugin files already use `project/` paths** — only 2 source file lines reference old paths (a comment and a test literal).
3. **Actual files to move: 291** (not ~870) — 8 brainstorms, 66 learnings, 73 plans, 144 specs.
4. **The actual non-project KB dirs are:** `engineering/`, `marketing/`, `operations/`, `product/`, `sales/`, `support/` — not `audits/`, `community/`, `design/`, `ops/` as the brainstorm listed.
5. **`workspace.ts` is production code** that provisions user workspaces with old-style paths — must be updated.

## Acceptance Criteria

- [ ] All files from `knowledge-base/{brainstorms,specs,learnings,plans}/` merged into `knowledge-base/project/{brainstorms,specs,learnings,plans}/`
- [ ] Top-level workflow dirs removed (Git auto-removes empty dirs)
- [ ] `workspace.ts` updated to create `project/` subdirectory paths
- [ ] `workspace.test.ts` and `canusertool-sandbox.test.ts` updated
- [ ] `scripts/test-all.sh` comment updated
- [ ] Cross-referencing content files (~139) updated with new paths via best-effort sed
- [ ] Zero old-path references in source files: `grep -rn "knowledge-base/(brainstorms|specs|learnings|plans)/" plugins/ scripts/ apps/ .github/ AGENTS.md` (excluding `knowledge-base/project/`)

## Test Scenarios

- Given files at `knowledge-base/project/brainstorms/`, when migration runs, then files exist at `knowledge-base/project/brainstorms/` and old dir is gone
- Given `workspace.ts` creates dirs, when a new user is provisioned, then dirs are created under `knowledge-base/project/`
- Given archive dirs exist in both locations, when migration runs, then archive files merge without overwriting

## Implementation

### Phase 1: Move files and update references

**Step 1: Move files with direct `git mv` commands.**

No committed script — run interactively, verify, commit. `git mv` handles directories recursively.

```bash
# Move top-level files from each workflow dir
for dir in brainstorms learnings plans specs; do
  git mv "knowledge-base/$dir"/* "knowledge-base/project/$dir/" 2>/dev/null || true
done

# Handle subdirectories that need individual file moves (archive dirs exist in both locations)
# For plans/archive and specs/archive, move files individually since target dirs exist
for dir in plans specs; do
  if [[ -d "knowledge-base/$dir/archive" ]]; then
    find "knowledge-base/$dir/archive" -type f -exec bash -c '
      f="$1"; dir="$2"
      rel="${f#knowledge-base/$dir/archive/}"
      target="knowledge-base/project/$dir/archive/$rel"
      mkdir -p "$(dirname "$target")"
      git mv "$f" "$target"
    ' _ {} "$dir" \;
  fi
done

# Move remaining feature subdirs under specs (e.g., specs/feat-*/*)
find "knowledge-base/specs" -mindepth 1 -maxdepth 1 -type d ! -name archive -exec bash -c '
  subdir="$1"; name="$(basename "$subdir")"
  mkdir -p "knowledge-base/project/specs/$name"
  git mv "$subdir"/* "knowledge-base/project/specs/$name/" 2>/dev/null || true
' _ {} \;
```

If any `git mv` fails on a specific file, fall back to `git add <file> && git mv <file> <dest>` for untracked files.

**Step 2: Update 4 source files.**

1. **`apps/web-platform/server/workspace.ts`** (line 46-48): Nest KB dirs under `project/`

   ```typescript
   // Before:
   for (const sub of KNOWLEDGE_BASE_DIRS) {
     ensureDir(join(kbRoot, sub));
   }

   // After:
   const projectDir = join(kbRoot, "project");
   ensureDir(projectDir);
   for (const sub of KNOWLEDGE_BASE_DIRS) {
     ensureDir(join(projectDir, sub));
   }
   ```

2. **`apps/web-platform/test/workspace.test.ts`**: Update assertions to expect `project/` subdirectories
3. **`apps/web-platform/test/canusertool-sandbox.test.ts`** (line 23): `knowledge-base/project/plans/plan.md` → `knowledge-base/project/plans/plan.md`
4. **`scripts/test-all.sh`** (line 6): Update comment path

**Step 3: Best-effort sed on content cross-references (~139 files).**

Kieran's review found 139 files with cross-directory references (plans → learnings, specs → plans, etc.). The original sed loop only handled intra-directory refs. Fixed to search all 4 patterns across all moved files:

```bash
# Replace all 4 old-path patterns across ALL moved content files
for search_dir in brainstorms learnings plans specs; do
  find knowledge-base/project/{brainstorms,learnings,plans,specs} -name "*.md" \
    -exec grep -l "knowledge-base/$search_dir/" {} + 2>/dev/null | while read -r f; do
      sed -i "s|knowledge-base/$search_dir/|knowledge-base/project/$search_dir/|g" "$f"
  done
done
```

The sed pattern is double-prefix safe: `knowledge-base/project/plans/` is not a substring of `knowledge-base/project/plans/`, so already-correct paths survive untouched (verified by Kieran).

**Step 4: Verify and commit.**

```bash
# No old-path references in source files
grep -rn -E "knowledge-base/(brainstorms|specs|learnings|plans)/" \
  plugins/ scripts/ apps/ .github/ AGENTS.md CLAUDE.md |
  grep -v "knowledge-base/project/" | grep -c . && echo "FAIL" || echo "PASS"

# No double-prefix
grep -rn "knowledge-base/project/project/" . | grep -c . && echo "FAIL" || echo "PASS"

# Old dirs gone
for d in brainstorms learnings plans specs; do
  [[ -d "knowledge-base/$d" ]] && echo "FAIL: $d still exists" || echo "PASS"
done

# Tests pass
cd apps/web-platform && bun test
```

## Active Feature Branches

These branches have files at old paths and will get merge conflicts after this PR merges:

- `feat-byok-decryption-fix`
- `feat/fix-fetch-metrics`
- `fix-safe-error-msg-837`
- `sec-env-allowlist-723`

**Reconciliation strategy:** After merge, each branch runs `git fetch origin main && git merge origin/main`. Git will report the files as deleted (moved). For each conflicting file, `git mv` it to the new location and continue the merge.

## Out of Scope

- `scheduled-growth-audit.yml` references `knowledge-base/overview/brand-guide.md` (pre-existing bug, separate issue)
- Domain dirs (`engineering/`, `marketing/`, etc.) stay at `knowledge-base/` level — not part of this migration
- `knowledge-base/project/constitution.md` and `knowledge-base/project/README.md` — already in correct location
