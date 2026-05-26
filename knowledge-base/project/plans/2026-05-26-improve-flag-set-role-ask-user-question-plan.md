---
title: "improve: flag-set-role should use AskUserQuestion for operator ack"
type: feat
date: 2026-05-26
lane: single-domain
---

# improve: flag-set-role should use AskUserQuestion for operator ack

## Overview

`flag-set-role/scripts/flip.sh` uses a raw `read -p` terminal prompt for operator acknowledgment (line 251). This breaks the agent-driven UX: the agent cannot pipe input into the prompt, forcing it to either expose raw CLI commands to the operator or bypass the script entirely (as happened during the 2026-05-26 TEAM_WORKSPACE_INVITE_ENABLED flag-flip session). The fix adds a `--confirmed` flag to `flip.sh` that skips the `read -p` prompt, and updates SKILL.md to instruct the agent to use `AskUserQuestion` before passing `--confirmed`. All precondition checks (fallback-fidelity, segment resolution, arg validation) remain unchanged.

**Precedent:** `git-worktree/scripts/worktree-manager.sh` uses `--yes` for the same pattern (line 54: `# Auto-confirm flag (--yes skips all interactive prompts)`). The deploy skill uses `AskUserQuestion` for operator ack before running `deploy.sh`. This change aligns `flag-set-role` with both established patterns.

**Scope note:** Sibling scripts `flag-create/scripts/create.sh:77` and `user-set-role/scripts/set-role.sh:82` have the same `read -p` pattern. These are tracked as follow-up work, not in scope for this PR.

## User-Brand Impact

- **If this lands broken, the user experiences:** flag flip silently runs without operator confirmation (the `--confirmed` flag bypasses the ack gate)
- **If this leaks, the user's workflow is exposed via:** N/A -- no data exposure; the change is UX-only on operator-side tooling
- **Brand-survival threshold:** `none`

## Files to Edit

| File | Change |
|------|--------|
| `plugins/soleur/skills/flag-set-role/scripts/flip.sh` | Add `--confirmed` flag parsing; skip `read -p` block when set; keep all other checks |
| `plugins/soleur/skills/flag-set-role/SKILL.md` | Update Procedure section: agent uses AskUserQuestion with pre/post matrix, then passes `--confirmed`; update Arguments to document `--confirmed` |

## Files to Create

None.

## Open Code-Review Overlap

None.

## Implementation Phases

### Phase 1: Add `--confirmed` flag to `flip.sh`

**Contract change (must come first per plan-phase-order rule).**

1. In the arg-parsing block (lines 46-59), add a `--confirmed` case **before the `--*)` catch-all** (line 51 -- the catch-all would otherwise intercept `--confirmed` and exit 2):
   ```bash
   --confirmed) CONFIRMED=1; shift ;;
   ```
   Initialize `CONFIRMED=0` alongside `DRY_RUN=0` (line 39).

2. Replace the interactive prompt block (lines 249-252):
   ```bash
   # --- operator ack ----------------------------------------------------------
   echo
   read -p "Proceed? Type 'yes' to apply: " ACK
   [[ "$ACK" == "yes" ]] || { echo "aborted (ack was '$ACK')" >&2; exit 0; }
   ```
   With:
   ```bash
   # --- operator ack ----------------------------------------------------------
   if [[ $CONFIRMED -eq 0 ]]; then
     echo
     read -p "Proceed? Type 'yes' to apply: " ACK
     [[ "$ACK" == "yes" ]] || { echo "aborted (ack was '$ACK')" >&2; exit 0; }
   else
     echo "(--confirmed: skipping interactive prompt)"
   fi
   ```

3. Update the `usage()` function (line 62) to include `--confirmed`:
   ```bash
   echo "Usage: flip.sh <flag> <prd|dev> <on|off> [--confirmed] [--target role|org] [--org <orgId>] [--dry-run]" >&2
   ```

4. Update the script header comment (line 7) to document the flag:
   ```bash
   # Usage: bash flip.sh <flag> <prd|dev> <on|off> [--confirmed] [--dry-run]
   ```

**Key invariant:** All precondition checks (prerequisite validation, fallback-fidelity rule, segment resolution, Doppler token fetch) still run regardless of `--confirmed`. The flag skips ONLY the `read -p` prompt.

### Phase 2: Update SKILL.md

1. **Arguments section** (line 30): Add `--confirmed` documentation:
   ```
   Flag `--confirmed` skips the interactive `read -p` prompt (for agent-driven use; the agent must obtain operator ack via AskUserQuestion before passing this flag).
   ```

