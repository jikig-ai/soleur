# Validation Workshop (if selected)

<!-- Follows brand-architect workshop pattern: worktree, issue, hand off, STOP. See constitution for the workshop archetype. -->

1. **Create worktree:**
   - Derive feature name: use the first 2-3 descriptive words from the feature description in kebab-case (e.g., "validate my SaaS idea" -> `validate-saas`). If the description is fewer than 3 words, default to `business-validation`.
   - Run `./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh feature <name>`
   - Set `WORKTREE_PATH`

2. **Handle issue:**
   - Parse feature_description for existing issue reference (`#N` pattern)
   - If found: validate issue state with `gh issue view`. If OPEN, use it. If CLOSED or not found, create a new one.
   - If not found: create a new issue with `gh issue create --title "feat: <Topic>" --body "..."`
   - Update the issue body with artifact links (validation report path, branch name)
   - Do NOT generate spec.md -- validation workshops produce a validation report, not a spec

3. **Navigate to worktree:**

   Run `cd` to the worktree path from step 1 (e.g., `.worktrees/feat-<name>`), then run `pwd` to verify the path shows `.worktrees/feat-<name>`.

4. **Hand off to business-validator:**

   The business-validator is an interactive workshop agent with sequential gates. Since Task subagents cannot prompt the user directly, relay each gate manually:

   1. Invoke `Task business-validator(feature_description)` -- agent returns the first gate question
   2. Relay the question to the user via **AskUserQuestion**
   3. Invoke `Task business-validator(prior_gate_results + user_answer)` -- agent returns next gate question
   4. Repeat until all 6 gates complete and the vision alignment check runs
   5. Final invocation writes the validation report to `knowledge-base/overview/business-validation.md` inside the worktree

5. **Display completion message and STOP.** Do NOT proceed to Phase 1. Do NOT run Phase 2 or Phase 3.5. Display:

   ```text
   Validation workshop complete!

   Document: none (validation workshop)
   Validation report: knowledge-base/overview/business-validation.md
   Issue: #N (using existing) | #N (created)
   Branch: feat-<name> (if worktree created)
   Working directory: .worktrees/feat-<name>/ (if worktree created)

   Next: Review the validation report. If verdict is GO, run /soleur:plan to start building.
   ```

   End brainstorm execution after displaying this message.
