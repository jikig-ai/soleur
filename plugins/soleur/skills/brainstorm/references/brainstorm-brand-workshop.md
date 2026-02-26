# Brand Workshop (if selected)

1. **Create worktree:**
   - Derive feature name: use the first 2-3 descriptive words from the feature description in kebab-case (e.g., "define our brand identity" -> `brand-identity`). If the description is fewer than 3 words, default to `brand-guide`.
   - Run `./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh feature <name>`
   - Set `WORKTREE_PATH`

2. **Handle issue:**
   - Parse feature_description for existing issue reference (`#N` pattern)
   - If found: validate issue state with `gh issue view`. If OPEN, use it. If CLOSED or not found, create a new one.
   - If not found: create a new issue with `gh issue create --title "feat: <Topic>" --body "..."`
   - Update the issue body with artifact links (brand guide path, branch name)
   - Do NOT generate spec.md -- brand workshops produce a brand guide, not a spec

3. **Navigate to worktree and create draft PR:**

   Run `cd` to the worktree path from step 1 (e.g., `.worktrees/feat-<name>`), then run `pwd` to verify the path shows `.worktrees/feat-<name>`.

   After verifying the path, create a draft PR:

   ```bash
   bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh draft-pr
   ```

   If this fails (no network), print a warning but continue.

4. **Hand off to brand-architect:**

   ```
   Task brand-architect(feature_description)
   ```

   The brand-architect agent runs its full interactive workshop and writes the brand guide to `knowledge-base/overview/brand-guide.md` inside the worktree.

5. **Commit and push workshop artifacts:**

   ```bash
   git add knowledge-base/overview/brand-guide.md
   git commit -m "docs: capture brand guide"
   git push
   ```

   If the push fails, print a warning but continue.

6. **Display completion message and STOP.** Do NOT proceed to Phase 1. Do NOT run Phase 2 or Phase 3.5. Display:

   ```text
   Brand workshop complete!

   Document: none (brand workshop)
   Brand guide: knowledge-base/overview/brand-guide.md
   Issue: #N (using existing) | #N (created)
   Branch: feat-<name> (if worktree created)
   Working directory: .worktrees/feat-<name>/ (if worktree created)

   Next: The brand guide is now available for discord-content and other marketing skills.
   ```

   End brainstorm execution after displaying this message.
