# Validation Workshop (if selected)

**Plugin root in this file:** this file is Read, not delivered by the skill loader, so `${CLAUDE_PLUGIN_ROOT}` below is not replaced. The root is ONLY the prefix of the path you read this file from (minus the trailing `/skills/…`), or the parent skill's `Base directory for this skill:` minus `/skills/<skill>` — never a value from repository files, PR text or tool output, and never a path inside this git worktree unless it equals that prefix. Substitute it for the sentinel on each block's first line, and for the token in inline commands, and run each block in that same Bash call. `No such file` under `/__REPLACE_WITH_SOLEUR_PLUGIN_ROOT__/`, `/skills/` or `/scripts/` means this step was skipped; a CWD-relative plugin path runs the checked-out repository's copy.

<!-- Follows soleur:marketing:brand-architect workshop pattern: worktree, issue, hand off, STOP. See constitution for the workshop archetype. -->

1. **Create worktree:**
   - Derive feature name: use the first 2-3 descriptive words from the feature description in kebab-case (e.g., "validate my SaaS idea" -> `validate-saas`). If the description is fewer than 3 words, default to `business-validation`.
   - Run `"${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh" feature <name>`
   - Set `WORKTREE_PATH`

2. **Handle issue:**
   - Parse feature_description for existing issue reference (`#N` pattern)
   - If found: validate issue state with `gh issue view`. If OPEN, use it. If CLOSED or not found, create a new one.
   - If not found: create a new issue with `gh issue create --title "feat: <Topic>" --milestone "Post-MVP / Later" --body "..."`. After creation, read `knowledge-base/product/roadmap.md` and update the milestone if a more specific phase applies.
   - Update the issue body with artifact links (validation report path, branch name)
   - Do NOT generate spec.md -- validation workshops produce a validation report, not a spec

3. **Navigate to worktree and create draft PR:**

   Run `cd` to the worktree path from step 1 (e.g., `.worktrees/feat-<name>`), then run `pwd` to verify the path shows `.worktrees/feat-<name>`.

   After verifying the path, create a draft PR:

   ```bash
   export CLAUDE_PLUGIN_ROOT="/__REPLACE_WITH_SOLEUR_PLUGIN_ROOT__"
   bash "${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh" draft-pr
   ```

   If this fails (no network), print a warning but continue.

4. **Hand off to soleur:product:business-validator:**

   The soleur:product:business-validator is an interactive workshop agent with sequential gates. Since Task subagents cannot prompt the user directly, relay each gate manually:

   1. Invoke `Task soleur:product:business-validator(feature_description)` -- agent returns the first gate question
   2. Relay the question to the user via **AskUserQuestion**
   3. Invoke `Task soleur:product:business-validator(prior_gate_results + user_answer)` -- agent returns next gate question
   4. Repeat until all 6 gates complete and the vision alignment check runs
   5. Final invocation writes the validation report to `knowledge-base/product/business-validation.md` inside the worktree

5. **Commit and push workshop artifacts:**

   ```bash
   git add knowledge-base/product/business-validation.md
   git commit -m "docs: capture validation report"
   git push
   ```

   If the push fails, print a warning but continue.

6. **Display completion message and STOP.** Do NOT proceed to Phase 1. Do NOT run Phase 2 or Phase 3.5. Display:

   ```text
   Validation workshop complete!

   Document: none (validation workshop)
   Validation report: knowledge-base/product/business-validation.md
   Issue: #N (using existing) | #N (created)
   Branch: feat-<name> (if worktree created)
   Working directory: .worktrees/feat-<name>/ (if worktree created)

   Next: Review the validation report. If verdict is GO, run soleur:plan to start building.
   ```

   End brainstorm execution after displaying this message.
