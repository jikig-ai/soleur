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

- [ ] 1.1 In `.github/workflows/reusable-release.yml`, delete the "Post to Discord (release)" step (lines 653–707).
- [ ] 1.2 Add an inline "Post to Slack (release)" step under the same `if:` condition with `continue-on-error: true` (env: `SLACK_RELEASES_WEBHOOK_URL`, `TAG`, `VERSION`, `COMPONENT_DISPLAY`, `RELEASE_NOTES_FILE`).
- [ ] 1.3 Step body: webhook-empty guard (`exit 0`) → `::add-mask::` → read notes file (`BODY=""` if missing) → build `*bold*` mrkdwn message → `jq -n --arg text … '{text:$text, unfurl_links:false}'` → `curl --max-time 15` → HTTP-2xx check with `::warning::` on non-2xx. No `username`/`icon_url`; no truncation.
- [ ] 1.4 Confirm the "Email notification (release)" step is untouched.

## Phase 2 — Secret scanning

- [ ] 2.1 Add `[[rules]] id = "slack-webhook-url"` to `.gitleaks.toml` adjacent to the Discord rule: regex `https://hooks\.slack\.com/services/T[A-Z0-9]+/[A-Z0-9]+/[A-Za-z0-9]{24,}` (2nd segment `[A-Z0-9]+`, NOT `/B`), keyword `hooks.slack.com/services`, tags `["webhook","slack"]`.
- [ ] 2.2 Copy the Discord rule's `[[rules.allowlists]] paths` list verbatim into the Slack rule.

## Phase 3 — Forward-looking doc cleanup

- [ ] 3.1 `plugins/soleur/AGENTS.md:11` — "posts to Discord" → "posts to Slack".
- [ ] 3.2 `plugins/soleur/skills/release-announce/SKILL.md` lines 3 (`description:`), 10, 47 — Discord → Slack.
- [ ] 3.3 `plugins/soleur/skills/ship/SKILL.md:1414` — "posts to Discord" → "posts to Slack".
- [ ] 3.4 Leave `2026-02-19-discord-bot-identity-and-webhook-behavior.md` (historical) unchanged.

## Phase 4 — Verification (pre-merge)

- [ ] 4.1 `shellcheck` the extracted `run:` script passes (AC1).
- [ ] 4.2 `grep -c "hooks.slack.com\|SLACK_RELEASES_WEBHOOK_URL" reusable-release.yml` ≥ 1; no "Post to Discord" step remains (AC2).
- [ ] 4.3 gitleaks flags both a canonical Slack URL fixture AND a non-`B`-2nd-segment fixture (AC4).
- [ ] 4.4 `grep -ri "discord" <edited docs>` returns only the out-of-scope historical learning (AC5).
- [ ] 4.5 `actionlint .github/workflows/reusable-release.yml` passes (AC6).

## Phase 5 — Operator (PRE-merge, gated) & post-merge

- [ ] 5.1 (operator) Create the Slack app "Sol" (set name + icon in Display Information) → enable Incoming Webhooks → add to the release channel → copy URL.
- [ ] 5.2 (operator) `gh secret set SLACK_RELEASES_WEBHOOK_URL` (paste at prompt; never `--body`/`!`).
- [ ] 5.3 **MERGE GATE (AC7):** `gh secret list | grep SLACK_RELEASES_WEBHOOK_URL` returns the secret before `gh pr merge`.
- [ ] 5.4 (post-merge, AC8) First release posts to Slack — verify via `gh run view <id> --log | grep 'Slack notification'`.
- [ ] 5.5 (post-merge, AC10) `gh issue close 5079`.
