---
title: "fix(ci): pin bun-version in scheduled workflows"
type: fix
date: 2026-03-18
---

# fix(ci): pin bun-version in scheduled workflows

## Enhancement Summary

**Deepened on:** 2026-03-18
**Sections enhanced:** 3 (Acceptance Criteria, Context, MVP)
**Research sources:** Context7 `oven-sh/setup-bun` docs, repo grep audit, institutional learnings

### Key Improvements
1. Added `bun-version-file` as a future consolidation option (single source of truth)
2. Confirmed `scheduled-bug-fixer.yml` also lacks `bun install` -- added acceptance criterion
3. Verified full workflow inventory -- no other files use `setup-bun`

---

Two scheduled workflows use `oven-sh/setup-bun` without specifying `bun-version`, defaulting to `latest`. A breaking Bun release could fail these workflows for reasons unrelated to the code under test. Pin `bun-version: "1.3.11"` in both files to match `ci.yml`.

## Acceptance Criteria

- [x] `scheduled-ship-merge.yml` specifies `bun-version: "1.3.11"` in the Setup Bun step (`.github/workflows/scheduled-ship-merge.yml:43`)
- [x] `scheduled-bug-fixer.yml` specifies `bun-version: "1.3.11"` in the Setup Bun step (`.github/workflows/scheduled-bug-fixer.yml:48`)
- [x] Both `with:` blocks match the format used in `ci.yml` (`.github/workflows/ci.yml:17-19`)
- [x] Version comment on `scheduled-ship-merge.yml` line 43 updated from `# v2` to `# v2.1.2` for consistency with the other two files
- [x] No other workflows in `.github/workflows/` use `setup-bun` without a pinned version (verified -- only these three files use the action)

### Research Insights

**`oven-sh/setup-bun` default behavior (from Context7 docs):**
- When `bun-version` is omitted, the action defaults to `latest` -- this means every workflow run could install a different Bun version depending on when it runs.
- The action also supports `bun-version-file` which reads from `.bun-version`, `.tool-versions`, or `package.json`. This is a cleaner long-term solution for keeping all workflows in sync (single source of truth), but out of scope for this fix.

**Audit results:**
- Only 3 workflow files reference `oven-sh/setup-bun`: `ci.yml`, `scheduled-ship-merge.yml`, `scheduled-bug-fixer.yml`. No other workflows install Bun via action or script.
- All three use the same pinned SHA `3d267786b128fe76c2f16a390aa2448b815359f3`, but `scheduled-ship-merge.yml` has an inconsistent version comment (`# v2` vs `# v2.1.2`).

**Edge case -- `scheduled-bug-fixer.yml` lacks `bun install`:**
- `ci.yml` runs `bun install` before `bun test`. `scheduled-ship-merge.yml` runs `bun install --frozen-lockfile`. But `scheduled-bug-fixer.yml` has no explicit `bun install` step -- it relies on the `claude-code-action` agent to install deps as needed. This is acceptable since the agent runs arbitrary commands, but worth noting as a divergence from `ci.yml`.

## Test Scenarios

- Given the `scheduled-ship-merge.yml` workflow, when the Setup Bun step runs, then Bun 1.3.11 is installed (not latest)
- Given the `scheduled-bug-fixer.yml` workflow, when the Setup Bun step runs, then Bun 1.3.11 is installed (not latest)
- Given all three workflow files using `setup-bun`, when inspected, then all specify `bun-version: "1.3.11"` and use action SHA `3d267786b128fe76c2f16a390aa2448b815359f3` with comment `# v2.1.2`

## Context

Found during security review of #715 (commit `83ddb2b`). The learning `knowledge-base/project/learnings/2026-03-18-bun-test-segfault-missing-deps.md` documents that Bun 1.3.5 segfaults on missing dependencies -- pinning the version in CI protects against regressions from untested Bun releases.

### Research Insights

**Institutional learning applied:**
- `2026-03-18-bun-test-segfault-missing-deps.md`: Bun 1.3.5 segfaults with missing `node_modules/`. CI hardening layer 3 pinned `ci.yml` to 1.3.11 but missed the two scheduled workflows. This fix closes that gap.

**Future improvement (out of scope):**
- Consider creating a `.bun-version` file at repo root containing `1.3.11` and switching all three workflows to `bun-version-file: ".bun-version"`. This eliminates version drift between workflow files. File a follow-up issue if desired.

## MVP

### `.github/workflows/scheduled-ship-merge.yml` (lines 42-44)

**Before:**
```yaml
      - name: Setup Bun
        uses: oven-sh/setup-bun@3d267786b128fe76c2f16a390aa2448b815359f3 # v2
```

**After:**
```yaml
      - name: Setup Bun
        uses: oven-sh/setup-bun@3d267786b128fe76c2f16a390aa2448b815359f3 # v2.1.2
        with:
          bun-version: "1.3.11"
```

### `.github/workflows/scheduled-bug-fixer.yml` (lines 47-48)

**Before:**
```yaml
      - name: Setup Bun
        uses: oven-sh/setup-bun@3d267786b128fe76c2f16a390aa2448b815359f3 # v2.1.2
```

**After:**
```yaml
      - name: Setup Bun
        uses: oven-sh/setup-bun@3d267786b128fe76c2f16a390aa2448b815359f3 # v2.1.2
        with:
          bun-version: "1.3.11"
```

### Implementation Notes

- Both edits are identical: add a `with:` block containing `bun-version: "1.3.11"` after the `uses:` line.
- The `scheduled-ship-merge.yml` edit also updates the trailing comment from `# v2` to `# v2.1.2`.
- YAML indentation must match the existing step indentation (8 spaces for `with:`, 10 spaces for `bun-version:`).

## References

- Issue: #717
- Related PR: #715 (where this gap was found)
- Learning: `knowledge-base/project/learnings/2026-03-18-bun-test-segfault-missing-deps.md`
- CI reference: `.github/workflows/ci.yml:17-19` (canonical pinned version)
- Action docs: https://github.com/oven-sh/setup-bun (Context7: `/oven-sh/setup-bun`)
