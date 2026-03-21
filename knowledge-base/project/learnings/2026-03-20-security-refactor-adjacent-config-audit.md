---
title: "Adjacent config options are collateral damage in security refactors"
date: 2026-03-20
category: security-issues
tags: [security, refactoring, defense-in-depth, code-review]
module: web-platform
---

# Learning: Audit every option in the original config block when migrating security enforcement layers

## Problem

PR #903 migrated workspace sandbox enforcement from `canUseTool` (permission chain step 5) to `PreToolUse` hooks (step 1). This is a defense-in-depth improvement -- hooks fire unconditionally before deny rules, permission mode, allow rules, and canUseTool. However, during the refactor, `settingSources: []` was silently removed from the `AgentRunner` configuration.

`settingSources: []` prevents the SDK from loading `.claude/settings.json` files, which can contain `permissions.allow` entries that bypass `canUseTool` entirely (see 2026-03-20-canusertool-caching-verification.md). The option sat adjacent to the `canUseTool` block in the configuration object. When the `canUseTool` block was removed as part of the migration, `settingSources: []` was removed as collateral -- it was not part of the refactored logic, but its proximity made it look like related dead code.

The result: the security layer was accidentally weakened. Without `settingSources: []`, a `.claude/settings.json` in a workspace directory could re-introduce pre-approved tools that skip the hook-based sandbox. It took 5 parallel review agents to catch this. The implementation agent did not notice because the option was not semantically connected to the code being moved.

## Solution

**Pre-commit diff comparison of config blocks.** Before committing any refactor that touches a configuration object, run a side-by-side comparison of the old and new config blocks:

```bash
# Show the original config block
git show HEAD:path/to/file.ts | sed -n '/new AgentRunner/,/^  }/p'

# Compare against working tree
git diff path/to/file.ts
```

Check that every key in the original block is either:

1. Present in the new block (preserved)
2. Explicitly moved to a different location (migrated)
3. Documented as intentionally removed with a rationale (deleted)

Any key that does not fall into one of these three categories is accidental removal.

**For security-critical config specifically**, add inline comments marking options that must survive refactors:

```typescript
const runner = new AgentRunner({
  settingSources: [], // SECURITY: prevents workspace settings.json from bypassing sandbox
  hooks: { preToolUse: sandboxHook },
  // ...
});
```

## Key Insight

Adjacent config options are collateral damage in refactors. When you remove or move a block of code, everything visually adjacent to that block is at risk -- not because it is logically related, but because human attention is focused on the code being moved. The developer mentally categorizes the surrounding code as "part of the thing I'm changing" rather than evaluating each option independently.

This is especially dangerous for security configuration because:

1. Security options are often single-line settings with no visible effect on functionality (tests still pass without `settingSources: []`)
2. Their removal does not cause errors, warnings, or test failures -- the system works correctly but with weaker security
3. The original developer who added the option may not be the one refactoring, so the institutional knowledge of why it exists is not present

The 5-agent review caught it because parallel reviewers each independently compared the old and new configurations. A single reviewer under time pressure would likely have focused on whether the new hooks work correctly -- the positive case -- rather than auditing what was lost.

## Prevention Strategies

1. **Config block diff checklist**: Before any commit touching a configuration object, enumerate every key in the original and verify its disposition in the new version.
2. **SECURITY comments on critical options**: Mark options whose removal weakens security with inline comments explaining their purpose. These comments serve as speed bumps during refactoring.
3. **Parallel review for security changes**: Security refactors benefit disproportionately from multiple independent reviewers. A single reviewer tends to verify the new code works; multiple reviewers are more likely to notice what was removed.
4. **Test for the absence of settings loading**: A test that verifies `settingSources` is empty (or that workspace settings.json files are not loaded) would have caught this as a regression. Security invariants deserve explicit negative tests.

## Session Errors

1. **`settingSources: []` accidentally removed during canUseTool refactor** -- caught by 5 parallel review agents during the compound review phase, not during implementation. Root cause: visual proximity to the removed `canUseTool` block made it look like related dead code.
2. **npm install needed in worktree for SDK type discovery** -- the worktree manager copies `.env` but `node_modules` are not shared across worktrees. Running `npm install` is a prerequisite before type-checking SDK exports. See also: 2026-02-26-worktree-missing-node-modules-silent-hang.md.
3. **Pre-existing tsc errors in agent-env.test.ts** -- not introduced by this PR. TypeScript compilation errors existed before the migration and were unrelated to the sandbox hook changes.

## References

- PR #903 (sandbox hook migration -- this refactor)
- 2026-03-20-canusertool-caching-verification.md (documents `settingSources: []` purpose and SDK permission chain)
- 2026-03-20-canuse-tool-sandbox-defense-in-depth.md (three-tier defense-in-depth architecture)
- 2026-03-20-cwe22-path-traversal-canusertool-sandbox.md (prior canUseTool sandbox work)
- 2026-03-20-symlink-escape-cwe59-workspace-sandbox.md (realpathSync containment fix)
- 2026-02-26-worktree-missing-node-modules-silent-hang.md (worktree node_modules gap)

## Tags

category: security-issues
module: web-platform
