---
title: "fix: apply compound route-to-definition proposals (batch 2)"
type: fix
date: 2026-04-06
---

# fix: Apply Compound Route-to-Definition Proposals (Batch 2)

Five route-to-definition GitHub issues have accumulated from compound-capture headless mode. Four need edits applied to skill definition files. One (#1597) is already fixed in the current codebase and should be closed as stale.

## Problem

The compound skill's headless mode creates GitHub issues for proposed route-to-definition edits (per compound-capture Step 8.4). A second batch of 5 issues needs resolution:

| Issue | Target File | Source Learning | Proposal Summary | Status |
|-------|-------------|-----------------|------------------|--------|
| [#1581](https://github.com/jikig-ai/soleur/issues/1581) | `plugins/soleur/skills/ship/SKILL.md` | `2026-04-06-terraform-data-connection-block-no-auto-replace.md` | Enumerate ALL `terraform_data`/`null_resource` connection block changes when creating follow-through issues | Needs edit |
| [#1597](https://github.com/jikig-ai/soleur/issues/1597) | `plugins/soleur/skills/one-shot/SKILL.md` | `integration-issues/sentry-api-boolean-search-not-supported-20260406.md` | Fix wrong script path for setup-ralph-loop.sh | Already fixed -- close |
| [#1601](https://github.com/jikig-ai/soleur/issues/1601) | `plugins/soleur/skills/work/SKILL.md` | `test-failures/2026-04-06-vitest-mock-hoisting-requires-vi-hoisted.md` | Add `vi.hoisted()` guidance for vitest mock factories | Needs edit |
| [#1614](https://github.com/jikig-ai/soleur/issues/1614) | `plugins/soleur/skills/work/SKILL.md` | `security-issues/canary-crash-leaks-env-file-ci-deploy-20260406.md` | Add `replace_all` grep verification step | Needs edit |
| [#1616](https://github.com/jikig-ai/soleur/issues/1616) | `plugins/soleur/skills/one-shot/SKILL.md` | `2026-04-06-doppler-cli-checksum-cloud-init.md` | Place subagent return format instruction as LAST line with CRITICAL prefix | Needs edit |
| [#1621](https://github.com/jikig-ai/soleur/issues/1621) | `AGENTS.md` | `integration-issues/2026-04-06-doppler-stderr-contaminates-docker-env-file.md` | Add terraform + doppler name-transformer bullet to Code Quality | Needs edit |

## Proposed Fix

### Edit 1: work/SKILL.md -- vitest vi.hoisted() guidance [#1601]

**Target section:** Phase 2, TDD Gate -- add as a new bullet after the existing `vi.mock()` bullet (line 241)

**Proposed bullet:**

```markdown
   - When creating test files with `vi.mock()` factories that reference shared variables, use `vi.hoisted()` from the start -- vitest hoists `vi.mock` to the top of the file before `const`/`let` declarations execute.
```

**Rationale:** The existing bullet at line 241 covers `vi.mock()` file-level scoping. This bullet extends that with the `vi.hoisted()` pattern for mock variable references -- a closely related vitest gotcha.

### Edit 2: work/SKILL.md -- replace_all grep verification [#1614]

**Target section:** Common Pitfalls to Avoid -- add as a new bullet

**Proposed bullet:**

```markdown
- **Incomplete replace_all** - After any `replace_all` Edit operation, grep the file to verify zero remaining matches before proceeding to the next task. `replace_all` can miss occurrences with different surrounding context (whitespace, indentation).
```

**Rationale:** This is a pitfall, not a test execution concern. It fits the "Common Pitfalls to Avoid" section pattern (bold label + dash + explanation). Source: #1502 fix where `replace_all` replaced 3 of 4 `cleanup_env_file` calls due to whitespace differences.

### Edit 3: ship/SKILL.md -- terraform resource enumeration in follow-through [#1581]

**Target section:** Phase 7, Step 3.5 Follow-Through, after "Step 3" (line 675) -- add as an instruction note after the issue creation step, before the issue body template

**Proposed bullet (add after the "Default to 'Post-MVP / Later' if unclear." line at 684):**

```markdown

   When follow-through items reference `terraform apply -replace`, enumerate ALL affected resources by scanning the full PR diff for `terraform_data` and `null_resource` connection block changes -- not just the resource named in the PR title or description. Use `git diff MERGE_BASE..HEAD -- '*.tf' | grep -E '(terraform_data|null_resource)' | grep -E '(connection|provisioner)'` to detect all changed provisioner blocks.
```

**Rationale:** Issue #1567 only mentioned `disk_monitor_install` but the PR also modified `deploy_pipeline_fix`. The plan phase caught this, but the ship skill's follow-through step should detect all affected resources proactively.

### Edit 4: one-shot/SKILL.md -- subagent return format compliance [#1616]

**Target section:** Steps 1-2 subagent prompt (the Task general-purpose block starting at line 34)

**Current contract text (line 62):**

```markdown
Do NOT proceed beyond deepen-plan. Do NOT start work."
```

**Proposed replacement:**

```markdown
Do NOT proceed beyond deepen-plan. Do NOT start work.

CRITICAL: You MUST output the ## Session Summary section in EXACTLY the format above. Place it as the last thing in your output."
```

**Rationale:** Subagents frequently ignore mid-prompt format requirements. Moving the format instruction to the LAST line with CRITICAL prefix maximizes compliance. Source: #1500 session where the planning subagent did not return the exact `## Session Summary` format.

### Edit 5: AGENTS.md -- terraform + doppler name-transformer [#1621]

**Target section:** Code Quality -- add as a new bullet

**Proposed bullet:**

```markdown
- When running terraform commands locally with Doppler, always use `doppler run --name-transformer tf-var` to match CI behavior. Export `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` separately for the R2 backend — the name transformer renames them to `TF_VAR_*` which the backend ignores.
```

**Rationale:** Source learning documents how Doppler's name transformer flag interacts with Terraform's R2 backend credentials. This is a recurring gotcha when running `terraform plan`/`apply` locally.

### Close: #1597 (stale -- already fixed)

**Action:** Close issue #1597 with a comment explaining the one-shot SKILL.md already has the correct path `plugins/soleur/scripts/setup-ralph-loop.sh` (line 11). The wrong path `plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` does not appear in the file. No edit needed.

## Acceptance Criteria

- [x] work/SKILL.md TDD Gate section has new `vi.hoisted()` bullet after existing `vi.mock()` bullet
- [x] work/SKILL.md Common Pitfalls section has new `replace_all` verification bullet
- [x] ship/SKILL.md Phase 7 Step 3.5 has new terraform resource enumeration instruction
- [x] one-shot/SKILL.md subagent prompt has CRITICAL format compliance instruction at the end
- [x] Issue #1597 is closed as stale with explanatory comment
- [x] AGENTS.md Code Quality section has new terraform + doppler name-transformer bullet
- [ ] GitHub issues #1581, #1601, #1614, #1616, #1621 are closed with `Closes #N` in PR body
- [x] Markdown lint passes on all modified files
- [x] Source learning `synced_to` frontmatter is updated for each applied edit

## Test Scenarios

- Given work/SKILL.md is read after edits, the TDD Gate section contains a bullet about `vi.hoisted()` for shared mock variables
- Given work/SKILL.md is read after edits, the Common Pitfalls section contains a bullet about `replace_all` grep verification
- Given ship/SKILL.md is read after edits, Step 3.5 contains an instruction about scanning the full PR diff for `terraform_data` and `null_resource` changes
- Given one-shot/SKILL.md is read after edits, the subagent prompt ends with a CRITICAL format compliance instruction
- Given `npx markdownlint-cli2` is run on all three modified files, then exit code is 0

## Context

### Files to Modify

1. `plugins/soleur/skills/work/SKILL.md` -- Two bullets: vi.hoisted() after line 241, replace_all in Common Pitfalls
2. `plugins/soleur/skills/ship/SKILL.md` -- One instruction note after line 684 in Step 3.5
3. `plugins/soleur/skills/one-shot/SKILL.md` -- Expand subagent return contract at line 62
4. `AGENTS.md` -- One bullet in Code Quality for terraform + doppler name-transformer

### Files to Update (synced_to frontmatter -- #1621 targets AGENTS.md so no synced_to update needed)

1. `knowledge-base/project/learnings/test-failures/2026-04-06-vitest-mock-hoisting-requires-vi-hoisted.md` -- Add `synced_to: [work]` after `tags` field
2. `knowledge-base/project/learnings/security-issues/canary-crash-leaks-env-file-ci-deploy-20260406.md` -- Add `synced_to: [work]` after `tags` field
3. `knowledge-base/project/learnings/2026-04-06-terraform-data-connection-block-no-auto-replace.md` -- Append `ship` to existing `synced_to: []` array
4. `knowledge-base/project/learnings/2026-04-06-doppler-cli-checksum-cloud-init.md` -- Add `synced_to: [one-shot]` after `tags` field

### Why Apply All Together

Same as batch 1: these are all compound route-to-definition proposals -- same origin mechanism, same review pattern, same type of edit. Batching into one PR is cleaner than separate branches for single-bullet additions.

### Sharp Edges

1. **Verify indentation matches existing bullets.** work/SKILL.md TDD Gate bullets use 3-space indentation. Common Pitfalls bullets use 0-space indentation with bold labels. ship/SKILL.md Step 3.5 uses 3-space indentation for paragraph content. Match exactly.
2. **Check for duplicate content before editing.** Grep each target file for key phrases from the proposed edit. Already verified: `vi.hoisted`, `replace_all.*grep`, `enumerate.*resource`, `CRITICAL.*format` return zero matches in their respective target files.
3. **Handle synced_to frontmatter differences.** The terraform learning already has `synced_to: []` (empty array) -- append `ship`. The other three have no `synced_to` field -- add after `tags`.
4. **Edit 4 is a replacement, not an append.** The one-shot subagent prompt ending needs the closing quote `"` to be moved after the new CRITICAL instruction. Use the Edit tool's exact string matching on the closing line.
5. **#1597 requires only a close, no file edit.** Do not modify one-shot/SKILL.md for this issue. The fix is already present. Verify with grep before closing.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal tooling/workflow improvement applying pre-approved proposals to skill definition files.

## MVP

| Phase | Tasks |
|-------|-------|
| 1. Apply Edits | Edit work/SKILL.md (2 bullets), ship/SKILL.md (1 instruction), one-shot/SKILL.md (1 expansion), AGENTS.md (1 bullet) |
| 2. Update Frontmatter | Update `synced_to` in 4 learning files |
| 3. Close Stale | Close #1597 with explanatory comment |
| 4. Verify | Run markdownlint on all 3 modified skill files |

## References

- Issue: [#1581](https://github.com/jikig-ai/soleur/issues/1581) -- route-to-definition proposal for ship SKILL.md
- Issue: [#1597](https://github.com/jikig-ai/soleur/issues/1597) -- route-to-definition proposal for one-shot SKILL.md (stale)
- Issue: [#1601](https://github.com/jikig-ai/soleur/issues/1601) -- route-to-definition proposal for work SKILL.md (vi.hoisted)
- Issue: [#1614](https://github.com/jikig-ai/soleur/issues/1614) -- route-to-definition proposal for work SKILL.md (replace_all)
- Issue: [#1616](https://github.com/jikig-ai/soleur/issues/1616) -- route-to-definition proposal for one-shot SKILL.md (subagent format)
- Issue: [#1621](https://github.com/jikig-ai/soleur/issues/1621) -- route-to-definition proposal for AGENTS.md (terraform + doppler name-transformer)
- Prior batch: `knowledge-base/project/plans/2026-04-06-fix-apply-compound-route-to-definition-proposals-plan.md`
