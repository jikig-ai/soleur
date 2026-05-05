# Brand Workshop (if selected)

1. **Create worktree:**
   - Derive feature name: use the first 2-3 descriptive words from the feature description in kebab-case (e.g., "define our brand identity" -> `brand-identity`). If the description is fewer than 3 words, default to `brand-guide`.
   - Run `./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh feature <name>`
   - Set `WORKTREE_PATH`

2. **Handle issue:**
   - Parse feature_description for existing issue reference (`#N` pattern)
   - If found: validate issue state with `gh issue view`. If OPEN, use it. If CLOSED or not found, create a new one.
   - If not found: create a new issue with `gh issue create --title "feat: <Topic>" --milestone "Post-MVP / Later" --body "..."`. After creation, read `knowledge-base/product/roadmap.md` and update the milestone if a more specific phase applies.
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

   The brand-architect agent runs its full interactive workshop and writes the brand guide to `knowledge-base/marketing/brand-guide.md` inside the worktree.

4.5. **Visual mockup gate (mandatory if Visual Direction changed):**

   After brand-architect returns, detect whether the `## Visual Direction` section was modified:

   ```bash
   git diff main...HEAD -- knowledge-base/marketing/brand-guide.md \
     | grep -E '^[+-].*(##? Visual Direction|Color Palette|Typography|Imagery|--bg-|--text-|--border-|--accent-|#[0-9A-Fa-f]{6}|oklch\()' \
     | head -1
   ```

   If the grep returns any line, OR if the brand-architect's status mentions palette/typography/imagery changes, the gate is REQUIRED. Hex values and oklch tokens are not founder-approvable in markdown — they must be seen rendered on representative app surfaces.

   a. **Hand off to ux-design-lead** with the new tokens, the existing palette (for paired comparison), and a target surface set:

      ```
      Task ux-design-lead("Render representative mockups applying <new tokens> to: primary button (default/hover/disabled), card surface with text hierarchy, form input (default/focus/error), navigation bar, modal/dialog, and one error state. If both light and dark palettes exist, render both side-by-side. Output: .pen file or screenshots in knowledge-base/marketing/brand-mockups/<topic>-<YYYY-MM-DD>/. If Pencil MCP is unavailable, fall back to a Playwright-rendered HTML mockup screenshotted at 1440×900.")
      ```

   b. **Surface mockups to the founder** via AskUserQuestion with options: `Approve`, `Request changes`, `Reject`. Include the mockup file paths in the question body so the founder can open them.

   c. **If "Request changes":** capture the founder's feedback verbatim, hand back to brand-architect with the feedback, then re-run step 4.5 (mockup → review). Maximum 3 iterations before pausing for a fresh-context resume.

   d. **If "Reject":** close the draft PR with the rejection reason, file a `blocked` issue capturing the founder's veto, do NOT commit the brand-guide changes, then exit.

   e. **Only "Approve" continues to step 5.** Capture the approving message in the commit body so the audit trail names the founder, the date, and the mockup path that was approved.

   **Why:** abstract hex values are not a brand decision — the founder approves what they see, not numbers in markdown. Triggered by the 2026-05-05 Solar Radiance session: brand-architect produced approved-looking tokens with WCAG verification; the founder caught the missing mockup gate at PR-ready time, after the worktree, draft PR, and tracking issues had already been processed. See `knowledge-base/project/learnings/best-practices/2026-05-05-brand-workshop-needs-ux-mockup-gate.md`.

5. **Commit and push workshop artifacts:**

   ```bash
   git add knowledge-base/marketing/brand-guide.md
   git commit -m "docs: capture brand guide"
   git push
   ```

   If the push fails, print a warning but continue.

6. **Display completion message and STOP.** Do NOT proceed to Phase 1. Do NOT run Phase 2 or Phase 3.5. Display:

   ```text
   Brand workshop complete!

   Document: none (brand workshop)
   Brand guide: knowledge-base/marketing/brand-guide.md
   Mockups: knowledge-base/marketing/brand-mockups/<topic>-<YYYY-MM-DD>/ (if Visual Direction changed)
   Founder approval: <date> on mockup set <path> (if Visual Direction changed)
   Issue: #N (using existing) | #N (created)
   Branch: feat-<name> (if worktree created)
   Working directory: .worktrees/feat-<name>/ (if worktree created)

   Next: The brand guide is now available for discord-content and other marketing skills.
   ```

   End brainstorm execution after displaying this message.
