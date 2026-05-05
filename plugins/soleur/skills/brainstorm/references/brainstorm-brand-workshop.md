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

   **0. Pre-flight: enforce headless Pencil MCP (HARD GATE):**

   Agent-driven mockup runs MUST use the headless Pencil CLI adapter. IDE mode (VS Code / Cursor extension) and Desktop mode buffer `.pen` edits in editor memory and do not flush to disk without manual Ctrl+S — `mcp__pencil__export_nodes` reads from disk and returns `you are probably referencing the wrong .pen file` while the doc is unsaved, so the workshop's PNG export, git diff, and review trail all break. Headless CLI auto-calls `save()` after every mutating op (see `plugins/soleur/skills/pencil-setup/SKILL.md` §"No programmatic save (Desktop/IDE only)").

   ```bash
   pencil_mode=""
   pencil_listing=$(claude mcp list 2>&1 | grep pencil || true)
   case "$pencil_listing" in
     *pencil-mcp-adapter*|*@pencil.dev/cli*|*pencil-cli*) pencil_mode=headless_cli ;;
     *visual_studio_code*|*cursor*)                       pencil_mode=ide ;;
     *--app\ pencil*|*mcp-server*)                        pencil_mode=desktop ;;
     "")                                                  pencil_mode=unregistered ;;
     *)                                                   pencil_mode=unknown ;;
   esac

   if [[ "$pencil_mode" != "headless_cli" ]]; then
     echo "BLOCKED: Pencil MCP mode is '$pencil_mode'; brand-workshop step 4.5 requires headless_cli."
     echo "Run: bash ./plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --auto"
     echo "Then restart Claude Code and resume from this step."
     exit 1
   fi
   ```

   If the gate exits non-zero, run pencil-setup with `--auto`, then provide the founder a copy-pasteable resume prompt (per `cm-when-proposing-to-clear-context-or` in AGENTS.md) for a fresh session that picks up at step 4.5. Do NOT proceed to step 4.5.a in IDE/Desktop mode — the rendered mockup will exist only in editor memory and the PNG export will fail.

   a. **Hand off to ux-design-lead** with the new tokens, the existing palette (for paired comparison), and a target surface set:

      ```
      Task ux-design-lead("Render representative mockups applying <new tokens> to: primary button (default/hover/disabled), card surface with text hierarchy, form input (default/focus/error), navigation bar, modal/dialog, and one error state. If both light and dark palettes exist, render both side-by-side. Output is a .pen file in knowledge-base/product/design/brand/<topic>-<YYYY-MM-DD>/ produced via Pencil MCP in headless mode — IDE/Desktop modes are blocked by step 4.5.0. Pencil is the founder's standard design surface and is the required primary path. The agent must NOT fall back to Playwright/HTML mockups; if the headless adapter fails mid-run, halt and surface the error to the founder.")
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
   Mockups: knowledge-base/product/design/brand/<topic>-<YYYY-MM-DD>/ (if Visual Direction changed)
   Founder approval: <date> on mockup set <path> (if Visual Direction changed)
   Issue: #N (using existing) | #N (created)
   Branch: feat-<name> (if worktree created)
   Working directory: .worktrees/feat-<name>/ (if worktree created)

   Next: The brand guide is now available for discord-content and other marketing skills.
   ```

   End brainstorm execution after displaying this message.
