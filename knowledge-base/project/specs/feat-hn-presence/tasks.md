# Tasks: feat-hn-presence

- [ ] 1. Create `plugins/soleur/skills/community/scripts/hn-community.sh` — 3 subcommands (`mentions`, `trending`, `thread`) wrapping HN Algolia API. Follow `github-community.sh` structure (always-enabled, no auth) with 429 retry from discord/x pattern. `mentions` uses `/search_by_date` for stories+comments, default 20 hits. `trending` fetches all `front_page` stories (no client-side keyword filtering — agent filters). `thread` fetches `/items/<id>`, validates numeric ID. Use `curl --data-urlencode` for query params. Include `BASH_SOURCE` guard. `chmod +x`.
- [ ] 2. Update `plugins/soleur/skills/community/SKILL.md` — add HN to description (frontmatter + body text), platform detection table (always-enabled, no env vars), scripts list (markdown link), platforms sub-command output, important guidelines.
- [ ] 3. Update `plugins/soleur/agents/support/community-manager.md` — add HN to description (frontmatter + body text line 7), prerequisites (new always-enabled subsection), Capability 1 data collection + analysis, digest heading contract table (`## Hacker News Activity`, optional), scripts list (backtick format), important guidelines. Also update platform-enumerating prose at lines 47 and 101.
- [ ] 4. Update `.github/workflows/scheduled-community-monitor.yml` — add HN data collection commands to prompt (after GitHub section). No secrets needed. Include "If hn-community.sh fails, log the error and continue."
- [ ] 5. Add `### Hacker News` channel notes to `knowledge-base/marketing/brand-guide.md` — understated technical tone, no marketing speak, show-don't-tell, no emojis. Two examples (story title, comment reply).
- [ ] 6. Smoke test: run all 3 subcommands + invalid ID + zero-result query. Verify JSON output.
- [ ] 7. Compound and commit.
