---
feature: slack-release-notify
lane: cross-domain
brand_survival_threshold: none
plan: knowledge-base/project/plans/2026-06-09-feat-move-release-notifications-discord-to-slack-plan.md
issue: 5079
created: 2026-06-09
---

# Tasks: Move Release Notifications from Discord to Slack

## Phase 1 — Workflow swap (inline Slack step)

- [x] 1.1 In `.github/workflows/reusable-release.yml`, delete the "Post to Discord (release)" step (lines 653–707).
- [x] 1.2 Add an inline "Post to Slack (release)" step under the same `if:` condition with `continue-on-error: true` (env: `SLACK_RELEASES_WEBHOOK_URL`, `TAG`, `VERSION`, `COMPONENT_DISPLAY`, `RELEASE_NOTES_FILE`).
- [x] 1.3 Step body: webhook-empty guard (`exit 0`) → `::add-mask::` → read notes file (`BODY=""` if missing) → build `*bold*` mrkdwn message → `jq -n --arg text … '{text:$text, unfurl_links:false}'` → `curl --max-time 15` → HTTP-2xx check with `::warning::` on non-2xx. No `username`/`icon_url`; no truncation.
- [x] 1.4 Confirm the "Email notification (release)" step is untouched.

## Phase 2 — Secret scanning

- [x] 2.1 Add `[[rules]] id = "slack-webhook-url"` to `.gitleaks.toml` adjacent to the Discord rule: regex `https://hooks\.slack\.com/services/T[A-Z0-9]+/[A-Z0-9]+/[A-Za-z0-9]{24,}` (2nd segment `[A-Z0-9]+`, NOT `/B`), keyword `hooks.slack.com/services`, tags `["webhook","slack"]`. *(As shipped: secret segment widened to `[A-Za-z0-9_-]{24,}` in 5ab594f35; rule renamed `soleur-slack-webhook-url` at review — the default pack ships a same-id rule that the original name silently shadowed, dropping `/workflows/` detection. Pinned by `plugins/soleur/test/gitleaks-rules.test.sh`.)*
- [x] 2.2 Copy the Discord rule's `[[rules.allowlists]] paths` list verbatim into the Slack rule.

## Phase 3 — Forward-looking doc cleanup

- [x] 3.1 `plugins/soleur/AGENTS.md:11` — "posts to Discord" → "posts to Slack".
- [x] 3.2 `plugins/soleur/skills/release-announce/SKILL.md` lines 3 (`description:`), 10, 47 — Discord → Slack (line 47 secret name → `SLACK_RELEASES_WEBHOOK_URL`).
- [x] 3.3 `plugins/soleur/skills/ship/SKILL.md:1414` — "posts to Discord" → "posts to Slack".
- [x] 3.4 Leave `2026-02-19-discord-bot-identity-and-webhook-behavior.md` (historical) unchanged.

## Phase 3.5 — Test update (orphan suite caught at exit gate)

- [x] 3.5 `plugins/soleur/test/reusable-release-idempotency.test.sh` T6 — assert "Post to Slack (release)" notifies on self-heal (was "Post to Discord"). 11/11 pass.

## Phase 4 — Verification (pre-merge)

- [x] 4.1 `shellcheck` the extracted `run:` script passes (AC1).
- [x] 4.2 No "Post to Discord" step remains; Slack post present (AC2).
- [x] 4.3 gitleaks flags both a canonical Slack URL AND a non-`B`-2nd-segment fixture (AC4).
- [x] 4.4 No residual "discord" in the 3 edited forward-looking docs (AC5).
- [x] 4.5 `actionlint` clean on the Slack step (pre-existing SC2129/SC2012 nits in untouched steps are out of scope, AC6).

## Phase 5 — Operator (PRE-merge, gated) & post-merge

- [x] 5.1 ~~(operator)~~ Create the Slack app "Sol" (set name + icon in Display Information) → enable Incoming Webhooks → add to the release channel → copy URL. *(Done autonomously via Playwright MCP 2026-06-10: app A0B9G5EBCP5 "Sol" in Soleur.ai, icon uploaded, #releases channel created (C0B9G7NA93M), webhook installed via OAuth Allow.)*
- [x] 5.2 ~~(operator)~~ `gh secret set SLACK_RELEASES_WEBHOOK_URL` (paste at prompt; never `--body`/`!`). *(Done: URL extracted browser→file, shape-validated, piped to `gh secret set` via stdin, files shredded — never entered conversation or shell history.)*
- [x] 5.3 **MERGE GATE (AC7):** `gh secret list | grep SLACK_RELEASES_WEBHOOK_URL` returns the secret before `gh pr merge`. *(Verified 2026-06-10; webhook smoke test to #releases returned `ok`.)*
- [ ] 5.4 (post-merge, AC8) First release posts to Slack — verify via `gh run view <id> --log | grep 'Slack notification'`.
- [ ] 5.5 (post-merge, AC10) `gh issue close 5079`.
- [ ] 5.6 (post-merge, after 5.4 confirms) Delete the orphaned Discord release secrets — no workflow consumes them after this PR: `gh secret delete DISCORD_RELEASES_WEBHOOK_URL` and revoke the webhook in Discord. (`DISCORD_WEBHOOK_URL` stays — community crons still use it, NG2/#5080.)
