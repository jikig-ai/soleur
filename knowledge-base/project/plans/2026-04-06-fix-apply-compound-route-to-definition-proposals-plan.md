---
title: "fix: apply compound route-to-definition proposals"
type: fix
date: 2026-04-06
---

# fix: Apply Compound Route-to-Definition Proposals

## Problem

The compound skill's headless mode now correctly files GitHub issues instead of skipping route-to-definition proposals (fixed in #1299). Three such issues have accumulated and need to be resolved by applying the proposed edits to their target skill definition files:

| Issue | Target File | Source Learning | Proposal Summary |
|-------|-------------|-----------------|------------------|
| [#1572](https://github.com/jikig-ai/soleur/issues/1572) | `plugins/soleur/skills/work/SKILL.md` | `security-issues/bwrap-sandbox-three-layer-docker-fix-20260405.md` | Docker seccomp `includes.caps` is compile-time, not runtime -- test with `--privileged` first to establish baseline |
| [#1564](https://github.com/jikig-ai/soleur/issues/1564) | `plugins/soleur/skills/work/SKILL.md` | `integration-issues/stale-env-deploy-pipeline-terraform-bridge-20260405.md` | `terraform_data` provisioner inline heredoc strings desync from `triggers_replace` hash -- extract to standalone files |
| [#1556](https://github.com/jikig-ai/soleur/issues/1556) | `plugins/soleur/skills/one-shot/SKILL.md` | `2026-04-05-graceful-sigterm-shutdown-node-patterns.md` | `gh pr create --draft` fails with "No commits between branches" -- handle gracefully or defer to after first commit |

## Proposed Fix

### Edit 1: work/SKILL.md -- Infrastructure Validation (bwrap/seccomp) [#1572]

**Target section:** Phase 2, step 6 "Infrastructure Validation" -- add as a new bullet after the existing cloud-init/lifecycle bullet (line 321)

**Proposed bullet:**

```markdown
   - When fixing syscall-level issues in Docker containers, test with `--privileged` first to establish a working baseline, then remove privileges one at a time. Docker's seccomp `includes.caps` is compile-time (evaluated when building BPF filter), not runtime -- processes gaining capabilities inside user namespaces do NOT gain access to capability-gated seccomp rules.
```

**Rationale:** This is a non-obvious gotcha specific to infrastructure work that the `/work` skill governs. The existing Infrastructure Validation section already has one cloud-init/Terraform gotcha bullet -- this adds a Docker-specific one.

### Edit 2: work/SKILL.md -- Infrastructure Validation (Terraform provisioner) [#1564]

**Target section:** Phase 2, step 6 "Infrastructure Validation" -- add as a new bullet after Edit 1's bullet

**Proposed bullet:**

```markdown
   - When a `terraform_data` provisioner writes a systemd unit or config file via `remote-exec` heredoc, extract the content to a standalone file and use `file()` in both `triggers_replace` and a `file` provisioner. Inline heredoc strings desync from the trigger hash -- partial strings in `triggers_replace` silently skip re-provisioning when the unit content changes.
```

**Rationale:** This is a Terraform-specific sharp edge that directly relates to the Infrastructure Validation section. The existing bullet already covers `terraform_data` provisioners with `remote-exec` -- this adds the `triggers_replace` gotcha.

### Edit 3: one-shot/SKILL.md -- Step 0c graceful failure [#1556]

**Target section:** Step 0c "Create draft PR" -- add a note after the existing failure handling text (line 28)

**Current text (lines 27-29):**

```markdown
If this fails (no network), print a warning but continue. The branch exists locally.
```

**Proposed replacement:**

```markdown
If this fails (no network, or "No commits between main and <branch>"), print a warning but continue. The branch exists locally and the `/ship` phase will create the PR after implementation commits exist.
```

**Rationale:** The current text only mentions network failure. The "No commits between branches" error is a common case when the draft PR is created immediately after branching (before any commits exist). This edit makes the existing graceful-degradation instruction cover the additional failure mode.

## Acceptance Criteria

- [ ] work/SKILL.md Infrastructure Validation section has two new bullets (Docker seccomp and Terraform triggers_replace)
- [ ] one-shot/SKILL.md Step 0c failure handling covers "No commits between branches" error
- [ ] All three source learning files exist and are referenced correctly
- [ ] GitHub issues #1556, #1564, and #1572 are closed with `Closes #N` in PR body
- [ ] Markdown lint passes on both modified files
- [ ] Source learning `synced_to` frontmatter is updated for each applied edit

## Test Scenarios

- Given work/SKILL.md is read after edits, the Infrastructure Validation section (step 6) contains a bullet about Docker seccomp `includes.caps` being compile-time
- Given work/SKILL.md is read after edits, the Infrastructure Validation section (step 6) contains a bullet about `terraform_data` provisioner `triggers_replace` desync
- Given one-shot/SKILL.md is read after edits, Step 0c failure handling text mentions "No commits between main and" as a handled failure case
- Given `npx markdownlint-cli2` is run on both modified files, then exit code is 0

## Context

### Files to Modify

1. `plugins/soleur/skills/work/SKILL.md` -- Add two bullets to Infrastructure Validation section (step 6, after line 321)
2. `plugins/soleur/skills/one-shot/SKILL.md` -- Expand Step 0c failure handling text (line 28)

### Files to Update (synced_to frontmatter)

1. `knowledge-base/project/learnings/security-issues/bwrap-sandbox-three-layer-docker-fix-20260405.md` -- Add/update `synced_to` with `work`
2. `knowledge-base/project/learnings/integration-issues/stale-env-deploy-pipeline-terraform-bridge-20260405.md` -- Add/update `synced_to` with `work`
3. `knowledge-base/project/learnings/2026-04-05-graceful-sigterm-shutdown-node-patterns.md` -- Add/update `synced_to` with `one-shot`

### Why Apply All Three Together

These are all compound route-to-definition proposals -- same origin mechanism, same review pattern, same type of edit (adding sharp-edge bullets to skill definitions). Batching them into one PR is cleaner than three separate branches for single-bullet additions.

### Sharp Edges

1. **Verify indentation matches existing bullets.** The work/SKILL.md Infrastructure Validation bullets use 3-space indentation (under a numbered list item). New bullets must match exactly or markdownlint will flag inconsistency.
2. **Check for duplicate content.** Before adding each bullet, grep the target file for key phrases from the proposed edit to avoid duplication if the edit was partially applied in a prior session.
3. **Update synced_to arrays, not overwrite.** If the learning already has a `synced_to` field, append to the array -- do not replace it.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal tooling/workflow improvement applying pre-approved proposals to skill definition files.

## References

- Issue: [#1572](https://github.com/jikig-ai/soleur/issues/1572) -- route-to-definition proposal for work SKILL.md (bwrap/seccomp)
- Issue: [#1564](https://github.com/jikig-ai/soleur/issues/1564) -- route-to-definition proposal for work/SKILL.md (Terraform triggers)
- Issue: [#1556](https://github.com/jikig-ai/soleur/issues/1556) -- route-to-definition proposal for one-shot SKILL.md (draft PR failure)
- Prior fix: [#1299](https://github.com/jikig-ai/soleur/issues/1299) -- compound route-to-definition should file issues in pipeline mode
- Learning: `2026-03-30-compound-headless-issue-filing-over-auto-accept.md`