2. **Procedure section** (lines 40-57): Update Step 6 (Operator ack) to describe the agent-driven flow:
   - The agent runs the script with `--dry-run` first to get the pre/post matrix output (exits 0, no writes, no prompt).
   - The agent presents the matrix to the operator via **AskUserQuestion** with options: "Yes, apply" / "Cancel".
   - On confirmation, the agent re-runs with `--confirmed` (skips the `read -p` prompt, proceeds to write).
   - On cancel, the agent aborts.
   - **Important:** The agent must NOT run the script without both `--dry-run` and `--confirmed` -- running without either flag would hit the interactive `read -p` prompt and hang the agent shell.

3. **Procedure code block** (line 43): Update to show both forms:
   ```bash
   # Dry-run to see the matrix:
   bash plugins/soleur/skills/flag-set-role/scripts/flip.sh <flag> <role> <on|off> --dry-run
   # After AskUserQuestion confirmation:
   bash plugins/soleur/skills/flag-set-role/scripts/flip.sh <flag> <role> <on|off> --confirmed
   ```

## Acceptance Criteria

- [ ] **AC1:** `flip.sh --confirmed` skips the `read -p` prompt and proceeds directly to the audit + Flagsmith write steps.
  Verification: `grep -c 'read -p' plugins/soleur/skills/flag-set-role/scripts/flip.sh` returns 1 (still present, guarded by `CONFIRMED` check).
- [ ] **AC2:** `flip.sh` without `--confirmed` still prompts interactively (backward compatible).
  Verification: `grep -A2 'CONFIRMED -eq 0' plugins/soleur/skills/flag-set-role/scripts/flip.sh | grep -c 'read -p'` returns 1.
- [ ] **AC3:** All precondition checks (arg validation, fallback-fidelity rule, prerequisite checks) run regardless of `--confirmed`.
  Verification: `--confirmed` flag case appears ONLY in the operator-ack block, NOT in the prerequisite or fallback-fidelity sections. `grep -n 'CONFIRMED' plugins/soleur/skills/flag-set-role/scripts/flip.sh` shows exactly 3 occurrences: initialization, arg-parse case, and the ack-guard if-block.
- [ ] **AC4:** SKILL.md Procedure section instructs the agent to use **AskUserQuestion** before passing `--confirmed`.
  Verification: `grep -c 'AskUserQuestion' plugins/soleur/skills/flag-set-role/SKILL.md` returns >= 1.
- [ ] **AC5:** SKILL.md Arguments section documents `--confirmed`.
  Verification: `grep -c '\-\-confirmed' plugins/soleur/skills/flag-set-role/SKILL.md` returns >= 2 (Arguments + Procedure).

## Test Scenarios

- Given the agent runs `flip.sh kb-chat-sidebar prd on --dry-run`, when the script completes, then the pre/post matrix is printed and exit code is 0 (no prompt).
- Given the agent runs `flip.sh kb-chat-sidebar prd on --confirmed`, when preconditions pass, then the script proceeds to audit + Flagsmith write without prompting.
- Given the agent runs `flip.sh kb-chat-sidebar prd on` (no `--confirmed`), when the script reaches the ack block, then it prompts interactively via `read -p`.
- Given the agent runs `flip.sh kb-chat-sidebar dev off --confirmed` while prd is on, when the fallback-fidelity rule fires, then the script exits 1 regardless of `--confirmed`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `--confirmed` bypasses safety ack | The flag skips ONLY the terminal prompt; all precondition checks (fallback-fidelity, segment resolution, Doppler auth) still run. The agent is instructed to use AskUserQuestion first, preserving the intent of `hr-menu-option-ack-not-prod-write-auth`. |
| Sibling scripts diverge | Follow-up issues for `flag-create` and `user-set-role` to apply the same pattern. Noted in scope note above. |

## Alternative Approaches Considered

| Approach | Why Not |
|----------|---------|
| Pipe `echo "yes"` into stdin | Fragile; depends on shell TTY behavior; violates the spirit of `hr-menu-option-ack-not-prod-write-auth` |
| Remove the prompt entirely | Loses operator protection; silent prod writes are the failure mode the ack prevents |
| Use `--yes` like worktree-manager | `--confirmed` is more specific -- `--yes` implies blanket consent; `--confirmed` implies the ack already happened elsewhere (at the AskUserQuestion layer). Either name works; `--confirmed` chosen per issue #4503 spec. |

## Context

Surfaced during the TEAM_WORKSPACE_INVITE_ENABLED flag-flip session (2026-05-26). The agent had to work around the interactive prompt by calling the Flagsmith API directly, bypassing the skill's precondition checks and audit trail.

## References

- Issue: #4503
- `hr-menu-option-ack-not-prod-write-auth` (AGENTS.core.md:32)
- Precedent: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` `--yes` flag (line 54)
- Precedent: `plugins/soleur/skills/deploy/SKILL.md` AskUserQuestion pattern (line 40)
- Sibling scripts with same problem: `plugins/soleur/skills/flag-create/scripts/create.sh:77`, `plugins/soleur/skills/user-set-role/scripts/set-role.sh:82`
