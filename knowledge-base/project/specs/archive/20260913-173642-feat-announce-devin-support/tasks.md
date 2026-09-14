# Tasks — feat-announce-devin-support

Derived from `knowledge-base/project/plans/2026-09-13-feat-announce-devin-support-plan.md`.
Carrier PR: #8121 (draft) on branch `feat-announce-devin-support`.

## Phase 1 — Author the distribution file

- 1.1. Create `knowledge-base/marketing/distribution-content/2026-09-13-devin-cli-harness-support.md` with frontmatter: `title` (non-empty, quoted), `type: feature-launch`, `publish_date: 2026-09-14`, `channels: x, bluesky`, `status: scheduled`, `pr_reference: "#8083"`; include the `<!-- To publish: set BOTH publish_date AND status: scheduled -->` comment from precedent.
- 1.2. Write `## X/Twitter Thread` in numbered format — hook paragraph un-prefixed, then `2/ ` and `3/ ` tweets on fresh lines. Beats: (a) Devin CLI is the fourth supported harness alongside Claude Code / Grok Build / Codex, `/soleur:go` runs the matching skill in-session; (b) install via `devin plugins install jikig-ai/soleur#plugins/soleur -y` and the three native slash commands; (c) `.devin-plugin/plugin.json` + session-start-hook parity with Codex/Grok and `devin plugins update soleur`.
- 1.3. Write `## Bluesky` — one paragraph, no hashtags, covering fourth-harness + install + update.
- 1.4. Keep every claim within the plan's "Verified copy claims" list; no `{{`, `}}`, `{%`, `%}` in the body.

## Phase 2 — Validate and commit

- 2.1. Per-tweet `wc -m` ≤ 280; Bluesky body `wc -m` ≤ 300.
- 2.2. `bash scripts/lint-distribution-content.sh knowledge-base/marketing/distribution-content/2026-09-13-devin-cli-harness-support.md` → exit 0.
- 2.3. Re-run the publisher's `extract_section`/`extract_tweets` awk against the file; confirm the extracted tweet count equals the authored count (not 1).
- 2.4. Verify `publish_date` is strictly `> $(date -u +%F)` at ship time; if not, bump to the next day.
- 2.5. Verify no pre-existing Devin announcement on main: `git log origin/main --oneline -- knowledge-base/marketing/distribution-content/` shows no Devin announce file.
- 2.6. Commit the file on `feat-announce-devin-support`; PR #8121 carries it.
