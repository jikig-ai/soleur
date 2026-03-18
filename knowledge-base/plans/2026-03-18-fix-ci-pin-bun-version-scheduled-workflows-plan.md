---
title: "fix(ci): pin bun-version in scheduled workflows"
type: fix
date: 2026-03-18
---

# fix(ci): pin bun-version in scheduled workflows

Two scheduled workflows use `oven-sh/setup-bun` without specifying `bun-version`, defaulting to `latest`. A breaking Bun release could fail these workflows for reasons unrelated to the code under test. Pin `bun-version: "1.3.11"` in both files to match `ci.yml`.

## Acceptance Criteria

- [ ] `scheduled-ship-merge.yml` specifies `bun-version: "1.3.11"` in the Setup Bun step (`.github/workflows/scheduled-ship-merge.yml:43`)
- [ ] `scheduled-bug-fixer.yml` specifies `bun-version: "1.3.11"` in the Setup Bun step (`.github/workflows/scheduled-bug-fixer.yml:48`)
- [ ] Both `with:` blocks match the format used in `ci.yml` (`.github/workflows/ci.yml:17-19`)
- [ ] Version comment on `scheduled-ship-merge.yml` line 43 updated from `# v2` to `# v2.1.2` for consistency with the other two files
- [ ] No other workflows in `.github/workflows/` use `setup-bun` without a pinned version (verified -- only these three files use the action)

## Test Scenarios

- Given the `scheduled-ship-merge.yml` workflow, when the Setup Bun step runs, then Bun 1.3.11 is installed (not latest)
- Given the `scheduled-bug-fixer.yml` workflow, when the Setup Bun step runs, then Bun 1.3.11 is installed (not latest)
- Given all three workflow files using `setup-bun`, when inspected, then all specify `bun-version: "1.3.11"` and use action SHA `3d267786b128fe76c2f16a390aa2448b815359f3` with comment `# v2.1.2`

## Context

Found during security review of #715 (commit `83ddb2b`). The learning `knowledge-base/learnings/2026-03-18-bun-test-segfault-missing-deps.md` documents that Bun 1.3.5 segfaults on missing dependencies -- pinning the version in CI protects against regressions from untested Bun releases.

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

## References

- Issue: #717
- Related PR: #715 (where this gap was found)
- Learning: `knowledge-base/learnings/2026-03-18-bun-test-segfault-missing-deps.md`
- CI reference: `.github/workflows/ci.yml:17-19` (canonical pinned version)
